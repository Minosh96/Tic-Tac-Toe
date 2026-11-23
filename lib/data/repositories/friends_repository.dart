import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../domain/game_engine.dart';
import '../../domain/models/social_models.dart';
import '../../domain/models/user_profile.dart';
import 'game_repository.dart';

/// Handles friend lookup by code, requests, friend list, blocking, reporting,
/// and atomic friend room challenges.
class FriendsRepository {
  FriendsRepository({
    required this.gameRepository,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
    String? databaseId,
  })  : _db = firestore ??
            (databaseId != null
                ? FirebaseFirestore.instanceFor(
                    app: Firebase.app(),
                    databaseId: databaseId,
                  )
                : FirebaseFirestore.instance),
        _auth = auth ?? FirebaseAuth.instance,
        _functions = functions ?? FirebaseFunctions.instance;

  final GameRepository gameRepository;
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;

  String get currentUid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Not signed in');
    return uid;
  }

  /// Looks up a public user profile by shareable 8-character friend code.
  Future<UserProfile?> findUserByFriendCode(String rawCode) async {
    final code = rawCode.trim().toUpperCase();
    if (code.length < 6) return null;
    final codeDoc = await _db.collection('friendCodes').doc(code).get();
    final targetUid = codeDoc.data()?['uid'] as String?;
    if (targetUid == null || targetUid.isEmpty) return null;
    if (targetUid == currentUid) {
      throw Exception('That is your own friend code!');
    }
    final userDoc = await _db.collection('users').doc(targetUid).get();
    if (!userDoc.exists || userDoc.data() == null) return null;
    return UserProfile.fromFirestore(userDoc);
  }

  Stream<List<FriendEntry>> watchFriends(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('friends')
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(FriendEntry.fromFirestore)
              .toList(growable: false),
        );
  }

  Stream<List<FriendRequest>> watchIncomingRequests(String uid) {
    return _db
        .collection('friendRequests')
        .where('receiverUid', isEqualTo: uid)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(FriendRequest.fromFirestore)
              .where((r) => r.isPending && !r.isExpired)
              .toList(growable: false),
        );
  }

  Stream<List<FriendRequest>> watchOutgoingRequests(String uid) {
    return _db
        .collection('friendRequests')
        .where('senderUid', isEqualTo: uid)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(FriendRequest.fromFirestore)
              .where((r) => r.isPending && !r.isExpired)
              .toList(growable: false),
        );
  }

  Stream<List<FriendChallenge>> watchIncomingChallenges(String uid) {
    return _db
        .collection('friendChallenges')
        .where('receiverUid', isEqualTo: uid)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(FriendChallenge.fromFirestore)
              .where((c) => c.isPending && !c.isExpired)
              .toList(growable: false),
        );
  }

  Stream<List<FriendChallenge>> watchOutgoingChallenges(String uid) {
    return _db
        .collection('friendChallenges')
        .where('senderUid', isEqualTo: uid)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(FriendChallenge.fromFirestore)
              .where((c) => (c.isPending || c.isAccepted) && !c.isExpired)
              .toList(growable: false),
        );
  }

  Future<void> sendFriendRequest({
    required UserProfile me,
    required UserProfile target,
  }) async {
    if (me.uid == target.uid) {
      throw Exception('You cannot add yourself as a friend.');
    }
    final existing = await _db
        .collection('friendRequests')
        .where('senderUid', isEqualTo: me.uid)
        .where('receiverUid', isEqualTo: target.uid)
        .get();
    final hasPending = existing.docs.any((d) => d.data()['status'] == 'pending');
    if (hasPending) {
      throw Exception('Friend request already pending.');
    }
    await _db.collection('friendRequests').add({
      'senderUid': me.uid,
      'senderName': me.nickname,
      'senderAvatar': me.avatarId,
      'receiverUid': target.uid,
      'receiverName': target.nickname,
      'receiverAvatar': target.avatarId,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(
        DateTime.now().add(const Duration(days: 14)),
      ),
    });
  }

  Future<void> respondFriendRequest({
    required FriendRequest request,
    required bool accept,
  }) async {
    final uid = currentUid;
    final ref = _db.collection('friendRequests').doc(request.id);
    if (!accept) {
      await ref.update({'status': 'declined'});
      return;
    }

    final batch = _db.batch();
    batch.update(ref, {'status': 'accepted'});
    batch.set(
      _db.collection('users').doc(uid).collection('friends').doc(request.senderUid),
      {
        'friendUid': request.senderUid,
        'nickname': request.senderName,
        'avatarId': request.senderAvatar,
        'since': FieldValue.serverTimestamp(),
        'status': 'accepted',
      },
    );
    batch.set(
      _db.collection('users').doc(request.senderUid).collection('friends').doc(uid),
      {
        'friendUid': uid,
        'nickname': request.receiverName,
        'avatarId': request.receiverAvatar,
        'since': FieldValue.serverTimestamp(),
        'status': 'accepted',
      },
    );
    await batch.commit();
  }

  Future<void> cancelFriendRequest(String requestId) async {
    await _db
        .collection('friendRequests')
        .doc(requestId)
        .update({'status': 'cancelled'});
  }

  Future<void> removeFriend(String friendUid) async {
    final uid = currentUid;
    await _db
        .collection('users')
        .doc(uid)
        .collection('friends')
        .doc(friendUid)
        .delete();
  }

  Future<void> blockUser(
    String blockedUid, {
    String? nickname,
    String? avatarId,
  }) async {
    final uid = currentUid;
    final trimmedName = nickname?.trim() ?? '';
    final safeName = trimmedName.isNotEmpty
        ? trimmedName.substring(0, trimmedName.length.clamp(0, 20))
        : null;
    final trimmedAvatar = avatarId?.trim() ?? '';
    final safeAvatar = trimmedAvatar.isNotEmpty
        ? trimmedAvatar.substring(0, trimmedAvatar.length.clamp(0, 32))
        : null;
    final batch = _db.batch();
    batch.set(
      _db.collection('users').doc(uid).collection('blocked').doc(blockedUid),
      {
        'blockedUid': blockedUid,
        if (safeName != null) 'nickname': safeName,
        if (safeAvatar != null) 'avatarId': safeAvatar,
        'createdAt': FieldValue.serverTimestamp(),
      },
    );
    batch.delete(
      _db.collection('users').doc(uid).collection('friends').doc(blockedUid),
    );
    await batch.commit();
  }

  /// Streams all users currently blocked by [uid].
  Stream<List<BlockedUserEntry>> watchBlockedUsers(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('blocked')
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map(BlockedUserEntry.fromFirestore)
          .toList(growable: true);
      list.sort(
        (a, b) => (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(
          a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        ),
      );
      return list;
    });
  }

  /// Unblocks [blockedUid] and optionally restores them to the user's friends list.
  Future<void> unblockUser(
    String blockedUid, {
    String? nickname,
    String? avatarId,
    bool restoreFriend = true,
  }) async {
    final uid = currentUid;
    final batch = _db.batch();
    batch.delete(
      _db.collection('users').doc(uid).collection('blocked').doc(blockedUid),
    );
    if (restoreFriend) {
      final rawName = nickname?.trim() ?? '';
      final safeName = (rawName.isNotEmpty && rawName != 'Blocked Player')
          ? rawName.substring(0, rawName.length.clamp(0, 20))
          : 'Friend';
      final rawAvatar = avatarId?.trim() ?? '';
      final safeAvatar = rawAvatar.isNotEmpty
          ? rawAvatar.substring(0, rawAvatar.length.clamp(0, 32))
          : 'fox';
      batch.set(
        _db.collection('users').doc(uid).collection('friends').doc(blockedUid),
        {
          'friendUid': blockedUid,
          'nickname': safeName,
          'avatarId': safeAvatar,
          'since': FieldValue.serverTimestamp(),
          'status': 'accepted',
        },
      );
    }
    await batch.commit();
  }

  Future<void> reportUser({
    required String reportedUid,
    required String reason,
  }) async {
    final trimmed = reason.trim();
    if (trimmed.isEmpty) throw Exception('Please enter a brief reason.');
    await _db.collection('reports').add({
      'reporterUid': currentUid,
      'reportedUid': reportedUid,
      'reason': trimmed.substring(0, trimmed.length.clamp(0, 300)),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Sends a room match challenge to a friend.
  Future<String> sendFriendChallenge({
    required UserProfile me,
    required String friendUid,
    required String friendName,
    required GameMode mode,
    required int boardSize,
    required int bestOf,
    String existingRoomId = '',
  }) async {
    final docRef = await _db.collection('friendChallenges').add({
      'senderUid': me.uid,
      'senderName': me.nickname,
      'senderAvatar': me.avatarId,
      'senderEmoji': me.preferredEmoji,
      'receiverUid': friendUid,
      'receiverName': friendName,
      'mode': mode.id,
      'boardSize': boardSize,
      'bestOf': bestOf,
      'roomId': existingRoomId,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(
        DateTime.now().add(const Duration(minutes: 30)),
      ),
    });
    return docRef.id;
  }

  /// Atomically & idempotently accepts a friend challenge and returns the room code.
  Future<String> acceptFriendChallenge({
    required FriendChallenge challenge,
    required UserProfile me,
  }) async {
    if (challenge.isExpired) {
      throw Exception('This challenge has expired.');
    }

    // Prefer trusted Cloud Function for atomic room creation if deployed.
    try {
      final callable = _functions.httpsCallable('acceptFriendChallenge');
      final response = await callable.call({
        'challengeId': challenge.id,
        'guestName': me.nickname,
        'guestEmoji': me.preferredEmoji == challenge.senderEmoji
            ? (emojiChoices.firstWhere((e) => e != challenge.senderEmoji))
            : me.preferredEmoji,
        'guestAvatar': me.avatarId,
      });
      final roomId = (response.data as Map?)?['roomId'] as String?;
      if (roomId != null && roomId.isNotEmpty) return roomId;
    } catch (_) {
      // Fallback for Spark tier without deployed Functions.
    }

    // Ensure guest picks an emoji distinct from sender.
    final guestEmoji = me.preferredEmoji == challenge.senderEmoji
        ? emojiChoices.firstWhere((e) => e != challenge.senderEmoji)
        : me.preferredEmoji;

    String roomId = challenge.roomId;
    if (roomId.isNotEmpty) {
      await gameRepository.joinRoom(
        code: roomId,
        name: me.nickname,
        emoji: guestEmoji,
        guestAvatar: me.avatarId,
      );
      await _db.collection('friendChallenges').doc(challenge.id).update({
        'status': 'accepted',
        'roomId': roomId,
      });
      return roomId;
    }

    // Create a fresh room hosted by the receiver so the sender can immediately join.
    roomId = await gameRepository.createRoom(
      name: me.nickname,
      emoji: guestEmoji,
      size: challenge.boardSize,
      bestOf: challenge.bestOf,
      gameMode: GameMode.fromId(challenge.mode),
      hostAvatar: me.avatarId,
    );

    final challengeRef = _db.collection('friendChallenges').doc(challenge.id);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(challengeRef);
      final data = snap.data();
      if (data == null) throw Exception('Challenge no longer exists.');
      if (data['status'] == 'accepted' &&
          (data['roomId'] as String? ?? '').isNotEmpty) {
        roomId = data['roomId'] as String;
        return;
      }
      if (data['status'] != 'pending') {
        throw Exception('Challenge is no longer pending.');
      }
      tx.update(challengeRef, {
        'status': 'accepted',
        'roomId': roomId,
      });
    });

    return roomId;
  }

  Future<void> declineFriendChallenge(String challengeId) async {
    await _db
        .collection('friendChallenges')
        .doc(challengeId)
        .update({'status': 'declined'});
  }

  Future<void> cancelFriendChallenge(String challengeId) async {
    await _db
        .collection('friendChallenges')
        .doc(challengeId)
        .update({'status': 'cancelled'});
  }

  /// Permanently removes a previously sent challenge (pending or accepted).
  Future<void> removeSentChallenge(String challengeId) async {
    try {
      await _db.collection('friendChallenges').doc(challengeId).delete();
    } catch (_) {
      await cancelFriendChallenge(challengeId);
    }
  }

  /// Removes multiple previously sent challenges in one batch.
  Future<void> clearAllSentChallenges(List<String> challengeIds) async {
    if (challengeIds.isEmpty) return;
    final batch = _db.batch();
    for (final id in challengeIds) {
      batch.delete(_db.collection('friendChallenges').doc(id));
    }
    await batch.commit();
  }
}
