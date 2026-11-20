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

/// Result of checking a board for a winning line.
class WinResult {
  const WinResult({required this.winner, required this.line});

  /// Winning side (`'h'` for host or `'g'` for guest).
  final String winner;

  /// Cell indices forming the winning horizontal, vertical, or diagonal line.
  final List<int> line;
}

/// Pure, testable Tic-Tac-Toe rules engine for N×N boards and tournaments.
class GameEngine {
  static const String _roomCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  /// Generates a 6-character room code avoiding ambiguous characters (0/O, 1/I).
  static String generateRoomCode([Random? random]) {
    final rng = random ?? Random.secure();
    return List.generate(
      6,
      (_) => _roomCodeAlphabet[rng.nextInt(_roomCodeAlphabet.length)],
    ).join();
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
}
