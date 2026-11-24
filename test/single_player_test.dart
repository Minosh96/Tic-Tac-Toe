import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:melow_tic_tac_toe/data/repositories/single_player_repository.dart';
import 'package:melow_tic_tac_toe/domain/bot_engine.dart';
import 'package:melow_tic_tac_toe/domain/game_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('BotEngine — Legal Moves, Win/Block Detection & Difficulties', () {
    test('returns -1 when no empty cells exist', () {
      const fullBoard = ['h', 'g', 'h', 'g', 'h', 'g', 'g', 'h', 'g'];
      for (final diff in BotDifficulty.values) {
        expect(
          BotEngine.computeMove(
            board: fullBoard,
            size: 3,
            difficulty: diff,
            botMark: 'g',
            humanMark: 'h',
          ),
          -1,
        );
      }
    });

    test('never selects an occupied cell across all board sizes and difficulties', () {
      final rng = Random(42);
      for (final size in supportedBoardSizes) {
        final board = List<String>.filled(size * size, '');
        // Place alternating marks on the first row and second row without completing any column/row/diagonal
        board[0] = 'h';
        board[1] = 'g';
        board[size] = 'g';
        board[size + 1] = 'h';
        expect(GameEngine.evaluateWinner(board, size), isNull);

        for (final diff in BotDifficulty.values) {
          final move = BotEngine.computeMove(
            board: board,
            size: size,
            difficulty: diff,
            botMark: 'g',
            humanMark: 'h',
            random: rng,
          );
          expect(move, inInclusiveRange(0, size * size - 1));
          expect(board[move], isEmpty);
        }
      }
    });

    test('Normal, Hard, and Impossible immediately take a 1-move winning cell', () {
      const board = [
        'g', 'g', '',
        'h', 'h', '',
        '', '', '',
      ];
      for (final diff in [
        BotDifficulty.normal,
        BotDifficulty.hard,
        BotDifficulty.impossible,
      ]) {
        final move = BotEngine.computeMove(
          board: board,
          size: 3,
          difficulty: diff,
          botMark: 'g',
          humanMark: 'h',
        );
        expect(move, 2, reason: 'Failed on ${diff.label}');
      }
    });

    test('Normal, Hard, and Impossible immediately block opponent 1-move win', () {
      const board = [
        'h', 'h', '',
        '', 'g', '',
        '', '', '',
      ];
      for (final diff in [
        BotDifficulty.normal,
        BotDifficulty.hard,
        BotDifficulty.impossible,
      ]) {
        final move = BotEngine.computeMove(
          board: board,
          size: 3,
          difficulty: diff,
          botMark: 'g',
          humanMark: 'h',
        );
        expect(move, 2, reason: 'Failed to block on ${diff.label}');
      }
    });

    test('Impossible mode on standard 3x3 is unbeatable against random and tactical opponents', () {
      final rng = Random(2026);
      for (int gameIdx = 0; gameIdx < 40; gameIdx++) {
        final board = List<String>.filled(9, '');
        String turn = gameIdx.isEven ? 'h' : 'g';

        while (true) {
          final win = GameEngine.evaluateWinner(board, 3);
          if (win != null) {
            expect(win.winner, isNot('h'), reason: 'Impossible bot lost on game $gameIdx');
            break;
          }
          if (!board.contains('')) {
            break;
          }

          if (turn == 'g') {
            final botMove = BotEngine.computeMove(
              board: board,
              size: 3,
              difficulty: BotDifficulty.impossible,
              botMark: 'g',
              humanMark: 'h',
            );
            expect(board[botMove], isEmpty);
            board[botMove] = 'g';
            turn = 'h';
          } else {
            final oppMove = gameIdx % 3 == 0
                ? BotEngine.computeMove(
                    board: board,
                    size: 3,
                    difficulty: BotDifficulty.normal,
                    botMark: 'h',
                    humanMark: 'g',
                    random: rng,
                  )
                : BotEngine.computeMove(
                    board: board,
                    size: 3,
                    difficulty: BotDifficulty.easy,
                    botMark: 'h',
                    humanMark: 'g',
                    random: rng,
                  );
            board[oppMove] = 'h';
            turn = 'g';
          }
        }
      }
    });

    test('Larger board (4x4, 5x5, 6x6) Impossible heuristic search completes quickly and blocks threats', () {
      for (final size in [4, 5, 6]) {
        final board = List<String>.filled(size * size, '');
        for (int c = 0; c < size - 1; c++) {
          board[c] = 'h';
        }
        board[size * size - 1] = 'g';

        final sw = Stopwatch()..start();
        final move = BotEngine.computeMove(
          board: board,
          size: size,
          difficulty: BotDifficulty.impossible,
          botMark: 'g',
          humanMark: 'h',
        );
        sw.stop();

        expect(move, size - 1, reason: 'Bot must block winning row on ${size}x$size');
        expect(sw.elapsedMilliseconds, lessThan(1500));
      }
    });

    test('computeMoveAsync executes in background isolate and returns valid move', () async {
      const board = [
        'h', '', '',
        '', '', '',
        '', '', '',
      ];
      final move = await BotEngine.computeMoveAsync(
        board: board,
        size: 3,
        difficulty: BotDifficulty.impossible,
      );
      expect(move, 4);
    });
  });

  group('SinglePlayerRepository — Offline Stats, Deduplication, Achievements & Account Deletion', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('records wins, losses, draws, solo cups, streaks, and difficulty breakdown accurately offline', () async {
      final repo = SinglePlayerRepository(enableCloudSync: false);
      await repo.loadLocalAndSync();

      expect(repo.stats.totalGames, 0);

      // 1. Win on Easy Classic
      final recorded1 = await repo.recordGameResult(
        gameId: 'solo_1',
        difficulty: BotDifficulty.easy,
        mode: SinglePlayerMode.classic,
        boardSize: 3,
        bestOf: 1,
        outcome: 'win',
        playerScore: 1,
        botScore: 0,
        draws: 0,
      );
      expect(recorded1, isTrue);
      expect(repo.stats.totalGames, 1);
      expect(repo.stats.wins, 1);
      expect(repo.stats.currentStreak, 1);
      expect(repo.stats.bestStreak, 1);
      expect(repo.stats.statsFor(BotDifficulty.easy).wins, 1);
      expect(repo.achievements['first_solo_victory']?.isUnlocked, isTrue);

      // 2. Duplicate gameId must be ignored (no duplicate stats recording!)
      final dup = await repo.recordGameResult(
        gameId: 'solo_1',
        difficulty: BotDifficulty.easy,
        mode: SinglePlayerMode.classic,
        boardSize: 3,
        bestOf: 1,
        outcome: 'win',
        playerScore: 1,
        botScore: 0,
        draws: 0,
      );
      expect(dup, isFalse);
      expect(repo.stats.totalGames, 1);
      expect(repo.stats.wins, 1);

      // 3. Draw on Impossible
      final recorded2 = await repo.recordGameResult(
        gameId: 'solo_2',
        difficulty: BotDifficulty.impossible,
        mode: SinglePlayerMode.classic,
        boardSize: 3,
        bestOf: 1,
        outcome: 'draw',
        playerScore: 0,
        botScore: 0,
        draws: 1,
      );
      expect(recorded2, isTrue);
      expect(repo.stats.totalGames, 2);
      expect(repo.stats.draws, 1);
      expect(repo.stats.currentStreak, 1);
      expect(repo.stats.bestStreak, 1);
      expect(repo.stats.statsFor(BotDifficulty.impossible).draws, 1);
      expect(repo.achievements['impossible_draw']?.isUnlocked, isTrue);

      // 4. Win a Solo Tournament Cup
      final recorded3 = await repo.recordGameResult(
        gameId: 'solo_3',
        difficulty: BotDifficulty.normal,
        mode: SinglePlayerMode.tournament,
        boardSize: 3,
        bestOf: 3,
        outcome: 'win',
        playerScore: 2,
        botScore: 1,
        draws: 0,
        wonTournamentCup: true,
      );
      expect(recorded3, isTrue);
      expect(repo.stats.soloCups, 1);
      expect(repo.achievements['solo_tournament_champion']?.isUnlocked, isTrue);

      // 5. Verify persistence across new repository instance
      final repoReloaded = SinglePlayerRepository(enableCloudSync: false);
      await repoReloaded.loadLocalAndSync();
      expect(repoReloaded.stats.totalGames, 3);
      expect(repoReloaded.stats.wins, 2);
      expect(repoReloaded.stats.draws, 1);
      expect(repoReloaded.stats.soloCups, 1);
      expect(repoReloaded.history.length, 3);

      // 6. Account deletion / clearAllSoloData wipes all local solo stats, history & achievements
      await repoReloaded.clearAllSoloData(deleteCloud: false);
      expect(repoReloaded.stats.totalGames, 0);
      expect(repoReloaded.stats.wins, 0);
      expect(repoReloaded.stats.soloCups, 0);
      expect(repoReloaded.history, isEmpty);
      expect(
        repoReloaded.achievements.values.where((a) => a.isUnlocked),
        isEmpty,
      );
    });

    test('unlocks 5 consecutive wins and difficulty master achievements', () async {
      final repo = SinglePlayerRepository(enableCloudSync: false);
      await repo.loadLocalAndSync();

      for (int i = 1; i <= 5; i++) {
        await repo.recordGameResult(
          gameId: 'easy_win_$i',
          difficulty: BotDifficulty.easy,
          mode: SinglePlayerMode.classic,
          boardSize: 3,
          bestOf: 1,
          outcome: 'win',
          playerScore: 1,
          botScore: 0,
          draws: 0,
        );
      }

      expect(repo.stats.currentStreak, 5);
      expect(repo.achievements['easy_master']?.isUnlocked, isTrue);
      expect(repo.achievements['five_consecutive_wins']?.isUnlocked, isTrue);
    });
  });
}
