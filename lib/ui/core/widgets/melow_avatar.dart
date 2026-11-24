import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Built-in playful avatar choices (including Boy, Girl & fun characters).
class AvatarOption {
  const AvatarOption({
    required this.id,
    required this.emoji,
    required this.label,
    required this.color,
  });

  final String id;
  final String emoji;
  final String label;
  final Color color;
}

/// Built-in playful avatar choices using 100% universal Unicode 6.0–9.0 emojis
/// guaranteed to render on every Android device (no missing-glyph boxes!).
const List<AvatarOption> melowAvatars = [
  AvatarOption(id: 'astro', emoji: '🚀', label: 'Astro', color: Color(0xFF8B5CF6)),
  AvatarOption(id: 'boy', emoji: '👦', label: 'Boy', color: Color(0xFF3B82F6)),
  AvatarOption(id: 'girl', emoji: '👧', label: 'Girl', color: Color(0xFFEC4899)),
  AvatarOption(id: 'fox', emoji: '🦊', label: 'Fox', color: Color(0xFFF97316)),
  AvatarOption(id: 'cat', emoji: '🐱', label: 'Cat', color: Color(0xFFF43F5E)),
  AvatarOption(id: 'bot', emoji: '🤖', label: 'Robo', color: Color(0xFF06B6D4)),
  AvatarOption(id: 'dragon', emoji: '🐉', label: 'Dragon', color: Color(0xFF10B981)),
  AvatarOption(id: 'owl', emoji: '🦉', label: 'Owl', color: Color(0xFF6366F1)),
  AvatarOption(id: 'panda', emoji: '🐼', label: 'Panda', color: Color(0xFF64748B)),
  AvatarOption(id: 'lion', emoji: '🦁', label: 'Lion', color: Color(0xFFF59E0B)),
  AvatarOption(id: 'unicorn', emoji: '🦄', label: 'Spark', color: Color(0xFFD946EF)),
  AvatarOption(id: 'clown', emoji: '🤡', label: 'Jester', color: Color(0xFFEF4444)),
  AvatarOption(id: 'ninja', emoji: '😎', label: 'Cool', color: Color(0xFF475569)),
  AvatarOption(id: 'crown', emoji: '👑', label: 'Royal', color: Color(0xFFEAB308)),
  AvatarOption(id: 'alien', emoji: '👽', label: 'Alien', color: Color(0xFF14B8A6)),
  AvatarOption(id: 'ghost', emoji: '👻', label: 'Ghost', color: Color(0xFFA855F7)),
  AvatarOption(id: 'tiger', emoji: '🐯', label: 'Tiger', color: Color(0xFFEA580C)),
  AvatarOption(id: 'penguin', emoji: '🐧', label: 'Penguin', color: Color(0xFF0284C7)),
  AvatarOption(id: 'koala', emoji: '🐨', label: 'Koala', color: Color(0xFF4F46E5)),
  AvatarOption(id: 'cowboy', emoji: '🤠', label: 'Ranger', color: Color(0xFFD97706)),
  AvatarOption(id: 'prince', emoji: '🤴', label: 'Prince', color: Color(0xFF2563EB)),
  AvatarOption(id: 'princess', emoji: '👸', label: 'Princess', color: Color(0xFFDB2777)),
];

AvatarOption avatarById(String id) {
  return melowAvatars.firstWhere(
    (a) => a.id == id,
    orElse: () => melowAvatars.first,
  );
}

final Map<int, Uint8List> _decodedPhotoCache = <int, Uint8List>{};

Uint8List? _decodeCached(String? base64Str) {
  if (base64Str == null || base64Str.isEmpty) return null;
  final key = base64Str.hashCode;
  final cached = _decodedPhotoCache[key];
  if (cached != null) return cached;
  try {
    final bytes = base64Decode(base64Str);
    if (_decodedPhotoCache.length > 60) {
      _decodedPhotoCache.clear();
    }
    _decodedPhotoCache[key] = bytes;
    return bytes;
  } catch (_) {
    return null;
  }
}

/// Renders either the player's custom gallery photo (`photoBase64`) or built-in avatar.
class MelowAvatar extends StatelessWidget {
  const MelowAvatar({
    super.key,
    required this.avatarId,
    this.photoBase64,
    this.size = 44,
    this.borderColor,
  });

  final String avatarId;
  final String? photoBase64;
  final double size;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final option = avatarById(avatarId);
    final bytes = _decodeCached(photoBase64);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: bytes == null
            ? LinearGradient(
                colors: [
                  option.color.withValues(alpha: 0.9),
                  option.color.withValues(alpha: 0.55),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        border: Border.all(
          color: borderColor ?? option.color.withValues(alpha: 0.85),
          width: 2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: bytes != null
          ? Image.memory(
              bytes,
              width: size,
              height: size,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => Text(
                option.emoji,
                style: TextStyle(fontSize: size * 0.52),
              ),
            )
          : Text(
              option.emoji,
              style: TextStyle(fontSize: size * 0.52),
            ),
    );
  }
}
