import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/repositories/game_repository.dart';
import '../../../domain/models/game_room.dart';
import '../../core/widgets/footer.dart';
import 'widgets/game_board.dart';
import 'widgets/room_chat_panel.dart';
import 'widgets/scoreboard_card.dart';

/// Live multiplayer room displaying lobby invite, board, trophy, and chat.
class RoomPage extends StatefulWidget {
  const RoomPage({
    super.key,
    required this.code,
    required this.repository,
  });

  final String code;
  final GameRepository repository;

  @override
  State<RoomPage> createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> {
  final TextEditingController _chatController = TextEditingController();
  bool _sendingChat = false;
  bool _actionBusy = false;

  @override
  void dispose() {
    _chatController.dispose();
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
    _notice('Room code ${widget.code} copied to clipboard');
  }

  Future<void> _sendMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty || _sendingChat) return;
    setState(() => _sendingChat = true);
    try {
      await widget.repository.sendChatMessage(widget.code, text);
      _chatController.clear();
    } catch (e) {
      _notice('Chat failed: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _sendingChat = false);
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

  @override
  Widget build(BuildContext context) {
    final uid = widget.repository.currentUid;
    final scheme = Theme.of(context).colorScheme;

    return StreamBuilder<GameRoom?>(
      stream: widget.repository.watchRoom(widget.code),
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

        final myTurn = room.turn == mySide;
        final winResult = room.winResult;

        return Scaffold(
          appBar: AppBar(
            title: Text(
              'Room ${widget.code}',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.copy_rounded),
                tooltip: 'Copy room code',
                onPressed: _copyCode,
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        children: [
                          ScoreboardCard(room: room, currentUid: uid),
                          const SizedBox(height: 12),
                          if (room.isLobby)
                            _LobbyCard(
                              code: widget.code,
                              hostEmoji: room.hostEmoji,
                              size: room.size,
                              bestOf: room.bestOf,
                              onCopyCode: _copyCode,
                            )
                          else ...[
                            _StatusBanner(room: room, myTurn: myTurn),
                            const SizedBox(height: 12),
                            GameBoard(
                              size: room.size,
                              board: room.board,
                              emojiForSide: room.playerEmoji,
                              canPlay: room.isPlaying && !room.roundDone && myTurn,
                              winningLine: winResult?.line ?? const [],
                              onCellTap: (index) => _runRoomAction(
                                () => widget.repository.playMove(widget.code, index),
                              ),
                            ),
                            const SizedBox(height: 14),
                            if (room.isFinished)
                              _ChampionCard(
                                winnerName: room.playerName(room.champion),
                                winnerEmoji: room.playerEmoji(room.champion),
                                busy: _actionBusy,
                                onRematch: () => _runRoomAction(
                                  () => widget.repository.startRematch(widget.code),
                                ),
                              )
                            else if (room.roundDone)
                              FilledButton.icon(
                                onPressed: _actionBusy
                                    ? null
                                    : () => _runRoomAction(
                                          () => widget.repository
                                              .startNextRound(widget.code),
                                        ),
                                icon: const Icon(Icons.navigate_next_rounded),
                                label: Text('Start Round ${room.round + 1}'),
                              ),
                          ],
                          const SizedBox(height: 16),
                          RoomChatPanel(
                            room: room,
                            currentUid: uid,
                            messagesStream:
                                widget.repository.watchMessages(widget.code),
                          ),
                          const MelowFooter(),
                        ],
                      ),
                    ),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    border: Border(
                      top: BorderSide(
                        color: scheme.outlineVariant.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Row(
                        children: [
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
                            onPressed: _sendingChat ? null : _sendMessage,
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
        );
      },
    );
  }
}

class _LobbyCard extends StatelessWidget {
  const _LobbyCard({
    required this.code,
    required this.hostEmoji,
    required this.size,
    required this.bestOf,
    required this.onCopyCode,
  });

  final String code;
  final String hostEmoji;
  final int size;
  final int bestOf;
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
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Share this code with a friend ($size×$size • Best of $bestOf).\n'
              'They must choose an emoji other than $hostEmoji.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
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
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: onCopyCode,
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy Room Code'),
            ),
            const SizedBox(height: 18),
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
      bg = scheme.tertiaryContainer;
      fg = scheme.onTertiaryContainer;
    } else if (room.roundDone) {
      text = room.lastResult == 'draw'
          ? 'Round ${room.round} ended in a draw 🤝'
          : '${room.playerEmoji(room.lastResult)} ${room.playerName(room.lastResult)} wins Round ${room.round}!';
      bg = scheme.secondaryContainer;
      fg = scheme.onSecondaryContainer;
    } else {
      text = 'Round ${room.round} • ${myTurn ? 'Your turn!' : 'Opponent’s turn…'}';
      bg = myTurn ? scheme.primaryContainer : scheme.surfaceContainerHighest;
      fg = myTurn ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
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
  });

  final String winnerName;
  final String winnerEmoji;
  final bool busy;
  final VoidCallback onRematch;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.tertiaryContainer.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text('🏆', style: TextStyle(fontSize: 68)),
            const SizedBox(height: 6),
            Text(
              '$winnerEmoji $winnerName takes the Melow Cup!',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: busy ? null : onRematch,
              icon: const Icon(Icons.replay_rounded),
              label: const Text('Play Rematch'),
            ),
          ],
        ),
      ),
    );
  }
}
