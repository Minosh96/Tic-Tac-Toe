import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../domain/models/group_models.dart';
import '../../domain/models/social_models.dart';

enum VoiceTransportMode { connecting, webrtcLive, fullDuplexRelay }

/// Real-Time Hands-Free WhatsApp-Style Voice Call Manager:
/// 1. Tries direct P2P WebRTC first (verified fast STUN + optional Firestore `config/rtc` TURN).
/// 2. If mobile carrier CGNAT / symmetric NAT blocks direct P2P within 4 seconds,
///    automatically switches to our native **Full-Duplex Hands-Free Voice Stream**
///    (`AudioRecord` + Hardware AEC/NS/AGC + ITU-T G.711 u-law + continuous `AudioTrack`)
///    over Cloud Firestore HTTPS/443 — ZERO buttons to press, talk naturally like WhatsApp!
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

  /// Creates an outgoing hands-free real-time voice call.
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
            await activeCall.switchToFullDuplexRelay();
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

  /// Answers an incoming hands-free real-time voice call.
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

  /// Starts or joins a multi-person Group Voice Call (up to 5 members in a single call).
  /// - If no call is currently ongoing in the group (`ringMembersIfStarting == true`),
  ///   rings all other group members simultaneously so their phones ring and show an Answer banner.
  /// - If a group call is already ongoing, or if a member previously left and taps "Rejoin Group Call",
  ///   adds the current member back into `activeCall.activeMemberUids`.
  Future<ActiveGroupVoiceCall> startOrJoinGroupVoiceCall({
    required FriendGroup group,
    required String myName,
    required String myAvatar,
    String? incomingAlertCallId,
  }) async {
    final myUid = currentUid;
    await _requestNativeMicPermission();
    await _configureAndroidAudio(enabled: true, speaker: true);

    final groupRef = _db.collection('groups').doc(group.id);
    bool shouldRingMembers = false;

    await _db.runTransaction((tx) async {
      final snap = await tx.get(groupRef);
      if (!snap.exists || snap.data() == null) {
        throw Exception('This group no longer exists.');
      }
      final g = FriendGroup.fromFirestore(snap);
      final currentCall = g.activeCall;
      if (currentCall != null && currentCall.isOngoing) {
        // Ongoing call -> add or re-add this member!
        final nextMembers = <String>[
          ...currentCall.activeMemberUids,
          if (!currentCall.activeMemberUids.contains(myUid)) myUid,
        ];
        final updatedCall = GroupActiveCall(
          callSessionId: currentCall.callSessionId,
          initiatorUid: currentCall.initiatorUid,
          initiatorName: currentCall.initiatorName,
          status: 'active',
          activeMemberUids: nextMembers.take(5).toList(growable: false),
        );
        tx.update(groupRef, {
          'activeCall': updatedCall.toMap(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        // Brand new group call -> ring all other members in the group!
        shouldRingMembers = true;
        final sessionId =
            'gcall_${DateTime.now().millisecondsSinceEpoch}';
        final newCall = GroupActiveCall(
          callSessionId: sessionId,
          initiatorUid: myUid,
          initiatorName: myName,
          status: 'active',
          activeMemberUids: [myUid],
        );
        tx.update(groupRef, {
          'activeCall': newCall.toMap(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });

    // If answering from an incoming ringing alert doc, mark that ringing alert doc as active.
    if (incomingAlertCallId != null && incomingAlertCallId.isNotEmpty) {
      await updateCallStatus(incomingAlertCallId, 'active');
    }

    // Ring all other members in the group so their phones ring and show the incoming Group Call banner!
    if (shouldRingMembers) {
      for (final memberUid in group.memberUids) {
        if (memberUid == myUid) continue;
        final memberName = group.memberNames[memberUid] ?? 'Group Member';
        try {
          await _db.collection('calls').add({
            'callerUid': myUid,
            'calleeUid': memberUid,
            'callerName': myName,
            'callerAvatar': myAvatar,
            'calleeName': memberName,
            'groupId': group.id,
            'groupName': group.name,
            'status': 'ringing',
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } catch (_) {}
      }
    }

    final handle = ActiveGroupVoiceCall._(
      groupId: group.id,
      myUid: myUid,
      groupRef: groupRef,
      onLeaveRemote: () => _leaveGroupCallRemote(group.id, myUid),
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
    await handle._start();
    return handle;
  }

  Future<void> _leaveGroupCallRemote(String groupId, String uid) async {
    final groupRef = _db.collection('groups').doc(groupId);
    bool callEndedCompletely = false;
    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(groupRef);
        if (!snap.exists || snap.data() == null) return;
        final g = FriendGroup.fromFirestore(snap);
        final currentCall = g.activeCall;
        if (currentCall == null) return;
        final remaining = currentCall.activeMemberUids
            .where((m) => m != uid)
            .toList(growable: false);
        if (remaining.isEmpty) {
          callEndedCompletely = true;
          tx.update(groupRef, {
            'activeCall': GroupActiveCall(
              callSessionId: currentCall.callSessionId,
              initiatorUid: currentCall.initiatorUid,
              initiatorName: currentCall.initiatorName,
              status: 'ended',
              activeMemberUids: const <String>[],
            ).toMap(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          tx.update(groupRef, {
            'activeCall': GroupActiveCall(
              callSessionId: currentCall.callSessionId,
              initiatorUid: currentCall.initiatorUid,
              initiatorName: currentCall.initiatorName,
              status: 'active',
              activeMemberUids: remaining,
            ).toMap(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });
    } catch (_) {}

    // If the last member left the group call, cancel any pending ringing alerts for this group.
    if (callEndedCompletely) {
      try {
        final ringingDocs = await _db
            .collection('calls')
            .where('callerUid', isEqualTo: uid)
            .get();
        for (final doc in ringingDocs.docs) {
          final d = doc.data();
          if (d['groupId'] == groupId && d['status'] == 'ringing') {
            await doc.reference.update({
              'status': 'ended',
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
        }
      } catch (_) {}
    }
  }
}

/// Active hands-free real-time voice call handle (P2P WebRTC + automatic
/// native Full-Duplex Hands-Free Relay with zero buttons to press).
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
        mySpeaking = ValueNotifier<bool>(false),
        peerSpeaking = ValueNotifier<bool>(false);

  static const MethodChannel _audioChannel = MethodChannel('melow/audio_call');

  final String callId;
  final String myUid;
  final DocumentReference<Map<String, dynamic>> callRef;
  MediaStream? localStream;
  final RTCVideoRenderer remoteRenderer;
  final ValueNotifier<String> audioState;
  final ValueNotifier<VoiceTransportMode> transportMode;
  final ValueNotifier<bool> mySpeaking;
  final ValueNotifier<bool> peerSpeaking;
  final Future<void> Function() onEndRemote;
  final Future<void> Function() onRestoreAudio;
  final Future<void> Function(bool speaker) onSetSpeaker;

  RTCPeerConnection? _pc;
  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _iceFallbackTimer;
  Timer? _peerSpeakingTimer;
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
      if (_disposed ||
          transportMode.value == VoiceTransportMode.fullDuplexRelay) {
        return;
      }
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _markWebRtcConnected();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        switchToFullDuplexRelay();
      }
    };

    pc.onIceConnectionState = (RTCIceConnectionState state) {
      if (_disposed ||
          transportMode.value == VoiceTransportMode.fullDuplexRelay) {
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
          switchToFullDuplexRelay();
          break;
        default:
          break;
      }
    };
  }

  void _markWebRtcConnected() {
    if (_disposed || _switchingToRelay) return;
    _iceFallbackTimer?.cancel();
    _everConnected = true;
    transportMode.value = VoiceTransportMode.webrtcLive;
    audioState.value = 'Connected';
  }

  /// 4-second watchdog after peer answers: if carrier CGNAT prevents direct
  /// P2P WebRTC, silently upgrades to hands-free Full-Duplex Voice Streaming!
  void _onPeerAnswered() {
    if (_disposed) return;
    if (transportMode.value == VoiceTransportMode.connecting) {
      audioState.value = 'Connecting audio…';
    }
    _iceFallbackTimer?.cancel();
    _iceFallbackTimer = Timer(const Duration(seconds: 4), () {
      if (!_disposed && transportMode.value == VoiceTransportMode.connecting) {
        switchToFullDuplexRelay();
      }
    });
  }

  /// Seamlessly switches to hands-free Full-Duplex real-time audio streaming
  /// (works on every mobile carrier with zero buttons to press).
  Future<void> switchToFullDuplexRelay() async {
    if (_disposed ||
        _switchingToRelay ||
        transportMode.value == VoiceTransportMode.fullDuplexRelay) {
      return;
    }
    _switchingToRelay = true;
    _iceFallbackTimer?.cancel();
    _everConnected = true;

    // Release WebRTC mic stream so Android AudioRecord + Hardware AEC gets clean mic access.
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

    // Register native callback handler for continuous hands-free speech frames.
    _audioChannel.setMethodCallHandler(_handleNativeAudioCallback);

    try {
      await _audioChannel.invokeMethod('startFullDuplexRelay', {
        'speaker': _speakerOn,
        'muted': _muted,
      });
    } catch (_) {}

    if (_disposed) return;
    transportMode.value = VoiceTransportMode.fullDuplexRelay;
    audioState.value = 'Connected';
  }

  Future<dynamic> _handleNativeAudioCallback(MethodCall call) async {
    if (_disposed) return;
    if (call.method == 'onFullDuplexFrame') {
      final args = call.arguments;
      if (args is Map) {
        final b64 = args['audioBase64'] as String?;
        final durMs = (args['durationMs'] as num?)?.toInt() ?? 320;
        if (b64 != null && b64.isNotEmpty && b64.length <= 340000) {
          // Fire-and-forget upload so capture thread stays completely real-time.
          callRef.collection('audioChunks').add({
            'senderUid': myUid,
            'audioBase64': b64,
            'durationMs': durMs.clamp(20, 60000),
            'createdAt': FieldValue.serverTimestamp(),
          }).catchError((_) => callRef);
        }
      }
    } else if (call.method == 'onLocalSpeaking') {
      final speaking = call.arguments == true;
      if (!_disposed && mySpeaking.value != speaking) {
        mySpeaking.value = speaking;
      }
    }
  }

  /// Streams incoming speech frames from the peer & plays them immediately via AudioTrack.
  void _startRelayChunkListener() {
    _addSub(
      callRef
          .collection('audioChunks')
          .orderBy('createdAt', descending: false)
          .snapshots()
          .listen((snap) async {
        final now = DateTime.now();
        for (final doc in snap.docs) {
          if (!_playedChunkIds.add(doc.id)) continue;
          final d = doc.data();
          if (d['senderUid'] == myUid) continue;
          final b64 = d['audioBase64'] as String?;
          if (b64 == null || b64.isEmpty) continue;

          // Ignore very stale frames (> 6s old) so reconnecting never replays old audio.
          final ts = d['createdAt'];
          if (ts is Timestamp && now.difference(ts.toDate()).inSeconds > 6) {
            continue;
          }

          // Auto-switch receiver to hands-free Full-Duplex if peer switched first!
          if (transportMode.value != VoiceTransportMode.fullDuplexRelay) {
            await switchToFullDuplexRelay();
          }
          if (_disposed) return;

          peerSpeaking.value = true;
          _peerSpeakingTimer?.cancel();
          final durMs = ((d['durationMs'] as num?)?.toInt() ?? 320).clamp(200, 5000);
          _peerSpeakingTimer = Timer(Duration(milliseconds: durMs + 350), () {
            if (!_disposed) peerSpeaking.value = false;
          });

          try {
            await _audioChannel.invokeMethod('playFullDuplexFrame', {
              'audioBase64': b64,
            });
          } catch (_) {}
        }
      }),
    );
  }

  void setMuted(bool value) {
    _muted = value;
    if (value && !_disposed) {
      mySpeaking.value = false;
    }
    final stream = localStream;
    if (stream != null) {
      for (final track in stream.getAudioTracks()) {
        track.enabled = !value;
      }
    }
    if (transportMode.value == VoiceTransportMode.fullDuplexRelay) {
      _audioChannel
          .invokeMethod('setFullDuplexMuted', {'muted': value})
          .catchError((_) {});
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
    _audioChannel.setMethodCallHandler(null);
    for (final sub in _subs) {
      await sub.cancel();
    }
    try {
      await _audioChannel.invokeMethod('stopFullDuplexRelay');
    } catch (_) {}
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
    mySpeaking.dispose();
    peerSpeaking.dispose();
  }
}

/// Active multi-person Group Voice Call handle (supports up to 5 members in a single call,
/// tracks per-member live speaking state, and allows leaving and rejoining at any time).
class ActiveGroupVoiceCall {
  ActiveGroupVoiceCall._({
    required this.groupId,
    required this.myUid,
    required this.groupRef,
    required this.onLeaveRemote,
    required this.onRestoreAudio,
    required this.onSetSpeaker,
  })  : mySpeaking = ValueNotifier<bool>(false),
        speakingMemberUids = ValueNotifier<Set<String>>(<String>{});

  static const MethodChannel _audioChannel = MethodChannel('melow/audio_call');

  final String groupId;
  final String myUid;
  final DocumentReference<Map<String, dynamic>> groupRef;
  final Future<void> Function() onLeaveRemote;
  final Future<void> Function() onRestoreAudio;
  final Future<void> Function(bool speaker) onSetSpeaker;

  final ValueNotifier<bool> mySpeaking;
  final ValueNotifier<Set<String>> speakingMemberUids;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _chunkSub;
  final Map<String, Timer> _speakerTimers = <String, Timer>{};
  final Set<String> _playedChunkIds = <String>{};

  bool _muted = false;
  bool _speakerOn = true;
  bool _disposed = false;

  bool get muted => _muted;
  bool get speakerOn => _speakerOn;

  Future<void> _start() async {
    _audioChannel.setMethodCallHandler(_handleNativeAudioCallback);
    try {
      await _audioChannel.invokeMethod('startFullDuplexRelay', {
        'speaker': _speakerOn,
        'muted': _muted,
      });
    } catch (_) {}

    _chunkSub = groupRef
        .collection('audioChunks')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .listen((snap) async {
      final now = DateTime.now();
      for (final doc in snap.docs) {
        if (!_playedChunkIds.add(doc.id)) continue;
        final d = doc.data();
        final senderUid = d['senderUid'] as String? ?? '';
        if (senderUid.isEmpty || senderUid == myUid) continue;
        final b64 = d['audioBase64'] as String?;
        if (b64 == null || b64.isEmpty) continue;

        final ts = d['createdAt'];
        if (ts is Timestamp && now.difference(ts.toDate()).inSeconds > 6) {
          continue;
        }
        if (_disposed) return;

        // Mark this group member as actively speaking!
        final nextSet = Set<String>.from(speakingMemberUids.value)
          ..add(senderUid);
        speakingMemberUids.value = nextSet;
        _speakerTimers[senderUid]?.cancel();
        final durMs =
            ((d['durationMs'] as num?)?.toInt() ?? 320).clamp(200, 5000);
        _speakerTimers[senderUid] =
            Timer(Duration(milliseconds: durMs + 400), () {
          if (_disposed) return;
          final updated = Set<String>.from(speakingMemberUids.value)
            ..remove(senderUid);
          speakingMemberUids.value = updated;
        });

        try {
          await _audioChannel.invokeMethod('playFullDuplexFrame', {
            'audioBase64': b64,
          });
        } catch (_) {}
      }
    });
  }

  Future<dynamic> _handleNativeAudioCallback(MethodCall call) async {
    if (_disposed) return;
    if (call.method == 'onFullDuplexFrame') {
      final args = call.arguments;
      if (args is Map) {
        final b64 = args['audioBase64'] as String?;
        final durMs = (args['durationMs'] as num?)?.toInt() ?? 320;
        if (b64 != null && b64.isNotEmpty && b64.length <= 340000) {
          groupRef.collection('audioChunks').add({
            'senderUid': myUid,
            'audioBase64': b64,
            'durationMs': durMs.clamp(20, 60000),
            'createdAt': FieldValue.serverTimestamp(),
          }).catchError((_) => groupRef);
        }
      }
    } else if (call.method == 'onLocalSpeaking') {
      final speaking = call.arguments == true;
      if (!_disposed && mySpeaking.value != speaking) {
        mySpeaking.value = speaking;
      }
    }
  }

  void setMuted(bool value) {
    _muted = value;
    if (value && !_disposed) {
      mySpeaking.value = false;
    }
    _audioChannel
        .invokeMethod('setFullDuplexMuted', {'muted': value})
        .catchError((_) {});
  }

  Future<void> setSpeakerphone(bool value) async {
    _speakerOn = value;
    await onSetSpeaker(value);
  }

  Future<void> leaveCall({bool notifyRemote = true}) async {
    if (_disposed) return;
    _disposed = true;
    _audioChannel.setMethodCallHandler(null);
    await _chunkSub?.cancel();
    for (final t in _speakerTimers.values) {
      t.cancel();
    }
    _speakerTimers.clear();
    try {
      await _audioChannel.invokeMethod('stopFullDuplexRelay');
    } catch (_) {}
    if (notifyRemote) {
      await onLeaveRemote();
    }
    await onRestoreAudio();
    mySpeaking.dispose();
    speakingMemberUids.dispose();
  }
}
