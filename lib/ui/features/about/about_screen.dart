import 'package:flutter/material.dart';

import '../../core/widgets/footer.dart';
import '../../core/widgets/melow_logo.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 12),
          const Center(child: MelowLogo(size: 104, borderRadius: 26)),
          const SizedBox(height: 16),
          Text(
            'Melow Tic Tac Toe',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            'Version 3.9.4 (Build 22)',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'What’s New in Version 3.9.4',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  const _Bullet(
                    text: 'WhatsApp-style background call & message notifications: incoming calls and messages ring and pop up even when your phone is locked or you are using another app, with direct Answer & Decline actions',
                  ),
                  const _Bullet(
                    text: 'Multi-participant Group Voice Calls (up to 5 members in a single call) with simultaneous ringing, live participant profiles & speaking indicators, and anytime leave/rejoin',
                  ),
                  const _Bullet(
                    text: 'Live room rejoin detection: when an opponent leaves and rejoins the same match room, the "opponent left" message disappears automatically and notifies that your opponent is back',
                  ),
                  const _Bullet(
                    text: 'New Melow Tic Tac Toe app logo across launcher icons, native splash screen, headers, and share cards',
                  ),
                  const _Bullet(
                    text: 'Home tab Your Arena Stats card showing Played, Wins, Losses, Draws, Streak & Melow Cups separately for Single Player and Multiplayer',
                  ),
                  const _Bullet(
                    text: 'Group members numbered 1, 2, 3, 4, 5 before tournament completion, with full Match Results, Final Rankings & Shareable Tournament Result Card upon completion',
                  ),
                  const _Bullet(
                    text: 'Auto-generated Group Tournament Fixtures (User1 vs User2) with private Room Codes visible only to the 2 match participants & end-of-tournament Champion 🥇 / Runner-Up 🥈 Summary',
                  ),
                  const _Bullet(
                    text: 'Live Android notifications & in-app alerts for incoming Friend Requests & Match Challenges, with Mark Read & Erase All in Notifications',
                  ),
                  const _Bullet(
                    text: 'Cancel pending Friend Requests directly on the Global Top 100 Ranks tab, plus Delete Profile & release username for reuse',
                  ),
                  const _Bullet(
                    text: 'Expanded universal Avatar gallery with 8 new avatars and full Group Chat sender names & message controls',
                  ),
                  const _Bullet(
                    text: 'Create a Friend Group with your own Friend Code (choose 2–5 max members) and share your code for friends to join & play',
                  ),
                  const _Bullet(
                    text: 'Send Friend Requests directly to players on the Global Top 100 list (with an enable/disable toggle in Privacy Settings)',
                  ),
                  const _Bullet(
                    text: 'Redesigned neon arcade Login Screen background & live Notification Bell with Clear All across all tabs',
                  ),
                  const _Bullet(
                    text: '5-Player Friend Groups with 2-player matches, Final Match for the Melow Challenge Champion Cup 🏆, Group Rankings, Group Chat & Group Voice Calls',
                  ),
                  const _Bullet(
                    text: 'Player Account Registration & Startup Login with Username (min 4 chars) & Password (min 6 chars) alongside Quick Anonymous Login',
                  ),
                  const _Bullet(
                    text: 'Melow All-Challenge Cup, Melow Grand Challenge Cup & Melow Grand Slam Cup awarded when all Single Player or Multiplayer challenges are won',
                  ),
                  const _Bullet(
                    text: 'Dual symbol selection (My Symbol & Bot Symbol) in Single Player and detailed Played • Won • Lost • Draw difficulty statistics',
                  ),
                  const _Bullet(
                    text: 'Offline-ready Single Player (Player vs System) mode with Easy, Normal, Hard & Impossible difficulties',
                  ),
                  const _Bullet(
                    text: 'Classic, Tournament (BO3/5/7) & Blitz (5s) solo modes with Practice Hints & Undo',
                  ),
                  const _Bullet(
                    text: 'Separate Single Player Statistics, difficulty breakdown, Solo Cups & 8 Solo Achievements',
                  ),
                  const _Bullet(
                    text: 'Streamlined Player Profile tab featuring Online & Solo Game Summaries',
                  ),
                  const _Bullet(
                    text: 'Instant Melow Cup trophies, achievements & stats sync after every tournament win',
                  ),
                  const _Bullet(
                    text: '100+ categorized emojis including Boy 👦, Girl 👧 & funny emojis',
                  ),
                  const _Bullet(
                    text: 'Direct Friend Chat with Gallery/Camera photo sharing & live WebRTC Voice Calls',
                  ),
                  const _Bullet(
                    text: 'Custom Profile Photo selection directly from your phone gallery',
                  ),
                  const _Bullet(
                    text: 'Live Notifications Center for calls, friend requests, challenges & unread messages',
                  ),
                  const _Bullet(
                    text: 'Refined mobile typography & button alignment across all screen sizes',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Developer & Credits',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Developed at Melow Labs.\n'
                    'Powered by Flutter, Firebase Authentication, Cloud Firestore, and WebRTC.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const MelowFooter(),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  ', style: TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
