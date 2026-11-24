import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/services/app_services.dart';
import '../../../core/services/image_helper.dart';
import '../../../data/repositories/group_repository.dart';
import '../../../domain/models/group_models.dart';
import '../../../domain/models/social_models.dart';
import '../../../domain/models/user_profile.dart';
import '../../core/app_theme.dart';
import '../../core/widgets/live_user_avatar.dart';
import '../chat/voice_call_screen.dart';
import '../room/room_page.dart';

/// Friend Group Tournament & Group Chat Screen:
/// - Displays all Tournament Fixtures (`User1 vs User2`) as compact cards.
/// - The Room Code and Play/Join button are visible ONLY to the 2 participating players of that fixture;
///   other group members see the fixture card with its live Status (`Ready to Play`, `Playing`, or `Result`).
/// - At the end of the tournament, displays a Champion 🥇 and Runner-Up 🥈 Summary Card
///   with options to Keep Group or Remove Group.
/// - Group Chat displays the sender's name on every message with Send, Unsend, Delete for Me,
///   Delete for Everyone, Clear for Me, and Clear for Everyone.
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
  String? _busyFixtureId;

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

  Future<void> _playFixtureMatch({
    required FriendGroup group,
    required GroupFixture fixture,
    required UserProfile me,
  }) async {
    if (!fixture.isParticipant(me.uid)) {
      _snack(
        'Only ${fixture.player1Name} and ${fixture.player2Name} are eligible to play this match.',
      );
      return;
    }
    if (_busyFixtureId != null) return;
    setState(() => _busyFixtureId = fixture.id);
    try {
      final roomCode = await widget.services.groups.startOrJoinFixture(
        group: group,
        fixture: fixture,
        me: me,
      );
      if (!mounted) return;
      setState(() => _busyFixtureId = null);
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RoomPage(
            code: roomCode,
            services: widget.services,
          ),
        ),
      );
      // When returning from RoomPage, sync the match result back to the fixture & rankings!
      final roomSnap = await widget.services.game.watchRoom(roomCode).first;
      if (roomSnap != null && roomSnap.isFinished) {
        await widget.services.groups.syncFixtureResult(
          groupId: group.id,
          fixtureId: fixture.id,
          room: roomSnap,
        );
      }
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busyFixtureId = null);
    }
  }

  void _openGroupCallPicker(FriendGroup group, UserProfile me) {
    final others =
        group.memberUids.where((u) => u != me.uid).toList(growable: false);
    if (others.isEmpty) {
      _snack('Wait for another member to join the group before calling.');
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

  String _formatTime(DateTime? dt) {
    if (dt == null) return 'now';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
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
            final fixtures = group.fixtures.isNotEmpty
                ? group.fixtures
                : GroupRepository.buildFixturesForMembers(
                    memberUids: group.memberUids,
                    memberNames: group.memberNames,
                    existingFixtures: const [],
                  );

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
                          'Group Code ${group.hostFriendCode} copied! Share with friends to join.',
                        );
                      },
                    ),
                    if (me != null)
                      IconButton(
                        tooltip: 'Group Voice Call',
                        icon: const Icon(Icons.call_rounded),
                        onPressed: () => _openGroupCallPicker(group, me),
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
                        text: 'Fixtures & Rankings',
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
                    // TAB 1: Tournament Summary, Fixtures Cards & Individual Rankings
                    ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        // Shareable Join Code Banner while waiting for members
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.vpn_key_rounded),
                            title: Text(
                              'Group Join Code: ${group.hostFriendCode}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            subtitle: Text(
                              '${group.memberUids.length} of ${group.maxMembers} members joined • Friends tap "Join Group" and enter ${group.hostFriendCode}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: IconButton.filledTonal(
                              icon: const Icon(Icons.copy_rounded),
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(text: group.hostFriendCode),
                                );
                                _snack(
                                  'Code ${group.hostFriendCode} copied!',
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // End-of-Tournament Summary Card (Champion 🥇 & Runner-Up 🥈)
                        if (group.tournamentStatus == 'completed' &&
                            group.championName.isNotEmpty) ...[
                          Card(
                            color:
                                AppTheme.goldAccent.withValues(alpha: 0.18),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  const Text(
                                    '🏆 Tournament Summary',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 17,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: scheme.surface
                                          .withValues(alpha: 0.8),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Column(
                                      children: [
                                        Text(
                                          '🥇 Champion: ${group.championName}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 16,
                                            color: AppTheme.goldAccent,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Won the ${group.cupName} 🏆',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        if (group.effectiveRunnerUpName
                                            .isNotEmpty) ...[
                                          const Divider(height: 16),
                                          Text(
                                            '🥈 Runner-Up: ${group.effectiveRunnerUpName}',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 14,
                                              color: scheme.primary,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
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
                                              'Group kept! New tournament fixtures generated.',
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
                          const SizedBox(height: 14),
                        ],
                        // Tournament Fixtures Section
                        Text(
                          'Tournament Fixtures (${fixtures.length} ${fixtures.length == 1 ? 'Match' : 'Matches'})',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Room codes and Play buttons are visible only to the 2 players in each match.',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (fixtures.isEmpty)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Text(
                                'Share your Group Code (${group.hostFriendCode}) with at least 1 friend. Fixtures will appear automatically as members join!',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          )
                        else
                          for (final f in fixtures)
                            _FixtureCard(
                              fixture: f,
                              currentUid: uid,
                              busy: _busyFixtureId == f.id,
                              onPlayOrJoin: me == null
                                  ? null
                                  : () => _playFixtureMatch(
                                        group: group,
                                        fixture: f,
                                        me: me,
                                      ),
                              onCopyRoomCode: f.roomId.isEmpty
                                  ? null
                                  : () async {
                                      await Clipboard.setData(
                                        ClipboardData(text: f.roomId),
                                      );
                                      _snack(
                                        'Match Room Code ${f.roomId} copied!',
                                      );
                                    },
                            ),
                        const SizedBox(height: 16),
                        // Group Individual Rankings Table
                        const Text(
                          'Group Individual Rankings',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
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
                    // TAB 2: Group Chat (Sender's name shown on every message + unsend/delete/clear)
                    Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Group Chat (${group.memberUids.length} members)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () => _confirmClearGroupChat(group),
                                icon: const Icon(
                                  Icons.delete_sweep_rounded,
                                  size: 16,
                                ),
                                label: const Text('Clear Chat'),
                              ),
                            ],
                          ),
                        ),
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
                                  final senderLabel = msg.senderName.isNotEmpty
                                      ? (isMe
                                          ? '${msg.senderName} (You)'
                                          : msg.senderName)
                                      : (isMe ? 'You' : 'Member');
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
                                              0.76,
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
                                            // Always show sender's name on every group chat message!
                                            Text(
                                              senderLabel,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w900,
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
                                                  top: 3,
                                                ),
                                                child: Text(msg.text),
                                              ),
                                            const SizedBox(height: 3),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  _formatTime(msg.createdAt),
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color:
                                                        scheme.onSurfaceVariant,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                InkWell(
                                                  onTap: () =>
                                                      _showGroupMessageActions(
                                                    group.id,
                                                    msg,
                                                    isMe,
                                                  ),
                                                  child: Icon(
                                                    Icons.more_horiz_rounded,
                                                    size: 14,
                                                    color:
                                                        scheme.onSurfaceVariant,
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

/// Compact fixture card (`User1 vs User2`):
/// - Shows the Room Code and Play/Join button ONLY if `fixture.isParticipant(currentUid)` is true.
/// - Non-participating group members see the fixture card with its live Status (`Ready to Play`, `Playing`, or `Result`).
class _FixtureCard extends StatelessWidget {
  const _FixtureCard({
    required this.fixture,
    required this.currentUid,
    required this.busy,
    this.onPlayOrJoin,
    this.onCopyRoomCode,
  });

  final GroupFixture fixture;
  final String currentUid;
  final bool busy;
  final VoidCallback? onPlayOrJoin;
  final VoidCallback? onCopyRoomCode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iAmParticipant = fixture.isParticipant(currentUid);
    final isFinished = fixture.status == 'finished';
    final isPlaying = fixture.status == 'playing';

    final statusColor = isFinished
        ? Colors.green
        : (isPlaying ? AppTheme.goldAccent : scheme.primary);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        color: fixture.isFinalMatch
            ? AppTheme.goldAccent.withValues(alpha: 0.14)
            : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: (fixture.isFinalMatch
                              ? AppTheme.goldAccent
                              : scheme.primary)
                          .withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      fixture.isFinalMatch
                          ? '🏆 FINAL MATCH'
                          : 'Match ${fixture.matchNumber}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: fixture.isFinalMatch
                            ? AppTheme.goldAccent
                            : scheme.primary,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      fixture.statusLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${fixture.player1Name}  vs  ${fixture.player2Name}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (iAmParticipant && !isFinished)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: busy ? null : onPlayOrJoin,
                      icon: const Icon(Icons.sports_esports_rounded, size: 16),
                      label: Text(
                        busy
                            ? 'Opening…'
                            : (isPlaying
                                ? 'Join Match'
                                : 'Play Match'),
                      ),
                    ),
                ],
              ),
              // Show Room Code ONLY to the 2 participating players of this fixture!
              if (iAmParticipant && fixture.roomId.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.vpn_key_rounded,
                      size: 14,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Your Match Room Code: ${fixture.roomId}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: onCopyRoomCode,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.copy_rounded,
                          size: 14,
                          color: scheme.primary,
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
}
