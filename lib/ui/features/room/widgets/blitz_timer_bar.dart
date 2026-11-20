import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../domain/game_engine.dart';

/// Isolated 5-second Blitz countdown widget so ticks never rebuild the full game screen.
class BlitzTimerBar extends StatefulWidget {
  const BlitzTimerBar({
    super.key,
    required this.deadline,
    required this.round,
    required this.turnKey,
    required this.active,
    required this.isMyTurn,
    required this.onExpired,
  });

  final DateTime? deadline;
  final int round;
  final String turnKey;
  final bool active;
  final bool isMyTurn;
  final VoidCallback onExpired;

  @override
  State<BlitzTimerBar> createState() => _BlitzTimerBarState();
}

class _BlitzTimerBarState extends State<BlitzTimerBar> {
  Timer? _timer;
  Duration _remaining = const Duration(seconds: kBlitzTurnSeconds);
  bool _firedForTurn = false;

  @override
  void initState() {
    super.initState();
    _syncAndStart();
  }

  @override
  void didUpdateWidget(covariant BlitzTimerBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.turnKey != widget.turnKey ||
        oldWidget.deadline != widget.deadline ||
        oldWidget.active != widget.active) {
      _firedForTurn = false;
      _syncAndStart();
    }
  }

  void _syncAndStart() {
    _timer?.cancel();
    if (!widget.active || widget.deadline == null) {
      setState(() => _remaining = const Duration(seconds: kBlitzTurnSeconds));
      return;
    }
    _tick();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
  }

  void _tick() {
    if (!mounted) return;
    final rem = GameEngine.remainingBlitzTime(
      deadline: widget.deadline,
      now: DateTime.now(),
    );
    setState(() => _remaining = rem);
    if (rem == Duration.zero && !_firedForTurn && widget.active) {
      _firedForTurn = true;
      _timer?.cancel();
      widget.onExpired();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = kBlitzTurnSeconds * 1000;
    final progress = (_remaining.inMilliseconds / totalMs).clamp(0.0, 1.0);
    final secondsText = (_remaining.inMilliseconds / 1000.0).toStringAsFixed(1);
    final urgent = progress < 0.35;
    final scheme = Theme.of(context).colorScheme;
    final barColor = urgent
        ? scheme.error
        : widget.isMyTurn
            ? scheme.secondary
            : scheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: urgent
            ? scheme.errorContainer.withValues(alpha: 0.55)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: urgent ? scheme.error : barColor.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.bolt_rounded, size: 18, color: barColor),
              const SizedBox(width: 6),
              Text(
                widget.isMyTurn ? 'BLITZ — Your move!' : 'BLITZ — Opponent clock',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: urgent ? scheme.error : scheme.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                '${secondsText}s',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: urgent ? scheme.error : barColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              color: barColor,
              backgroundColor: scheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }
}
