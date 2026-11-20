import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

import 'preferences_controller.dart';

enum SoundEffect { click, place, win, draw, trophy }

/// Plays locally bundled WAV SFX with overlap throttling & haptic coordination.
class SoundService {
  SoundService({required this.preferences});

  final PreferencesController preferences;
  AudioPlayer? _player;
  DateTime _lastPlayed = DateTime.fromMillisecondsSinceEpoch(0);
  bool _disposed = false;

  static const Map<SoundEffect, String> _assetPaths = {
    SoundEffect.click: 'sounds/click.wav',
    SoundEffect.place: 'sounds/place.wav',
    SoundEffect.win: 'sounds/win.wav',
    SoundEffect.draw: 'sounds/draw.wav',
    SoundEffect.trophy: 'sounds/trophy.wav',
  };

  Future<void> play(SoundEffect effect) async {
    if (_disposed || !preferences.soundEnabled) return;
    final now = DateTime.now();
    // Throttle rapid overlapping audio playback to preserve battery & audio focus.
    if (now.difference(_lastPlayed) < const Duration(milliseconds: 80) &&
        effect == SoundEffect.click) {
      return;
    }
    _lastPlayed = now;
    try {
      _player ??= AudioPlayer()..setReleaseMode(ReleaseMode.stop);
      await _player!.stop();
      await _player!.play(AssetSource(_assetPaths[effect]!));
    } catch (_) {
      // Gracefully ignore missing audio hardware/plugins in widget tests.
    }
  }

  Future<void> hapticLight() async {
    if (!preferences.hapticsEnabled) return;
    try {
      await HapticFeedback.lightImpact();
    } catch (_) {}
  }

  Future<void> hapticMedium() async {
    if (!preferences.hapticsEnabled) return;
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  Future<void> dispose() async {
    _disposed = true;
    try {
      await _player?.dispose();
    } catch (_) {}
    _player = null;
  }
}
