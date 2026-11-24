import 'dart:math';

/// Categorized curated emoji marks — strictly universal Unicode 6.0–9.0 emojis
/// guaranteed to render cleanly on all Android devices (no missing-glyph boxes).
const Map<String, List<String>> emojiCategories = {
  'Classic': ['❌', '⭕', '🔥', '⭐', '⚡', '👑', '💎', '🚀', '🏆', '🎯', '💯', '❤️'],
  'People': [
    '👦', '👧', '👶', '👨', '👩', '🤴', '👸', '🤠', '💃', '🕺', '🎅', '👼',
    '👮', '👷', '💂', '🕵️', '👰', '👳', '🙋', '🙇', '🙌', '💪',
  ],
  'Funny': [
    '😂', '🤣', '😜', '😝', '😆', '😅', '😋', '😛', '🤑', '😱', '🤡', '💩',
    '👻', '👽', '👾', '🤖', '😈', '👹', '👺', '💀', '🙈', '🙉', '🙊', '🙄',
    '😏', '😤', '😴', '🤧', '😬', '😵', '😲', '🤓', '😎', '😹', '😻', '😼',
  ],
  'Animals': [
    '🐱', '🐶', '🦊', '🐼', '🐨', '🦁', '🐯', '🐸', '🐵', '🐔', '🐧', '🦄',
    '🐉', '🐻', '🐙', '🦈', '🐝', '🦋', '🐢', '🦉', '🐰', '🐬',
  ],
  'Fun': [
    '🍕', '🍔', '🌮', '🍩', '🍉', '🥑', '🍦', '🍿', '🎸', '⚽', '🏀', '💣',
    '🎉', '🎈', '🌈', '🔮', '🎮', '🕹️', '🎲', '💜', '💙', '🍀',
  ],
};

/// Flat list of all curated emoji marks players can choose for board pieces.
final List<String> emojiChoices = [
  for (final group in emojiCategories.values) ...group,
];

/// Fast lookup set of verified universal emojis.
final Set<String> _universalEmojiSet = Set<String>.from(emojiChoices);

/// Maps newer Unicode 11–15 / OEM-unsupported emojis to universal equivalents.
const Map<String, String> _legacyEmojiFallbacks = {
  '🩵': '💙',
  '🩷': '❤️',
  '🩶': '💜',
  '🫣': '🙈',
  '🥸': '😎',
  '🥷': '🤖',
  '🧑‍🚀': '🚀',
  '🦸‍♂️': '⚡',
  '🦸‍♀️': '⚡',
  '🧙‍♂️': '🔮',
  '🧙‍♀️': '🔮',
  '🧛': '👻',
  '🧜‍♀️': '🐬',
  '🧝': '👑',
  '🧒': '👦',
  '🧑': '👦',
  '🦥': '🐨',
  '🦝': '🦊',
  '🦖': '🐉',
  '🥶': '😱',
  '🥵': '🔥',
  '🥺': '😻',
  '🥴': '😜',
  '🥳': '🎉',
  '🤪': '😜',
  '🤯': '😱',
  '🤮': '😝',
  '🤭': '🙊',
};

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

  final String winner;
  final List<int> line;
}

/// Pure, testable Tic-Tac-Toe rules engine for N×N boards, Blitz, Wheel & social helpers.
class GameEngine {
  static const String _codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  static String generateRoomCode([Random? random]) {
    final rng = random ?? Random.secure();
    return List.generate(
      6,
      (_) => _codeAlphabet[rng.nextInt(_codeAlphabet.length)],
    ).join();
  }

  static String generateFriendCode([Random? random]) {
    final rng = random ?? Random.secure();
    return List.generate(
      8,
      (_) => _codeAlphabet[rng.nextInt(_codeAlphabet.length)],
    ).join();
  }

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

  /// Ensures an emoji mark is supported across all Android devices (preventing
  /// missing-glyph boxes `[X]` when a player on Android 14 plays with Android 10/11/12).
  static String sanitizeEmoji(
    String? raw, {
    String fallback = '❌',
    String? avoidSameAs,
  }) {
    final trimmed = raw?.trim() ?? '';
    String resolved;
    if (trimmed.isEmpty) {
      resolved = fallback;
    } else if (_universalEmojiSet.contains(trimmed)) {
      resolved = trimmed;
    } else if (_legacyEmojiFallbacks.containsKey(trimmed)) {
      resolved = _legacyEmojiFallbacks[trimmed]!;
    } else {
      resolved = fallback;
    }

    if (avoidSameAs != null && resolved == avoidSameAs) {
      for (final candidate in const ['⭕', '❌', '🔥', '⭐', '⚡', '👑']) {
        if (candidate != avoidSameAs) return candidate;
      }
    }
    return resolved;
  }

  static (String hostEmoji, String guestEmoji) pickShuffleEmojis([
    Random? random,
  ]) {
    final rng = random ?? Random.secure();
    final pool = List<String>.from(emojiChoices)..shuffle(rng);
    return (pool[0], pool[1]);
  }

  static String rivalryIdFor(String uidA, String uidB) {
    final sorted = [uidA, uidB]..sort();
    return '${sorted[0]}__${sorted[1]}';
  }

  static WinResult? evaluateWinner(List<String> board, int size) {
    if (size < 3 || board.length != size * size) return null;

    for (var row = 0; row < size; row++) {
      final start = row * size;
      final first = board[start];
      if (first.isEmpty) continue;
      final line = List<int>.generate(size, (col) => start + col);
      if (line.every((idx) => board[idx] == first)) {
        return WinResult(winner: first, line: line);
      }
    }

    for (var col = 0; col < size; col++) {
      final first = board[col];
      if (first.isEmpty) continue;
      final line = List<int>.generate(size, (row) => row * size + col);
      if (line.every((idx) => board[idx] == first)) {
        return WinResult(winner: first, line: line);
      }
    }

    final d1 = board[0];
    if (d1.isNotEmpty) {
      final line = List<int>.generate(size, (i) => i * size + i);
      if (line.every((idx) => board[idx] == d1)) {
        return WinResult(winner: d1, line: line);
      }
    }

    final d2 = board[size - 1];
    if (d2.isNotEmpty) {
      final line = List<int>.generate(size, (i) => i * size + (size - i - 1));
      if (line.every((idx) => board[idx] == d2)) {
        return WinResult(winner: d2, line: line);
      }
    }

    return null;
  }

  static bool isDraw(List<String> board, int size) {
    return evaluateWinner(board, size) == null && !board.contains('');
  }

  static int winsNeeded(int bestOf) => (bestOf ~/ 2) + 1;

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

  static String startingTurnForRound(int round) => round.isOdd ? 'h' : 'g';

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

  static bool isBlitzExpired({
    required DateTime? deadline,
    required DateTime now,
    Duration serverOffset = Duration.zero,
  }) {
    if (deadline == null) return false;
    return !now.add(serverOffset).isBefore(deadline);
  }
}
