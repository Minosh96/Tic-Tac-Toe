import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/services/app_services.dart';
import '../../../core/services/image_helper.dart';
import '../../../domain/game_engine.dart';
import '../../../domain/models/group_models.dart';
import '../../../domain/models/social_models.dart';
import '../../../domain/models/user_profile.dart';
import '../../core/app_theme.dart';
import '../../core/widgets/live_user_avatar.dart';
import '../chat/voice_call_screen.dart';
import '../room/room_page.dart';

/// Friend Group (up to 5 members) screen with 2 tabs:
/// 1. Tournament & Rankings:
///    - Any member can initiate a 2-player challenge or start the Final Match for the
///      Melow Challenge Champion Cup 🏆.
///    - Live Group Individual Rankings table (`Played • Won • Lost • Draw • Cups`).
///    - When the Final Match finishes, displays the Champion Banner + options to
///      "Keep Group & New Season" or "Remove Group".
///    - Add Member by Friend Code (up to 5 members) + "Leave Group".
/// 2. Group Chat & Calls:
///    - Full chat with Gallery/Camera photo sharing, Clear for Me / Clear for Everyone,
///      Single-message Delete for Me / Unsend for Everyone, and Group Member Voice Calls.
class GroupDetailScreen extends StatefulWidget {
  const GroupDetailScreen({
    super.key,
    required this.services,
    required this.groupId,
  });

  final AppServices services;
  final String groupId;

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  final TextEditingController _chatCtrl = TextEditingController();
  bool _sendingChat = false;

