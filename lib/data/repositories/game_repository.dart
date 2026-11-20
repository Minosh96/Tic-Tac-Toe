import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../domain/game_engine.dart';
import '../../domain/models/chat_message.dart';
import '../../domain/models/game_room.dart';

/// Encapsulates Firebase Auth and Cloud Firestore operations for game rooms.
class GameRepository {
  GameRepository({
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

  /// Creates a new multiplayer room with a collision-checked 6-character code.
  Future<String> createRoom({
    required String name,
    required String emoji,
    required int size,
    required int bestOf,
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
            'size': size,
            'bestOf': bestOf,
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
            'createdAt': FieldValue.serverTimestamp(),
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
  }) async {
    final user = await ensureSignedIn();
    final ref = _roomRef(code);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists || snap.data() == null) {
        throw Exception('Room not found. Double-check the 6-character code.');
      }
      final data = snap.data()!;
      if (data['status'] != 'lobby' || (data['guestId'] as String? ?? '') != '') {
        throw Exception('This room is already full.');
      }
      if (data['hostId'] == user.uid) {
        throw Exception('You are already the host of this room.');
      }
      if (data['hostEmoji'] == emoji) {
        throw Exception('Choose a different emoji from the host (${data['hostEmoji']}).');
      }
      tx.update(ref, {
        'guestId': user.uid,
        'guestName': name,
        'guestEmoji': emoji,
        'status': 'playing',
      });
    });
  }

  /// Places the current player's mark at [cellIndex] inside an atomic transaction.
  Future<void> playMove(String code, int cellIndex) async {
    final uid = currentUid;
    final ref = _roomRef(code);
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

      final board = List<String>.from(d['board'] as List);
      if (cellIndex < 0 || cellIndex >= board.length || board[cellIndex].isNotEmpty) {
        return;
      }
      board[cellIndex] = side;
      final size = (d['size'] as num).toInt();
      final win = GameEngine.evaluateWinner(board, size);
      final isDraw = win == null && !board.contains('');

      final patch = <String, dynamic>{
        'board': board,
        'turn': side == 'h' ? 'g' : 'h',
      };

      if (win != null || isDraw) {
        final hostWins = (d['hostWins'] as num).toInt() + (win?.winner == 'h' ? 1 : 0);
        final guestWins = (d['guestWins'] as num).toInt() + (win?.winner == 'g' ? 1 : 0);
        final draws = (d['draws'] as num).toInt() + (isDraw ? 1 : 0);
        final bestOf = (d['bestOf'] as num).toInt();
        final champion = GameEngine.computeChampion(
          hostWins: hostWins,
          guestWins: guestWins,
          bestOf: bestOf,
        );
        patch.addAll({
          'roundDone': true,
          'lastResult': isDraw ? 'draw' : win!.winner,
          'hostWins': hostWins,
          'guestWins': guestWins,
          'draws': draws,
          'champion': champion,
          'status': champion.isNotEmpty ? 'finished' : 'playing',
        });
      }

      tx.update(ref, patch);
    });
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
      if (d['status'] != 'playing' || d['roundDone'] != true || d['champion'] != '') {
        return;
      }
      final nextRound = (d['round'] as num).toInt() + 1;
      final size = (d['size'] as num).toInt();
      tx.update(ref, {
        'board': List<String>.filled(size * size, ''),
        'round': nextRound,
        'roundDone': false,
        'lastResult': '',
        'turn': GameEngine.startingTurnForRound(nextRound),
      });
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
      tx.update(ref, {
        'board': List<String>.filled(size * size, ''),
        'turn': 'h',
        'round': 1,
        'roundDone': false,
        'lastResult': '',
        'hostWins': 0,
        'guestWins': 0,
        'draws': 0,
        'champion': '',
        'status': 'playing',
      });
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
}
