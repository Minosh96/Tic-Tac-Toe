import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/services/app_services.dart';
import '../../../data/repositories/voice_call_repository.dart';
import '../../../domain/models/group_models.dart';
import '../../core/app_theme.dart';
import '../../core/widgets/live_user_avatar.dart';

/// Multi-Participant Group Voice Call Screen (up to 5 members in a single call).
/// - Displays live profile cards for all members currently in the call (plus ringing/offline status for other members).
/// - Highlights each member's profile card in glowing neon green whenever they speak.
/// - Any member can leave the call and rejoin again at any time while the call is active.
class GroupVoiceCallScreen extends StatefulWidget {
  const GroupVoiceCallScreen({
    super.key,
    required this.services,
    required this.groupId,
    required this.myName,
    required this.myAvatar,
    this.incomingAlertCallId,
  });

  final AppServices services;
  final String groupId;
  final String myName;
  final String myAvatar;
  final String? incomingAlertCallId;

  @override
  State<GroupVoiceCallScreen> createState() => _GroupVoiceCallScreenState();
}

class _GroupVoiceCallScreenState extends State<GroupVoiceCallScreen> {
  ActiveGroupVoiceCall? _activeCall;
  Timer? _durationTimer;
  int _elapsedSeconds = 0;
  String _statusText = 'Joining group voice call…';
  bool _muted = false;
  bool _speakerOn = true;
  bool _leaving = false;
  bool _loggedCallStart = false;

  @override
  void initState() {
    super.initState();
    _joinGroupCall();
  }

