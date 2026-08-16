import 'dart:async';

import 'package:flutter/material.dart';

import '../services/giphy_service.dart';
import '../services/secret_redaction.dart';
import 'deltiecord_theme.dart';

class GiphyDialog extends StatefulWidget {
  const GiphyDialog({required this.service, super.key});

  final GiphyService service;

  @override
  State<GiphyDialog> createState() => _GiphyDialogState();
}

class _GiphyDialogState extends State<GiphyDialog> {
  final _query = TextEditingController();
  List<GifSearchResult> _results = const [];
  List<GifSearchResult> _favorites = const [];
  bool _loading = false;
  String? _error;
  Timer? _debounce;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _query.addListener(_scheduleSearch);
    unawaited(_search());
  }

  void _scheduleSearch() {
    _debounce?.cancel();
    _generation++;
    _debounce = Timer(const Duration(milliseconds: 280), _search);
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final favorites = await widget.service.favorites();
      final results = query.isEmpty
          ? await widget.service.trending()
          : await widget.service.search(query);
      if (!mounted || generation != _generation) return;
      final combined = query.isEmpty
          ? [
              ...favorites,
              ...results.where(
                (gif) => !favorites.any(
                  (favorite) => favorite.shareUrl == gif.shareUrl,
                ),
              ),
            ]
          : results;
      setState(() {
        _favorites = favorites;
        _results = combined;
      });
    } catch (exception) {
      if (mounted && generation == _generation) {
        setState(() => _error = safeErrorMessage(exception));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _toggleFavorite(GifSearchResult gif) async {
    await widget.service.toggleFavorite(gif);
    if (!mounted) return;
    final favorites = await widget.service.favorites();
    if (!mounted) return;
    setState(() => _favorites = favorites);
    if (_query.text.trim().isEmpty) unawaited(_search());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Sticker / GIF'),
    content: SizedBox(
      width: 620,
      height: 500,
      child: Column(
        children: [
          TextField(
            controller: _query,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) {
              _debounce?.cancel();
              unawaited(_search());
            },
            decoration: InputDecoration(
              hintText: 'Search Giphy',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                onPressed: () {
                  _debounce?.cancel();
                  unawaited(_search());
                },
                icon: _loading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.arrow_forward),
              ),
            ),
          ),
          if (_error case final error?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                error,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _query.text.trim().isEmpty
                  ? _favorites.isEmpty
                        ? 'Trending'
                        : 'Favourites first · Trending'
                  : 'Search results',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: _loading && _results.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 6,
                          mainAxisSpacing: 6,
                        ),
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final gif = _results[index];
                      final favorite = widget.service.isFavorite(gif);
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          Tooltip(
                            message: gif.title,
                            child: InkWell(
                              onTap: () => Navigator.of(context).pop(gif),
                              child: Image.network(
                                gif.previewUrl.toString(),
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                                errorBuilder: (_, _, _) =>
                                    const ColoredBox(color: Color(0xff292a30)),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: Material(
                              color: Colors.black54,
                              borderRadius: DeltiecordCorners.borderRadius,
                              child: IconButton(
                                tooltip: favorite
                                    ? 'Remove from favourites'
                                    : 'Add to favourites',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _toggleFavorite(gif),
                                icon: Icon(
                                  favorite ? Icons.star : Icons.star_border,
                                  color: favorite
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
          const Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Powered by GIPHY',
              style: TextStyle(
                fontSize: DeltiecordTypeScale.normal,
                color: Color(0xff989aa5),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
