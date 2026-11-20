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
                  _SectionHeader(title: 'Appearance'),
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
                              segments: const [
                                ButtonSegment(
                                  value: ThemeMode.system,
                                  icon: Icon(Icons.brightness_auto_rounded),
                                  label: Text('System'),
                                ),
                                ButtonSegment(
                                  value: ThemeMode.light,
                                  icon: Icon(Icons.light_mode_rounded),
                                  label: Text('Light'),
                                ),
                                ButtonSegment(
                                  value: ThemeMode.dark,
                                  icon: Icon(Icons.dark_mode_rounded),
                                  label: Text('Dark'),
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
                  _SectionHeader(title: 'Audio, Haptics & Accessibility'),
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
                    _SectionHeader(title: 'Privacy & Leaderboards'),
                    Card(
                      child: Column(
                        children: [
                          SwitchListTile(
                            secondary: const Icon(Icons.visibility_rounded),
                            title: const Text('Public Player Profile'),
                            subtitle: const Text(
                              'Allow friends & players with your friend code to view stats',
                            ),
                            value: profile.publicProfileEnabled,
                            onChanged: (v) => services.profile.updateProfile(
                              nickname: profile.nickname,
                              avatarId: profile.avatarId,
                              preferredEmoji: profile.preferredEmoji,
                              publicProfileEnabled: v,
                              leaderboardOptIn: profile.leaderboardOptIn,
                            ),
                          ),
                          const Divider(height: 1),
                          SwitchListTile(
                            secondary: const Icon(Icons.leaderboard_rounded),
                            title: const Text('Show on Global Leaderboard'),
                            subtitle: const Text(
                              'Opt in or out of public global rankings anytime',
                            ),
                            value: profile.leaderboardOptIn,
                            onChanged: (v) => services.profile.updateProfile(
                              nickname: profile.nickname,
                              avatarId: profile.avatarId,
                              preferredEmoji: profile.preferredEmoji,
                              publicProfileEnabled:
                                  profile.publicProfileEnabled,
                              leaderboardOptIn: v,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _SectionHeader(title: 'App Info'),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.info_outline_rounded),
                      title: const Text('About Melow Tic Tac Toe'),
                      subtitle: const Text('Version 2.0.0 • Melow Labs'),
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
