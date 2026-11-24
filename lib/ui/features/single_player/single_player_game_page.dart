import 'dart:async';
import 'dart:math';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';

import '../../../core/services/app_services.dart';
import '../../../core/services/sound_service.dart';
import '../../../domain/bot_engine.dart';
import '../../../domain/game_engine.dart';
import '../../core/app_theme.dart';
import '../../core/widgets/footer.dart';
import '../../core/widgets/melow_avatar.dart';
import '../room/widgets/blitz_timer_bar.dart';
import '../room/widgets/game_board.dart';

class _BoardSnapshot {
  const _BoardSnapshot({
    required this.board,
    required this.turn,
  });

  final List<String> board;
  final String turn;
}

/// Offline-capable Single Player (Player vs System) match screen supporting
/// Easy, Normal, Hard, and Impossible AI, Classic/Tournament/Blitz modes,
/// Best of 3/5/7, Practice Hints & Undo, and isolated Solo statistics.
class SinglePlayerGamePage extends StatefulWidget {
  const SinglePlayerGamePage({
    super.key,
    required this.services,
    required this.playerName,
    required this.playerAvatar,
    required this.playerEmoji,
    this.botEmoji,
    required this.difficulty,
    required this.mode,
    required this.boardSize,
    required this.bestOf,
    required this.firstPlayer,
    this.practiceToolsEnabled = true,
  });

  final AppServices services;
  final String playerName;
  final String playerAvatar;
  final String playerEmoji;
  final String? botEmoji;
  final BotDifficulty difficulty;
  final SinglePlayerMode mode;
  final int boardSize;
  final int bestOf;
  final FirstPlayerChoice firstPlayer;
  final bool practiceToolsEnabled;

  @override
  State<SinglePlayerGamePage> createState() => _SinglePlayerGamePageState();
}

class _SinglePlayerGamePageState extends State<SinglePlayerGamePage> {
  late final ConfettiController _confettiController;
  final Random _rng = Random();

  late String _botEmoji;
  late List<String> _board;
  late String _turn; // 'h' = human player, 'g' = system bot
  int _round = 1;
  bool _roundDone = false;
  bool _seriesFinished = false;
  String _lastResult = ''; // '' | 'h' | 'g' | 'draw'
  String _champion = ''; // '' | 'h' | 'g'
  WinResult? _winResult;

  int _playerWins = 0;
  int _botWins = 0;
  int _draws = 0;

  bool _botThinking = false;
  int? _hintCellIndex;
  DateTime? _turnDeadlineAt;
  final List<_BoardSnapshot> _undoStack = <_BoardSnapshot>[];

  /// Incremented on every state reset, undo, round change, or dispose so
  /// any pending async bot move is safely ignored.
  int _turnGeneration = 0;
  late String _matchSessionId;

  int get _effectiveBestOf =>
      widget.mode == SinglePlayerMode.tournament ? widget.bestOf : 1;

  int get _winsNeeded => (_effectiveBestOf ~/ 2) + 1;

