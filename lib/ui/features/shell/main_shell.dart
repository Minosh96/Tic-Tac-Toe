import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/services/app_services.dart';
import '../../../core/services/push_notification_service.dart';
import '../../../core/services/sound_service.dart';
import '../../../domain/models/social_models.dart';
import '../../core/app_theme.dart';
import '../../core/widgets/live_user_avatar.dart';
import '../chat/voice_call_screen.dart';
import '../friends/friends_page.dart';
import '../home/home_page.dart';
import '../leaderboard/leaderboard_page.dart';
import '../profile/profile_page.dart';
import '../trophies/trophies_page.dart';

/// Main 5-tab navigation shell with live Android notifications for messages & calls,
/// global incoming voice call banner, and exact unread message count badges.
class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.services});

  final AppServices services;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _index = 0;
  bool _appInForeground = true;

  StreamSubscription<List<DirectChatSummary>>? _chatNotifSub;
  StreamSubscription<List<VoiceCallSession>>? _callNotifSub;

  bool _chatsSeeded = false;
  final Map<String, DateTime?> _lastNotifiedMsgAt = <String, DateTime?>{};
  final Set<String> _activeRingingCallIds = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initNotifications();
  }

  Future<void> _initNotifications() async {
    await PushNotificationService.requestPermission();
    // Start lightweight Android foreground service so incoming calls & messages
    // still notify & ring even while the phone screen is locked.
    await PushNotificationService.startBackgroundKeepAlive();
    if (!mounted) return;
    final uid = widget.services.game.currentUid;

    _chatNotifSub = widget.services.chat.watchUserChats(uid).listen((chats) {
      if (!_chatsSeeded) {
        _chatsSeeded = true;
        for (final c in chats) {
          _lastNotifiedMsgAt[c.chatId] = c.lastMessageAt;
        }
        return;
      }

      for (final c in chats) {
        final prevAt = _lastNotifiedMsgAt[c.chatId];
        final nextAt = c.lastMessageAt;
        final isNewer = nextAt != null && (prevAt == null || nextAt.isAfter(prevAt));
        if (!isNewer) continue;
        _lastNotifiedMsgAt[c.chatId] = nextAt;

        if (c.lastSenderUid == uid || !c.isUnreadFor(uid)) continue;
        final otherUid = c.otherParticipantUid(uid);
        final viewingThisChat = _appInForeground &&
            PushNotificationService.activeChatFriendUid == otherUid;
        if (viewingThisChat) continue;

        final sender =
            c.lastSenderName.isNotEmpty ? c.lastSenderName : 'New Message';
        PushNotificationService.showMessageNotification(
          chatId: c.chatId,
          senderName: sender,
          messagePreview: c.lastMessage,
          unreadCount: c.unreadCountFor(uid),
        );
      }
    });

    _callNotifSub =
        widget.services.voiceCall.watchIncomingCalls(uid).listen((calls) {
      final currentIds = calls.map((c) => c.callId).toSet();

      // Dismiss notifications for calls that stopped ringing.
      for (final oldId in _activeRingingCallIds.difference(currentIds)) {
        PushNotificationService.cancelCallNotification(oldId);
      }

      // Post high-priority Android call notification for newly ringing calls.
      for (final call in calls) {
        if (_activeRingingCallIds.add(call.callId)) {
          PushNotificationService.showCallNotification(
            callId: call.callId,
            callerName: call.callerName,
          );
        }
      }
      _activeRingingCallIds
        ..clear()
        ..addAll(currentIds);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appInForeground = state == AppLifecycleState.resumed;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _chatNotifSub?.cancel();
    _callNotifSub?.cancel();
    super.dispose();
  }

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
                          LiveUserAvatar(
                            services: widget.services,
                            uid: incoming.callerUid,
                            fallbackAvatarId: incoming.callerAvatar,
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
                            onPressed: () {
                              PushNotificationService.cancelCallNotification(
                                incoming.callId,
                              );
                              widget.services.voiceCall
                                  .declineCall(incoming.callId);
                            },
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
                            onPressed: () {
                              PushNotificationService.cancelCallNotification(
                                incoming.callId,
                              );
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => VoiceCallScreen.incoming(
                                    services: widget.services,
                                    session: incoming,
                                  ),
                                ),
                              );
                            },
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
                  final unreadMessages = (chatSnap.data ?? const []).fold<int>(
                    0,
                    (sum, c) => sum + c.unreadCountFor(uid),
                  );
                  final pendingCount = (chalSnap.data?.length ?? 0) +
                      (reqSnap.data?.length ?? 0) +
                      unreadMessages;
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
                          label: Text(
                            pendingCount > 99 ? '99+' : '$pendingCount',
                          ),
                          child: const Icon(Icons.groups_outlined),
                        ),
                        selectedIcon: Badge(
                          isLabelVisible: pendingCount > 0,
                          label: Text(
                            pendingCount > 99 ? '99+' : '$pendingCount',
                          ),
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
