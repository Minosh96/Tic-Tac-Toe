import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/app_services.dart';
import '../../../core/services/image_helper.dart';
import '../../../domain/achievements_catalog.dart';
import '../../../domain/game_engine.dart';
import '../../../domain/models/social_models.dart';
import '../../../domain/models/user_profile.dart';
import '../../core/app_theme.dart';
import '../../core/widgets/emoji_picker_grid.dart';
import '../../core/widgets/footer.dart';
import '../../core/widgets/melow_avatar.dart';
import '../about/about_screen.dart';
import '../settings/settings_screen.dart';

/// Melow v3.0 Player Profile with Gallery Photo Selection, 100+ Emoji Picker &
/// fixed responsive Stat Cards.
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

  Future<void> _quickPickGalleryPhoto(UserProfile profile) async {
    try {
      final base64Img = await ImageHelper.pickProfilePhotoBase64();
      if (base64Img == null) return;
      await widget.services.profile.updateProfile(
        nickname: profile.nickname,
        avatarId: profile.avatarId,
        photoBase64: base64Img,
        updatePhoto: true,
        preferredEmoji: profile.preferredEmoji,
        publicProfileEnabled: profile.publicProfileEnabled,
        leaderboardOptIn: profile.leaderboardOptIn,
      );
      _snack('Profile photo updated!');
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _openEditProfileSheet(UserProfile profile) async {
    final nameCtrl = TextEditingController(text: profile.nickname);
    String avatarId = profile.avatarId;
    String? photoBase64 = profile.photoBase64;
    bool photoChanged = false;
    String emoji = profile.preferredEmoji;
    bool saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              14,
              20,
              MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Theme.of(ctx).colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Edit Player Profile',
                    style: Theme.of(ctx)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 14),
                  // Gallery Photo Preview + Pick/Remove Controls
                  Row(
                    children: [
                      MelowAvatar(
                        avatarId: avatarId,
                        photoBase64: photoBase64,
                        size: 64,
                        borderColor: AppTheme.cyanAccent,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FilledButton.tonalIcon(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(42),
                              ),
                              onPressed: () async {
                                try {
                                  final picked =
                                      await ImageHelper.pickProfilePhotoBase64();
                                  if (picked != null) {
                                    setModalState(() {
                                      photoBase64 = picked;
                                      photoChanged = true;
                                    });
                                  }
                                } catch (e) {
                                  _snack(
                                    e
                                        .toString()
                                        .replaceFirst('Exception: ', ''),
                                  );
                                }
                              },
                              icon: const Icon(Icons.photo_library_rounded),
                              label: const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text('Choose from Gallery'),
                              ),
                            ),
                            if (photoBase64 != null && photoBase64!.isNotEmpty)
                              TextButton(
                                onPressed: () => setModalState(() {
                                  photoBase64 = null;
                                  photoChanged = true;
                                }),
                                child: const Text('Remove Photo (Use Avatar)'),
                              ),
                          ],
                        ),
                      ),
                    ],
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
                    'Or Choose Built-In Avatar',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final a in melowAvatars)
                        GestureDetector(
                          onTap: () => setModalState(() {
                            avatarId = a.id;
                            photoBase64 = null;
                            photoChanged = true;
                          }),
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: (photoBase64 == null && avatarId == a.id)
                                    ? AppTheme.cyanAccent
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                            child: MelowAvatar(avatarId: a.id, size: 44),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Text(
                        'Preferred Emoji Mark',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      Text(emoji, style: const TextStyle(fontSize: 24)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  EmojiPickerGrid(
                    selectedEmoji: emoji,
                    maxHeight: 165,
                    onSelected: (e) => setModalState(() => emoji = e),
                  ),
                  const SizedBox(height: 16),
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
                                photoBase64: photoBase64,
                                updatePhoto: photoChanged,
                                preferredEmoji: emoji,
                                publicProfileEnabled:
                                    profile.publicProfileEnabled,
                                leaderboardOptIn: profile.leaderboardOptIn,
                              );
                              if (ctx.mounted) Navigator.pop(ctx);
                              _snack('Profile updated!');
                            } catch (e) {
                              _snack(
                                e.toString().replaceFirst('Exception: ', ''),
                              );
                            } finally {
                              if (ctx.mounted) {
                                setModalState(() => saving = false);
                              }
                            }
                          },
                    child: Text(saving ? 'Saving…' : 'Save Changes'),
                  ),
                ],
              ),
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
                        // Identity Card with Gallery Photo Tap
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              children: [
                                GestureDetector(
                                  onTap: profile == null
                                      ? null
                                      : () => _quickPickGalleryPhoto(profile),
                                  child: Stack(
                                    alignment: Alignment.bottomRight,
                                    children: [
                                      MelowAvatar(
                                        avatarId: profile?.avatarId ?? 'astro',
                                        photoBase64: profile?.photoBase64,
                                        size: 84,
                                        borderColor: AppTheme.cyanAccent,
                                      ),
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: scheme.primary,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: scheme.surface,
                                            width: 2,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.photo_camera_rounded,
                                          size: 16,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  profile?.nickname ?? 'Player',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: 6,
                                  children: [
                                    Text(
                                      '${stats.rankBadge} • Lvl ${stats.level} • ${profile?.preferredEmoji ?? '❌'}',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: scheme.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                                if (profile != null &&
                                    profile.friendCode.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  ActionChip(
                                    avatar: const Icon(
                                      Icons.copy_rounded,
                                      size: 16,
                                    ),
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
                        // Responsive Stat Grid (no text clipping!)
                        GridView.count(
                          crossAxisCount: 3,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 1.0,
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
                          'Recent Match History',
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
                            title: const Text('About Melow Tic Tac Toe v3.0'),
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: accent,
                ),
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
