import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/services/app_services.dart';
import '../../../core/services/image_helper.dart';
import '../../../domain/models/social_models.dart';
import '../../core/widgets/melow_avatar.dart';
import 'voice_call_screen.dart';

/// Direct 1-on-1 Friend Chat screen supporting text, image sharing & voice calls.
class FriendChatScreen extends StatefulWidget {
  const FriendChatScreen({
    super.key,
    required this.services,
    required this.friendUid,
    required this.friendName,
    required this.friendAvatar,
    this.friendPhotoBase64,
  });

  final AppServices services;
  final String friendUid;
  final String friendName;
  final String friendAvatar;
  final String? friendPhotoBase64;

  @override
  State<FriendChatScreen> createState() => _FriendChatScreenState();
}

class _FriendChatScreenState extends State<FriendChatScreen> {
  final TextEditingController _inputController = TextEditingController();
  String? _chatId;
  bool _sending = false;
  String _myName = 'Player';
  String _myAvatar = 'astro';

  @override
  void initState() {
    super.initState();
    _initThread();
  }

  Future<void> _initThread() async {
    try {
      final me = await widget.services.profile
          .getProfile(widget.services.game.currentUid);
      final id =
          await widget.services.chat.ensureChatThread(widget.friendUid);
      await widget.services.chat.markChatRead(id);
      if (!mounted) return;
      setState(() {
        _chatId = id;
        if (me != null) {
          _myName = me.nickname;
          _myAvatar = me.avatarId;
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open chat: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _sendText() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.services.chat.sendMessage(
        friendUid: widget.friendUid,
        senderName: _myName,
        text: text,
      );
      _inputController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      final base64Img = await ImageHelper.pickChatImageBase64(source: source);
      if (base64Img == null) return;
      await widget.services.chat.sendMessage(
        friendUid: widget.friendUid,
        senderName: _myName,
        text: _inputController.text.trim(),
        imageBase64: base64Img,
      );
      _inputController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showImageSourcePicker() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndSendImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: const Text('Take a Photo'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndSendImage(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _startVoiceCall() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VoiceCallScreen.outgoing(
          services: widget.services,
          calleeUid: widget.friendUid,
          calleeName: widget.friendName,
          calleeAvatar: widget.friendAvatar,
          callerName: _myName,
          callerAvatar: _myAvatar,
        ),
      ),
    );
  }

  void _openFullImage(Uint8List bytes) {
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

  String _formatTime(DateTime? dt) {
    if (dt == null) return 'now';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final myUid = widget.services.game.currentUid;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            MelowAvatar(
              avatarId: widget.friendAvatar,
              photoBase64: widget.friendPhotoBase64,
              size: 36,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.friendName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton.filledTonal(
            tooltip: 'Start Voice Call',
            icon: const Icon(Icons.call_rounded),
            onPressed: _startVoiceCall,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _chatId == null
                  ? const Center(child: CircularProgressIndicator())
                  : StreamBuilder<List<DirectChatMessage>>(
                      stream: widget.services.chat.watchMessages(_chatId!),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text('Chat error: ${snapshot.error}'),
                            ),
                          );
                        }
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final items = snapshot.data!;
                        if (items.isNotEmpty) {
                          widget.services.chat.markChatRead(_chatId!);
                        }
                        if (items.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(28),
                              child: Text(
                                'Say hi to ${widget.friendName}, share a photo, or start a voice call! 🎙️',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: scheme.onSurfaceVariant),
                              ),
                            ),
                          );
                        }
                        return ListView.builder(
                          reverse: true,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          itemCount: items.length,
                          itemBuilder: (context, idx) {
                            final msg = items[idx];
                            final isMe = msg.senderUid == myUid;
                            Uint8List? imgBytes;
                            if (msg.hasImage) {
                              try {
                                imgBytes = base64Decode(msg.imageBase64!);
                              } catch (_) {}
                            }
                            return Align(
                              alignment: isMe
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.of(context).size.width * 0.76,
                                ),
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isMe
                                      ? scheme.primaryContainer
                                      : scheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(16),
                                    topRight: const Radius.circular(16),
                                    bottomLeft: Radius.circular(isMe ? 16 : 4),
                                    bottomRight: Radius.circular(isMe ? 4 : 16),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: isMe
                                      ? CrossAxisAlignment.end
                                      : CrossAxisAlignment.start,
                                  children: [
                                    if (imgBytes != null) ...[
                                      GestureDetector(
                                        onTap: () => _openFullImage(imgBytes!),
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          child: Image.memory(
                                            imgBytes,
                                            fit: BoxFit.cover,
                                            height: 180,
                                            width: 220,
                                          ),
                                        ),
                                      ),
                                      if (msg.text.isNotEmpty)
                                        const SizedBox(height: 6),
                                    ],
                                    if (msg.text.isNotEmpty)
                                      Text(
                                        msg.text,
                                        style: const TextStyle(fontSize: 15),
                                      ),
                                    const SizedBox(height: 3),
                                    Text(
                                      _formatTime(msg.createdAt),
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
            Container(
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border(
                  top: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.6),
                  ),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Share photo',
                    onPressed: _sending ? null : _showImageSourcePicker,
                    icon: const Icon(Icons.photo_outlined),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      maxLength: 500,
                      maxLines: 1,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendText(),
                      decoration: const InputDecoration(
                        hintText: 'Message friend…',
                        counterText: '',
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 11,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Send',
                    onPressed: _sending ? null : _sendText,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
