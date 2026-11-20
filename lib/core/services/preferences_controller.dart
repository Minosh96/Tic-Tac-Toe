import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted user preferences for theme, sound, haptics, reactions & accessibility.
class PreferencesController extends ChangeNotifier {
  PreferencesController({
    ThemeMode themeMode = ThemeMode.system,
    bool soundEnabled = true,
    bool hapticsEnabled = true,
    bool reactionsMuted = false,
    bool reducedMotion = false,
    int favoriteBoardSize = 3,
    String favoriteMode = 'classic',
    Set<String>? hiddenRivals,
  })  : _themeMode = themeMode,
        _soundEnabled = soundEnabled,
        _hapticsEnabled = hapticsEnabled,
        _reactionsMuted = reactionsMuted,
        _reducedMotion = reducedMotion,
        _favoriteBoardSize = favoriteBoardSize,
        _favoriteMode = favoriteMode,
        _hiddenRivals = hiddenRivals ?? <String>{};

  static const _kThemeMode = 'melow_theme_mode';
  static const _kSound = 'melow_sound_enabled';
  static const _kHaptics = 'melow_haptics_enabled';
  static const _kReactionsMuted = 'melow_reactions_muted';
  static const _kReducedMotion = 'melow_reduced_motion';
  static const _kFavBoard = 'melow_fav_board';
  static const _kFavMode = 'melow_fav_mode';
  static const _kHiddenRivals = 'melow_hidden_rivals';

  ThemeMode _themeMode;
  bool _soundEnabled;
  bool _hapticsEnabled;
  bool _reactionsMuted;
  bool _reducedMotion;
  int _favoriteBoardSize;
  String _favoriteMode;
  final Set<String> _hiddenRivals;

  ThemeMode get themeMode => _themeMode;
  bool get soundEnabled => _soundEnabled;
  bool get hapticsEnabled => _hapticsEnabled;
  bool get reactionsMuted => _reactionsMuted;
  bool get reducedMotion => _reducedMotion;
  int get favoriteBoardSize => _favoriteBoardSize;
  String get favoriteMode => _favoriteMode;
  Set<String> get hiddenRivals => Set.unmodifiable(_hiddenRivals);

  Future<void> Function(Map<String, dynamic> prefs)? onCloudSync;

  /// Loads preferences from local storage (fast, offline-safe).
  Future<void> loadLocal() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final themeStr = sp.getString(_kThemeMode);
      _themeMode = _parseThemeMode(themeStr);
      _soundEnabled = sp.getBool(_kSound) ?? true;
      _hapticsEnabled = sp.getBool(_kHaptics) ?? true;
      _reactionsMuted = sp.getBool(_kReactionsMuted) ?? false;
      _reducedMotion = sp.getBool(_kReducedMotion) ?? false;
      _favoriteBoardSize = sp.getInt(_kFavBoard) ?? 3;
      _favoriteMode = sp.getString(_kFavMode) ?? 'classic';
      final hidden = sp.getStringList(_kHiddenRivals);
      if (hidden != null) {
        _hiddenRivals
          ..clear()
          ..addAll(hidden);
      }
      notifyListeners();
    } catch (_) {
      // Fall back to defaults in tests or restricted environments.
    }
  }

  /// Hydrates from cloud preferences map without overwriting local if empty.
  void applyCloudPreferences(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return;
    if (data['themeMode'] is String) {
      _themeMode = _parseThemeMode(data['themeMode'] as String);
    }
    if (data['soundEnabled'] is bool) {
      _soundEnabled = data['soundEnabled'] as bool;
    }
    if (data['hapticsEnabled'] is bool) {
      _hapticsEnabled = data['hapticsEnabled'] as bool;
    }
    if (data['reactionsMuted'] is bool) {
      _reactionsMuted = data['reactionsMuted'] as bool;
    }
    if (data['reducedMotion'] is bool) {
      _reducedMotion = data['reducedMotion'] as bool;
    }
    if (data['favoriteBoardSize'] is num) {
      final size = (data['favoriteBoardSize'] as num).toInt();
      if (size >= 3 && size <= 6) _favoriteBoardSize = size;
    }
    if (data['favoriteMode'] is String) {
      final m = data['favoriteMode'] as String;
      if (m == 'classic' || m == 'blitz') _favoriteMode = m;
    }
    if (data['hiddenRivals'] is List) {
      _hiddenRivals
        ..clear()
        ..addAll((data['hiddenRivals'] as List).map((e) => e.toString()));
    }
    notifyListeners();
  }

  Map<String, dynamic> toMap() => {
        'themeMode': _themeMode.name,
        'soundEnabled': _soundEnabled,
        'hapticsEnabled': _hapticsEnabled,
        'reactionsMuted': _reactionsMuted,
        'reducedMotion': _reducedMotion,
        'favoriteBoardSize': _favoriteBoardSize,
        'favoriteMode': _favoriteMode,
        'hiddenRivals': _hiddenRivals.toList(growable: false),
      };

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    await _persist();
  }

  Future<void> setSoundEnabled(bool value) async {
    if (_soundEnabled == value) return;
    _soundEnabled = value;
    notifyListeners();
    await _persist();
  }

  Future<void> setHapticsEnabled(bool value) async {
    if (_hapticsEnabled == value) return;
    _hapticsEnabled = value;
    notifyListeners();
    await _persist();
  }

  Future<void> setReactionsMuted(bool value) async {
    if (_reactionsMuted == value) return;
    _reactionsMuted = value;
    notifyListeners();
    await _persist();
  }

  Future<void> setReducedMotion(bool value) async {
    if (_reducedMotion == value) return;
    _reducedMotion = value;
    notifyListeners();
    await _persist();
  }

  Future<void> setFavoriteBoardSize(int size) async {
    if (size < 3 || size > 6 || _favoriteBoardSize == size) return;
    _favoriteBoardSize = size;
    notifyListeners();
    await _persist();
  }

  Future<void> setFavoriteMode(String mode) async {
    if ((mode != 'classic' && mode != 'blitz') || _favoriteMode == mode) return;
    _favoriteMode = mode;
    notifyListeners();
    await _persist();
  }

  Future<void> setRivalHidden(String rivalryId, bool hidden) async {
    final changed =
        hidden ? _hiddenRivals.add(rivalryId) : _hiddenRivals.remove(rivalryId);
    if (!changed) return;
    notifyListeners();
    await _persist();
  }

  bool isRivalHidden(String rivalryId) => _hiddenRivals.contains(rivalryId);

  Future<void> _persist() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_kThemeMode, _themeMode.name);
      await sp.setBool(_kSound, _soundEnabled);
      await sp.setBool(_kHaptics, _hapticsEnabled);
      await sp.setBool(_kReactionsMuted, _reactionsMuted);
      await sp.setBool(_kReducedMotion, _reducedMotion);
      await sp.setInt(_kFavBoard, _favoriteBoardSize);
      await sp.setString(_kFavMode, _favoriteMode);
      await sp.setStringList(_kHiddenRivals, _hiddenRivals.toList());
    } catch (_) {}
    final sync = onCloudSync;
    if (sync != null) {
      try {
        await sync(toMap());
      } catch (_) {}
    }
  }

  static ThemeMode _parseThemeMode(String? value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}
