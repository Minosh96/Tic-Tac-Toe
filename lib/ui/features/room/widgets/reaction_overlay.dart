import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../domain/models/room_reaction.dart';

/// Displays short-lived floating animated emojis & quick taunts for ~2 seconds.
class ReactionOverlay extends StatefulWidget {
  const ReactionOverlay({
    super.key,
    required this.latestReaction,
    required this.senderLabel,
    required this.muted,
    required this.reducedMotion,
  });

  final RoomReaction? latestReaction;
  final String senderLabel;
  final bool muted;
  final bool reducedMotion;

  @override
  State<ReactionOverlay> createState() => _ReactionOverlayState();
}

class _ReactionOverlayState extends State<ReactionOverlay> {
  String? _shownId;
  RoomReaction? _active;
  Timer? _dismissTimer;

  @override
  void didUpdateWidget(covariant ReactionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.latestReaction;
    if (widget.muted || next == null) return;
    if (next.id == _shownId) return;
    // Ignore stale reactions older than 6 seconds on initial room load.
    if (DateTime.now().difference(next.createdAt).inSeconds > 6) {
      _shownId = next.id;
      return;
    }
    _shownId = next.id;
    _dismissTimer?.cancel();
    setState(() => _active = next);
    _dismissTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _active = null);
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reaction = _active;
    if (widget.muted || reaction == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: Center(
        child: TweenAnimationBuilder<double>(
          key: ValueKey(reaction.id),
          tween: Tween(begin: 0.0, end: 1.0),
          duration: Duration(milliseconds: widget.reducedMotion ? 80 : 320),
          curve: Curves.easeOutBack,
          builder: (context, value, child) {
            return Opacity(
              opacity: value.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, widget.reducedMotion ? 0 : (1 - value) * 28),
                child: Transform.scale(
                  scale: widget.reducedMotion ? 1.0 : 0.75 + 0.25 * value,
                  child: child,
                ),
              ),
            );
          },
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: reaction.isEmoji ? 22 : 18,
              vertical: reaction.isEmoji ? 12 : 10,
            ),
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: scheme.primary.withValues(alpha: 0.65),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.3),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.senderLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  reaction.payload,
                  style: TextStyle(
                    fontSize: reaction.isEmoji ? 42 : 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
