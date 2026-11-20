import 'package:cloud_firestore/cloud_firestore.dart';

import '../game_engine.dart';

/// Immutable domain model representing a multiplayer Tic-Tac-Toe room.
class GameRoom {
  const GameRoom({
    required this.code,
    required this.hostId,
    required this.guestId,
    required this.hostName,
    required this.guestName,
    required this.hostEmoji,
    required this.guestEmoji,
    required this.size,
    required this.bestOf,
    required this.status,
    required this.board,
    required this.turn,
    required this.round,
    required this.roundDone,
    required this.hostWins,
    required this.guestWins,
    required this.draws,
    required this.lastResult,
    required this.champion,
  });

  final String code;
  final String hostId;
  final String guestId;
  final String hostName;
  final String guestName;
  final String hostEmoji;
  final String guestEmoji;
  final int size;
  final int bestOf;
  final String status;
  final List<String> board;
  final String turn;
  final int round;
  final bool roundDone;
  final int hostWins;
  final int guestWins;
  final int draws;
  final String lastResult;
  final String champion;

  factory GameRoom.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final size = (data['size'] as num?)?.toInt() ?? 3;
    final rawBoard = data['board'];
    final board = rawBoard is List
        ? rawBoard.map((e) => e?.toString() ?? '').toList(growable: false)
        : List<String>.filled(size * size, '', growable: false);

    return GameRoom(
      code: doc.id,
      hostId: data['hostId'] as String? ?? '',
      guestId: data['guestId'] as String? ?? '',
      hostName: data['hostName'] as String? ?? '',
      guestName: data['guestName'] as String? ?? '',
      hostEmoji: data['hostEmoji'] as String? ?? '❌',
      guestEmoji: data['guestEmoji'] as String? ?? '',
      size: size,
      bestOf: (data['bestOf'] as num?)?.toInt() ?? 3,
      status: data['status'] as String? ?? 'lobby',
      board: board,
      turn: data['turn'] as String? ?? 'h',
      round: (data['round'] as num?)?.toInt() ?? 1,
      roundDone: data['roundDone'] == true,
      hostWins: (data['hostWins'] as num?)?.toInt() ?? 0,
      guestWins: (data['guestWins'] as num?)?.toInt() ?? 0,
      draws: (data['draws'] as num?)?.toInt() ?? 0,
      lastResult: data['lastResult'] as String? ?? '',
      champion: data['champion'] as String? ?? '',
    );
  }

  bool get isLobby => status == 'lobby';
  bool get isPlaying => status == 'playing';
  bool get isFinished => status == 'finished';
  int get winsNeeded => GameEngine.winsNeeded(bestOf);
  WinResult? get winResult => GameEngine.evaluateWinner(board, size);

  String? sideForUid(String uid) {
    if (uid == hostId) return 'h';
    if (uid == guestId) return 'g';
    return null;
  }

  String playerName(String side) => side == 'h' ? hostName : guestName;

  String playerEmoji(String side) => side == 'h' ? hostEmoji : guestEmoji;

  String nameForUid(String uid) {
    if (uid == hostId) return hostName;
    if (uid == guestId) return guestName;
    return 'Player';
  }

  String emojiForUid(String uid) {
    if (uid == hostId) return hostEmoji;
    if (uid == guestId) return guestEmoji;
    return '💬';
  }
}
