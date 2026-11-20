enum AchievementTier {
  bronze('Bronze'),
  silver('Silver'),
  gold('Gold');

  const AchievementTier(this.label);
  final String label;
}

class AchievementDefinition {
  const AchievementDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.tier,
    required this.target,
  });

  final String id;
  final String title;
  final String description;
  final String icon;
  final AchievementTier tier;
  final int target;
}

/// Complete deterministic catalog of Melow Tic Tac Toe v2.0 achievements.
const List<AchievementDefinition> achievementsCatalog = [
  AchievementDefinition(
    id: 'first_victory',
    title: 'First Victory',
    description: 'Win 1 completed match.',
    icon: '🏅',
    tier: AchievementTier.bronze,
    target: 1,
  ),
  AchievementDefinition(
    id: 'rising_star',
    title: 'Rising Star',
    description: 'Win 5 completed matches.',
    icon: '⭐',
    tier: AchievementTier.bronze,
    target: 5,
  ),
  AchievementDefinition(
    id: 'tic_tac_master',
    title: 'Tic Tac Master',
    description: 'Win 25 completed matches.',
    icon: '👑',
    tier: AchievementTier.gold,
    target: 25,
  ),
  AchievementDefinition(
    id: 'champion',
    title: 'Champion',
    description: 'Win 1 Melow Cup tournament.',
    icon: '🏆',
    tier: AchievementTier.bronze,
    target: 1,
  ),
  AchievementDefinition(
    id: 'triple_champion',
    title: 'Triple Champion',
    description: 'Win 3 Melow Cup tournaments.',
    icon: '🥇',
    tier: AchievementTier.gold,
    target: 3,
  ),
  AchievementDefinition(
    id: 'perfect_match',
    title: 'Perfect Match',
    description: 'Win a tournament without losing a single round.',
    icon: '💎',
    tier: AchievementTier.silver,
    target: 1,
  ),
  AchievementDefinition(
    id: 'blitz_hero',
    title: 'Blitz Hero',
    description: 'Win 5 Blitz Mode matches.',
    icon: '⚡',
    tier: AchievementTier.silver,
    target: 5,
  ),
  AchievementDefinition(
    id: 'mega_strategist',
    title: 'Mega Strategist',
    description: 'Win 5 matches on 5×5 or larger boards.',
    icon: '🧠',
    tier: AchievementTier.silver,
    target: 5,
  ),
  AchievementDefinition(
    id: 'friendly_rival',
    title: 'Friendly Rival',
    description: 'Finish 10 matches against the same opponent.',
    icon: '🤝',
    tier: AchievementTier.silver,
    target: 10,
  ),
  AchievementDefinition(
    id: 'comeback_king',
    title: 'Comeback King',
    description: 'Win a tournament after trailing in rounds.',
    icon: '🔥',
    tier: AchievementTier.gold,
    target: 1,
  ),
];

class AchievementEvaluationInput {
  const AchievementEvaluationInput({
    required this.totalWins,
    required this.tournamentsWon,
    required this.blitzWins,
    required this.megaWins,
    required this.maxRivalryMatches,
    required this.wonWithoutDroppingRound,
    required this.wonAfterTrailing,
  });

  final int totalWins;
  final int tournamentsWon;
  final int blitzWins;
  final int megaWins;
  final int maxRivalryMatches;
  final bool wonWithoutDroppingRound;
  final bool wonAfterTrailing;
}

/// Deterministic achievement progress & eligibility calculator (mirrored in Cloud Functions).
class AchievementEvaluator {
  static Map<String, int> computeProgress(AchievementEvaluationInput input) {
    return {
      'first_victory': input.totalWins.clamp(0, 1),
      'rising_star': input.totalWins.clamp(0, 5),
      'tic_tac_master': input.totalWins.clamp(0, 25),
      'champion': input.tournamentsWon.clamp(0, 1),
      'triple_champion': input.tournamentsWon.clamp(0, 3),
      'perfect_match': input.wonWithoutDroppingRound ? 1 : 0,
      'blitz_hero': input.blitzWins.clamp(0, 5),
      'mega_strategist': input.megaWins.clamp(0, 5),
      'friendly_rival': input.maxRivalryMatches.clamp(0, 10),
      'comeback_king': input.wonAfterTrailing ? 1 : 0,
    };
  }

  static Set<String> eligibleIds(AchievementEvaluationInput input) {
    final progress = computeProgress(input);
    final unlocked = <String>{};
    for (final def in achievementsCatalog) {
      if ((progress[def.id] ?? 0) >= def.target) {
        unlocked.add(def.id);
      }
    }
    return unlocked;
  }
}
