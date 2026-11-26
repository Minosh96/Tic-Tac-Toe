import 'dart:async';
import 'dart:math';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/services/app_services.dart';
import '../../../core/services/image_helper.dart';
import '../../../core/services/sound_service.dart';
import '../../../domain/game_engine.dart';
import '../../../domain/models/game_room.dart';
import '../../../domain/models/room_reaction.dart';
import '../../core/app_theme.dart';
import '../../core/widgets/footer.dart';
import '../challenge_wheel/challenge_wheel_dialog.dart';
import '../chat/voice_call_screen.dart';
import '../sharing/victory_card_sheet.dart';
import 'widgets/blitz_timer_bar.dart';
import 'widgets/game_board.dart';
import 'widgets/reaction_overlay.dart';
import 'widgets/room_chat_panel.dart';
import 'widgets/scoreboard_card.dart';

/// Melow v3.0 Game Room with automatic trophy/cup recording, Blitz mode,
/// Challenge Wheel, Reactions/Taunts, Image Chat, Voice Call & Victory Sharing.
class RoomPage extends StatefulWidget {
  const RoomPage({
    super.key,
    required this.code,
    required this.services,
  });

  final String code;
  final AppServices services;

  @override
  State<RoomPage> createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> {
  final TextEditingController _chatController = TextEditingController();
  late final ConfettiController _confettiController;

  bool _sendingChat = false;
  bool _actionBusy = false;
  bool _chatExpanded = false;
  bool _confirmedLeave = false;

  String? _lastWheelSpinId;
  String? _lastRecordedMatchKey;
  int _lastSoundRound = 0;
  bool _lastRoundDone = false;
  bool _lastFinished = false;
  bool _wasOpponentLeft = false;
  bool _opponentRejoinedBannerVisible = false;
  bool _sentInitialPresence = false;
  Timer? _rejoinBannerTimer;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 2),
    );
    // Clear any stale hostLeft/guestLeft flag for our side when entering/rejoining the room!
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.services.game.markPlayerPresent(widget.code);
      }
    });
  }

  @override
  void dispose() {
    _rejoinBannerTimer?.cancel();
    _chatController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    widget.services.sound.play(SoundEffect.click);
    _notice('Room code ${widget.code} copied');
  }

  Future<void> _sendMessage({String? imageBase64}) async {
    final text = _chatController.text.trim();
    if (text.isEmpty && (imageBase64 == null || imageBase64.isEmpty)) return;
    if (_sendingChat) return;
    setState(() => _sendingChat = true);
    try {
      await widget.services.game.sendChatMessage(
        widget.code,
        text,
        imageBase64: imageBase64,
      );
      _chatController.clear();
    } catch (e) {
      _notice('Chat failed: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _sendingChat = false);
    }
  }

  Future<void> _pickAndSendChatImage() async {
    try {
      final base64Img = await ImageHelper.pickChatImageBase64(
        source: ImageSource.gallery,
      );
      if (base64Img != null) {
        await _sendMessage(imageBase64: base64Img);
      }
    } catch (e) {
      _notice(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _sendReaction(String kind, String payload) async {
    try {
      widget.services.sound.play(SoundEffect.click);
      await widget.services.game.sendReaction(
        code: widget.code,
        kind: kind,
        payload: payload,
      );
    } catch (e) {
      _notice(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _runRoomAction(Future<void> Function() action) async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      await action();
    } catch (e) {
      _notice(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  void _handleRoomStateEffects(GameRoom room, String mySide) {
    final reducedMotion = widget.services.preferences.reducedMotion ||
        MediaQuery.of(context).disableAnimations;

    // If our own side still has hostLeft/guestLeft == true on the snapshot, clear it immediately!
    final myLeftFlag = mySide == 'h' ? room.hostLeft : room.guestLeft;
    if (myLeftFlag && !_confirmedLeave && !_sentInitialPresence) {
      _sentInitialPresence = true;
      widget.services.game.markPlayerPresent(widget.code);
    } else if (!myLeftFlag) {
      _sentInitialPresence = false;
    }

    // Track opponent leave -> rejoin transition and notify when opponent is back!
    final opponentLeftNow =
        (mySide == 'h' && room.guestLeft) || (mySide == 'g' && room.hostLeft);
    if (opponentLeftNow && !_wasOpponentLeft) {
      _wasOpponentLeft = true;
      _opponentRejoinedBannerVisible = false;
    } else if (!opponentLeftNow && _wasOpponentLeft) {
      _wasOpponentLeft = false;
      _opponentRejoinedBannerVisible = true;
      final oppSide = mySide == 'h' ? 'g' : 'h';
      final oppName = room.playerName(oppSide);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.services.sound.play(SoundEffect.click);
        _notice('👋 Your opponent ($oppName) is back in the room!');
        setState(() {});
      });
      _rejoinBannerTimer?.cancel();
      _rejoinBannerTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) {
          setState(() => _opponentRejoinedBannerVisible = false);
        }
      });
    }

    // Immediately record round win/loss/draw & tournament cup/trophy/achievement/stats for BOTH players!
    if (room.roundDone || (room.isFinished && room.champion.isNotEmpty)) {
      final tsTag = room.turnStartedAt?.millisecondsSinceEpoch ?? 0;
      final matchKey =
          '${room.code}_${tsTag}_${room.hostWins}_${room.guestWins}_${room.draws}_${room.round}';
      if (_lastRecordedMatchKey != matchKey) {
        _lastRecordedMatchKey = matchKey;
        widget.services.game.recordFinishedMatchForCurrentUser(room);
      }
    }

    final spin = room.wheelResult;
    if (spin != null && spin.spinId != _lastWheelSpinId) {
      _lastWheelSpinId = spin.spinId;
      final option = spin.option;
      if (option != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (_) => ChallengeWheelDialog(
              targetOption: option,
              reducedMotion: reducedMotion,
              hostEmoji: spin.hostEmoji,
              guestEmoji: spin.guestEmoji,
            ),
          );
        });
      }
    }

    if (room.isFinished && !_lastFinished) {
      _lastFinished = true;
      _lastRoundDone = true;
      _lastSoundRound = room.round;
      widget.services.sound.play(SoundEffect.trophy);
      widget.services.sound.hapticMedium();
      if (!reducedMotion && room.champion == mySide) {
        _confettiController.play();
      }
    } else if (!room.isFinished &&
        room.roundDone &&
        (!_lastRoundDone || _lastSoundRound != room.round)) {
      _lastRoundDone = true;
      _lastSoundRound = room.round;
      if (room.lastResult == 'draw') {
        widget.services.sound.play(SoundEffect.draw);
      } else {
        widget.services.sound.play(SoundEffect.win);
        if (!reducedMotion && room.lastResult == mySide) {
          _confettiController.play();
        }
      }
    } else if (!room.roundDone) {
      _lastRoundDone = false;
      _lastFinished = false;
    }
  }

  Future<bool> _confirmLeaveGame() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Match Room?'),
        content: const Text(
          'Your opponent will be notified if you leave this room.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (leave == true) {
      _confirmedLeave = true;
      await widget.services.game.leaveRoom(widget.code);
      return true;
    }
    return false;
  }

  void _openReactionsSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Send Live Reaction',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final emoji in allowedReactionEmojis)
                    ActionChip(
                      label: Text(emoji, style: const TextStyle(fontSize: 26)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        _sendReaction('emoji', emoji);
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openQuickTauntsSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Quick Taunts',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final taunt in allowedQuickTaunts)
                    ActionChip(
                      avatar: const Icon(Icons.campaign_rounded, size: 18),
                      label: Text(
                        taunt,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        _sendReaction('taunt', taunt);
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openVictoryShareSheet(GameRoom room) {
    final champSide = room.champion.isNotEmpty ? room.champion : room.lastResult;
    final winnerSide = (champSide == 'h' || champSide == 'g') ? champSide : 'h';
    final loserSide = winnerSide == 'h' ? 'g' : 'h';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => VictoryCardSheet(
        winnerName: room.playerName(winnerSide),
        winnerAvatar: room.playerAvatar(winnerSide),
        opponentName: room.playerName(loserSide),
        scoreText: '${room.hostWins} - ${room.guestWins}',
        gameMode: room.gameMode,
        boardSize: room.size,
        isTournamentChampion: room.isFinished,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.services.game.currentUid;
    final prefs = widget.services.preferences;
    final scheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: _confirmedLeave,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await _confirmLeaveGame();
        if (ok && context.mounted) Navigator.pop(context);
      },
      child: StreamBuilder<GameRoom?>(
        stream: widget.services.game.watchRoom(widget.code),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Scaffold(
              appBar: AppBar(title: Text('Room ${widget.code}')),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Unable to load room:\n${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return Scaffold(
              appBar: AppBar(title: Text('Room ${widget.code}')),
              body: const Center(child: CircularProgressIndicator()),
            );
          }

          final room = snapshot.data;
          if (room == null) {
            return Scaffold(
              appBar: AppBar(title: Text('Room ${widget.code}')),
              body: const Center(child: Text('This room no longer exists.')),
            );
          }

          final mySide = room.sideForUid(uid);
          if (mySide == null) {
            return Scaffold(
              appBar: AppBar(title: Text('Room ${widget.code}')),
              body: const Center(child: Text('This room is private.')),
            );
          }

          _handleRoomStateEffects(room, mySide);

          final myTurn = room.turn == mySide;
          final winResult = room.winResult;
          final opponentSide = mySide == 'h' ? 'g' : 'h';
          final opponentUid = mySide == 'h' ? room.guestId : room.hostId;
          final opponentLeft =
              (mySide == 'h' && room.guestLeft) || (mySide == 'g' && room.hostLeft);
          final reducedMotion = prefs.reducedMotion ||
              MediaQuery.of(context).disableAnimations;

          return Scaffold(
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.exit_to_app_rounded),
                tooltip: 'Leave game',
                onPressed: () async {
                  final ok = await _confirmLeaveGame();
                  if (ok && context.mounted) Navigator.pop(context);
                },
              ),
              title: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Room ${widget.code}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              actions: [
                if (opponentUid.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.call_rounded),
                    tooltip: 'Voice call opponent',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VoiceCallScreen.outgoing(
                          services: widget.services,
                          calleeUid: opponentUid,
                          calleeName: room.playerName(opponentSide),
                          calleeAvatar: room.playerAvatar(opponentSide),
                          callerName: room.playerName(mySide),
                          callerAvatar: room.playerAvatar(mySide),
                          roomId: widget.code,
                        ),
                      ),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded),
                  tooltip: 'Copy room code',
                  onPressed: _copyCode,
                ),
              ],
            ),
            body: Stack(
              children: [
                SafeArea(
                  child: Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 520),
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                              children: [
                                ScoreboardCard(
                                  room: room,
                                  currentUid: uid,
                                  services: widget.services,
                                ),
                                if (opponentLeft) ...[
                                  const SizedBox(height: 10),
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: scheme.errorContainer,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      'Your opponent left the room.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: scheme.onErrorContainer,
                                      ),
                                    ),
                                  ),
                                ] else if (_opponentRejoinedBannerVisible) ...[
                                  const SizedBox(height: 10),
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.green,
                                      ),
                                    ),
                                    child: Text(
                                      '👋 Your opponent (${room.playerName(opponentSide)}) is back!',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: Colors.green,
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                if (room.isLobby)
                                  _LobbyCard(
                                    code: widget.code,
                                    hostEmoji: room.hostEmoji,
                                    size: room.size,
                                    bestOf: room.bestOf,
                                    mode: room.gameMode,
                                    onCopyCode: _copyCode,
                                  )
                                else ...[
                                  if (room.canUseChallengeWheel)
                                    _ChallengeWheelBanner(
                                      room: room,
                                      isHost: mySide == 'h',
                                      busy: _actionBusy,
                                      onPropose: () => _runRoomAction(
                                        () => widget.services.game
                                            .proposeChallengeWheel(widget.code),
                                      ),
                                      onRespond: (accept) => _runRoomAction(
                                        () => widget.services.game
                                            .respondChallengeWheel(
                                          widget.code,
                                          accept: accept,
                                        ),
                                      ),
                                    ),
                                  _StatusBanner(room: room, myTurn: myTurn),
                                  if (room.isBlitz &&
                                      room.isPlaying &&
                                      !room.roundDone) ...[
                                    const SizedBox(height: 10),
                                    BlitzTimerBar(
                                      deadline: room.turnDeadlineAt,
                                      round: room.round,
                                      turnKey:
                                          '${room.round}-${room.turn}-${room.board.where((c) => c.isNotEmpty).length}',
                                      active: room.isPlaying && !room.roundDone,
                                      isMyTurn: myTurn,
                                      onExpired: () => widget.services.game
                                          .claimBlitzTimeout(
                                        widget.code,
                                        room.round,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  GameBoard(
                                    size: room.size,
                                    board: room.board,
                                    emojiForSide: room.playerEmoji,
                                    canPlay: room.isPlaying &&
                                        !room.roundDone &&
                                        myTurn,
                                    winningLine: winResult?.line ?? const [],
                                    reducedMotion: reducedMotion,
                                    hapticsEnabled: prefs.hapticsEnabled,
                                    onCellTap: (index) {
                                      widget.services.sound
                                          .play(SoundEffect.place);
                                      _runRoomAction(
                                        () => widget.services.game
                                            .playMove(widget.code, index),
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                            ),
                                          ),
                                          onPressed: _openReactionsSheet,
                                          icon: const Text('😂'),
                                          label: const FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text('React'),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                            ),
                                          ),
                                          onPressed: _openQuickTauntsSheet,
                                          icon: const Icon(
                                            Icons.campaign_rounded,
                                            size: 18,
                                          ),
                                          label: const FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text('Taunt'),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton.filledTonal(
                                        tooltip: _chatExpanded
                                            ? 'Hide chat'
                                            : 'Open room chat',
                                        onPressed: () => setState(
                                          () => _chatExpanded = !_chatExpanded,
                                        ),
                                        icon: Icon(
                                          _chatExpanded
                                              ? Icons.chat_bubble_rounded
                                              : Icons.chat_bubble_outline_rounded,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  if (room.isFinished)
                                    _ChampionCard(
                                      winnerName:
                                          room.playerName(room.champion),
                                      winnerEmoji:
                                          room.playerEmoji(room.champion),
                                      busy: _actionBusy,
                                      onRematch: () => _runRoomAction(
                                        () => widget.services.game
                                            .startRematch(widget.code),
                                      ),
                                      onShare: () =>
                                          _openVictoryShareSheet(room),
                                    )
                                  else if (room.roundDone)
                                    Column(
                                      children: [
                                        FilledButton.icon(
                                          onPressed: _actionBusy
                                              ? null
                                              : () => _runRoomAction(
                                                    () => widget.services.game
                                                        .startNextRound(
                                                            widget.code),
                                                  ),
                                          icon: const Icon(
                                            Icons.navigate_next_rounded,
                                          ),
                                          label: Text(
                                            'Start Round ${room.round + 1}',
                                          ),
                                        ),
                                        if (room.lastResult == mySide) ...[
                                          const SizedBox(height: 8),
                                          OutlinedButton.icon(
                                            onPressed: () =>
                                                _openVictoryShareSheet(room),
                                            icon:
                                                const Icon(Icons.share_rounded),
                                            label:
                                                const Text('Share Round Win'),
                                          ),
                                        ],
                                      ],
                                    ),
                                ],
                                if (_chatExpanded || room.isLobby) ...[
                                  const SizedBox(height: 14),
                                  RoomChatPanel(
                                    room: room,
                                    currentUid: uid,
                                    services: widget.services,
                                    messagesStream: widget.services.game
                                        .watchMessages(widget.code),
                                  ),
                                ],
                                const MelowFooter(),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (_chatExpanded || room.isLobby)
                        Container(
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            border: Border(
                              top: BorderSide(
                                color:
                                    scheme.outlineVariant.withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                          padding: const EdgeInsets.fromLTRB(8, 8, 10, 12),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 520),
                              child: Row(
                                children: [
                                  IconButton(
                                    tooltip: 'Share photo in chat',
                                    onPressed: _sendingChat
                                        ? null
                                        : _pickAndSendChatImage,
                                    icon: const Icon(Icons.photo_outlined),
                                  ),
                                  Expanded(
                                    child: TextField(
                                      controller: _chatController,
                                      maxLength: 280,
                                      maxLines: 1,
                                      textInputAction: TextInputAction.send,
                                      onSubmitted: (_) => _sendMessage(),
                                      decoration: const InputDecoration(
                                        hintText: 'Type a message…',
                                        counterText: '',
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton.filled(
                                    tooltip: 'Send message',
                                    onPressed:
                                        _sendingChat ? null : _sendMessage,
                                    icon: _sendingChat
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.send_rounded),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Positioned.fill(
                  child: StreamBuilder<List<RoomReaction>>(
                    stream: widget.services.game.watchReactions(widget.code),
                    builder: (context, reactSnap) {
                      final latest = (reactSnap.data?.isNotEmpty ?? false)
                          ? reactSnap.data!.first
                          : null;
                      final sender = latest == null
                          ? ''
                          : latest.senderUid == uid
                              ? 'You'
                              : room.nameForUid(latest.senderUid);
                      return ReactionOverlay(
                        latestReaction: latest,
                        senderLabel: sender,
                        muted: prefs.reactionsMuted,
                        reducedMotion: reducedMotion,
                      );
                    },
                  ),
                ),
                Align(
                  alignment: Alignment.topCenter,
                  child: ConfettiWidget(
                    confettiController: _confettiController,
                    blastDirection: pi / 2,
                    emissionFrequency: 0.06,
                    numberOfParticles: 18,
                    gravity: 0.25,
                    colors: const [
                      AppTheme.purpleAccent,
                      AppTheme.cyanAccent,
                      AppTheme.goldAccent,
                      Colors.pinkAccent,
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ChallengeWheelBanner extends StatelessWidget {
  const _ChallengeWheelBanner({
    required this.room,
    required this.isHost,
    required this.busy,
    required this.onPropose,
    required this.onRespond,
  });

  final GameRoom room;
  final bool isHost;
  final bool busy;
  final VoidCallback onPropose;
  final ValueChanged<bool> onRespond;

  @override
  Widget build(BuildContext context) {
    final proposal = room.wheelProposal;
    final scheme = Theme.of(context).colorScheme;

    if (proposal == null || proposal.status == 'declined') {
      if (!isHost) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Card(
          color: scheme.primaryContainer.withValues(alpha: 0.4),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Text('🎡', style: TextStyle(fontSize: 24)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Random Challenge Wheel',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Propose a surprise mode (both players must accept).',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonal(
                    onPressed: busy ? null : onPropose,
                    child: const Text('Propose Wheel Spin'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (proposal.status == 'pending') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Card(
          color: scheme.tertiaryContainer.withValues(alpha: 0.45),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Text(
                  isHost
                      ? '🎡 Waiting for ${room.guestName} to accept the Challenge Wheel…'
                      : '🎡 ${room.hostName} wants to spin the Challenge Wheel!',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                if (!isHost) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed: busy ? null : () => onRespond(false),
                          child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Decline'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed: busy ? null : () => onRespond(true),
                          child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Accept & Spin!'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

class _LobbyCard extends StatelessWidget {
  const _LobbyCard({
    required this.code,
    required this.hostEmoji,
    required this.size,
    required this.bestOf,
    required this.mode,
    required this.onCopyCode,
  });

  final String code;
  final String hostEmoji;
  final int size;
  final int bestOf;
  final GameMode mode;
  final VoidCallback onCopyCode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            Text(
              'Waiting for your opponent…',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Share this code (${mode.label} • $size×$size • Best of $bestOf).\n'
              'Your friend must pick an emoji other than $hostEmoji.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(18),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SelectableText(
                  code,
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: onCopyCode,
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy Room Code'),
            ),
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.room, required this.myTurn});

  final GameRoom room;
  final bool myTurn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final String text;
    final Color bg;
    final Color fg;

    if (room.isFinished) {
      text = '🏆 Champion: ${room.playerName(room.champion)}!';
      bg = AppTheme.goldAccent.withValues(alpha: 0.25);
      fg = scheme.onSurface;
    } else if (room.roundDone) {
      if (room.timeoutWinner.isNotEmpty) {
        text =
            '⏱️ Time expired! ${room.playerName(room.timeoutWinner)} wins Round ${room.round}!';
      } else if (room.lastResult == 'draw') {
        text = 'Round ${room.round} ended in a draw 🤝';
      } else {
        text =
            '${room.playerEmoji(room.lastResult)} ${room.playerName(room.lastResult)} wins Round ${room.round}!';
      }
      bg = scheme.secondaryContainer;
      fg = scheme.onSecondaryContainer;
    } else {
      text =
          'Round ${room.round} • ${myTurn ? 'Your turn!' : 'Opponent’s turn…'}';
      bg = myTurn ? scheme.primaryContainer : scheme.surfaceContainerHighest;
      fg = myTurn ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }
}

class _ChampionCard extends StatelessWidget {
  const _ChampionCard({
    required this.winnerName,
    required this.winnerEmoji,
    required this.busy,
    required this.onRematch,
    required this.onShare,
  });

  final String winnerName;
  final String winnerEmoji;
  final bool busy;
  final VoidCallback onRematch;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppTheme.goldAccent.withValues(alpha: 0.16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text('🏆', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 6),
            Text(
              '$winnerEmoji $winnerName takes the Melow Cup!',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    onPressed: busy ? null : onRematch,
                    icon: const Icon(Icons.replay_rounded, size: 18),
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Rematch'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    onPressed: onShare,
                    icon: const Icon(Icons.share_rounded, size: 18),
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Share Card'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
