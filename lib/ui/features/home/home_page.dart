import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/app_services.dart';
import '../../../core/services/sound_service.dart';
import '../../../domain/achievements_catalog.dart';
import '../../../domain/game_engine.dart';
import '../../../domain/models/social_models.dart';
import '../../../domain/models/user_profile.dart';
import '../../core/app_theme.dart';
import '../../core/widgets/footer.dart';
import '../../core/widgets/melow_avatar.dart';
import '../../core/widgets/melow_logo.dart';
import '../room/room_page.dart';
import '../settings/settings_screen.dart';

/// Phase 2 Redesigned Gaming Dashboard Home Screen.
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.services,
    required this.onNavigateTab,
  });

  final AppServices services;
  final ValueChanged<int> onNavigateTab;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openCreateRoomSheet(UserProfile? profile) async {
    widget.services.sound.play(SoundEffect.click);
    final prefs = widget.services.preferences;
    final nameCtrl = TextEditingController(text: profile?.nickname ?? '');
    String emoji = profile?.preferredEmoji ?? emojiChoices.first;
    int size = prefs.favoriteBoardSize;
    int bestOf = 3;
    GameMode mode = GameMode.fromId(prefs.favoriteMode);
    bool busy = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            MediaQuery.of(sheetCtx).viewInsets.bottom + 24,
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
                      color: Theme.of(sheetCtx).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Create Match Room',
                  style: Theme.of(sheetCtx)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: nameCtrl,
                  maxLength: 20,
                  decoration: const InputDecoration(
                    labelText: 'Your nickname',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Game Mode',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<GameMode>(
                    segments: const [
                      ButtonSegment(
                        value: GameMode.classic,
                        icon: Icon(Icons.grid_on_rounded),
                        label: Text('Classic'),
                      ),
                      ButtonSegment(
                        value: GameMode.blitz,
                        icon: Icon(Icons.bolt_rounded),
                        label: Text('Blitz (5s)'),
                      ),
                    ],
                    selected: {mode},
                    onSelectionChanged: (v) =>
                        setModalState(() => mode = v.first),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Board Size',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: [
                      for (final n in supportedBoardSizes)
                        ButtonSegment(value: n, label: Text('$n×$n')),
                    ],
                    selected: {size},
                    onSelectionChanged: (v) =>
                        setModalState(() => size = v.first),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text(
                      'Tournament',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    SegmentedButton<int>(
                      showSelectedIcon: false,
                      segments: [
                        for (final b in supportedBestOf)
                          ButtonSegment(value: b, label: Text('Best of $b')),
                      ],
                      selected: {bestOf},
                      onSelectionChanged: (v) =>
                          setModalState(() => bestOf = v.first),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Choose Emoji Mark',
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
                FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          final err =
                              GameEngine.validateNickname(nameCtrl.text);
                          if (err != null) {
                            _snack(err);
                            return;
                          }
                          setModalState(() => busy = true);
                          try {
                            await prefs.setFavoriteBoardSize(size);
                            await prefs.setFavoriteMode(mode.id);
                            final code = await widget.services.game.createRoom(
                              name: nameCtrl.text.trim(),
                              emoji: emoji,
                              size: size,
                              bestOf: bestOf,
                              gameMode: mode,
                              hostAvatar: profile?.avatarId ?? 'astro',
                            );
                            if (!sheetCtx.mounted) return;
                            Navigator.pop(sheetCtx);
                            if (!mounted) return;
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => RoomPage(
                                  code: code,
                                  services: widget.services,
                                ),
                              ),
                            );
                          } catch (e) {
                            _snack(e.toString().replaceFirst('Exception: ', ''));
                          } finally {
                            if (sheetCtx.mounted) {
                              setModalState(() => busy = false);
                            }
                          }
                        },
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(busy ? 'Creating Room…' : 'Create Room & Play'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    nameCtrl.dispose();
  }

  Future<void> _openJoinRoomSheet(UserProfile? profile) async {
    widget.services.sound.play(SoundEffect.click);
    final nameCtrl = TextEditingController(text: profile?.nickname ?? '');
    final codeCtrl = TextEditingController();
    String emoji = profile?.preferredEmoji ?? '⭕';
    bool busy = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            MediaQuery.of(sheetCtx).viewInsets.bottom + 24,
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
                      color: Theme.of(sheetCtx).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Join Friend’s Room',
                  style: Theme.of(sheetCtx)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: nameCtrl,
                  maxLength: 20,
                  decoration: const InputDecoration(
                    labelText: 'Your nickname',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: codeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 6,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: '6-character room code',
                    hintText: 'ABC234',
                    prefixIcon: Icon(Icons.key_rounded),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Choose Emoji Mark',
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
                FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          final err =
                              GameEngine.validateNickname(nameCtrl.text);
                          if (err != null) {
                            _snack(err);
                            return;
                          }
                          final code = codeCtrl.text.trim().toUpperCase();
                          if (code.length != 6) {
                            _snack('Enter a valid 6-character room code.');
                            return;
                          }
                          setModalState(() => busy = true);
                          try {
                            await widget.services.game.joinRoom(
                              code: code,
                              name: nameCtrl.text.trim(),
                              emoji: emoji,
                              guestAvatar: profile?.avatarId ?? 'fox',
                            );
                            if (!sheetCtx.mounted) return;
                            Navigator.pop(sheetCtx);
                            if (!mounted) return;
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => RoomPage(
                                  code: code,
                                  services: widget.services,
                                ),
                              ),
                            );
                          } catch (e) {
                            _snack(e.toString().replaceFirst('Exception: ', ''));
                          } finally {
                            if (sheetCtx.mounted) {
                              setModalState(() => busy = false);
                            }
                          }
                        },
                  icon: const Icon(Icons.login_rounded),
                  label: Text(busy ? 'Joining…' : 'Join Room'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    nameCtrl.dispose();
    codeCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.services.game.currentUid;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
                titleSpacing: 16,
                title: Row(
                  children: [
                    const MelowLogo(size: 36, borderRadius: 10, showGlow: false),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Melow Tic Tac Toe',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                actions: [
                  // Notification indicator for pending friend requests / challenges
                  StreamBuilder<List<FriendChallenge>>(
                    stream:
                        widget.services.friends.watchIncomingChallenges(uid),
                    builder: (context, chalSnap) {
                      final count = chalSnap.data?.length ?? 0;
                      return IconButton(
                        tooltip: 'Friend invitations',
                        onPressed: () => widget.onNavigateTab(1),
                        icon: Badge(
                          isLabelVisible: count > 0,
                          label: Text('$count'),
                          child: const Icon(Icons.notifications_none_rounded),
                        ),
                      );
                    },
                  ),
                  IconButton(
                    tooltip:
                        isDark ? 'Switch to light mode' : 'Switch to dark mode',
                    onPressed: () {
                      widget.services.sound.play(SoundEffect.click);
                      widget.services.preferences.setThemeMode(
                        isDark ? ThemeMode.light : ThemeMode.dark,
                      );
                    },
                    icon: Icon(
                      isDark
                          ? Icons.light_mode_rounded
                          : Icons.dark_mode_rounded,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Settings',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            SettingsScreen(services: widget.services),
                      ),
                    ),
                    icon: const Icon(Icons.settings_outlined),
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
                        // Player Hero Card
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isDark
                                  ? const [
                                      Color(0xFF2E1A6B),
                                      Color(0xFF1A254E),
                                    ]
                                  : const [
                                      Color(0xFF7C3AED),
                                      Color(0xFF0891B2),
                                    ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(26),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.purpleAccent
                                    .withValues(alpha: isDark ? 0.35 : 0.25),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  MelowAvatar(
                                    avatarId: profile?.avatarId ?? 'astro',
                                    size: 52,
                                    borderColor: AppTheme.cyanAccent,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Welcome back, ${profile?.nickname ?? 'Challenger'}!',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 19,
                                            fontWeight: FontWeight.w900,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white
                                                .withValues(alpha: 0.16),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            '${stats.rankBadge} • Lvl ${stats.level}',
                                            style: const TextStyle(
                                              color: AppTheme.goldAccent,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    profile?.preferredEmoji ?? '❌',
                                    style: const TextStyle(fontSize: 34),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppTheme.goldAccent,
                                    foregroundColor: AppTheme.darkBackground,
                                    minimumSize: const Size.fromHeight(54),
                                  ),
                                  onPressed: () =>
                                      _openCreateRoomSheet(profile),
                                  icon: const Icon(
                                    Icons.play_arrow_rounded,
                                    size: 28,
                                  ),
                                  label: const Text(
                                    'PLAY NOW',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        // Quick Actions Row
                        Row(
                          children: [
                            Expanded(
                              child: _QuickActionCard(
                                icon: Icons.add_box_rounded,
                                color: AppTheme.purpleAccent,
                                title: 'Create Room',
                                subtitle: 'Classic or Blitz',
                                onTap: () => _openCreateRoomSheet(profile),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _QuickActionCard(
                                icon: Icons.vpn_key_rounded,
                                color: AppTheme.cyanAccent,
                                title: 'Join Room',
                                subtitle: 'Enter 6-char code',
                                onTap: () => _openJoinRoomSheet(profile),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _QuickActionCard(
                                icon: Icons.groups_rounded,
                                color: AppTheme.goldAccent,
                                title: 'Challenge',
                                subtitle: 'Invite a friend',
                                onTap: () => widget.onNavigateTab(1),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        // Stats & Trophies Summary
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Text(
                                      'Your Arena Stats',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const Spacer(),
                                    TextButton(
                                      onPressed: () => widget.onNavigateTab(2),
                                      child: Text(
                                        '🏆 ${stats.tournamentsWon} Cups',
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    _MiniStat(
                                      label: 'Wins',
                                      value: '${stats.wins}',
                                      color: Colors.green,
                                    ),
                                    _MiniStat(
                                      label: 'Losses',
                                      value: '${stats.losses}',
                                      color: scheme.error,
                                    ),
                                    _MiniStat(
                                      label: 'Draws',
                                      value: '${stats.draws}',
                                      color: scheme.secondary,
                                    ),
                                    _MiniStat(
                                      label: 'Streak',
                                      value: '${stats.currentStreak}🔥',
                                      color: AppTheme.goldAccent,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        // Achievement Highlight
                        StreamBuilder<List<UserAchievement>>(
                          stream:
                              widget.services.profile.watchAchievements(uid),
                          builder: (context, achSnap) {
                            final unlockedCount = (achSnap.data ?? const [])
                                .where((a) => a.isUnlocked)
                                .length;
                            final total = achievementsCatalog.length;
                            return Card(
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                leading: const Text(
                                  '🎖️',
                                  style: TextStyle(fontSize: 32),
                                ),
                                title: const Text(
                                  'Achievements & Trophy Cabinet',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Text(
                                      '$unlockedCount of $total milestones unlocked',
                                    ),
                                    const SizedBox(height: 6),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: LinearProgressIndicator(
                                        value: total == 0
                                            ? 0
                                            : unlockedCount / total,
                                        minHeight: 6,
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: const Icon(
                                  Icons.chevron_right_rounded,
                                ),
                                onTap: () => widget.onNavigateTab(2),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 14),
                        // Recently Played Friends / Quick Rematch
                        StreamBuilder<List<FriendEntry>>(
                          stream: widget.services.friends.watchFriends(uid),
                          builder: (context, friendsSnap) {
                            final friends = friendsSnap.data ?? const [];
                            if (friends.isEmpty) {
                              return Card(
                                child: ListTile(
                                  leading: const Icon(Icons.person_add_rounded),
                                  title: const Text(
                                    'Add Friends & Build Rivalries',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                  subtitle: const Text(
                                    'Share your friend code to challenge friends anytime.',
                                  ),
                                  trailing: const Icon(
                                    Icons.arrow_forward_rounded,
                                  ),
                                  onTap: () => widget.onNavigateTab(1),
                                ),
                              );
                            }
                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Text(
                                          'Quick Challenge Friends',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 15,
                                          ),
                                        ),
                                        const Spacer(),
                                        TextButton(
                                          onPressed: () =>
                                              widget.onNavigateTab(1),
                                          child: const Text('See all'),
                                        ),
                                      ],
                                    ),
                                    SizedBox(
                                      height: 82,
                                      child: ListView.separated(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: friends.length.clamp(0, 8),
                                        separatorBuilder: (_, __) =>
                                            const SizedBox(width: 12),
                                        itemBuilder: (context, idx) {
                                          final f = friends[idx];
                                          return InkWell(
                                            borderRadius:
                                                BorderRadius.circular(14),
                                            onTap: () =>
                                                widget.onNavigateTab(1),
                                            child: SizedBox(
                                              width: 68,
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  MelowAvatar(
                                                    avatarId: f.avatarId,
                                                    size: 46,
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Text(
                                                    f.nickname,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
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

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
