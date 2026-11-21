import 'package:flutter/material.dart';

import '../../../core/services/app_services.dart';
import '../../../domain/achievements_catalog.dart';
import '../../../domain/models/user_profile.dart';
import '../../core/app_theme.dart';
import '../../core/widgets/footer.dart';

/// Melow v3.0 Trophies & Achievements Cabinet displaying won Melow Cups live!
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
      appBar: AppBar(title: const Text('Trophies & Cups')),
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
                    final map = <String, UserAchievement>{
                      for (final a in (achSnap.data ?? const <UserAchievement>[]))
                        a.achievementId: a,
                    };
                    final unlockedCount =
                        map.values.where((a) => a.isUnlocked).length;

                    final filtered = achievementsCatalog.where((def) {
                      final unlocked = map[def.id]?.isUnlocked ?? false;
                      if (_filter == 'unlocked') return unlocked;
                      if (_filter == 'locked') return !unlocked;
                      return true;
                    }).toList(growable: false);

                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 580),
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
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
                                            '${trophies.length > stats.tournamentsWon ? trophies.length : stats.tournamentsWon} Melow Cups Won',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleLarge
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w900,
                                                ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '$unlockedCount / ${achievementsCatalog.length} achievements unlocked',
                                            style: TextStyle(
                                              fontSize: 13,
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
                            // Won Melow Cups Shelf (prominently displayed!)
                            if (trophies.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              const Text(
                                'Your Melow Cup Collection',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              for (final t in trophies)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
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
                            const Text(
                              'Achievements',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
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
                            const SizedBox(height: 12),
                            if (filtered.isEmpty)
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Text(
                                    _filter == 'unlocked'
                                        ? 'Win a tournament cup to unlock your first trophy!'
                                        : 'You have unlocked every achievement — Melow Legend!',
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              )
                            else
                              for (final def in filtered)
                                _AchievementTile(
                                  definition: def,
                                  record: map[def.id],
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
