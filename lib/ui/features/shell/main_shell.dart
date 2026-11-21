import 'package:flutter/material.dart';

import '../../../core/services/app_services.dart';
import '../../../core/services/sound_service.dart';
import '../../../domain/models/social_models.dart';
import '../../core/app_theme.dart';
import '../../core/widgets/melow_avatar.dart';
import '../chat/voice_call_screen.dart';
import '../friends/friends_page.dart';
import '../home/home_page.dart';
import '../leaderboard/leaderboard_page.dart';
import '../profile/profile_page.dart';
import '../trophies/trophies_page.dart';

/// Main 5-tab navigation shell with global incoming voice call banner & live badges.
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
      body: Stack(
        children: [
          IndexedStack(index: _index, children: pages),
          // Global incoming voice call banner visible across all tabs
          StreamBuilder<List<VoiceCallSession>>(
            stream: widget.services.voiceCall.watchIncomingCalls(uid),
            builder: (context, callSnap) {
              final incoming = (callSnap.data?.isNotEmpty ?? false)
                  ? callSnap.data!.first
                  : null;
              if (incoming == null) return const SizedBox.shrink();
              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Material(
                    elevation: 10,
                    borderRadius: BorderRadius.circular(18),
                    color: AppTheme.darkSurface,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: AppTheme.cyanAccent,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          MelowAvatar(
                            avatarId: incoming.callerAvatar,
                            size: 40,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  incoming.callerName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const Text(
                                  'Incoming voice call…',
                                  style: TextStyle(
                                    color: AppTheme.cyanAccent,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Decline',
                            icon: const Icon(
                              Icons.call_end_rounded,
                              color: Colors.redAccent,
                            ),
                            onPressed: () => widget.services.voiceCall
                                .declineCall(incoming.callId),
                          ),
                          IconButton.filled(
                            tooltip: 'Answer',
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.green,
                            ),
                            icon: const Icon(
                              Icons.call_rounded,
                              color: Colors.white,
                            ),
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => VoiceCallScreen.incoming(
                                  services: widget.services,
                                  session: incoming,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      bottomNavigationBar: StreamBuilder<List<FriendChallenge>>(
        stream: widget.services.friends.watchIncomingChallenges(uid),
        builder: (context, chalSnap) {
          return StreamBuilder<List<FriendRequest>>(
            stream: widget.services.friends.watchIncomingRequests(uid),
            builder: (context, reqSnap) {
              return StreamBuilder<List<DirectChatSummary>>(
                stream: widget.services.chat.watchUnreadChats(uid),
                builder: (context, chatSnap) {
                  final pendingCount = (chalSnap.data?.length ?? 0) +
                      (reqSnap.data?.length ?? 0) +
                      (chatSnap.data?.length ?? 0);
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
              );
            },
          );
        },
      ),
    );
  }
}
