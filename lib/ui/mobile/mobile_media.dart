import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../backend/chat_backend.dart';
import '../../models/chat_models.dart';
import '../../services/temporary_attachment_store.dart';
import '../deltiecord_theme.dart';

class MobileAttachmentView extends StatefulWidget {
  const MobileAttachmentView({
    required this.backend,
    required this.message,
    super.key,
  });
  final ChatBackend backend;
  final ChatMessage message;

  @override
  State<MobileAttachmentView> createState() => _MobileAttachmentViewState();
}

class _MobileAttachmentViewState extends State<MobileAttachmentView> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final attachment = widget.message.attachment!;
    final hidden = attachment.spoiler && !_revealed;
    final media = switch (attachment.kind) {
      AttachmentKind.image => _MobileImage(
        backend: widget.backend,
        message: widget.message,
      ),
      AttachmentKind.video || AttachmentKind.audio => _MobilePlayer(
        backend: widget.backend,
        message: widget.message,
        audioOnly: attachment.kind == AttachmentKind.audio,
      ),
      AttachmentKind.file => _MobileFile(
        backend: widget.backend,
        message: widget.message,
      ),
    };
    return GestureDetector(
      onTap: hidden ? () => setState(() => _revealed = true) : null,
      onLongPress: hidden ? null : _showMediaActions,
      child: Stack(
        alignment: Alignment.center,
        children: [
          IgnorePointer(
            ignoring: hidden,
            child: AnimatedOpacity(
              opacity: hidden ? 0.14 : 1,
              duration: const Duration(milliseconds: 120),
              child: media,
            ),
          ),
          if (hidden)
            const Chip(
              avatar: Icon(Icons.visibility_off, size: 17),
              label: Text('Spoiler — tap to reveal'),
            ),
        ],
      ),
    );
  }

  Future<void> _showMediaActions() async {
    final attachment = widget.message.attachment!;
    final image = attachment.kind == AttachmentKind.image;
    final video = attachment.kind == AttachmentKind.video;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            if (image)
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copy image'),
                onTap: () => Navigator.pop(context, 'copy-image'),
              ),
            ListTile(
              leading: const Icon(Icons.link),
              title: Text(
                image ? 'Copy image reference' : 'Copy media reference',
              ),
              onTap: () => Navigator.pop(context, 'copy-reference'),
            ),
            ListTile(
              leading: const Icon(Icons.save_alt),
              title: Text(image ? 'Save image as…' : 'Save media as…'),
              onTap: () => Navigator.pop(context, 'save'),
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('Open externally'),
              onTap: () => Navigator.pop(context, 'open'),
            ),
            if (image || video)
              ListTile(
                leading: const Icon(Icons.fullscreen),
                title: const Text('View fullscreen'),
                onTap: () => Navigator.pop(context, 'fullscreen'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'copy-reference':
        final reference = await widget.backend.getAttachmentReference(
          widget.message.id,
        );
        if (reference != null) {
          await Clipboard.setData(ClipboardData(text: reference));
        }
      case 'copy-image':
        final bytes = await widget.backend.downloadAttachment(
          widget.message.id,
        );
        final clipboard = SystemClipboard.instance;
        if (clipboard != null) {
          final item = DataWriterItem(suggestedName: attachment.name);
          switch (attachment.mimeType) {
            case 'image/jpeg':
              item.add(Formats.jpeg(bytes));
            case 'image/gif':
              item.add(Formats.gif(bytes));
            case 'image/webp':
              item.add(Formats.webp(bytes));
            default:
              item.add(Formats.png(bytes));
          }
          await clipboard.write([item]);
        }
      case 'save':
        final target = await FilePicker.saveFile(
          dialogTitle: 'Save attachment',
          fileName: attachment.name,
        );
        if (target != null) {
          final bytes = await widget.backend.downloadAttachment(
            widget.message.id,
          );
          await File(target).writeAsBytes(bytes, flush: true);
        }
      case 'open':
        final bytes = await widget.backend.downloadAttachment(
          widget.message.id,
        );
        final file = await TemporaryAttachmentStore.instance.create(
          bytes: bytes,
          displayName: attachment.name,
        );
        await launchUrl(
          Uri.file(file.path),
          mode: LaunchMode.externalApplication,
        );
      case 'fullscreen':
        if (!mounted) return;
        if (image) {
          final bytes = await widget.backend.downloadAttachment(
            widget.message.id,
          );
          if (mounted) _showImageFullscreen(context, bytes);
        } else if (video) {
          await showDialog<void>(
            context: context,
            barrierColor: Colors.black,
            builder: (context) => Dialog.fullscreen(
              backgroundColor: Colors.black,
              child: Stack(
                children: [
                  Center(
                    child: _MobilePlayer(
                      backend: widget.backend,
                      message: widget.message,
                      audioOnly: false,
                    ),
                  ),
                  _fullscreenCloseButton(context),
                ],
              ),
            ),
          );
        }
    }
  }
}

