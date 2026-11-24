import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/bot_engine.dart';
import '../../domain/models/single_player_models.dart';
import '../../domain/models/user_profile.dart';

/// Manages separate Single Player (Player vs System) statistics, difficulty
/// records, solo achievements, and game history with offline-first local
/// storage and optional owner-only private cloud backup (`users/{uid}/private/singlePlayer`).
///
/// Single-player results are NEVER written to online `stats/{uid}` or
/// `leaderboardEntries/{uid}` (Global Top 100 rankings).
class SinglePlayerRepository extends ChangeNotifier {
  SinglePlayerRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    String? databaseId,
    bool enableCloudSync = true,
  })  : _db = firestore,
        _auth = auth,
        _databaseId = databaseId,
        _enableCloudSync = enableCloudSync;

  static const String _kLocalStorageKey = 'melow_single_player_state_v1';
  static const String _kProcessedIdsKey = 'melow_single_player_processed_v1';

  final FirebaseFirestore? _db;
  final FirebaseAuth? _auth;
  final String? _databaseId;
  final bool _enableCloudSync;

  SinglePlayerStats _stats = const SinglePlayerStats();
  final Set<String> _processedGameIds = <String>{};

  SinglePlayerStats get stats => _stats;

  List<SinglePlayerMatchRecord> get history => _stats.history;

  Map<String, UserAchievement> get achievements => {
        for (final def in soloAchievementsCatalog)
          def.id: UserAchievement(
            achievementId: def.id,
            unlockedAt: _stats.isAchievementUnlocked(def.id)
                ? DateTime.now()
                : null,
            progress: _stats.progressForAchievement(def.id),
            verified: true,
          ),
      };

  FirebaseFirestore? get _resolvedDb {
    if (!_enableCloudSync) return null;
    if (_db != null) return _db;
    try {
      if (Firebase.apps.isEmpty) return null;
      return _databaseId != null
          ? FirebaseFirestore.instanceFor(
              app: Firebase.app(),
              databaseId: _databaseId,
            )
          : FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  String? get _maybeUid {
    if (!_enableCloudSync) return null;
    try {
      final auth = _auth ?? (Firebase.apps.isNotEmpty ? FirebaseAuth.instance : null);
      return auth?.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  /// Loads offline Single Player statistics from local storage and merges
  /// with optional cloud backup when available.
  Future<void> loadLocalAndSync() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final rawJson = sp.getString(_kLocalStorageKey);
      if (rawJson != null && rawJson.isNotEmpty) {
        final decoded = jsonDecode(rawJson);
        if (decoded is Map) {
          _stats = SinglePlayerStats.fromMap(
            Map<String, dynamic>.from(decoded),
          );
        }
      }
      final savedIds = sp.getStringList(_kProcessedIdsKey);
      if (savedIds != null) {
        _processedGameIds
          ..clear()
          ..addAll(savedIds);
      }
      notifyListeners();
    } catch (_) {}

    // Best-effort optional cloud sync if signed in and online.
    await _tryPullFromCloud();
  }

  /// Idempotently records a completed Single Player round/game result.
  /// Returns `true` if the result was newly recorded, or `false` if [gameId]
  /// was already processed (preventing duplicate stats).
  Future<bool> recordGameResult({
    required String gameId,
    required BotDifficulty difficulty,
    required SinglePlayerMode mode,
    required int boardSize,
    required int bestOf,
    required String outcome, // 'win' | 'loss' | 'draw'
    required int playerScore,
    required int botScore,
    required int draws,
    bool wonTournamentCup = false,
  }) async {
    if (gameId.trim().isEmpty) return false;
    if (_processedGameIds.contains(gameId)) return false;
    _processedGameIds.add(gameId);
    if (_processedGameIds.length > 250) {
      final first = _processedGameIds.first;
      _processedGameIds.remove(first);
    }

    final isWin = outcome == 'win';
    final isLoss = outcome == 'loss';
    final isDraw = outcome == 'draw';

    final nextTotal = _stats.totalGames + 1;
    final nextWins = _stats.wins + (isWin ? 1 : 0);
    final nextLosses = _stats.losses + (isLoss ? 1 : 0);
    final nextDraws = _stats.draws + (isDraw ? 1 : 0);
    final nextCups = _stats.soloCups + (wonTournamentCup ? 1 : 0);
    final nextStreak = isWin
        ? _stats.currentStreak + 1
        : (isDraw ? _stats.currentStreak : 0);
    final nextBestStreak =
        nextStreak > _stats.bestStreak ? nextStreak : _stats.bestStreak;

    final prevDiff = _stats.statsForDifficulty(difficulty);
    final nextDiff = prevDiff.copyWith(
      games: prevDiff.games + 1,
      wins: prevDiff.wins + (isWin ? 1 : 0),
      losses: prevDiff.losses + (isLoss ? 1 : 0),
      draws: prevDiff.draws + (isDraw ? 1 : 0),
    );
    final nextByDiff = Map<String, DifficultyStats>.from(_stats.byDifficulty)
      ..[difficulty.id] = nextDiff;

    final record = SinglePlayerMatchRecord(
      id: gameId,
      difficulty: difficulty.id,
      mode: mode.id,
      boardSize: boardSize,
      bestOf: bestOf,
      playerScore: playerScore,
      botScore: botScore,
      draws: draws,
      outcome: outcome,
      wonCup: wonTournamentCup,
      playedAt: DateTime.now(),
    );
    final nextHistory = <SinglePlayerMatchRecord>[
      record,
      ..._stats.history,
    ].take(35).toList(growable: false);

    // Evaluate Solo Achievements progress & unlocks
    final easyWins = (nextByDiff[BotDifficulty.easy.id]?.wins ?? 0);
    final normalWins = (nextByDiff[BotDifficulty.normal.id]?.wins ?? 0);
    final hardWins = (nextByDiff[BotDifficulty.hard.id]?.wins ?? 0);
    final impStats = nextByDiff[BotDifficulty.impossible.id];
    final impDrawOrWin = (impStats?.draws ?? 0) + (impStats?.wins ?? 0);

    final nextProgress = <String, int>{
      'first_solo_victory': nextWins.clamp(0, 1),
      'easy_master': easyWins.clamp(0, 3),
      'normal_master': normalWins.clamp(0, 3),
      'hard_master': hardWins.clamp(0, 3),
      'impossible_draw': impDrawOrWin.clamp(0, 1),
      'five_consecutive_wins': nextBestStreak.clamp(0, 5),
      'ten_solo_victories': nextWins.clamp(0, 10),
      'solo_tournament_champion': nextCups.clamp(0, 1),
    };

    final nextUnlocked = Set<String>.from(_stats.unlockedAchievements);
    for (final def in soloAchievementsCatalog) {
      final p = nextProgress[def.id] ?? 0;
      if (p >= def.target) {
        nextUnlocked.add(def.id);
      }
    }

    _stats = SinglePlayerStats(
      totalGames: nextTotal,
      wins: nextWins,
      losses: nextLosses,
      draws: nextDraws,
      soloCups: nextCups,
      currentStreak: nextStreak,
      bestStreak: nextBestStreak,
      byDifficulty: nextByDiff,
      history: nextHistory,
      achievementProgress: nextProgress,
      unlockedAchievements: nextUnlocked,
    );

    notifyListeners();
    await _persistLocal();
    await _tryPushToCloud();
    return true;
  }

  /// Wipes all local and cloud Single Player data (called on Permanent Account Deletion).
  Future<void> clearAllSoloData({bool deleteCloud = true}) async {
    _stats = const SinglePlayerStats();
    _processedGameIds.clear();
    notifyListeners();

    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_kLocalStorageKey);
      await sp.remove(_kProcessedIdsKey);
    } catch (_) {}

    if (deleteCloud) {
      final db = _resolvedDb;
      final uid = _maybeUid;
      if (db != null && uid != null && uid.isNotEmpty) {
        try {
          await db
              .collection('users')
              .doc(uid)
              .collection('private')
              .doc('singlePlayer')
              .delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _persistLocal() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_kLocalStorageKey, jsonEncode(_stats.toMap()));
      await sp.setStringList(
        _kProcessedIdsKey,
        _processedGameIds.toList(growable: false),
      );
    } catch (_) {}
  }

  Future<void> _tryPushToCloud() async {
    final db = _resolvedDb;
    final uid = _maybeUid;
    if (db == null || uid == null || uid.isEmpty) return;
    try {
      await db
          .collection('users')
          .doc(uid)
          .collection('private')
          .doc('singlePlayer')
          .set({
        ..._stats.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _tryPullFromCloud() async {
    final db = _resolvedDb;
    final uid = _maybeUid;
    if (db == null || uid == null || uid.isEmpty) return;
    try {
      final snap = await db
          .collection('users')
          .doc(uid)
          .collection('private')
          .doc('singlePlayer')
          .get();
      if (!snap.exists || snap.data() == null) return;
      final remote = SinglePlayerStats.fromMap(snap.data());
      if (remote.totalGames > _stats.totalGames) {
        _stats = remote;
        notifyListeners();
        await _persistLocal();
      } else if (_stats.totalGames > remote.totalGames) {
        await _tryPushToCloud();
      }
    } catch (_) {}
  }
}
