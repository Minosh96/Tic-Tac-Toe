import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../domain/game_engine.dart';
import '../../domain/models/game_room.dart';
import '../../domain/models/group_models.dart';
import '../../domain/models/social_models.dart';
import '../../domain/models/user_profile.dart';
import 'friends_repository.dart';
import 'game_repository.dart';

/// Manages Friend Groups (up to 5 members added by Friend Code),
/// 2-player group matches, Final Match for the Melow Challenge Champion Cup,
/// Group Individual Rankings, Group Chat (with Clear for Me/Everyone & message delete/unsend),
/// and Leave / Remove Group.
class GroupRepository {
  GroupRepository({
    required this.gameRepository,
    required this.friendsRepository,
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

  final GameRepository gameRepository;
  final FriendsRepository friendsRepository;
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  final Map<String, DateTime> _localClearedAt = <String, DateTime>{};
  final Set<String> _deletedForMeMessageIds = <String>{};

  String get currentUid => _auth.currentUser?.uid ?? 'offline_player';

  DocumentReference<Map<String, dynamic>> _groupRef(String groupId) =>
      _db.collection('groups').doc(groupId);

  /// Streams all Friend Groups that [uid] is a member of.
  Stream<List<FriendGroup>> watchUserGroups(String uid) {
    if (uid.isEmpty || uid == 'offline_player') {
      return Stream.value(const <FriendGroup>[]);
    }
    return _db
        .collection('groups')
        .where('memberUids', arrayContains: uid)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map(FriendGroup.fromFirestore)
          .toList(growable: true);
      list.sort(
        (a, b) => (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
      );
      return list;
    });
  }

  /// Streams a single Friend Group live.
  Stream<FriendGroup?> watchGroup(String groupId) {
    return _groupRef(groupId).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return FriendGroup.fromFirestore(snap);
    });
  }

  /// Creates a new Friend Group using the creator's own Friend Code (`creator.friendCode`)
  /// so the creator simply enters a Group Name, chooses the maximum number of members (2..5),
  /// and shares their Friend Code for others to enter and join the group!
  Future<String> createGroupWithMyFriendCode({
    required UserProfile creator,
    required String groupName,
    required int maxMembers,
    String cupName = 'Melow Challenge Champion Cup',
  }) async {
    final cleanName = groupName.trim();
    if (cleanName.isEmpty || cleanName.length > 24) {
      throw Exception('Enter a group name (1–24 characters).');
    }
    final code = creator.friendCode.trim().toUpperCase();
    if (code.length < 6) {
      throw Exception('Your friend code is not ready yet. Please try again.');
    }
    final cap = maxMembers.clamp(2, FriendGroup.maxAllowedMembers);

    final docRef = _groupRef(code);
    await docRef.set({
      'name': cleanName,
      'creatorUid': creator.uid,
      'hostFriendCode': code,
      'maxMembers': cap,
      'memberUids': <String>[creator.uid],
      'memberNames': <String, String>{creator.uid: creator.nickname},
      'memberAvatars': <String, String>{creator.uid: creator.avatarId},
      'tournamentStatus': 'active',
      'championUid': '',
      'championName': '',
      'cupName': cupName,
      'winsByUid': <String, int>{creator.uid: 0},
      'lossesByUid': <String, int>{creator.uid: 0},
      'drawsByUid': <String, int>{creator.uid: 0},
      'cupsByUid': <String, int>{creator.uid: 0},
      'lastMessage':
          '🏆 Group "$cleanName" created! Share code $code for up to $cap players to join!',
      'lastSenderUid': creator.uid,
      'lastSenderName': creator.nickname,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  /// Joins an existing Friend Group using the host's shared Friend Code!
  Future<FriendGroup> joinGroupByFriendCode({
    required UserProfile me,
    required String friendCode,
  }) async {
    final code = friendCode.trim().toUpperCase();
    if (code.length < 6) {
      throw Exception('Enter a valid friend code to join the group.');
    }

    final ref = _groupRef(code);
    final snap = await ref.get();
    if (!snap.exists || snap.data() == null) {
      throw Exception(
        'No active group found for code "$code". Ask your friend to create a group with their code first!',
      );
    }

    final group = FriendGroup.fromFirestore(snap);
    if (group.memberUids.contains(me.uid)) {
      return group;
    }
    if (group.memberUids.length >= group.maxMembers) {
      throw Exception(
        'Group "${group.name}" is already full (${group.maxMembers}/${group.maxMembers} members).',
      );
    }

    await ref.update({
      'memberUids': FieldValue.arrayUnion([me.uid]),
      'memberNames.${me.uid}': me.nickname,
      'memberAvatars.${me.uid}': me.avatarId,
      'winsByUid.${me.uid}': 0,
      'lossesByUid.${me.uid}': 0,
      'drawsByUid.${me.uid}': 0,
      'cupsByUid.${me.uid}': 0,
      'lastMessage': '👋 ${me.nickname} joined the group!',
      'lastSenderUid': me.uid,
      'lastSenderName': me.nickname,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final updated = await ref.get();
    return FriendGroup.fromFirestore(updated);
  }

  /// Creates a new Friend Group of up to 5 members (including the creator)
  /// using the provided friend codes (legacy helper kept for compatibility).
  Future<String> createGroupByFriendCodes({
    required UserProfile creator,
    required String groupName,
    required List<String> friendCodes,
    String cupName = 'Melow Challenge Champion Cup',
  }) async {
    return createGroupWithMyFriendCode(
      creator: creator,
      groupName: groupName,
      maxMembers: (friendCodes.length + 1).clamp(2, 5),
      cupName: cupName,
    );
  }

  /// Adds a new member to an existing group by Friend Code (up to 5 members max).
  Future<UserProfile> addMemberByFriendCode({
    required String groupId,
    required String friendCode,
  }) async {
    final found =
        await friendsRepository.findUserByFriendCode(friendCode.trim());
    if (found == null) {
      throw Exception('No player found with friend code "$friendCode".');
    }

    final ref = _groupRef(groupId);
    final snap = await ref.get();
    if (!snap.exists || snap.data() == null) {
      throw Exception('Group no longer exists.');
    }
    final group = FriendGroup.fromFirestore(snap);
    if (group.memberUids.contains(found.uid)) {
      throw Exception('${found.nickname} is already in this group.');
    }
    if (group.memberUids.length >= group.maxMembers) {
      throw Exception(
        'Group already has the maximum of ${group.maxMembers} members.',
      );
    }

    await ref.update({
      'memberUids': FieldValue.arrayUnion([found.uid]),
      'memberNames.${found.uid}': found.nickname,
      'memberAvatars.${found.uid}': found.avatarId,
      'winsByUid.${found.uid}': 0,
      'lossesByUid.${found.uid}': 0,
      'drawsByUid.${found.uid}': 0,
      'cupsByUid.${found.uid}': 0,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return found;
  }

  /// Initiates a 2-player match inside the group (any member can initiate a regular
  /// challenge against any member, or the Final Match between the Top 2 ranked members).
  Future<String> initiateGroupMatch({
    required FriendGroup group,
    required UserProfile initiator,
    required String opponentUid,
    required GameMode mode,
    required int boardSize,
    required int bestOf,
    required bool isFinalMatch,
  }) async {
    if (!group.memberUids.contains(initiator.uid) ||
        !group.memberUids.contains(opponentUid)) {
      throw Exception('Both players must be members of this group.');
    }
    if (initiator.uid == opponentUid) {
      throw Exception('Choose another group member to challenge.');
    }

    final roomCode = await gameRepository.createRoom(
      name: initiator.nickname,
      emoji: initiator.preferredEmoji,
      size: boardSize,
      bestOf: bestOf,
      gameMode: mode,
      hostAvatar: initiator.avatarId,
    );

    final opponentName = group.memberNames[opponentUid] ?? 'Challenger';
    final activeMatch = GroupActiveMatch(
      roomId: roomCode,
      hostUid: initiator.uid,
      hostName: initiator.nickname,
      guestUid: opponentUid,
      guestName: opponentName,
      mode: mode.id,
      boardSize: boardSize,
      bestOf: bestOf,
      isFinalMatch: isFinalMatch,
      status: 'pending',
    );

    await _groupRef(group.id).update({
      'activeMatch': activeMatch.toMap(),
      'tournamentStatus': isFinalMatch ? 'final_ready' : 'active',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Also send a direct friendChallenge so the opponent gets a live notification bell alert!
    try {
      await friendsRepository.sendFriendChallenge(
        me: initiator,
        friendUid: opponentUid,
        friendName: opponentName,
        mode: mode,
        boardSize: boardSize,
        bestOf: bestOf,
        existingRoomId: roomCode,
      );
    } catch (_) {}

    return roomCode;
  }

  /// Joins the active 2-player group match room and synchronizes the match result
  /// back into the Group Individual Rankings when the match finishes.
  Future<void> syncGroupMatchResult({
    required String groupId,
    required GameRoom room,
    required bool isFinalMatch,
  }) async {
    if (!room.isFinished && !room.roundDone) return;
    if (!room.isFinished) return;

    final ref = _groupRef(groupId);
    final winnerUid = room.champion == 'h'
        ? room.hostId
        : (room.champion == 'g' ? room.guestId : '');
    final loserUid = room.champion == 'h'
        ? room.guestId
        : (room.champion == 'g' ? room.hostId : '');

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists || snap.data() == null) return;
      final group = FriendGroup.fromFirestore(snap);
      final active = group.activeMatch;
      if (active == null ||
          active.roomId != room.code ||
          active.status == 'finished') {
        return;
      }

      final wins = Map<String, int>.from(group.winsByUid);
      final losses = Map<String, int>.from(group.lossesByUid);
      final draws = Map<String, int>.from(group.drawsByUid);
      final cups = Map<String, int>.from(group.cupsByUid);

      if (winnerUid.isNotEmpty && loserUid.isNotEmpty) {
        wins[winnerUid] = (wins[winnerUid] ?? 0) + 1;
        losses[loserUid] = (losses[loserUid] ?? 0) + 1;
        if (isFinalMatch) {
          cups[winnerUid] = (cups[winnerUid] ?? 0) + 1;
        }
      } else {
        draws[room.hostId] = (draws[room.hostId] ?? 0) + 1;
        draws[room.guestId] = (draws[room.guestId] ?? 0) + 1;
      }

      final winnerName = winnerUid.isNotEmpty
          ? (group.memberNames[winnerUid] ?? room.playerName(room.champion))
          : '';

      final updatedMatch = GroupActiveMatch(
        roomId: active.roomId,
        hostUid: active.hostUid,
        hostName: active.hostName,
        guestUid: active.guestUid,
        guestName: active.guestName,
        mode: active.mode,
        boardSize: active.boardSize,
        bestOf: active.bestOf,
        isFinalMatch: isFinalMatch,
        status: 'finished',
        winnerUid: winnerUid,
        winnerName: winnerName,
      );

      final patch = <String, dynamic>{
        'activeMatch': updatedMatch.toMap(),
        'winsByUid': wins,
        'lossesByUid': losses,
        'drawsByUid': draws,
        'cupsByUid': cups,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (isFinalMatch && winnerUid.isNotEmpty) {
        patch['tournamentStatus'] = 'completed';
        patch['championUid'] = winnerUid;
        patch['championName'] = winnerName;
      }

      tx.update(ref, patch);
    });

    // Award the Melow Challenge Champion Cup trophy to the winner's Trophy Cabinet!
    if (isFinalMatch && winnerUid == currentUid) {
      try {
        final trophyId = 'group_cup_${groupId}_${room.code}';
        await _db
            .collection('users')
            .doc(currentUid)
            .collection('trophies')
            .doc(trophyId)
            .set({
          'trophyId': trophyId,
          'matchId': '${room.code}_group',
          'roomId': room.code,
          'title': 'Melow Challenge Champion Cup 🏆',
          'awardedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
    }
  }

  /// Starts a fresh Group Tournament season while keeping the group and members intact.
  Future<void> keepGroupAndStartNewTournament(String groupId) async {
    await _groupRef(groupId).update({
      'tournamentStatus': 'active',
      'championUid': '',
      'championName': '',
      'activeMatch': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Allows the current player to leave the group. If they are the last member,
  /// the group is removed.
  Future<void> leaveGroup(String groupId) async {
    final uid = currentUid;
    final ref = _groupRef(groupId);
    final snap = await ref.get();
    if (!snap.exists || snap.data() == null) return;
    final group = FriendGroup.fromFirestore(snap);
    final remaining =
        group.memberUids.where((m) => m != uid).toList(growable: false);
    if (remaining.isEmpty) {
      await deleteGroup(groupId);
      return;
    }
    await ref.update({
      'memberUids': remaining,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Removes/deletes the entire group and its chat messages.
  Future<void> deleteGroup(String groupId) async {
    final ref = _groupRef(groupId);
    try {
      final msgs = await ref.collection('messages').get();
      for (final doc in msgs.docs) {
        try {
          await doc.reference.delete();
        } catch (_) {}
      }
    } catch (_) {}
    await ref.delete();
  }

  // ===============================================================
  // Group Chat (Text, Gallery/Camera Photos, Clear for Me/Everyone,
  // Single-Message Delete for Me & Unsend/Delete for Everyone)
  // ===============================================================

  Stream<List<DirectChatMessage>> watchGroupMessages(String groupId) {
    return _groupRef(groupId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(80)
        .snapshots()
        .map((snap) {
      final uid = currentUid;
      final clearedAt = _localClearedAt[groupId];
      return snap.docs
          .map(DirectChatMessage.fromFirestore)
          .where((m) {
            if (_deletedForMeMessageIds.contains(m.id)) return false;
            if (uid.isNotEmpty && m.isDeletedFor(uid)) return false;
            if (clearedAt == null) return true;
            final created = m.createdAt;
            return created != null && created.isAfter(clearedAt);
          })
          .toList(growable: false);
    });
  }

  Future<void> sendGroupMessage({
    required String groupId,
    required String senderName,
    String text = '',
    String? imageBase64,
    String? msgType,
  }) async {
    final trimmed = text.trim();
    final hasImage = imageBase64 != null && imageBase64.isNotEmpty;
    if (trimmed.isEmpty && !hasImage) return;
    if (trimmed.length > 500) {
      throw Exception('Message is too long (max 500 characters).');
    }

    final meUid = currentUid;
    final ref = _groupRef(groupId);
    final effectiveType = msgType ?? (hasImage ? 'image' : 'text');
    final preview = trimmed.isNotEmpty ? trimmed : '📷 Shared an image';

    final batch = _db.batch();
    batch.set(ref.collection('messages').doc(), {
      'senderUid': meUid,
      'senderName': senderName,
      'text': trimmed,
      if (hasImage) 'imageBase64': imageBase64,
      'msgType': effectiveType,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(ref, {
      'lastMessage':
          preview.length > 120 ? preview.substring(0, 120) : preview,
      'lastSenderUid': meUid,
      'lastSenderName': senderName,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> clearGroupChatForMe(String groupId) async {
    final uid = currentUid;
    _localClearedAt[groupId] = DateTime.now();
    try {
      await _groupRef(groupId).update({
        'clearedAtBy.$uid': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Future<void> clearGroupChatForEveryone(String groupId) async {
    _localClearedAt[groupId] = DateTime.now();
    final ref = _groupRef(groupId);
    try {
      final snap = await ref.collection('messages').get();
      final batch = _db.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
    } catch (_) {}
    try {
      await ref.update({
        'lastMessage': '',
        'lastSenderUid': '',
        'lastSenderName': '',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Future<void> deleteGroupMessageForMe({
    required String groupId,
    required String messageId,
  }) async {
    final uid = currentUid;
    _deletedForMeMessageIds.add(messageId);
    try {
      await _groupRef(groupId).collection('messages').doc(messageId).update({
        'deletedFor': FieldValue.arrayUnion([uid]),
      });
    } catch (_) {}
  }

  Future<void> deleteGroupMessageForEveryone({
    required String groupId,
    required String messageId,
  }) async {
    _deletedForMeMessageIds.add(messageId);
    try {
      await _groupRef(groupId).collection('messages').doc(messageId).delete();
    } catch (_) {}
  }
}
