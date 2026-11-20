import 'package:flutter/material.dart';

import '../../../../domain/models/chat_message.dart';
import '../../../../domain/models/game_room.dart';

/// Live room chat feed with automatic client-side filtering of expired messages.
class RoomChatPanel extends StatelessWidget {
  const RoomChatPanel({
    super.key,
    required this.room,
    required this.currentUid,
    required this.messagesStream,
  });

  final GameRoom room;
  final String currentUid;
  final Stream<List<ChatMessage>> messagesStream;

  String _formatTime(DateTime? dt) {
    if (dt == null) return 'just now';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  '💬 Room Chat',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(
                  'Auto-expires in 24h',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 185,
              child: StreamBuilder<List<ChatMessage>>(
                stream: messagesStream,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Unable to load chat: ${snapshot.error}',
                        style: TextStyle(color: scheme.error, fontSize: 12),
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final items = snapshot.data!
                      .where((msg) => !msg.isExpired())
                      .toList(growable: false);
                  if (items.isEmpty) {
                    return Center(
                      child: Text(
                        'No messages yet. Say hi to your opponent!',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    );
                  }
                  return ListView.builder(
                    reverse: true,
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final msg = items[index];
                      final isOwn = msg.uid == currentUid;
                      final senderLabel = isOwn
                          ? 'You'
                          : '${room.emojiForUid(msg.uid)} ${room.nameForUid(msg.uid)}';
                      return Align(
                        alignment: isOwn
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 280),
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isOwn
                                ? scheme.primaryContainer
                                : scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(14),
                              topRight: const Radius.circular(14),
                              bottomLeft: Radius.circular(isOwn ? 14 : 4),
                              bottomRight: Radius.circular(isOwn ? 4 : 14),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: isOwn
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    senderLabel,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _formatTime(msg.createdAt),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(msg.text),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
