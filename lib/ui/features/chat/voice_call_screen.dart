import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../core/services/app_services.dart';
import '../../../data/repositories/voice_call_repository.dart';
import '../../../domain/models/social_models.dart';
import '../../core/app_theme.dart';
import '../../core/widgets/melow_avatar.dart';

/// Real-time Peer-to-Peer WebRTC Voice Call screen with bound remote audio sink,
/// real ICE audio status, native mic permission, mute & speakerphone controls.
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
        _calleeUid = calleeUid,
        _peerName = calleeName,
        _peerAvatar = calleeAvatar,
        _callerName = callerName,
        _callerAvatar = callerAvatar,
        _roomId = roomId,
        _incomingSession = null;

  VoiceCallScreen.incoming({
    super.key,
    required this.services,
    required VoiceCallSession session,
  })  : _isOutgoing = false,
        _calleeUid = session.calleeUid,
        _peerName = session.callerName,
        _peerAvatar = session.callerAvatar,
        _callerName = session.callerName,
        _callerAvatar = session.callerAvatar,
        _roomId = session.roomId,
        _incomingSession = session;

  final AppServices services;
  final bool _isOutgoing;
  final String _calleeUid;
  final String _peerName;
  final String _peerAvatar;
  final String _callerName;
  final String _callerAvatar;
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
  bool _muted = false;
  bool _speakerOn = true;
  bool _ended = false;

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
          calleeUid: widget._calleeUid,
          calleeName: widget._peerName,
          callerName: widget._callerName,
          callerAvatar: widget._callerAvatar,
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
      });

      call.audioState.addListener(_onAudioStateChanged);

      _callSub =
          widget.services.voiceCall.watchCall(call.callId).listen((session) {
        if (!mounted || session == null) return;
        if (session.status == 'declined') {
          _closeWithMessage('Call declined');
        } else if (session.status == 'ended' || session.status == 'missed') {
          _closeWithMessage('Call ended');
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

  void _onAudioStateChanged() {
    final call = _activeCall;
    if (!mounted || call == null || _ended) return;
    final next = call.audioState.value;
    if (next == 'Connected' && _durationTimer == null) {
      _startTimer();
    }
    setState(() => _statusText = next);
  }

  void _startTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
  }

  Future<void> _closeWithMessage(String msg) async {
    if (_ended) return;
    _ended = true;
    _durationTimer?.cancel();
    _activeCall?.audioState.removeListener(_onAudioStateChanged);
    await _activeCall?.hangUp(notifyRemote: false);
    if (!mounted) return;
    setState(() => _statusText = msg);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _hangUp() async {
    _ended = true;
    _durationTimer?.cancel();
    _activeCall?.audioState.removeListener(_onAudioStateChanged);
    await _activeCall?.hangUp(notifyRemote: true);
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _callSub?.cancel();
    _activeCall?.audioState.removeListener(_onAudioStateChanged);
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
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      body: SafeArea(
        child: Stack(
          children: [
            // Hidden 1x1 RTCVideoView ensures Android WebRTC remote audio sink stays active.
            if (call != null)
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
                  const SizedBox(height: 20),
                  const Text(
                    '🎙️ Melow Voice Call',
                    style: TextStyle(
                      color: AppTheme.cyanAccent,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const Spacer(),
                  MelowAvatar(
                    avatarId: widget._peerAvatar,
                    size: 112,
                    borderColor: _durationTimer != null
                        ? Colors.greenAccent
                        : AppTheme.purpleAccent,
                  ),
                  const SizedBox(height: 20),
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
                    _durationTimer != null && _statusText == 'Connected'
                        ? 'Live Audio • ${_formatDuration(_elapsedSeconds)}'
                        : _statusText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _durationTimer != null
                          ? Colors.greenAccent
                          : Colors.white.withValues(alpha: 0.8),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
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
                  const SizedBox(height: 28),
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
