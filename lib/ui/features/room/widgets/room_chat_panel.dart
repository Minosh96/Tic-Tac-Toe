import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/services/app_services.dart';
import '../../../../domain/models/chat_message.dart';
import '../../../../domain/models/game_room.dart';
import '../../../core/widgets/live_user_avatar.dart';
import '../../../core/widgets/melow_avatar.dart';

/// Live room chat feed supporting text + shared images + opponent's live profile photo
/// + in-room chat clear option.
class RoomChatPanel extends StatefulWidget {
  const RoomChatPanel({
    super.key,
    required this.room,
    required this.currentUid,
    required this.messagesStream,
    this.services,
  });

  final GameRoom room;
  final String currentUid;
  final Stream<List<ChatMessage>> messagesStream;
  final AppServices? services;

  @override
  State<RoomChatPanel> createState() => _RoomChatPanelState();
}

class _RoomChatPanelState extends State<RoomChatPanel> {
  DateTime? _clearedBefore;

  String _formatTime(DateTime? dt) {
    if (dt == null) return 'just now';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _clearRoomChat() async {
    setState(() => _clearedBefore = DateTime.now());
    final svc = widget.services;
    if (svc != null) {
      await svc.game.clearRoomChatMessages(widget.room.code);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Room chat cleared.')));
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

  Widget _buildUserAvatar(String uid, String fallbackAvatar, double size) {
    if (widget.services != null && uid.isNotEmpty) {
      return LiveUserAvatar(
        services: widget.services!,
        uid: uid,
        fallbackAvatarId: fallbackAvatar,
        size: size,
        enableFullScreenPreview: true,
      );
    }
    return MelowAvatar(avatarId: fallbackAvatar, size: size);
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final currentUid = widget.currentUid;
    final scheme = Theme.of(context).colorScheme;
    final mySide = room.sideForUid(currentUid);
    final opponentUid = mySide == 'h' ? room.guestId : room.hostId;
    final opponentSide = mySide == 'h' ? 'g' : 'h';
    final opponentAvatar = room.playerAvatar(opponentSide);
    final opponentName = room.playerName(opponentSide);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (opponentUid.isNotEmpty) ...[
                  _buildUserAvatar(opponentUid, opponentAvatar, 30),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    opponentUid.isNotEmpty
                        ? 'Chat with $opponentName'
                        : '💬 Room Chat',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
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
                const SizedBox(width: 4),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Clear Chat',
                  icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                  onPressed: _clearRoomChat,
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 190,
              child: StreamBuilder<List<ChatMessage>>(
                stream: widget.messagesStream,
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
                      .where((msg) {
                        if (msg.isExpired()) return false;
                        if (_clearedBefore != null && msg.createdAt != null) {
                          return msg.createdAt!.isAfter(_clearedBefore!);
                        }
                        return true;
                      })
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
                      final bubble = Container(
                        constraints: const BoxConstraints(maxWidth: 235),
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
                      );

                      if (isOwn) {
                        return Align(
                          alignment: Alignment.centerRight,
                          child: bubble,
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 6, bottom: 4),
                            child: _buildUserAvatar(
                              msg.uid,
                              opponentAvatar,
                              26,
                            ),
                          ),
                          Flexible(child: bubble),
                        ],
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
