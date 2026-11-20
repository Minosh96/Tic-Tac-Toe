import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/app_services.dart';
import '../../../domain/game_engine.dart';
import '../../../domain/models/social_models.dart';
import '../../../domain/models/user_profile.dart';
import '../../core/widgets/footer.dart';
import '../../core/widgets/melow_avatar.dart';
import '../rivalry/rivalry_screen.dart';
import '../room/room_page.dart';

/// Phase 10 Friends List, Friend Code Search, Requests & Match Challenges.
class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key, required this.services});

  final AppServices services;

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  final TextEditingController _searchCodeController = TextEditingController();
  bool _searching = false;
  UserProfile? _foundUser;

  @override
  void dispose() {
    _searchCodeController.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _searchByCode() async {
    final code = _searchCodeController.text.trim().toUpperCase();
    if (code.length < 6) {
      _snack('Enter a valid friend code.');
      return;
    }
    setState(() {
      _searching = true;
      _foundUser = null;
    });
    try {
      final user = await widget.services.friends.findUserByFriendCode(code);
      if (user == null) {
        _snack('No player found with code $code.');
      }
      if (mounted) setState(() => _foundUser = user);
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _openChallengeDialog(UserProfile me, FriendEntry friend) async {
    GameMode mode = GameMode.classic;
    int boardSize = 3;
    int bestOf = 3;
    bool sending = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Challenge ${friend.nickname}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Mode', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              SegmentedButton<GameMode>(
                segments: const [
                  ButtonSegment(value: GameMode.classic, label: Text('Classic')),
                  ButtonSegment(value: GameMode.blitz, label: Text('Blitz 5s')),
                ],
                selected: {mode},
                onSelectionChanged: (v) =>
                    setDialogState(() => mode = v.first),
              ),
              const SizedBox(height: 12),
              const Text(
                'Board Size',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [
                  for (final n in supportedBoardSizes)
                    ButtonSegment(value: n, label: Text('$n×$n')),
                ],
                selected: {boardSize},
                onSelectionChanged: (v) =>
                    setDialogState(() => boardSize = v.first),
              ),
              const SizedBox(height: 12),
              const Text(
                'Tournament',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [
                  for (final b in supportedBestOf)
                    ButtonSegment(value: b, label: Text('Best of $b')),
                ],
                selected: {bestOf},
                onSelectionChanged: (v) =>
                    setDialogState(() => bestOf = v.first),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: sending
                  ? null
                  : () async {
                      setDialogState(() => sending = true);
                      try {
                        await widget.services.friends.sendFriendChallenge(
                          me: me,
                          friendUid: friend.friendUid,
                          friendName: friend.nickname,
                          mode: mode,
                          boardSize: boardSize,
                          bestOf: bestOf,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        _snack('Challenge sent to ${friend.nickname}!');
                      } catch (e) {
                        _snack(e.toString().replaceFirst('Exception: ', ''));
                      } finally {
                        if (ctx.mounted) setDialogState(() => sending = false);
                      }
                    },
              child: Text(sending ? 'Sending…' : 'Send Challenge'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openReportDialog(FriendEntry friend) async {
    final reasonCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Report ${friend.nickname}'),
        content: TextField(
          controller: reasonCtrl,
          maxLength: 300,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Briefly describe the issue…',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await widget.services.friends.reportUser(
                  reportedUid: friend.friendUid,
                  reason: reasonCtrl.text,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                _snack('Report submitted. Thank you.');
              } catch (e) {
                _snack(e.toString().replaceFirst('Exception: ', ''));
              }
            },
            child: const Text('Submit Report'),
          ),
        ],
      ),
    );
    reasonCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.services.game.currentUid;
    final scheme = Theme.of(context).colorScheme;

    return StreamBuilder<UserProfile?>(
      stream: widget.services.profile.watchProfile(uid),
      builder: (context, meSnap) {
        final me = meSnap.data;
        return Scaffold(
          appBar: AppBar(title: const Text('Friends & Challenges')),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 580),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    // My Friend Code Card
                    if (me != null)
                      Card(
                        child: ListTile(
                          leading: MelowAvatar(avatarId: me.avatarId, size: 42),
                          title: const Text(
                            'Your Shareable Friend Code',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            me.friendCode,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                              color: scheme.primary,
                            ),
                          ),
                          trailing: IconButton.filledTonal(
                            tooltip: 'Copy friend code',
                            icon: const Icon(Icons.copy_rounded),
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: me.friendCode),
                              );
                              _snack('Friend code ${me.friendCode} copied!');
                            },
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    // Search by Friend Code
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Add a Friend by Code',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _searchCodeController,
                                    textCapitalization:
                                        TextCapitalization.characters,
                                    decoration: const InputDecoration(
                                      hintText: 'Enter 8-char friend code',
                                      prefixIcon: Icon(Icons.search_rounded),
                                    ),
                                    onSubmitted: (_) => _searchByCode(),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(86, 52),
                                  ),
                                  onPressed: _searching ? null : _searchByCode,
                                  child: _searching
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text('Find'),
                                ),
                              ],
                            ),
                            if (_foundUser != null && me != null) ...[
                              const SizedBox(height: 12),
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: MelowAvatar(
                                  avatarId: _foundUser!.avatarId,
                                  size: 42,
                                ),
                                title: Text(
                                  _foundUser!.nickname,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                subtitle: Text(
                                  'Favorite mark: ${_foundUser!.preferredEmoji}',
                                ),
                                trailing: FilledButton.tonal(
                                  onPressed: () async {
                                    try {
                                      await widget.services.friends
                                          .sendFriendRequest(
                                        me: me,
                                        target: _foundUser!,
                                      );
                                      _snack(
                                        'Friend request sent to ${_foundUser!.nickname}!',
                                      );
                                      setState(() => _foundUser = null);
                                    } catch (e) {
                                      _snack(
                                        e
                                            .toString()
                                            .replaceFirst('Exception: ', ''),
                                      );
                                    }
                                  },
                                  child: const Text('Add'),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Incoming Match Challenges
                    StreamBuilder<List<FriendChallenge>>(
                      stream:
                          widget.services.friends.watchIncomingChallenges(uid),
                      builder: (context, chalSnap) {
                        final list = chalSnap.data ?? const [];
                        if (list.isEmpty) return const SizedBox.shrink();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '⚔️ Incoming Match Challenges',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 8),
                            for (final c in list)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                      children: [
                                        Row(
                                          children: [
                                            MelowAvatar(
                                              avatarId: c.senderAvatar,
                                              size: 42,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    '${c.senderName} challenged you!',
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                                  ),
                                                  Text(
                                                    '${GameMode.fromId(c.mode).label} • ${c.boardSize}×${c.boardSize} • Best of ${c.bestOf}',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: scheme
                                                          .onSurfaceVariant,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: OutlinedButton(
                                                onPressed: () => widget
                                                    .services.friends
                                                    .declineFriendChallenge(
                                                  c.id,
                                                ),
                                                child: const Text('Decline'),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: FilledButton(
                                                onPressed: me == null
                                                    ? null
                                                    : () async {
                                                        try {
                                                          final roomId =
                                                              await widget
                                                                  .services
                                                                  .friends
                                                                  .acceptFriendChallenge(
                                                            challenge: c,
                                                            me: me,
                                                          );
                                                          if (!context.mounted) {
                                                            return;
                                                          }
                                                          await Navigator.push(
                                                            context,
                                                            MaterialPageRoute(
                                                              builder: (_) =>
                                                                  RoomPage(
                                                                code: roomId,
                                                                services: widget
                                                                    .services,
                                                              ),
                                                            ),
                                                          );
                                                        } catch (e) {
                                                          _snack(
                                                            e
                                                                .toString()
                                                                .replaceFirst(
                                                                  'Exception: ',
                                                                  '',
                                                                ),
                                                          );
                                                        }
                                                      },
                                                child: const Text('Accept'),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 8),
                          ],
                        );
                      },
                    ),
                    // Outgoing Accepted Challenges (Jump directly into room!)
                    StreamBuilder<List<FriendChallenge>>(
                      stream:
                          widget.services.friends.watchOutgoingChallenges(uid),
                      builder: (context, outSnap) {
                        final list = outSnap.data ?? const [];
                        if (list.isEmpty) return const SizedBox.shrink();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Sent Challenges',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 8),
                            for (final c in list)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Card(
                                  child: ListTile(
                                    title: Text(
                                      'To ${c.receiverName}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    subtitle: Text(
                                      c.isAccepted
                                          ? 'Accepted! Tap Join to start.'
                                          : 'Pending • ${c.boardSize}×${c.boardSize}',
                                    ),
                                    trailing: c.isAccepted && c.roomId.isNotEmpty
                                        ? FilledButton(
                                            style: FilledButton.styleFrom(
                                              minimumSize: const Size(80, 40),
                                            ),
                                            onPressed: me == null
                                                ? null
                                                : () async {
                                                    try {
                                                      try {
                                                        await widget
                                                            .services.game
                                                            .joinRoom(
                                                          code: c.roomId,
                                                          name: me.nickname,
                                                          emoji:
                                                              me.preferredEmoji,
                                                          guestAvatar:
                                                              me.avatarId,
                                                        );
                                                      } catch (_) {
                                                        // Already a member if created by Cloud Function.
                                                      }
                                                      if (!context.mounted) {
                                                        return;
                                                      }
                                                      await Navigator.push(
                                                        context,
                                                        MaterialPageRoute(
                                                          builder: (_) =>
                                                              RoomPage(
                                                            code: c.roomId,
                                                            services:
                                                                widget.services,
                                                          ),
                                                        ),
                                                      );
                                                    } catch (e) {
                                                      _snack('$e');
                                                    }
                                                  },
                                            child: const Text('Join'),
                                          )
                                        : TextButton(
                                            onPressed: () => widget
                                                .services.friends
                                                .cancelFriendChallenge(c.id),
                                            child: const Text('Cancel'),
                                          ),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 8),
                          ],
                        );
                      },
                    ),
                    // Incoming Friend Requests
                    StreamBuilder<List<FriendRequest>>(
                      stream:
                          widget.services.friends.watchIncomingRequests(uid),
                      builder: (context, reqSnap) {
                        final requests = reqSnap.data ?? const [];
                        if (requests.isEmpty) return const SizedBox.shrink();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Friend Requests',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 8),
                            for (final req in requests)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Card(
                                  child: ListTile(
                                    leading: MelowAvatar(
                                      avatarId: req.senderAvatar,
                                      size: 42,
                                    ),
                                    title: Text(
                                      req.senderName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    subtitle: const Text('Wants to be friends'),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: 'Decline',
                                          icon: const Icon(Icons.close_rounded),
                                          onPressed: () => widget
                                              .services.friends
                                              .respondFriendRequest(
                                            request: req,
                                            accept: false,
                                          ),
                                        ),
                                        IconButton.filled(
                                          tooltip: 'Accept',
                                          icon: const Icon(Icons.check_rounded),
                                          onPressed: () => widget
                                              .services.friends
                                              .respondFriendRequest(
                                            request: req,
                                            accept: true,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 8),
                          ],
                        );
                      },
                    ),
                    // Friends List
                    const Text(
                      'Your Friends',
                      style:
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    StreamBuilder<List<FriendEntry>>(
                      stream: widget.services.friends.watchFriends(uid),
                      builder: (context, friendsSnap) {
                        if (!friendsSnap.hasData) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: CircularProgressIndicator(),
                            ),
                          );
                        }
                        final friends = friendsSnap.data!;
                        if (friends.isEmpty) {
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                children: [
                                  const Text('👋', style: TextStyle(fontSize: 40)),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'No friends added yet',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Share your friend code above or search for a friend’s code to start rivalries!',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                        return Column(
                          children: [
                            for (final f in friends)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Card(
                                  child: ListTile(
                                    leading: MelowAvatar(
                                      avatarId: f.avatarId,
                                      size: 44,
                                    ),
                                    title: Text(
                                      f.nickname,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    subtitle: const Text(
                                      'Tap to view head-to-head rivalry',
                                    ),
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => RivalryScreen(
                                          services: widget.services,
                                          opponentUid: f.friendUid,
                                          opponentName: f.nickname,
                                          opponentAvatar: f.avatarId,
                                        ),
                                      ),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton.filledTonal(
                                          tooltip: 'Challenge friend',
                                          icon: const Icon(
                                            Icons.sports_esports_rounded,
                                          ),
                                          onPressed: me == null
                                              ? null
                                              : () =>
                                                  _openChallengeDialog(me, f),
                                        ),
                                        PopupMenuButton<String>(
                                          onSelected: (action) async {
                                            if (action == 'rivalry') {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) => RivalryScreen(
                                                    services: widget.services,
                                                    opponentUid: f.friendUid,
                                                    opponentName: f.nickname,
                                                    opponentAvatar: f.avatarId,
                                                  ),
                                                ),
                                              );
                                            } else if (action == 'remove') {
                                              await widget.services.friends
                                                  .removeFriend(f.friendUid);
                                              _snack(
                                                'Removed ${f.nickname} from friends.',
                                              );
                                            } else if (action == 'block') {
                                              await widget.services.friends
                                                  .blockUser(f.friendUid);
                                              _snack('Blocked ${f.nickname}.');
                                            } else if (action == 'report') {
                                              await _openReportDialog(f);
                                            }
                                          },
                                          itemBuilder: (_) => const [
                                            PopupMenuItem(
                                              value: 'rivalry',
                                              child: Text('View Rivalry'),
                                            ),
                                            PopupMenuItem(
                                              value: 'remove',
                                              child: Text('Remove Friend'),
                                            ),
                                            PopupMenuItem(
                                              value: 'block',
                                              child: Text('Block Player'),
                                            ),
                                            PopupMenuItem(
                                              value: 'report',
                                              child: Text('Report Player'),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    const MelowFooter(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
