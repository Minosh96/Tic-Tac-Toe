import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melow_tic_tac_toe/domain/game_engine.dart';
import 'package:melow_tic_tac_toe/domain/models/game_room.dart';
import 'package:melow_tic_tac_toe/ui/core/app_theme.dart';
import 'package:melow_tic_tac_toe/ui/features/about/about_screen.dart';
import 'package:melow_tic_tac_toe/ui/features/room/widgets/blitz_timer_bar.dart';
import 'package:melow_tic_tac_toe/ui/features/room/widgets/game_board.dart';
import 'package:melow_tic_tac_toe/ui/features/room/widgets/scoreboard_card.dart';
import 'package:melow_tic_tac_toe/ui/features/sharing/victory_card_sheet.dart';

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

    await tester.tap(find.bySemanticsLabel('Cell 2, empty'));
    await tester.pump();
    expect(tappedIndex, 1);

    tappedIndex = null;
    await tester.tap(find.bySemanticsLabel('Cell 1, ❌'));
    await tester.pump();
    expect(tappedIndex, isNull);
  });

  testWidgets('ScoreboardCard displays players, scores, BO format and Blitz badge', (
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
      size: 4,
      bestOf: 5,
      gameMode: GameMode.blitz,
      status: 'playing',
      board: [
        '', '', '', '',
        '', '', '', '',
        '', '', '', '',
        '', '', '', '',
      ],
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
    expect(find.text('4×4'), findsOneWidget);
    expect(find.text('Blitz (5s)'), findsOneWidget);
    expect(find.text('2 - 1'), findsOneWidget);
    expect(find.text('Draws: 1'), findsOneWidget);
  });

  testWidgets('VictoryCardSheet hides opponent name when privacy toggle is on', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: VictoryCardSheet(
              winnerName: 'Minosh',
              winnerAvatar: 'astro',
              opponentName: 'SecretOpponent',
              scoreText: '2 - 0',
              gameMode: GameMode.blitz,
              boardSize: 3,
              isTournamentChampion: true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('CHAMPION!'), findsOneWidget);
    expect(find.text('vs SecretOpponent'), findsOneWidget);
    expect(find.text('Developed at Melow Labs'), findsOneWidget);

    await tester.tap(find.text('Hide opponent nickname'));
    await tester.pump();
    expect(find.text('vs SecretOpponent'), findsNothing);
  });

  testWidgets('BlitzTimerBar fires onExpired once when deadline passes', (
    WidgetTester tester,
  ) async {
    int expiredCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: BlitzTimerBar(
            deadline: DateTime.now().subtract(const Duration(seconds: 1)),
            round: 1,
            turnKey: '1-h-0',
            active: true,
            isMyTurn: true,
            onExpired: () => expiredCount++,
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 250));
    expect(expiredCount, 1);
  });

  testWidgets('AboutScreen shows v2.0 branding and Melow Labs credit', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark(), home: const AboutScreen()),
    );
    expect(find.text('Melow Tic Tac Toe'), findsOneWidget);
    expect(find.text('Version 2.0.0 (Build 2)'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Developed at Melow Labs'),
      200,
    );
    expect(find.text('Developed at Melow Labs'), findsOneWidget);
  });
}
