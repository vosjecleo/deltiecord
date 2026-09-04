import 'dart:async';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart' as file_picker;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../backend/chat_backend.dart';
import '../models/chat_models.dart';
import '../services/favourite_reactions_store.dart';
import '../services/custom_emoji.dart';
import '../services/telegram_sticker_service.dart';
import 'deltiecord_theme.dart';

Future<PollDraft?> showPollComposer(BuildContext context) =>
    showDialog<PollDraft>(
      context: context,
      builder: (context) => const _PollComposerDialog(),
    );

Future<DateTime?> showSchedulePicker(BuildContext context) async {
  final now = DateTime.now();
  final date = await showDatePicker(
    context: context,
    initialDate: now,
    firstDate: now,
    lastDate: now.add(const Duration(days: 365)),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
  );
  if (time == null) return null;
  final result = DateTime(
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
  );
  return result.isAfter(now) ? result : now.add(const Duration(minutes: 1));
}

Future<void> showRoomNotificationControls(
  BuildContext context,
  ChatBackend backend,
  RoomSummary room,
) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Wrap(
        children: [
          const ListTile(title: Text('Room notifications')),
          ListTile(
            leading: Icon(
              room.notificationMode == RoomNotificationMode.allMessages
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
            ),
            title: const Text('All messages'),
            onTap: () => Navigator.pop(context, 'all'),
          ),
          ListTile(
            leading: Icon(
              room.notificationMode == RoomNotificationMode.mentionsOnly
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
            ),
            title: const Text('Mentions only'),
            onTap: () => Navigator.pop(context, 'mentions'),
          ),
          ListTile(
            leading: Icon(
              room.notificationMode == RoomNotificationMode.muted
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
            ),
            title: const Text('Mute'),
            onTap: () => Navigator.pop(context, 'mute'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Mute for 1 hour'),
            onTap: () => Navigator.pop(context, 'hour'),
          ),
          ListTile(
            leading: const Icon(Icons.bedtime_outlined),
            title: const Text('Mute until tomorrow'),
            onTap: () => Navigator.pop(context, 'tomorrow'),
          ),
          ListTile(
            leading: Icon(
              room.markedUnread
                  ? Icons.mark_chat_read_outlined
                  : Icons.mark_chat_unread_outlined,
            ),
            title: Text(room.markedUnread ? 'Mark read' : 'Mark unread'),
            onTap: () => Navigator.pop(context, 'unread'),
          ),
        ],
      ),
    ),
  );
  if (action == null) return;
  switch (action) {
    case 'all':
      await backend.setRoomNotificationMode(
        room.id,
        RoomNotificationMode.allMessages,
      );
    case 'mentions':
      await backend.setRoomNotificationMode(
        room.id,
        RoomNotificationMode.mentionsOnly,
      );
    case 'mute':
      await backend.setRoomNotificationMode(
        room.id,
        RoomNotificationMode.muted,
      );
    case 'hour':
      await backend.muteRoomUntil(
        room.id,
        DateTime.now().add(const Duration(hours: 1)),
      );
    case 'tomorrow':
      final now = DateTime.now();
      await backend.muteRoomUntil(
        room.id,
        DateTime(now.year, now.month, now.day + 1, 9),
      );
    case 'unread':
      await backend.markRoomUnread(room.id, !room.markedUnread);
  }
}

Future<StickerSummary?> showStickerPicker(
  BuildContext context,
  ChatBackend backend,
) async {
  await backend.refreshStickerPacks();
  await FavouriteReactionsStore.instance.load();
  if (!context.mounted) return null;
  return _showStickerSurface<StickerSummary>(
    context,
    desktopWidth: 640,
    desktopHeight: 600,
    mobileHeightFactor: 0.82,
    surfaceKey: const ValueKey('sticker-picker-surface'),
    builder: (context) => _StickerPickerContents(backend: backend),
  );
}

class _StickerPickerContents extends StatefulWidget {
  const _StickerPickerContents({required this.backend});

  final ChatBackend backend;

  @override
  State<_StickerPickerContents> createState() => _StickerPickerContentsState();
}

class _StickerPickerContentsState extends State<_StickerPickerContents> {
  String _query = '';

