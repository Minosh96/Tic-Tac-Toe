import 'package:flutter/material.dart';

import '../../../core/services/app_services.dart';
import '../../../domain/models/user_profile.dart';
import 'melow_avatar.dart';

/// Streams a player's live `users/{uid}` profile so custom gallery photos
/// immediately appear in chats, friends lists, incoming calls & call screens.
class LiveUserAvatar extends StatelessWidget {
  const LiveUserAvatar({
    super.key,
    required this.services,
    required this.uid,
    this.fallbackAvatarId = 'astro',
    this.fallbackPhotoBase64,
    this.size = 44,
    this.borderColor,
  });

  final AppServices services;
  final String uid;
  final String fallbackAvatarId;
  final String? fallbackPhotoBase64;
  final double size;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    if (uid.isEmpty) {
      return MelowAvatar(
        avatarId: fallbackAvatarId,
        photoBase64: fallbackPhotoBase64,
        size: size,
        borderColor: borderColor,
      );
    }
    return StreamBuilder<UserProfile?>(
      stream: services.profile.watchProfile(uid),
      builder: (context, snap) {
        final p = snap.data;
        return MelowAvatar(
          avatarId: p?.avatarId ?? fallbackAvatarId,
          photoBase64: p?.photoBase64 ?? fallbackPhotoBase64,
          size: size,
          borderColor: borderColor,
        );
      },
    );
  }
}
