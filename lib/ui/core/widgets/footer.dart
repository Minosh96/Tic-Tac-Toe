import 'package:flutter/material.dart';

/// Branded attribution footer displayed across screens.
class MelowFooter extends StatelessWidget {
  const MelowFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      child: Text(
        'Developed at Melow Labs',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, color: color, letterSpacing: 0.4),
      ),
    );
  }
}
