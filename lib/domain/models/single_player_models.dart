import '../achievements_catalog.dart';
import '../bot_engine.dart';

/// Per-difficulty win/loss/draw statistics for Single Player mode.
class DifficultyStats {
  const DifficultyStats({
    this.games = 0,
    this.wins = 0,
    this.losses = 0,
    this.draws = 0,
  });

  final int games;
  final int wins;
  final int losses;
  final int draws;

  double get winRate => games == 0 ? 0.0 : (wins / games) * 100.0;

  DifficultyStats copyWith({
    int? games,
    int? wins,
    int? losses,
    int? draws,
  }) {
    return DifficultyStats(
      games: games ?? this.games,
      wins: wins ?? this.wins,
      losses: losses ?? this.losses,
      draws: draws ?? this.draws,
    );
  }

  Map<String, dynamic> toMap() => {
        'games': games,
        'wins': wins,
        'losses': losses,
        'draws': draws,
      };

  factory DifficultyStats.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const DifficultyStats();
    return DifficultyStats(
      games: (map['games'] as num?)?.toInt() ?? 0,
      wins: (map['wins'] as num?)?.toInt() ?? 0,
      losses: (map['losses'] as num?)?.toInt() ?? 0,
      draws: (map['draws'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Record of a completed Single Player game or tournament.
class SinglePlayerMatchRecord {
  const SinglePlayerMatchRecord({
    required this.id,
    required this.difficulty,
    required this.mode,
    required this.boardSize,
    required this.bestOf,
    required this.playerScore,
    required this.botScore,
    required this.draws,
    required this.outcome,
    required this.wonCup,
    required this.playedAt,
  });

  final String id;
  final String difficulty; // 'easy' | 'normal' | 'hard' | 'impossible'
  final String mode; // 'classic' | 'tournament' | 'blitz'
  final int boardSize;
  final int bestOf;
  final int playerScore;
  final int botScore;
  final int draws;
  final String outcome; // 'win' | 'loss' | 'draw'
  final bool wonCup;
  final DateTime playedAt;

  int get systemScore => botScore;
  String get result => outcome;

  Map<String, dynamic> toMap() => {
        'id': id,
        'difficulty': difficulty,
        'mode': mode,
        'boardSize': boardSize,
        'bestOf': bestOf,
        'playerScore': playerScore,
        'botScore': botScore,
        'draws': draws,
        'outcome': outcome,
        'wonCup': wonCup,
        'playedAt': playedAt.toIso8601String(),
      };

  factory SinglePlayerMatchRecord.fromMap(Map<String, dynamic> map) {
    return SinglePlayerMatchRecord(
      id: map['id'] as String? ?? '',
      difficulty: map['difficulty'] as String? ?? 'normal',
      mode: map['mode'] as String? ?? 'classic',
      boardSize: (map['boardSize'] as num?)?.toInt() ?? 3,
      bestOf: (map['bestOf'] as num?)?.toInt() ?? 1,
      playerScore: (map['playerScore'] as num?)?.toInt() ?? 0,
      botScore: (map['botScore'] as num?)?.toInt() ?? 0,
      draws: (map['draws'] as num?)?.toInt() ?? 0,
      outcome: map['outcome'] as String? ?? 'draw',
      wonCup: map['wonCup'] == true,
      playedAt: DateTime.tryParse(map['playedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// Complete offline-first Single Player statistics, difficulty records,
/// solo achievements, and game history (never mixed with Global Top 100 rankings).
class SinglePlayerStats {
  const SinglePlayerStats({
    this.totalGames = 0,
    this.wins = 0,
    this.losses = 0,
    this.draws = 0,
    this.soloCups = 0,
    this.currentStreak = 0,
    this.bestStreak = 0,
    this.byDifficulty = const <String, DifficultyStats>{},
    this.history = const <SinglePlayerMatchRecord>[],
    this.achievementProgress = const <String, int>{},
    this.unlockedAchievements = const <String>{},
  });

  final int totalGames;
  final int wins;
  final int losses;
  final int draws;
  final int soloCups;
  final int currentStreak;
  final int bestStreak;
  final Map<String, DifficultyStats> byDifficulty;
  final List<SinglePlayerMatchRecord> history;
  final Map<String, int> achievementProgress;
  final Set<String> unlockedAchievements;

  double get winPercentage =>
      totalGames == 0 ? 0.0 : (wins / totalGames) * 100.0;

  DifficultyStats statsForDifficulty(BotDifficulty difficulty) =>
      byDifficulty[difficulty.id] ?? const DifficultyStats();

  DifficultyStats statsFor(BotDifficulty difficulty) =>
      statsForDifficulty(difficulty);

  bool isAchievementUnlocked(String id) => unlockedAchievements.contains(id);

  int progressForAchievement(String id) => achievementProgress[id] ?? 0;

  Map<String, dynamic> toMap() => {
        'totalGames': totalGames,
        'wins': wins,
        'losses': losses,
        'draws': draws,
        'soloCups': soloCups,
        'currentStreak': currentStreak,
        'bestStreak': bestStreak,
        'byDifficulty': {
          for (final entry in byDifficulty.entries)
            entry.key: entry.value.toMap(),
        },
        'history': history.map((h) => h.toMap()).toList(growable: false),
        'achievementProgress': achievementProgress,
        'unlockedAchievements': unlockedAchievements.toList(growable: false),
      };

  factory SinglePlayerStats.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const SinglePlayerStats();
    final rawDiff = map['byDifficulty'];
    final diffMap = <String, DifficultyStats>{};
    if (rawDiff is Map) {
      for (final entry in rawDiff.entries) {
        if (entry.value is Map) {
          diffMap[entry.key.toString()] = DifficultyStats.fromMap(
            Map<String, dynamic>.from(entry.value as Map),
          );
        }
      }
    }

    final rawHistory = map['history'];
    final histList = <SinglePlayerMatchRecord>[];
    if (rawHistory is List) {
      for (final item in rawHistory) {
        if (item is Map) {
          histList.add(
            SinglePlayerMatchRecord.fromMap(
              Map<String, dynamic>.from(item),
            ),
          );
        }
      }
    }

    final rawProg = map['achievementProgress'];
    final progMap = <String, int>{};
    if (rawProg is Map) {
      for (final entry in rawProg.entries) {
        progMap[entry.key.toString()] = (entry.value as num?)?.toInt() ?? 0;
      }
    }

    final rawUnlocked = map['unlockedAchievements'];
    final unlockedSet = <String>{};
    if (rawUnlocked is List) {
      for (final item in rawUnlocked) {
        unlockedSet.add(item.toString());
      }
    }

    return SinglePlayerStats(
      totalGames: (map['totalGames'] as num?)?.toInt() ?? 0,
      wins: (map['wins'] as num?)?.toInt() ?? 0,
      losses: (map['losses'] as num?)?.toInt() ?? 0,
      draws: (map['draws'] as num?)?.toInt() ?? 0,
      soloCups: (map['soloCups'] as num?)?.toInt() ?? 0,
      currentStreak: (map['currentStreak'] as num?)?.toInt() ?? 0,
      bestStreak: (map['bestStreak'] as num?)?.toInt() ?? 0,
      byDifficulty: diffMap,
      history: histList,
      achievementProgress: progMap,
      unlockedAchievements: unlockedSet,
    );
  }
}

/// Separate Solo Achievements catalog for Single Player mode.
const List<AchievementDefinition> soloAchievementsCatalog = [
  AchievementDefinition(
    id: 'first_solo_victory',
    title: 'First Solo Victory',
    description: 'Win your first Single Player game against the system.',
    icon: '🏅',
    tier: AchievementTier.bronze,
    target: 1,
  ),
  AchievementDefinition(
    id: 'easy_master',
    title: 'Easy Master',
    description: 'Win 3 Single Player games on Easy difficulty.',
    icon: '🌱',
    tier: AchievementTier.bronze,
    target: 3,
  ),
  AchievementDefinition(
    id: 'normal_master',
    title: 'Normal Master',
    description: 'Win 3 Single Player games on Normal difficulty.',
    icon: '⚔️',
    tier: AchievementTier.silver,
    target: 3,
  ),
  AchievementDefinition(
    id: 'hard_master',
    title: 'Hard Master',
    description: 'Win 3 Single Player games on Hard difficulty.',
    icon: '🧠',
    tier: AchievementTier.silver,
    target: 3,
  ),
  AchievementDefinition(
    id: 'impossible_draw',
    title: 'Impossible Draw',
    description: 'Hold the Impossible system AI to a draw (or win!).',
    icon: '🛡️',
    tier: AchievementTier.gold,
    target: 1,
  ),
  AchievementDefinition(
    id: 'five_consecutive_wins',
    title: 'Five Consecutive Wins',
    description: 'Reach a 5-game winning streak in Single Player mode.',
    icon: '🔥',
    tier: AchievementTier.silver,
    target: 5,
  ),
  AchievementDefinition(
    id: 'ten_solo_victories',
    title: 'Ten Solo Victories',
    description: 'Win 10 Single Player games across any difficulty.',
    icon: '⭐',
    tier: AchievementTier.gold,
    target: 10,
  ),
  AchievementDefinition(
    id: 'solo_tournament_champion',
    title: 'Solo Tournament Champion',
    description: 'Win a Best of 3, 5, or 7 Single Player Tournament Cup.',
    icon: '🏆',
    tier: AchievementTier.gold,
    target: 1,
  ),
];
