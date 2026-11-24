import 'package:flutter/material.dart';

import '../../../core/services/app_services.dart';
import '../../../core/services/sound_service.dart';
import '../../../domain/models/social_models.dart';
import '../../../domain/models/user_profile.dart';
import '../../features/notifications/notifications_sheet.dart';

/// Shared live Notification Bell icon button showing incoming voice calls,
/// friend requests, game challenge requests, accepted invites, and unread messages,
/// opening NotificationsSheet with a one-tap Clear All option.
class NotificationBellIconButton extends StatelessWidget {
  const NotificationBellIconButton({
    super.key,
    required this.services,
    this.me,
  });

  final AppServices services;
  final UserProfile? me;

  void _openSheet(BuildContext context, UserProfile? resolvedMe) {
    services.sound.play(SoundEffect.click);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => NotificationsSheet(
        services: services,
        me: resolvedMe,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = services.game.currentUid;
    return StreamBuilder<UserProfile?>(
      stream: me != null ? null : services.profile.watchProfile(uid),
      initialData: me,
      builder: (context, meSnap) {
        final resolvedMe = me ?? meSnap.data;
        return StreamBuilder<List<VoiceCallSession>>(
          stream: services.voiceCall.watchIncomingCalls(uid),
          builder: (context, callSnap) {
            return StreamBuilder<List<FriendRequest>>(
              stream: services.friends.watchIncomingRequests(uid),
              builder: (context, reqSnap) {
                return StreamBuilder<List<FriendChallenge>>(
                  stream: services.friends.watchIncomingChallenges(uid),
                  builder: (context, chalSnap) {
                    return StreamBuilder<List<FriendChallenge>>(
                      stream: services.friends.watchOutgoingChallenges(uid),
                      builder: (context, outSnap) {
                        return StreamBuilder<List<DirectChatSummary>>(
                          stream: services.chat.watchUnreadChats(uid),
                          builder: (context, chatSnap) {
                            final acceptedOut = (outSnap.data ?? const [])
                                .where(
                                    (c) => c.isAccepted && c.roomId.isNotEmpty)
                                .length;
                            final unreadMessages = (chatSnap.data ?? const [])
                                .fold<int>(
                                  0,
                                  (sum, c) => sum + c.unreadCountFor(uid),
                                );
                            final count = (callSnap.data?.length ?? 0) +
                                (reqSnap.data?.length ?? 0) +
                                (chalSnap.data?.length ?? 0) +
                                acceptedOut +
                                unreadMessages;
                            return IconButton(
                              tooltip: 'Notifications',
                              onPressed: () => _openSheet(context, resolvedMe),
                              icon: Badge(
                                isLabelVisible: count > 0,
                                label: Text(count > 99 ? '99+' : '$count'),
                                child: Icon(
                                  count > 0
                                      ? Icons.notifications_active_rounded
                                      : Icons.notifications_none_rounded,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}
