import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'data/repositories/game_repository.dart';
import 'firebase_options.dart';
import 'ui/core/app_theme.dart';
import 'ui/features/home/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(MelowApp(repository: GameRepository(databaseId: 'melow-game')));
}

class MelowApp extends StatefulWidget {
  const MelowApp({super.key, required this.repository});

  final GameRepository repository;

  @override
  State<MelowApp> createState() => _MelowAppState();
}

class _MelowAppState extends State<MelowApp> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Melow Tic Tac Toe',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: _AuthGate(
        repository: widget.repository,
        themeMode: _themeMode,
        onThemeModeChanged: (mode) => setState(() => _themeMode = mode),
      ),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate({
    required this.repository,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  final GameRepository repository;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  late Future<void> _signInFuture;

  @override
  void initState() {
    super.initState();
    _signInFuture = widget.repository.ensureSignedIn();
  }

  void _retry() {
    setState(() {
      _signInFuture = widget.repository.ensureSignedIn();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _signInFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('🎮', style: TextStyle(fontSize: 48)),
                  SizedBox(height: 16),
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Connecting to Melow Labs…'),
                ],
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_rounded, size: 52),
                    const SizedBox(height: 12),
                    const Text(
                      'Could not connect to Firebase',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _retry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return HomePage(
          repository: widget.repository,
          themeMode: widget.themeMode,
          onThemeModeChanged: widget.onThemeModeChanged,
        );
      },
    );
  }
}
