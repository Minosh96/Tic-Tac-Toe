import 'package:flutter/material.dart';

import '../../../core/services/app_services.dart';
import '../../../domain/game_engine.dart';
import '../../../domain/models/social_models.dart';
import '../../core/app_theme.dart';
import '../../core/widgets/footer.dart';
import '../../core/widgets/melow_avatar.dart';

/// Phase 11 Head-to-Head Rivalry Screen between the current player and a rival.
class RivalryScreen extends StatelessWidget {
  const RivalryScreen({
    super.key,
    required this.services,
    required this.opponentUid,
    required this.opponentName,
    required this.opponentAvatar,
  });

  final AppServices services;
  final String opponentUid;
  final String opponentName;
  final String opponentAvatar;

  @override
  Widget build(BuildContext context) {
    final myUid = services.game.currentUid;
    final rivalryId = GameEngine.rivalryIdFor(myUid, opponentUid);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Rivalry vs $opponentName'),
        actions: [
          ListenableBuilder(
            listenable: services.preferences,
            builder: (context, _) {
              final hidden = services.preferences.isRivalHidden(rivalryId);
              return IconButton(
                tooltip: hidden ? 'Show rivalry' : 'Hide rivalry',
                icon: Icon(
                  hidden
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                ),
                onPressed: () =>
                    services.preferences.setRivalHidden(rivalryId, !hidden),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<RivalryStats?>(
        stream: services.rivalry.watchRivalry(myUid, opponentUid),
        builder: (context, rivalSnap) {
          final stats = rivalSnap.data;
          final myWins = stats?.winsFor(myUid) ?? 0;
          final oppWins = stats?.winsFor(opponentUid) ?? 0;
          final draws = stats?.draws ?? 0;
          final total = stats?.totalMatches ?? 0;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Column(
                            children: [
                              const MelowAvatar(avatarId: 'astro', size: 54),
                              const SizedBox(height: 6),
                              const Text(
                                'You',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              Text(
                                '$myWins',
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.cyanAccent,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            children: [
                              const Text(
                                'VS',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$total matches',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              Text(
                                '$draws draws',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            children: [
                              MelowAvatar(avatarId: opponentAvatar, size: 54),
                              const SizedBox(height: 6),
                              Text(
                                opponentName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                '$oppWins',
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.purpleAccent,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _RivalPill(
                              label: 'Current Streak',
                              value: stats == null || stats.currentStreak == 0
                                  ? '—'
                                  : '${stats.currentStreak} 🔥',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _RivalPill(
                              label: 'Best H2H Streak',
                              value: '${stats?.bestStreak ?? 0} 🏆',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () async {
                          final me = await services.profile.getProfile(myUid);
                          if (me == null || !context.mounted) return;
                          await services.friends.sendFriendChallenge(
                            me: me,
                            friendUid: opponentUid,
                            friendName: opponentName,
                            mode: GameMode.fromId(
                              services.preferences.favoriteMode,
                            ),
                            boardSize: services.preferences.favoriteBoardSize,
                            bestOf: 3,
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content:
                                    Text('Challenge sent to $opponentName!'),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.sports_esports_rounded),
                        label: Text('Challenge $opponentName'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Completed Tournament History',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              StreamBuilder<List<MatchSummary>>(
                stream:
                    services.rivalry.watchHeadToHeadMatches(myUid, opponentUid),
                builder: (context, matchSnap) {
                  final matches = matchSnap.data ?? const [];
                  if (matches.isEmpty) {
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          'No finalized tournament matches recorded together yet.\n'
                          'Rivalry stats update automatically when completed matches are verified.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (final m in matches)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Card(
                            child: ListTile(
                              leading: Text(
                                m.finalWinnerUid == myUid ? '🏆' : '⚔️',
                                style: const TextStyle(fontSize: 26),
                              ),
                              title: Text(
                                m.finalWinnerUid == myUid
                                    ? 'You won (${m.hostWins} - ${m.guestWins})'
                                    : '$opponentName won (${m.hostWins} - ${m.guestWins})',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Text(
                                '${GameMode.fromId(m.gameMode).label} • ${m.boardSize}×${m.boardSize}',
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const MelowFooter(),
            ],
          );
        },
      ),
    );
  }
}

class _RivalPill extends StatelessWidget {
  const _RivalPill({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
