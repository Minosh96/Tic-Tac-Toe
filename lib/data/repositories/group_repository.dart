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

/// Manages Friend Groups (2 to 5 members joining via the host's Friend Code),
/// auto-generated tournament fixtures (`User1 vs User2`) with participant-only
/// Room Code & Play eligibility, Final Match for the Melow Challenge Champion Cup,
/// Champion & Runner-Up summary, Group Individual Rankings, and Group Chat.
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

  /// Generates all round-robin 1v1 fixtures for the current group members
  /// (preserving any existing fixture room codes or finished results!).
  static List<GroupFixture> buildFixturesForMembers({
    required List<String> memberUids,
    required Map<String, String> memberNames,
    required List<GroupFixture> existingFixtures,
  }) {
    if (memberUids.length < 2) return const <GroupFixture>[];

    final existingByPair = <String, GroupFixture>{};
    GroupFixture? existingFinal;
    for (final f in existingFixtures) {
      if (f.isFinalMatch) {
        existingFinal = f;
      } else {
        final pairKey = _pairKey(f.player1Uid, f.player2Uid);
        existingByPair[pairKey] = f;
      }
    }

    final result = <GroupFixture>[];
    int matchNum = 1;
    for (var i = 0; i < memberUids.length; i++) {
      for (var j = i + 1; j < memberUids.length; j++) {
        final u1 = memberUids[i];
        final u2 = memberUids[j];
        final key = _pairKey(u1, u2);
        final prev = existingByPair[key];
        if (prev != null) {
          result.add(
            GroupFixture(
              id: 'M$matchNum',
              matchNumber: matchNum,
              player1Uid: prev.player1Uid,
              player1Name:
                  memberNames[prev.player1Uid] ?? prev.player1Name,
              player2Uid: prev.player2Uid,
              player2Name:
                  memberNames[prev.player2Uid] ?? prev.player2Name,
              roomId: prev.roomId.isNotEmpty
                  ? prev.roomId
                  : GameEngine.generateRoomCode(),
              status: prev.status,
              winnerUid: prev.winnerUid,
              winnerName: prev.winnerName,
              resultText: prev.resultText,
              isFinalMatch: false,
            ),
          );
        } else {
          result.add(
            GroupFixture(
              id: 'M$matchNum',
              matchNumber: matchNum,
              player1Uid: u1,
              player1Name: memberNames[u1] ?? 'Player ${i + 1}',
              player2Uid: u2,
              player2Name: memberNames[u2] ?? 'Player ${j + 1}',
              roomId: GameEngine.generateRoomCode(),
              isFinalMatch: false,
            ),
          );
        }
        matchNum++;
      }
    }

    // If there are only 2 players in the group, Match 1 is itself the Championship Final!
    if (memberUids.length == 2 && result.length == 1) {
      final only = result.first;
      return [
        GroupFixture(
          id: 'FINAL',
          matchNumber: 1,
          player1Uid: only.player1Uid,
          player1Name: only.player1Name,
          player2Uid: only.player2Uid,
          player2Name: only.player2Name,
          roomId: only.roomId,
          status: only.status,
          winnerUid: only.winnerUid,
          winnerName: only.winnerName,
          resultText: only.resultText,
          isFinalMatch: true,
        ),
      ];
    }

    if (existingFinal != null) {
      result.add(
        GroupFixture(
          id: 'FINAL',
          matchNumber: matchNum,
          player1Uid: existingFinal.player1Uid,
          player1Name:
              memberNames[existingFinal.player1Uid] ?? existingFinal.player1Name,
          player2Uid: existingFinal.player2Uid,
          player2Name:
              memberNames[existingFinal.player2Uid] ?? existingFinal.player2Name,
          roomId: existingFinal.roomId,
          status: existingFinal.status,
          winnerUid: existingFinal.winnerUid,
          winnerName: existingFinal.winnerName,
          resultText: existingFinal.resultText,
          isFinalMatch: true,
        ),
      );
    }

    return result;
  }

  static String _pairKey(String a, String b) =>
      a.compareTo(b) <= 0 ? '${a}__$b' : '${b}__$a';

  /// Creates or resets a Friend Group using the creator's own Friend Code (`creator.friendCode`).
  /// Other members press "Join Group", enter this Friend Code, and join the group!
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
    var code = creator.friendCode.trim().toUpperCase();
    if (code.length < 6) {
      code = GameEngine.generateFriendCode();
    }
    final cap = maxMembers.clamp(2, FriendGroup.maxAllowedMembers);

    final docRef = _groupRef(code);
    // Clean up any old group doc under the same friend code before creating fresh
    try {
      final existing = await docRef.get();
      if (existing.exists) {
        await docRef.delete();
      }
    } catch (_) {}

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
      'runnerUpUid': '',
      'runnerUpName': '',
      'cupName': cupName,
      'fixtures': <Map<String, dynamic>>[],
      'winsByUid': <String, int>{creator.uid: 0},
      'lossesByUid': <String, int>{creator.uid: 0},
      'drawsByUid': <String, int>{creator.uid: 0},
      'cupsByUid': <String, int>{creator.uid: 0},
      'lastMessage':
          '🏆 Group "$cleanName" created! Share code $code so up to $cap members can join!',
      'lastSenderUid': creator.uid,
      'lastSenderName': creator.nickname,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  /// Joins an existing Friend Group using the host's shared Friend Code and
  /// automatically generates the tournament fixture cards (`User1 vs User2`)!
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

    final nextMembers = <String>[...group.memberUids, me.uid];
    final nextNames = Map<String, String>.from(group.memberNames)
      ..[me.uid] = me.nickname;
    final nextAvatars = Map<String, String>.from(group.memberAvatars)
      ..[me.uid] = me.avatarId;
    final nextWins = Map<String, int>.from(group.winsByUid)..[me.uid] = 0;
    final nextLosses = Map<String, int>.from(group.lossesByUid)..[me.uid] = 0;
    final nextDraws = Map<String, int>.from(group.drawsByUid)..[me.uid] = 0;
    final nextCups = Map<String, int>.from(group.cupsByUid)..[me.uid] = 0;

    final nextFixtures = buildFixturesForMembers(
      memberUids: nextMembers,
      memberNames: nextNames,
      existingFixtures: group.fixtures,
    );

    await ref.update({
      'memberUids': nextMembers,
      'memberNames': nextNames,
      'memberAvatars': nextAvatars,
      'winsByUid': nextWins,
      'lossesByUid': nextLosses,
      'drawsByUid': nextDraws,
      'cupsByUid': nextCups,
      'fixtures': nextFixtures.map((f) => f.toMap()).toList(growable: false),
      'lastMessage': '👋 ${me.nickname} joined the group!',
      'lastSenderUid': me.uid,
      'lastSenderName': me.nickname,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final updated = await ref.get();
    return FriendGroup.fromFirestore(updated);
  }

  /// Starts or joins a specific tournament fixture (`User1 vs User2`).
  /// Only the two participants (`fixture.player1Uid` or `fixture.player2Uid`) are eligible!
  Future<String> startOrJoinFixture({
    required FriendGroup group,
    required GroupFixture fixture,
    required UserProfile me,
    GameMode mode = GameMode.classic,
    int boardSize = 3,
    int bestOf = 3,
  }) async {
    if (!fixture.isParticipant(me.uid)) {
      throw Exception('Only ${fixture.player1Name} and ${fixture.player2Name} can play this match.');
    }

    // If a room code already exists for this fixture, join or rejoin it!
    if (fixture.roomId.isNotEmpty) {
      final roomSnap = await _db.collection('rooms').doc(fixture.roomId).get();
      if (roomSnap.exists && roomSnap.data() != null) {
        final d = roomSnap.data()!;
        final hostId = d['hostId'] as String? ?? '';
        final guestId = d['guestId'] as String? ?? '';
        if (me.uid == hostId || me.uid == guestId) {
          await gameRepository.markPlayerPresent(fixture.roomId);
        } else if (guestId.isEmpty) {
          final hostEmoji = d['hostEmoji'] as String? ?? '❌';
          final myEmoji = me.preferredEmoji == hostEmoji
              ? emojiChoices.firstWhere((e) => e != hostEmoji)
              : me.preferredEmoji;
          await gameRepository.joinRoom(
            code: fixture.roomId,
            name: me.nickname,
            emoji: myEmoji,
            guestAvatar: me.avatarId,
          );
        }
        return fixture.roomId;
      }
    }

    // Otherwise create the match room for this fixture using its assigned roomId!
    final roomCode = await gameRepository.createRoom(
      name: me.nickname,
      emoji: me.preferredEmoji,
      size: boardSize,
      bestOf: bestOf,
      gameMode: mode,
      hostAvatar: me.avatarId,
      preferredCode: fixture.roomId,
    );

    final opponentUid =
        fixture.player1Uid == me.uid ? fixture.player2Uid : fixture.player1Uid;
    final opponentName =
        fixture.player1Uid == me.uid ? fixture.player2Name : fixture.player1Name;

    final updatedFixtures = group.fixtures.map((f) {
      if (f.id == fixture.id) {
        return f.copyWith(
          roomId: roomCode,
          status: 'playing',
        );
      }
      return f;
    }).toList(growable: false);

    await _groupRef(group.id).update({
      'fixtures': updatedFixtures.map((f) => f.toMap()).toList(growable: false),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Send a direct challenge notification so the opponent gets a live Notification Bell alert!
    try {
      await friendsRepository.sendFriendChallenge(
        me: me,
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

  /// Synchronizes a completed fixture room back into the group's fixtures list,
  /// updates Group Individual Rankings, automatically creates the Final Match
  /// between the Top 2 players once all qualifying fixtures finish, and crowns
  /// the Champion 🥇 & Runner-Up 🥈 when the Final Match finishes!
  Future<void> syncFixtureResult({
    required String groupId,
    required String fixtureId,
    required GameRoom room,
  }) async {
    if (!room.isFinished) return;

    final ref = _groupRef(groupId);
    final winnerUid = room.champion == 'h'
        ? room.hostId
        : (room.champion == 'g' ? room.guestId : '');
    final loserUid = room.champion == 'h'
        ? room.guestId
        : (room.champion == 'g' ? room.hostId : '');

    bool crownedGroupChampion = false;

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists || snap.data() == null) return;
      final group = FriendGroup.fromFirestore(snap);

      final idx = group.fixtures.indexWhere((f) => f.id == fixtureId);
      if (idx < 0) return;
      final currentFixture = group.fixtures[idx];
      if (currentFixture.status == 'finished') return;

      final wins = Map<String, int>.from(group.winsByUid);
      final losses = Map<String, int>.from(group.lossesByUid);
      final draws = Map<String, int>.from(group.drawsByUid);
      final cups = Map<String, int>.from(group.cupsByUid);

      if (winnerUid.isNotEmpty && loserUid.isNotEmpty) {
        wins[winnerUid] = (wins[winnerUid] ?? 0) + 1;
        losses[loserUid] = (losses[loserUid] ?? 0) + 1;
      } else {
        draws[currentFixture.player1Uid] =
            (draws[currentFixture.player1Uid] ?? 0) + 1;
        draws[currentFixture.player2Uid] =
            (draws[currentFixture.player2Uid] ?? 0) + 1;
      }

      final winnerName = winnerUid.isNotEmpty
          ? (group.memberNames[winnerUid] ?? room.playerName(room.champion))
          : '';
      final loserName = loserUid.isNotEmpty
          ? (group.memberNames[loserUid] ?? '')
          : '';
      final scoreLabel = winnerName.isNotEmpty
          ? '$winnerName won (${room.hostWins} - ${room.guestWins})'
          : 'Draw (${room.hostWins} - ${room.guestWins})';

      final updatedFixtures = List<GroupFixture>.from(group.fixtures);
      updatedFixtures[idx] = currentFixture.copyWith(
        status: 'finished',
        winnerUid: winnerUid,
        winnerName: winnerName,
        resultText: scoreLabel,
      );

      // Compute temporary rankings to determine Top 2 for Final Match or final Champion/Runner-Up
      final tempGroup = FriendGroup(
        id: group.id,
        name: group.name,
        creatorUid: group.creatorUid,
        hostFriendCode: group.hostFriendCode,
        maxMembers: group.maxMembers,
        memberUids: group.memberUids,
        memberNames: group.memberNames,
        memberAvatars: group.memberAvatars,
        tournamentStatus: group.tournamentStatus,
        winsByUid: wins,
        lossesByUid: losses,
        drawsByUid: draws,
        cupsByUid: cups,
        fixtures: updatedFixtures,
      );
      final sortedRankings = tempGroup.rankings;

      String nextStatus = group.tournamentStatus;
      String nextChampUid = group.championUid;
      String nextChampName = group.championName;
      String nextRunnerUid = group.runnerUpUid;
      String nextRunnerName = group.runnerUpName;

      final regularFixtures =
          updatedFixtures.where((f) => !f.isFinalMatch).toList();
      final allRegularDone = regularFixtures.isNotEmpty &&
          regularFixtures.every((f) => f.status == 'finished');
      final hasFinalAlready = updatedFixtures.any((f) => f.isFinalMatch);

      if (currentFixture.isFinalMatch && winnerUid.isNotEmpty) {
        // Final Match completed -> Crown Champion & Runner-Up!
        cups[winnerUid] = (cups[winnerUid] ?? 0) + 1;
        nextStatus = 'completed';
        nextChampUid = winnerUid;
        nextChampName = winnerName;
        nextRunnerUid = loserUid;
        nextRunnerName = loserName.isNotEmpty
            ? loserName
            : (sortedRankings.length >= 2 ? sortedRankings[1].nickname : '');
        crownedGroupChampion = (winnerUid == currentUid);
      } else if (allRegularDone &&
          !hasFinalAlready &&
          sortedRankings.length >= 2) {
        // All qualifying fixtures finished -> Automatically add the FINAL MATCH fixture between Top 2!
        final top1 = sortedRankings[0];
        final top2 = sortedRankings[1];
        updatedFixtures.add(
          GroupFixture(
            id: 'FINAL',
            matchNumber: updatedFixtures.length + 1,
            player1Uid: top1.uid,
            player1Name: top1.nickname,
            player2Uid: top2.uid,
            player2Name: top2.nickname,
            roomId: GameEngine.generateRoomCode(),
            isFinalMatch: true,
          ),
        );
        nextStatus = 'final_ready';
      }

      tx.update(ref, {
        'fixtures':
            updatedFixtures.map((f) => f.toMap()).toList(growable: false),
        'winsByUid': wins,
        'lossesByUid': losses,
        'drawsByUid': draws,
        'cupsByUid': cups,
        'tournamentStatus': nextStatus,
        'championUid': nextChampUid,
        'championName': nextChampName,
        'runnerUpUid': nextRunnerUid,
        'runnerUpName': nextRunnerName,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    if (crownedGroupChampion) {
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

  /// Starts a fresh Group Tournament season with freshly generated fixtures while keeping the group intact.
  Future<void> keepGroupAndStartNewTournament(String groupId) async {
    final ref = _groupRef(groupId);
    final snap = await ref.get();
    if (!snap.exists || snap.data() == null) return;
    final group = FriendGroup.fromFirestore(snap);
    final freshFixtures = buildFixturesForMembers(
      memberUids: group.memberUids,
      memberNames: group.memberNames,
      existingFixtures: const <GroupFixture>[],
    );
    await ref.update({
      'tournamentStatus': 'active',
      'championUid': '',
      'championName': '',
      'runnerUpUid': '',
      'runnerUpName': '',
      'fixtures': freshFixtures.map((f) => f.toMap()).toList(growable: false),
      'activeMatch': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Allows the current player to leave the group.
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
    final updatedFixtures = buildFixturesForMembers(
      memberUids: remaining,
      memberNames: group.memberNames,
      existingFixtures: group.fixtures
          .where((f) => !f.isParticipant(uid))
          .toList(growable: false),
    );
    await ref.update({
      'memberUids': remaining,
      'fixtures': updatedFixtures.map((f) => f.toMap()).toList(growable: false),
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
  // Group Chat (Sender's name on every message, Text, Photos,
  // Clear for Me/Everyone, Delete for Me & Unsend for Everyone)
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
