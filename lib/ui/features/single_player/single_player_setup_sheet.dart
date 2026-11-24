import 'package:flutter/material.dart';

import '../../../core/services/app_services.dart';
import '../../../core/services/sound_service.dart';
import '../../../domain/bot_engine.dart';
import '../../../domain/game_engine.dart';
import '../../../domain/models/user_profile.dart';
import '../../core/widgets/emoji_picker_grid.dart';
import 'single_player_game_page.dart';

/// Configuration modal bottom sheet for Single Player (Player vs System) mode.
class SinglePlayerSetupSheet extends StatefulWidget {
  const SinglePlayerSetupSheet({
    super.key,
    required this.services,
    this.profile,
  });

  final AppServices services;
  final UserProfile? profile;

  @override
  State<SinglePlayerSetupSheet> createState() => _SinglePlayerSetupSheetState();
}

class _SinglePlayerSetupSheetState extends State<SinglePlayerSetupSheet> {
  BotDifficulty _difficulty = BotDifficulty.normal;
  SinglePlayerMode _mode = SinglePlayerMode.classic;
  int _boardSize = 3;
  int _bestOf = 3;
  FirstPlayerChoice _firstPlayer = FirstPlayerChoice.player;
  late String _emoji;
  bool _practiceTools = true;
  bool _showFullEmojiGrid = false;

  @override
  void initState() {
    super.initState();
    _boardSize = widget.services.preferences.favoriteBoardSize;
    _emoji = widget.profile?.preferredEmoji ?? '❌';
  }

  void _startSoloMatch() {
    widget.services.sound.play(SoundEffect.click);
    final playerName = (widget.profile?.nickname.isNotEmpty ?? false)
        ? widget.profile!.nickname
        : 'Challenger';
    final playerAvatar = widget.profile?.avatarId ?? 'astro';

    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SinglePlayerGamePage(
          services: widget.services,
          playerName: playerName,
          playerAvatar: playerAvatar,
          playerEmoji: _emoji,
          difficulty: _difficulty,
          mode: _mode,
          boardSize: _boardSize,
          bestOf: _bestOf,
          firstPlayer: _firstPlayer,
          practiceToolsEnabled: _practiceTools,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final prefs = widget.services.preferences;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          14,
          20,
          MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('🤖', style: TextStyle(fontSize: 26)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Single Player vs System',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // 1. Difficulty
              const Text(
                'System Difficulty',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final d in BotDifficulty.values)
                    ChoiceChip(
                      label: Text('${d.icon} ${d.label}'),
                      selected: _difficulty == d,
                      onSelected: (_) => setState(() => _difficulty = d),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _difficulty.subtitleForSize(_boardSize),
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              // 2. Game Mode
              const Text(
                'Game Mode',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<SinglePlayerMode>(
                  showSelectedIcon: false,
                  segments: [
                    for (final m in SinglePlayerMode.values)
                      ButtonSegment(
                        value: m,
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(m.label),
                        ),
                      ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (v) => setState(() => _mode = v.first),
                ),
              ),
              if (_mode == SinglePlayerMode.tournament) ...[
                const SizedBox(height: 12),
                const Text(
                  'Tournament Length',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: [
                      for (final b in supportedSoloBestOf)
                        ButtonSegment(
                          value: b,
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Best of $b'),
                          ),
                        ),
                    ],
                    selected: {_bestOf},
                    onSelectionChanged: (v) =>
                        setState(() => _bestOf = v.first),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              // 3. Board Size
              const Text(
                'Board Size',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: [
                    for (final s in supportedBoardSizes)
                      ButtonSegment(
                        value: s,
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('$s×$s'),
                        ),
                      ),
                  ],
                  selected: {_boardSize},
                  onSelectionChanged: (v) =>
                      setState(() => _boardSize = v.first),
                ),
              ),
              const SizedBox(height: 12),
              // 4. First Player
              const Text(
                'First Player',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<FirstPlayerChoice>(
                  showSelectedIcon: false,
                  segments: [
                    for (final fp in FirstPlayerChoice.values)
                      ButtonSegment(
                        value: fp,
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(fp.label),
                        ),
                      ),
                  ],
                  selected: {_firstPlayer},
                  onSelectionChanged: (v) =>
                      setState(() => _firstPlayer = v.first),
                ),
              ),
              const SizedBox(height: 12),
              // 5. Game Symbol (X, O, or Universal Emojis)
              Row(
                children: [
                  const Text(
                    'Your Symbol',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 10),
                  ChoiceChip(
                    label: const Text('❌ X'),
                    selected: _emoji == '❌',
                    onSelected: (_) => setState(() => _emoji = '❌'),
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: const Text('⭕ O'),
                    selected: _emoji == '⭕',
                    onSelected: (_) => setState(() => _emoji = '⭕'),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => setState(
                      () => _showFullEmojiGrid = !_showFullEmojiGrid,
                    ),
                    icon: Text(_emoji, style: const TextStyle(fontSize: 20)),
                    label: Text(_showFullEmojiGrid ? 'Hide' : 'More Emojis'),
                  ),
                ],
              ),
              if (_showFullEmojiGrid) ...[
                const SizedBox(height: 6),
                EmojiPickerGrid(
                  selectedEmoji: _emoji,
                  maxHeight: 150,
                  onSelected: (e) => setState(() => _emoji = e),
                ),
              ],
              // 6. Practice Mode & Quick Audio/Haptic/Animation Toggles
              if (_mode != SinglePlayerMode.blitz)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text(
                    'Practice Hints & Undo',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text(
                    'Enable AI move hints and undo during solo play',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: _practiceTools,
                  onChanged: (v) => setState(() => _practiceTools = v),
                ),
              ListenableBuilder(
                listenable: prefs,
                builder: (context, _) {
                  return Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      FilterChip(
                        avatar: Icon(
                          prefs.soundEnabled
                              ? Icons.volume_up_rounded
                              : Icons.volume_off_rounded,
                          size: 16,
                        ),
                        label: const Text('Sound'),
                        selected: prefs.soundEnabled,
                        showCheckmark: false,
                        onSelected: (v) => prefs.setSoundEnabled(v),
                      ),
                      FilterChip(
                        avatar: const Icon(Icons.vibration_rounded, size: 16),
                        label: const Text('Vibration'),
                        selected: prefs.hapticsEnabled,
                        showCheckmark: false,
                        onSelected: (v) => prefs.setHapticsEnabled(v),
                      ),
                      FilterChip(
                        avatar: const Icon(Icons.auto_awesome_rounded, size: 16),
                        label: const Text('Animations'),
                        selected: !prefs.reducedMotion,
                        showCheckmark: false,
                        onSelected: (v) => prefs.setReducedMotion(!v),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                  onPressed: _startSoloMatch,
                  icon: const Icon(Icons.smart_toy_rounded),
                  label: const Text(
                    'START SINGLE PLAYER',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
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
