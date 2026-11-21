import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../core/services/app_services.dart';
import '../../../data/repositories/voice_call_repository.dart';
import '../../../domain/models/social_models.dart';
import '../../core/app_theme.dart';
import '../../core/widgets/live_user_avatar.dart';

/// Hybrid WebRTC + Carrier-Proof Live Relay Voice Call screen.
/// Automatically displays the peer's live gallery photo and logs the call into Friend Chat.
class VoiceCallScreen extends StatefulWidget {
  const VoiceCallScreen.outgoing({
    super.key,
    required this.services,
    required String calleeUid,
    required String calleeName,
    required String calleeAvatar,
    required String callerName,
    required String callerAvatar,
    String? roomId,
  })  : _isOutgoing = true,
        _peerUid = calleeUid,
        _peerName = calleeName,
        _peerAvatar = calleeAvatar,
        _myName = callerName,
        _myAvatar = callerAvatar,
        _roomId = roomId,
        _incomingSession = null;

  VoiceCallScreen.incoming({
    super.key,
    required this.services,
    required VoiceCallSession session,
  })  : _isOutgoing = false,
        _peerUid = session.callerUid,
        _peerName = session.callerName,
        _peerAvatar = session.callerAvatar,
        _myName = session.calleeName,
        _myAvatar = 'fox',
        _roomId = session.roomId,
        _incomingSession = session;

