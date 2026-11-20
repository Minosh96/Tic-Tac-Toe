import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melow_tic_tac_toe/core/services/preferences_controller.dart';
import 'package:melow_tic_tac_toe/data/repositories/leaderboard_repository.dart';
import 'package:melow_tic_tac_toe/domain/achievements_catalog.dart';
import 'package:melow_tic_tac_toe/domain/game_engine.dart';
import 'package:melow_tic_tac_toe/domain/models/social_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Blitz deadline & timeout boundary', () {
    test('reports remaining time accurately and expires at exact boundary', () {
      final deadline = DateTime.utc(2026, 11, 21, 10, 0, 5);
      final before = DateTime.utc(2026, 11, 21, 10, 0, 3);
      final exact = DateTime.utc(2026, 11, 21, 10, 0, 5);
      final after = DateTime.utc(2026, 11, 21, 10, 0, 6);

      expect(
        GameEngine.remainingBlitzTime(deadline: deadline, now: before),
        const Duration(seconds: 2),
      );
      expect(GameEngine.isBlitzExpired(deadline: deadline, now: before), isFalse);
      expect(GameEngine.isBlitzExpired(deadline: deadline, now: exact), isTrue);
      expect(GameEngine.isBlitzExpired(deadline: deadline, now: after), isTrue);
      expect(
        GameEngine.remainingBlitzTime(deadline: deadline, now: after),
        Duration.zero,
      );
    });

    test('accounts for clock skew via serverOffset', () {
      final deadline = DateTime.utc(2026, 11, 21, 10, 0, 5);
      final localNow = DateTime.utc(2026, 11, 21, 10, 0, 4);
      // Server is 2 seconds ahead of local device clock.
      expect(
        GameEngine.isBlitzExpired(
          deadline: deadline,
          now: localNow,
          serverOffset: const Duration(seconds: 2),
        ),
        isTrue,
      );
    });
  });

  group('Challenge Wheel & Emoji uniqueness', () {
    test('pickShuffleEmojis always assigns two distinct allowed emojis', () {
      for (var seed = 0; seed < 30; seed++) {
        final pair = GameEngine.pickShuffleEmojis(Random(seed));
        expect(pair.$1, isNot(equals(pair.$2)));
        expect(emojiChoices, contains(pair.$1));
        expect(emojiChoices, contains(pair.$2));
      }
    });

    test('ChallengeWheelOption lookup resolves all 6 options', () {
      expect(ChallengeWheelOption.values.length, 6);
      for (final opt in ChallengeWheelOption.values) {
        expect(ChallengeWheelOption.fromId(opt.id), opt);
      }
    });
  });

  group('Nickname validation & deterministic rivalry IDs', () {
    test('validates nicknames cleanly', () {
      expect(GameEngine.validateNickname('Minosh96'), isNull);
      expect(GameEngine.validateNickname('Melow_Player-1'), isNull);
      expect(GameEngine.validateNickname('   '), isNotNull);
      expect(GameEngine.validateNickname('a' * 21), isNotNull);
      expect(GameEngine.validateNickname('bad<script>'), isNotNull);
    });

    test('rivalryIdFor is order-independent', () {
      expect(
        GameEngine.rivalryIdFor('uid_z', 'uid_a'),
        GameEngine.rivalryIdFor('uid_a', 'uid_z'),
      );
      expect(GameEngine.rivalryIdFor('uid_z', 'uid_a'), 'uid_a__uid_z');
    });
  });

  group('Achievement eligibility', () {
    test('evaluates deterministic milestones without false unlocks', () {
      final ids = AchievementEvaluator.eligibleIds(
        const AchievementEvaluationInput(
          totalWins: 5,
          tournamentsWon: 1,
          blitzWins: 5,
          megaWins: 2,
          maxRivalryMatches: 10,
          wonWithoutDroppingRound: true,
          wonAfterTrailing: false,
        ),
      );
      expect(ids, contains('first_victory'));
      expect(ids, contains('rising_star'));
      expect(ids, contains('champion'));
      expect(ids, contains('perfect_match'));
      expect(ids, contains('blitz_hero'));
      expect(ids, contains('friendly_rival'));
      expect(ids, isNot(contains('tic_tac_master')));
      expect(ids, isNot(contains('mega_strategist')));
      expect(ids, isNot(contains('comeback_king')));
    });
  });

  group('Leaderboard sorting & tie handling', () {
    test('sorts deterministically with tie-breakers', () {
      const entries = [
        LeaderboardEntry(
          uid: 'u1',
          publicNickname: 'Zara',
          avatarId: 'cat',
          wins: 10,
          tournamentsWon: 2,
          bestStreak: 4,
          blitzWins: 3,
          optIn: true,
        ),
        LeaderboardEntry(
          uid: 'u2',
          publicNickname: 'Alex',
          avatarId: 'fox',
          wins: 10,
          tournamentsWon: 3,
          bestStreak: 5,
          blitzWins: 1,
          optIn: true,
        ),
        LeaderboardEntry(
          uid: 'u3',
          publicNickname: 'Minosh',
          avatarId: 'astro',
          wins: 15,
          tournamentsWon: 4,
          bestStreak: 6,
          blitzWins: 5,
          optIn: true,
        ),
      ];

      final sorted = LeaderboardRepository.sortDeterministically(
        entries,
        LeaderboardMetric.wins,
      );
      expect(sorted.map((e) => e.uid).toList(), ['u3', 'u2', 'u1']);
    });
  });

  group('Theme & preferences persistence', () {
    test('persists themeMode, sound, haptics and reducedMotion locally', () async {
      SharedPreferences.setMockInitialValues({});
      final controller = PreferencesController();
      await controller.setThemeMode(ThemeMode.dark);
      await controller.setSoundEnabled(false);
      await controller.setHapticsEnabled(false);
      await controller.setReducedMotion(true);

      final reloaded = PreferencesController();
      await reloaded.loadLocal();
      expect(reloaded.themeMode, ThemeMode.dark);
      expect(reloaded.soundEnabled, isFalse);
      expect(reloaded.hapticsEnabled, isFalse);
      expect(reloaded.reducedMotion, isTrue);
    });
  });
}
