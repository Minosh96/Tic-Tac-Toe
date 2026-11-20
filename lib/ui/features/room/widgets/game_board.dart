import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_theme.dart';

/// Responsive, animated N×N Tic-Tac-Toe board with neon winning-line glow & haptics.
class GameBoard extends StatelessWidget {
  const GameBoard({
    super.key,
    required this.size,
    required this.board,
    required this.emojiForSide,
    required this.canPlay,
    required this.onCellTap,
    this.winningLine = const [],
    this.reducedMotion = false,
    this.hapticsEnabled = true,
  });

  final int size;
  final List<String> board;
  final String Function(String side) emojiForSide;
  final bool canPlay;
  final ValueChanged<int> onCellTap;
  final List<int> winningLine;
  final bool reducedMotion;
  final bool hapticsEnabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final winSet = winningLine.toSet();
    final gap = size >= 5 ? 5.0 : 9.0;
    final radius = size >= 5 ? 11.0 : 16.0;

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
                padding: EdgeInsets.all(gap + 2),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppTheme.darkSurface
                      : scheme.surfaceContainerHighest.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(radius + 8),
                  border: Border.all(
                    color: canPlay
                        ? scheme.primary.withValues(alpha: 0.55)
                        : scheme.outlineVariant.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (canPlay ? AppTheme.purpleAccent : Colors.black)
                          .withValues(alpha: isDark ? 0.25 : 0.08),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
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
                        ? AppTheme.goldAccent.withValues(
                            alpha: isDark ? 0.34 : 0.28,
                          )
                        : mark.isNotEmpty
                            ? (isDark
                                ? AppTheme.darkSurfaceHigh
                                : scheme.primaryContainer.withValues(alpha: 0.6))
                            : (isDark
                                ? AppTheme.darkBackground.withValues(alpha: 0.8)
                                : scheme.surface);

                    final borderColor = isWinningCell
                        ? AppTheme.goldAccent
                        : isTappable
                            ? scheme.primary.withValues(alpha: 0.38)
                            : scheme.outlineVariant.withValues(alpha: 0.35);

                    return Semantics(
                      button: isTappable,
                      excludeSemantics: true,
                      label: mark.isEmpty
                          ? 'Cell ${index + 1}, empty'
                          : 'Cell ${index + 1}, $displayEmoji',
                      child: AnimatedContainer(
                        duration: Duration(
                          milliseconds: reducedMotion ? 0 : 220,
                        ),
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(radius),
                          border: Border.all(
                            color: borderColor,
                            width: isWinningCell ? 2.6 : 1.2,
                          ),
                          boxShadow: isWinningCell
                              ? [
                                  BoxShadow(
                                    color: AppTheme.goldAccent
                                        .withValues(alpha: 0.45),
                                    blurRadius: 12,
                                  ),
                                ]
                              : null,
                        ),
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(radius),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(radius),
                            onTap: isTappable
                                ? () {
                                    if (hapticsEnabled) {
                                      HapticFeedback.lightImpact();
                                    }
                                    onCellTap(index);
                                  }
                                : null,
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: AnimatedSwitcher(
                                  duration: Duration(
                                    milliseconds: reducedMotion ? 0 : 220,
                                  ),
                                  transitionBuilder: (child, anim) =>
                                      reducedMotion
                                          ? child
                                          : ScaleTransition(
                                              scale: CurvedAnimation(
                                                parent: anim,
                                                curve: Curves.easeOutBack,
                                              ),
                                              child: child,
                                            ),
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
