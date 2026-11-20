import 'dart:math';

import 'package:flutter/material.dart';

import '../../../domain/game_engine.dart';
import '../../core/app_theme.dart';

/// Purely cosmetic Challenge Wheel landing deterministically on [targetOption].
class ChallengeWheelDialog extends StatefulWidget {
  const ChallengeWheelDialog({
    super.key,
    required this.targetOption,
    required this.reducedMotion,
    this.hostEmoji,
    this.guestEmoji,
  });

  final ChallengeWheelOption targetOption;
  final bool reducedMotion;
  final String? hostEmoji;
  final String? guestEmoji;

  @override
  State<ChallengeWheelDialog> createState() => _ChallengeWheelDialogState();
}

class _ChallengeWheelDialogState extends State<ChallengeWheelDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _angle;
  bool _landed = false;

  static const _sliceColors = [
    AppTheme.purpleAccent,
    AppTheme.cyanAccent,
    Color(0xFFEC4899),
    AppTheme.goldAccent,
    Color(0xFF10B981),
    Color(0xFF6366F1),
  ];

  @override
  void initState() {
    super.initState();
    final options = ChallengeWheelOption.values;
    final targetIndex = options.indexOf(widget.targetOption);
    final sliceAngle = (2 * pi) / options.length;
    // Align target slice center with the top pointer (-pi / 2).
    final targetCenterAngle = targetIndex * sliceAngle + sliceAngle / 2;
    final finalRotation = (4 * 2 * pi) - targetCenterAngle - (pi / 2);

    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.reducedMotion ? 150 : 2800),
    );
    _angle = Tween<double>(begin: 0, end: finalRotation).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _landed = true);
      }
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final options = ChallengeWheelOption.values;
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '🎡 Random Challenge Wheel',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              _landed
                  ? 'Challenge locked for this match!'
                  : 'Spinning synchronized challenge…',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: 240,
              height: 256,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    top: 0,
                    child: Icon(
                      Icons.arrow_drop_down_rounded,
                      size: 40,
                      color: scheme.tertiary,
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    child: AnimatedBuilder(
                      animation: _angle,
                      builder: (context, child) {
                        return Transform.rotate(
                          angle: _angle.value,
                          child: child,
                        );
                      },
                      child: CustomPaint(
                        size: const Size(224, 224),
                        painter: _WheelPainter(
                          options: options,
                          colors: _sliceColors,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 88,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: scheme.surface,
                        border: Border.all(color: scheme.primary, width: 3),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _landed ? widget.targetOption.emoji : '🎯',
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            AnimatedOpacity(
              opacity: _landed ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 250),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Text(
                      '${widget.targetOption.emoji} ${widget.targetOption.label}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (widget.targetOption.shuffleEmojis &&
                        widget.hostEmoji != null &&
                        widget.guestEmoji != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Shuffled marks: ${widget.hostEmoji} vs ${widget.guestEmoji}',
                          style: TextStyle(color: scheme.onPrimaryContainer),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _landed ? () => Navigator.pop(context) : null,
              child: Text(_landed ? 'Let’s Play!' : 'Spinning…'),
            ),
          ],
        ),
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  const _WheelPainter({required this.options, required this.colors});

  final List<ChallengeWheelOption> options;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final sweep = (2 * pi) / options.length;

    for (var i = 0; i < options.length; i++) {
      final start = i * sweep;
      final paint = Paint()
        ..color = colors[i % colors.length]
        ..style = PaintingStyle.fill;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sweep,
        true,
        paint,
      );

      final border = Paint()
        ..color = Colors.white.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sweep,
        true,
        border,
      );

      final textAngle = start + sweep / 2;
      final tx = center.dx + cos(textAngle) * radius * 0.65;
      final ty = center.dy + sin(textAngle) * radius * 0.65;
      final tp = TextPainter(
        text: TextSpan(
          text: options[i].emoji,
          style: const TextStyle(fontSize: 22),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(tx - tp.width / 2, ty - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _WheelPainter oldDelegate) => false;
}
