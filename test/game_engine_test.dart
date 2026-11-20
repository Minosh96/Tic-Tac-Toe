import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:melow_tic_tac_toe/domain/game_engine.dart';

void main() {
  group('GameEngine.evaluateWinner', () {
    test('detects row win on 3x3 board with exact winning line', () {
      const board = [
        'h', 'h', 'h',
        'g', '', 'g',
        '', '', '',
      ];
      final result = GameEngine.evaluateWinner(board, 3);
      expect(result, isNotNull);
      expect(result!.winner, 'h');
      expect(result.line, [0, 1, 2]);
    });

    test('detects column win on 4x4 board', () {
      const board = [
        '', 'g', '', '',
        'h', 'g', '', '',
        '', 'g', 'h', '',
        '', 'g', '', '',
      ];
      final result = GameEngine.evaluateWinner(board, 4);
      expect(result, isNotNull);
      expect(result!.winner, 'g');
      expect(result.line, [1, 5, 9, 13]);
    });

    test('detects main diagonal win on 5x5 board', () {
      final board = List<String>.filled(25, '');
      for (var i = 0; i < 5; i++) {
        board[i * 5 + i] = 'h';
      }
      final result = GameEngine.evaluateWinner(board, 5);
      expect(result, isNotNull);
      expect(result!.winner, 'h');
      expect(result.line, [0, 6, 12, 18, 24]);
    });

    test('detects anti-diagonal win on 6x6 board', () {
      final board = List<String>.filled(36, '');
      for (var i = 0; i < 6; i++) {
        board[i * 6 + (5 - i)] = 'g';
      }
      final result = GameEngine.evaluateWinner(board, 6);
      expect(result, isNotNull);
      expect(result!.winner, 'g');
      expect(result.line, [5, 10, 15, 20, 25, 30]);
    });

    test('returns null for a full draw board and isDraw is true', () {
      const board = [
        'h', 'g', 'h',
        'h', 'g', 'g',
        'g', 'h', 'h',
      ];
      expect(GameEngine.evaluateWinner(board, 3), isNull);
      expect(GameEngine.isDraw(board, 3), isTrue);
    });

    test('returns null for incomplete board with no winner', () {
      const board = [
        'h', 'g', '',
        '', 'h', '',
        '', '', 'g',
      ];
      expect(GameEngine.evaluateWinner(board, 3), isNull);
      expect(GameEngine.isDraw(board, 3), isFalse);
    });
  });

  group('GameEngine tournament math', () {
    test('calculates winsNeeded for best-of-3 and best-of-5', () {
      expect(GameEngine.winsNeeded(3), 2);
      expect(GameEngine.winsNeeded(5), 3);
    });

    test('computes tournament champion accurately', () {
      expect(
        GameEngine.computeChampion(hostWins: 1, guestWins: 1, bestOf: 3),
        '',
      );
      expect(
        GameEngine.computeChampion(hostWins: 2, guestWins: 1, bestOf: 3),
        'h',
      );
      expect(
        GameEngine.computeChampion(hostWins: 2, guestWins: 3, bestOf: 5),
        'g',
      );
    });

    test('alternates starting player across rounds', () {
      expect(GameEngine.startingTurnForRound(1), 'h');
      expect(GameEngine.startingTurnForRound(2), 'g');
      expect(GameEngine.startingTurnForRound(3), 'h');
      expect(GameEngine.startingTurnForRound(4), 'g');
    });

    test('generates 6-character uppercase non-ambiguous room codes', () {
      final code = GameEngine.generateRoomCode(Random(42));
      expect(code.length, 6);
      expect(RegExp(r'^[A-HJ-NP-Z2-9]{6}$').hasMatch(code), isTrue);
    });
  });
}