  List<StickerPackSummary> _packs() {
    final favouriteStickers = widget.backend.stickerPacks
        .expand((pack) => pack.stickers)
        .where(
          (sticker) =>
              sticker.assetType == StickerAssetType.sticker &&
              FavouriteReactionsStore.instance.isStickerFavourite(
                sticker.mxcUri,
              ),
        )
        .toList(growable: false);
    final query = _query.trim().toLowerCase();
    return <StickerPackSummary>[
      if (favouriteStickers.isNotEmpty)
        StickerPackSummary(
          id: 'favourites',
          name: 'Favourites',
          stickers: favouriteStickers,
        ),
      ...widget.backend.stickerPacks.map((pack) {
        final stickers = pack.stickers
            .where((sticker) {
              if (sticker.assetType != StickerAssetType.sticker) return false;
              return query.isEmpty ||
                  sticker.name.toLowerCase().contains(query);
            })
            .toList(growable: false);
        return StickerPackSummary(
          id: pack.id,
          name: pack.name,
          stickers: stickers,
          roomScoped: pack.roomScoped,
          sourceRoomId: pack.sourceRoomId,
          stateKey: pack.stateKey,
          canManage: pack.canManage,
          globallyEnabled: pack.globallyEnabled,
        );
      }),
    ].where((pack) => pack.stickers.isNotEmpty).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      FavouriteReactionsStore.instance,
      widget.backend,
    ]),
    builder: (context, _) {
      final packs = _packs();
      final palette = Theme.of(context).extension<DeltiecordPalette>();
      final surface =
          palette?.surface ?? Theme.of(context).colorScheme.surfaceContainer;
      return Material(
        color: surface,
        child: CustomScrollView(
          key: const ValueKey('sticker-picker-scroll'),
          slivers: [
            SliverAppBar(
              pinned: true,
              automaticallyImplyLeading: false,
              backgroundColor: surface,
              surfaceTintColor: Colors.transparent,
              titleSpacing: 10,
              title: TextField(
                key: const ValueKey('sticker-search'),
                onChanged: (value) => setState(() => _query = value),
                decoration: const InputDecoration(
                  hintText: 'Search stickers',
                  prefixIcon: Icon(Icons.search, size: 20),
                  isDense: true,
                ),
              ),
              actions: [
                IconButton(
                  tooltip: 'Manage sticker packs',
                  onPressed: () async {
                    await _manageStickerPacks(context, widget.backend);
                    await widget.backend.refreshStickerPacks();
                  },
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                ),
                const SizedBox(width: 4),
              ],
            ),
            if (packs.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: FilledButton.icon(
                    onPressed: () =>
                        _manageStickerPacks(context, widget.backend),
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: Text(
                      _query.isEmpty
                          ? 'Create or import a pack'
                          : 'No matching stickers',
                    ),
                  ),
                ),
              )
            else
              for (final pack in packs) ...[
                SliverToBoxAdapter(
                  child: _StickerPackHeader(
                    backend: widget.backend,
                    pack: pack,
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                  sliver: SliverGrid.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 84,
                          mainAxisSpacing: 6,
                          crossAxisSpacing: 6,
                        ),
                    itemCount: pack.stickers.length,
                    itemBuilder: (context, index) {
                      final sticker = pack.stickers[index];
                      final favourite = FavouriteReactionsStore.instance
                          .isStickerFavourite(sticker.mxcUri);
                      return InkWell(
                        key: ValueKey('sticker-${pack.id}-${sticker.id}'),
                        onTap: () => Navigator.pop(context, sticker),
                        onLongPress: () => FavouriteReactionsStore.instance
                            .toggleSticker(sticker.mxcUri),
                        borderRadius: DeltiecordCorners.borderRadius,
                        child: Tooltip(
                          message: sticker.name,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: _StickerPreviewImage(
                                    backend: widget.backend,
                                    sticker: sticker,
                                  ),
                                ),
                              ),
                              if (favourite)
                                const Positioned(
                                  right: 1,
                                  top: 1,
                                  child: Icon(Icons.star, size: 14),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
          ],
        ),
      );
    },
  );
}

class _StickerPackHeader extends StatelessWidget {
  const _StickerPackHeader({required this.backend, required this.pack});

  final ChatBackend backend;
  final StickerPackSummary pack;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    contentPadding: const EdgeInsets.only(left: 12, right: 4),
    title: Text(pack.name, style: const TextStyle(fontWeight: FontWeight.w700)),
    trailing: pack.id == 'favourites'
        ? null
        : PopupMenuButton<String>(
            tooltip: 'Pack options',
            onSelected: (action) async {
              if (action == 'toggle') {
                await backend.setStickerPackGloballyEnabled(
                  pack,
                  !pack.globallyEnabled,
                );
              } else if (action == 'delete') {
                await _confirmDeleteStickerPack(context, backend, pack);
              }
            },
            itemBuilder: (context) => [
              if (pack.sourceRoomId != null)
                PopupMenuItem(
                  value: 'toggle',
                  child: Text(
                    pack.globallyEnabled
                        ? 'Remove from my account'
                        : 'Use pack everywhere',
                  ),
                ),
              if (pack.canManage)
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete pack'),
                ),
            ],
          ),
  );
}

