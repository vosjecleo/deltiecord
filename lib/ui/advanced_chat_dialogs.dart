import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart' as file_picker;
import 'package:flutter/material.dart';

import '../backend/chat_backend.dart';
import '../models/chat_models.dart';
import '../services/favourite_reactions_store.dart';
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
              (sticker) => FavouriteReactionsStore.instance.isStickerFavourite(
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
          ...backend.stickerPacks,
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
                                              child:
                                                  sticker.previewBytes == null
                                                  ? Center(
                                                      child: Text(
                                                        sticker.name,
                                                        textAlign:
                                                            TextAlign.center,
                                                        maxLines: 3,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    )
                                                  : Image.memory(
                                                      sticker.previewBytes!,
                                                      fit: BoxFit.contain,
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
            title: const Text('Create from images'),
            onTap: () => Navigator.pop(context, 'create'),
          ),
          ListTile(
            leading: const Icon(Icons.folder_zip_outlined),
            title: const Text('Import ZIP'),
            subtitle: const Text('Up to 50 PNG, JPEG, GIF or WebP files'),
            onTap: () => Navigator.pop(context, 'import'),
          ),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  try {
    final items = action == 'create'
        ? await _pickStickerImages()
        : await _pickStickerZip();
    if (items == null || items.isEmpty || !context.mounted) return;
    final name = await _askStickerPackName(context);
    if (name == null) return;
    await backend.savePersonalStickerPack(
      StickerPackDraft(name: name, stickers: items),
    );
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
  return result.files
      .take(50)
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
  if (bytes.length > 25 * 1024 * 1024) {
    throw StateError('Sticker ZIPs are limited to 25 MiB.');
  }
  final archive = ZipDecoder().decodeBytes(bytes, verify: true);
  final candidates = archive.files
      .where((file) => file.isFile && _isStickerImage(file.name))
      .take(51)
      .toList(growable: false);
  if (candidates.length > 50 ||
      candidates.fold<int>(0, (total, file) => total + file.size) >
          100 * 1024 * 1024) {
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

Future<String?> _askStickerPackName(BuildContext context) async {
  final controller = TextEditingController();
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
