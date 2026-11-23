import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../domain/achievements_catalog.dart';
import '../../domain/game_engine.dart';
import '../../domain/models/chat_message.dart';
import '../../domain/models/game_room.dart';
import '../../domain/models/room_reaction.dart';

/// Encapsulates Firebase Auth, Cloud Firestore, and Cloud Functions for rooms,
/// Blitz timing, Challenge Wheel agreement, reactions, temporary chat, and
/// idempotent post-match Trophy/Achievement/Stats recording.
class GameRepository {
  GameRepository({
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

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;

  DateTime _lastReactionSentAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration reactionCooldown = Duration(milliseconds: 1500);
  final Map<String, Future<void>> _inFlightMatchRecordings =
      <String, Future<void>>{};

  Future<User> ensureSignedIn() async {
    final existing = _auth.currentUser;
    if (existing != null) return existing;
    final credential = await _auth.signInAnonymously();
    final user = credential.user;
    if (user == null) {
      throw StateError('Anonymous sign-in returned no user.');
    }
    return user;
  }

  String get currentUid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw StateError('Player is not signed in yet.');
    }
    return uid;
  }

  String? get maybeCurrentUid => _auth.currentUser?.uid;

  DocumentReference<Map<String, dynamic>> _roomRef(String code) =>
      _db.collection('rooms').doc(code);

