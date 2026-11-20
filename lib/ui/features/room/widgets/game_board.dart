import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Responsive, animated N×N Tic-Tac-Toe board with winning-line highlighting.
class GameBoard extends StatelessWidget {
  const GameBoard({
    super.key,
    required this.size,
    required this.board,
    required this.emojiForSide,
    required this.canPlay,
    required this.onCellTap,
    this.winningLine = const [],
  });

  final int size;
  final List<String> board;
  final String Function(String side) emojiForSide;
  final bool canPlay;
  final ValueChanged<int> onCellTap;
  final List<int> winningLine;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final winSet = winningLine.toSet();
    final gap = size >= 5 ? 5.0 : 8.0;
    final radius = size >= 5 ? 10.0 : 14.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? min(constraints.maxWidth, 420.0)
            : 360.0;
        return Center(
          child: SizedBox(
            width: maxWidth,
            child: AspectRatio(
              aspectRatio: 1,
              child: Container(
                padding: EdgeInsets.all(gap),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(radius + 6),
                ),
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: size,
                    mainAxisSpacing: gap,
                    crossAxisSpacing: gap,
                  ),
                  itemCount: board.length,
                  itemBuilder: (context, index) {
                    final mark = board[index];
                    final isWinningCell = winSet.contains(index);
                    final isTappable = canPlay && mark.isEmpty;
                    final displayEmoji = mark.isEmpty ? '' : emojiForSide(mark);

                    final bgColor = isWinningCell
                        ? scheme.tertiaryContainer
                        : mark.isNotEmpty
                            ? scheme.primaryContainer
                            : scheme.surface;

                    final borderColor = isWinningCell
                        ? scheme.tertiary
                        : isTappable
                            ? scheme.primary.withValues(alpha: 0.35)
                            : scheme.outlineVariant.withValues(alpha: 0.5);

                    return Semantics(
                      button: isTappable,
                      excludeSemantics: true,
                      label: mark.isEmpty
                          ? 'Cell ${index + 1}, empty'
                          : 'Cell ${index + 1}, $displayEmoji',
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(radius),
                          border: Border.all(
                            color: borderColor,
                            width: isWinningCell ? 2.5 : 1.2,
                          ),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(radius),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(radius),
                            onTap: isTappable
                                ? () {
                                    HapticFeedback.lightImpact();
                                    onCellTap(index);
                                  }
                                : null,
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 200),
                                  transitionBuilder: (child, anim) =>
                                      ScaleTransition(scale: anim, child: child),
                                  child: displayEmoji.isEmpty
                                      ? const SizedBox.shrink(
                                          key: ValueKey('empty'),
                                        )
                                      : FittedBox(
                                          key: ValueKey(
                                            '$index-$displayEmoji',
                                          ),
                                          child: Text(
                                            displayEmoji,
                                            style: TextStyle(
                                              fontSize: 54.0 / (size / 3),
                                            ),
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
