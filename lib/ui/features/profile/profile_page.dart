import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/app_services.dart';
import '../../../domain/achievements_catalog.dart';
import '../../../domain/game_engine.dart';
import '../../../domain/models/social_models.dart';
import '../../../domain/models/user_profile.dart';
import '../../core/app_theme.dart';
import '../../core/widgets/footer.dart';
import '../../core/widgets/melow_avatar.dart';
import '../about/about_screen.dart';
import '../settings/settings_screen.dart';

/// Phase 8 Dedicated Player Profile, Verified Stats & Match History Screen.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.services});

  final AppServices services;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openEditProfileSheet(UserProfile profile) async {
    final nameCtrl = TextEditingController(text: profile.nickname);
    String avatarId = profile.avatarId;
    String emoji = profile.preferredEmoji;
    bool saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Edit Player Profile',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: nameCtrl,
                  maxLength: 20,
                  decoration: const InputDecoration(
                    labelText: 'Nickname',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Choose Avatar',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final a in melowAvatars)
                      GestureDetector(
                        onTap: () => setModalState(() => avatarId = a.id),
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: avatarId == a.id
                                  ? AppTheme.cyanAccent
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                          child: MelowAvatar(avatarId: a.id, size: 46),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'Preferred Emoji Mark',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in emojiChoices)
                      ChoiceChip(
                        label: Text(c, style: const TextStyle(fontSize: 22)),
                        selected: emoji == c,
                        onSelected: (_) => setModalState(() => emoji = c),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final err =
                              GameEngine.validateNickname(nameCtrl.text);
                          if (err != null) {
                            _snack(err);
                            return;
                          }
                          setModalState(() => saving = true);
                          try {
                            await widget.services.profile.updateProfile(
                              nickname: nameCtrl.text.trim(),
                              avatarId: avatarId,
                              preferredEmoji: emoji,
                              publicProfileEnabled:
                                  profile.publicProfileEnabled,
                              leaderboardOptIn: profile.leaderboardOptIn,
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            _snack('Profile updated!');
                          } catch (e) {
                            _snack(e.toString().replaceFirst('Exception: ', ''));
                          } finally {
                            if (ctx.mounted) setModalState(() => saving = false);
                          }
                        },
                  child: Text(saving ? 'Saving…' : 'Save Changes'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    nameCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.services.game.currentUid;
    final scheme = Theme.of(context).colorScheme;

    return StreamBuilder<UserProfile?>(
      stream: widget.services.profile.watchProfile(uid),
      builder: (context, profileSnap) {
        final profile = profileSnap.data;
        return StreamBuilder<PlayerStats>(
          stream: widget.services.profile.watchStats(uid),
          builder: (context, statsSnap) {
            final stats = statsSnap.data ?? const PlayerStats();
            return Scaffold(
              appBar: AppBar(
                title: const Text('Player Profile'),
                actions: [
                  if (profile != null)
                    IconButton(
                      tooltip: 'Edit profile',
                      icon: const Icon(Icons.edit_rounded),
                      onPressed: () => _openEditProfileSheet(profile),
                    ),
                  IconButton(
                    tooltip: 'Settings',
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            SettingsScreen(services: widget.services),
                      ),
                    ),
                  ),
                ],
              ),
              body: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 580),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      children: [
                        // Identity Card
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              children: [
                                MelowAvatar(
                                  avatarId: profile?.avatarId ?? 'astro',
                                  size: 76,
                                  borderColor: AppTheme.cyanAccent,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  profile?.nickname ?? 'Player',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${stats.rankBadge} • Level ${stats.level} • Mark ${profile?.preferredEmoji ?? '❌'}',
                                  style: TextStyle(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (profile != null &&
                                    profile.friendCode.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  ActionChip(
                                    avatar: const Icon(Icons.copy_rounded,
                                        size: 16),
                                    label: Text(
                                      'Friend Code: ${profile.friendCode}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    onPressed: () async {
                                      await Clipboard.setData(
                                        ClipboardData(text: profile.friendCode),
                                      );
                                      _snack('Friend code copied!');
                                    },
                                  ),
                                ],
                                const SizedBox(height: 8),
                                Text(
                                  profile?.createdAt != null
                                      ? 'Joined ${profile!.createdAt!.toLocal().toString().substring(0, 10)}'
                                      : 'Anonymous Firebase Player',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        // Verified Statistics Grid
                        GridView.count(
                          crossAxisCount: 3,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 1.2,
                          children: [
                            _StatTile(
                              label: 'Played',
                              value: '${stats.gamesPlayed}',
                            ),
                            _StatTile(
                              label: 'Wins',
                              value: '${stats.wins}',
                              accent: Colors.green,
                            ),
                            _StatTile(
                              label: 'Win Rate',
                              value: '${stats.winRate.toStringAsFixed(0)}%',
                              accent: AppTheme.cyanAccent,
                            ),
                            _StatTile(
                              label: 'Cups Won',
                              value: '${stats.tournamentsWon} 🏆',
                              accent: AppTheme.goldAccent,
                            ),
                            _StatTile(
                              label: 'Streak',
                              value: '${stats.currentStreak} 🔥',
                            ),
                            _StatTile(
                              label: 'Best Streak',
                              value: '${stats.bestStreak}',
                              accent: AppTheme.purpleAccent,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        // Next Achievement Progress
                        StreamBuilder<List<UserAchievement>>(
                          stream:
                              widget.services.profile.watchAchievements(uid),
                          builder: (context, achSnap) {
                            final records = {
                              for (final a in (achSnap.data ?? const []))
                                a.achievementId: a,
                            };
                            final nextDef = achievementsCatalog.firstWhere(
                              (def) => !(records[def.id]?.isUnlocked ?? false),
                              orElse: () => achievementsCatalog.last,
                            );
                            final prog = (records[nextDef.id]?.progress ?? 0)
                                .clamp(0, nextDef.target);
                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Next Milestone: ${nextDef.icon} ${nextDef.title}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      nextDef.description,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: LinearProgressIndicator(
                                        value: nextDef.target == 0
                                            ? 1
                                            : prog / nextDef.target,
                                        minHeight: 8,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '$prog / ${nextDef.target}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: scheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Recent Verified Match History',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        StreamBuilder<List<MatchSummary>>(
                          stream:
                              widget.services.profile.watchRecentMatches(uid),
                          builder: (context, matchSnap) {
                            final matches = matchSnap.data ?? const [];
                            if (matches.isEmpty) {
                              return Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Text(
                                    'Completed multiplayer tournaments will appear here.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                    ),
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
                                          m.finalWinnerUid == uid ? '🏆' : '🎮',
                                          style: const TextStyle(fontSize: 24),
                                        ),
                                        title: Text(
                                          m.finalWinnerUid == uid
                                              ? 'Victory (${m.hostWins} - ${m.guestWins})'
                                              : 'Match (${m.hostWins} - ${m.guestWins})',
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
                        const SizedBox(height: 10),
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.info_outline_rounded),
                            title: const Text('About Melow Tic Tac Toe v2.0'),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AboutScreen(),
                              ),
                            ),
                          ),
                        ),
                        const MelowFooter(),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    this.accent,
  });

  final String label;
  final String value;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: accent,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
