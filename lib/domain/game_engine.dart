import 'dart:math';

/// Curated emoji marks players can pick for their board pieces.
const List<String> emojiChoices = [
  '❌',
  '⭕',
  '😎',
  '🤖',
  '🐱',
  '🐶',
  '🔥',
  '⭐',
  '🍕',
  '👑',
  '💎',
  '🚀',
];

/// Supported board dimensions (N×N).
const List<int> supportedBoardSizes = [3, 4, 5, 6];

/// Supported best-of tournament formats.
const List<int> supportedBestOf = [3, 5];

/// Blitz move timeout duration in seconds.
const int kBlitzTurnSeconds = 5;

/// Supported game modes.
enum GameMode {
  classic('classic', 'Classic', 'Untimed strategic rounds'),
  blitz('blitz', 'Blitz (5s)', '5 seconds per move — fast & intense!');

  const GameMode(this.id, this.label, this.description);
  final String id;
  final String label;
  final String description;

  static GameMode fromId(String? id) {
    return id == 'blitz' ? GameMode.blitz : GameMode.classic;
  }
}

/// Options on the Random Challenge Wheel.
enum ChallengeWheelOption {
  classic3(
    id: 'classic_3x3',
    label: 'Classic 3×3',
    emoji: '🎯',
    mode: GameMode.classic,
    boardSize: 3,
    shuffleEmojis: false,
  ),
  blitz3(
    id: 'blitz_3x3',
    label: 'Blitz 3×3',
    emoji: '⚡',
    mode: GameMode.blitz,
    boardSize: 3,
    shuffleEmojis: false,
  ),
  emojiShuffle(
    id: 'emoji_shuffle',
    label: 'Emoji Shuffle',
    emoji: '🎲',
    mode: GameMode.classic,
    boardSize: 3,
    shuffleEmojis: true,
  ),
  mega4(
    id: 'mega_4x4',
    label: 'Mega Board 4×4',
    emoji: '🧩',
    mode: GameMode.classic,
    boardSize: 4,
    shuffleEmojis: false,
  ),
  mega5(
    id: 'mega_5x5',
    label: 'Mega Board 5×5',
    emoji: '🔥',
    mode: GameMode.classic,
    boardSize: 5,
    shuffleEmojis: false,
  ),
  mega6(
    id: 'mega_6x6',
    label: 'Mega Board 6×6',
    emoji: '🚀',
    mode: GameMode.classic,
    boardSize: 6,
    shuffleEmojis: false,
  );

  const ChallengeWheelOption({
    required this.id,
    required this.label,
    required this.emoji,
    required this.mode,
    required this.boardSize,
    required this.shuffleEmojis,
  });

  final String id;
  final String label;
  final String emoji;
  final GameMode mode;
  final int boardSize;
  final bool shuffleEmojis;

  static ChallengeWheelOption? fromId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final option in values) {
      if (option.id == id) return option;
    }
    return null;
  }
}

/// Result of checking a board for a winning line.
class WinResult {
  const WinResult({required this.winner, required this.line});

  /// Winning side (`'h'` for host or `'g'` for guest).
  final String winner;

  /// Cell indices forming the winning horizontal, vertical, or diagonal line.
  final List<int> line;
}

/// Pure, testable Tic-Tac-Toe rules engine for N×N boards, Blitz, Wheel & social helpers.
class GameEngine {
  static const String _codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  /// Generates a 6-character room code avoiding ambiguous characters (0/O, 1/I).
  static String generateRoomCode([Random? random]) {
    final rng = random ?? Random.secure();
    return List.generate(
      6,
      (_) => _codeAlphabet[rng.nextInt(_codeAlphabet.length)],
    ).join();
  }

  /// Generates an 8-character shareable friend code (e.g., `MLW4K9P2`).
  static String generateFriendCode([Random? random]) {
    final rng = random ?? Random.secure();
    return List.generate(
      8,
      (_) => _codeAlphabet[rng.nextInt(_codeAlphabet.length)],
    ).join();
  }