Future<void> showStickerPackForMessage(
  BuildContext context,
  ChatBackend backend, {
  required String messageId,
  required ChatAttachment attachment,
}) async {
  await backend.refreshStickerPacks();
  final reference = await backend.getAttachmentReference(messageId);
  if (!context.mounted) return;
  final pack = backend.stickerPacks.where((candidate) {
    if (attachment.stickerPackId != null &&
        candidate.id == attachment.stickerPackId) {
      return true;
    }
    return reference != null &&
        candidate.stickers.any(
          (sticker) => sticker.mxcUri.toString() == reference,
        );
  }).firstOrNull;
  if (pack == null) {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                attachment.stickerPackName ?? 'Sticker',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'This message does not expose an accessible Matrix image '
                'pack. The sticker can still be viewed in the timeline.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
    return;
  }
  final action = await _showStickerSurface<String>(
    context,
    desktopWidth: 520,
    desktopHeight: 480,
    mobileHeightFactor: 0.62,
    surfaceKey: const ValueKey('message-sticker-pack-surface'),
    builder: (context) => Material(
      color:
          Theme.of(context).extension<DeltiecordPalette>()?.surface ??
          Theme.of(context).colorScheme.surfaceContainer,
      child: Column(
        children: [
          ListTile(
            title: Text(
              pack.name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text('${pack.stickers.length} items'),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 84,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
              ),
              itemCount: pack.stickers.length,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.all(4),
                child: _StickerPreviewImage(
                  backend: backend,
                  sticker: pack.stickers[index],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
                if (pack.sourceRoomId != null) ...[
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(context, 'toggle'),
                    icon: Icon(pack.globallyEnabled ? Icons.remove : Icons.add),
                    label: Text(
                      pack.globallyEnabled
                          ? 'Remove from my account'
                          : 'Add to my account',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
  if (action == 'toggle') {
    await backend.setStickerPackGloballyEnabled(pack, !pack.globallyEnabled);
  }
}

/// Sticker management is a compact dialog on desktop and a draggable sheet on
/// Android. Keeping presentation here prevents mobile sheet geometry from
/// leaking into wide desktop windows while giving long action lists one
/// bounded, scrollable viewport on phones.
Future<T?> _showStickerSurface<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  required double desktopWidth,
  required double desktopHeight,
  required double mobileHeightFactor,
  required Key surfaceKey,
}) {
  if (defaultTargetPlatform == TargetPlatform.android) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => FractionallySizedBox(
        key: surfaceKey,
        heightFactor: mobileHeightFactor,
        child: builder(sheetContext),
      ),
    );
  }
  return showDialog<T>(
    context: context,
    builder: (dialogContext) {
      final viewport = MediaQuery.sizeOf(dialogContext);
      return Dialog(
        key: surfaceKey,
        child: SizedBox(
          width: min(desktopWidth, max(280, viewport.width - 64)),
          height: min(desktopHeight, max(280, viewport.height - 64)),
          child: builder(dialogContext),
        ),
      );
    },
  );
}

class _StickerPreviewImage extends StatefulWidget {
  const _StickerPreviewImage({required this.backend, required this.sticker});

  final ChatBackend backend;
  final StickerSummary sticker;

  @override
  State<_StickerPreviewImage> createState() => _StickerPreviewImageState();
}

class _StickerPreviewImageState extends State<_StickerPreviewImage> {
  late Future<Uint8List?> _preview;

  @override
  void initState() {
    super.initState();
    _preview = widget.backend.loadStickerPreview(widget.sticker);
  }

  @override
  void didUpdateWidget(covariant _StickerPreviewImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sticker.mxcUri != widget.sticker.mxcUri ||
        oldWidget.backend != widget.backend) {
      _preview = widget.backend.loadStickerPreview(widget.sticker);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: _preview,
    builder: (context, snapshot) {
      final bytes = snapshot.data;
      if (bytes != null) return Image.memory(bytes, fit: BoxFit.contain);
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(
          child: SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      }
      return Center(
        child: Text(
          widget.sticker.name,
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      );
    },
  );
}

Future<void> _manageStickerPacks(
  BuildContext context,
  ChatBackend backend,
) async {
  final action = await _showStickerSurface<String>(
    context,
    desktopWidth: 560,
    desktopHeight: 610,
    mobileHeightFactor: 0.88,
    surfaceKey: const ValueKey('sticker-pack-manager-surface'),
    builder: (context) => SafeArea(
      child: ListView(
        key: const ValueKey('sticker-pack-manager-list'),
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          const ListTile(
            title: Text('Sticker packs'),
            subtitle: Text(
              'Personal packs use the Matrix image-pack format and work in '
              'compatible clients such as FluffyChat. Pack media is uploaded '
              'to your homeserver and is not room end-to-end encrypted.',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.collections_outlined),
            title: const Text('Create sticker pack'),
            onTap: () => Navigator.pop(context, 'create-sticker'),
          ),
          ListTile(
            leading: const Icon(Icons.folder_zip_outlined),
            title: const Text('Import ZIP'),
            subtitle: const Text('Up to 120 PNG, JPEG, GIF or WebP files'),
            onTap: () => Navigator.pop(context, 'import-sticker'),
          ),
          ListTile(
            leading: const Icon(Icons.send_outlined),
            title: const Text('Import from Telegram'),
            subtitle: const Text('Paste a public static sticker-pack link'),
            onTap: () => Navigator.pop(context, 'telegram-sticker'),
          ),
          ListTile(
            leading: const Icon(Icons.add_reaction_outlined),
            title: const Text('Create custom emoji pack'),
            subtitle: const Text('Up to 120 images, 128×128 and 256 KiB each'),
            onTap: () => Navigator.pop(context, 'create-emoji'),
          ),
          ListTile(
            leading: const Icon(Icons.folder_zip_outlined),
            title: const Text('Import emoji ZIP'),
            subtitle: const Text('PNG, JPEG, GIF or WebP'),
            onTap: () => Navigator.pop(context, 'import-emoji'),
          ),
          ListTile(
            leading: const Icon(Icons.send_outlined),
            title: const Text('Import Telegram pack as emoji'),
            onTap: () => Navigator.pop(context, 'telegram-emoji'),
          ),
          if (backend.stickerPacks.any((pack) => pack.canManage))
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete a pack'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  if (action == 'delete') {
    await _deleteStickerPack(context, backend);
    return;
  }
  final assetType = action.endsWith('-emoji')
      ? StickerAssetType.emoji
      : StickerAssetType.sticker;
  if (action.startsWith('telegram-')) {
    await _importTelegramStickerPack(context, backend, assetType: assetType);
    return;
  }
  try {
    final selectedItems = action.startsWith('create-')
        ? await _pickStickerImages()
        : await _pickStickerZip();
    if (selectedItems == null || selectedItems.isEmpty || !context.mounted) {
      return;
    }
    final items = assetType == StickerAssetType.emoji
        ? await _prepareEmojiItems(context, selectedItems)
        : _asAssetType(selectedItems, assetType);
    if (items == null || !context.mounted) return;
    final name = await _askStickerPackName(context);
    if (name == null || !context.mounted) return;
    final draft = StickerPackDraft(name: name, stickers: items);
    final destination = await _chooseStickerPackDestination(context, backend);
    if (destination == _cancelledPackDestination) return;
    if (destination == null) {
      await backend.savePersonalStickerPack(draft);
    } else {
      await backend.saveRoomStickerPack(destination, draft);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Personal sticker pack saved.')),
      );
    }
  } catch (exception) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sticker import failed: $exception')),
      );
    }
  }
}

Future<List<StickerDraftItem>?> _pickStickerImages() async {
  final result = await file_picker.FilePicker.pickFiles(
    type: file_picker.FileType.image,
    allowMultiple: true,
    withData: true,
  );
  if (result == null) return null;
  if (result.files.length > StickerPackDraft.maximumItems) {
    throw StateError('Sticker packs are limited to 120 images.');
  }
  if (result.files.any((file) => file.size > 5 * 1024 * 1024) ||
      result.files.fold<int>(0, (total, file) => total + file.size) >
          StickerPackDraft.maximumBytes) {
    throw StateError('Sticker files exceed the safe import limit.');
  }
  return result.files
      .map((file) {
        final bytes = file.bytes;
        if (bytes == null) throw StateError('Could not read ${file.name}.');
        return StickerDraftItem(
          shortcode: _stickerShortcode(file.name),
          bytes: bytes,
          mimeType: _stickerMime(file.name),
        );
      })
      .toList(growable: false);
}

Future<List<StickerDraftItem>?> _pickStickerZip() async {
  final result = await file_picker.FilePicker.pickFiles(
    type: file_picker.FileType.custom,
    allowedExtensions: const ['zip'],
    withData: true,
  );
  final bytes = result?.files.single.bytes;
  if (bytes == null) return null;
  if (bytes.length > 64 * 1024 * 1024) {
    throw StateError('Sticker ZIPs are limited to 64 MiB.');
  }
  final archive = ZipDecoder().decodeBytes(bytes, verify: true);
  final candidates = archive.files
      .where((file) => file.isFile && _isStickerImage(file.name))
      .take(StickerPackDraft.maximumItems + 1)
      .toList(growable: false);
  if (candidates.length > StickerPackDraft.maximumItems ||
      candidates.any((file) => file.size > 5 * 1024 * 1024) ||
      candidates.fold<int>(0, (total, file) => total + file.size) >
          StickerPackDraft.maximumBytes) {
    throw StateError('Sticker ZIP expands beyond the safe import limit.');
  }
  return candidates
      .map((file) {
        final content = Uint8List.fromList(file.content);
        return StickerDraftItem(
          shortcode: _stickerShortcode(file.name),
          bytes: content,
          mimeType: _stickerMime(file.name),
        );
      })
      .toList(growable: false);
}

Future<String?> _askStickerPackName(
  BuildContext context, {
  String initialValue = '',
}) async {
  final controller = TextEditingController(text: initialValue);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Pack name'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 80,
        decoration: const InputDecoration(hintText: 'My stickers'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result?.isEmpty == false ? result : null;
}

const _cancelledPackDestination = '__cancelled__';

List<StickerDraftItem> _asAssetType(
  List<StickerDraftItem> items,
  StickerAssetType assetType,
) => [
  for (final item in items)
    StickerDraftItem(
      shortcode: item.shortcode,
      bytes: item.bytes,
      mimeType: item.mimeType,
      width: item.width,
      height: item.height,
      assetType: assetType,
    ),
];

Future<List<StickerDraftItem>?> _prepareEmojiItems(
  BuildContext context,
  List<StickerDraftItem> items,
) async {
  final needsResize = <StickerDraftItem>[];
  for (final item in items) {
    try {
      validateCustomEmojiAsset(item.bytes, item.mimeType);
    } catch (_) {
      needsResize.add(item);
    }
  }
  var filter = CustomEmojiResizeFilter.bicubic;
  if (needsResize.isNotEmpty) {
    final selected = await _chooseEmojiResizeFilter(context, needsResize.first);
    if (selected == null) return null;
    filter = selected;
  }

  final prepared = <StickerDraftItem>[];
  for (final item in items) {
    final result = await compute(_prepareEmojiInIsolate, (
      item.bytes,
      item.mimeType,
      filter.index,
    ));
    prepared.add(
      StickerDraftItem(
        shortcode: item.shortcode,
        bytes: result.bytes,
        mimeType: result.mimeType,
        width: result.width,
        height: result.height,
        assetType: StickerAssetType.emoji,
      ),
    );
  }
  return prepared;
}

PreparedCustomEmoji _prepareEmojiInIsolate((Uint8List, String, int) request) =>
    prepareCustomEmojiAsset(
      request.$1,
      request.$2,
      filter: CustomEmojiResizeFilter.values[request.$3],
    );

Future<CustomEmojiResizeFilter?> _chooseEmojiResizeFilter(
  BuildContext context,
  StickerDraftItem example,
) => showDialog<CustomEmojiResizeFilter>(
  context: context,
  builder: (context) => _EmojiResizeDialog(example: example),
);

class _EmojiResizeDialog extends StatefulWidget {
  const _EmojiResizeDialog({required this.example});

  final StickerDraftItem example;

  @override
  State<_EmojiResizeDialog> createState() => _EmojiResizeDialogState();
}

class _EmojiResizeDialogState extends State<_EmojiResizeDialog> {
  var _filter = CustomEmojiResizeFilter.bicubic;

  Future<PreparedCustomEmoji> _preview() => compute(_prepareEmojiInIsolate, (
    widget.example.bytes,
    widget.example.mimeType,
    _filter.index,
  ));

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Resize custom emoji'),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Images larger than 128×128 will keep their aspect ratio, fit '
            'inside a centred 128×128 canvas, and never be stretched.',
          ),
          const SizedBox(height: 12),
          SizedBox.square(
            dimension: 128,
            child: FutureBuilder<PreparedCustomEmoji>(
              future: _preview(),
              builder: (context, snapshot) {
                final result = snapshot.data;
                return result == null
                    ? const Center(child: CircularProgressIndicator())
                    : DecoratedBox(
                        decoration: BoxDecoration(
                          color: context.deltiecord.elevated,
                          borderRadius: DeltiecordCorners.borderRadius,
                        ),
                        child: Image.memory(result.bytes, fit: BoxFit.contain),
                      );
              },
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<CustomEmojiResizeFilter>(
            segments: const [
              ButtonSegment(
                value: CustomEmojiResizeFilter.bicubic,
                label: Text('Bicubic'),
              ),
              ButtonSegment(
                value: CustomEmojiResizeFilter.bilinear,
                label: Text('Bilinear'),
              ),
            ],
            selected: {_filter},
            onSelectionChanged: (value) =>
                setState(() => _filter = value.single),
          ),
          const SizedBox(height: 6),
          Text(
            _filter == CustomEmojiResizeFilter.bicubic
                ? 'Smoother; recommended for artwork'
                : 'Slightly sharper and faster',
          ),
          if (const {
            'image/gif',
            'image/webp',
          }.contains(widget.example.mimeType))
            const Text(
              'Oversized animated images are converted to a static PNG.',
              style: TextStyle(fontSize: DeltiecordTypeScale.normal),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _filter),
        child: const Text('Resize and continue'),
      ),
    ],
  );
}

Future<String?> _chooseStickerPackDestination(
  BuildContext context,
  ChatBackend backend,
) async {
  final spaceId = backend.selectedSpaceId;
  if (spaceId == null || !backend.canManageStickerPacksInRoom(spaceId)) {
    return null;
  }
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Personal pack'),
            subtitle: const Text('Available wherever your account can use it'),
            onTap: () => Navigator.pop(context, 'personal'),
          ),
          ListTile(
            leading: const Icon(Icons.hub_outlined),
            title: const Text('Current server'),
            subtitle: const Text('Available only to members of this Space'),
            onTap: () => Navigator.pop(context, 'server'),
          ),
        ],
      ),
    ),
  );
  return switch (choice) {
    'personal' => null,
    'server' => spaceId,
    _ => _cancelledPackDestination,
  };
}

