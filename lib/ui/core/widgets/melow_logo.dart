import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Displays the custom Melow logo (`assets/images/melow_logo.png`) with graceful fallback.
class MelowLogo extends StatelessWidget {
  const MelowLogo({
    super.key,
    this.size = 64,
    this.borderRadius = 18,
    this.showGlow = true,
  });

  final double size;
  final double borderRadius;
  final bool showGlow;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: showGlow
            ? [
                BoxShadow(
                  color: AppTheme.purpleAccent.withValues(
                    alpha: isDark ? 0.42 : 0.22,
                  ),
                  blurRadius: size * 0.3,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Image.asset(
          'assets/images/melow_logo.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.purpleAccent, AppTheme.cyanAccent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              'M',
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
