import 'package:flutter/material.dart';

import '../../../core/services/app_services.dart';
import '../../../core/services/push_notification_service.dart';
import '../../../domain/game_engine.dart';
import '../../../domain/models/social_models.dart';
import '../../../domain/models/user_profile.dart';
import '../../core/widgets/live_user_avatar.dart';
import '../../core/widgets/melow_avatar.dart';
import '../chat/friend_chat_screen.dart';
import '../chat/voice_call_screen.dart';
import '../room/room_page.dart';

/// Unified live Notifications Sheet displaying incoming voice calls,
/// friend requests, match challenges, accepted invites, and unread friend chats.
class NotificationsSheet extends StatelessWidget {
  const NotificationsSheet({
    super.key,
    required this.services,
    required this.me,
  });

  final AppServices services;
  final UserProfile? me;

  @override
  Widget build(BuildContext context) {
    final uid = services.game.currentUid;
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (context, scrollController) {
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
                              final calls = callSnap.data ?? const [];
                              final requests = reqSnap.data ?? const [];
                              final challenges = chalSnap.data ?? const [];
                              final acceptedOut = (outSnap.data ?? const [])
                                  .where((c) => c.isAccepted && c.roomId.isNotEmpty)
                                  .toList(growable: false);
                              final unreadChats = chatSnap.data ?? const [];

                              final unreadTotal = unreadChats.fold<int>(
                                0,
                                (sum, c) => sum + c.unreadCountFor(uid),
                              );
                              final total = calls.length +
                                  requests.length +
                                  challenges.length +
                                  acceptedOut.length +
                                  unreadTotal;

                              return ListView(
                                controller: scrollController,
                                padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
                                children: [
                                  Center(
                                    child: Container(
                                      width: 44,
                                      height: 4,
                                      decoration: BoxDecoration(
                                        color: scheme.outlineVariant,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Row(
                                    children: [
                                      Text(
                                        'Notifications',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge
                                            ?.copyWith(fontWeight: FontWeight.w900),
                                      ),
                                      const SizedBox(width: 8),
                                      if (total > 0)
                                        Chip(
                                          label: Text('$total'),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                      const Spacer(),
                                      if (unreadChats.isNotEmpty)
                                        TextButton(
                                          onPressed: () async {
                                            final ids = unreadChats
                                                .map((c) => c.chatId)
                                                .toList(growable: false);
                                            await services.chat
                                                .markAllChatsRead(ids);
                                            for (final id in ids) {
                                              await PushNotificationService
                                                  .cancelMessageNotification(id);
                                            }
                                          },
                                          child: const Text('Mark all read'),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  if (total == 0)
                                    Card(
                                      child: Padding(
                                        padding: const EdgeInsets.all(28),
                                        child: Column(
                                          children: [
                                            const Text(
                                              '🔔',
                                              style: TextStyle(fontSize: 40),
                                            ),
                                            const SizedBox(height: 8),
                                            const Text(
                                              'You’re all caught up!',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 16,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Friend requests, match challenges, unread messages, and voice calls will appear here.',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: scheme.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  for (final call in calls)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Card(
                                        color: scheme.primaryContainer
                                            .withValues(alpha: 0.45),
                                        child: ListTile(
                                          leading: MelowAvatar(
                                            avatarId: call.callerAvatar,
                                            size: 42,
                                          ),
                                          title: Text(
                                            '📞 Incoming call from ${call.callerName}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.call_end_rounded,
                                                  color: Colors.redAccent,
                                                ),
                                                onPressed: () => services
                                                    .voiceCall
                                                    .declineCall(call.callId),
                                              ),
                                              IconButton.filled(
                                                icon: const Icon(
                                                  Icons.call_rounded,
                                                ),
                                                onPressed: () {
                                                  Navigator.pop(context);
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (_) =>
                                                          VoiceCallScreen
                                                              .incoming(
                                                        services: services,
                                                        session: call,
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
                                  for (final req in requests)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Card(
                                        child: ListTile(
                                          leading: MelowAvatar(
                                            avatarId: req.senderAvatar,
                                            size: 40,
                                          ),
                                          title: Text(
                                            'Friend request from ${req.senderName}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.close_rounded,
                                                ),
                                                onPressed: () => services.friends
                                                    .respondFriendRequest(
                                                  request: req,
                                                  accept: false,
                                                ),
                                              ),
                                              IconButton.filled(
                                                icon: const Icon(
                                                  Icons.check_rounded,
                                                ),
                                                onPressed: () => services.friends
                                                    .respondFriendRequest(
                                                  request: req,
                                                  accept: true,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  for (final c in challenges)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Card(
                                        child: ListTile(
                                          leading: MelowAvatar(
                                            avatarId: c.senderAvatar,
                                            size: 40,
                                          ),
                                          title: Text(
                                            '⚔️ ${c.senderName} challenged you',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          subtitle: Text(
                                            '${GameMode.fromId(c.mode).label} • ${c.boardSize}×${c.boardSize} • BO${c.bestOf}',
                                          ),
                                          trailing: FilledButton(
                                            style: FilledButton.styleFrom(
                                              minimumSize: const Size(74, 38),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 12,
                                              ),
                                            ),
                                            onPressed: me == null
                                                ? null
                                                : () async {
                                                    final roomId =
                                                        await services.friends
                                                            .acceptFriendChallenge(
                                                      challenge: c,
                                                      me: me!,
                                                    );
                                                    if (!context.mounted) {
                                                      return;
                                                    }
                                                    Navigator.pop(context);
                                                    Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (_) =>
                                                            RoomPage(
                                                          code: roomId,
                                                          services: services,
                                                        ),
                                                      ),
                                                    );
                                                  },
                                            child: const Text('Play'),
                                          ),
                                        ),
                                      ),
                                    ),
                                  for (final c in acceptedOut)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Card(
                                        child: ListTile(
                                          leading: const Text(
                                            '🎮',
                                            style: TextStyle(fontSize: 28),
                                          ),
                                          title: Text(
                                            '${c.receiverName} accepted your challenge!',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          subtitle: Text('Room ${c.roomId}'),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              FilledButton(
                                                style: FilledButton.styleFrom(
                                                  minimumSize:
                                                      const Size(64, 38),
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 12,
                                                  ),
                                                ),
                                                onPressed: me == null
                                                    ? null
                                                    : () async {
                                                        try {
                                                          await services.game
                                                              .joinRoom(
                                                            code: c.roomId,
                                                            name: me!.nickname,
                                                            emoji: me!
                                                                .preferredEmoji,
                                                            guestAvatar:
                                                                me!.avatarId,
                                                          );
                                                        } catch (_) {}
                                                        await services.friends
                                                            .removeSentChallenge(
                                                                c.id);
                                                        if (!context.mounted) {
                                                          return;
                                                        }
                                                        Navigator.pop(context);
                                                        Navigator.push(
                                                          context,
                                                          MaterialPageRoute(
                                                            builder: (_) =>
                                                                RoomPage(
                                                              code: c.roomId,
                                                              services:
                                                                  services,
                                                            ),
                                                          ),
                                                        );
                                                      },
                                                child: const Text('Join'),
                                              ),
                                              IconButton(
                                                tooltip: 'Remove challenge',
                                                icon: const Icon(
                                                  Icons.close_rounded,
                                                  size: 20,
                                                ),
                                                onPressed: () => services
                                                    .friends
                                                    .removeSentChallenge(c.id),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  for (final chat in unreadChats)
                                    Builder(
                                      builder: (context) {
                                        final otherUid =
                                            chat.otherParticipantUid(uid);
                                        final unread = chat.unreadCountFor(uid);
                                        return Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 8),
                                          child: Card(
                                            child: ListTile(
                                              leading: LiveUserAvatar(
                                                services: services,
                                                uid: otherUid,
                                                size: 40,
                                              ),
                                              title: Text(
                                                chat.lastSenderName.isNotEmpty
                                                    ? chat.lastSenderName
                                                    : 'New Friend Message',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                              subtitle: Text(
                                                chat.lastMessage,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              trailing: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 9,
                                                  vertical: 4,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: scheme.primary,
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  '$unread new',
                                                  style: TextStyle(
                                                    color: scheme.onPrimary,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                              ),
                                              onTap: () async {
                                                // Immediately clear unread badge & Android tray notification once read!
                                                await services.chat
                                                    .markChatRead(chat.chatId);
                                                await PushNotificationService
                                                    .cancelMessageNotification(
                                                        chat.chatId);
                                                if (otherUid.isEmpty) return;
                                                final friendProfile =
                                                    await services.profile
                                                        .getProfile(otherUid);
                                                if (!context.mounted) return;
                                                Navigator.pop(context);
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        FriendChatScreen(
                                                      services: services,
                                                      friendUid: otherUid,
                                                      friendName: friendProfile
                                                              ?.nickname ??
                                                          (chat.lastSenderName
                                                                  .isNotEmpty
                                                              ? chat
                                                                  .lastSenderName
                                                              : 'Friend'),
                                                      friendAvatar:
                                                          friendProfile
                                                                  ?.avatarId ??
                                                              'fox',
                                                      friendPhotoBase64:
                                                          friendProfile
                                                              ?.photoBase64,
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                ],
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
      ),
    );
  }
}
