import 'package:cloud_firestore/cloud_firestore.dart';

import '../game_engine.dart';

/// Tracks host proposal & guest acceptance for the Random Challenge Wheel.
class WheelProposal {
  const WheelProposal({
    required this.proposedBy,
    required this.hostAccepted,
    required this.guestAccepted,
    required this.status,
  });

  final String proposedBy;
  final bool hostAccepted;
  final bool guestAccepted;
  final String status; // 'pending' | 'accepted' | 'declined' | 'spun'

  factory WheelProposal.fromMap(Map<String, dynamic> map) {
    return WheelProposal(
      proposedBy: map['proposedBy'] as String? ?? '',
      hostAccepted: map['hostAccepted'] == true,
      guestAccepted: map['guestAccepted'] == true,
      status: map['status'] as String? ?? 'pending',
    );
  }

  Map<String, dynamic> toMap() => {
        'proposedBy': proposedBy,
        'hostAccepted': hostAccepted,
        'guestAccepted': guestAccepted,
        'status': status,
      };

  bool get bothAccepted => hostAccepted && guestAccepted;
}

/// Authoritative single spin outcome shared by both players.
class WheelSpinResult {
  const WheelSpinResult({
    required this.optionId,
    required this.spinId,
    required this.hostEmoji,
    required this.guestEmoji,
  });

  final String optionId;
  final String spinId;
  final String hostEmoji;
  final String guestEmoji;

  ChallengeWheelOption? get option => ChallengeWheelOption.fromId(optionId);

  factory WheelSpinResult.fromMap(Map<String, dynamic> map) {
    final h = GameEngine.sanitizeEmoji(
      map['hostEmoji'] as String?,
      fallback: '❌',
    );
    final g = GameEngine.sanitizeEmoji(
      map['guestEmoji'] as String?,
      fallback: '⭕',
      avoidSameAs: h,
    );
    return WheelSpinResult(
      optionId: map['optionId'] as String? ?? '',
      spinId: map['spinId'] as String? ?? '',
      hostEmoji: h,
      guestEmoji: g,
    );
  }

  Map<String, dynamic> toMap() => {
        'optionId': optionId,
        'spinId': spinId,
        'hostEmoji': hostEmoji,
        'guestEmoji': guestEmoji,
      };
}

/// Immutable domain model representing a multiplayer Tic-Tac-Toe room.
/// 100% backwards-compatible with v1 Firestore room documents.
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
    this.gameMode = GameMode.classic,
    this.hostAvatar = 'astro',
    this.guestAvatar = 'fox',
    this.turnStartedAt,
    this.turnDeadlineAt,
    this.timeoutWinner = '',
    this.wheelProposal,
    this.wheelResult,
    this.hostLeft = false,
    this.guestLeft = false,
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

  // v2 optional backwards-compatible fields
  final GameMode gameMode;
  final String hostAvatar;
  final String guestAvatar;
  final DateTime? turnStartedAt;
  final DateTime? turnDeadlineAt;
  final String timeoutWinner;
  final WheelProposal? wheelProposal;
  final WheelSpinResult? wheelResult;
  final bool hostLeft;
  final bool guestLeft;

  factory GameRoom.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final size = (data['size'] as num?)?.toInt() ?? 3;
    final rawBoard = data['board'];
    final board = rawBoard is List
        ? rawBoard.map((e) => e?.toString() ?? '').toList(growable: false)
        : List<String>.filled(size * size, '', growable: false);

    DateTime? parseTs(Object? v) => v is Timestamp ? v.toDate() : null;

    final rawProposal = data['wheelProposal'];
    final rawWheelResult = data['wheelResult'];

    final safeHostEmoji = GameEngine.sanitizeEmoji(
      data['hostEmoji'] as String?,
      fallback: '❌',
    );
    final rawGuestEmoji = (data['guestEmoji'] as String?)?.trim() ?? '';
    final safeGuestEmoji = rawGuestEmoji.isEmpty
        ? ''
        : GameEngine.sanitizeEmoji(
            rawGuestEmoji,
            fallback: '⭕',
            avoidSameAs: safeHostEmoji,
          );

    return GameRoom(
      code: doc.id,
      hostId: data['hostId'] as String? ?? '',
      guestId: data['guestId'] as String? ?? '',
      hostName: data['hostName'] as String? ?? '',
      guestName: data['guestName'] as String? ?? '',
      hostEmoji: safeHostEmoji,
      guestEmoji: safeGuestEmoji,
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
      gameMode: GameMode.fromId(data['gameMode'] as String?),
      hostAvatar: data['hostAvatar'] as String? ?? 'astro',
      guestAvatar: data['guestAvatar'] as String? ?? 'fox',
      turnStartedAt: parseTs(data['turnStartedAt']),
      turnDeadlineAt: parseTs(data['turnDeadlineAt']),
      timeoutWinner: data['timeoutWinner'] as String? ?? '',
      wheelProposal: rawProposal is Map<String, dynamic>
          ? WheelProposal.fromMap(rawProposal)
          : null,
      wheelResult: rawWheelResult is Map<String, dynamic>
          ? WheelSpinResult.fromMap(rawWheelResult)
          : null,
      hostLeft: data['hostLeft'] == true,
      guestLeft: data['guestLeft'] == true,
    );
  }

  bool get isLobby => status == 'lobby';
  bool get isPlaying => status == 'playing';
  bool get isFinished => status == 'finished';
  bool get isBlitz => gameMode == GameMode.blitz;
  bool get hasAnyMoves => board.any((cell) => cell.isNotEmpty);
  bool get canUseChallengeWheel =>
      isPlaying &&
      round == 1 &&
      !roundDone &&
      !hasAnyMoves &&
      hostWins == 0 &&
      guestWins == 0 &&
      draws == 0 &&
      wheelResult == null;

  int get winsNeeded => GameEngine.winsNeeded(bestOf);
  WinResult? get winResult => GameEngine.evaluateWinner(board, size);

  String? sideForUid(String uid) {
    if (uid == hostId) return 'h';
    if (uid == guestId) return 'g';
    return null;
  }

  String playerName(String side) => side == 'h' ? hostName : guestName;
  String playerEmoji(String side) => side == 'h' ? hostEmoji : guestEmoji;
  String playerAvatar(String side) => side == 'h' ? hostAvatar : guestAvatar;

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
