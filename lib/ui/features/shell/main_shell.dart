import 'package:flutter/material.dart';

import '../../../core/services/app_services.dart';
import '../../../core/services/sound_service.dart';
import '../../../domain/models/social_models.dart';
import '../friends/friends_page.dart';
import '../home/home_page.dart';
import '../leaderboard/leaderboard_page.dart';
import '../profile/profile_page.dart';
import '../trophies/trophies_page.dart';

/// Main 5-tab navigation shell: Home | Friends | Trophies | Leaderboard | Profile.
class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.services});

  final AppServices services;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  void _goToTab(int idx) {
    if (idx == _index) return;
    widget.services.sound.play(SoundEffect.click);
    setState(() => _index = idx);
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.services.game.currentUid;
    final pages = [
      HomePage(services: widget.services, onNavigateTab: _goToTab),
      FriendsPage(services: widget.services),
      TrophiesPage(services: widget.services),
      LeaderboardPage(services: widget.services),
      ProfilePage(services: widget.services),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: StreamBuilder<List<FriendChallenge>>(
        stream: widget.services.friends.watchIncomingChallenges(uid),
        builder: (context, chalSnap) {
          final pendingCount = chalSnap.data?.length ?? 0;
          return NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: _goToTab,
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: pendingCount > 0,
                  label: Text('$pendingCount'),
                  child: const Icon(Icons.groups_outlined),
                ),
                selectedIcon: Badge(
                  isLabelVisible: pendingCount > 0,
                  label: Text('$pendingCount'),
                  child: const Icon(Icons.groups_rounded),
                ),
                label: 'Friends',
              ),
              const NavigationDestination(
                icon: Icon(Icons.emoji_events_outlined),
                selectedIcon: Icon(Icons.emoji_events_rounded),
                label: 'Trophies',
              ),
              const NavigationDestination(
                icon: Icon(Icons.leaderboard_outlined),
                selectedIcon: Icon(Icons.leaderboard_rounded),
                label: 'Ranks',
              ),
              const NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: 'Profile',
              ),
            ],
          );
        },
      ),
    );
  }
}
