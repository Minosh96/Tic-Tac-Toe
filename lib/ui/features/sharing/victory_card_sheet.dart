import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../domain/game_engine.dart';
import '../../core/app_theme.dart';
import '../../core/widgets/melow_avatar.dart';
import '../../core/widgets/melow_logo.dart';

/// Privacy-safe Victory Card preview & local PNG share sheet.
/// Never includes room codes, private chat messages, or Firebase UIDs.
class VictoryCardSheet extends StatefulWidget {
  const VictoryCardSheet({
    super.key,
    required this.winnerName,
    required this.winnerAvatar,
    required this.opponentName,
    required this.scoreText,
    required this.gameMode,
    required this.boardSize,
    required this.isTournamentChampion,
  });

  final String winnerName;
  final String winnerAvatar;
  final String opponentName;
  final String scoreText;
  final GameMode gameMode;
  final int boardSize;
  final bool isTournamentChampion;

  @override
  State<VictoryCardSheet> createState() => _VictoryCardSheetState();
}

class _VictoryCardSheetState extends State<VictoryCardSheet> {
  final GlobalKey _cardKey = GlobalKey();
  bool _hideOpponent = false;
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
        throw Exception('Could not encode victory card PNG.');
      }
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/melow_victory_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(byteData.buffer.asUint8List());
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          text: widget.isTournamentChampion
              ? '${widget.winnerName} won the Melow Cup in Melow Tic Tac Toe! 🏆'
              : '${widget.winnerName} scored a victory in Melow Tic Tac Toe! 🎉',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not share victory card: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
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
              'Share Victory Card',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            RepaintBoundary(
              key: _cardKey,
              child: VictoryCardPreview(
                winnerName: widget.winnerName,
                winnerAvatar: widget.winnerAvatar,
                opponentName: _hideOpponent ? null : widget.opponentName,
                scoreText: widget.scoreText,
                gameMode: widget.gameMode,
                boardSize: widget.boardSize,
                isTournamentChampion: widget.isTournamentChampion,
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Hide opponent nickname'),
              subtitle: const Text(
                'Room codes, UIDs, and chat are never included.',
                style: TextStyle(fontSize: 12),
              ),
              value: _hideOpponent,
              onChanged: (v) => setState(() => _hideOpponent = v),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _exporting ? null : _sharePng,
              icon: _exporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.share_rounded),
              label: Text(_exporting ? 'Preparing PNG…' : 'Share Victory Card'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pure renderable Victory Card widget (also directly testable in widget tests).
class VictoryCardPreview extends StatelessWidget {
  const VictoryCardPreview({
    super.key,
    required this.winnerName,
    required this.winnerAvatar,
    required this.opponentName,
    required this.scoreText,
    required this.gameMode,
    required this.boardSize,
    required this.isTournamentChampion,
  });

  final String winnerName;
  final String winnerAvatar;
  final String? opponentName;
  final String scoreText;
  final GameMode gameMode;
  final int boardSize;
  final bool isTournamentChampion;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.darkBackground, Color(0xFF281B5A), Color(0xFF152546)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppTheme.goldAccent.withValues(alpha: 0.7),
          width: 2,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const MelowLogo(size: 36, borderRadius: 10, showGlow: false),
              const SizedBox(width: 10),
              const Text(
                'Melow Tic Tac Toe',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.purpleAccent.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  '${gameMode.label} • $boardSize×$boardSize',
                  style: const TextStyle(
                    color: AppTheme.cyanAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text('🏆', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 4),
          Text(
            isTournamentChampion ? 'CHAMPION!' : 'VICTORY!',
            style: const TextStyle(
              color: AppTheme.goldAccent,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              MelowAvatar(
                avatarId: winnerAvatar,
                size: 46,
                borderColor: AppTheme.goldAccent,
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    winnerName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (opponentName != null && opponentName!.isNotEmpty)
                    Text(
                      'vs $opponentName',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 13,
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              'Final Score: $scoreText',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Developed at Melow Labs',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 10,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}
