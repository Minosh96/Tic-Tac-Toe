import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../domain/models/social_models.dart';

/// Peer-to-peer WebRTC Voice Call manager backed by Cloud Firestore signaling,
/// native Android mic permissions, STUN+TURN NAT traversal, and properly ordered
/// local + remote ICE candidate buffering.
class VoiceCallRepository {
  VoiceCallRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    String? databaseId,
  })  : _db = firestore ??
            (databaseId != null
                ? FirebaseFirestore.instanceFor(
                    app: Firebase.app(),
                    databaseId: databaseId,
                  )
                : FirebaseFirestore.instance),
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  static const MethodChannel _audioChannel = MethodChannel('melow/audio_call');

  /// STUN + OpenRelay TURN servers (UDP 80/443 + TCP 443) for carrier NAT & Wi-Fi traversal.
  static const Map<String, dynamic> _rtcConfig = {
    'sdpSemantics': 'unified-plan',
    'iceCandidatePoolSize': 10,
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      {'urls': 'stun:openrelay.metered.ca:80'},
      {
        'urls': 'turn:openrelay.metered.ca:80',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
      {
        'urls': 'turn:openrelay.metered.ca:443',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
      {
        'urls': 'turn:openrelay.metered.ca:443?transport=tcp',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
    ],
  };

  static const Map<String, dynamic> _audioConstraints = {
    'audio': {
      'echoCancellation': true,
      'noiseSuppression': true,
      'autoGainControl': true,
    },
    'video': false,
  };

  String get currentUid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Not signed in');
    return uid;
  }

  Stream<List<VoiceCallSession>> watchIncomingCalls(String uid) {
    return _db
        .collection('calls')
        .where('calleeUid', isEqualTo: uid)
        .snapshots()
        .map((snap) {
      final now = DateTime.now();
      return snap.docs
          .map(VoiceCallSession.fromFirestore)
          .where((c) =>
              c.isRinging &&
              (c.createdAt == null ||
                  now.difference(c.createdAt!).inMinutes < 3))
          .toList(growable: false);
    });
  }

  Stream<VoiceCallSession?> watchCall(String callId) {
    return _db.collection('calls').doc(callId).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return VoiceCallSession.fromFirestore(snap);
    });
  }

  Future<void> _requestNativeMicPermission() async {
    try {
      final granted = await _audioChannel
          .invokeMethod<bool>('requestMicrophonePermission');
      if (granted != true) {
        throw Exception(
          'Microphone permission denied. Please allow Microphone access for Melow Tic Tac Toe in Android Settings.',
        );
      }
    } on MissingPluginException {
      // Non-Android / test fallback.
    }
  }

  Future<void> _configureAndroidAudio({
    required bool enabled,
    bool speaker = true,
  }) async {
    try {
      if (enabled) {
        await Helper.setAndroidAudioConfiguration(
          AndroidAudioConfiguration.communication,
        );
      }
      await Helper.setSpeakerphoneOn(enabled && speaker);
    } catch (_) {}
    try {
      await _audioChannel.invokeMethod('setCommunicationAudio', {
        'enabled': enabled,
        'speaker': speaker,
      });
    } catch (_) {}
  }

  Future<MediaStream> _openMicrophoneStream() async {
    await _requestNativeMicPermission();
    await _configureAndroidAudio(enabled: true, speaker: true);
    try {
      final stream = await navigator.mediaDevices.getUserMedia(_audioConstraints);
      for (final track in stream.getAudioTracks()) {
        track.enabled = true;
      }
      return stream;
    } catch (_) {
      await _configureAndroidAudio(enabled: false);
      throw Exception(
        'Could not access microphone. Please check Android Microphone permission.',
      );
    }
  }

  void _attachRemoteAudioHandlers(
    RTCPeerConnection pc,
    RTCVideoRenderer remoteRenderer,
    ValueNotifier<String> audioState,
  ) {
    pc.onTrack = (RTCTrackEvent event) async {
      if (event.streams.isNotEmpty) {
        remoteRenderer.srcObject = event.streams.first;
      }
      if (event.track.kind == 'audio') {
        event.track.enabled = true;
        try {
          await Helper.setVolume(1.0, event.track);
        } catch (_) {}
      }
    };

    pc.onAddStream = (MediaStream stream) async {
      remoteRenderer.srcObject = stream;
      for (final track in stream.getAudioTracks()) {
        track.enabled = true;
        try {
          await Helper.setVolume(1.0, track);
        } catch (_) {}
      }
    };

    pc.onConnectionState = (RTCPeerConnectionState state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        audioState.value = 'Connected';
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        audioState.value = 'Audio connection failed';
      }
    };

    pc.onIceConnectionState = (RTCIceConnectionState state) {
      switch (state) {
        case RTCIceConnectionState.RTCIceConnectionStateConnected:
        case RTCIceConnectionState.RTCIceConnectionStateCompleted:
          audioState.value = 'Connected';
          break;
        case RTCIceConnectionState.RTCIceConnectionStateChecking:
          if (audioState.value != 'Connected') {
            audioState.value = 'Connecting audio…';
          }
          break;
        case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
          audioState.value = 'Reconnecting…';
          break;
        case RTCIceConnectionState.RTCIceConnectionStateFailed:
          audioState.value = 'Audio connection failed';
          break;
        default:
          break;
      }
    };
  }

  /// Creates an outgoing WebRTC audio call.
  /// CRITICAL: Buffers local ICE candidates until `calls/{callId}` is created in
  /// Firestore so security rules (`exists(calls/{callId})`) never reject them!
  Future<ActiveVoiceCall> startVoiceCall({
    required String calleeUid,
    required String calleeName,
    required String callerName,
    required String callerAvatar,
    String? roomId,
  }) async {
    final callerUid = currentUid;
    final localStream = await _openMicrophoneStream();
    final remoteRenderer = RTCVideoRenderer();
    await remoteRenderer.initialize();

    final audioState = ValueNotifier<String>('Ringing $calleeName…');
    final pc = await createPeerConnection(_rtcConfig);
    _attachRemoteAudioHandlers(pc, remoteRenderer, audioState);

    for (final track in localStream.getAudioTracks()) {
      await pc.addTrack(track, localStream);
    }

    final callRef = _db.collection('calls').doc();
    final offerCandidates = callRef.collection('offerCandidates');
    final answerCandidates = callRef.collection('answerCandidates');

    // Buffer local ICE candidates until parent `calls/{callId}` exists in Firestore!
    bool callDocCreated = false;
    final pendingLocalCandidates = <Map<String, dynamic>>[];

    Future<void> writeLocalCandidate(Map<String, dynamic> payload) async {
      try {
        await offerCandidates.add(payload);
      } catch (_) {}
    }

    pc.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate == null || candidate.candidate!.isEmpty) return;
      final payload = <String, dynamic>{
        'candidate': candidate.candidate!,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      };
      if (callDocCreated) {
        writeLocalCandidate(payload);
      } else {
        pendingLocalCandidates.add(payload);
      }
    };

    final offer = await pc.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': false,
    });
    await pc.setLocalDescription(offer);

    // Create parent `calls/{callId}` FIRST before flushing any offerCandidates!
    await callRef.set({
      'callerUid': callerUid,
      'calleeUid': calleeUid,
      'callerName': callerName,
      'callerAvatar': callerAvatar,
      'calleeName': calleeName,
      if (roomId != null && roomId.isNotEmpty) 'roomId': roomId,
      'status': 'ringing',
      'offer': {'sdp': offer.sdp, 'type': offer.type},
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    callDocCreated = true;
    final toFlush = List<Map<String, dynamic>>.from(pendingLocalCandidates);
    pendingLocalCandidates.clear();
    for (final payload in toFlush) {
      await writeLocalCandidate(payload);
    }

    final subs = <StreamSubscription<dynamic>>[];
    bool remoteSet = false;
    final pendingRemoteCandidates = <RTCIceCandidate>[];
    final seenAnswerCandidateIds = <String>{};

    subs.add(
      callRef.snapshots().listen((snap) async {
        final data = snap.data();
        if (data == null) return;
        final answer = data['answer'];
        if (!remoteSet && answer is Map<String, dynamic>) {
          remoteSet = true;
          if (audioState.value != 'Connected') {
            audioState.value = 'Connecting audio…';
          }
          try {
            await pc.setRemoteDescription(
              RTCSessionDescription(
                answer['sdp'] as String?,
                answer['type'] as String?,
              ),
            );
            for (final cand in pendingRemoteCandidates) {
              try {
                await pc.addCandidate(cand);
              } catch (_) {}
            }
            pendingRemoteCandidates.clear();
          } catch (_) {}
        }
      }),
    );

    subs.add(
      answerCandidates.snapshots().listen((snap) async {
        for (final doc in snap.docs) {
          if (!seenAnswerCandidateIds.add(doc.id)) continue;
          final d = doc.data();
          if (d['candidate'] is String && (d['candidate'] as String).isNotEmpty) {
            final cand = RTCIceCandidate(
              d['candidate'] as String,
              d['sdpMid'] as String?,
              (d['sdpMLineIndex'] as num?)?.toInt(),
            );
            if (remoteSet) {
              try {
                await pc.addCandidate(cand);
              } catch (_) {}
            } else {
              pendingRemoteCandidates.add(cand);
            }
          }
        }
      }),
    );

    return ActiveVoiceCall(
      callId: callRef.id,
      peerConnection: pc,
      localStream: localStream,
      remoteRenderer: remoteRenderer,
      audioState: audioState,
      subscriptions: subs,
      onEndRemote: () => updateCallStatus(callRef.id, 'ended'),
      onRestoreAudio: () => _configureAndroidAudio(enabled: false),
      onSetSpeaker: (speaker) async {
        try {
          await Helper.setSpeakerphoneOn(speaker);
        } catch (_) {}
        try {
          await _audioChannel
              .invokeMethod('setSpeakerphone', {'speaker': speaker});
        } catch (_) {}
      },
    );
  }

  /// Answers an incoming ringing voice call with properly ordered SDP + ICE exchange.
  Future<ActiveVoiceCall> answerVoiceCall(VoiceCallSession session) async {
    final offer = session.offer;
    if (offer == null) {
      throw Exception('Call offer is no longer available.');
    }

    final localStream = await _openMicrophoneStream();
    final remoteRenderer = RTCVideoRenderer();
    await remoteRenderer.initialize();

    final audioState = ValueNotifier<String>('Connecting audio…');
    final pc = await createPeerConnection(_rtcConfig);
    _attachRemoteAudioHandlers(pc, remoteRenderer, audioState);

    for (final track in localStream.getAudioTracks()) {
      await pc.addTrack(track, localStream);
    }

    final callRef = _db.collection('calls').doc(session.callId);
    final offerCandidates = callRef.collection('offerCandidates');
    final answerCandidates = callRef.collection('answerCandidates');

    bool answerPublished = false;
    final pendingLocalCandidates = <Map<String, dynamic>>[];

    Future<void> writeLocalCandidate(Map<String, dynamic> payload) async {
      try {
        await answerCandidates.add(payload);
      } catch (_) {}
    }

    pc.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate == null || candidate.candidate!.isEmpty) return;
      final payload = <String, dynamic>{
        'candidate': candidate.candidate!,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      };
      if (answerPublished) {
        writeLocalCandidate(payload);
      } else {
        pendingLocalCandidates.add(payload);
      }
    };

    await pc.setRemoteDescription(
      RTCSessionDescription(
        offer['sdp'] as String?,
        offer['type'] as String?,
      ),
    );
    final answer = await pc.createAnswer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': false,
    });
    await pc.setLocalDescription(answer);

    await callRef.update({
      'status': 'active',
      'answer': {'sdp': answer.sdp, 'type': answer.type},
      'updatedAt': FieldValue.serverTimestamp(),
    });

    answerPublished = true;
    final toFlush = List<Map<String, dynamic>>.from(pendingLocalCandidates);
    pendingLocalCandidates.clear();
    for (final payload in toFlush) {
      await writeLocalCandidate(payload);
    }

    final seenOfferCandidateIds = <String>{};
    final subs = <StreamSubscription<dynamic>>[];
    subs.add(
      offerCandidates.snapshots().listen((snap) async {
        for (final doc in snap.docs) {
          if (!seenOfferCandidateIds.add(doc.id)) continue;
          final d = doc.data();
          if (d['candidate'] is String && (d['candidate'] as String).isNotEmpty) {
            try {
              await pc.addCandidate(
                RTCIceCandidate(
                  d['candidate'] as String,
                  d['sdpMid'] as String?,
                  (d['sdpMLineIndex'] as num?)?.toInt(),
                ),
              );
            } catch (_) {}
          }
        }
      }),
    );

    return ActiveVoiceCall(
      callId: session.callId,
      peerConnection: pc,
      localStream: localStream,
      remoteRenderer: remoteRenderer,
      audioState: audioState,
      subscriptions: subs,
      onEndRemote: () => updateCallStatus(session.callId, 'ended'),
      onRestoreAudio: () => _configureAndroidAudio(enabled: false),
      onSetSpeaker: (speaker) async {
        try {
          await Helper.setSpeakerphoneOn(speaker);
        } catch (_) {}
        try {
          await _audioChannel
              .invokeMethod('setSpeakerphone', {'speaker': speaker});
        } catch (_) {}
      },
    );
  }

  Future<void> declineCall(String callId) => updateCallStatus(callId, 'declined');

  Future<void> updateCallStatus(String callId, String status) async {
    try {
      await _db.collection('calls').doc(callId).update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }
}

