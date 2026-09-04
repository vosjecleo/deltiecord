import 'dart:async';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart' as file_picker;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../backend/chat_backend.dart';
import '../models/chat_models.dart';
import '../services/favourite_reactions_store.dart';
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
  return showModalBottomSheet<StickerSummary>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => ListenableBuilder(
      listenable: FavouriteReactionsStore.instance,
      builder: (context, _) {
        final favouriteStickers = backend.stickerPacks
            .expand((pack) => pack.stickers)
            .where(
              (sticker) =>
                  sticker.assetType == StickerAssetType.sticker &&
                  FavouriteReactionsStore.instance.isStickerFavourite(
                    sticker.mxcUri,
                  ),
            )
            .toList(growable: false);
        final packs = <StickerPackSummary>[
          if (favouriteStickers.isNotEmpty)
            StickerPackSummary(
              id: 'favourites',
              name: 'Favourites',
              stickers: favouriteStickers,
            ),
          ...backend.stickerPacks
              .map(
                (pack) => StickerPackSummary(
                  id: pack.id,
                  name: pack.name,
                  stickers: pack.stickers
                      .where(
                        (sticker) =>
                            sticker.assetType == StickerAssetType.sticker,
                      )
                      .toList(growable: false),
                  roomScoped: pack.roomScoped,
                  sourceRoomId: pack.sourceRoomId,
                  stateKey: pack.stateKey,
                  canManage: pack.canManage,
                ),
              )
              .where((pack) => pack.stickers.isNotEmpty),
        ];
        return FractionallySizedBox(
          heightFactor: 0.72,
          child: packs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No compatible sticker packs found.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () => _manageStickerPacks(context, backend),
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: const Text('Create or import a pack'),
                      ),
                    ],
                  ),
                )
              : DefaultTabController(
                  length: packs.length,
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: IconButton(
                          tooltip: 'Create or import sticker pack',
                          onPressed: () =>
                              _manageStickerPacks(context, backend),
                          icon: const Icon(Icons.add_photo_alternate_outlined),
                        ),
                      ),
                      TabBar(
                        isScrollable: true,
                        tabs: [for (final pack in packs) Tab(text: pack.name)],
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            for (final pack in packs)
                              GridView.builder(
                                padding: const EdgeInsets.all(12),
                                gridDelegate:
                                    const SliverGridDelegateWithMaxCrossAxisExtent(
                                      maxCrossAxisExtent: 112,
                                      mainAxisSpacing: 8,
                                      crossAxisSpacing: 8,
                                    ),
                                itemCount: pack.stickers.length,
                                itemBuilder: (context, index) {
                                  final sticker = pack.stickers[index];
                                  final favourite = FavouriteReactionsStore
                                      .instance
                                      .isStickerFavourite(sticker.mxcUri);
                                  return InkWell(
                                    key: ValueKey(
                                      'sticker-${pack.id}-${sticker.id}',
                                    ),
                                    onTap: () =>
                                        Navigator.pop(context, sticker),
                                    onLongPress: () => FavouriteReactionsStore
                                        .instance
                                        .toggleSticker(sticker.mxcUri),
                                    borderRadius:
                                        DeltiecordCorners.borderRadius,
                                    child: Tooltip(
                                      message: sticker.name,
                                      child: Padding(
                                        padding: const EdgeInsets.all(6),
                                        child: Stack(
                                          children: [
                                            Positioned.fill(
                                              child: _StickerPreviewImage(
                                                backend: backend,
                                                sticker: sticker,
                                              ),
                                            ),
                                            Positioned(
                                              right: 0,
                                              top: 0,
                                              child: IconButton(
                                                tooltip: favourite
                                                    ? 'Remove from favourites'
                                                    : 'Add to favourites',
                                                visualDensity:
                                                    VisualDensity.compact,
                                                onPressed: () =>
                                                    FavouriteReactionsStore
                                                        .instance
                                                        .toggleSticker(
                                                          sticker.mxcUri,
                                                        ),
                                                icon: Icon(
                                                  favourite
                                                      ? Icons.star
                                                      : Icons.star_border,
                                                  size: 18,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        );
      },
    ),
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
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Wrap(
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
    final items = _asAssetType(selectedItems, assetType);
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

  final service = TelegramStickerService();
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
      final draft = StickerPackDraft(
        name: name,
        stickers: _asAssetType(items, assetType),
      );
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
  late final Future<Uint8List> _bytes = widget.service.preview(
    widget.pack,
    widget.sticker,
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _bytes,
    builder: (context, snapshot) {
      if (snapshot.data case final bytes?) {
        return Image.memory(bytes, fit: BoxFit.contain);
      }
      if (snapshot.hasError) {
        return Icon(
          Icons.broken_image_outlined,
          color: context.deltiecord.muted,
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
