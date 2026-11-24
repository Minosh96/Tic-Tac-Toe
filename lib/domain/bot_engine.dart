import 'dart:isolate';
import 'dart:math';

import 'game_engine.dart';

/// Four difficulty levels for Single Player (Player vs System) mode.
enum BotDifficulty {
  easy(
    'easy',
    'Easy',
    '🌱',
    'Relaxed random legal moves — great for warming up',
  ),
  normal(
    'normal',
    'Normal',
    '⚔️',
    'Tactical rule-based AI that spots winning & blocking moves',
  ),
  hard(
    'hard',
    'Hard',
    '🧠',
    'Depth-limited Minimax with positional line evaluation',
  ),
  impossible(
    'impossible',
    'Impossible',
    '🤖',
    'Full Alpha-Beta Minimax on 3×3 • Master Heuristic on 4×4–6×6',
  );

  const BotDifficulty(this.id, this.label, this.icon, this.description);
  final String id;
  final String label;
  final String icon;
  final String description;

  String get badge => icon;

  /// Accurate board-size-specific label so larger boards do not falsely claim
  /// mathematically solved unbeatable play.
  String subtitleForSize(int boardSize) {
    if (this != BotDifficulty.impossible) return description;
    if (boardSize == 3) {
      return 'Unbeatable full Alpha-Beta Minimax search on 3×3';
    }
    return 'Optimized master heuristic search for $boardSize×$boardSize boards';
  }

  static BotDifficulty fromId(String? raw) {
    for (final d in values) {
      if (d.id == raw) return d;
    }
    return BotDifficulty.normal;
  }
}

/// Supported Single Player game modes.
enum SinglePlayerMode {
  classic('classic', 'Classic', 'Single match with optional Practice Hints & Undo'),
  tournament('tournament', 'Tournament', 'Multi-round series to win a Solo Cup 🏆'),
  blitz('blitz', 'Blitz (5s)', '5 seconds per move — fast tactical reflex test');

  const SinglePlayerMode(this.id, this.label, this.description);
  final String id;
  final String label;
  final String description;

  static SinglePlayerMode fromId(String? raw) {
    for (final m in values) {
      if (m.id == raw) return m;
    }
    return SinglePlayerMode.classic;
  }
}

/// Supported tournament lengths in Single Player mode.
const List<int> supportedSoloBestOf = [3, 5, 7];

/// Who makes the opening move in Single Player mode.
enum FirstPlayerChoice {
  player('player', 'Player First'),
  system('system', 'Bot First'),
  random('random', 'Random');

  const FirstPlayerChoice(this.id, this.label);
  final String id;
  final String label;

  static FirstPlayerChoice fromId(String? raw) {
    for (final c in values) {
      if (c.id == raw) return c;
    }
    return FirstPlayerChoice.player;
  }
}

/// Dedicated offline local BotEngine supporting Easy, Normal, Hard, and
/// Impossible difficulties across 3×3, 4×4, 5×5, and 6×6 boards.
class BotEngine {
  static final Map<int, List<List<int>>> _winningLinesCache =
      <int, List<List<int>>>{};

  /// Returns all N-in-a-row winning lines (rows, columns, 2 main diagonals) for an N×N board.
  static List<List<int>> winningLinesForSize(int size) {
    return _winningLinesCache.putIfAbsent(size, () {
      final lines = <List<int>>[];
      for (var r = 0; r < size; r++) {
        lines.add([for (var c = 0; c < size; c++) r * size + c]);
      }
      for (var c = 0; c < size; c++) {
        lines.add([for (var r = 0; r < size; r++) r * size + c]);
      }
      lines.add([for (var i = 0; i < size; i++) i * size + i]);
      lines.add([for (var i = 0; i < size; i++) i * size + (size - 1 - i)]);
      return lines;
    });
  }

  /// Returns all empty legal cell indices on [board].
  static List<int> legalMoves(List<String> board) {
    final moves = <int>[];
    for (var i = 0; i < board.length; i++) {
      if (board[i].isEmpty) moves.add(i);
    }
    return moves;
  }

