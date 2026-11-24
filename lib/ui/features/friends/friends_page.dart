import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/app_services.dart';
import '../../../domain/game_engine.dart';
import '../../../domain/models/group_models.dart';
import '../../../domain/models/social_models.dart';
import '../../../domain/models/user_profile.dart';
import '../../core/app_theme.dart';
import '../../core/widgets/footer.dart';
import '../../core/widgets/live_user_avatar.dart';
import '../../core/widgets/melow_avatar.dart';
import '../../core/widgets/notification_bell_button.dart';
import '../chat/friend_chat_screen.dart';
import '../chat/voice_call_screen.dart';
import '../groups/group_detail_screen.dart';
import '../rivalry/rivalry_screen.dart';
import '../room/room_page.dart';

/// Melow v3.0 Friends List, Friend Chat, Voice Call, Requests & Match Challenges.
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

  Future<void> _openCreateGroupDialog(UserProfile me) async {
    final nameCtrl = TextEditingController();
    int maxMembers = 5;
    bool creating = false;
    String? errorMsg;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final scheme = Theme.of(ctx).colorScheme;
          return AlertDialog(
            title: const Text('Create Group with My Code'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Create a group using your Friend Code (${me.friendCode}). Share your code with friends so up to $maxMembers members can enter it, join the group, and play for the Melow Challenge Champion Cup 🏆!',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.vpn_key_rounded, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Group Code: ${me.friendCode}',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: scheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    maxLength: 24,
                    decoration: const InputDecoration(
                      labelText: 'Group Name',
                      hintText: 'Melow Champions Squad',
                      prefixIcon: Icon(Icons.groups_rounded),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Maximum Number of Members (2–5)',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final count in const [2, 3, 4, 5])
                        ChoiceChip(
                          label: Text('$count Players'),
                          selected: maxMembers == count,
                          onSelected: (_) =>
                              setDialogState(() => maxMembers = count),
                        ),
                    ],
                  ),
                  if (errorMsg != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      errorMsg!,
                      style: TextStyle(
                        color: scheme.error,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: creating ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: creating
                    ? null
                    : () async {
                        setDialogState(() {
                          creating = true;
                          errorMsg = null;
                        });
                        try {
                          final groupId = await widget.services.groups
                              .createGroupWithMyFriendCode(
                            creator: me,
                            groupName: nameCtrl.text,
                            maxMembers: maxMembers,
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (!mounted) return;
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => GroupDetailScreen(
                                services: widget.services,
                                groupId: groupId,
                              ),
                            ),
                          );
                        } catch (e) {
                          if (ctx.mounted) {
                            setDialogState(() {
                              creating = false;
                              errorMsg = e
                                  .toString()
                                  .replaceFirst('Exception: ', '');
                            });
                          }
                        }
                      },
                icon: const Icon(Icons.group_add_rounded),
                label: Text(creating ? 'Creating…' : 'Create Group'),
              ),
            ],
          );
        },
      ),
    );
    nameCtrl.dispose();
  }

  Future<void> _openJoinGroupByCodeDialog(UserProfile me) async {
    final codeCtrl = TextEditingController();
    bool joining = false;
    String? errorMsg;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final scheme = Theme.of(ctx).colorScheme;
          return AlertDialog(
            title: const Text('Join Friend Group by Code'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Enter the Friend Code shared by the group creator to join their group and compete for the Melow Challenge Champion Cup 🏆!',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: codeCtrl,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 10,
                    decoration: const InputDecoration(
                      labelText: 'Host Friend Code',
                      hintText: '8-character code',
                      prefixIcon: Icon(Icons.vpn_key_rounded),
                    ),
                  ),
                  if (errorMsg != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      errorMsg!,
                      style: TextStyle(
                        color: scheme.error,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: joining ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: joining
                    ? null
                    : () async {
                        setDialogState(() {
                          joining = true;
                          errorMsg = null;
                        });
                        try {
                          final group = await widget.services.groups
                              .joinGroupByFriendCode(
                            me: me,
                            friendCode: codeCtrl.text,
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (!mounted) return;
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => GroupDetailScreen(
                                services: widget.services,
                                groupId: group.id,
                              ),
                            ),
                          );
                        } catch (e) {
                          if (ctx.mounted) {
                            setDialogState(() {
                              joining = false;
                              errorMsg = e
                                  .toString()
                                  .replaceFirst('Exception: ', '');
                            });
                          }
                        }
                      },
                icon: const Icon(Icons.login_rounded),
                label: Text(joining ? 'Joining…' : 'Join Group'),
              ),
            ],
          );
        },
      ),
    );
    codeCtrl.dispose();
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
          title: Text(
            'Challenge ${friend.nickname}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Mode',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      label: const Text('Classic'),
                      selected: mode == GameMode.classic,
                      onSelected: (_) =>
                          setDialogState(() => mode = GameMode.classic),
                    ),
                    ChoiceChip(
                      label: const Text('Blitz (5s)'),
                      selected: mode == GameMode.blitz,
                      onSelected: (_) =>
                          setDialogState(() => mode = GameMode.blitz),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Board Size',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final n in supportedBoardSizes)
                      ChoiceChip(
                        label: Text('$n×$n'),
                        selected: boardSize == n,
                        onSelected: (_) =>
                            setDialogState(() => boardSize = n),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Tournament',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final b in supportedBestOf)
                      ChoiceChip(
                        label: Text('Best of $b'),
                        selected: bestOf == b,
                        onSelected: (_) => setDialogState(() => bestOf = b),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(120, 44),
              ),
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
              child: Text(sending ? 'Sending…' : 'Send'),
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
            style: FilledButton.styleFrom(minimumSize: const Size(110, 44)),
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
            child: const Text('Submit'),
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
          appBar: AppBar(
            title: const Text('Friends & Chat'),
            actions: [
              NotificationBellIconButton(
                services: widget.services,
                me: me,
              ),
            ],
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 580),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    if (me != null)
                      Card(
                        child: ListTile(
                          leading: MelowAvatar(
                            avatarId: me.avatarId,
                            photoBase64: me.photoBase64,
                            size: 42,
                          ),
                          title: const Text(
                            'Your Shareable Friend Code',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: FittedBox(
                            alignment: Alignment.centerLeft,
                            fit: BoxFit.scaleDown,
                            child: Text(
                              me.friendCode,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2,
                                color: scheme.primary,
                              ),
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
                                      hintText: '8-char friend code',
                                      prefixIcon: Icon(Icons.search_rounded),
                                    ),
                                    onSubmitted: (_) => _searchByCode(),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(76, 52),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                    ),
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
                                  photoBase64: _foundUser!.photoBase64,
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
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(72, 40),
                                  ),
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
                    // Unified "Create Group" Card with Join Group & Create New Group buttons + description
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Text('🏟️', style: TextStyle(fontSize: 24)),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Create Group (Tournament & Chat)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Create a group (2–5 players) using your Friend Code or enter a friend’s code to join their group tournament, play fixtures, and chat!',
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: me == null
                                        ? null
                                        : () => _openJoinGroupByCodeDialog(me),
                                    icon: const Icon(
                                      Icons.vpn_key_rounded,
                                      size: 18,
                                    ),
                                    label: const FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text('Join Group'),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: me == null
                                        ? null
                                        : () => _openCreateGroupDialog(me),
                                    icon: const Icon(
                                      Icons.group_add_rounded,
                                      size: 18,
                                    ),
                                    label: const FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text('Create New Group'),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    StreamBuilder<List<FriendGroup>>(
                      stream: widget.services.groups.watchUserGroups(uid),
                      builder: (context, groupSnap) {
                        final groups = groupSnap.data ?? const [];
                        if (groups.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return Column(
                          children: [
                            for (final g in groups)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Card(
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: AppTheme.purpleAccent
                                          .withValues(alpha: 0.18),
                                      child: const Text('🏆'),
                                    ),
                                    title: Text(
                                      '${g.name} (Code: ${g.hostFriendCode})',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    subtitle: Text(
                                      g.tournamentStatus == 'completed' &&
                                              g.championName.isNotEmpty
                                          ? 'Champion: ${g.championName} 🏆 • ${g.memberUids.length}/${g.maxMembers} Members'
                                          : '${g.memberUids.length}/${g.maxMembers} Members • ${g.fixtures.length} Fixtures',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: const Icon(
                                      Icons.chevron_right_rounded,
                                    ),
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => GroupDetailScreen(
                                          services: widget.services,
                                          groupId: g.id,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
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
                    // Outgoing Sent Challenges (with per-item Remove & Clear All)
                    StreamBuilder<List<FriendChallenge>>(
                      stream:
                          widget.services.friends.watchOutgoingChallenges(uid),
                      builder: (context, outSnap) {
                        final list = outSnap.data ?? const [];
                        if (list.isEmpty) return const SizedBox.shrink();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'Sent Challenges',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                                if (list.length > 1)
                                  TextButton.icon(
                                    onPressed: () async {
                                      try {
                                        await widget.services.friends
                                            .clearAllSentChallenges(
                                          list.map((c) => c.id).toList(),
                                        );
                                        _snack('Cleared all sent challenges.');
                                      } catch (e) {
                                        _snack('$e');
                                      }
                                    },
                                    icon: const Icon(
                                      Icons.delete_sweep_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('Clear All'),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
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
                                          ? 'Accepted! Tap Join or remove.'
                                          : 'Pending • ${c.boardSize}×${c.boardSize} • BO${c.bestOf}',
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (c.isAccepted && c.roomId.isNotEmpty)
                                          FilledButton(
                                            style: FilledButton.styleFrom(
                                              minimumSize: const Size(64, 38),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 12,
                                              ),
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
                                                      } catch (_) {}
                                                      await widget
                                                          .services.friends
                                                          .removeSentChallenge(
                                                              c.id);
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
                                          ),
                                        IconButton(
                                          tooltip: 'Remove challenge',
                                          icon: const Icon(
                                            Icons.delete_outline_rounded,
                                          ),
                                          onPressed: () async {
                                            try {
                                              await widget.services.friends
                                                  .removeSentChallenge(c.id);
                                              _snack('Challenge removed.');
                                            } catch (e) {
                                              _snack('$e');
                                            }
                                          },
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
                    // Friends List with Chat, Voice Call & Challenge
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
                                  const Text('👋',
                                      style: TextStyle(fontSize: 40)),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'No friends added yet',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Share your friend code above or search for a friend’s code to chat, voice call, and play!',
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
                        return StreamBuilder<Map<String, DirectChatSummary>>(
                          stream: widget.services.chat.watchChatsByFriend(uid),
                          builder: (context, chatMapSnap) {
                            final chatsByFriend = chatMapSnap.data ?? const {};
                            return Column(
                              children: [
                                for (final f in friends)
                                  LiveUserProfileBuilder(
                                    services: widget.services,
                                    uid: f.friendUid,
                                    builder: (context, liveProfile) {
                                      final liveName =
                                          (liveProfile?.nickname.isNotEmpty ??
                                                  false)
                                              ? liveProfile!.nickname
                                              : f.nickname;
                                      final liveAvatarId =
                                          liveProfile?.avatarId ?? f.avatarId;
                                      final livePhoto =
                                          (liveProfile?.photoBase64 != null &&
                                                  liveProfile!
                                                      .photoBase64!.isNotEmpty)
                                              ? liveProfile.photoBase64
                                              : f.photoBase64;
                                      final liveFriend = FriendEntry(
                                        friendUid: f.friendUid,
                                        nickname: liveName,
                                        avatarId: liveAvatarId,
                                        photoBase64: livePhoto,
                                        status: f.status,
                                        since: f.since,
                                      );
                                      final chatSummary =
                                          chatsByFriend[f.friendUid];
                                      final unread =
                                          chatSummary?.unreadCountFor(uid) ?? 0;
                                      final visibleLast = chatSummary
                                              ?.visibleLastMessageFor(uid) ??
                                          '';
                                      final previewText = visibleLast.isNotEmpty
                                          ? visibleLast
                                          : 'Chat, call, or start a rivalry';
                                      return Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 10),
                                        child: Card(
                                          child: Padding(
                                            padding: const EdgeInsets.all(12),
                                            child: Column(
                                              children: [
                                                Row(
                                                  children: [
                                                    Badge(
                                                      isLabelVisible:
                                                          unread > 0,
                                                      label: Text(
                                                        unread > 99
                                                            ? '99+'
                                                            : '$unread',
                                                      ),
                                                      child: LiveUserAvatar(
                                                        services:
                                                            widget.services,
                                                        uid: f.friendUid,
                                                        fallbackAvatarId:
                                                            liveAvatarId,
                                                        fallbackPhotoBase64:
                                                            livePhoto,
                                                        size: 46,
                                                        enableFullScreenPreview:
                                                            true,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                            liveName,
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style:
                                                                const TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w800,
                                                              fontSize: 15,
                                                            ),
                                                          ),
                                                          Text(
                                                            previewText,
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              fontWeight: unread >
                                                                      0
                                                                  ? FontWeight
                                                                      .w800
                                                                  : FontWeight
                                                                      .normal,
                                                              color: unread > 0
                                                                  ? scheme
                                                                      .primary
                                                                  : scheme
                                                                      .onSurfaceVariant,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    PopupMenuButton<String>(
                                                      onSelected:
                                                          (action) async {
                                                        if (action ==
                                                            'rivalry') {
                                                          Navigator.push(
                                                            context,
                                                            MaterialPageRoute(
                                                              builder: (_) =>
                                                                  RivalryScreen(
                                                                services: widget
                                                                    .services,
                                                                opponentUid: f
                                                                    .friendUid,
                                                                opponentName:
                                                                    liveName,
                                                                opponentAvatar:
                                                                    liveAvatarId,
                                                              ),
                                                            ),
                                                          );
                                                        } else if (action ==
                                                            'clear_chat') {
                                                          final chatId = widget
                                                              .services.chat
                                                              .chatIdFor(
                                                            uid,
                                                            f.friendUid,
                                                          );
                                                          final choice =
                                                              await showDialog<
                                                                  String>(
                                                            context: context,
                                                            builder: (ctx) =>
                                                                AlertDialog(
                                                              title: Text(
                                                                'Clear Chat with $liveName',
                                                              ),
                                                              content:
                                                                  const Text(
                                                                'Choose whether to clear this chat only for yourself or for everyone.',
                                                              ),
                                                              actions: [
                                                                TextButton(
                                                                  onPressed: () =>
                                                                      Navigator.pop(
                                                                          ctx),
                                                                  child: const Text(
                                                                      'Cancel'),
                                                                ),
                                                                FilledButton
                                                                    .tonal(
                                                                  onPressed: () =>
                                                                      Navigator.pop(
                                                                          ctx,
                                                                          'me'),
                                                                  child: const Text(
                                                                      'Clear for Me'),
                                                                ),
                                                                FilledButton(
                                                                  style: FilledButton
                                                                      .styleFrom(
                                                                    backgroundColor:
                                                                        scheme
                                                                            .error,
                                                                    foregroundColor:
                                                                        scheme
                                                                            .onError,
                                                                  ),
                                                                  onPressed: () =>
                                                                      Navigator.pop(
                                                                          ctx,
                                                                          'everyone'),
                                                                  child: const Text(
                                                                      'Clear for Everyone'),
                                                                ),
                                                              ],
                                                            ),
                                                          );
                                                          if (choice == 'me') {
                                                            await widget
                                                                .services.chat
                                                                .clearChatForMe(
                                                                    chatId);
                                                            _snack(
                                                              'Cleared chat with $liveName for you.',
                                                            );
                                                          } else if (choice ==
                                                              'everyone') {
                                                            await widget
                                                                .services.chat
                                                                .clearChatForEveryone(
                                                                    chatId);
                                                            _snack(
                                                              'Cleared chat with $liveName for everyone.',
                                                            );
                                                          }
                                                        } else if (action ==
                                                            'remove') {
                                                          await widget
                                                              .services.friends
                                                              .removeFriend(
                                                                  f.friendUid);
                                                          _snack(
                                                            'Removed $liveName.',
                                                          );
                                                        } else if (action ==
                                                            'block') {
                                                          await widget
                                                              .services.friends
                                                              .blockUser(
                                                            f.friendUid,
                                                            nickname: liveName,
                                                            avatarId:
                                                                liveAvatarId,
                                                          );
                                                          _snack(
                                                            'Blocked $liveName.',
                                                          );
                                                        } else if (action ==
                                                            'report') {
                                                          await _openReportDialog(
                                                            liveFriend,
                                                          );
                                                        }
                                                      },
                                                      itemBuilder: (_) =>
                                                          const [
                                                        PopupMenuItem(
                                                          value: 'rivalry',
                                                          child: Text(
                                                              'View Rivalry'),
                                                        ),
                                                        PopupMenuItem(
                                                          value: 'clear_chat',
                                                          child: Text(
                                                              'Clear Chat'),
                                                        ),
                                                        PopupMenuItem(
                                                          value: 'remove',
                                                          child: Text(
                                                              'Remove Friend'),
                                                        ),
                                                        PopupMenuItem(
                                                          value: 'block',
                                                          child: Text(
                                                              'Block Player'),
                                                        ),
                                                        PopupMenuItem(
                                                          value: 'report',
                                                          child: Text(
                                                              'Report Player'),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 10),
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: OutlinedButton.icon(
                                                        style: OutlinedButton
                                                            .styleFrom(
                                                          minimumSize:
                                                              const Size
                                                                  .fromHeight(
                                                                  42),
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal:
                                                                      8),
                                                        ),
                                                        onPressed: () =>
                                                            Navigator.push(
                                                          context,
                                                          MaterialPageRoute(
                                                            builder: (_) =>
                                                                FriendChatScreen(
                                                              services: widget
                                                                  .services,
                                                              friendUid:
                                                                  f.friendUid,
                                                              friendName:
                                                                  liveName,
                                                              friendAvatar:
                                                                  liveAvatarId,
                                                              friendPhotoBase64:
                                                                  livePhoto,
                                                            ),
                                                          ),
                                                        ),
                                                        icon: const Icon(
                                                          Icons.chat_rounded,
                                                          size: 16,
                                                        ),
                                                        label: FittedBox(
                                                          fit: BoxFit.scaleDown,
                                                          child: Text(
                                                            unread > 0
                                                                ? 'Chat ($unread)'
                                                                : 'Chat',
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: OutlinedButton.icon(
                                                        style: OutlinedButton
                                                            .styleFrom(
                                                          minimumSize:
                                                              const Size
                                                                  .fromHeight(
                                                                  42),
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal:
                                                                      8),
                                                        ),
                                                        onPressed: me == null
                                                            ? null
                                                            : () =>
                                                                Navigator.push(
                                                                  context,
                                                                  MaterialPageRoute(
                                                                    builder: (_) =>
                                                                        VoiceCallScreen
                                                                            .outgoing(
                                                                      services:
                                                                          widget
                                                                              .services,
                                                                      calleeUid:
                                                                          f.friendUid,
                                                                      calleeName:
                                                                          liveName,
                                                                      calleeAvatar:
                                                                          liveAvatarId,
                                                                      callerName:
                                                                          me.nickname,
                                                                      callerAvatar:
                                                                          me.avatarId,
                                                                    ),
                                                                  ),
                                                                ),
                                                        icon: const Icon(
                                                          Icons.call_rounded,
                                                          size: 16,
                                                        ),
                                                        label: const FittedBox(
                                                          fit: BoxFit.scaleDown,
                                                          child: Text('Call'),
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: FilledButton.icon(
                                                        style: FilledButton
                                                            .styleFrom(
                                                          minimumSize:
                                                              const Size
                                                                  .fromHeight(
                                                                  42),
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal:
                                                                      8),
                                                        ),
                                                        onPressed: me == null
                                                            ? null
                                                            : () =>
                                                                _openChallengeDialog(
                                                                    me,
                                                                    liveFriend),
                                                        icon: const Icon(
                                                          Icons
                                                              .sports_esports_rounded,
                                                          size: 16,
                                                        ),
                                                        label: const FittedBox(
                                                          fit: BoxFit.scaleDown,
                                                          child: Text('Play'),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                    // Blocked Players Section with Unblock Action
                    StreamBuilder<List<BlockedUserEntry>>(
                      stream:
                          widget.services.friends.watchBlockedUsers(uid),
                      builder: (context, blockedSnap) {
                        final blockedList = blockedSnap.data ?? const [];
                        if (blockedList.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Icon(
                                  Icons.block_rounded,
                                  size: 18,
                                  color: scheme.error,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Blocked Players (${blockedList.length})',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            for (final b in blockedList)
                              LiveUserProfileBuilder(
                                services: widget.services,
                                uid: b.blockedUid,
                                builder: (context, liveProfile) {
                                  final liveName =
                                      (liveProfile?.nickname.isNotEmpty ??
                                              false)
                                          ? liveProfile!.nickname
                                          : b.nickname;
                                  final liveAvatar =
                                      liveProfile?.avatarId ?? b.avatarId;
                                  final livePhoto = liveProfile?.photoBase64;
                                  return Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 8),
                                    child: Card(
                                      child: ListTile(
                                        leading: LiveUserAvatar(
                                          services: widget.services,
                                          uid: b.blockedUid,
                                          fallbackAvatarId: liveAvatar,
                                          fallbackPhotoBase64: livePhoto,
                                          size: 42,
                                        ),
                                        title: Text(
                                          liveName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        subtitle: const Text(
                                          'Blocked • Tap Unblock to restore friend',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                        trailing: FilledButton.tonalIcon(
                                          style: FilledButton.styleFrom(
                                            minimumSize:
                                                const Size(100, 38),
                                            padding:
                                                const EdgeInsets.symmetric(
                                              horizontal: 12,
                                            ),
                                          ),
                                          onPressed: () async {
                                            try {
                                              await widget.services.friends
                                                  .unblockUser(
                                                b.blockedUid,
                                                nickname: liveName,
                                                avatarId: liveAvatar,
                                              );
                                              _snack(
                                                'Unblocked $liveName!',
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
                                          icon: const Icon(
                                            Icons.lock_open_rounded,
                                            size: 16,
                                          ),
                                          label: const Text('Unblock'),
                                        ),
                                      ),
                                    ),
                                  );
                                },
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