  Future<void> _joinGroupCall() async {
    try {
      final groupSnap =
          await widget.services.groups.watchGroup(widget.groupId).first;
      if (groupSnap == null) {
        if (!mounted) return;
        setState(() => _statusText = 'Group no longer exists.');
        return;
      }

      final wasAlreadyActive = groupSnap.activeCall?.isOngoing ?? false;

      final handle = await widget.services.voiceCall.startOrJoinGroupVoiceCall(
        group: groupSnap,
        myName: widget.myName,
        myAvatar: widget.myAvatar,
        incomingAlertCallId: widget.incomingAlertCallId,
      );

      if (!mounted) {
        await handle.leaveCall();
        return;
      }

      if (!wasAlreadyActive && !_loggedCallStart) {
        _loggedCallStart = true;
        try {
          await widget.services.groups.sendGroupMessage(
            groupId: widget.groupId,
            senderName: widget.myName,
            text:
                '📞 ${widget.myName} started a Group Voice Call — tap Join Group Call to talk!',
          );
        } catch (_) {}
      }

      setState(() {
        _activeCall = handle;
        _statusText = 'Connected • Group Voice Call';
      });
      _startTimer();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusText = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _startTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
  }

  String _formatDuration(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _leaveCall() async {
    if (_leaving) return;
    _leaving = true;
    _durationTimer?.cancel();
    await _activeCall?.leaveCall(notifyRemote: true);
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    if (!_leaving) {
      _activeCall?.leaveCall(notifyRemote: true);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myUid = widget.services.game.currentUid;
    final call = _activeCall;

    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Leave Group Call',
          onPressed: _leaveCall,
        ),
        title: const Text(
          '🎙️ Group Voice Call',
          style: TextStyle(
            color: AppTheme.cyanAccent,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: StreamBuilder<FriendGroup?>(
          stream: widget.services.groups.watchGroup(widget.groupId),
          builder: (context, groupSnap) {
            final group = groupSnap.data;
            final activeCallState = group?.activeCall;
            final inCallUids = <String>{
              ...?activeCallState?.activeMemberUids,
              if (call != null) myUid,
            }.toList(growable: false);
            final allGroupMembers = group?.memberUids ?? <String>[myUid];

            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                children: [
                  Text(
                    group?.name ?? 'Friend Group',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    call != null
                        ? '${inCallUids.length} of ${allGroupMembers.length} in call • ${_formatDuration(_elapsedSeconds)}'
                        : _statusText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: call != null
                          ? Colors.greenAccent
                          : Colors.white.withValues(alpha: 0.8),
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      inCallUids.length <= 1
                          ? '🔔 Ringing all group members… Anyone can join or rejoin at any time!'
                          : '🔊 Members in this call (${inCallUids.length}/5) — speak freely!',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  // Grid of Member Profiles in the Call (plus ringing status for members who haven't joined yet)
                  Expanded(
                    child: call == null
                        ? const Center(
                            child: CircularProgressIndicator(),
                          )
                        : ValueListenableBuilder<Set<String>>(
                            valueListenable: call.speakingMemberUids,
                            builder: (context, remoteSpeakers, _) {
                              return ValueListenableBuilder<bool>(
                                valueListenable: call.mySpeaking,
                                builder: (context, iAmSpeaking, _) {
                                  // Put active call participants first, followed by ringing/invited members
                                  final orderedUids = <String>[
                                    ...inCallUids,
                                    ...allGroupMembers.where(
                                      (u) => !inCallUids.contains(u),
                                    ),
                                  ];
                                  return GridView.builder(
                                    gridDelegate:
                                        const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      mainAxisSpacing: 12,
                                      crossAxisSpacing: 12,
                                      childAspectRatio: 1.05,
                                    ),
                                    itemCount: orderedUids.length,
                                    itemBuilder: (context, index) {
                                      final memberUid = orderedUids[index];
                                      final isMe = memberUid == myUid;
                                      final isJoined =
                                          inCallUids.contains(memberUid);
                                      final isSpeaking = isJoined &&
                                          (isMe
                                              ? (iAmSpeaking && !_muted)
                                              : remoteSpeakers
                                                  .contains(memberUid));
                                      final fallbackName = isMe
                                          ? widget.myName
                                          : (group?.memberNames[memberUid] ??
                                              'Member');
                                      final fallbackAvatar = isMe
                                          ? widget.myAvatar
                                          : (group?.memberAvatars[memberUid] ??
                                              'fox');

                                      return AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 200),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: isJoined
                                              ? const Color(0xFF1F2242)
                                              : Colors.white
                                                  .withValues(alpha: 0.04),
                                          borderRadius:
                                              BorderRadius.circular(22),
                                          border: Border.all(
                                            color: isSpeaking
                                                ? Colors.greenAccent
                                                : (isJoined
                                                    ? AppTheme.cyanAccent
                                                        .withValues(alpha: 0.7)
                                                    : Colors.white24),
                                            width: isSpeaking ? 2.5 : 1.3,
                                          ),
                                          boxShadow: isSpeaking
                                              ? [
                                                  BoxShadow(
                                                    color: Colors.greenAccent
                                                        .withValues(
                                                            alpha: 0.35),
                                                    blurRadius: 18,
                                                    spreadRadius: 2,
                                                  ),
                                                ]
                                              : null,
                                        ),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            LiveUserAvatar(
                                              services: widget.services,
                                              uid: memberUid,
                                              fallbackAvatarId: fallbackAvatar,
                                              size: 56,
                                              borderColor: isSpeaking
                                                  ? Colors.greenAccent
                                                  : (isJoined
                                                      ? AppTheme.cyanAccent
                                                      : Colors.white38),
                                            ),
                                            const SizedBox(height: 8),
                                            LiveUserProfileBuilder(
                                              services: widget.services,
                                              uid: memberUid,
                                              builder: (context, liveProfile) {
                                                final name = (liveProfile
                                                            ?.nickname
                                                            .isNotEmpty ??
                                                        false)
                                                    ? liveProfile!.nickname
                                                    : fallbackName;
                                                return Text(
                                                  isMe ? '$name (You)' : name,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    color: isJoined
                                                        ? Colors.white
                                                        : Colors.white60,
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 13,
                                                  ),
                                                );
                                              },
                                            ),
                                            const SizedBox(height: 4),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: isSpeaking
                                                    ? Colors.greenAccent
                                                        .withValues(alpha: 0.2)
                                                    : (isJoined
                                                        ? AppTheme.cyanAccent
                                                            .withValues(
                                                                alpha: 0.16)
                                                        : Colors.white10),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: Text(
                                                !isJoined
                                                    ? '🔔 Ringing / Not in call'
                                                    : (isMe && _muted
                                                        ? '🔇 Muted'
                                                        : (isSpeaking
                                                            ? '🔊 Speaking…'
                                                            : '✅ In Call')),
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w800,
                                                  color: isSpeaking
                                                      ? Colors.greenAccent
                                                      : (isJoined
                                                          ? AppTheme.cyanAccent
                                                          : Colors.white54),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  );
                                },
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 14),
                  // Call Controls Row (Mute, Speaker, Leave Call)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _GroupCallControlButton(
                        icon: _muted
                            ? Icons.mic_off_rounded
                            : Icons.mic_rounded,
                        label: _muted ? 'Unmute' : 'Mute',
                        active: _muted,
                        onTap: () {
                          final next = !_muted;
                          setState(() => _muted = next);
                          _activeCall?.setMuted(next);
                        },
                      ),
                      _GroupCallControlButton(
                        icon: _speakerOn
                            ? Icons.volume_up_rounded
                            : Icons.phone_in_talk_rounded,
                        label: _speakerOn ? 'Speaker' : 'Earpiece',
                        active: _speakerOn,
                        onTap: () async {
                          final next = !_speakerOn;
                          setState(() => _speakerOn = next);
                          await _activeCall?.setSpeakerphone(next);
                        },
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 64,
                            height: 64,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.redAccent,
                                shape: const CircleBorder(),
                                padding: EdgeInsets.zero,
                              ),
                              onPressed: _leaveCall,
                              child: const Icon(
                                Icons.call_end_rounded,
                                color: Colors.white,
                                size: 30,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Leave',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _GroupCallControlButton extends StatelessWidget {
  const _GroupCallControlButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 58,
          height: 58,
          child: IconButton.filledTonal(
            style: IconButton.styleFrom(
              backgroundColor: active
                  ? AppTheme.cyanAccent.withValues(alpha: 0.25)
                  : Colors.white.withValues(alpha: 0.12),
              foregroundColor: active ? AppTheme.cyanAccent : Colors.white,
            ),
            onPressed: onTap,
            icon: Icon(icon, size: 26),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
