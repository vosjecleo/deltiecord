import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../backend/chat_backend.dart';
import '../models/chat_models.dart';
import 'deltiecord_theme.dart';

enum RoomSearchSection { messages, media, files, links }

Future<void> showRoomSearchDialog(
  BuildContext context,
  ChatBackend backend, {
  required Future<void> Function(String eventId) onOpen,
  RoomSearchSection initialSection = RoomSearchSection.messages,
}) => showDialog<void>(
  context: context,
  builder: (context) => Dialog(
    child: SizedBox(
      width: 760,
      height: 680,
      child: RoomSearchPanel(
        backend: backend,
        onOpen: onOpen,
        initialSection: initialSection,
      ),
    ),
  ),
);

Future<void> showRoomSearchSheet(
  BuildContext context,
  ChatBackend backend, {
  required Future<void> Function(String eventId) onOpen,
  RoomSearchSection initialSection = RoomSearchSection.messages,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => FractionallySizedBox(
    heightFactor: 0.9,
    child: RoomSearchPanel(
      backend: backend,
      onOpen: onOpen,
      initialSection: initialSection,
    ),
  ),
);

/// Room search keeps pagination deliberately bounded: opening a panel must not
/// turn into an unbounded history/media download.
class RoomSearchPanel extends StatefulWidget {
  const RoomSearchPanel({
    required this.backend,
    required this.onOpen,
    this.initialSection = RoomSearchSection.messages,
    super.key,
  });

  final ChatBackend backend;
  final Future<void> Function(String eventId) onOpen;
  final RoomSearchSection initialSection;

  @override
  State<RoomSearchPanel> createState() => _RoomSearchPanelState();
}

class _RoomSearchPanelState extends State<RoomSearchPanel>
    with SingleTickerProviderStateMixin {
  static const _maximumPaginationPasses = 3;
  static const _maximumResults = 120;

  final _query = TextEditingController();
  late final TabController _tabs;
  Timer? _debounce;
  List<ChatMessage> _serverResults = const [];
  bool _searching = false;
  bool _loadingOlder = false;
  int _paginationPasses = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: RoomSearchSection.values.length,
      vsync: this,
      initialIndex: widget.initialSection.index,
    )..addListener(_tabChanged);
    if (widget.initialSection != RoomSearchSection.messages) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadOlder());
    }
  }

  void _tabChanged() {
    if (!_tabs.indexIsChanging &&
        _tabs.index != RoomSearchSection.messages.index &&
        _paginationPasses == 0) {
      _loadOlder();
    }
    if (mounted) setState(() {});
  }

  void _queryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _search);
    setState(() {});
  }

  Future<void> _search() async {
    final value = _query.text.trim();
    if (value.isEmpty) {
      setState(() {
        _serverResults = const [];
        _error = null;
      });
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final found = await widget.backend.searchRoomHistory(value);
      if (mounted) setState(() => _serverResults = found);
    } catch (_) {
      if (mounted) setState(() => _error = 'Search failed. Try again.');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder ||
        _paginationPasses >= _maximumPaginationPasses ||
        !widget.backend.canLoadMoreHistory) {
      return;
    }
    setState(() => _loadingOlder = true);
    try {
      await widget.backend.loadMoreHistory();
      _paginationPasses++;
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  void _addFilter(String filter) {
    final current = _query.text.trim();
    _query.text = current.isEmpty ? '$filter ' : '$current $filter ';
    _query.selection = TextSelection.collapsed(offset: _query.text.length);
    _queryChanged(_query.text);
  }

  List<ChatMessage> get _results {
    final byId = <String, ChatMessage>{
      for (final message in widget.backend.messages) message.id: message,
      for (final message in _serverResults) message.id: message,
    };
    final query = _query.text.trim().toLowerCase();
    final section = RoomSearchSection.values[_tabs.index];
    final results = byId.values.where((message) {
      if (query.isNotEmpty &&
          !message.body.toLowerCase().contains(query) &&
          !message.sender.toLowerCase().contains(query)) {
        // Structured filters and remote text search are evaluated by backend.
        if (!_serverResults.any((item) => item.id == message.id)) return false;
      }
      return switch (section) {
        RoomSearchSection.messages => true,
        RoomSearchSection.media =>
          message.attachment?.kind == AttachmentKind.image ||
              message.attachment?.kind == AttachmentKind.video,
        RoomSearchSection.files =>
          message.attachment != null &&
              message.attachment?.kind != AttachmentKind.image &&
              message.attachment?.kind != AttachmentKind.video,
        RoomSearchSection.links =>
          message.linkPreviews.isNotEmpty ||
              RegExp(r'https?://', caseSensitive: false).hasMatch(message.body),
      };
    }).toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return results.take(_maximumResults).toList(growable: false);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tabs.dispose();
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    final media = _tabs.index == RoomSearchSection.media.index;
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: TextField(
              controller: _query,
              autofocus: widget.initialSection == RoomSearchSection.messages,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search this room',
                suffixIcon: Icon(Icons.tune),
              ),
              onChanged: _queryChanged,
              onSubmitted: (_) => _search(),
            ),
          ),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final filter in const [
                  'from:',
                  'before:',
                  'after:',
                  'has:image',
                  'has:file',
                  'has:link',
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ActionChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(filter),
                      onPressed: () => _addFilter(filter),
                    ),
                  ),
              ],
            ),
          ),
          TabBar(
            controller: _tabs,
            tabs: const [
              Tab(text: 'Messages'),
              Tab(text: 'Media'),
              Tab(text: 'Files'),
              Tab(text: 'Links'),
            ],
          ),
          if (_searching || _loadingOlder)
            const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(8), child: Text(_error!)),
          Expanded(
            child: results.isEmpty
                ? Center(
                    child: Text(
                      _paginationPasses == 0
                          ? 'No matching loaded messages.'
                          : 'No matching messages found.',
                      style: TextStyle(color: context.deltiecord.muted),
                    ),
                  )
                : media
                ? GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 190,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                    itemCount: results.length,
                    itemBuilder: (context, index) => _MediaResult(
                      backend: widget.backend,
                      message: results[index],
                      onOpen: widget.onOpen,
                    ),
                  )
                : ListView.builder(
                    itemCount: results.length,
                    itemBuilder: (context, index) {
                      final message = results[index];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.chat_bubble_outline),
                        title: Text(message.sender),
                        subtitle: Text(
                          message.attachment?.name ?? message.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () async {
                          Navigator.pop(context);
                          await widget.onOpen(message.id);
                        },
                      );
                    },
                  ),
          ),
          if (_paginationPasses < _maximumPaginationPasses &&
              widget.backend.canLoadMoreHistory)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              child: OutlinedButton.icon(
                onPressed: _loadingOlder ? null : _loadOlder,
                icon: const Icon(Icons.history),
                label: Text(
                  _paginationPasses == 0
                      ? 'Search older messages'
                      : 'Search one more older page',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MediaResult extends StatelessWidget {
  const _MediaResult({
    required this.backend,
    required this.message,
    required this.onOpen,
  });

  final ChatBackend backend;
  final ChatMessage message;
  final Future<void> Function(String eventId) onOpen;

  Future<Uint8List?> _thumbnail() async {
    final attachment = message.attachment;
    if (attachment == null) return null;
    final useThumbnail = attachment.hasThumbnail;
    final size = useThumbnail ? attachment.thumbnailSize : attachment.size;
    final width = useThumbnail ? attachment.thumbnailWidth : attachment.width;
    final height = useThumbnail
        ? attachment.thumbnailHeight
        : attachment.height;
    if (size == null ||
        size <= 0 ||
        size > 2 * 1024 * 1024 ||
        width == null ||
        height == null ||
        width <= 0 ||
        height <= 0 ||
        width > 4096 ||
        height > 4096 ||
        width * height > 8000000) {
      return null;
    }
    final bytes = await backend.downloadAttachment(
      message.id,
      thumbnail: useThumbnail,
    );
    return bytes.length <= 2 * 1024 * 1024 ? bytes : null;
  }

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () async {
      Navigator.pop(context);
      await onOpen(message.id);
    },
    child: ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ColoredBox(
        color: context.deltiecord.elevated,
        child: FutureBuilder<Uint8List?>(
          future: _thumbnail(),
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              return Image.memory(snapshot.data!, fit: BoxFit.cover);
            }
            return Center(
              child: Icon(
                message.attachment?.kind == AttachmentKind.video
                    ? Icons.play_circle_outline
                    : Icons.image_outlined,
                size: 38,
              ),
            );
          },
        ),
      ),
    ),
  );
}
