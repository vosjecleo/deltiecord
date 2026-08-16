import 'package:flutter/material.dart';

import '../services/timezone_catalog.dart';

class TimezonePickerDialog extends StatefulWidget {
  const TimezonePickerDialog({this.selected, super.key});

  final String? selected;

  @override
  State<TimezonePickerDialog> createState() => _TimezonePickerDialogState();
}

class _TimezonePickerDialogState extends State<TimezonePickerDialog> {
  final _search = TextEditingController();
  late List<String> _matches = TimezoneCatalog.names;

  @override
  void initState() {
    super.initState();
    _search.addListener(_filter);
  }

  void _filter() {
    final query = _search.text.trim().toLowerCase();
    setState(() {
      _matches = query.isEmpty
          ? TimezoneCatalog.names
          : TimezoneCatalog.names
                .where(
                  (zone) =>
                      zone.toLowerCase().contains(query) ||
                      TimezoneCatalog.offsetLabel(
                        zone,
                      ).toLowerCase().contains(query),
                )
                .toList(growable: false);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Choose timezone'),
    content: SizedBox(
      width: 520,
      height: 520,
      child: Column(
        children: [
          TextField(
            key: const Key('timezone-search'),
            controller: _search,
            autofocus: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search city, region, or UTC offset',
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: _matches.length,
              itemBuilder: (context, index) {
                final timezone = _matches[index];
                return ListTile(
                  dense: true,
                  selected: timezone == widget.selected,
                  title: Text(timezone),
                  trailing: Text(TimezoneCatalog.offsetLabel(timezone)),
                  onTap: () => Navigator.of(context).pop(timezone),
                );
              },
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(''),
        child: const Text('Do not show a timezone'),
      ),
      TextButton(
        onPressed: Navigator.of(context).pop,
        child: const Text('Cancel'),
      ),
    ],
  );
}
