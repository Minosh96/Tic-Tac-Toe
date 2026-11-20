import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'core/services/app_services.dart';
import 'firebase_options.dart';
import 'ui/core/app_theme.dart';
import 'ui/features/splash/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  final services = AppServices.production(databaseId: 'melow-game');
  runApp(MelowApp(services: services));
}

class MelowApp extends StatefulWidget {
  const MelowApp({super.key, required this.services});

  final AppServices services;

  @override
  State<MelowApp> createState() => _MelowAppState();
}

class _MelowAppState extends State<MelowApp> {
  @override
  void dispose() {
    widget.services.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.services.preferences,
      builder: (context, _) {
        return MaterialApp(
          title: 'Melow Tic Tac Toe',
          debugShowCheckedModeBanner: false,
          themeMode: widget.services.preferences.themeMode,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          home: SplashScreen(services: widget.services),
        );
      },
    );
  }
}
