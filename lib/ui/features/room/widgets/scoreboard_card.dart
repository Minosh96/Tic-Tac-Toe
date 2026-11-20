import 'package:flutter/material.dart';

import '../../../../domain/models/game_room.dart';

/// Displays matchup players, active turn highlight, and tournament score pips.
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
            Row(
              children: [
                Expanded(
                  child: _PlayerColumn(
                    name: room.hostName,
                    emoji: room.hostEmoji,
                    wins: room.hostWins,
                    winsNeeded: room.winsNeeded,
                    isActive: hostActive,
                    isYou: room.hostId == currentUid,
                    alignment: CrossAxisAlignment.start,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'BO${room.bestOf}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${room.hostWins} - ${room.guestWins}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
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

class _PlayerColumn extends StatelessWidget {
  const _PlayerColumn({
    required this.name,
    required this.emoji,
    required this.wins,
    required this.winsNeeded,
    required this.isActive,
    required this.isYou,
    required this.alignment,
  });

  final String name;
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isActive
            ? scheme.primaryContainer.withValues(alpha: 0.7)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive ? scheme.primary : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(height: 2),
          Text(
            isYou ? '$name (You)' : name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(
              winsNeeded,
              (idx) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Icon(
                  idx < wins ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 16,
                  color: idx < wins
                      ? Colors.amber.shade700
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
