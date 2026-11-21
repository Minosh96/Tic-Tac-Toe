import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../domain/models/chat_message.dart';
import '../../../../domain/models/game_room.dart';

/// Live room chat feed supporting text + shared images with 24h expiry filtering.
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

  void _openImageViewer(BuildContext context, Uint8List bytes) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(
              child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton.filled(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
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
                const Expanded(
                  child: Text(
                    '💬 Room Chat',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  'Expires in 24h',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 190,
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
                        'No messages yet. Say hi or share a photo!',
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
                      Uint8List? imgBytes;
                      if (msg.hasImage) {
                        try {
                          imgBytes = base64Decode(msg.imageBase64!);
                        } catch (_) {}
                      }
                      return Align(
                        alignment: isOwn
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 260),
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
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
                                  Flexible(
                                    child: Text(
                                      senderLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: scheme.onSurfaceVariant,
                                      ),
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
                              if (imgBytes != null) ...[
                                const SizedBox(height: 6),
                                GestureDetector(
                                  onTap: () =>
                                      _openImageViewer(context, imgBytes!),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.memory(
                                      imgBytes,
                                      width: 190,
                                      height: 140,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              ],
                              if (msg.text.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(msg.text),
                              ],
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
