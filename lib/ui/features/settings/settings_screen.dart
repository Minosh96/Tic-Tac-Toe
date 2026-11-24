import 'package:flutter/material.dart';

import '../../../core/services/app_services.dart';
import '../../../core/services/sound_service.dart';
import '../../../domain/models/user_profile.dart';
import '../../core/widgets/footer.dart';
import '../about/about_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    final prefs = services.preferences;
    final uid = services.game.currentUid;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: prefs,
        builder: (context, _) {
          return StreamBuilder<UserProfile?>(
            stream: services.profile.watchProfile(uid),
            builder: (context, snap) {
              final profile = snap.data;
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const _SectionHeader(title: 'Appearance'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Theme Mode',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: SegmentedButton<ThemeMode>(
                              showSelectedIcon: false,
                              segments: const [
                                ButtonSegment(
                                  value: ThemeMode.system,
                                  icon: Icon(Icons.brightness_auto_rounded,
                                      size: 18),
                                  label: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text('System'),
                                  ),
                                ),
                                ButtonSegment(
                                  value: ThemeMode.light,
                                  icon:
                                      Icon(Icons.light_mode_rounded, size: 18),
                                  label: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text('Light'),
                                  ),
                                ),
                                ButtonSegment(
                                  value: ThemeMode.dark,
                                  icon: Icon(Icons.dark_mode_rounded, size: 18),
                                  label: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text('Dark'),
                                  ),
                                ),
                              ],
                              selected: {prefs.themeMode},
                              onSelectionChanged: (values) {
                                services.sound.play(SoundEffect.click);
                                prefs.setThemeMode(values.first);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const _SectionHeader(title: 'Audio, Haptics & Accessibility'),
                  Card(
                    child: Column(
                      children: [
                        SwitchListTile(
                          secondary: const Icon(Icons.volume_up_rounded),
                          title: const Text('Sound Effects'),
                          subtitle: const Text('Moves, wins, draws & trophies'),
                          value: prefs.soundEnabled,
                          onChanged: (v) async {
                            await prefs.setSoundEnabled(v);
                            if (v) services.sound.play(SoundEffect.click);
                          },
                        ),
                        const Divider(height: 1),
                        SwitchListTile(
                          secondary: const Icon(Icons.vibration_rounded),
                          title: const Text('Vibration & Haptics'),
                          subtitle: const Text('Tactile feedback on valid moves'),
                          value: prefs.hapticsEnabled,
                          onChanged: (v) async {
                            await prefs.setHapticsEnabled(v);
                            if (v) services.sound.hapticLight();
                          },
                        ),
                        const Divider(height: 1),
                        SwitchListTile(
                          secondary: const Icon(Icons.emoji_emotions_outlined),
                          title: const Text('Mute Live Reactions'),
                          subtitle: const Text(
                            'Hide floating emojis & quick taunts during matches',
                          ),
                          value: prefs.reactionsMuted,
                          onChanged: (v) => prefs.setReactionsMuted(v),
                        ),
                        const Divider(height: 1),
                        SwitchListTile(
                          secondary: const Icon(Icons.motion_photos_off_rounded),
                          title: const Text('Reduced Motion'),
                          subtitle: const Text(
                            'Simplify wheel spins, confetti & transitions',
                          ),
                          value: prefs.reducedMotion,
                          onChanged: (v) => prefs.setReducedMotion(v),
                        ),
                      ],
                    ),
                  ),
                  if (profile != null) ...[
                    const SizedBox(height: 16),
                    const _SectionHeader(title: 'Privacy & Profile Management'),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Whole Profile Visibility (Picture & Name)',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: SegmentedButton<ProfileVisibility>(
                                showSelectedIcon: false,
                                segments: const [
                                  ButtonSegment(
                                    value: ProfileVisibility.public,
                                    icon: Icon(Icons.public_rounded, size: 16),
                                    label: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text('Public'),
                                    ),
                                  ),
                                  ButtonSegment(
                                    value: ProfileVisibility.friends,
                                    icon: Icon(Icons.group_rounded, size: 16),
                                    label: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text('Friends Only'),
                                    ),
                                  ),
                                  ButtonSegment(
                                    value: ProfileVisibility.private,
                                    icon: Icon(
                                      Icons.lock_outline_rounded,
                                      size: 16,
                                    ),
                                    label: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text('Private'),
                                    ),
                                  ),
                                ],
                                selected: {profile.profileVisibility},
                                onSelectionChanged: (v) {
                                  final chosen = v.first;
                                  services.profile.updateProfile(
                                    nickname: profile.nickname,
                                    avatarId: profile.avatarId,
                                    preferredEmoji: profile.preferredEmoji,
                                    publicProfileEnabled:
                                        chosen == ProfileVisibility.public,
                                    leaderboardOptIn: profile.leaderboardOptIn,
                                    profileVisibility: chosen,
                                    hidePhotoGlobally:
                                        profile.hidePhotoGlobally,
                                    hideNameGlobally: profile.hideNameGlobally,
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              profile.profileVisibility.description,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Divider(height: 18),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              secondary: const Icon(Icons.hide_image_outlined),
                              title: const Text('Hide Profile Picture Globally'),
                              subtitle: const Text(
                                'Hide your gallery photo from global rankings',
                              ),
                              value: !profile.isPublic ||
                                  profile.hidePhotoGlobally,
                              onChanged: !profile.isPublic
                                  ? null
                                  : (v) => services.profile.updateProfile(
                                        nickname: profile.nickname,
                                        avatarId: profile.avatarId,
                                        preferredEmoji: profile.preferredEmoji,
                                        publicProfileEnabled: profile.isPublic,
                                        leaderboardOptIn:
                                            profile.leaderboardOptIn,
                                        profileVisibility:
                                            profile.profileVisibility,
                                        hidePhotoGlobally: v,
                                        hideNameGlobally:
                                            profile.hideNameGlobally,
                                      ),
                            ),
                            const Divider(height: 1),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              secondary: const Icon(Icons.person_off_outlined),
                              title: const Text('Hide Name Globally'),
                              subtitle: Text(
                                'Show default system name (${profile.defaultSystemNickname}) globally',
                              ),
                              value:
                                  !profile.isPublic || profile.hideNameGlobally,
                              onChanged: !profile.isPublic
                                  ? null
                                  : (v) => services.profile.updateProfile(
                                        nickname: profile.nickname,
                                        avatarId: profile.avatarId,
                                        preferredEmoji: profile.preferredEmoji,
                                        publicProfileEnabled: profile.isPublic,
                                        leaderboardOptIn:
                                            profile.leaderboardOptIn,
                                        profileVisibility:
                                            profile.profileVisibility,
                                        hidePhotoGlobally:
                                            profile.hidePhotoGlobally,
                                        hideNameGlobally: v,
                                      ),
                            ),
                            const Divider(height: 1),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              secondary: const Icon(Icons.leaderboard_rounded),
                              title: const Text('Show on Global Top 100'),
                              subtitle: const Text(
                                'Opt in or out of public global rankings anytime',
                              ),
                              value: profile.isPublic &&
                                  profile.leaderboardOptIn,
                              onChanged: !profile.isPublic
                                  ? null
                                  : (v) => services.profile.updateProfile(
                                        nickname: profile.nickname,
                                        avatarId: profile.avatarId,
                                        preferredEmoji: profile.preferredEmoji,
                                        publicProfileEnabled: profile.isPublic,
                                        leaderboardOptIn: v,
                                        profileVisibility:
                                            profile.profileVisibility,
                                        hidePhotoGlobally:
                                            profile.hidePhotoGlobally,
                                        hideNameGlobally:
                                            profile.hideNameGlobally,
                                        allowGlobalFriendRequests:
                                            profile.allowGlobalFriendRequests,
                                      ),
                            ),
                            const Divider(height: 1),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              secondary:
                                  const Icon(Icons.person_add_alt_1_rounded),
                              title: const Text(
                                'Allow Add Friend from Global List',
                              ),
                              subtitle: const Text(
                                'Enable or disable other players sending you friend requests from Global Top 100 rankings',
                              ),
                              value: profile.isPublic &&
                                  profile.allowGlobalFriendRequests,
                              onChanged: !profile.isPublic
                                  ? null
                                  : (v) => services.profile.updateProfile(
                                        nickname: profile.nickname,
                                        avatarId: profile.avatarId,
                                        preferredEmoji: profile.preferredEmoji,
                                        publicProfileEnabled: profile.isPublic,
                                        leaderboardOptIn:
                                            profile.leaderboardOptIn,
                                        profileVisibility:
                                            profile.profileVisibility,
                                        hidePhotoGlobally:
                                            profile.hidePhotoGlobally,
                                        hideNameGlobally:
                                            profile.hideNameGlobally,
                                        allowGlobalFriendRequests: v,
                                      ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor:
                                      Theme.of(context).colorScheme.error,
                                ),
                                onPressed: () async {
                                  bool deleteName = true;
                                  bool deletePhoto = true;
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => StatefulBuilder(
                                      builder: (ctx, setDialogState) =>
                                          AlertDialog(
                                        title: const Text(
                                          'Reset Name / Photo',
                                        ),
                                        content: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            CheckboxListTile(
                                              contentPadding: EdgeInsets.zero,
                                              value: deleteName,
                                              onChanged: (v) => setDialogState(
                                                  () => deleteName = v ?? true),
                                              title: const Text(
                                                'Reset Custom Name',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              subtitle: Text(
                                                'Revert to ${profile.defaultSystemNickname}',
                                              ),
                                            ),
                                            CheckboxListTile(
                                              contentPadding: EdgeInsets.zero,
                                              value: deletePhoto,
                                              onChanged: (v) => setDialogState(
                                                  () =>
                                                      deletePhoto = v ?? true),
                                              title: const Text(
                                                'Delete Profile Picture',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              subtitle: const Text(
                                                'Remove custom gallery photo',
                                              ),
                                            ),
                                          ],
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, false),
                                            child: const Text('Cancel'),
                                          ),
                                          FilledButton(
                                            onPressed: (!deleteName &&
                                                    !deletePhoto)
                                                ? null
                                                : () =>
                                                    Navigator.pop(ctx, true),
                                            child: const Text(
                                              'Reset Selected',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                  if (confirmed != true) return;
                                  await services.profile.deleteOrResetProfile(
                                    deleteName: deleteName,
                                    deletePhoto: deletePhoto,
                                  );
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Profile reset to default system settings (${profile.defaultSystemNickname}).',
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(
                                  Icons.person_off_rounded,
                                  size: 18,
                                ),
                                label: const Text(
                                  'Reset Name & Photo to System Default',
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor:
                                      Theme.of(context).colorScheme.error,
                                  foregroundColor:
                                      Theme.of(context).colorScheme.onError,
                                ),
                                onPressed: () async {
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text(
                                        'Permanently Delete Account?',
                                      ),
                                      content: const Text(
                                        'This will permanently delete your account, friends, chats, notifications, trophies, match stats, and all settings, and start fresh with a brand-new default profile.',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, false),
                                          child: const Text('Cancel'),
                                        ),
                                        FilledButton(
                                          style: FilledButton.styleFrom(
                                            backgroundColor: Theme.of(ctx)
                                                .colorScheme
                                                .error,
                                            foregroundColor: Theme.of(ctx)
                                                .colorScheme
                                                .onError,
                                          ),
                                          onPressed: () =>
                                              Navigator.pop(ctx, true),
                                          child: const Text(
                                            'Permanently Delete',
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmed != true) return;
                                  final fresh = await services.profile
                                      .permanentlyDeleteAccountAndCreateNew(
                                    preferences: services.preferences,
                                    chatRepository: services.chat,
                                    singlePlayerRepository:
                                        services.singlePlayer,
                                  );
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Account permanently deleted. Started fresh as ${fresh.nickname}!',
                                      ),
                                    ),
                                  );
                                  Navigator.pop(context);
                                },
                                icon: const Icon(
                                  Icons.no_accounts_rounded,
                                  size: 18,
                                ),
                                label: const Text(
                                  'Permanently Delete Account & All Data',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const _SectionHeader(title: 'App Info'),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.info_outline_rounded),
                      title: const Text('About Melow Tic Tac Toe'),
                      subtitle: const Text('Version 3.8.1 • Melow Labs'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AboutScreen()),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const MelowFooter(),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}
