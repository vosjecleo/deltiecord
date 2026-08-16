import 'package:flutter/material.dart';

import '../services/emoji_repository.dart';
import 'deltiecord_theme.dart';

class EmojiPickerDialog extends StatefulWidget {
  const EmojiPickerDialog({super.key});

  @override
  State<EmojiPickerDialog> createState() => _EmojiPickerDialogState();
}

class _EmojiPickerDialogState extends State<EmojiPickerDialog> {
  final _query = TextEditingController();
  List<EmojiEntry> _results = const [];
  EmojiCategory? _selectedCategory;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _search();
    _query.addListener(_search);
  }

  Future<void> _search() async {
    final generation = ++_generation;
    final familiar = EmojiRepository.instance.familiarMatches(
      _query.text,
      limit: 160,
    );
    if (mounted && generation == _generation && familiar.isNotEmpty) {
      setState(() => _results = familiar);
    }
    final catalog = await EmojiRepository.instance.search(
      _query.text,
      limit: _query.text.trim().isEmpty ? null : 160,
    );
    final results = [
      ...familiar,
      ...catalog.where(
        (entry) => !familiar.any((match) => match.emoji == entry.emoji),
      ),
    ];
    if (mounted && generation == _generation) {
      setState(() => _results = results);
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visibleResults = _selectedCategory == null
        ? _results
        : _results
              .where((entry) => entry.category == _selectedCategory)
              .toList(growable: false);
    final grouped = <EmojiCategory, List<EmojiEntry>>{};
    for (final entry in visibleResults) {
      (grouped[entry.category] ??= []).add(entry);
    }
    return AlertDialog(
      title: const Text('Emoji'),
      content: SizedBox(
        width: 540,
        height: 460,
        child: Column(
          children: [
            TextField(
              controller: _query,
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search names and aliases',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _CategoryButton(
                    label: 'All emoji',
                    icon: Icons.apps,
                    selected: _selectedCategory == null,
                    onTap: () => setState(() => _selectedCategory = null),
                  ),
                  for (final category in EmojiCategory.values)
                    _CategoryButton(
                      label: category.label,
                      icon: _categoryIcon(category),
                      selected: _selectedCategory == category,
                      onTap: () => setState(() => _selectedCategory = category),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: CustomScrollView(
                slivers: [
                  for (final category in EmojiCategory.values)
                    if (grouped[category] case final entries?) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(4, 8, 4, 5),
                          child: Text(
                            category.label,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                      ),
                      SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 54,
                              mainAxisSpacing: 2,
                              crossAxisSpacing: 2,
                            ),
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final entry = entries[index];
                          return Tooltip(
                            message:
                                '${entry.name}  :${entry.aliases.firstOrNull ?? entry.name}:',
                            child: InkWell(
                              key: ValueKey(
                                'emoji-picker-result-${entry.emoji}',
                              ),
                              onTap: () =>
                                  Navigator.of(context).pop(entry.emoji),
                              child: Center(
                                child: Text(
                                  entry.emoji,
                                  style: TextStyle(
                                    fontSize: 25,
                                    fontFamily: context.deltiecordEmojiFont,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }, childCount: entries.length),
                      ),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _categoryIcon(EmojiCategory category) => switch (category) {
    EmojiCategory.smileysAndPeople => Icons.mood,
    EmojiCategory.animalsAndNature => Icons.pets,
    EmojiCategory.foodAndDrink => Icons.restaurant,
    EmojiCategory.travelAndPlaces => Icons.travel_explore,
    EmojiCategory.activities => Icons.sports_esports,
    EmojiCategory.objects => Icons.lightbulb_outline,
    EmojiCategory.symbols => Icons.category_outlined,
    EmojiCategory.flags => Icons.flag_outlined,
  };
}

class _CategoryButton extends StatelessWidget {
  const _CategoryButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: IconButton(
      isSelected: selected,
      onPressed: onTap,
      icon: Icon(icon),
      selectedIcon: Icon(icon, color: Theme.of(context).colorScheme.primary),
    ),
  );
}