  /// Validates a player's nickname (1-20 trimmed chars, safe printable characters).
  static String? validateNickname(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'Enter a nickname.';
    if (trimmed.length > 20) return 'Nickname must be 20 characters or fewer.';
    final valid = RegExp(r'^[\p{L}\p{N}_\-\. ]+$', unicode: true);
    if (!valid.hasMatch(trimmed)) {
      return 'Use letters, numbers, spaces, _, -, or . only.';
    }
    return null;
  }

  /// Picks two distinct emojis for Emoji Shuffle mode.
  static (String hostEmoji, String guestEmoji) pickShuffleEmojis([
    Random? random,
  ]) {
    final rng = random ?? Random.secure();
    final pool = List<String>.from(emojiChoices)..shuffle(rng);
    return (pool[0], pool[1]);
  }

  /// Deterministic rivalry document ID from two player UIDs.
  static String rivalryIdFor(String uidA, String uidB) {
    final sorted = [uidA, uidB]..sort();
    return '${sorted[0]}__${sorted[1]}';
  }

  /// Evaluates an N×N flattened [board] and returns a [WinResult] if either
  /// side has connected N marks in a straight row, column, or diagonal.
  static WinResult? evaluateWinner(List<String> board, int size) {
    if (size < 3 || board.length != size * size) return null;

    // Rows
    for (var row = 0; row < size; row++) {
      final start = row * size;
      final first = board[start];
      if (first.isEmpty) continue;
      final line = List<int>.generate(size, (col) => start + col);
      if (line.every((idx) => board[idx] == first)) {
        return WinResult(winner: first, line: line);
      }
    }

    // Columns
    for (var col = 0; col < size; col++) {
      final first = board[col];
      if (first.isEmpty) continue;
      final line = List<int>.generate(size, (row) => row * size + col);
      if (line.every((idx) => board[idx] == first)) {
        return WinResult(winner: first, line: line);
      }
    }

    // Main diagonal (top-left -> bottom-right)
    final d1 = board[0];
    if (d1.isNotEmpty) {
      final line = List<int>.generate(size, (i) => i * size + i);
      if (line.every((idx) => board[idx] == d1)) {
        return WinResult(winner: d1, line: line);
      }
    }

    // Anti-diagonal (top-right -> bottom-left)
    final d2 = board[size - 1];
    if (d2.isNotEmpty) {
      final line = List<int>.generate(size, (i) => i * size + (size - i - 1));
      if (line.every((idx) => board[idx] == d2)) {
        return WinResult(winner: d2, line: line);
      }
    }

    return null;
  }

  /// Returns true when the board is completely filled with no winner.
  static bool isDraw(List<String> board, int size) {
    return evaluateWinner(board, size) == null && !board.contains('');
  }

  /// Number of decisive round wins required to claim a best-of-[bestOf] cup.
  static int winsNeeded(int bestOf) => (bestOf ~/ 2) + 1;

  /// Returns `'h'`, `'g'`, or `''` when neither player has clinched the cup yet.
  static String computeChampion({
    required int hostWins,
    required int guestWins,
    required int bestOf,
  }) {
    final target = winsNeeded(bestOf);
    if (hostWins >= target) return 'h';
    if (guestWins >= target) return 'g';
    return '';
  }

  /// Starting player alternates every round: host starts odd rounds, guest even.
  static String startingTurnForRound(int round) => round.isOdd ? 'h' : 'g';

  /// Returns remaining Blitz duration using a deadline & optional server clock offset.
  static Duration remainingBlitzTime({
    required DateTime? deadline,
    required DateTime now,
    Duration serverOffset = Duration.zero,
  }) {
    if (deadline == null) return const Duration(seconds: kBlitzTurnSeconds);
    final adjustedNow = now.add(serverOffset);
    final diff = deadline.difference(adjustedNow);
    return diff.isNegative ? Duration.zero : diff;
  }

  /// Checks whether a Blitz turn has expired against [now] + [serverOffset].
  static bool isBlitzExpired({
    required DateTime? deadline,
    required DateTime now,
    Duration serverOffset = Duration.zero,
  }) {
    if (deadline == null) return false;
    return !now.add(serverOffset).isBefore(deadline);
  }
}