  bool get _isBlitz => widget.mode == SinglePlayerMode.blitz;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 2),
    );
    final chosenBot = widget.botEmoji?.trim() ?? '';
    _botEmoji = (chosenBot.isNotEmpty && chosenBot != widget.playerEmoji)
        ? chosenBot
        : _pickDistinctBotEmoji(widget.playerEmoji);
    _matchSessionId = '${DateTime.now().microsecondsSinceEpoch}';
    _initRound(roundNumber: 1, resetScores: true);
  }

  @override
  void dispose() {
    _turnGeneration++;
    _confettiController.dispose();
    super.dispose();
  }

  String _pickDistinctBotEmoji(String humanEmoji) {
    const candidates = ['🤖', '⭕', '❌', '⚡', '🔥', '👾'];
    for (final c in candidates) {
      if (c != humanEmoji) return c;
    }
    return '⭕';
  }

  String _resolveOpeningTurn(int roundNumber) {
    switch (widget.firstPlayer) {
      case FirstPlayerChoice.player:
        return roundNumber.isOdd ? 'h' : 'g';
      case FirstPlayerChoice.system:
        return roundNumber.isOdd ? 'g' : 'h';
      case FirstPlayerChoice.random:
        return _rng.nextBool() ? 'h' : 'g';
    }
  }

  void _initRound({required int roundNumber, required bool resetScores}) {
    _turnGeneration++;
    final n = widget.boardSize;
    final opening = _resolveOpeningTurn(roundNumber);
    setState(() {
      if (resetScores) {
        _playerWins = 0;
        _botWins = 0;
        _draws = 0;
        _champion = '';
        _seriesFinished = false;
        _matchSessionId = '${DateTime.now().microsecondsSinceEpoch}';
      }
      _round = roundNumber;
      _board = List<String>.filled(n * n, '');
      _turn = opening;
      _roundDone = false;
      _lastResult = '';
      _winResult = null;
      _botThinking = false;
      _hintCellIndex = null;
      _undoStack.clear();
      _turnDeadlineAt = _isBlitz
          ? DateTime.now().add(const Duration(seconds: kBlitzTurnSeconds))
          : null;
    });

    if (opening == 'g') {
      _scheduleBotMove();
    }
  }

  Future<void> _onHumanCellTap(int index) async {
    if (_roundDone || _seriesFinished || _botThinking || _turn != 'h') return;
    if (index < 0 || index >= _board.length || _board[index].isNotEmpty) return;

    // Save snapshot for Practice Undo before human move
    _undoStack.add(
      _BoardSnapshot(
        board: List<String>.from(_board, growable: false),
        turn: _turn,
      ),
    );

    widget.services.sound.play(SoundEffect.place);
    widget.services.sound.hapticLight();

    setState(() {
      _board[index] = 'h';
      _hintCellIndex = null;
    });

    final ended = await _evaluateAfterMove(moverSide: 'h');
    if (!ended && mounted) {
      setState(() {
        _turn = 'g';
        _turnDeadlineAt = _isBlitz
            ? DateTime.now().add(const Duration(seconds: kBlitzTurnSeconds))
            : null;
      });
      _scheduleBotMove();
    }
  }

  void _scheduleBotMove() {
    final gen = ++_turnGeneration;
    setState(() => _botThinking = true);

    Future<void>(() async {
      // Short, natural thinking pause so moves feel responsive and organic
      final delayMs = widget.difficulty == BotDifficulty.easy ? 260 : 380;
      await Future<void>.delayed(Duration(milliseconds: delayMs));
      if (!mounted || gen != _turnGeneration || _roundDone || _turn != 'g') {
        return;
      }

      final move = await BotEngine.computeMoveAsync(
        board: _board,
        size: widget.boardSize,
        difficulty: widget.difficulty,
        botMark: 'g',
        humanMark: 'h',
      );

      if (!mounted || gen != _turnGeneration || _roundDone || _turn != 'g') {
        return;
      }

      if (move < 0 || move >= _board.length || _board[move].isNotEmpty) {
        // Fallback safety guard: pick first available empty cell
        final fallback = BotEngine.legalMoves(_board);
        if (fallback.isEmpty) {
          setState(() => _botThinking = false);
          return;
        }
        setState(() {
          _board[fallback.first] = 'g';
          _botThinking = false;
        });
      } else {
        setState(() {
          _board[move] = 'g';
          _botThinking = false;
        });
      }

      widget.services.sound.play(SoundEffect.place);
      final ended = await _evaluateAfterMove(moverSide: 'g');
      if (!ended && mounted && gen == _turnGeneration) {
        setState(() {
          _turn = 'h';
          _turnDeadlineAt = _isBlitz
              ? DateTime.now().add(const Duration(seconds: kBlitzTurnSeconds))
              : null;
        });
      }
    });
  }

  Future<bool> _evaluateAfterMove({required String moverSide}) async {
    final win = GameEngine.evaluateWinner(_board, widget.boardSize);
    final isDraw = win == null && !_board.contains('');
    if (win == null && !isDraw) return false;

    _turnGeneration++; // Cancel any pending timers/searches
    final roundWinner = isDraw ? 'draw' : win!.winner;
    final nextPlayerWins = _playerWins + (roundWinner == 'h' ? 1 : 0);
    final nextBotWins = _botWins + (roundWinner == 'g' ? 1 : 0);
    final nextDraws = _draws + (isDraw ? 1 : 0);

    String champ = '';
    if (nextPlayerWins >= _winsNeeded) {
      champ = 'h';
    } else if (nextBotWins >= _winsNeeded) {
      champ = 'g';
    } else if (widget.mode != SinglePlayerMode.tournament) {
      // In single-game Classic or Blitz (bestOf == 1), a draw also completes the game
      champ = isDraw ? 'draw' : roundWinner;
    }

    final seriesDone = champ.isNotEmpty;
    final wonTournamentCup =
        widget.mode == SinglePlayerMode.tournament && champ == 'h';

    setState(() {
      _winResult = win;
      _roundDone = true;
      _botThinking = false;
      _lastResult = roundWinner;
      _playerWins = nextPlayerWins;
      _botWins = nextBotWins;
      _draws = nextDraws;
      _champion = champ;
      _seriesFinished = seriesDone;
      _turnDeadlineAt = null;
    });

    final reducedMotion = widget.services.preferences.reducedMotion ||
        MediaQuery.of(context).disableAnimations;

    if (roundWinner == 'h') {
      widget.services.sound.play(
        wonTournamentCup ? SoundEffect.trophy : SoundEffect.win,
      );
      widget.services.sound.hapticMedium();
      if (!reducedMotion) {
        _confettiController.play();
      }
    } else if (roundWinner == 'draw') {
      widget.services.sound.play(SoundEffect.draw);
    } else {
      widget.services.sound.play(SoundEffect.draw);
    }

    final outcome = roundWinner == 'h'
        ? 'win'
        : (roundWinner == 'g' ? 'loss' : 'draw');
    final gameId =
        'solo_${_matchSessionId}_r${_round}_${nextPlayerWins}_${nextBotWins}_$nextDraws';

    await widget.services.singlePlayer.recordGameResult(
      gameId: gameId,
      difficulty: widget.difficulty,
      mode: widget.mode,
      boardSize: widget.boardSize,
      bestOf: _effectiveBestOf,
      outcome: outcome,
      playerScore: nextPlayerWins,
      botScore: nextBotWins,
      draws: nextDraws,
      wonTournamentCup: wonTournamentCup,
    );

    return true;
  }

  Future<void> _onBlitzTimeout() async {
    if (!_isBlitz || _roundDone || _seriesFinished) return;
    _turnGeneration++;
    final timedOutSide = _turn;
    final winnerSide = timedOutSide == 'h' ? 'g' : 'h';

    final nextPlayerWins = _playerWins + (winnerSide == 'h' ? 1 : 0);
    final nextBotWins = _botWins + (winnerSide == 'g' ? 1 : 0);
    final champ = nextPlayerWins >= _winsNeeded
        ? 'h'
        : (nextBotWins >= _winsNeeded ? 'g' : '');
    final seriesDone = champ.isNotEmpty;

    setState(() {
      _roundDone = true;
      _botThinking = false;
      _lastResult = winnerSide;
      _playerWins = nextPlayerWins;
      _botWins = nextBotWins;
      _champion = champ;
      _seriesFinished = seriesDone;
      _turnDeadlineAt = null;
    });

    widget.services.sound.play(
      winnerSide == 'h' ? SoundEffect.win : SoundEffect.draw,
    );

    final gameId =
        'solo_timeout_${_matchSessionId}_r${_round}_${nextPlayerWins}_$nextBotWins';
    await widget.services.singlePlayer.recordGameResult(
      gameId: gameId,
      difficulty: widget.difficulty,
      mode: widget.mode,
      boardSize: widget.boardSize,
      bestOf: _effectiveBestOf,
      outcome: winnerSide == 'h' ? 'win' : 'loss',
      playerScore: nextPlayerWins,
      botScore: nextBotWins,
      draws: _draws,
      wonTournamentCup: false,
    );
  }

  Future<void> _requestHint() async {
    if (_roundDone || _seriesFinished || _botThinking || _turn != 'h') return;
    final hint = await BotEngine.computeHintAsync(
      board: _board,
      size: widget.boardSize,
      humanMark: 'h',
      botMark: 'g',
    );
    if (!mounted || hint < 0) return;
    setState(() => _hintCellIndex = hint);
    final row = (hint ~/ widget.boardSize) + 1;
    final col = (hint % widget.boardSize) + 1;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('💡 Recommended move: Row $row, Column $col'),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _undoLastTurn() {
    if (_undoStack.isEmpty || _roundDone || _seriesFinished) return;
    _turnGeneration++;
    final prev = _undoStack.removeLast();
    setState(() {
      _board = List<String>.from(prev.board);
      _turn = prev.turn;
      _botThinking = false;
      _hintCellIndex = null;
    });
    widget.services.sound.play(SoundEffect.click);
  }

  String _statusBannerText() {
    if (_roundDone) {
      if (_seriesFinished && widget.mode == SinglePlayerMode.tournament) {
        return _champion == 'h'
            ? '🏆 You Won the Solo Tournament Cup!'
            : '🤖 Melow Bot Won the Tournament';
      }
      if (_lastResult == 'h') return '🎉 You Won Round $_round!';
      if (_lastResult == 'g') return '🤖 Melow Bot Won Round $_round';
      return '🤝 Round $_round Ended in a Draw!';
    }
    if (_botThinking || _turn == 'g') {
      return '🤖 Melow Bot (${widget.difficulty.label}) is thinking…';
    }
    if (_hintCellIndex != null) {
      final r = (_hintCellIndex! ~/ widget.boardSize) + 1;
      final c = (_hintCellIndex! % widget.boardSize) + 1;
      return '💡 Your Turn — Try Row $r, Col $c (${widget.playerEmoji})';
    }
    return '🎯 Your Turn (${widget.playerEmoji})';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final showPracticeTools = widget.practiceToolsEnabled && !_isBlitz;

    return Scaffold(
      appBar: AppBar(
        title: Text('Solo • ${widget.difficulty.label}'),
        actions: [
          IconButton(
            tooltip: 'Restart Match',
            icon: const Icon(Icons.replay_rounded),
            onPressed: () => _initRound(roundNumber: 1, resetScores: true),
          ),
        ],
      ),
      body: Stack(
        alignment: Alignment.topCenter,
        children: [
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    // Solo Scoreboard Card
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              alignment: WrapAlignment.center,
                              children: [
                                _BadgeChip(
                                  icon: widget.difficulty.icon,
                                  label: widget.difficulty.label,
                                ),
                                _BadgeChip(
                                  icon: '🎛️',
                                  label: widget.mode.label,
                                ),
                                _BadgeChip(
                                  icon: '⊞',
                                  label:
                                      '${widget.boardSize}×${widget.boardSize}',
                                ),
                                if (widget.mode ==
                                    SinglePlayerMode.tournament)
                                  _BadgeChip(
                                    icon: '🏆',
                                    label: 'BO${widget.bestOf}',
                                  ),
                              ],
                            ),
                            if (widget.difficulty ==
                                    BotDifficulty.impossible &&
                                widget.boardSize > 3) ...[
                              const SizedBox(height: 6),
                              Text(
                                widget.difficulty
                                    .subtitleForSize(widget.boardSize),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _CompetitorColumn(
                                    name: '${widget.playerName} (You)',
                                    emoji: widget.playerEmoji,
                                    avatarId: widget.playerAvatar,
                                    isActive: !_roundDone && _turn == 'h',
                                    wins: _playerWins,
                                    winsNeeded: _winsNeeded,
                                    showStars: widget.mode ==
                                        SinglePlayerMode.tournament,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        '$_playerWins - $_botWins',
                                        style: const TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      Text(
                                        widget.mode ==
                                                SinglePlayerMode.tournament
                                            ? 'Round $_round'
                                            : (_draws > 0
                                                ? '$_draws Draw${_draws == 1 ? '' : 's'}'
                                                : 'Solo Match'),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: scheme.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: _CompetitorColumn(
                                    name: 'Melow Bot',
                                    emoji: _botEmoji,
                                    avatarId: 'robot',
                                    isActive:
                                        !_roundDone && (_turn == 'g' || _botThinking),
                                    wins: _botWins,
                                    winsNeeded: _winsNeeded,
                                    showStars: widget.mode ==
                                        SinglePlayerMode.tournament,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Blitz Timer Bar
                    if (_isBlitz && !_roundDone && _turnDeadlineAt != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: BlitzTimerBar(
                          deadline: _turnDeadlineAt,
                          round: _round,
                          turnKey: '$_round-$_turn-$_turnGeneration',
                          active: !_roundDone && !_seriesFinished,
                          isMyTurn: _turn == 'h',
                          onExpired: _onBlitzTimeout,
                        ),
                      ),
                    // Status / Thinking Banner
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: _roundDone
                            ? (_lastResult == 'h'
                                ? AppTheme.goldAccent.withValues(alpha: 0.2)
                                : scheme.surfaceContainerHighest)
                            : scheme.primaryContainer.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_botThinking) ...[
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Flexible(
                            child: Text(
                              _statusBannerText(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Game Board (reuses existing GameBoard component!)
                    GameBoard(
                      board: _board,
                      size: widget.boardSize,
                      emojiForSide: (side) =>
                          side == 'h' ? widget.playerEmoji : _botEmoji,
                      winningLine: _winResult?.line ?? const [],
                      canPlay:
                          !_roundDone && !_seriesFinished && !_botThinking && _turn == 'h',
                      reducedMotion:
                          widget.services.preferences.reducedMotion ||
                              MediaQuery.of(context).disableAnimations,
                      hapticsEnabled:
                          widget.services.preferences.hapticsEnabled,
                      onCellTap: _onHumanCellTap,
                    ),
                    const SizedBox(height: 12),
                    // Practice Mode Tools (Hint & Undo)
                    if (showPracticeTools && !_roundDone)
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: (_botThinking || _turn != 'h')
                                  ? null
                                  : _requestHint,
                              icon: const Icon(
                                Icons.lightbulb_outline_rounded,
                                size: 18,
                              ),
                              label: const Text('Hint'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: (_botThinking || _undoStack.isEmpty)
                                  ? null
                                  : _undoLastTurn,
                              icon: const Icon(Icons.undo_rounded, size: 18),
                              label: const Text('Undo Move'),
                            ),
                          ),
                        ],
                      ),
                    // Post-Round & Post-Tournament Action Buttons
                    if (_roundDone) ...[
                      const SizedBox(height: 6),
                      if (!_seriesFinished &&
                          widget.mode == SinglePlayerMode.tournament)
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                          onPressed: () => _initRound(
                            roundNumber: _round + 1,
                            resetScores: false,
                          ),
                          icon: const Icon(Icons.skip_next_rounded),
                          label: Text('Start Round ${_round + 1}'),
                        )
                      else
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(48),
                                ),
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.arrow_back_rounded),
                                label: const Text('Dashboard'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(48),
                                ),
                                onPressed: () => _initRound(
                                  roundNumber: 1,
                                  resetScores: true,
                                ),
                                icon: const Icon(Icons.replay_rounded),
                                label: const Text('Play Again'),
                              ),
                            ),
                          ],
                        ),
                    ],
                    const MelowFooter(),
                  ],
                ),
              ),
            ),
          ),
          ConfettiWidget(
            confettiController: _confettiController,
            blastDirectionality: BlastDirectionality.explosive,
            shouldLoop: false,
            numberOfParticles: 24,
          ),
        ],
      ),
    );
  }
}

class _BadgeChip extends StatelessWidget {
  const _BadgeChip({required this.icon, required this.label});
  final String icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        '$icon $label',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _CompetitorColumn extends StatelessWidget {
  const _CompetitorColumn({
    required this.name,
    required this.emoji,
    required this.avatarId,
    required this.isActive,
    required this.wins,
    required this.winsNeeded,
    required this.showStars,
  });

  final String name;
  final String emoji;
  final String avatarId;
  final bool isActive;
  final int wins;
  final int winsNeeded;
  final bool showStars;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            MelowAvatar(
              avatarId: avatarId,
              size: 38,
              borderColor: isActive ? AppTheme.cyanAccent : null,
            ),
            const SizedBox(width: 6),
            Text(emoji, style: const TextStyle(fontSize: 22)),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13,
            color: isActive ? AppTheme.cyanAccent : null,
          ),
        ),
        if (showStars) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < winsNeeded; i++)
                Icon(
                  i < wins ? Icons.star_rounded : Icons.star_border_rounded,
                  size: 16,
                  color: AppTheme.goldAccent,
                ),
            ],
          ),
        ],
      ],
    );
  }
}
