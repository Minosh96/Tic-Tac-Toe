import 'package:flutter/material.dart';

/// Built-in playful avatar choices (no personal photo uploads required).
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

const List<AvatarOption> melowAvatars = [
  AvatarOption(id: 'astro', emoji: '🧑‍🚀', label: 'Astro', color: Color(0xFF8B5CF6)),
  AvatarOption(id: 'fox', emoji: '🦊', label: 'Fox', color: Color(0xFFF97316)),
  AvatarOption(id: 'cat', emoji: '🐱', label: 'Cat', color: Color(0xFFEC4899)),
  AvatarOption(id: 'bot', emoji: '🤖', label: 'Robo', color: Color(0xFF06B6D4)),
  AvatarOption(id: 'dragon', emoji: '🐉', label: 'Dragon', color: Color(0xFF10B981)),
  AvatarOption(id: 'owl', emoji: '🦉', label: 'Owl', color: Color(0xFF6366F1)),
  AvatarOption(id: 'panda', emoji: '🐼', label: 'Panda', color: Color(0xFF64748B)),
  AvatarOption(id: 'lion', emoji: '🦁', label: 'Lion', color: Color(0xFFF59E0B)),
  AvatarOption(id: 'unicorn', emoji: '🦄', label: 'Spark', color: Color(0xFFD946EF)),
  AvatarOption(id: 'shark', emoji: '🦈', label: 'Shark', color: Color(0xFF0EA5E9)),
  AvatarOption(id: 'ninja', emoji: '🥷', label: 'Ninja', color: Color(0xFF475569)),
  AvatarOption(id: 'crown', emoji: '👑', label: 'Royal', color: Color(0xFFEAB308)),
];

AvatarOption avatarById(String id) {
  return melowAvatars.firstWhere(
    (a) => a.id == id,
    orElse: () => melowAvatars.first,
  );
}

class MelowAvatar extends StatelessWidget {
  const MelowAvatar({
    super.key,
    required this.avatarId,
    this.size = 44,
    this.borderColor,
  });

  final String avatarId;
  final double size;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final option = avatarById(avatarId);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            option.color.withValues(alpha: 0.9),
            option.color.withValues(alpha: 0.55),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: borderColor ?? option.color.withValues(alpha: 0.8),
          width: 2,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        option.emoji,
        style: TextStyle(fontSize: size * 0.52),
      ),
    );
  }
}
