import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/services/app_services.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../core/app_theme.dart';
import '../../core/widgets/footer.dart';
import '../../core/widgets/melow_logo.dart';
import '../shell/main_shell.dart';
import '../single_player/single_player_setup_sheet.dart';

/// Branded animated splash & startup authentication gate with an attractive
/// neon arcade login background, offering:
/// 1. Login as Anonymous (Quick Play)
/// 2. Login with Existing User (Username & Password)
/// 3. Create Username & Password (with minimum character requirements)
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
  bool _checkingSession = true;
  bool _busy = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scale = Tween<double>(begin: 0.84, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
    _checkInitialSession();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _checkInitialSession() async {
    setState(() {
      _checkingSession = true;
      _error = null;
    });
    try {
      await widget.services.preferences.loadLocal();
      await widget.services.singlePlayer.loadLocalAndSync();
      final existingUser = FirebaseAuth.instance.currentUser;
      if (existingUser != null) {
        await widget.services.profile.ensureProfile();
        await widget.services.singlePlayer.loadLocalAndSync();
        try {
          final cloudPrefs =
              await widget.services.profile.fetchPrivatePreferences();
          widget.services.preferences.applyCloudPreferences(cloudPrefs);
        } catch (_) {}
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => _checkingSession = false);
  }

  Future<void> _loginAsAnonymous() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.services.game.ensureSignedIn();
      await widget.services.profile.ensureProfile();
      await widget.services.singlePlayer.loadLocalAndSync();
      try {
        final cloudPrefs =
            await widget.services.profile.fetchPrivatePreferences();
        widget.services.preferences.applyCloudPreferences(cloudPrefs);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _busy = false;
        _ready = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Unable to connect to Melow servers. '
            'You can still play Single Player offline!';
      });
    }
  }

  Future<void> _openUsernamePasswordDialog({required bool isRegister}) async {
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    bool obscure = true;
    bool submitting = false;
    String? dialogError;

    final success = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final scheme = Theme.of(ctx).colorScheme;
          return AlertDialog(
            title: Text(
              isRegister
                  ? 'Register Username & Password'
                  : 'Login with Existing User',
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      '• Username: Minimum 4 characters (letters, numbers, _ or .)\n'
                      '• Password: Minimum 6 characters',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: userCtrl,
                    maxLength: 20,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Username (min 4 characters)',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: passCtrl,
                    obscureText: obscure,
                    maxLength: 64,
                    decoration: InputDecoration(
                      labelText: 'Password (min 6 characters)',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () =>
                            setDialogState(() => obscure = !obscure),
                      ),
                    ),
                  ),
                  if (dialogError != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      dialogError!,
                      style: TextStyle(
                        color: scheme.error,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: submitting ? null : () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: submitting
                    ? null
                    : () async {
                        final uErr =
                            ProfileRepository.validateUsername(userCtrl.text);
                        if (uErr != null) {
                          setDialogState(() => dialogError = uErr);
                          return;
                        }
                        final pErr =
                            ProfileRepository.validatePassword(passCtrl.text);
                        if (pErr != null) {
                          setDialogState(() => dialogError = pErr);
                          return;
                        }
                        setDialogState(() {
                          submitting = true;
                          dialogError = null;
                        });
                        try {
                          if (isRegister) {
                            await widget.services.profile
                                .registerUsernameAndPassword(
                              username: userCtrl.text,
                              password: passCtrl.text,
                            );
                          } else {
                            await widget.services.profile
                                .loginWithUsernameAndPassword(
                              username: userCtrl.text,
                              password: passCtrl.text,
                            );
                          }
                          await widget.services.singlePlayer.loadLocalAndSync();
                          if (ctx.mounted) Navigator.pop(ctx, true);
                        } catch (e) {
                          if (ctx.mounted) {
                            setDialogState(() {
                              submitting = false;
                              dialogError = e
                                  .toString()
                                  .replaceFirst('Exception: ', '');
                            });
                          }
                        }
                      },
                icon: Icon(
                  isRegister ? Icons.how_to_reg_rounded : Icons.login_rounded,
                  size: 18,
                ),
                label: Text(
                  submitting
                      ? (isRegister ? 'Registering…' : 'Signing in…')
                      : (isRegister ? 'Register & Play' : 'Login'),
                ),
              ),
            ],
          );
        },
      ),
    );
    userCtrl.dispose();
    passCtrl.dispose();

    if (success == true && mounted) {
      setState(() => _ready = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) {
      return MainShell(services: widget.services);
    }

    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reducedMotion = widget.services.preferences.reducedMotion ||
        MediaQuery.of(context).disableAnimations;
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Rich Multi-Stop Arcade Gradient Backdrop
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? const [
                        Color(0xFF0A0B1E),
                        Color(0xFF1F144C),
                        Color(0xFF0F264A),
                      ]
                    : const [
                        Color(0xFFEEF2FF),
                        Color(0xFFE0E7FF),
                        Color(0xFFCCFBF1),
                      ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          // 2. Decorative Glowing Orbs & Tic-Tac-Toe Grid Watermark
          Positioned(
            top: -70,
            left: -60,
            child: _GlowOrb(
              size: 240,
              color: AppTheme.purpleAccent.withValues(alpha: isDark ? 0.32 : 0.2),
            ),
          ),
          Positioned(
            bottom: -80,
            right: -50,
            child: _GlowOrb(
              size: 260,
              color: AppTheme.cyanAccent.withValues(alpha: isDark ? 0.28 : 0.22),
            ),
          ),
          Positioned(
            top: 110,
            right: -30,
            child: _GlowOrb(
              size: 160,
              color: AppTheme.goldAccent.withValues(alpha: isDark ? 0.2 : 0.16),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _ArcadeGridBackdropPainter(isDark: isDark),
              ),
            ),
          ),
          // 3. Floating Game Symbols Backdrop Accents
          const Positioned(
            top: 56,
            left: 28,
            child: Opacity(
              opacity: 0.18,
              child: Text('❌', style: TextStyle(fontSize: 38)),
            ),
          ),
          const Positioned(
            top: 84,
            right: 34,
            child: Opacity(
              opacity: 0.18,
              child: Text('⭕', style: TextStyle(fontSize: 36)),
            ),
          ),
          const Positioned(
            bottom: 92,
            left: 36,
            child: Opacity(
              opacity: 0.18,
              child: Text('🏆', style: TextStyle(fontSize: 36)),
            ),
          ),
          const Positioned(
            bottom: 120,
            right: 32,
            child: Opacity(
              opacity: 0.18,
              child: Text('⚡', style: TextStyle(fontSize: 36)),
            ),
          ),
          // 4. Foreground Login Card & Branding
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FadeTransition(
                        opacity:
                            reducedMotion ? kAlwaysCompleteAnimation : _fade,
                        child: ScaleTransition(
                          scale:
                              reducedMotion ? kAlwaysCompleteAnimation : _scale,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const MelowLogo(size: 110, borderRadius: 28),
                              const SizedBox(height: 18),
                              Text(
                                'Welcome to Melow',
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Single Player • Multiplayer • Friend Groups • Chat & Voice Call',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Glassmorphic Login Panel
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: (isDark
                                  ? const Color(0xFF1A1B36)
                                  : Colors.white)
                              .withValues(alpha: isDark ? 0.86 : 0.92),
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(
                            color: AppTheme.purpleAccent
                                .withValues(alpha: isDark ? 0.45 : 0.25),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black
                                  .withValues(alpha: isDark ? 0.4 : 0.1),
                              blurRadius: 24,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: _checkingSession || _busy
                            ? const Padding(
                                padding: EdgeInsets.all(24),
                                child: Center(
                                  child:
                                      CircularProgressIndicator(strokeWidth: 3),
                                ),
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Option 1: Login as Anonymous / Continue
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: AppTheme.goldAccent,
                                      foregroundColor: AppTheme.darkBackground,
                                      minimumSize: const Size.fromHeight(50),
                                    ),
                                    onPressed: _loginAsAnonymous,
                                    icon: const Icon(
                                      Icons.play_arrow_rounded,
                                      size: 24,
                                    ),
                                    label: Text(
                                      currentUser != null &&
                                              !currentUser.isAnonymous
                                          ? 'Continue as Registered Player'
                                          : 'Login as Anonymous',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  // Option 2: Login with Existing User
                                  FilledButton.tonalIcon(
                                    style: FilledButton.styleFrom(
                                      minimumSize: const Size.fromHeight(48),
                                    ),
                                    onPressed: () =>
                                        _openUsernamePasswordDialog(
                                      isRegister: false,
                                    ),
                                    icon: const Icon(Icons.login_rounded),
                                    label: const Text(
                                      'Login with Existing User',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  // Option 3: Create Username & Password
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size.fromHeight(48),
                                    ),
                                    onPressed: () =>
                                        _openUsernamePasswordDialog(
                                      isRegister: true,
                                    ),
                                    icon: const Icon(Icons.how_to_reg_rounded),
                                    label: const Text(
                                      'Add Username & Password',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'Username: min 4 characters • Password: min 6 characters',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                  if (_error != null) ...[
                                    const SizedBox(height: 12),
                                    Text(
                                      _error!,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: scheme.error,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                  const Divider(height: 22),
                                  TextButton.icon(
                                    onPressed: () {
                                      showModalBottomSheet<void>(
                                        context: context,
                                        isScrollControlled: true,
                                        builder: (_) => SinglePlayerSetupSheet(
                                          services: widget.services,
                                        ),
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.smart_toy_rounded,
                                      size: 18,
                                    ),
                                    label: const Text(
                                      'Play Single Player Offline',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                      const SizedBox(height: 18),
                      const MelowFooter(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0.0)],
        ),
      ),
    );
  }
}

class _ArcadeGridBackdropPainter extends CustomPainter {
  const _ArcadeGridBackdropPainter({required this.isDark});
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = (isDark ? Colors.white : AppTheme.purpleAccent)
          .withValues(alpha: isDark ? 0.04 : 0.05)
      ..strokeWidth = 1.0;

    const spacing = 48.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ArcadeGridBackdropPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}
