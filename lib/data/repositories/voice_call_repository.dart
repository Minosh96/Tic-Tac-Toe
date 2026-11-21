import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../domain/models/social_models.dart';

/// Peer-to-peer WebRTC Voice Call manager backed by Cloud Firestore signaling.
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

  static const Map<String, dynamic> _rtcConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
    ],
  };

  String get currentUid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Not signed in');
    return uid;
  }

  /// Streams active incoming ringing calls for [uid].
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

  /// Opens the local microphone audio stream (Android automatically prompts
  /// for RECORD_AUDIO runtime permission through WebRTC).
  Future<MediaStream> _openMicrophoneStream() async {
    try {
      return await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
      });
    } catch (_) {
      throw Exception(
        'Microphone access is required for voice calls. Please allow microphone permission.',
      );
    }
  }

  /// Creates an outgoing WebRTC audio call and returns the active [ActiveVoiceCall].
  Future<ActiveVoiceCall> startVoiceCall({
    required String calleeUid,
    required String calleeName,
    required String callerName,
    required String callerAvatar,
    String? roomId,
  }) async {
    final callerUid = currentUid;
    final callRef = _db.collection('calls').doc();
    final offerCandidates = callRef.collection('offerCandidates');
    final answerCandidates = callRef.collection('answerCandidates');

    final localStream = await _openMicrophoneStream();
    final pc = await createPeerConnection(_rtcConfig);
    for (final track in localStream.getAudioTracks()) {
      await pc.addTrack(track, localStream);
    }

    pc.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate == null) return;
      offerCandidates.add({
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    final offer = await pc.createOffer({'offerToReceiveAudio': true});
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

    final subs = <StreamSubscription<dynamic>>[];
    bool remoteSet = false;

    subs.add(
      callRef.snapshots().listen((snap) async {
        final data = snap.data();
        if (data == null) return;
        final answer = data['answer'];
        if (!remoteSet && answer is Map<String, dynamic>) {
          remoteSet = true;
          await pc.setRemoteDescription(
            RTCSessionDescription(
              answer['sdp'] as String?,
              answer['type'] as String?,
            ),
          );
        }
      }),
    );

    subs.add(
      answerCandidates.snapshots().listen((snap) {
        for (final change in snap.docChanges) {
          if (change.type == DocumentChangeType.added) {
            final d = change.doc.data();
            if (d != null) {
              pc.addCandidate(
                RTCIceCandidate(
                  d['candidate'] as String?,
                  d['sdpMid'] as String?,
                  (d['sdpMLineIndex'] as num?)?.toInt(),
                ),
              );
            }
          }
        }
      }),
    );

    return ActiveVoiceCall(
      callId: callRef.id,
      peerConnection: pc,
      localStream: localStream,
      subscriptions: subs,
      onEndRemote: () => updateCallStatus(callRef.id, 'ended'),
    );
  }

  /// Answers an incoming ringing voice call.
  Future<ActiveVoiceCall> answerVoiceCall(VoiceCallSession session) async {
    final callRef = _db.collection('calls').doc(session.callId);
    final offerCandidates = callRef.collection('offerCandidates');
    final answerCandidates = callRef.collection('answerCandidates');

    final localStream = await _openMicrophoneStream();
    final pc = await createPeerConnection(_rtcConfig);
    for (final track in localStream.getAudioTracks()) {
      await pc.addTrack(track, localStream);
    }

    pc.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate == null) return;
      answerCandidates.add({
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    final offer = session.offer;
    if (offer == null) {
      await localStream.dispose();
      await pc.close();
      throw Exception('Call offer is no longer available.');
    }

    await pc.setRemoteDescription(
      RTCSessionDescription(
        offer['sdp'] as String?,
        offer['type'] as String?,
      ),
    );
    final answer = await pc.createAnswer({'offerToReceiveAudio': true});
    await pc.setLocalDescription(answer);

    await callRef.update({
      'status': 'active',
      'answer': {'sdp': answer.sdp, 'type': answer.type},
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final subs = <StreamSubscription<dynamic>>[];
    subs.add(
      offerCandidates.snapshots().listen((snap) {
        for (final change in snap.docChanges) {
          if (change.type == DocumentChangeType.added) {
            final d = change.doc.data();
            if (d != null) {
              pc.addCandidate(
                RTCIceCandidate(
                  d['candidate'] as String?,
                  d['sdpMid'] as String?,
                  (d['sdpMLineIndex'] as num?)?.toInt(),
                ),
              );
            }
          }
        }
      }),
    );

    return ActiveVoiceCall(
      callId: session.callId,
      peerConnection: pc,
      localStream: localStream,
      subscriptions: subs,
      onEndRemote: () => updateCallStatus(session.callId, 'ended'),
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

/// Active WebRTC audio handle with mute, speakerphone & clean resource disposal.
class ActiveVoiceCall {
  ActiveVoiceCall({
    required this.callId,
    required this.peerConnection,
    required this.localStream,
    required this.subscriptions,
    required this.onEndRemote,
  });

  final String callId;
  final RTCPeerConnection peerConnection;
  final MediaStream localStream;
  final List<StreamSubscription<dynamic>> subscriptions;
  final Future<void> Function() onEndRemote;

  bool _muted = false;
  bool _speakerOn = false;
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
    try {
      await Helper.setSpeakerphoneOn(value);
    } catch (_) {}
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
    try {
      for (final track in localStream.getTracks()) {
        await track.stop();
      }
      await localStream.dispose();
      await peerConnection.close();
    } catch (_) {}
  }
}
