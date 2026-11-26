import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/app_services.dart';
import '../../../core/services/image_helper.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../domain/achievements_catalog.dart';
import '../../../domain/bot_engine.dart';
import '../../../domain/game_engine.dart';
import '../../../domain/models/single_player_models.dart';
import '../../../domain/models/social_models.dart';
import '../../../domain/models/user_profile.dart';
import '../../core/app_theme.dart';
import '../../core/widgets/emoji_picker_grid.dart';
import '../../core/widgets/footer.dart';
import '../../core/widgets/live_user_avatar.dart';
import '../../core/widgets/melow_avatar.dart';
import '../../core/widgets/notification_bell_button.dart';
import '../about/about_screen.dart';
import '../settings/settings_screen.dart';
import '../splash/splash_screen.dart';

class _CombinedMatchItem {
  const _CombinedMatchItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.timestamp,
  });

  final String icon;
  final String title;
  final String subtitle;
  final DateTime timestamp;
}

/// Melow v3.7 Player Profile displaying:
/// - Player Identity Card + Username & Password Account Registration/Switch
/// - Single Player Summary FIRST (with full words Played, Won, Lost, Draw per difficulty)
/// - Online Multiplayer Summary SECOND
/// - Recent Match History capped strictly at 5 matches.
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
        publicProfileEnabled: profile.isPublic,
        leaderboardOptIn: profile.leaderboardOptIn,
        profileVisibility: profile.profileVisibility,
        hidePhotoGlobally: profile.hidePhotoGlobally,
        hideNameGlobally: profile.hideNameGlobally,
      );
      LiveUserProfileBuilder.cache.remove(profile.uid);
      _snack('Profile photo updated!');
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _openRegisterOrLoginDialog({
    required UserProfile? profile,
    required bool isRegister,
  }) async {
    final userCtrl = TextEditingController(
      text: isRegister ? (profile?.registeredUsername ?? '') : '',
    );
    final passCtrl = TextEditingController();
    bool obscure = true;
    bool busy = false;
    String? errText;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final scheme = Theme.of(ctx).colorScheme;
          return AlertDialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
            contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            title: Text(
              isRegister ? 'Register New User' : 'Login with Existing User',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top error banner immediately visible even when keyboard is up
                  if (errText != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: scheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: scheme.error, width: 1.4),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            color: scheme.error,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              errText!,
                              style: TextStyle(
                                color: scheme.onErrorContainer,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  Text(
                    'Min 4 chars for Username • Min 6 chars for Password',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: userCtrl,
                    maxLength: 20,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Username (min 4 chars)',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                      isDense: true,
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: passCtrl,
                    obscureText: obscure,
                    maxLength: 64,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: 'Password (min 6 chars)',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      isDense: true,
                      counterText: '',
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () =>
                            setDialogState(() => obscure = !obscure),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        FocusScope.of(ctx).unfocus();
                        final uErr =
                            ProfileRepository.validateUsername(userCtrl.text);
                        if (uErr != null) {
                          setDialogState(() => errText = uErr);
                          return;
                        }
                        final pErr =
                            ProfileRepository.validatePassword(passCtrl.text);
                        if (pErr != null) {
                          setDialogState(() => errText = pErr);
                          return;
                        }
                        setDialogState(() {
                          busy = true;
                          errText = null;
                        });
                        try {
                          if (isRegister) {
                            final updated = await widget.services.profile
                                .registerUsernameAndPassword(
                              username: userCtrl.text,
                              password: passCtrl.text,
                              nickname: profile?.nickname,
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            _snack(
                              'Profile registered as @${updated.registeredUsername}!',
                            );
                          } else {
                            final loggedIn = await widget.services.profile
                                .loginWithUsernameAndPassword(
                              username: userCtrl.text,
                              password: passCtrl.text,
                            );
                            await widget.services.singlePlayer
                                .loadLocalAndSync();
                            if (ctx.mounted) Navigator.pop(ctx);
                            _snack('Signed in as ${loggedIn.nickname}!');
                          }
                          if (mounted) setState(() {});
                        } catch (e) {
                          if (ctx.mounted) {
                            setDialogState(() {
                              busy = false;
                              errText = e
                                  .toString()
                                  .replaceFirst('Exception: ', '');
                            });
                          }
                        }
                      },
                icon: Icon(
                  isRegister ? Icons.how_to_reg_rounded : Icons.login_rounded,
                  size: 18,
                ),
                label: Text(
                  busy
                      ? (isRegister ? 'Registering…' : 'Signing in…')
                      : (isRegister ? 'Register New User' : 'Login'),
                ),
              ),
            ],
          );
        },
      ),
    );
    userCtrl.dispose();
    passCtrl.dispose();
  }

  Future<void> _openDeleteProfileReleaseUsernameDialog(
    UserProfile profile,
  ) async {
    final passCtrl = TextEditingController();
    bool busy = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final scheme = Theme.of(ctx).colorScheme;
          return AlertDialog(
            title: const Text('Delete Profile?'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.isRegisteredAccount
                        ? 'This will permanently delete your profile, stats, friends, and chats, and release the username "@${profile.registeredUsername}" so it can be used again by any user.'
                        : 'This will permanently delete your profile, stats, friends, and chats, and start fresh with a brand-new profile.',
                  ),
                  if (profile.isRegisteredAccount) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: passCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirm Password (optional if recent)',
                        prefixIcon: Icon(Icons.lock_outline_rounded),
                        isDense: true,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                ),
                onPressed: busy
                    ? null
                    : () async {
                        setDialogState(() => busy = true);
                        try {
                          final fresh = await widget.services.profile
                              .deleteRegisteredProfileAndReleaseUsername(
                            preferences: widget.services.preferences,
                            chatRepository: widget.services.chat,
                            singlePlayerRepository:
                                widget.services.singlePlayer,
                            password: passCtrl.text.trim(),
                          );
                          LiveUserProfileBuilder.cache.clear();
                          if (ctx.mounted) Navigator.pop(ctx);
                          _snack(
                            'Profile deleted and username released. Started fresh as ${fresh.nickname}!',
                          );
                          if (mounted) setState(() {});
                        } catch (e) {
                          _snack(
                            e.toString().replaceFirst('Exception: ', ''),
                          );
                          if (ctx.mounted) setDialogState(() => busy = false);
                        }
                      },
                icon: const Icon(Icons.delete_forever_rounded, size: 18),
                label: Text(busy ? 'Deleting…' : 'Delete Profile'),
              ),
            ],
          );
        },
      ),
    );
    passCtrl.dispose();
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
                                publicProfileEnabled: profile.isPublic,
                                leaderboardOptIn: profile.leaderboardOptIn,
                                profileVisibility: profile.profileVisibility,
                                hidePhotoGlobally: profile.hidePhotoGlobally,
                                hideNameGlobally: profile.hideNameGlobally,
                              );
                              LiveUserProfileBuilder.cache.remove(profile.uid);
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
                  NotificationBellIconButton(
                    services: widget.services,
                    me: profile,
                  ),
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
                                StreamBuilder<List<FriendEntry>>(
                                  stream: widget.services.friends
                                      .watchFriends(uid),
                                  builder: (context, friendsSnap) {
                                    final friendCount =
                                        friendsSnap.data?.length ?? 0;
                                    return Text(
                                      'Favorite Symbol: ${profile?.preferredEmoji ?? '❌'} • 👥 $friendCount ${friendCount == 1 ? 'Friend' : 'Friends'}',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: scheme.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    );
                                  },
                                ),
                                if (profile != null &&
                                    profile.friendCode.isNotEmpty) ...[
                                  const SizedBox(height: 10),
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
                                const SizedBox(height: 12),
                                // Account Registration (Username & Password) section
                                if (profile != null &&
                                    profile.isRegisteredAccount) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Text(
                                      '✅ Registered Account: @${profile.registeredUsername}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.green,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    alignment: WrapAlignment.center,
                                    children: [
                                      TextButton.icon(
                                        onPressed: () =>
                                            _openRegisterOrLoginDialog(
                                          profile: profile,
                                          isRegister: false,
                                        ),
                                        icon: const Icon(
                                          Icons.swap_horiz_rounded,
                                          size: 18,
                                        ),
                                        label: const Text(
                                          'Switch / Login Account',
                                        ),
                                      ),
                                      TextButton.icon(
                                        style: TextButton.styleFrom(
                                          foregroundColor: scheme.error,
                                        ),
                                        onPressed: () =>
                                            _openDeleteProfileReleaseUsernameDialog(
                                          profile,
                                        ),
                                        icon: const Icon(
                                          Icons.delete_forever_rounded,
                                          size: 18,
                                        ),
                                        label: const Text('Delete Profile'),
                                      ),
                                    ],
                                  ),
                                ] else ...[
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    alignment: WrapAlignment.center,
                                    children: [
                                      FilledButton.tonalIcon(
                                        onPressed: () =>
                                            _openRegisterOrLoginDialog(
                                          profile: profile,
                                          isRegister: true,
                                        ),
                                        icon: const Icon(
                                          Icons.how_to_reg_rounded,
                                          size: 18,
                                        ),
                                        label: const Text(
                                          'Register New User',
                                        ),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: () =>
                                            _openRegisterOrLoginDialog(
                                          profile: profile,
                                          isRegister: false,
                                        ),
                                        icon: const Icon(
                                          Icons.login_rounded,
                                          size: 18,
                                        ),
                                        label: const Text(
                                          'Login Existing User',
                                        ),
                                      ),
                                      if (profile != null)
                                        OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: scheme.error,
                                          ),
                                          onPressed: () =>
                                              _openDeleteProfileReleaseUsernameDialog(
                                            profile,
                                          ),
                                          icon: const Icon(
                                            Icons.delete_outline_rounded,
                                            size: 18,
                                          ),
                                          label: const Text('Delete Profile'),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Username min 4 chars • Password min 6 chars',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 6),
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    await widget.services.profile
                                        .signOutToLogin();
                                    if (!context.mounted) return;
                                    Navigator.of(context).pushAndRemoveUntil(
                                      MaterialPageRoute(
                                        builder: (_) => SplashScreen(
                                          services: widget.services,
                                        ),
                                      ),
                                      (_) => false,
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.logout_rounded,
                                    size: 18,
                                  ),
                                  label: const Text(
                                    'Log Out',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Section 1: Single Player Summary FIRST
                        ListenableBuilder(
                          listenable: widget.services.singlePlayer,
                          builder: (context, _) {
                            final solo = widget.services.singlePlayer.stats;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Single Player Summary',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                GridView.count(
                                  crossAxisCount: 3,
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  mainAxisSpacing: 10,
                                  crossAxisSpacing: 10,
                                  childAspectRatio: 1.05,
                                  children: [
                                    _StatTile(
                                      label: 'Played',
                                      value: '${solo.totalGames}',
                                    ),
                                    _StatTile(
                                      label: 'Won',
                                      value: '${solo.wins}',
                                      accent: Colors.green,
                                    ),
                                    _StatTile(
                                      label: 'Lost / Draw',
                                      value: '${solo.losses} / ${solo.draws}',
                                      accent: scheme.error,
                                    ),
                                    _StatTile(
                                      label: 'Win Rate',
                                      value:
                                          '${solo.winPercentage.toStringAsFixed(0)}%',
                                      accent: AppTheme.cyanAccent,
                                    ),
                                    _StatTile(
                                      label: 'Solo Cups',
                                      value: '${solo.soloCups} 🏆',
                                      accent: AppTheme.goldAccent,
                                    ),
                                    _StatTile(
                                      label: 'Streak / Best',
                                      value:
                                          '${solo.currentStreak}🔥 / ${solo.bestStreak}',
                                      accent: AppTheme.purpleAccent,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Single Player Statistics by Difficulty',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        for (final diff in BotDifficulty.values)
                                          _DifficultyBreakdownRow(
                                            difficulty: diff,
                                            stats: solo.statsFor(diff),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        // Section 2: Multiplayer Summary SECOND
                        const Text(
                          'Multiplayer Summary',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        GridView.count(
                          crossAxisCount: 3,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 1.05,
                          children: [
                            _StatTile(
                              label: 'Played',
                              value: '${stats.gamesPlayed}',
                            ),
                            _StatTile(
                              label: 'Won',
                              value: '${stats.wins}',
                              accent: Colors.green,
                            ),
                            _StatTile(
                              label: 'Lost / Draw',
                              value: '${stats.losses} / ${stats.draws}',
                              accent: scheme.error,
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
                              label: 'Streak / Best',
                              value:
                                  '${stats.currentStreak}🔥 / ${stats.bestStreak}',
                              accent: AppTheme.purpleAccent,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        // Next Milestone
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
                          'Recent Match History (Last 5)',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Combined Recent Match History strictly capped at 5 matches!
                        ListenableBuilder(
                          listenable: widget.services.singlePlayer,
                          builder: (context, _) {
                            final soloHistory =
                                widget.services.singlePlayer.history;
                            return StreamBuilder<List<MatchSummary>>(
                              stream: widget.services.profile
                                  .watchRecentMatches(uid, limit: 5),
                              builder: (context, matchSnap) {
                                final matches = matchSnap.data ?? const [];
                                final combined = <_CombinedMatchItem>[
                                  for (final s in soloHistory)
                                    _CombinedMatchItem(
                                      icon: s.result == 'win'
                                          ? '🏆'
                                          : (s.result == 'draw' ? '🤝' : '🤖'),
                                      title: s.result == 'win'
                                          ? 'Single Player Victory (${s.playerScore} - ${s.systemScore})'
                                          : s.result == 'draw'
                                              ? 'Single Player Draw (${s.playerScore} - ${s.systemScore})'
                                              : 'Single Player Match (${s.playerScore} - ${s.systemScore})',
                                      subtitle:
                                          '${BotDifficulty.fromId(s.difficulty).label} • ${SinglePlayerMode.fromId(s.mode).label} • ${s.boardSize}×${s.boardSize}',
                                      timestamp: s.playedAt,
                                    ),
                                  for (final m in matches)
                                    _CombinedMatchItem(
                                      icon: m.finalWinnerUid == uid
                                          ? '🏆'
                                          : '🎮',
                                      title: m.finalWinnerUid == uid
                                          ? 'Multiplayer Victory (${m.hostWins} - ${m.guestWins})'
                                          : 'Multiplayer Match (${m.hostWins} - ${m.guestWins})',
                                      subtitle:
                                          '${GameMode.fromId(m.gameMode).label} • ${m.boardSize}×${m.boardSize}',
                                      timestamp: m.completedAt ??
                                          DateTime.fromMillisecondsSinceEpoch(
                                              0),
                                    ),
                                ];
                                combined.sort(
                                  (a, b) => b.timestamp.compareTo(a.timestamp),
                                );
                                final topFive =
                                    combined.take(5).toList(growable: false);

                                if (topFive.isEmpty) {
                                  return Card(
                                    child: Padding(
                                      padding: const EdgeInsets.all(20),
                                      child: Text(
                                        'Your last 5 Single Player and Multiplayer games will appear here.',
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
                                    for (final item in topFive)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 8),
                                        child: Card(
                                          child: ListTile(
                                            leading: Text(
                                              item.icon,
                                              style:
                                                  const TextStyle(fontSize: 24),
                                            ),
                                            title: Text(
                                              item.title,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            subtitle: Text(item.subtitle),
                                          ),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.info_outline_rounded),
                            title: const Text('About Melow Tic Tac Toe v3.9.2'),
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

class _DifficultyBreakdownRow extends StatelessWidget {
  const _DifficultyBreakdownRow({
    required this.difficulty,
    required this.stats,
  });

  final BotDifficulty difficulty;
  final DifficultyStats stats;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(difficulty.badge, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Text(
                difficulty.label,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Text(
              'Played: ${stats.games} • Won: ${stats.wins} • Lost: ${stats.losses} • Draw: ${stats.draws}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
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
                  fontSize: 18,
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
