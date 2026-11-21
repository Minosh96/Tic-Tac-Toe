import 'package:flutter/material.dart';

import '../../../core/services/app_services.dart';
import '../../core/app_theme.dart';
import '../../core/widgets/footer.dart';
import '../../core/widgets/melow_logo.dart';
import '../shell/main_shell.dart';

/// Branded animated splash & Firebase bootstrap gate.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.services});

  final AppServices services;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  String? _error;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _scale = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
    _bootstrap();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _error = null;
      _ready = false;
    });
    try {
      await widget.services.preferences.loadLocal();
      await widget.services.game.ensureSignedIn();
      await widget.services.profile.ensureProfile();
      try {
        final cloudPrefs =
            await widget.services.profile.fetchPrivatePreferences();
        widget.services.preferences.applyCloudPreferences(cloudPrefs);
      } catch (_) {
        // Offline or first run — local preferences remain active.
      }
      await Future<void>.delayed(const Duration(milliseconds: 550));
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to connect to Melow servers. '
            'Check your internet connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) {
      return MainShell(services: widget.services);
    }

    final scheme = Theme.of(context).colorScheme;
    final reducedMotion = widget.services.preferences.reducedMotion ||
        MediaQuery.of(context).disableAnimations;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: Theme.of(context).brightness == Brightness.dark
                ? const [AppTheme.darkBackground, Color(0xFF1D1742)]
                : const [AppTheme.lightBackground, Color(0xFFEDE9FE)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(),
              Center(
                child: FadeTransition(
                  opacity: reducedMotion ? kAlwaysCompleteAnimation : _fade,
                  child: ScaleTransition(
                    scale: reducedMotion ? kAlwaysCompleteAnimation : _scale,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const MelowLogo(size: 112, borderRadius: 28),
                        const SizedBox(height: 24),
                        Text(
                          'Melow Tic Tac Toe',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Version 3.0 • Play • Chat • Call • Win',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 36),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    children: [
                      Icon(
                        Icons.wifi_off_rounded,
                        size: 38,
                        color: scheme.error,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: 200,
                        child: FilledButton.icon(
                          onPressed: _bootstrap,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Retry'),
                        ),
                      ),
                    ],
                  ),
                )
              else
                const SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
              const Spacer(),
              const MelowFooter(),
            ],
          ),
        ),
      ),
    );
  }
}
