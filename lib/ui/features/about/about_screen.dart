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
            'Version 3.4.2 (Build 12)',
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
                    'What’s New in Version 3.0',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
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