  /// Synchronous bot move calculation (suitable for unit tests and fast calls).
  /// Returns `-1` if no legal moves exist or the board already has a winner.
  static int computeMove({
    required List<String> board,
    required int size,
    required BotDifficulty difficulty,
    String botMark = 'g',
    String humanMark = 'h',
    Random? random,
  }) {
    if (board.length != size * size) {
      throw ArgumentError('Board length (${board.length}) must equal size * size (${size * size}).');
    }
    if (GameEngine.evaluateWinner(board, size) != null) return -1;
    final empty = legalMoves(board);
    if (empty.isEmpty) return -1;
    if (empty.length == 1) return empty.first;

    final rng = random ?? Random();

    switch (difficulty) {
      case BotDifficulty.easy:
        return empty[rng.nextInt(empty.length)];
      case BotDifficulty.normal:
        return _computeNormalMove(
          board: board,
          size: size,
          empty: empty,
          botMark: botMark,
          humanMark: humanMark,
          rng: rng,
        );
      case BotDifficulty.hard:
        return _computeHardMove(
          board: board,
          size: size,
          empty: empty,
          botMark: botMark,
          humanMark: humanMark,
          rng: rng,
        );
      case BotDifficulty.impossible:
        return _computeImpossibleMove(
          board: board,
          size: size,
          empty: empty,
          botMark: botMark,
          humanMark: humanMark,
        );
    }
  }

  /// Runs computationally expensive searches (Hard / Impossible) in a background
  /// isolate so UI animations never drop frames.
  static Future<int> computeMoveAsync({
    required List<String> board,
    required int size,
    required BotDifficulty difficulty,
    String botMark = 'g',
    String humanMark = 'h',
  }) async {
    final copy = List<String>.from(board, growable: false);
    if (difficulty == BotDifficulty.easy ||
        difficulty == BotDifficulty.normal) {
      return computeMove(
        board: copy,
        size: size,
        difficulty: difficulty,
        botMark: botMark,
        humanMark: humanMark,
      );
    }
    return Isolate.run(
      () => computeMove(
        board: copy,
        size: size,
        difficulty: difficulty,
        botMark: botMark,
        humanMark: humanMark,
      ),
    );
  }

  /// Computes a tactical hint for [humanMark] in Practice Mode.
  static Future<int> computeHintAsync({
    required List<String> board,
    required int size,
    String humanMark = 'h',
    String botMark = 'g',
  }) {
    return computeMoveAsync(
      board: board,
      size: size,
      difficulty: BotDifficulty.impossible,
      botMark: humanMark,
      humanMark: botMark,
    );
  }

  /// Identifies an immediate 1-move win for [mark] if one exists.
  static int? findImmediateWinningMove(
    List<String> board,
    int size,
    String mark,
  ) {
    final lines = winningLinesForSize(size);
    for (final line in lines) {
      int markCount = 0;
      int? emptyIndex;
      for (final idx in line) {
        final cell = board[idx];
        if (cell == mark) {
          markCount++;
        } else if (cell.isEmpty) {
          emptyIndex = idx;
        }
      }
      if (markCount == size - 1 && emptyIndex != null) {
        return emptyIndex;
      }
    }
    return null;
  }

  static int _computeNormalMove({
    required List<String> board,
    required int size,
    required List<int> empty,
    required String botMark,
    required String humanMark,
    required Random rng,
  }) {
    // 1. Take immediate winning move.
    final winMove = findImmediateWinningMove(board, size, botMark);
    if (winMove != null) return winMove;

    // 2. Block opponent's immediate winning move.
    final blockMove = findImmediateWinningMove(board, size, humanMark);
    if (blockMove != null) return blockMove;

    // 3. Onlarger boards (size >= 4), block (size - 2) open double threats.
    if (size >= 4) {
      final urgentBlock = _findUrgentLineThreat(board, size, humanMark);
      if (urgentBlock != null) return urgentBlock;
    }

    // 4. Prefer center or strategic intersections, with slight variety.
    final centers = _centerIndices(size).where((i) => board[i].isEmpty).toList();
    if (centers.isNotEmpty && rng.nextDouble() < 0.75) {
      return centers[rng.nextInt(centers.length)];
    }

    final corners = _cornerIndices(size).where((i) => board[i].isEmpty).toList();
    if (corners.isNotEmpty && rng.nextDouble() < 0.65) {
      return corners[rng.nextInt(corners.length)];
    }

    return empty[rng.nextInt(empty.length)];
  }