  Stream<GameRoom?> watchRoom(String code) {
    return _roomRef(code).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return GameRoom.fromFirestore(snap);
    });
  }

  Stream<List<ChatMessage>> watchMessages(String code) {
    return _roomRef(code)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(60)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(ChatMessage.fromFirestore)
              .toList(growable: false),
        );
  }

  Stream<List<RoomReaction>> watchReactions(String code) {
    return _roomRef(code)
        .collection('reactions')
        .orderBy('createdAt', descending: true)
        .limit(12)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(RoomReaction.fromFirestore)
              .toList(growable: false),
        );
  }

  Future<String> createRoom({
    required String name,
    required String emoji,
    required int size,
    required int bestOf,
    GameMode gameMode = GameMode.classic,
    String hostAvatar = 'astro',
  }) async {
    final user = await ensureSignedIn();
    for (var attempt = 0; attempt < 8; attempt++) {
      final code = GameEngine.generateRoomCode();
      try {
        await _db.runTransaction((tx) async {
          final ref = _roomRef(code);
          final existing = await tx.get(ref);
          if (existing.exists) {
            throw StateError('Room-code collision');
          }
          tx.set(ref, {
            'hostId': user.uid,
            'guestId': '',
            'hostName': name,
            'guestName': '',
            'hostEmoji': emoji,
            'guestEmoji': '',
            'hostAvatar': hostAvatar,
            'guestAvatar': '',
            'size': size,
            'bestOf': bestOf,
            'gameMode': gameMode.id,
            'status': 'lobby',
            'board': List<String>.filled(size * size, ''),
            'turn': 'h',
            'round': 1,
            'roundDone': false,
            'hostWins': 0,
            'guestWins': 0,
            'draws': 0,
            'lastResult': '',
            'champion': '',
            'timeoutWinner': '',
            'hostLeft': false,
            'guestLeft': false,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            'expiresAt': Timestamp.fromDate(
              DateTime.now().add(const Duration(hours: 24)),
            ),
          });
        });
        return code;
      } on StateError catch (e) {
        if (e.message != 'Room-code collision') rethrow;
      }
    }
    throw Exception('Unable to generate a room code. Please try again.');
  }

  Future<void> joinRoom({
    required String code,
    required String name,
    required String emoji,
    String guestAvatar = 'fox',
  }) async {
    final user = await ensureSignedIn();
    final ref = _roomRef(code);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists || snap.data() == null) {
        throw Exception('Room not found. Double-check the 6-character code.');
      }
      final data = snap.data()!;
      if (data['status'] != 'lobby' ||
          (data['guestId'] as String? ?? '') != '') {
        throw Exception('This room is already full.');
      }
      if (data['hostId'] == user.uid) {
        throw Exception('You are already the host of this room.');
      }
      if (data['hostEmoji'] == emoji) {
        throw Exception(
          'Choose a different emoji from the host (${data['hostEmoji']}).',
        );
      }
      final isBlitz = data['gameMode'] == GameMode.blitz.id;
      final patch = <String, dynamic>{
        'guestId': user.uid,
        'guestName': name,
        'guestEmoji': emoji,
        'guestAvatar': guestAvatar,
        'status': 'playing',
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (isBlitz) {
        patch['turnStartedAt'] = FieldValue.serverTimestamp();
        patch['turnDeadlineAt'] = Timestamp.fromDate(
          DateTime.now().add(const Duration(seconds: kBlitzTurnSeconds)),
        );
      }
      tx.update(ref, patch);
    });
  }

  Future<void> playMove(String code, int cellIndex) async {
    final uid = currentUid;
    final ref = _roomRef(code);
    bool matchFinished = false;

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists || snap.data() == null) return;
      final d = snap.data()!;
      if (d['status'] != 'playing' || d['roundDone'] == true) return;
      final side = d['hostId'] == uid
          ? 'h'
          : d['guestId'] == uid
              ? 'g'
              : '';
      if (side.isEmpty || d['turn'] != side) return;

      final isBlitz = d['gameMode'] == GameMode.blitz.id;
      final deadlineRaw = d['turnDeadlineAt'];
      if (isBlitz &&
          deadlineRaw is Timestamp &&
          DateTime.now().isAfter(
            deadlineRaw.toDate().add(const Duration(milliseconds: 350)),
          )) {
        return;
      }

      final board = List<String>.from(d['board'] as List);
      if (cellIndex < 0 ||
          cellIndex >= board.length ||
          board[cellIndex].isNotEmpty) {
        return;
      }
      board[cellIndex] = side;
      final size = (d['size'] as num).toInt();
      final win = GameEngine.evaluateWinner(board, size);
      final isDraw = win == null && !board.contains('');

      final patch = <String, dynamic>{
        'board': board,
        'turn': side == 'h' ? 'g' : 'h',
        'timeoutWinner': '',
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (win != null || isDraw) {
        final hostWins =
            (d['hostWins'] as num).toInt() + (win?.winner == 'h' ? 1 : 0);
        final guestWins =
            (d['guestWins'] as num).toInt() + (win?.winner == 'g' ? 1 : 0);
        final draws = (d['draws'] as num).toInt() + (isDraw ? 1 : 0);
        final bestOf = (d['bestOf'] as num).toInt();
        final champion = GameEngine.computeChampion(
          hostWins: hostWins,
          guestWins: guestWins,
          bestOf: bestOf,
        );
        matchFinished = champion.isNotEmpty;
        patch.addAll({
          'roundDone': true,
          'lastResult': isDraw ? 'draw' : win!.winner,
          'hostWins': hostWins,
          'guestWins': guestWins,
          'draws': draws,
          'champion': champion,
          'status': matchFinished ? 'finished' : 'playing',
          'turnDeadlineAt': null,
        });
      } else if (isBlitz) {
        patch['turnStartedAt'] = FieldValue.serverTimestamp();
        patch['turnDeadlineAt'] = Timestamp.fromDate(
          DateTime.now().add(const Duration(seconds: kBlitzTurnSeconds)),
        );
      }

      tx.update(ref, patch);
    });

    if (matchFinished) {
      await _tryCloudFinalizeOrLocal(code);
    }
  }

  Future<void> claimBlitzTimeout(String code, int expectedRound) async {
    try {
      final callable = _functions.httpsCallable('claimBlitzTimeout');
      await callable.call({'roomId': code, 'round': expectedRound});
      return;
    } catch (_) {}

    final uid = currentUid;
    final ref = _roomRef(code);
    bool matchFinished = false;

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists || snap.data() == null) return;
      final d = snap.data()!;
      if (uid != d['hostId'] && uid != d['guestId']) return;
      if (d['gameMode'] != GameMode.blitz.id) return;
      if (d['status'] != 'playing' || d['roundDone'] == true) return;
      if ((d['round'] as num).toInt() != expectedRound) return;

      final deadlineRaw = d['turnDeadlineAt'];
      if (deadlineRaw is! Timestamp) return;
      if (DateTime.now().isBefore(deadlineRaw.toDate())) return;

      final timedOutSide = d['turn'] as String? ?? 'h';
      final winnerSide = timedOutSide == 'h' ? 'g' : 'h';
      final hostWins =
          (d['hostWins'] as num).toInt() + (winnerSide == 'h' ? 1 : 0);
      final guestWins =
          (d['guestWins'] as num).toInt() + (winnerSide == 'g' ? 1 : 0);
      final bestOf = (d['bestOf'] as num).toInt();
      final champion = GameEngine.computeChampion(
        hostWins: hostWins,
        guestWins: guestWins,
        bestOf: bestOf,
      );
      matchFinished = champion.isNotEmpty;

      tx.update(ref, {
        'roundDone': true,
        'lastResult': winnerSide,
        'timeoutWinner': winnerSide,
        'hostWins': hostWins,
        'guestWins': guestWins,
        'champion': champion,
        'status': matchFinished ? 'finished' : 'playing',
        'turnDeadlineAt': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    if (matchFinished) {
      await _tryCloudFinalizeOrLocal(code);
    }
  }

  /// Idempotently records completed tournament results (cups, trophies,
  /// achievements, stats, rivalries, match history, and leaderboard) for the
  /// signed-in player with in-memory deduplication so winning a cup NEVER
  /// triggers concurrent-transaction Firebase errors.
  Future<void> recordFinishedMatchForCurrentUser(GameRoom room) {
    if (!room.isFinished ||
        room.champion.isEmpty ||
        room.hostId.isEmpty ||
        room.guestId.isEmpty) {
      return Future<void>.value();
    }
    final myUid = maybeCurrentUid;
    if (myUid == null) return Future<void>.value();
    final mySide = room.sideForUid(myUid);
    if (mySide == null) return Future<void>.value();

    final matchId =
        '${room.code}__${room.hostWins}_${room.guestWins}_${room.draws}_${room.round}';
    final existing = _inFlightMatchRecordings[matchId];
    if (existing != null) return existing;

    final future = _doRecordFinishedMatch(
      room: room,
      myUid: myUid,
      mySide: mySide,
      matchId: matchId,
    ).whenComplete(() => _inFlightMatchRecordings.remove(matchId));
    _inFlightMatchRecordings[matchId] = future;
    return future;
  }

  Future<void> _doRecordFinishedMatch({
    required GameRoom room,
    required String myUid,
    required String mySide,
    required String matchId,
  }) async {
    final processedRef = _db
        .collection('users')
        .doc(myUid)
        .collection('processedMatches')
        .doc(matchId);

    try {
      final already = await processedRef.get();
      if (already.exists) return;
    } catch (_) {}

    final iWon = room.champion == mySide;
    final winnerUid = room.champion == 'h' ? room.hostId : room.guestId;
    final opponentUid = mySide == 'h' ? room.guestId : room.hostId;
    final wonCleanSweep = iWon &&
        ((mySide == 'h' && room.guestWins == 0) ||
            (mySide == 'g' && room.hostWins == 0));

    final statsRef = _db.collection('stats').doc(myUid);
    final userRef = _db.collection('users').doc(myUid);
    final leaderboardRef = _db.collection('leaderboardEntries').doc(myUid);
    final rivalryId = GameEngine.rivalryIdFor(room.hostId, room.guestId);
    final rivalryRef = _db.collection('rivalries').doc(rivalryId);
    final matchRef = _db.collection('matches').doc(matchId);

    int nextWins = 0;
    int nextTournaments = 0;
    int nextBlitzWins = 0;
    int nextMegaWins = 0;
    int nextRivalryTotal = 1;
    bool recordedOwnerStats = false;

    // Step 1: Owner-only atomic transaction (processedMatches + stats + Melow Cup trophy + leaderboard).
    // Kept separate from shared rivalry/match docs so opponent contention can never abort your cup!
    try {
      await _db.runTransaction((tx) async {
        final procSnap = await tx.get(processedRef);
        if (procSnap.exists) return;

        final statsSnap = await tx.get(statsRef);
        final userSnap = await tx.get(userRef);

        final prevStats = statsSnap.data() ?? const <String, dynamic>{};
        final userData = userSnap.data() ?? const <String, dynamic>{};

        final gamesPlayed =
            ((prevStats['gamesPlayed'] as num?)?.toInt() ?? 0) + 1;
        nextWins =
            ((prevStats['wins'] as num?)?.toInt() ?? 0) + (iWon ? 1 : 0);
        final losses =
            ((prevStats['losses'] as num?)?.toInt() ?? 0) + (iWon ? 0 : 1);
        final draws = (prevStats['draws'] as num?)?.toInt() ?? 0;
        nextTournaments =
            ((prevStats['tournamentsWon'] as num?)?.toInt() ?? 0) +
                (iWon ? 1 : 0);
        final currentStreak = iWon
            ? ((prevStats['currentStreak'] as num?)?.toInt() ?? 0) + 1
            : 0;
        final prevBest = (prevStats['bestStreak'] as num?)?.toInt() ?? 0;
        final bestStreak = currentStreak > prevBest ? currentStreak : prevBest;
        nextBlitzWins = ((prevStats['blitzWins'] as num?)?.toInt() ?? 0) +
            (iWon && room.isBlitz ? 1 : 0);
        nextMegaWins = ((prevStats['megaWins'] as num?)?.toInt() ?? 0) +
            (iWon && room.size >= 5 ? 1 : 0);
        final trophyCount =
            ((prevStats['trophyCount'] as num?)?.toInt() ?? 0) + (iWon ? 1 : 0);

        tx.set(processedRef, {
          'roomId': room.code,
          'processedAt': FieldValue.serverTimestamp(),
        });

        tx.set(statsRef, {
          'gamesPlayed': gamesPlayed,
          'wins': nextWins,
          'losses': losses,
          'draws': draws,
          'tournamentsWon': nextTournaments,
          'currentStreak': currentStreak,
          'bestStreak': bestStreak,
          'blitzWins': nextBlitzWins,
          'megaWins': nextMegaWins,
          'trophyCount': trophyCount,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        if (iWon) {
          final trophyId = 'cup_$matchId';
          tx.set(
            _db
                .collection('users')
                .doc(myUid)
                .collection('trophies')
                .doc(trophyId),
            {
              'trophyId': trophyId,
              'matchId': matchId,
              'roomId': room.code,
              'title':
                  'Melow Cup (${room.size}×${room.size} ${room.isBlitz ? 'Blitz' : 'Classic'})',
              'awardedAt': FieldValue.serverTimestamp(),
            },
          );
        }

        final rawNick =
            ((userData['nickname'] as String?) ?? room.playerName(mySide))
                .trim();
        final safeNick = rawNick.isEmpty
            ? 'Player'
            : (rawNick.length > 20 ? rawNick.substring(0, 20) : rawNick);
        final rawAvatar =
            ((userData['avatarId'] as String?) ?? room.playerAvatar(mySide))
                .trim();
        final safeAvatar = rawAvatar.isEmpty ? 'astro' : rawAvatar;

        tx.set(leaderboardRef, {
          'publicNickname': safeNick,
          'avatarId': safeAvatar,
          if (userData['photoBase64'] is String &&
              (userData['photoBase64'] as String).length <= 140000)
            'photoBase64': userData['photoBase64'],
          'wins': nextWins,
          'tournamentsWon': nextTournaments,
          'bestStreak': bestStreak,
          'blitzWins': nextBlitzWins,
          'optIn': userData['leaderboardOptIn'] != false,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        recordedOwnerStats = true;
      });
    } catch (_) {
      return;
    }

    if (!recordedOwnerStats) return;

    // Step 2: Shared match summary & rivalry stats (isolated so contention never affects cups/stats).
    try {
      await _db.runTransaction((tx) async {
        final rivalSnap = await tx.get(rivalryRef);
        final matchSnap = await tx.get(matchRef);
        final prevRival = rivalSnap.data() ?? const <String, dynamic>{};

        if (iWon && !matchSnap.exists) {
          tx.set(matchRef, {
            'roomId': room.code,
            'players': [room.hostId, room.guestId],
            'playerNames': {
              room.hostId: room.hostName,
              room.guestId: room.guestName,
            },
            'gameMode': room.gameMode.id,
            'boardSize': room.size,
            'hostWins': room.hostWins,
            'guestWins': room.guestWins,
            'draws': room.draws,
            'finalWinnerUid': winnerUid,
            'finalStatus': 'won',
            'completedAt': FieldValue.serverTimestamp(),
            'processedAt': FieldValue.serverTimestamp(),
          });

          final prevWinsMap = Map<String, dynamic>.from(
            prevRival['winsByPlayer'] as Map? ?? const {},
          );
          final hostRivalWins =
              ((prevWinsMap[room.hostId] as num?)?.toInt() ?? 0) +
                  (winnerUid == room.hostId ? 1 : 0);
          final guestRivalWins =
              ((prevWinsMap[room.guestId] as num?)?.toInt() ?? 0) +
                  (winnerUid == room.guestId ? 1 : 0);
          nextRivalryTotal =
              ((prevRival['totalMatches'] as num?)?.toInt() ?? 0) + 1;
          final prevStreakOwner =
              prevRival['currentStreakOwner'] as String? ?? '';
          final nextRivalStreak = prevStreakOwner == winnerUid
              ? ((prevRival['currentStreak'] as num?)?.toInt() ?? 0) + 1
              : 1;
          final prevRivalBest =
              (prevRival['bestStreak'] as num?)?.toInt() ?? 0;

          tx.set(rivalryRef, {
            'playerUids': [room.hostId, room.guestId]..sort(),
            'winsByPlayer': {
              room.hostId: hostRivalWins,
              room.guestId: guestRivalWins,
            },
            'draws': (prevRival['draws'] as num?)?.toInt() ?? 0,
            'totalMatches': nextRivalryTotal,
            'currentStreakOwner': winnerUid,
            'currentStreak': nextRivalStreak,
            'bestStreak': nextRivalStreak > prevRivalBest
                ? nextRivalStreak
                : prevRivalBest,
            'lastMatchAt': FieldValue.serverTimestamp(),
          });
        } else {
          nextRivalryTotal =
              ((prevRival['totalMatches'] as num?)?.toInt() ?? 0) +
                  (opponentUid.isNotEmpty ? 1 : 0);
        }
      });
    } catch (_) {}

    // Step 3: Update deterministic achievements progress & unlocks (preserving prior unlocks).
    try {
      final achCol = _db.collection('users').doc(myUid).collection('achievements');
      final existingSnap = await achCol.get();
      final existingUnlocked = <String>{
        for (final doc in existingSnap.docs)
          if (doc.data()['unlockedAt'] != null) doc.id,
      };

      final progressMap = AchievementEvaluator.computeProgress(
        AchievementEvaluationInput(
          totalWins: nextWins,
          tournamentsWon: nextTournaments,
          blitzWins: nextBlitzWins,
          megaWins: nextMegaWins,
          maxRivalryMatches: nextRivalryTotal,
          wonWithoutDroppingRound:
              wonCleanSweep || existingUnlocked.contains('perfect_match'),
          wonAfterTrailing: existingUnlocked.contains('comeback_king'),
        ),
      );

      final batch = _db.batch();
      for (final def in achievementsCatalog) {
        final prog = progressMap[def.id] ?? 0;
        final unlocked = prog >= def.target || existingUnlocked.contains(def.id);
        final payload = <String, dynamic>{
          'achievementId': def.id,
          'progress': unlocked ? def.target : prog,
          'verified': true,
        };
        if (unlocked && !existingUnlocked.contains(def.id)) {
          payload['unlockedAt'] = FieldValue.serverTimestamp();
        }
        batch.set(achCol.doc(def.id), payload, SetOptions(merge: true));
      }
      await batch.commit();
    } catch (_) {}
  }

  Future<void> _tryCloudFinalizeOrLocal(String code) async {
    try {
      final snap = await _roomRef(code).get();
      if (snap.exists && snap.data() != null) {
        await recordFinishedMatchForCurrentUser(GameRoom.fromFirestore(snap));
      }
    } catch (_) {}
  }

  Future<void> startNextRound(String code) async {
    final uid = currentUid;
    final ref = _roomRef(code);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists || snap.data() == null) return;
      final d = snap.data()!;
      if (uid != d['hostId'] && uid != d['guestId']) return;
      if (d['status'] != 'playing' ||
          d['roundDone'] != true ||
          d['champion'] != '') {
        return;
      }
      final nextRound = (d['round'] as num).toInt() + 1;
      final size = (d['size'] as num).toInt();
      final isBlitz = d['gameMode'] == GameMode.blitz.id;
      final patch = <String, dynamic>{
        'board': List<String>.filled(size * size, ''),
        'round': nextRound,
        'roundDone': false,
        'lastResult': '',
        'timeoutWinner': '',
        'turn': GameEngine.startingTurnForRound(nextRound),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (isBlitz) {
        patch['turnStartedAt'] = FieldValue.serverTimestamp();
        patch['turnDeadlineAt'] = Timestamp.fromDate(
          DateTime.now().add(const Duration(seconds: kBlitzTurnSeconds)),
        );
      }
      tx.update(ref, patch);
    });
  }

  Future<void> startRematch(String code) async {
    final uid = currentUid;
    final ref = _roomRef(code);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists || snap.data() == null) return;
      final d = snap.data()!;
      if (uid != d['hostId'] && uid != d['guestId']) return;
      if (d['status'] != 'finished') return;
      final size = (d['size'] as num).toInt();
      final isBlitz = d['gameMode'] == GameMode.blitz.id;
      final patch = <String, dynamic>{
        'board': List<String>.filled(size * size, ''),
        'turn': 'h',
        'round': 1,
        'roundDone': false,
        'lastResult': '',
        'timeoutWinner': '',
        'hostWins': 0,
        'guestWins': 0,
        'draws': 0,
        'champion': '',
        'status': 'playing',
        'wheelProposal': null,
        'wheelResult': null,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (isBlitz) {
        patch['turnStartedAt'] = FieldValue.serverTimestamp();
        patch['turnDeadlineAt'] = Timestamp.fromDate(
          DateTime.now().add(const Duration(seconds: kBlitzTurnSeconds)),
        );
      }
      tx.update(ref, patch);
    });
  }

  Future<void> proposeChallengeWheel(String code) async {
    final uid = currentUid;
    final ref = _roomRef(code);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists || snap.data() == null) return;
      final d = snap.data()!;
      if (d['hostId'] != uid) {
        throw Exception('Only the room host can propose the Challenge Wheel.');
      }
      if (d['status'] != 'playing' || (d['round'] as num).toInt() != 1) {
        throw Exception('Challenge Wheel is only available before Round 1.');
      }
      final board = List<String>.from(d['board'] as List);
      if (board.any((c) => c.isNotEmpty)) {
        throw Exception('Challenge Wheel cannot be used after moves begin.');
      }
      tx.update(ref, {
        'wheelProposal': const WheelProposal(
          proposedBy: 'h',
          hostAccepted: true,
          guestAccepted: false,
          status: 'pending',
        ).toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> respondChallengeWheel(String code, {required bool accept}) async {
    final uid = currentUid;
    final ref = _roomRef(code);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists || snap.data() == null) return;
      final d = snap.data()!;
      if (d['guestId'] != uid) return;
      final rawProp = d['wheelProposal'];
      if (rawProp is! Map<String, dynamic> || rawProp['status'] != 'pending') {
        return;
      }
      if (!accept) {
        tx.update(ref, {
          'wheelProposal': const WheelProposal(
            proposedBy: 'h',
            hostAccepted: true,
            guestAccepted: false,
            status: 'declined',
          ).toMap(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return;
      }

      final options = ChallengeWheelOption.values;
      final chosen =
          options[DateTime.now().microsecondsSinceEpoch % options.length];
      String hostEmoji = d['hostEmoji'] as String? ?? '❌';
      String guestEmoji = d['guestEmoji'] as String? ?? '⭕';
      if (chosen.shuffleEmojis) {
        final pair = GameEngine.pickShuffleEmojis();
        hostEmoji = pair.$1;
        guestEmoji = pair.$2;
      }

      final spinResult = WheelSpinResult(
        optionId: chosen.id,
        spinId: DateTime.now().millisecondsSinceEpoch.toString(),
        hostEmoji: hostEmoji,
        guestEmoji: guestEmoji,
      );

      final patch = <String, dynamic>{
        'wheelProposal': const WheelProposal(
          proposedBy: 'h',
          hostAccepted: true,
          guestAccepted: true,
          status: 'spun',
        ).toMap(),
        'wheelResult': spinResult.toMap(),
        'gameMode': chosen.mode.id,
        'size': chosen.boardSize,
        'board': List<String>.filled(chosen.boardSize * chosen.boardSize, ''),
        'hostEmoji': hostEmoji,
        'guestEmoji': guestEmoji,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (chosen.mode == GameMode.blitz) {
        patch['turnStartedAt'] = FieldValue.serverTimestamp();
        patch['turnDeadlineAt'] = Timestamp.fromDate(
          DateTime.now().add(const Duration(seconds: kBlitzTurnSeconds + 3)),
        );
      } else {
        patch['turnDeadlineAt'] = null;
      }

      tx.update(ref, patch);
    });
  }

  Future<void> leaveRoom(String code) async {
    final uid = maybeCurrentUid;
    if (uid == null) return;
    try {
      final ref = _roomRef(code);
      await _db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists || snap.data() == null) return;
        final d = snap.data()!;
        if (d['hostId'] == uid) {
          tx.update(ref, {
            'hostLeft': true,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else if (d['guestId'] == uid) {
          tx.update(ref, {
            'guestLeft': true,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });
    } catch (_) {}
  }

  Future<void> sendReaction({
    required String code,
    required String kind,
    required String payload,
  }) async {
    final now = DateTime.now();
    if (now.difference(_lastReactionSentAt) < reactionCooldown) {
      throw Exception('Slow down! Wait a moment before reacting again.');
    }
    if (kind == 'emoji' && !allowedReactionEmojis.contains(payload)) {
      throw Exception('Unsupported reaction.');
    }
    if (kind == 'taunt' && !allowedQuickTaunts.contains(payload)) {
      throw Exception('Unsupported taunt.');
    }
    final uid = currentUid;
    _lastReactionSentAt = now;
    await _roomRef(code).collection('reactions').add({
      'senderUid': uid,
      'kind': kind,
      'payload': payload,
      'createdAt': FieldValue.serverTimestamp(),
      'expireAt': Timestamp.fromDate(now.add(const Duration(minutes: 5))),
    });
  }

  Future<void> sendChatMessage(
    String code,
    String text, {
    String? imageBase64,
  }) async {
    final trimmed = text.trim();
    final hasImage = imageBase64 != null && imageBase64.isNotEmpty;
    if ((trimmed.isEmpty && !hasImage) || trimmed.length > 280) return;
    final uid = currentUid;
    final snap = await _roomRef(code).get();
    final d = snap.data();
    if (d == null || (d['hostId'] != uid && d['guestId'] != uid)) {
      throw Exception('You are not a member of this room.');
    }
    await _roomRef(code).collection('messages').add({
      'uid': uid,
      'text': trimmed,
      if (hasImage) 'imageBase64': imageBase64,
      'createdAt': FieldValue.serverTimestamp(),
      'expireAt': Timestamp.fromDate(
        DateTime.now().add(const Duration(hours: 24)),
      ),
    });
  }

  /// Clears all messages in the room chat subcollection.
  Future<void> clearRoomChatMessages(String code) async {
    try {
      final snap = await _roomRef(code).collection('messages').get();
      if (snap.docs.isEmpty) return;
      final batch = _db.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
    } catch (_) {}
  }
}