Future<void> _deleteStickerPack(
  BuildContext context,
  ChatBackend backend,
) async {
  final manageable = backend.stickerPacks
      .where((pack) => pack.canManage)
      .toList(growable: false);
  final selected = await showModalBottomSheet<StickerPackSummary>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const ListTile(title: Text('Delete pack')),
          for (final pack in manageable)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(pack.name),
              subtitle: Text(pack.roomScoped ? 'Server pack' : 'Personal pack'),
              onTap: () => Navigator.pop(context, pack),
            ),
        ],
      ),
    ),
  );
  if (selected == null || !context.mounted) return;
  await _confirmDeleteStickerPack(context, backend, selected);
}

Future<void> _confirmDeleteStickerPack(
  BuildContext context,
  ChatBackend backend,
  StickerPackSummary selected,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Delete ${selected.name}?'),
      content: const Text(
        'Existing messages keep their fallback emoji names, but the media '
        'will no longer be offered by this pack.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed == true) await backend.deleteStickerPack(selected);
}

Future<void> _importTelegramStickerPack(
  BuildContext context,
  ChatBackend backend, {
  required StickerAssetType assetType,
}) async {
  final linkController = TextEditingController();
  final input = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Import Telegram stickers'),
      content: TextField(
        controller: linkController,
        autofocus: true,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(
          labelText: 'Public pack link',
          hintText: 'https://t.me/addstickers/PackName',
        ),
        onSubmitted: (value) => Navigator.pop(context, value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, linkController.text.trim()),
          child: const Text('Look up'),
        ),
      ],
    ),
  );
  linkController.dispose();
  if (input == null || input.isEmpty || !context.mounted) return;

  final service = TelegramStickerService(
    convertedSize: assetType == StickerAssetType.emoji ? 128 : 256,
  );
  try {
    final pack = await _withStickerProgress(
      context,
      label: 'Looking up sticker pack…',
      operation: () => service.inspect(input),
    );
    if (!context.mounted) return;
    if (pack.stickers.isEmpty) {
      throw StateError(
        pack.unsupportedCount == 0
            ? 'That Telegram pack contains no stickers.'
            : 'Animated TGS and WebM Telegram stickers are not supported yet.',
      );
    }
    final selected = await _selectTelegramStickers(context, service, pack);
    if (selected == null || selected.isEmpty || !context.mounted) return;
    final name = await _askStickerPackName(
      context,
      initialValue: pack.title.length <= 80
          ? pack.title
          : pack.title.substring(0, 80),
    );
    if (name == null || !context.mounted) return;

    final progress = ValueNotifier<(int, int)>((0, selected.length));
    try {
      final items = await _withStickerProgress(
        context,
        label: 'Importing sticker pack…',
        progress: progress,
        operation: () => service.downloadSelected(
          pack,
          selected,
          onProgress: (complete, total) => progress.value = (complete, total),
        ),
      );
      if (!context.mounted) return;
      final preparedItems = assetType == StickerAssetType.emoji
          ? await _prepareEmojiItems(context, items)
          : _asAssetType(items, assetType);
      if (preparedItems == null || !context.mounted) return;
      final draft = StickerPackDraft(name: name, stickers: preparedItems);
      if (!context.mounted) return;
      final destination = await _chooseStickerPackDestination(context, backend);
      if (destination == _cancelledPackDestination) return;
      if (destination == null) {
        await backend.savePersonalStickerPack(draft);
      } else {
        await backend.saveRoomStickerPack(destination, draft);
      }
    } finally {
      progress.dispose();
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Imported ${selected.length} stickers from ${pack.title}.',
          ),
        ),
      );
    }
  } catch (exception) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Telegram import failed: $exception')),
      );
    }
  }
}

