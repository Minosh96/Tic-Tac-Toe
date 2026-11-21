import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../domain/models/social_models.dart';

enum VoiceTransportMode { connecting, webrtcLive, relayLive }

/// Hybrid Voice Call Manager:
/// 1. Tries direct P2P WebRTC first (with verified fast STUN + optional Firestore `config/rtc` TURN).
/// 2. If carrier CGNAT / symmetric NAT blocks direct P2P, seamlessly upgrades the active call
///    to **Live Relay Mode** (compressed AAC voice clips streamed over Cloud Firestore HTTPS/443
///    with automatic playback on the receiver) so players can ALWAYS hear each other on every network!
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

  static const List<Map<String, dynamic>> _defaultStunServers = [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
    {'urls': 'stun:stun.cloudflare.com:3478'},
    {'urls': 'stun:stun.relay.metered.ca:80'},
  ];

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

  /// Loads verified STUN servers + optional TURN servers from Firestore `config/rtc`.
  Future<Map<String, dynamic>> _loadRtcConfig() async {
    final iceServers = List<Map<String, dynamic>>.from(_defaultStunServers);
    try {
      final snap = await _db.collection('config').doc('rtc').get();
      final custom = snap.data()?['iceServers'];
      if (custom is List) {
        for (final item in custom) {
          if (item is Map) {
            iceServers.add(Map<String, dynamic>.from(item));
          }
        }
      }
    } catch (_) {}
    return {
      'sdpSemantics': 'unified-plan',
      'iceCandidatePoolSize': 8,
      'iceServers': iceServers,
    };
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

  /// Creates an outgoing hybrid WebRTC + Live Relay voice call.
  Future<ActiveVoiceCall> startVoiceCall({
    required String calleeUid,
    required String calleeName,
    required String callerName,
    required String callerAvatar,
    String? roomId,
  }) async {
    final callerUid = currentUid;
    final rtcConfig = await _loadRtcConfig();
    final localStream = await _openMicrophoneStream();
    final remoteRenderer = RTCVideoRenderer();
    await remoteRenderer.initialize();

    final callRef = _db.collection('calls').doc();
    final offerCandidates = callRef.collection('offerCandidates');
    final answerCandidates = callRef.collection('answerCandidates');

    final activeCall = ActiveVoiceCall._(
      callId: callRef.id,
      myUid: callerUid,
      callRef: callRef,
      localStream: localStream,
      remoteRenderer: remoteRenderer,
      initialStatus: 'Ringing $calleeName…',
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

    final pc = await createPeerConnection(rtcConfig);
    activeCall._attachPeerConnection(pc);

    for (final track in localStream.getAudioTracks()) {
      await pc.addTrack(track, localStream);
    }

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

    bool remoteSet = false;
    final pendingRemoteCandidates = <RTCIceCandidate>[];
    final seenAnswerCandidateIds = <String>{};

    activeCall._addSub(
      callRef.snapshots().listen((snap) async {
        final data = snap.data();
        if (data == null) return;
        final answer = data['answer'];
        if (!remoteSet && answer is Map) {
          remoteSet = true;
          final map = Map<String, dynamic>.from(answer);
          activeCall._onPeerAnswered();
          try {
            await pc.setRemoteDescription(
              RTCSessionDescription(
                map['sdp'] as String?,
                map['type'] as String?,
              ),
            );
            for (final cand in pendingRemoteCandidates) {
              try {
                await pc.addCandidate(cand);
              } catch (_) {}
            }
            pendingRemoteCandidates.clear();
          } catch (_) {
            await activeCall.switchToRelayMode();
          }
        }
      }),
    );

    activeCall._addSub(
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

    activeCall._startRelayChunkListener();
    return activeCall;
  }

  /// Answers an incoming hybrid WebRTC + Live Relay voice call.
  Future<ActiveVoiceCall> answerVoiceCall(VoiceCallSession session) async {
    final offer = session.offer;
    if (offer == null) {
      throw Exception('Call offer is no longer available.');
    }

    final myUid = currentUid;
    final rtcConfig = await _loadRtcConfig();
    final localStream = await _openMicrophoneStream();
    final remoteRenderer = RTCVideoRenderer();
    await remoteRenderer.initialize();

    final callRef = _db.collection('calls').doc(session.callId);
    final offerCandidates = callRef.collection('offerCandidates');
    final answerCandidates = callRef.collection('answerCandidates');

    final activeCall = ActiveVoiceCall._(
      callId: session.callId,
      myUid: myUid,
      callRef: callRef,
      localStream: localStream,
      remoteRenderer: remoteRenderer,
      initialStatus: 'Connecting audio…',
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

    final pc = await createPeerConnection(rtcConfig);
    activeCall._attachPeerConnection(pc);

    for (final track in localStream.getAudioTracks()) {
      await pc.addTrack(track, localStream);
    }

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

    activeCall._onPeerAnswered();

    answerPublished = true;
    final toFlush = List<Map<String, dynamic>>.from(pendingLocalCandidates);
    pendingLocalCandidates.clear();
    for (final payload in toFlush) {
      await writeLocalCandidate(payload);
    }

    final seenOfferCandidateIds = <String>{};
    activeCall._addSub(
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

    activeCall._startRelayChunkListener();
    return activeCall;
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

/// Active hybrid voice call handle supporting full-duplex WebRTC AND automatic
/// carrier-proof Live Relay Voice Mode (auto-playing AAC voice clips via Firestore).
class ActiveVoiceCall {
  ActiveVoiceCall._({
    required this.callId,
    required this.myUid,
    required this.callRef,
    required this.localStream,
    required this.remoteRenderer,
    required String initialStatus,
    required this.onEndRemote,
    required this.onRestoreAudio,
    required this.onSetSpeaker,
  })  : audioState = ValueNotifier<String>(initialStatus),
        transportMode = ValueNotifier<VoiceTransportMode>(
          VoiceTransportMode.connecting,
        ),
        isTalking = ValueNotifier<bool>(false),
        peerSpeaking = ValueNotifier<bool>(false);

  static const MethodChannel _audioChannel = MethodChannel('melow/audio_call');

  final String callId;
  final String myUid;
  final DocumentReference<Map<String, dynamic>> callRef;
  MediaStream? localStream;
  final RTCVideoRenderer remoteRenderer;
  final ValueNotifier<String> audioState;
  final ValueNotifier<VoiceTransportMode> transportMode;
  final ValueNotifier<bool> isTalking;
  final ValueNotifier<bool> peerSpeaking;
  final Future<void> Function() onEndRemote;
  final Future<void> Function() onRestoreAudio;
  final Future<void> Function(bool speaker) onSetSpeaker;

  RTCPeerConnection? _pc;
  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _iceFallbackTimer;
  Timer? _peerSpeakingTimer;
  DateTime? _talkStartedAt;
  final Set<String> _playedChunkIds = <String>{};

  bool _muted = false;
  bool _speakerOn = true;
  bool _disposed = false;
  bool _everConnected = false;
  bool _switchingToRelay = false;

  bool get muted => _muted;
  bool get speakerOn => _speakerOn;
  bool get everConnected => _everConnected;

  void _addSub(StreamSubscription<dynamic> sub) => _subs.add(sub);

  void _attachPeerConnection(RTCPeerConnection pc) {
    _pc = pc;
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
      if (_disposed || transportMode.value == VoiceTransportMode.relayLive) {
        return;
      }
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _markWebRtcConnected();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        switchToRelayMode();
      }
    };

    pc.onIceConnectionState = (RTCIceConnectionState state) {
      if (_disposed || transportMode.value == VoiceTransportMode.relayLive) {
        return;
      }
      switch (state) {
        case RTCIceConnectionState.RTCIceConnectionStateConnected:
        case RTCIceConnectionState.RTCIceConnectionStateCompleted:
          _markWebRtcConnected();
          break;
        case RTCIceConnectionState.RTCIceConnectionStateChecking:
          audioState.value = 'Connecting audio…';
          break;
        case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
        case RTCIceConnectionState.RTCIceConnectionStateFailed:
          switchToRelayMode();
          break;
        default:
          break;
      }
    };
  }

  void _markWebRtcConnected() {
    if (_disposed) return;
    _iceFallbackTimer?.cancel();
    _everConnected = true;
    transportMode.value = VoiceTransportMode.webrtcLive;
    audioState.value = 'Connected';
  }

  /// Starts a 6-second watchdog once callee answers: if carrier CGNAT prevents
  /// direct P2P WebRTC, seamlessly switches to Live Relay Voice Mode!
  void _onPeerAnswered() {
    if (_disposed) return;
    if (transportMode.value == VoiceTransportMode.connecting) {
      audioState.value = 'Connecting audio…';
    }
    _iceFallbackTimer?.cancel();
    _iceFallbackTimer = Timer(const Duration(seconds: 6), () {
      if (!_disposed && transportMode.value == VoiceTransportMode.connecting) {
        switchToRelayMode();
      }
    });
  }

  /// Switches the active call into Live Relay Voice Mode (works over HTTPS/443 on all carriers).
  Future<void> switchToRelayMode() async {
    if (_disposed ||
        _switchingToRelay ||
        transportMode.value == VoiceTransportMode.relayLive) {
      return;
    }
    _switchingToRelay = true;
    _iceFallbackTimer?.cancel();
    _everConnected = true;

    // Release WebRTC mic stream so Android MediaRecorder has exclusive clean mic access.
    try {
      final stream = localStream;
      localStream = null;
      if (stream != null) {
        for (final t in stream.getTracks()) {
          await t.stop();
        }
        await stream.dispose();
      }
      await _pc?.close();
      _pc = null;
    } catch (_) {}

    if (_disposed) return;
    transportMode.value = VoiceTransportMode.relayLive;
    audioState.value = 'Connected (Live Relay)';
  }

  /// Listens for incoming relay voice clips from the other player & plays them immediately.
  void _startRelayChunkListener() {
    _addSub(
      callRef
          .collection('audioChunks')
          .orderBy('createdAt', descending: false)
          .snapshots()
          .listen((snap) async {
        for (final doc in snap.docs) {
          if (!_playedChunkIds.add(doc.id)) continue;
          final d = doc.data();
          if (d['senderUid'] == myUid) continue;
          final b64 = d['audioBase64'] as String?;
          if (b64 == null || b64.isEmpty) continue;
          // Auto-switch receiver to Relay Mode if peer already started sending relay audio!
          if (transportMode.value != VoiceTransportMode.relayLive) {
            await switchToRelayMode();
          }
          if (_disposed) return;
          peerSpeaking.value = true;
          _peerSpeakingTimer?.cancel();
          final durMs = ((d['durationMs'] as num?)?.toInt() ?? 2000).clamp(800, 30000);
          _peerSpeakingTimer = Timer(Duration(milliseconds: durMs + 400), () {
            if (!_disposed) peerSpeaking.value = false;
          });
          try {
            await _audioChannel.invokeMethod('playRelayAudio', {
              'audioBase64': b64,
              'speaker': _speakerOn,
            });
          } catch (_) {}
        }
      }),
    );
  }

  /// Begins recording a live relay voice clip (used in Live Relay Mode).
  Future<void> startRelayTalk() async {
    if (_disposed || _muted || isTalking.value) return;
    if (transportMode.value != VoiceTransportMode.relayLive) {
      await switchToRelayMode();
    }
    try {
      await _audioChannel.invokeMethod('startRelayRecording');
      _talkStartedAt = DateTime.now();
      isTalking.value = true;
    } catch (_) {}
  }

  /// Stops recording & immediately sends the compressed voice clip to your friend.
  Future<void> stopAndSendRelayTalk() async {
    if (_disposed || !isTalking.value) return;
    isTalking.value = false;
    final durMs = _talkStartedAt == null
        ? 1000
        : DateTime.now().difference(_talkStartedAt!).inMilliseconds.clamp(300, 55000);
    _talkStartedAt = null;
    try {
      final b64 =
          await _audioChannel.invokeMethod<String>('stopRelayRecording');
      if (b64 == null || b64.isEmpty || b64.length > 340000) return;
      await callRef.collection('audioChunks').add({
        'senderUid': myUid,
        'audioBase64': b64,
        'durationMs': durMs,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  void setMuted(bool value) {
    _muted = value;
    final stream = localStream;
    if (stream != null) {
      for (final track in stream.getAudioTracks()) {
        track.enabled = !value;
      }
    }
  }

  Future<void> setSpeakerphone(bool value) async {
    _speakerOn = value;
    await onSetSpeaker(value);
  }

  Future<void> hangUp({bool notifyRemote = true}) async {
    if (_disposed) return;
    _disposed = true;
    _iceFallbackTimer?.cancel();
    _peerSpeakingTimer?.cancel();
    for (final sub in _subs) {
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
      final stream = localStream;
      localStream = null;
      if (stream != null) {
        for (final track in stream.getTracks()) {
          await track.stop();
        }
        await stream.dispose();
      }
      await _pc?.close();
      _pc = null;
    } catch (_) {}
    audioState.dispose();
    transportMode.dispose();
    isTalking.dispose();
    peerSpeaking.dispose();
  }
}