  @override
  void dispose() {
    _chatCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openAddMemberDialog(FriendGroup group) async {
    final codeCtrl = TextEditingController();
    bool adding = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Member by Friend Code'),
          content: TextField(
            controller: codeCtrl,
            textCapitalization: TextCapitalization.characters,
            maxLength: 10,
            decoration: const InputDecoration(
              labelText: '8-character Friend Code',
              prefixIcon: Icon(Icons.person_add_alt_1_rounded),
            ),
          ),
          actions: [
            TextButton(
              onPressed: adding ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: adding
                  ? null
                  : () async {
                      setDialogState(() => adding = true);
                      try {
                        final added = await widget.services.groups
                            .addMemberByFriendCode(
                          groupId: group.id,
                          friendCode: codeCtrl.text,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        _snack('Added ${added.nickname} to ${group.name}!');
                      } catch (e) {
                        _snack(e.toString().replaceFirst('Exception: ', ''));
                        if (ctx.mounted) setDialogState(() => adding = false);
                      }
                    },
              child: Text(adding ? 'Adding…' : 'Add Member'),
            ),
          ],
        ),
      ),
    );
    codeCtrl.dispose();
  }

  Future<void> _openInitiateGroupMatchDialog({
    required FriendGroup group,
    required UserProfile me,
    required bool isFinalMatch,
  }) async {
    final standings = group.rankings;
    final otherUids =
        group.memberUids.where((u) => u != me.uid).toList(growable: false);
    if (otherUids.isEmpty) {
      _snack('Need at least 2 members in the group to start a match.');
      return;
    }

    String selectedOpponentUid = otherUids.first;
    if (isFinalMatch && standings.length >= 2) {
      final topTwo = [standings[0].uid, standings[1].uid];
      final otherTop = topTwo.firstWhere(
        (u) => u != me.uid,
        orElse: () => otherUids.first,
      );
      selectedOpponentUid = otherTop;
    }

    GameMode mode = GameMode.classic;
    int boardSize = 3;
    int bestOf = 3;
    bool busy = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            isFinalMatch
                ? '🏆 Start Group Final Match'
                : '⚔️ Initiate Group Match (2 Players)',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isFinalMatch)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      'Winner of this Final Match wins the ${group.cupName} 🏆!',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppTheme.goldAccent,
                        fontSize: 13,
                      ),
                    ),
                  ),
                const Text(
                  'Choose Opponent in Group',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final uid in otherUids)
                      ChoiceChip(
                        label: Text(group.memberNames[uid] ?? 'Member'),
                        selected: selectedOpponentUid == uid,
                        onSelected: (_) =>
                            setDialogState(() => selectedOpponentUid = uid),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Mode',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
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
                  children: [
                    for (final s in supportedBoardSizes)
                      ChoiceChip(
                        label: Text('$s×$s'),
                        selected: boardSize == s,
                        onSelected: (_) => setDialogState(() => boardSize = s),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Best Of',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
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
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      setDialogState(() => busy = true);
                      try {
                        final roomCode = await widget.services.groups
                            .initiateGroupMatch(
                          group: group,
                          initiator: me,
                          opponentUid: selectedOpponentUid,
                          mode: mode,
                          boardSize: boardSize,
                          bestOf: bestOf,
                          isFinalMatch: isFinalMatch,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        await _openAndSyncGroupRoom(
                          group: group,
                          roomCode: roomCode,
                          isFinalMatch: isFinalMatch,
                        );
                      } catch (e) {
                        _snack(e.toString().replaceFirst('Exception: ', ''));
                        if (ctx.mounted) setDialogState(() => busy = false);
                      }
                    },
              icon: const Icon(Icons.sports_esports_rounded),
              label: Text(
                busy
                    ? 'Creating…'
                    : (isFinalMatch ? 'Start Final' : 'Start Match'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAndSyncGroupRoom({
    required FriendGroup group,
    required String roomCode,
    required bool isFinalMatch,
    UserProfile? joinAsGuest,
  }) async {
    if (joinAsGuest != null) {
      try {
        await widget.services.game.joinRoom(
          code: roomCode,
          name: joinAsGuest.nickname,
          emoji: joinAsGuest.preferredEmoji,
          guestAvatar: joinAsGuest.avatarId,
        );
      } catch (_) {}
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RoomPage(
          code: roomCode,
          services: widget.services,
        ),
      ),
    );
    // When returning from RoomPage, sync the completed match result to Group Rankings!
    try {
      final roomSnap = await widget.services.game.watchRoom(roomCode).first;
      if (roomSnap != null && roomSnap.isFinished) {
        await widget.services.groups.syncGroupMatchResult(
          groupId: group.id,
          room: roomSnap,
          isFinalMatch: isFinalMatch,
        );
      }
    } catch (_) {}
  }

  void _openGroupCallPicker(FriendGroup group, UserProfile me) {
    final others =
        group.memberUids.where((u) => u != me.uid).toList(growable: false);
    if (others.isEmpty) {
      _snack('No other group members to call.');
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '📞 Group Voice Call — Select Member',
                style: Theme.of(ctx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              for (final uid in others)
                ListTile(
                  leading: LiveUserAvatar(
                    services: widget.services,
                    uid: uid,
                    fallbackAvatarId: group.memberAvatars[uid] ?? 'fox',
                    size: 40,
                  ),
                  title: Text(
                    group.memberNames[uid] ?? 'Group Member',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  trailing: FilledButton.tonalIcon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => VoiceCallScreen.outgoing(
                            services: widget.services,
                            calleeUid: uid,
                            calleeName:
                                group.memberNames[uid] ?? 'Group Member',
                            calleeAvatar: group.memberAvatars[uid] ?? 'fox',
                            callerName: me.nickname,
                            callerAvatar: me.avatarId,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.call_rounded, size: 16),
                    label: const Text('Call'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sendGroupText(String groupId, String senderName) async {
    final text = _chatCtrl.text.trim();
    if (text.isEmpty || _sendingChat) return;
    setState(() => _sendingChat = true);
    try {
      await widget.services.groups.sendGroupMessage(
        groupId: groupId,
        senderName: senderName,
        text: text,
      );
      _chatCtrl.clear();
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _sendingChat = false);
    }
  }

  Future<void> _pickAndSendGroupImage(
    String groupId,
    String senderName,
    ImageSource source,
  ) async {
    if (_sendingChat) return;
    setState(() => _sendingChat = true);
    try {
      final b64 = await ImageHelper.pickChatImageBase64(source: source);
      if (b64 == null) return;
      await widget.services.groups.sendGroupMessage(
        groupId: groupId,
        senderName: senderName,
        text: _chatCtrl.text.trim(),
        imageBase64: b64,
      );
      _chatCtrl.clear();
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _sendingChat = false);
    }
  }

  Future<void> _confirmClearGroupChat(FriendGroup group) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.person_outline_rounded),
                title: const Text(
                  'Clear for Me Only',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text(
                  'Hides group messages on your device only',
                ),
                onTap: () => Navigator.pop(ctx, 'me'),
              ),
              ListTile(
                leading: Icon(
                  Icons.delete_forever_rounded,
                  color: scheme.error,
                ),
                title: Text(
                  'Clear for Everyone',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: scheme.error,
                  ),
                ),
                subtitle: const Text(
                  'Deletes all messages in this group chat for all members',
                ),
                onTap: () => Navigator.pop(ctx, 'everyone'),
              ),
            ],
          ),
        );
      },
    );
    if (choice == 'me') {
      await widget.services.groups.clearGroupChatForMe(group.id);
      _snack('Group chat cleared for you.');
      setState(() {});
    } else if (choice == 'everyone') {
      await widget.services.groups.clearGroupChatForEveryone(group.id);
      _snack('Group chat cleared for everyone.');
      setState(() {});
    }
  }

  Future<void> _showGroupMessageActions(
    String groupId,
    DirectChatMessage msg,
    bool isMe,
  ) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined),
                title: const Text(
                  'Delete for Me',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                onTap: () => Navigator.pop(ctx, 'me'),
              ),
              ListTile(
                leading: Icon(
                  isMe ? Icons.undo_rounded : Icons.delete_forever_rounded,
                  color: scheme.error,
                ),
                title: Text(
                  isMe
                      ? 'Unsend / Delete for Everyone'
                      : 'Delete for Everyone',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: scheme.error,
                  ),
                ),
                onTap: () => Navigator.pop(ctx, 'everyone'),
              ),
            ],
          ),
        );
      },
    );
    if (choice == 'me') {
      await widget.services.groups.deleteGroupMessageForMe(
        groupId: groupId,
        messageId: msg.id,
      );
      setState(() {});
    } else if (choice == 'everyone') {
      await widget.services.groups.deleteGroupMessageForEveryone(
        groupId: groupId,
        messageId: msg.id,
      );
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.services.game.currentUid;
    final scheme = Theme.of(context).colorScheme;

    return StreamBuilder<UserProfile?>(
      stream: widget.services.profile.watchProfile(uid),
      builder: (context, meSnap) {
        final me = meSnap.data;
        return StreamBuilder<FriendGroup?>(
          stream: widget.services.groups.watchGroup(widget.groupId),
          builder: (context, groupSnap) {
            final group = groupSnap.data;
            if (group == null) {
              return Scaffold(
                appBar: AppBar(title: const Text('Friend Group')),
                body: const Center(
                  child: Text('This group no longer exists.'),
                ),
              );
            }

            final standings = group.rankings;
            final active = group.activeMatch;

            return DefaultTabController(
              length: 2,
              child: Scaffold(
                appBar: AppBar(
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                        ),
                      ),
                      Text(
                        '${group.memberUids.length}/${group.maxMembers} Members • Code: ${group.hostFriendCode}',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    IconButton(
                      tooltip: 'Copy Group Friend Code',
                      icon: const Icon(Icons.copy_rounded),
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: group.hostFriendCode),
                        );
                        _snack(
                          'Group Friend Code ${group.hostFriendCode} copied! Share with up to ${group.maxMembers} members.',
                        );
                      },
                    ),
                    if (me != null)
                      IconButton(
                        tooltip: 'Group Voice Call',
                        icon: const Icon(Icons.call_rounded),
                        onPressed: () => _openGroupCallPicker(group, me),
                      ),
                    if (group.memberUids.length < group.maxMembers)
                      IconButton(
                        tooltip: 'Add member by Friend Code',
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                        onPressed: () => _openAddMemberDialog(group),
                      ),
                    PopupMenuButton<String>(
                      onSelected: (action) async {
                        if (action == 'clear_chat') {
                          await _confirmClearGroupChat(group);
                        } else if (action == 'leave') {
                          await widget.services.groups.leaveGroup(group.id);
                          if (context.mounted) Navigator.pop(context);
                        } else if (action == 'remove') {
                          await widget.services.groups.deleteGroup(group.id);
                          if (context.mounted) Navigator.pop(context);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'clear_chat',
                          child: Text('Clear Group Chat'),
                        ),
                        PopupMenuItem(
                          value: 'leave',
                          child: Text('Leave Group'),
                        ),
                        PopupMenuItem(
                          value: 'remove',
                          child: Text('Remove Group'),
                        ),
                      ],
                    ),
                  ],
                  bottom: const TabBar(
                    tabs: [
                      Tab(
                        icon: Icon(Icons.emoji_events_rounded),
                        text: 'Tournament & Rankings',
                      ),
                      Tab(
                        icon: Icon(Icons.forum_rounded),
                        text: 'Group Chat',
                      ),
                    ],
                  ),
                ),
                body: TabBarView(
                  children: [
                    // TAB 1: Group Tournament, Active 2-Player Match & Individual Rankings
                    ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        // Tournament Completed Banner + Keep / Remove Group Options
                        if (group.tournamentStatus == 'completed' &&
                            group.championName.isNotEmpty)
                          Card(
                            color:
                                AppTheme.goldAccent.withValues(alpha: 0.18),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  const Text(
                                    '🏆',
                                    style: TextStyle(fontSize: 44),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${group.championName} Won the ${group.cupName}!',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 17,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'Group Tournament finished! Check the final individual rankings below. Would you like to keep this group for another tournament or remove it?',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: FilledButton.icon(
                                          onPressed: () async {
                                            await widget.services.groups
                                                .keepGroupAndStartNewTournament(
                                              group.id,
                                            );
                                            _snack(
                                              'Group kept! New tournament season started.',
                                            );
                                          },
                                          icon: const Icon(
                                            Icons.replay_rounded,
                                            size: 18,
                                          ),
                                          label: const Text('Keep Group'),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: scheme.error,
                                          ),
                                          onPressed: () async {
                                            await widget.services.groups
                                                .deleteGroup(group.id);
                                            if (context.mounted) {
                                              Navigator.pop(context);
                                            }
                                          },
                                          icon: const Icon(
                                            Icons.delete_forever_rounded,
                                            size: 18,
                                          ),
                                          label: const Text('Remove Group'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        // Active 2-Player Match Card
                        if (active != null && active.status != 'finished') ...[
                          const SizedBox(height: 10),
                          Card(
                            color: scheme.primaryContainer
                                .withValues(alpha: 0.45),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    active.isFinalMatch
                                        ? '🏆 FINAL MATCH IN PROGRESS (${group.cupName})'
                                        : '⚔️ LIVE 2-PLAYER GROUP MATCH',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${active.hostName} vs ${active.guestName} • Room ${active.roomId}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${GameMode.fromId(active.mode).label} • ${active.boardSize}×${active.boardSize} • Best of ${active.bestOf}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  if (me != null &&
                                      (active.hostUid == me.uid ||
                                          active.guestUid == me.uid))
                                    SizedBox(
                                      width: double.infinity,
                                      child: FilledButton.icon(
                                        onPressed: () =>
                                            _openAndSyncGroupRoom(
                                          group: group,
                                          roomCode: active.roomId,
                                          isFinalMatch: active.isFinalMatch,
                                          joinAsGuest:
                                              active.guestUid == me.uid
                                                  ? me
                                                  : null,
                                        ),
                                        icon: const Icon(
                                          Icons.play_arrow_rounded,
                                        ),
                                        label: Text(
                                          active.hostUid == me.uid
                                              ? 'Enter Match Room'
                                              : 'Accept & Join Match',
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        // Initiate Challenge or Final Match Buttons (anyone in the group can initiate!)
                        if (me != null)
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: () =>
                                      _openInitiateGroupMatchDialog(
                                    group: group,
                                    me: me,
                                    isFinalMatch: false,
                                  ),
                                  icon: const Icon(
                                    Icons.sports_esports_rounded,
                                    size: 18,
                                  ),
                                  label: const FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text('Challenge Member (2P)'),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton.tonalIcon(
                                  onPressed: () =>
                                      _openInitiateGroupMatchDialog(
                                    group: group,
                                    me: me,
                                    isFinalMatch: true,
                                  ),
                                  icon: const Icon(
                                    Icons.emoji_events_rounded,
                                    size: 18,
                                  ),
                                  label: const FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text('Play Final Match 🏆'),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 16),
                        // Group Individual Rankings Table
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Group Individual Rankings',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            if (group.memberUids.length < group.maxMembers)
                              TextButton.icon(
                                onPressed: () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: group.hostFriendCode),
                                  );
                                  _snack(
                                    'Group Code ${group.hostFriendCode} copied! Share with friends to join.',
                                  );
                                },
                                icon: const Icon(Icons.copy_rounded, size: 16),
                                label: Text('Code: ${group.hostFriendCode}'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        for (var i = 0; i < standings.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Card(
                              child: ListTile(
                                leading: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 28,
                                      child: Text(
                                        i == 0
                                            ? '🥇'
                                            : (i == 1
                                                ? '🥈'
                                                : (i == 2
                                                    ? '🥉'
                                                    : '#${i + 1}')),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    LiveUserAvatar(
                                      services: widget.services,
                                      uid: standings[i].uid,
                                      fallbackAvatarId: standings[i].avatarId,
                                      size: 38,
                                    ),
                                  ],
                                ),
                                title: Text(
                                  standings[i].uid == uid
                                      ? '${standings[i].nickname} (You)'
                                      : standings[i].nickname,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                subtitle: Text(
                                  'Played: ${standings[i].played} • Won: ${standings[i].wins} • Lost: ${standings[i].losses} • Draw: ${standings[i].draws}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${standings[i].points} pts',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        color: scheme.primary,
                                      ),
                                    ),
                                    if (standings[i].cups > 0)
                                      Text(
                                        '🏆 ${standings[i].cups}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: AppTheme.goldAccent,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: scheme.error,
                          ),
                          onPressed: () async {
                            await widget.services.groups.leaveGroup(group.id);
                            if (context.mounted) Navigator.pop(context);
                          },
                          icon: const Icon(Icons.exit_to_app_rounded),
                          label: const Text('Leave from Group'),
                        ),
                      ],
                    ),
                    // TAB 2: Group Chat & Voice Calls
                    Column(
                      children: [
                        Expanded(
                          child: StreamBuilder<List<DirectChatMessage>>(
                            stream: widget.services.groups
                                .watchGroupMessages(group.id),
                            builder: (context, msgSnap) {
                              final messages = msgSnap.data ?? const [];
                              if (messages.isEmpty) {
                                return Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Text(
                                      'Group chat for ${group.name}. Coordinate matches, share photos, or start a call!',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                );
                              }
                              return ListView.builder(
                                reverse: true,
                                padding: const EdgeInsets.all(14),
                                itemCount: messages.length,
                                itemBuilder: (context, idx) {
                                  final msg = messages[idx];
                                  final isMe = msg.senderUid == uid;
                                  Uint8List? imgBytes;
                                  if (msg.hasImage) {
                                    try {
                                      imgBytes =
                                          base64Decode(msg.imageBase64!);
                                    } catch (_) {}
                                  }
                                  return Align(
                                    alignment: isMe
                                        ? Alignment.centerRight
                                        : Alignment.centerLeft,
                                    child: GestureDetector(
                                      onLongPress: () =>
                                          _showGroupMessageActions(
                                        group.id,
                                        msg,
                                        isMe,
                                      ),
                                      child: Container(
                                        constraints: BoxConstraints(
                                          maxWidth: MediaQuery.of(context)
                                                  .size
                                                  .width *
                                              0.74,
                                        ),
                                        margin: const EdgeInsets.symmetric(
                                          vertical: 4,
                                        ),
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: isMe
                                              ? scheme.primaryContainer
                                              : scheme.surfaceContainerHighest,
                                          borderRadius:
                                              BorderRadius.circular(16),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: isMe
                                              ? CrossAxisAlignment.end
                                              : CrossAxisAlignment.start,
                                          children: [
                                            if (!isMe)
                                              Text(
                                                msg.senderName,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w800,
                                                  color: scheme.primary,
                                                ),
                                              ),
                                            if (imgBytes != null) ...[
                                              const SizedBox(height: 4),
                                              ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                child: Image.memory(
                                                  imgBytes,
                                                  height: 160,
                                                  width: 210,
                                                  fit: BoxFit.cover,
                                                ),
                                              ),
                                            ],
                                            if (msg.text.isNotEmpty)
                                              Padding(
                                                padding:
                                                    const EdgeInsets.only(
                                                  top: 2,
                                                ),
                                                child: Text(msg.text),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            border: Border(
                              top: BorderSide(
                                color: scheme.outlineVariant
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                tooltip: 'Share photo',
                                icon: const Icon(Icons.photo_outlined),
                                onPressed: me == null
                                    ? null
                                    : () => _pickAndSendGroupImage(
                                          group.id,
                                          me.nickname,
                                          ImageSource.gallery,
                                        ),
                              ),
                              Expanded(
                                child: TextField(
                                  controller: _chatCtrl,
                                  maxLength: 500,
                                  decoration: const InputDecoration(
                                    hintText: 'Message group…',
                                    counterText: '',
                                  ),
                                  onSubmitted: (_) {
                                    if (me != null) {
                                      _sendGroupText(group.id, me.nickname);
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton.filled(
                                onPressed: (_sendingChat || me == null)
                                    ? null
                                    : () =>
                                        _sendGroupText(group.id, me.nickname),
                                icon: const Icon(Icons.send_rounded),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