/// Active WebRTC audio handle with mute, speakerphone, remote audio sink & cleanup.
class ActiveVoiceCall {
  ActiveVoiceCall({
    required this.callId,
    required this.peerConnection,
    required this.localStream,
    required this.remoteRenderer,
    required this.audioState,
    required this.subscriptions,
    required this.onEndRemote,
    required this.onRestoreAudio,
    required this.onSetSpeaker,
  });

  final String callId;
  final RTCPeerConnection peerConnection;
  final MediaStream localStream;
  final RTCVideoRenderer remoteRenderer;
  final ValueNotifier<String> audioState;
  final List<StreamSubscription<dynamic>> subscriptions;
  final Future<void> Function() onEndRemote;
  final Future<void> Function() onRestoreAudio;
  final Future<void> Function(bool speaker) onSetSpeaker;

  bool _muted = false;
  bool _speakerOn = true;
  bool _disposed = false;

  bool get muted => _muted;
  bool get speakerOn => _speakerOn;

  void setMuted(bool value) {
    _muted = value;
    for (final track in localStream.getAudioTracks()) {
      track.enabled = !value;
    }
  }

  Future<void> setSpeakerphone(bool value) async {
    _speakerOn = value;
    await onSetSpeaker(value);
  }

  Future<void> hangUp({bool notifyRemote = true}) async {
    if (_disposed) return;
    _disposed = true;
    for (final sub in subscriptions) {
      await sub.cancel();
    }
    if (notifyRemote) {
      await onEndRemote();
    }
    await onRestoreAudio();
    try {
      remoteRenderer.srcObject = null;
      await remoteRenderer.dispose();
    } catch (_) {}
    try {
      for (final track in localStream.getTracks()) {
        await track.stop();
      }
      await localStream.dispose();
      await peerConnection.close();
    } catch (_) {}
    audioState.dispose();
  }
}
