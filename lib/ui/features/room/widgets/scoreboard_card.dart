import 'package:flutter/material.dart';

import '../../../../domain/models/game_room.dart';
import '../../../core/app_theme.dart';
import '../../../core/widgets/melow_avatar.dart';

/// Displays both players (avatar, nickname, emoji), mode/board pills, active turn & score pips.
class ScoreboardCard extends StatelessWidget {
  const ScoreboardCard({
    super.key,
    required this.room,
    required this.currentUid,
  });

  final GameRoom room;
  final String currentUid;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hostActive = !room.isLobby && !room.roundDone && room.turn == 'h';
    final guestActive = !room.isLobby && !room.roundDone && room.turn == 'g';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                _InfoPill(
                  icon:
                      room.isBlitz ? Icons.bolt_rounded : Icons.grid_on_rounded,
                  label: room.gameMode.label,
                  highlight: room.isBlitz,
                ),
                _InfoPill(
                  icon: Icons.apps_rounded,
                  label: '${room.size}×${room.size}',
                ),
                _InfoPill(
                  icon: Icons.emoji_events_outlined,
                  label: 'BO${room.bestOf}',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _PlayerColumn(
                    name: room.hostName,
                    avatarId: room.hostAvatar,
                    emoji: room.hostEmoji,
                    wins: room.hostWins,
                    winsNeeded: room.winsNeeded,
                    isActive: hostActive,
                    isYou: room.hostId == currentUid,
                    alignment: CrossAxisAlignment.start,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Column(
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${room.hostWins} - ${room.guestWins}',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Text(
                        'Round ${room.round}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: scheme.primary,
                        ),
                      ),
                      if (room.draws > 0)
                        Text(
                          'Draws: ${room.draws}',
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: _PlayerColumn(
                    name: room.isLobby ? 'Waiting…' : room.guestName,
                    avatarId: room.isLobby ? 'bot' : room.guestAvatar,
                    emoji: room.isLobby ? '⏳' : room.guestEmoji,
                    wins: room.guestWins,
                    winsNeeded: room.winsNeeded,
                    isActive: guestActive,
                    isYou: room.guestId == currentUid,
                    alignment: CrossAxisAlignment.end,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.icon,
    required this.label,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: highlight
            ? AppTheme.goldAccent.withValues(alpha: 0.22)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: highlight ? AppTheme.goldAccent : scheme.primary,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: highlight ? AppTheme.goldAccent : scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerColumn extends StatelessWidget {
  const _PlayerColumn({
    required this.name,
    required this.avatarId,
    required this.emoji,
    required this.wins,
    required this.winsNeeded,
    required this.isActive,
    required this.isYou,
    required this.alignment,
  });

  final String name;
  final String avatarId;
  final String emoji;
  final int wins;
  final int winsNeeded;
  final bool isActive;
  final bool isYou;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: isActive
            ? scheme.primaryContainer.withValues(alpha: 0.65)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? scheme.primary : Colors.transparent,
          width: 1.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (alignment == CrossAxisAlignment.end) ...[
                Text(emoji, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 5),
              ],
              MelowAvatar(avatarId: avatarId, size: 32),
              if (alignment == CrossAxisAlignment.start) ...[
                const SizedBox(width: 5),
                Text(emoji, style: const TextStyle(fontSize: 20)),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            isYou ? '$name (You)' : name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: alignment == CrossAxisAlignment.end
                ? TextAlign.right
                : TextAlign.left,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
          const SizedBox(height: 5),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(
              winsNeeded,
              (idx) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: Icon(
                  idx < wins ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 15,
                  color: idx < wins
                      ? AppTheme.goldAccent
                      : scheme.outlineVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
