import 'package:flutter/material.dart';

import '../../../domain/game_engine.dart';

/// Category-tabbed Emoji Picker supporting 100+ emojis (Classic, Boy/Girl/People,
/// Funny, Animals, Fun) cleanly on small & large Android phones.
class EmojiPickerGrid extends StatefulWidget {
  const EmojiPickerGrid({
    super.key,
    required this.selectedEmoji,
    required this.onSelected,
    this.maxHeight = 190,
  });

  final String selectedEmoji;
  final ValueChanged<String> onSelected;
  final double maxHeight;

  @override
  State<EmojiPickerGrid> createState() => _EmojiPickerGridState();
}

class _EmojiPickerGridState extends State<EmojiPickerGrid> {
  String _category = 'All';

  @override
  Widget build(BuildContext context) {
    final categories = ['All', ...emojiCategories.keys];
    final items = _category == 'All'
        ? emojiChoices
        : (emojiCategories[_category] ?? emojiChoices);
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final cat in categories)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(
                      cat,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    selected: _category == cat,
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => _category = cat),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: widget.maxHeight),
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final emoji in items)
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => widget.onSelected(emoji),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: widget.selectedEmoji == emoji
                            ? scheme.primaryContainer
                            : scheme.surfaceContainerHighest
                                .withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: widget.selectedEmoji == emoji
                              ? scheme.primary
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Text(emoji, style: const TextStyle(fontSize: 22)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