  static int _computeHardMove({
    required List<String> board,
    required int size,
    required List<int> empty,
    required String botMark,
    required String humanMark,
    required Random rng,
  }) {
    // 1. Immediate win or block.
    final winMove = findImmediateWinningMove(board, size, botMark);
    if (winMove != null) return winMove;
    final blockMove = findImmediateWinningMove(board, size, humanMark);
    if (blockMove != null) return blockMove;

    // 2. Depth-limited Alpha-Beta Minimax with positional heuristic.
    final maxDepth = size == 3 ? 3 : 2;
    final work = List<String>.from(board);
    final candidates = _orderedCandidateMoves(
      work,
      size,
      botMark,
      humanMark,
      maxCandidates: size == 3 ? 9 : 10,
    );

    int bestMove = candidates.first;
    int bestScore = -1000000;

    for (final move in candidates) {
      work[move] = botMark;
      final score = _alphaBetaHeuristic(
        board: work,
        size: size,
        depth: 1,
        maxDepth: maxDepth,
        alpha: -1000000,
        beta: 1000000,
        maximizing: false,
        botMark: botMark,
        humanMark: humanMark,
        maxCandidates: size == 3 ? 9 : 8,
      );
      work[move] = '';
      if (score > bestScore) {
        bestScore = score;
        bestMove = move;
      }
    }
    return bestMove;
  }

  static int _computeImpossibleMove({
    required List<String> board,
    required int size,
    required List<int> empty,
    required String botMark,
    required String humanMark,
  }) {
    // 1. Immediate win or block on all board sizes.
    final winMove = findImmediateWinningMove(board, size, botMark);
    if (winMove != null) return winMove;
    final blockMove = findImmediateWinningMove(board, size, humanMark);
    if (blockMove != null) return blockMove;

    // 2. Standard 3×3: Full exhaustive Minimax with Alpha-Beta pruning (unbeatable!).
    if (size == 3) {
      if (empty.length == 9) return 4; // Optimal opening center move
      if (empty.length == 8) {
        // Optimal 2nd move response: take center if free, else top-left corner
        return board[4].isEmpty ? 4 : 0;
      }
      final work = List<String>.from(board);
      final ordered = _orderedCandidateMoves(
        work,
        3,
        botMark,
        humanMark,
        maxCandidates: 9,
      );
      int bestMove = ordered.first;
      int bestScore = -1000000;
      var alpha = -1000000;
      const beta = 1000000;

      for (final move in ordered) {
        work[move] = botMark;
        final score = _fullMinimax3x3(
          board: work,
          depth: 1,
          alpha: alpha,
          beta: beta,
          maximizing: false,
          botMark: botMark,
          humanMark: humanMark,
        );
        work[move] = '';
        if (score > bestScore) {
          bestScore = score;
          bestMove = move;
        }
        if (score > alpha) alpha = score;
      }
      return bestMove;
    }

    // 3. Larger boards (4×4, 5×5, 6×6): Deep move-ordered Alpha-Beta heuristic search.
    final maxDepth = size == 4 ? 4 : 3;
    final maxCandidates = size == 4 ? 10 : 9;
    final work = List<String>.from(board);
    final candidates = _orderedCandidateMoves(
      work,
      size,
      botMark,
      humanMark,
      maxCandidates: maxCandidates,
    );

    int bestMove = candidates.first;
    int bestScore = -1000000;
    var alpha = -1000000;
    const beta = 1000000;

    for (final move in candidates) {
      work[move] = botMark;
      final score = _alphaBetaHeuristic(
        board: work,
        size: size,
        depth: 1,
        maxDepth: maxDepth,
        alpha: alpha,
        beta: beta,
        maximizing: false,
        botMark: botMark,
        humanMark: humanMark,
        maxCandidates: maxCandidates,
      );
      work[move] = '';
      if (score > bestScore) {
        bestScore = score;
        bestMove = move;
      }
      if (score > alpha) alpha = score;
    }
    return bestMove;
  }