Future<T> _withStickerProgress<T>(
  BuildContext context, {
  required String label,
  required Future<T> Function() operation,
  ValueListenable<(int, int)>? progress,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 18),
              Expanded(
                child: progress == null
                    ? Text(label)
                    : ValueListenableBuilder<(int, int)>(
                        valueListenable: progress,
                        builder: (context, value, _) => Text(
                          value.$2 == 0
                              ? label
                              : '$label ${value.$1}/${value.$2}',
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await Future<void>.delayed(Duration.zero);
  try {
    return await operation();
  } finally {
    if (navigator.mounted && navigator.canPop()) navigator.pop();
  }
}

Future<Set<int>?> _selectTelegramStickers(
  BuildContext context,
  TelegramStickerService service,
  TelegramStickerPack pack,
) {
  final selected = pack.stickers.map((sticker) => sticker.index).toSet();
  return showDialog<Set<int>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(pack.title),
        content: SizedBox(
          width: 620,
          height: min(MediaQuery.sizeOf(context).height * 0.62, 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${selected.length} of ${pack.stickers.length} selected'
                '${pack.unsupportedCount == 0 ? '' : ' · ${pack.unsupportedCount} animated/video skipped'}',
              ),
              const SizedBox(height: 8),
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 112,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                  ),
                  itemCount: pack.stickers.length,
                  itemBuilder: (context, index) {
                    final sticker = pack.stickers[index];
                    final included = selected.contains(sticker.index);
                    return InkWell(
                      onTap: () => setState(() {
                        if (!selected.remove(sticker.index)) {
                          selected.add(sticker.index);
                        }
                      }),
                      borderRadius: DeltiecordCorners.borderRadius,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(7),
                            child: _TelegramStickerPreview(
                              service: service,
                              pack: pack,
                              sticker: sticker,
                            ),
                          ),
                          Positioned(
                            top: 2,
                            right: 2,
                            child: Icon(
                              included
                                  ? Icons.check_circle
                                  : Icons.circle_outlined,
                              color: included
                                  ? Theme.of(context).colorScheme.primary
                                  : context.deltiecord.muted,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => setState(() {
              if (selected.length == pack.stickers.length) {
                selected.clear();
              } else {
                selected
                  ..clear()
                  ..addAll(pack.stickers.map((sticker) => sticker.index));
              }
            }),
            child: Text(
              selected.length == pack.stickers.length
                  ? 'Select none'
                  : 'Select all',
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: selected.isEmpty
                ? null
                : () => Navigator.pop(context, Set.unmodifiable(selected)),
            child: const Text('Import'),
          ),
        ],
      ),
    ),
  );
}

class _TelegramStickerPreview extends StatefulWidget {
  const _TelegramStickerPreview({
    required this.service,
    required this.pack,
    required this.sticker,
  });

  final TelegramStickerService service;
  final TelegramStickerPack pack;
  final TelegramStickerReference sticker;

  @override
  State<_TelegramStickerPreview> createState() =>
      _TelegramStickerPreviewState();
}

class _TelegramStickerPreviewState extends State<_TelegramStickerPreview> {
  late Future<Uint8List> _bytes = _load();

  Future<Uint8List> _load() =>
      widget.service.preview(widget.pack, widget.sticker);

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _bytes,
    builder: (context, snapshot) {
      if (snapshot.data case final bytes?) {
        return Image.memory(bytes, fit: BoxFit.contain);
      }
      if (snapshot.hasError) {
        return IconButton(
          tooltip: 'Retry preview',
          onPressed: () => setState(() => _bytes = _load()),
          icon: Icon(Icons.refresh, color: context.deltiecord.muted),
        );
      }
      return const Center(
        child: SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    },
  );
}

bool _isStickerImage(String name) => const [
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
  '.webp',
].any(name.toLowerCase().endsWith);

String _stickerMime(String name) => switch (name.toLowerCase()) {
  final value when value.endsWith('.gif') => 'image/gif',
  final value when value.endsWith('.webp') => 'image/webp',
  final value when value.endsWith('.jpg') || value.endsWith('.jpeg') =>
    'image/jpeg',
  _ => 'image/png',
};

String _stickerShortcode(String name) {
  final value = name
      .split(RegExp(r'[/\\]'))
      .last
      .replaceFirst(RegExp(r'\.[^.]+$'), '')
      .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return value.length <= 100 ? value : value.substring(0, 100);
}

class _PollComposerDialog extends StatefulWidget {
  const _PollComposerDialog();

  @override
  State<_PollComposerDialog> createState() => _PollComposerDialogState();
}

class _PollComposerDialogState extends State<_PollComposerDialog> {
  final _question = TextEditingController();
  final _answers = [TextEditingController(), TextEditingController()];
  bool _multiple = false;
  bool _disclosed = false;

  @override
  void dispose() {
    _question.dispose();
    for (final answer in _answers) {
      answer.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final answers = _answers
        .map((controller) => controller.text.trim())
        .where((answer) => answer.isNotEmpty)
        .toList();
    if (_question.text.trim().isEmpty || answers.length < 2) return;
    Navigator.pop(
      context,
      PollDraft(
        question: _question.text.trim(),
        answers: answers,
        maxSelections: _multiple ? max(2, answers.length) : 1,
        disclosed: _disclosed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Create poll'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('poll-question'),
              controller: _question,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Question'),
            ),
            const SizedBox(height: 10),
            for (var index = 0; index < _answers.length; index++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  key: ValueKey('poll-answer-$index'),
                  controller: _answers[index],
                  decoration: InputDecoration(
                    labelText: 'Answer ${index + 1}',
                    suffixIcon: _answers.length > 2
                        ? IconButton(
                            onPressed: () => setState(() {
                              _answers.removeAt(index).dispose();
                            }),
                            icon: const Icon(Icons.close),
                          )
                        : null,
                  ),
                ),
              ),
            if (_answers.length < 12)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () =>
                      setState(() => _answers.add(TextEditingController())),
                  icon: const Icon(Icons.add),
                  label: const Text('Add answer'),
                ),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _multiple,
              onChanged: (value) => setState(() => _multiple = value),
              title: const Text('Allow multiple answers'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _disclosed,
              onChanged: (value) => setState(() => _disclosed = value),
              title: const Text('Show who voted'),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Create poll')),
    ],
  );
}
