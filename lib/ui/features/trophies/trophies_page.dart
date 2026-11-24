import 'package:flutter/material.dart';

import '../../../core/services/app_services.dart';
import '../../../domain/achievements_catalog.dart';
import '../../../domain/models/single_player_models.dart';
import '../../../domain/models/user_profile.dart';
import '../../core/app_theme.dart';
import '../../core/widgets/footer.dart';
import '../../core/widgets/notification_bell_button.dart';

/// Melow v3.7 Trophies & Achievements Cabinet clearly separating
/// Single Player Achievements and Multiplayer Achievements, and awarding
/// the Melow All-Challenge Cup, Melow Grand Challenge Cup, and Melow Grand Slam Cup
/// when all challenges are won!
class TrophiesPage extends StatefulWidget {
  const TrophiesPage({super.key, required this.services});

  final AppServices services;

  @override
  State<TrophiesPage> createState() => _TrophiesPageState();
}

class _TrophiesPageState extends State<TrophiesPage> {
  String _filter = 'all';

  Color _tierColor(AchievementTier tier) {
    switch (tier) {
      case AchievementTier.gold:
        return AppTheme.goldAccent;
      case AchievementTier.silver:
        return const Color(0xFF94A3B8);
      case AchievementTier.bronze:
        return const Color(0xFFD97706);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.services.game.currentUid;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trophies & Cups'),
        actions: [
          NotificationBellIconButton(services: widget.services),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<PlayerStats>(
          stream: widget.services.profile.watchStats(uid),
          builder: (context, statsSnap) {
            final stats = statsSnap.data ?? const PlayerStats();
            return StreamBuilder<List<UserTrophy>>(
              stream: widget.services.profile.watchTrophies(uid),
              builder: (context, trophySnap) {
                final trophies = trophySnap.data ?? const <UserTrophy>[];
                return StreamBuilder<List<UserAchievement>>(
                  stream: widget.services.profile.watchAchievements(uid),
                  builder: (context, achSnap) {
                    return ListenableBuilder(
                      listenable: widget.services.singlePlayer,
                      builder: (context, _) {
                        final solo = widget.services.singlePlayer.stats;
                        final soloMap =
                            widget.services.singlePlayer.achievements;
                        final multiMap = <String, UserAchievement>{
                          for (final a in (achSnap.data ??
                              const <UserAchievement>[]))
                            a.achievementId: a,
                        };

                        final soloUnlockedCount = soloMap.values
                            .where((a) => a.isUnlocked)
                            .length;
                        final multiUnlockedCount = multiMap.values
                            .where((a) => a.isUnlocked)
                            .length;

                        final allSoloWon = soloUnlockedCount >=
                            soloAchievementsCatalog.length;
                        final allMultiWon =
                            multiUnlockedCount >= achievementsCatalog.length;
                        final allGrandSlamWon = allSoloWon && allMultiWon;

                        final filteredSolo =
                            soloAchievementsCatalog.where((def) {
                          final unlocked =
                              soloMap[def.id]?.isUnlocked ?? false;
                          if (_filter == 'unlocked') return unlocked;
                          if (_filter == 'locked') return !unlocked;
                          return true;
                        }).toList(growable: false);

                        final filteredMulti = achievementsCatalog.where((def) {
                          final unlocked =
                              multiMap[def.id]?.isUnlocked ?? false;
                          if (_filter == 'unlocked') return unlocked;
                          if (_filter == 'locked') return !unlocked;
                          return true;
                        }).toList(growable: false);

                        final onlineCupCount =
                            trophies.length > stats.tournamentsWon
                                ? trophies.length
                                : stats.tournamentsWon;
                        final specialCupsWon = (allSoloWon ? 1 : 0) +
                            (allMultiWon ? 1 : 0) +
                            (allGrandSlamWon ? 1 : 0);
                        final totalCups =
                            onlineCupCount + solo.soloCups + specialCupsWon;

                        return Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 580),
                            child: ListView(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              children: [
                                // Cup & Achievement Header Summary
                                Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(18),
                                    child: Row(
                                      children: [
                                        const Text(
                                          '🏆',
                                          style: TextStyle(fontSize: 48),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '$totalCups Melow Cups Won',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleLarge
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w900,
                                                    ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Single Player: $soloUnlockedCount/${soloAchievementsCatalog.length} • Multiplayer: $multiUnlockedCount/${achievementsCatalog.length}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color: scheme.primary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                // Grand Challenge Cups Showcase (Awarded when all challenges are won!)
                                const Text(
                                  'Melow Championship Cups',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _GrandCupCard(
                                  title: 'Melow All-Challenge Cup',
                                  subtitle:
                                      'Win all ${soloAchievementsCatalog.length} Single Player challenges ($soloUnlockedCount/${soloAchievementsCatalog.length})',
                                  unlocked: allSoloWon,
                                  icon: '🏆',
                                ),
                                _GrandCupCard(
                                  title: 'Melow Grand Challenge Cup',
                                  subtitle:
                                      'Win all ${achievementsCatalog.length} Multiplayer challenges ($multiUnlockedCount/${achievementsCatalog.length})',
                                  unlocked: allMultiWon,
                                  icon: '👑',
                                ),
                                _GrandCupCard(
                                  title: 'Melow Grand Slam Cup',
                                  subtitle:
                                      'Win every Single Player and Multiplayer challenge in Melow Tic Tac Toe!',
                                  unlocked: allGrandSlamWon,
                                  icon: '🌟',
                                ),
                                // Won Online & Group Tournament Melow Cups Shelf
                                if (trophies.isNotEmpty) ...[
                                  const SizedBox(height: 14),
                                  const Text(
                                    'Your Won Tournament Cups',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  for (final t in trophies)
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 8),
                                      child: Card(
                                        color: AppTheme.goldAccent
                                            .withValues(alpha: 0.12),
                                        child: ListTile(
                                          leading: const Text(
                                            '🏆',
                                            style: TextStyle(fontSize: 30),
                                          ),
                                          title: Text(
                                            t.title,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          subtitle: Text(
                                            t.awardedAt != null
                                                ? 'Won on ${t.awardedAt!.toLocal().toString().substring(0, 10)}'
                                                : 'Verified Melow Cup',
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                                const SizedBox(height: 14),
                                SizedBox(
                                  width: double.infinity,
                                  child: SegmentedButton<String>(
                                    showSelectedIcon: false,
                                    segments: const [
                                      ButtonSegment(
                                        value: 'all',
                                        label: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text('All'),
                                        ),
                                      ),
                                      ButtonSegment(
                                        value: 'unlocked',
                                        label: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text('Unlocked'),
                                        ),
                                      ),
                                      ButtonSegment(
                                        value: 'locked',
                                        label: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text('Locked'),
                                        ),
                                      ),
                                    ],
                                    selected: {_filter},
                                    onSelectionChanged: (v) =>
                                        setState(() => _filter = v.first),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                // 1. Single Player Achievements Section
                                Row(
                                  children: [
                                    const Expanded(
                                      child: Text(
                                        'Single Player Achievements',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '$soloUnlockedCount / ${soloAchievementsCatalog.length} • 🏆 ${solo.soloCups} Cups',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.goldAccent,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                if (filteredSolo.isEmpty)
                                  Card(
                                    child: Padding(
                                      padding: const EdgeInsets.all(18),
                                      child: Text(
                                        _filter == 'unlocked'
                                            ? 'Play Single Player to unlock your first Solo achievement!'
                                            : 'All Single Player achievements unlocked — Melow All-Challenge Cup Champion!',
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  )
                                else
                                  for (final def in filteredSolo)
                                    _AchievementTile(
                                      definition: def,
                                      record: soloMap[def.id],
                                      tierColor: _tierColor(def.tier),
                                    ),
                                const SizedBox(height: 16),
                                // 2. Multiplayer Achievements Section
                                Row(
                                  children: [
                                    const Expanded(
                                      child: Text(
                                        'Multiplayer Achievements',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '$multiUnlockedCount / ${achievementsCatalog.length} • 🏆 $onlineCupCount Cups',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: scheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                if (filteredMulti.isEmpty)
                                  Card(
                                    child: Padding(
                                      padding: const EdgeInsets.all(18),
                                      child: Text(
                                        _filter == 'unlocked'
                                            ? 'Win a multiplayer match or tournament to unlock your first trophy!'
                                            : 'All Multiplayer achievements unlocked — Melow Grand Challenge Cup Champion!',
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  )
                                else
                                  for (final def in filteredMulti)
                                    _AchievementTile(
                                      definition: def,
                                      record: multiMap[def.id],
                                      tierColor: _tierColor(def.tier),
                                    ),
                                const MelowFooter(),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _GrandCupCard extends StatelessWidget {
  const _GrandCupCard({
    required this.title,
    required this.subtitle,
    required this.unlocked,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final bool unlocked;
  final String icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        color: unlocked
            ? AppTheme.goldAccent.withValues(alpha: 0.18)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        child: ListTile(
          leading: Opacity(
            opacity: unlocked ? 1.0 : 0.4,
            child: Text(icon, style: const TextStyle(fontSize: 32)),
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          subtitle: Text(
            subtitle,
            style: const TextStyle(fontSize: 12),
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: unlocked
                  ? AppTheme.goldAccent.withValues(alpha: 0.25)
                  : scheme.outlineVariant.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              unlocked ? 'WON 🏆' : 'Locked',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: unlocked ? AppTheme.goldAccent : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AchievementTile extends StatelessWidget {
  const _AchievementTile({
    required this.definition,
    required this.record,
    required this.tierColor,
  });

  final AchievementDefinition definition;
  final UserAchievement? record;
  final Color tierColor;

  @override
  Widget build(BuildContext context) {
    final unlocked = record?.isUnlocked ?? false;
    final progress = (record?.progress ?? 0).clamp(0, definition.target);
    final ratio = definition.target == 0 ? 0.0 : progress / definition.target;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: unlocked
                      ? tierColor.withValues(alpha: 0.22)
                      : scheme.surfaceContainerHighest,
                  border: Border.all(
                    color: unlocked ? tierColor : scheme.outlineVariant,
                    width: 2,
                  ),
                ),
                alignment: Alignment.center,
                child: Opacity(
                  opacity: unlocked ? 1.0 : 0.45,
                  child: Text(
                    definition.icon,
                    style: const TextStyle(fontSize: 23),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            definition.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: tierColor.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            definition.tier.label,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: tierColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      definition.description,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: unlocked ? 1.0 : ratio,
                              minHeight: 6,
                              color: unlocked ? tierColor : scheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          unlocked
                              ? 'Unlocked'
                              : '$progress/${definition.target}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: unlocked
                                ? tierColor
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