  /// Exhaustive Alpha-Beta Minimax for 3×3 boards.
  static int _fullMinimax3x3({
    required List<String> board,
    required int depth,
    required int alpha,
    required int beta,
    required bool maximizing,
    required String botMark,
    required String humanMark,
  }) {
    final win = GameEngine.evaluateWinner(board, 3);
    if (win != null) {
      return win.winner == botMark ? (1000 - depth) : (-1000 + depth);
    }

    final empty = legalMoves(board);
    if (empty.isEmpty) return 0;

    var a = alpha;
    var b = beta;

    if (maximizing) {
      var maxEval = -1000000;
      for (final move in empty) {
        board[move] = botMark;
        final eval = _fullMinimax3x3(
          board: board,
          depth: depth + 1,
          alpha: a,
          beta: b,
          maximizing: false,
          botMark: botMark,
          humanMark: humanMark,
        );
        board[move] = '';
        if (eval > maxEval) maxEval = eval;
        if (eval > a) a = eval;
        if (b <= a) break;
      }
      return maxEval;
    } else {
      var minEval = 1000000;
      for (final move in empty) {
        board[move] = humanMark;
        final eval = _fullMinimax3x3(
          board: board,
          depth: depth + 1,
          alpha: a,
          beta: b,
          maximizing: true,
          botMark: botMark,
          humanMark: humanMark,
        );
        board[move] = '';
        if (eval < minEval) minEval = eval;
        if (eval < b) b = eval;
        if (b <= a) break;
      }
      return minEval;
    }
  }

  /// Depth-limited Alpha-Beta Minimax with line-potential heuristic evaluation.
  static int _alphaBetaHeuristic({
    required List<String> board,
    required int size,
    required int depth,
    required int maxDepth,
    required int alpha,
    required int beta,
    required bool maximizing,
    required String botMark,
    required String humanMark,
    required int maxCandidates,
  }) {
    final win = GameEngine.evaluateWinner(board, size);
    if (win != null) {
      return win.winner == botMark ? (100000 - depth * 100) : (-100000 + depth * 100);
    }
    if (depth >= maxDepth) {
      return _evaluateBoardHeuristic(board, size, botMark, humanMark);
    }

    final candidates = _orderedCandidateMoves(
      board,
      size,
      maximizing ? botMark : humanMark,
      maximizing ? humanMark : botMark,
      maxCandidates: maxCandidates,
    );
    if (candidates.isEmpty) return 0;

    var a = alpha;
    var b = beta;

    if (maximizing) {
      var maxEval = -1000000;
      for (final move in candidates) {
        board[move] = botMark;
        final eval = _alphaBetaHeuristic(
          board: board,
          size: size,
          depth: depth + 1,
          maxDepth: maxDepth,
          alpha: a,
          beta: b,
          maximizing: false,
          botMark: botMark,
          humanMark: humanMark,
          maxCandidates: maxCandidates,
        );
        board[move] = '';
        if (eval > maxEval) maxEval = eval;
        if (eval > a) a = eval;
        if (b <= a) break;
      }
      return maxEval;
    } else {
      var minEval = 1000000;
      for (final move in candidates) {
        board[move] = humanMark;
        final eval = _alphaBetaHeuristic(
          board: board,
          size: size,
          depth: depth + 1,
          maxDepth: maxDepth,
          alpha: a,
          beta: b,
          maximizing: true,
          botMark: botMark,
          humanMark: humanMark,
          maxCandidates: maxCandidates,
        );
        board[move] = '';
        if (eval < minEval) minEval = eval;
        if (eval < b) b = eval;
        if (b <= a) break;
      }
      return minEval;
    }
  }

