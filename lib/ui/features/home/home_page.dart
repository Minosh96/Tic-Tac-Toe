import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/repositories/game_repository.dart';
import '../../../domain/game_engine.dart';
import '../../core/widgets/footer.dart';
import '../room/room_page.dart';

/// Landing page where players pick their nickname/emoji and create or join a room.
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.repository,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  final GameRepository repository;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _roomCodeController = TextEditingController();

  String _selectedEmoji = emojiChoices.first;
  int _boardSize = 3;
  int _bestOf = 3;
  bool _busy = false;

  @override
  void dispose() {
    _nameController.dispose();
    _roomCodeController.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _runAction(Future<void> Function() task) async {
    if (_nameController.text.trim().isEmpty) {
      _showSnack('Enter your nickname first.');
      return;
    }
    setState(() => _busy = true);
    try {
      await task();
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggleTheme() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    widget.onThemeModeChanged(isDark ? ThemeMode.light : ThemeMode.dark);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Melow Tic Tac Toe',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
            onPressed: _toggleTheme,
            icon: Icon(isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        scheme.primaryContainer,
                        scheme.tertiaryContainer,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Challenge a friend & win the cup! 🏆',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Real-time multiplayer • 3×3 to 6×6 boards • Private room chat',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(_selectedEmoji, style: const TextStyle(fontSize: 44)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '1. Your Player Profile',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _nameController,
                          maxLength: 20,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            labelText: 'Nickname',
                            hintText: 'e.g. Minosh',
                            prefixIcon: Icon(Icons.person_outline_rounded),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Choose your emoji mark',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final choice in emojiChoices)
                              ChoiceChip(
                                label: Text(
                                  choice,
                                  style: const TextStyle(fontSize: 22),
                                ),
                                selected: _selectedEmoji == choice,
                                onSelected: (_) =>
                                    setState(() => _selectedEmoji = choice),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '2. Create a Match Room',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Board size',
                                    style: Theme.of(context).textTheme.labelMedium,
                                  ),
                                  const SizedBox(height: 6),
                                  SegmentedButton<int>(
                                    showSelectedIcon: false,
                                    segments: [
                                      for (final n in supportedBoardSizes)
                                        ButtonSegment(
                                          value: n,
                                          label: Text('$n×$n'),
                                        ),
                                    ],
                                    selected: {_boardSize},
                                    onSelectionChanged: (values) =>
                                        setState(() => _boardSize = values.first),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Text(
                              'Tournament format:',
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                            const Spacer(),
                            SegmentedButton<int>(
                              showSelectedIcon: false,
                              segments: [
                                for (final b in supportedBestOf)
                                  ButtonSegment(
                                    value: b,
                                    label: Text('Best of $b'),
                                  ),
                              ],
                              selected: {_bestOf},
                              onSelectionChanged: (values) =>
                                  setState(() => _bestOf = values.first),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _runAction(() async {
                                    final code = await widget.repository.createRoom(
                                      name: _nameController.text.trim(),
                                      emoji: _selectedEmoji,
                                      size: _boardSize,
                                      bestOf: _bestOf,
                                    );
                                    if (!context.mounted) return;
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => RoomPage(
                                          code: code,
                                          repository: widget.repository,
                                        ),
                                      ),
                                    );
                                  }),
                          icon: const Icon(Icons.add_circle_outline_rounded),
                          label: const Text('Create Room / Challenge Friend'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Or Join a Friend’s Room',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _roomCodeController,
                          textCapitalization: TextCapitalization.characters,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                          ],
                          maxLength: 6,
                          decoration: const InputDecoration(
                            labelText: '6-character room code',
                            hintText: 'ABC234',
                            prefixIcon: Icon(Icons.key_rounded),
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _runAction(() async {
                                    final code =
                                        _roomCodeController.text.trim().toUpperCase();
                                    if (code.length != 6) {
                                      throw Exception(
                                        'Enter a valid 6-character room code.',
                                      );
                                    }
                                    await widget.repository.joinRoom(
                                      code: code,
                                      name: _nameController.text.trim(),
                                      emoji: _selectedEmoji,
                                    );
                                    if (!context.mounted) return;
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => RoomPage(
                                          code: code,
                                          repository: widget.repository,
                                        ),
                                      ),
                                    );
                                  }),
                          icon: const Icon(Icons.login_rounded),
                          label: const Text('Join Room'),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_busy) ...[
                  const SizedBox(height: 16),
                  const Center(child: CircularProgressIndicator()),
                ],
                const MelowFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
