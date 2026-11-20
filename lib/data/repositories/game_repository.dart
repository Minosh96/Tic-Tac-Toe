import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../domain/game_engine.dart';
import '../../domain/models/chat_message.dart';
import '../../domain/models/game_room.dart';
import '../../domain/models/room_reaction.dart';

/// Encapsulates Firebase Auth, Cloud Firestore, and Cloud Functions for rooms,
/// Blitz timing, Challenge Wheel agreement, reactions, and temporary chat.
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

  /// Ensures the player has an active anonymous Firebase session.
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

  /// Live stream of a room document mapped to a type-safe [GameRoom].
  Stream<GameRoom?> watchRoom(String code) {
    return _roomRef(code).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return GameRoom.fromFirestore(snap);
    });
  }

  /// Live stream of the latest 60 room chat messages (newest first).
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

  /// Live stream of recent room reactions & quick taunts (newest first).
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

  /// Creates a new multiplayer room with a collision-checked 6-character code.
  /// Preserves all v1 room fields while adding backwards-compatible v2 fields.
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

  /// Joins an existing lobby room as guest.
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

  /// Places the current player's mark at [cellIndex] atomically.
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

      // Enforce Blitz deadline cleanly before accepting move.
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
      await notifyMatchFinished(code);
    }
  }

  /// Idempotently resolves a Blitz 5-second move timeout.
  /// Attempts the trusted Cloud Function first and falls back to an atomic
  /// Firestore transaction if Cloud Functions are not deployed yet.
  Future<void> claimBlitzTimeout(String code, int expectedRound) async {
    try {
      final callable = _functions.httpsCallable('claimBlitzTimeout');
      await callable.call({'roomId': code, 'round': expectedRound});
      return;
    } catch (_) {
      // Fall back to atomic transaction when running on Spark without Functions.
    }

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
      await notifyMatchFinished(code);
    }
  }

  /// Advances the room to the next round after a win or draw.
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

  /// Starts a fresh best-of tournament rematch in the same room.
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

  /// Host proposes spinning the Random Challenge Wheel before Round 1 starts.
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

  /// Guest accepts the Challenge Wheel, atomically determining & locking the
  /// shared authoritative spin result once for both players.
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

      // Single authoritative random pick shared with both clients.
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

  /// Marks that the current player voluntarily left the room.
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
    } catch (_) {
      // Do not trap user on screen if offline when leaving.
    }
  }

  /// Sends a room-scoped live emoji reaction or quick taunt with spam cooldown.
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

  /// Sends a room chat message configured to expire after 24 hours.
  Future<void> sendChatMessage(String code, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.length > 280) return;
    final uid = currentUid;
    final snap = await _roomRef(code).get();
    final d = snap.data();
    if (d == null || (d['hostId'] != uid && d['guestId'] != uid)) {
      throw Exception('You are not a member of this room.');
    }
    await _roomRef(code).collection('messages').add({
      'uid': uid,
      'text': trimmed,
      'createdAt': FieldValue.serverTimestamp(),
      'expireAt': Timestamp.fromDate(
        DateTime.now().add(const Duration(hours: 24)),
      ),
    });
  }

  /// Calls the trusted `finalizeMatch` Cloud Function idempotently so server
  /// records verified stats, achievements, trophies, rivalries & leaderboards.
  Future<void> notifyMatchFinished(String code) async {
    try {
      final callable = _functions.httpsCallable('finalizeMatch');
      await callable.call({'roomId': code});
    } catch (_) {
      // Safe no-op if Cloud Functions are not yet deployed (e.g. Spark tier).
    }
  }
}