  /// Evaluates board advantage for [botMark] vs [humanMark] across all winning lines.
  static int _evaluateBoardHeuristic(
    List<String> board,
    int size,
    String botMark,
    String humanMark,
  ) {
    final lines = winningLinesForSize(size);
    var totalScore = 0;

    for (final line in lines) {
      var botCount = 0;
      var humanCount = 0;
      for (final idx in line) {
        final cell = board[idx];
        if (cell == botMark) {
          botCount++;
        } else if (cell == humanMark) {
          humanCount++;
        }
      }
      if (botCount > 0 && humanCount > 0) {
        // Blocked line — neither side can win on this line.
        continue;
      }
      if (botCount > 0) {
        totalScore += _lineWeight(botCount, size);
      } else if (humanCount > 0) {
        totalScore -= (_lineWeight(humanCount, size) * 12) ~/ 10;
      }
    }

    for (final center in _centerIndices(size)) {
      if (board[center] == botMark) {
        totalScore += 6;
      } else if (board[center] == humanMark) {
        totalScore -= 6;
      }
    }
    return totalScore;
  }

  static int _lineWeight(int count, int size) {
    if (count >= size) return 50000;
    if (count == size - 1) return 2500;
    if (count == size - 2) return 220;
    if (count == size - 3) return 35;
    return 8;
  }

  static int? _findUrgentLineThreat(
    List<String> board,
    int size,
    String targetMark,
  ) {
    final lines = winningLinesForSize(size);
    int? bestCell;
    int bestThreatCount = 0;
    for (final line in lines) {
      var targetCount = 0;
      var otherCount = 0;
      final empties = <int>[];
      for (final idx in line) {
        final cell = board[idx];
        if (cell == targetMark) {
          targetCount++;
        } else if (cell.isEmpty) {
          empties.add(idx);
        } else {
          otherCount++;
        }
      }
      if (otherCount == 0 &&
          targetCount >= size - 2 &&
          empties.isNotEmpty &&
          targetCount > bestThreatCount) {
        bestThreatCount = targetCount;
        bestCell = empties.first;
      }
    }
    return bestCell;
  }

  /// Orders legal moves by immediate tactical value so Alpha-Beta pruning
  /// explores the strongest moves first.
  static List<int> _orderedCandidateMoves(
    List<String> board,
    int size,
    String activeMark,
    String opponentMark, {
    required int maxCandidates,
  }) {
    final empty = legalMoves(board);
    if (empty.length <= 1) return empty;

    final lines = winningLinesForSize(size);
    final cellScores = List<int>.filled(size * size, 0);

    for (final c in _centerIndices(size)) {
      cellScores[c] += 15;
    }
    for (final c in _cornerIndices(size)) {
      cellScores[c] += 8;
    }

    for (final line in lines) {
      var activeCount = 0;
      var oppCount = 0;
      for (final idx in line) {
        final cell = board[idx];
        if (cell == activeMark) {
          activeCount++;
        } else if (cell == opponentMark) {
          oppCount++;
        }
      }
      for (final idx in line) {
        if (board[idx].isNotEmpty) continue;
        if (oppCount == 0) {
          cellScores[idx] += _lineWeight(activeCount + 1, size);
        }
        if (activeCount == 0) {
          cellScores[idx] += (_lineWeight(oppCount + 1, size) * 11) ~/ 10;
        }
      }
    }

    empty.sort((a, b) => cellScores[b].compareTo(cellScores[a]));
    if (empty.length > maxCandidates) {
      return empty.sublist(0, maxCandidates);
    }
    return empty;
  }

  static List<int> _centerIndices(int size) {
    if (size.isOdd) {
      final mid = size ~/ 2;
      return [mid * size + mid];
    }
    final m1 = (size ~/ 2) - 1;
    final m2 = size ~/ 2;
    return [
      m1 * size + m1,
      m1 * size + m2,
      m2 * size + m1,
      m2 * size + m2,
    ];
  }

  static List<int> _cornerIndices(int size) => [
        0,
        size - 1,
        (size - 1) * size,
        size * size - 1,
      ];
}
