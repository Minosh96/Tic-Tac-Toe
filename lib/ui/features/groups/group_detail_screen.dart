import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/services/app_services.dart';
import '../../../core/services/image_helper.dart';
import '../../../data/repositories/group_repository.dart';
import '../../../domain/models/group_models.dart';
import '../../../domain/models/social_models.dart';
import '../../../domain/models/user_profile.dart';
import '../../core/app_theme.dart';
import '../../core/widgets/live_user_avatar.dart';
import '../../core/widgets/melow_avatar.dart';
import '../../core/widgets/melow_logo.dart';
import '../room/room_page.dart';
import 'group_voice_call_screen.dart';

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

  void _startOrJoinGroupVoiceCall(FriendGroup group, UserProfile me) {
    if (group.memberUids.length < 2) {
      _snack('Wait for at least 1 friend to join the group before starting a group call.');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupVoiceCallScreen(
          services: widget.services,
          groupId: group.id,
          myName: me.nickname,
          myAvatar: me.avatarId,
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
                        tooltip: (group.activeCall?.isOngoing ?? false)
                            ? 'Join Ongoing Group Voice Call'
                            : 'Start Group Voice Call (Rings All Members)',
                        icon: Icon(
                          (group.activeCall?.isOngoing ?? false)
                              ? Icons.phone_in_talk_rounded
                              : Icons.call_rounded,
                          color: (group.activeCall?.isOngoing ?? false)
                              ? Colors.greenAccent
                              : null,
                        ),
                        onPressed: () => _startOrJoinGroupVoiceCall(group, me),
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
                        // Live Active Group Call Banner (allows any member who left or hasn't joined yet to Join/Rejoin!)
                        if ((group.activeCall?.isOngoing ?? false) &&
                            me != null) ...[
                          Card(
                            color: Colors.green.withValues(alpha: 0.18),
                            child: ListTile(
                              leading: const Icon(
                                Icons.phone_in_talk_rounded,
                                color: Colors.green,
                              ),
                              title: Text(
                                '🎙️ Group Voice Call Live (${group.activeCall!.activeMemberUids.length}/${group.memberUids.length} in call)',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              subtitle: Text(
                                group.activeCall!.isMemberInCall(uid)
                                    ? 'You are in this call • Tap to open call screen'
                                    : 'Started by ${group.activeCall!.initiatorName} • Tap to join or rejoin!',
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () =>
                                    _startOrJoinGroupVoiceCall(group, me),
                                icon: const Icon(Icons.call_rounded, size: 16),
                                label: Text(
                                  group.activeCall!.isMemberInCall(uid)
                                      ? 'Open'
                                      : 'Join Call',
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
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
                        // End-of-Tournament Summary Card (Match Results, Final Rankings & Shareable Game Card)
                        if (group.tournamentStatus == 'completed' &&
                            group.championName.isNotEmpty) ...[
                          Card(
                            color:
                                AppTheme.goldAccent.withValues(alpha: 0.18),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Text(
                                    '🏆 Tournament Results & Summary',
                                    textAlign: TextAlign.center,
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
                                          .withValues(alpha: 0.85),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Center(
                                          child: Text(
                                            '🥇 Champion: ${group.championName}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 16,
                                              color: AppTheme.goldAccent,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Center(
                                          child: Text(
                                            'Won the ${group.cupName} 🏆',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        if (group.effectiveRunnerUpName
                                            .isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Center(
                                            child: Text(
                                              '🥈 Runner-Up: ${group.effectiveRunnerUpName}',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 14,
                                                color: scheme.primary,
                                              ),
                                            ),
                                          ),
                                        ],
                                        if (fixtures.isNotEmpty) ...[
                                          const Divider(height: 18),
                                          const Text(
                                            'Match Results:',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          for (final fx in fixtures)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 3,
                                              ),
                                              child: Text(
                                                '• ${fx.isFinalMatch ? 'Final' : 'Match ${fx.matchNumber}'} (${fx.player1Name} vs ${fx.player2Name}): ${fx.resultText.isNotEmpty ? fx.resultText : fx.statusLabel}',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                        ],
                                        if (standings.isNotEmpty) ...[
                                          const Divider(height: 18),
                                          const Text(
                                            'Final Group Rankings:',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          for (var r = 0;
                                              r < standings.length;
                                              r++)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 3,
                                              ),
                                              child: Text(
                                                '${r == 0 ? '🥇 1.' : (r == 1 ? '🥈 2.' : (r == 2 ? '🥉 3.' : '${r + 1}.'))} ${standings[r].nickname} — ${standings[r].points} pts (W:${standings[r].wins} L:${standings[r].losses} D:${standings[r].draws})',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  FilledButton.tonalIcon(
                                    onPressed: () =>
                                        showModalBottomSheet<void>(
                                      context: context,
                                      isScrollControlled: true,
                                      builder: (_) =>
                                          GroupTournamentShareSheet(
                                        group: group,
                                        standings: standings,
                                        fixtures: fixtures,
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.share_rounded,
                                      size: 18,
                                    ),
                                    label: const Text(
                                      'Share Tournament Result Card',
                                    ),
                                  ),
                                  const SizedBox(height: 8),
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
                        // Group Individual Rankings / Member List (Shows 1, 2, 3, 4, 5 before completion; shows medals & rankings after completion)
                        Text(
                          group.tournamentStatus == 'completed'
                              ? 'Final Group Rankings'
                              : 'Group Members & Standings',
                          style: const TextStyle(
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
                                    Container(
                                      width: 30,
                                      height: 30,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: group.tournamentStatus ==
                                                'completed'
                                            ? AppTheme.goldAccent
                                                .withValues(alpha: 0.16)
                                            : scheme.primary
                                                .withValues(alpha: 0.14),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text(
                                        group.tournamentStatus == 'completed'
                                            ? (i == 0
                                                ? '🥇'
                                                : (i == 1
                                                    ? '🥈'
                                                    : (i == 2
                                                        ? '🥉'
                                                        : '${i + 1}')))
                                            : '${i + 1}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 14,
                                          color: scheme.primary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
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

/// Shareable Group Tournament Result Card Sheet & PNG Exporter.
/// Displays the group name, Champion 🥇, Runner-Up 🥈, Final Group Rankings,
/// and Match Results, and exports a high-resolution PNG via SharePlus.
class GroupTournamentShareSheet extends StatefulWidget {
  const GroupTournamentShareSheet({
    super.key,
    required this.group,
    required this.standings,
    required this.fixtures,
  });

  final FriendGroup group;
  final List<GroupMemberStanding> standings;
  final List<GroupFixture> fixtures;

  @override
  State<GroupTournamentShareSheet> createState() =>
      _GroupTournamentShareSheetState();
}

class _GroupTournamentShareSheetState extends State<GroupTournamentShareSheet> {
  final GlobalKey _cardKey = GlobalKey();
  bool _exporting = false;

  Future<void> _sharePng() async {
    setState(() => _exporting = true);
    try {
      final boundary =
          _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('Card preview is still rendering.');
      }
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw Exception('Could not encode tournament card PNG.');
      }
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/melow_group_tournament_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(byteData.buffer.asUint8List());
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          text:
              '${widget.group.championName} won the ${widget.group.cupName} in ${widget.group.name} (Melow Tic Tac Toe)! 🏆',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not share tournament card: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final standings = widget.standings;
    final fixtures = widget.fixtures;
    final champAvatar = group.memberAvatars[group.championUid] ?? 'astro';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Share Tournament Result Card',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 14),
              RepaintBoundary(
                key: _cardKey,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        AppTheme.darkBackground,
                        Color(0xFF281B5A),
                        Color(0xFF152546),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: AppTheme.goldAccent.withValues(alpha: 0.75),
                      width: 2,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const MelowLogo(
                            size: 36,
                            borderRadius: 10,
                            showGlow: false,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Melow Tic Tac Toe',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                                Text(
                                  group.name,
                                  style: const TextStyle(
                                    color: AppTheme.cyanAccent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Text('🏆', style: TextStyle(fontSize: 28)),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Center(
                        child: Column(
                          children: [
                            Text(
                              group.cupName.toUpperCase(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppTheme.goldAccent,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.1,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                MelowAvatar(
                                  avatarId: champAvatar,
                                  size: 46,
                                  borderColor: AppTheme.goldAccent,
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '🥇 Champion: ${group.championName}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    if (group.effectiveRunnerUpName.isNotEmpty)
                                      Text(
                                        '🥈 Runner-Up: ${group.effectiveRunnerUpName}',
                                        style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.82),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Final Rankings',
                              style: TextStyle(
                                color: AppTheme.goldAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 6),
                            for (var i = 0; i < standings.length; i++)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 3),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${i == 0 ? '🥇 1.' : (i == 1 ? '🥈 2.' : (i == 2 ? '🥉 3.' : '${i + 1}.'))} ${standings[i].nickname}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${standings[i].points} pts (W:${standings[i].wins} L:${standings[i].losses} D:${standings[i].draws})',
                                      style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.78),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (fixtures.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              const Text(
                                'Match Results',
                                style: TextStyle(
                                  color: AppTheme.cyanAccent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              for (final fx in fixtures)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: Text(
                                    '• ${fx.isFinalMatch ? 'Final' : 'M${fx.matchNumber}'} (${fx.player1Name} vs ${fx.player2Name}): ${fx.resultText.isNotEmpty ? fx.resultText : fx.statusLabel}',
                                    style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.85),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: Text(
                          'Developed at Melow Labs',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: 10,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _exporting ? null : _sharePng,
                  icon: _exporting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.share_rounded),
                  label: Text(
                    _exporting
                        ? 'Preparing PNG…'
                        : 'Share Tournament Result Card',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
