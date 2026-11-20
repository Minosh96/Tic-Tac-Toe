import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melow_tic_tac_toe/domain/models/game_room.dart';
import 'package:melow_tic_tac_toe/ui/core/app_theme.dart';
import 'package:melow_tic_tac_toe/ui/features/room/widgets/game_board.dart';
import 'package:melow_tic_tac_toe/ui/features/room/widgets/scoreboard_card.dart';

void main() {
  testWidgets('GameBoard renders marks and triggers callback on empty cell tap', (
    WidgetTester tester,
  ) async {
    int? tappedIndex;
    const board = [
      'h', '', '',
      '', 'g', '',
      '', '', '',
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: GameBoard(
            size: 3,
            board: board,
            emojiForSide: (s) => s == 'h' ? '❌' : '⭕',
            canPlay: true,
            onCellTap: (index) => tappedIndex = index,
          ),
        ),
      ),
    );

    expect(find.text('❌'), findsOneWidget);
    expect(find.text('⭕'), findsOneWidget);

    // Tap cell 2 (index 1, empty)
    await tester.tap(find.bySemanticsLabel('Cell 2, empty'));
    await tester.pump();
    expect(tappedIndex, 1);

    // Tapping an occupied cell does not overwrite tappedIndex
    tappedIndex = null;
    await tester.tap(find.bySemanticsLabel('Cell 1, ❌'));
    await tester.pump();
    expect(tappedIndex, isNull);
  });

  testWidgets('ScoreboardCard displays players, scores, and BO format', (
    WidgetTester tester,
  ) async {
    const room = GameRoom(
      code: 'ABC234',
      hostId: 'uid-host',
      guestId: 'uid-guest',
      hostName: 'Minosh',
      guestName: 'Alex',
      hostEmoji: '🔥',
      guestEmoji: '🚀',
      size: 3,
      bestOf: 5,
      status: 'playing',
      board: ['', '', '', '', '', '', '', '', ''],
      turn: 'h',
      round: 3,
      roundDone: false,
      hostWins: 2,
      guestWins: 1,
      draws: 1,
      lastResult: '',
      champion: '',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: ScoreboardCard(room: room, currentUid: 'uid-host'),
        ),
      ),
    );

    expect(find.text('Minosh (You)'), findsOneWidget);
    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('BO5'), findsOneWidget);
    expect(find.text('2 - 1'), findsOneWidget);
    expect(find.text('Draws: 1'), findsOneWidget);
  });
}