class _MobileImage extends StatefulWidget {
  const _MobileImage({required this.backend, required this.message});
  final ChatBackend backend;
  final ChatMessage message;

  @override
  State<_MobileImage> createState() => _MobileImageState();
}

class _MobileImageState extends State<_MobileImage> {
  late Future<Uint8List> _bytes = widget.backend.downloadAttachment(
    widget.message.id,
  );

  @override
  void didUpdateWidget(covariant _MobileImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id) {
      _bytes = widget.backend.downloadAttachment(widget.message.id);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _bytes,
    builder: (context, snapshot) {
      if (snapshot.hasError) return const Text('Could not load image');
      final bytes = snapshot.data;
      if (bytes == null) {
        return const SizedBox.square(
          dimension: 44,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      }
      return GestureDetector(
        onTap: () => _showImageFullscreen(context, bytes),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              gaplessPlayback: true,
            ),
          ),
        ),
      );
    },
  );
}

void _showImageFullscreen(BuildContext context, Uint8List bytes) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black,
    builder: (context) => Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 6,
              child: Center(child: Image.memory(bytes)),
            ),
          ),
          _fullscreenCloseButton(context),
        ],
      ),
    ),
  );
}

Widget _fullscreenCloseButton(BuildContext context) => Positioned(
  right: 12,
  top: 12,
  child: SafeArea(
    child: IconButton(
      style: IconButton.styleFrom(
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
      ),
      onPressed: () => Navigator.pop(context),
      icon: const Text(
        '×',
        style: TextStyle(
          color: Colors.white,
          fontSize: 30,
          height: 0.82,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
  ),
);

class _MobilePlayer extends StatefulWidget {
  const _MobilePlayer({
    required this.backend,
    required this.message,
    required this.audioOnly,
  });
  final ChatBackend backend;
  final ChatMessage message;
  final bool audioOnly;

  @override
  State<_MobilePlayer> createState() => _MobilePlayerState();
}

class _MobilePlayerState extends State<_MobilePlayer> {
  Player? _player;
  VideoController? _video;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final source = await widget.backend.getMediaPlaybackSource(
        widget.message.id,
      );
      if (source == null || !mounted) return;
      final player = Player();
      final video = VideoController(player);
      await player.open(
        Media(source.uri.toString(), httpHeaders: source.headers),
        play: false,
      );
      if (!mounted) {
        await player.dispose();
        return;
      }
      setState(() {
        _player = player;
        _video = video;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    final player = _player;
    if (player != null) unawaited(player.dispose());
    unawaited(widget.backend.releaseMediaPlaybackSource(widget.message.id));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return const Text('Could not play media');
    final player = _player;
    if (player == null) {
      return const SizedBox.square(
        dimension: 44,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (widget.audioOnly) {
      return Card(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: player.playOrPause,
              icon: const Icon(Icons.play_arrow),
            ),
            Flexible(child: Text(widget.message.attachment!.name)),
          ],
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
      child: AspectRatio(
        aspectRatio: _aspectRatio(widget.message.attachment),
        child: ClipRRect(
          borderRadius: DeltiecordCorners.borderRadius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Video(
                controller: _video!,
                controls: AdaptiveVideoControls,
                fit: BoxFit.contain,
              ),
              StreamBuilder<bool>(
                stream: player.stream.playing,
                initialData: player.state.playing,
                builder: (context, snapshot) {
                  if (snapshot.data ?? false) return const SizedBox.shrink();
                  return Center(
                    child: IconButton.filled(
                      key: const ValueKey('mobile-media-play'),
                      tooltip: 'Play video',
                      onPressed: player.play,
                      icon: const _PlayGlyph(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _aspectRatio(ChatAttachment? attachment) {
    final width = attachment?.width;
    final height = attachment?.height;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return 16 / 9;
    }
    return (width / height).clamp(0.5, 2.0);
  }
}

class _MobileFile extends StatelessWidget {
  const _MobileFile({required this.backend, required this.message});
  final ChatBackend backend;
  final ChatMessage message;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.insert_drive_file_outlined),
      title: Text(message.attachment!.name),
      subtitle: Text(message.attachment!.mimeType),
      trailing: const Icon(Icons.open_in_new),
      onTap: () async {
        final bytes = await backend.downloadAttachment(message.id);
        final file = await TemporaryAttachmentStore.instance.create(
          bytes: bytes,
          displayName: message.attachment!.name,
        );
        await launchUrl(
          Uri.file(file.path),
          mode: LaunchMode.externalApplication,
        );
      },
    ),
  );
}

class MobileLinkPreviewCard extends StatelessWidget {
  const MobileLinkPreviewCard({required this.preview, super.key});
  final LinkPreview preview;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => launchUrl(preview.url, mode: LaunchMode.externalApplication),
    child: Card(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (preview.videoUrl case final video?)
              MobileLinkPreviewVideo(
                uri: video,
                thumbnail: preview.imageBytes,
                width: preview.width,
                height: preview.height,
              )
            else if (preview.imageBytes case final image?)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: Image.memory(
                  image,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(preview.siteName ?? preview.url.host),
                  if (preview.title case final title?)
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  if (preview.description case final description?)
                    Text(
                      description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class MobileLinkPreviewVideo extends StatefulWidget {
  const MobileLinkPreviewVideo({
    required this.uri,
    this.thumbnail,
    this.width,
    this.height,
    super.key,
  });

  final Uri uri;
  final Uint8List? thumbnail;
  final int? width;
  final int? height;

  @override
  State<MobileLinkPreviewVideo> createState() => _MobileLinkPreviewVideoState();
}

class _MobileLinkPreviewVideoState extends State<MobileLinkPreviewVideo> {
  Player? _player;
  VideoController? _controller;
  bool _opening = false;
  String? _error;

  Future<void> _play() async {
    final current = _player;
    if (current != null) {
      await current.playOrPause();
      return;
    }
    if (_opening) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    final player = Player(
      configuration: const PlayerConfiguration(bufferSize: 64 * 1024 * 1024),
    );
    final controller = VideoController(player);
    try {
      await player.open(Media(widget.uri.toString()), play: true);
      if (!mounted) {
        await player.dispose();
        return;
      }
      setState(() {
        _player = player;
        _controller = controller;
      });
    } catch (_) {
      await player.dispose();
      if (mounted) setState(() => _error = 'Could not play embedded video');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  void dispose() {
    final player = _player;
    if (player != null) unawaited(player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.width?.toDouble() ?? 16;
    final height = widget.height?.toDouble() ?? 9;
    final ratio = width > 0 && height > 0 ? width / height : 16 / 9;
    final player = _player;
    final controller = _controller;
    return AspectRatio(
      aspectRatio: ratio,
      child: player != null && controller != null
          ? Video(
              controller: controller,
              controls: AdaptiveVideoControls,
              fit: BoxFit.contain,
            )
          : Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: Colors.black,
                  child: widget.thumbnail == null
                      ? null
                      : Image.memory(widget.thumbnail!, fit: BoxFit.cover),
                ),
                Center(
                  child: _opening
                      ? const CircularProgressIndicator()
                      : IconButton.filled(
                          tooltip: 'Play embedded video',
                          onPressed: _play,
                          icon: const _PlayGlyph(),
                        ),
                ),
                if (_error case final error?)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        error,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _PlayGlyph extends StatelessWidget {
  const _PlayGlyph();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: 22,
    child: CustomPaint(painter: _PlayGlyphPainter()),
  );
}

class _PlayGlyphPainter extends CustomPainter {
  const _PlayGlyphPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    final path = Path()
      ..moveTo(size.width * 0.28, size.height * 0.14)
      ..lineTo(size.width * 0.82, size.height * 0.5)
      ..lineTo(size.width * 0.28, size.height * 0.86)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