  final AppServices services;
  final bool _isOutgoing;
  final String _peerUid;
  final String _peerName;
  final String _peerAvatar;
  final String _myName;
  final String _myAvatar;
  final String? _roomId;
  final VoiceCallSession? _incomingSession;

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen> {
  ActiveVoiceCall? _activeCall;
  StreamSubscription<VoiceCallSession?>? _callSub;
  Timer? _durationTimer;
  int _elapsedSeconds = 0;
  String _statusText = 'Requesting microphone…';
  VoiceTransportMode _mode = VoiceTransportMode.connecting;
  bool _muted = false;
  bool _speakerOn = true;
  bool _ended = false;
  bool _callLogged = false;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    try {
      ActiveVoiceCall call;
      if (widget._isOutgoing) {
        setState(() => _statusText = 'Ringing ${widget._peerName}…');
        call = await widget.services.voiceCall.startVoiceCall(
          calleeUid: widget._peerUid,
          calleeName: widget._peerName,
          callerName: widget._myName,
          callerAvatar: widget._myAvatar,
          roomId: widget._roomId,
        );
      } else {
        setState(() => _statusText = 'Joining voice call…');
        call = await widget.services.voiceCall
            .answerVoiceCall(widget._incomingSession!);
      }

      if (!mounted) {
        await call.hangUp();
        return;
      }

      setState(() {
        _activeCall = call;
        _statusText = call.audioState.value;
        _mode = call.transportMode.value;
      });

      call.audioState.addListener(_onCallStateChanged);
      call.transportMode.addListener(_onCallStateChanged);

      _callSub =
          widget.services.voiceCall.watchCall(call.callId).listen((session) {
        if (!mounted || session == null) return;
        if (session.status == 'declined') {
          _closeWithOutcome('Call declined', logSummary: '📞 Declined voice call');
        } else if (session.status == 'ended' || session.status == 'missed') {
          _closeWithOutcome('Call ended');
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ended = true;
        _statusText = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _onCallStateChanged() {
    final call = _activeCall;
    if (!mounted || call == null || _ended) return;
    final nextStatus = call.audioState.value;
    final nextMode = call.transportMode.value;
    if ((nextMode == VoiceTransportMode.webrtcLive ||
            nextMode == VoiceTransportMode.relayLive) &&
        _durationTimer == null) {
      _startTimer();
    }
    setState(() {
      _statusText = nextStatus;
      _mode = nextMode;
    });
  }

  void _startTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
  }

  Future<void> _writeCallLogIfCaller(String? customSummary) async {
    if (_callLogged || !widget._isOutgoing) return;
    _callLogged = true;
    final summary = customSummary ??
        (_elapsedSeconds > 0 || (_activeCall?.everConnected ?? false)
            ? '📞 Voice call • ${_formatDuration(_elapsedSeconds)}'
            : '📞 Missed voice call');
    await widget.services.chat.logCallInChat(
      friendUid: widget._peerUid,
      senderName: widget._myName,
      summary: summary,
    );
  }

  Future<void> _closeWithOutcome(String msg, {String? logSummary}) async {
    if (_ended) return;
    _ended = true;
    _durationTimer?.cancel();
    _activeCall?.audioState.removeListener(_onCallStateChanged);
    _activeCall?.transportMode.removeListener(_onCallStateChanged);
    await _writeCallLogIfCaller(logSummary);
    await _activeCall?.hangUp(notifyRemote: false);
    if (!mounted) return;
    setState(() => _statusText = msg);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _hangUp() async {
    if (_ended) {
      if (mounted) Navigator.pop(context);
      return;
    }
    _ended = true;
    _durationTimer?.cancel();
    _activeCall?.audioState.removeListener(_onCallStateChanged);
    _activeCall?.transportMode.removeListener(_onCallStateChanged);
    await _writeCallLogIfCaller(null);
    await _activeCall?.hangUp(notifyRemote: true);
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _callSub?.cancel();
    _activeCall?.audioState.removeListener(_onCallStateChanged);
    _activeCall?.transportMode.removeListener(_onCallStateChanged);
    _activeCall?.hangUp(notifyRemote: !_ended);
    super.dispose();
  }

  String _formatDuration(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final call = _activeCall;
    final isConnected = _mode == VoiceTransportMode.webrtcLive ||
        _mode == VoiceTransportMode.relayLive;
    final isRelay = _mode == VoiceTransportMode.relayLive;

    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      body: SafeArea(
        child: Stack(
          children: [
            if (call != null && _mode != VoiceTransportMode.relayLive)
              Positioned(
                left: 0,
                top: 0,
                width: 1,
                height: 1,
                child: Opacity(
                  opacity: 0.01,
                  child: RTCVideoView(call.remoteRenderer),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const SizedBox(height: 14),
                  Text(
                    isRelay ? '🎙️ Melow Live Voice Relay' : '🎙️ Melow Voice Call',
                    style: const TextStyle(
                      color: AppTheme.cyanAccent,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const Spacer(),
                  LiveUserAvatar(
                    services: widget.services,
                    uid: widget._peerUid,
                    fallbackAvatarId: widget._peerAvatar,
                    size: 112,
                    borderColor: isConnected
                        ? Colors.greenAccent
                        : AppTheme.purpleAccent,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    widget._peerName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isConnected
                        ? '${isRelay ? 'Live Relay' : 'Live Audio'} • ${_formatDuration(_elapsedSeconds)}'
                        : _statusText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isConnected
                          ? Colors.greenAccent
                          : Colors.white.withValues(alpha: 0.82),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (call != null && isRelay) ...[
                    const SizedBox(height: 12),
                    ValueListenableBuilder<bool>(
                      valueListenable: call.peerSpeaking,
                      builder: (context, speaking, _) => AnimatedOpacity(
                        opacity: speaking ? 1.0 : 0.65,
                        duration: const Duration(milliseconds: 200),
                        child: Text(
                          speaking
                              ? '🔊 ${widget._peerName} is speaking…'
                              : 'Hold the mic button below to talk (auto-plays on friend’s phone)',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    ValueListenableBuilder<bool>(
                      valueListenable: call.isTalking,
                      builder: (context, talking, _) {
                        return GestureDetector(
                          onLongPressStart: (_) => call.startRelayTalk(),
                          onLongPressEnd: (_) => call.stopAndSendRelayTalk(),
                          onTap: () {
                            if (talking) {
                              call.stopAndSendRelayTalk();
                            } else {
                              call.startRelayTalk();
                            }
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: talking ? 136 : 122,
                            height: talking ? 136 : 122,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: talking
                                    ? const [Colors.redAccent, Colors.orangeAccent]
                                    : const [
                                        AppTheme.purpleAccent,
                                        AppTheme.cyanAccent,
                                      ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: (talking
                                          ? Colors.redAccent
                                          : AppTheme.cyanAccent)
                                      .withValues(alpha: 0.55),
                                  blurRadius: talking ? 30 : 18,
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  talking
                                      ? Icons.graphic_eq_rounded
                                      : Icons.mic_rounded,
                                  color: Colors.white,
                                  size: 40,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  talking ? 'SENDING…' : 'HOLD / TAP\nTO TALK',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ] else if (call != null && !isConnected && !_ended) ...[
                    const SizedBox(height: 18),
                    TextButton.icon(
                      onPressed: () => call.switchToRelayMode(),
                      icon: const Icon(
                        Icons.cell_tower_rounded,
                        color: AppTheme.cyanAccent,
                        size: 18,
                      ),
                      label: const Text(
                        'Slow network? Switch to Live Relay',
                        style: TextStyle(color: AppTheme.cyanAccent),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _CallControlButton(
                        icon:
                            _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                        label: _muted ? 'Unmute' : 'Mute',
                        active: _muted,
                        onTap: () {
                          setState(() => _muted = !_muted);
                          _activeCall?.setMuted(_muted);
                        },
                      ),
                      _CallControlButton(
                        icon: _speakerOn
                            ? Icons.volume_up_rounded
                            : Icons.hearing_rounded,
                        label: _speakerOn ? 'Speaker' : 'Earpiece',
                        active: _speakerOn,
                        onTap: () {
                          setState(() => _speakerOn = !_speakerOn);
                          _activeCall?.setSpeakerphone(_speakerOn);
                        },
                      ),
                      _CallControlButton(
                        icon: Icons.call_end_rounded,
                        label: 'End',
                        danger: true,
                        onTap: _hangUp,
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallControlButton extends StatelessWidget {
  const _CallControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final bg = danger
        ? Colors.redAccent
        : active
            ? AppTheme.purpleAccent
            : AppTheme.darkSurfaceHigh;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
