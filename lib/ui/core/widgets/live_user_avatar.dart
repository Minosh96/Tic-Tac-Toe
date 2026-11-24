import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/services/app_services.dart';
import '../../../domain/models/user_profile.dart';
import 'melow_avatar.dart';

/// Streams a player's live `users/{uid}` profile with an in-memory cache and
/// stable stream subscription so updated nicknames and custom gallery photos
/// appear immediately across Friends, Home, Chat, Calls & Notifications.
class LiveUserProfileBuilder extends StatefulWidget {
  const LiveUserProfileBuilder({
    super.key,
    required this.services,
    required this.uid,
    required this.builder,
  });

  final AppServices services;
  final String uid;
  final Widget Function(BuildContext context, UserProfile? profile) builder;

  static final Map<String, UserProfile> cache = <String, UserProfile>{};

  @override
  State<LiveUserProfileBuilder> createState() => _LiveUserProfileBuilderState();
}

class _LiveUserProfileBuilderState extends State<LiveUserProfileBuilder> {
  Stream<UserProfile?>? _stream;

  @override
  void initState() {
    super.initState();
    _initStream();
  }

  @override
  void didUpdateWidget(covariant LiveUserProfileBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) {
      _initStream();
    }
  }

  void _initStream() {
    if (widget.uid.isEmpty) {
      _stream = null;
      return;
    }
    final myUid = widget.services.game.maybeCurrentUid;
    _stream = widget.services.profile
        .watchProfile(widget.uid)
        .map((profile) {
          if (profile == null) return null;
          // Enforce Private visibility masking when viewed by other users.
          final effective = (profile.isPrivate && widget.uid != myUid)
              ? UserProfile(
                  uid: profile.uid,
                  nickname: profile.defaultSystemNickname,
                  avatarId: 'astro',
                  photoBase64: null,
                  preferredEmoji: profile.preferredEmoji,
                  friendCode: profile.friendCode,
                  publicProfileEnabled: false,
                  leaderboardOptIn: false,
                  profileVisibility: ProfileVisibility.private,
                )
              : profile;
          if (LiveUserProfileBuilder.cache.length > 100) {
            LiveUserProfileBuilder.cache.clear();
          }
          LiveUserProfileBuilder.cache[widget.uid] = effective;
          return effective;
        })
        .handleError((_) {
          // When target profile is Private or Friends-Only for a non-friend,
          // Firestore security rules block read access; remove any stale cache.
          LiveUserProfileBuilder.cache.remove(widget.uid);
        });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.uid.isEmpty || _stream == null) {
      return widget.builder(context, null);
    }
    final cached = LiveUserProfileBuilder.cache[widget.uid];
    return StreamBuilder<UserProfile?>(
      stream: _stream,
      initialData: cached,
      builder: (context, snap) {
        return widget.builder(context, snap.data ?? cached);
      },
    );
  }
}

/// Renders a player's live avatar (custom gallery photo or built-in avatar)
/// backed by [LiveUserProfileBuilder].
class LiveUserAvatar extends StatelessWidget {
  const LiveUserAvatar({
    super.key,
    required this.services,
    required this.uid,
    this.fallbackAvatarId = 'astro',
    this.fallbackPhotoBase64,
    this.size = 44,
    this.borderColor,
    this.enableFullScreenPreview = false,
  });

  final AppServices services;
  final String uid;
  final String fallbackAvatarId;
  final String? fallbackPhotoBase64;
  final double size;
  final Color? borderColor;
  final bool enableFullScreenPreview;

  void _openPreview(BuildContext context, String photoBase64, String? nickname) {
    Uint8List? bytes;
    try {
      bytes = base64Decode(photoBase64);
    } catch (_) {
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(20),
        child: Stack(
          children: [
            InteractiveViewer(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (nickname != null && nickname.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          nickname,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image.memory(bytes!, fit: BoxFit.contain),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
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
    return LiveUserProfileBuilder(
      services: services,
      uid: uid,
      builder: (context, p) {
        final photo = (p?.photoBase64 != null && p!.photoBase64!.isNotEmpty)
            ? p.photoBase64
            : fallbackPhotoBase64;
        final avatar = MelowAvatar(
          avatarId: p?.avatarId ?? fallbackAvatarId,
          photoBase64: photo,
          size: size,
          borderColor: borderColor,
        );
        if (enableFullScreenPreview && photo != null && photo.isNotEmpty) {
          return GestureDetector(
            onTap: () => _openPreview(context, photo, p?.nickname),
            child: avatar,
          );
        }
        return avatar;
      },
    );
  }
}
