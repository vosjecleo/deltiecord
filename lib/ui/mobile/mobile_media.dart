import 'dart:async';
import 'dart:io';
import 'dart:math';

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
import '../advanced_chat_dialogs.dart';

/// Fits media inside a bounded frame without changing its aspect ratio.
///
/// Matrix attachment metadata is available before encrypted bytes finish
/// downloading, so the same size can be used for the placeholder and decoded
/// image. Unknown media reserves a portrait 3:4 frame and keeps that frame
/// after loading instead of shifting the surrounding timeline.
Size mobileMediaFrameSize({
  required double maxWidth,
  required double maxHeight,
  int? width,
  int? height,
  double fallbackAspectRatio = 3 / 4,
}) {
  final metadataRatio =
      width != null && height != null && width > 0 && height > 0
      ? width / height
      : fallbackAspectRatio;
  final aspectRatio = metadataRatio.isFinite
      ? metadataRatio.clamp(0.25, 4.0).toDouble()
      : fallbackAspectRatio;
  if (maxWidth / maxHeight > aspectRatio) {
    return Size(maxHeight * aspectRatio, maxHeight);
  }
  return Size(maxWidth, maxWidth / aspectRatio);
}

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
  final _videoKey = GlobalKey<_MobilePlayerState>();

  @override
  Widget build(BuildContext context) {
    final attachment = widget.message.attachment!;
    final image = attachment.kind == AttachmentKind.image;
    final hidden = attachment.spoiler && !_revealed;
    final media = switch (attachment.kind) {
      AttachmentKind.image => _MobileImage(
        backend: widget.backend,
        message: widget.message,
      ),
      AttachmentKind.video || AttachmentKind.audio => _MobilePlayer(
        key: attachment.kind == AttachmentKind.video ? _videoKey : null,
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
      onTap: hidden
          ? () => setState(() => _revealed = true)
          : attachment.sticker
          ? _openStickerPack
          : image
          ? _openImageFullscreen
          : null,
      onLongPress: hidden || attachment.sticker ? null : _showMediaActions,
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

  Future<void> _openStickerPack() => showStickerPackForMessage(
    context,
    widget.backend,
    messageId: widget.message.id,
    attachment: widget.message.attachment!,
  );

  Future<void> _openImageFullscreen() async {
    final bytes = await widget.backend.downloadAttachment(widget.message.id);
    if (mounted) {
      _showImageFullscreen(context, bytes, onActions: _showMediaActions);
    }
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
          if (mounted) {
            _showImageFullscreen(context, bytes, onActions: _showMediaActions);
          }
        } else if (video) {
          await _videoKey.currentState?.showFullscreen(
            onActions: _showMediaActions,
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
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final attachment = widget.message.attachment!;
    final frame = mobileMediaFrameSize(
      maxWidth: attachment.sticker
          ? 128
          : min(420, max(120, screen.width - 76)),
      maxHeight: attachment.sticker
          ? 128
          : min(520, max(180, screen.height * 0.48)),
      width: attachment.width,
      height: attachment.height,
    );
    return SizedBox(
      key: ValueKey('mobile-image-frame-${widget.message.id}'),
      width: frame.width,
      height: frame.height,
      child: ClipRRect(
        borderRadius: attachment.sticker
            ? BorderRadius.zero
            : DeltiecordCorners.borderRadius,
        child: ColoredBox(
          color: attachment.sticker
              ? Colors.transparent
              : context.deltiecord.elevated,
          child: FutureBuilder<Uint8List>(
            future: _bytes,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(child: Text('Could not load image'));
              }
              final bytes = snapshot.data;
              if (bytes == null) {
                return const Center(
                  child: SizedBox.square(
                    dimension: 28,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              return Image.memory(
                bytes,
                width: frame.width,
                height: frame.height,
                fit: BoxFit.contain,
                gaplessPlayback: true,
              );
            },
          ),
        ),
      ),
    );
  }
}

void _showImageFullscreen(
  BuildContext context,
  Uint8List bytes, {
  VoidCallback? onActions,
}) {
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
          if (onActions != null) _fullscreenActionsButton(context, onActions),
        ],
      ),
    ),
  );
}

Widget _fullscreenCloseButton(BuildContext context, {VoidCallback? onClose}) =>
    Positioned(
      right: 12,
      top: 12,
      child: SafeArea(
        child: IconButton(
          style: IconButton.styleFrom(
            backgroundColor: Colors.black87,
            foregroundColor: Colors.white,
          ),
          onPressed: onClose ?? () => Navigator.pop(context),
          icon: const SizedBox.square(
            dimension: 22,
            child: CustomPaint(painter: _MediaClosePainter()),
          ),
        ),
      ),
    );

Widget _fullscreenActionsButton(BuildContext context, VoidCallback onPressed) =>
    Positioned(
      right: 64,
      top: 12,
      child: SafeArea(
        child: IconButton(
          style: IconButton.styleFrom(
            backgroundColor: Colors.black87,
            foregroundColor: Colors.white,
          ),
          onPressed: onPressed,
          icon: const Icon(Icons.more_vert),
        ),
      ),
    );

class _MediaClosePainter extends CustomPainter {
  const _MediaClosePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(
        Offset(size.width * 0.25, size.height * 0.25),
        Offset(size.width * 0.75, size.height * 0.75),
        paint,
      )
      ..drawLine(
        Offset(size.width * 0.75, size.height * 0.25),
        Offset(size.width * 0.25, size.height * 0.75),
        paint,
      );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MobilePlayer extends StatefulWidget {
  const _MobilePlayer({
    required this.backend,
    required this.message,
    required this.audioOnly,
    super.key,
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
  bool _fullscreenOpen = false;
  bool _sourceRetained = false;

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
      if (source == null) return;
      _sourceRetained = true;
      if (!mounted) {
        await widget.backend.releaseMediaPlaybackSource(widget.message.id);
        _sourceRetained = false;
        return;
      }
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

  Future<void> showFullscreen({VoidCallback? onActions}) async {
    final player = _player;
    final video = _video;
    if (player == null || video == null || _fullscreenOpen || !mounted) return;
    setState(() => _fullscreenOpen = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: _MobileFullscreenVideo(
          player: player,
          controller: video,
          onClose: () => Navigator.pop(dialogContext),
          onActions: onActions,
        ),
      ),
    );
    if (mounted) setState(() => _fullscreenOpen = false);
  }

  @override
  void dispose() {
    final player = _player;
    if (player != null) unawaited(player.dispose());
    if (_sourceRetained) {
      unawaited(widget.backend.releaseMediaPlaybackSource(widget.message.id));
    }
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
    final screen = MediaQuery.sizeOf(context);
    final attachment = widget.message.attachment;
    final frame = mobileMediaFrameSize(
      maxWidth: min(420, max(120, screen.width - 76)),
      maxHeight: min(520, max(180, screen.height * 0.52)),
      width: attachment?.width,
      height: attachment?.height,
      fallbackAspectRatio: 16 / 9,
    );
    return SizedBox(
      width: frame.width,
      height: frame.height,
      child: ClipRRect(
        borderRadius: DeltiecordCorners.borderRadius,
        child: ColoredBox(
          color: Colors.black,
          child: _fullscreenOpen
              ? const SizedBox.expand()
              : GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: () => showFullscreen(),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Video(
                        controller: _video!,
                        controls: NoVideoControls,
                        fit: BoxFit.contain,
                      ),
                      StreamBuilder<bool>(
                        stream: player.stream.playing,
                        initialData: player.state.playing,
                        builder: (context, snapshot) {
                          if (snapshot.data ?? false) {
                            return const SizedBox.shrink();
                          }
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
                      Positioned(
                        right: 6,
                        bottom: 6,
                        child: IconButton(
                          tooltip: 'Fullscreen',
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black54,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => showFullscreen(),
                          icon: const Icon(Icons.fullscreen),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _MobileFullscreenVideo extends StatelessWidget {
  const _MobileFullscreenVideo({
    required this.player,
    required this.controller,
    required this.onClose,
    this.onActions,
  });

  final Player player;
  final VideoController controller;
  final VoidCallback onClose;
  final VoidCallback? onActions;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: player.playOrPause,
          child: Video(
            controller: controller,
            controls: NoVideoControls,
            fit: BoxFit.contain,
          ),
        ),
      ),
      Positioned(
        left: 16,
        right: 16,
        bottom: MediaQuery.paddingOf(context).bottom + 18,
        child: _MobileVideoControls(player: player),
      ),
      _fullscreenCloseButton(context, onClose: onClose),
      if (onActions != null) _fullscreenActionsButton(context, onActions!),
    ],
  );
}

class _MobileVideoControls extends StatelessWidget {
  const _MobileVideoControls({required this.player});

  final Player player;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black54,
      borderRadius: DeltiecordCorners.borderRadius,
    ),
    child: Row(
      children: [
        StreamBuilder<bool>(
          stream: player.stream.playing,
          initialData: player.state.playing,
          builder: (context, snapshot) => IconButton(
            color: Colors.white,
            onPressed: player.playOrPause,
            icon: Icon(snapshot.data == true ? Icons.pause : Icons.play_arrow),
          ),
        ),
        Expanded(
          child: StreamBuilder<Duration>(
            stream: player.stream.position,
            initialData: player.state.position,
            builder: (context, positionSnapshot) => StreamBuilder<Duration>(
              stream: player.stream.duration,
              initialData: player.state.duration,
              builder: (context, durationSnapshot) {
                final duration = durationSnapshot.data ?? Duration.zero;
                final position = positionSnapshot.data ?? Duration.zero;
                final maximum = max(1, duration.inMilliseconds).toDouble();
                return Slider(
                  value: min(position.inMilliseconds.toDouble(), maximum),
                  max: maximum,
                  onChanged: duration == Duration.zero
                      ? null
                      : (value) =>
                            player.seek(Duration(milliseconds: value.round())),
                );
              },
            ),
          ),
        ),
      ],
    ),
  );
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
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final mediaFrame = mobileMediaFrameSize(
      maxWidth: min(420, max(120, screen.width - 76)),
      maxHeight: min(520, max(180, screen.height * 0.52)),
      width: preview.width,
      height: preview.height,
      fallbackAspectRatio: preview.videoUrl == null ? 3 / 4 : 16 / 9,
    );
    return SizedBox(
      width: mediaFrame.width,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (preview.videoUrl case final video?)
              SizedBox(
                width: mediaFrame.width,
                child: MobileLinkPreviewVideo(
                  uri: video,
                  thumbnail: preview.imageBytes,
                  width: preview.width,
                  height: preview.height,
                ),
              )
            else if (preview.imageBytes case final image?)
              GestureDetector(
                onTap: () => _showImageFullscreen(context, image),
                child: SizedBox(
                  width: mediaFrame.width,
                  height: mediaFrame.height,
                  child: Image.memory(
                    image,
                    width: mediaFrame.width,
                    height: mediaFrame.height,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            InkWell(
              onTap: () =>
                  launchUrl(preview.url, mode: LaunchMode.externalApplication),
              child: Padding(
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
            ),
          ],
        ),
      ),
    );
  }
}

class MobileLinkPreviewVideo extends StatefulWidget {
  const MobileLinkPreviewVideo({
    required this.uri,
    this.thumbnail,
    this.width,
    this.height,
    this.autoplay = false,
    this.onDoubleTap,
    super.key,
  });

  final Uri uri;
  final Uint8List? thumbnail;
  final int? width;
  final int? height;
  final bool autoplay;
  final VoidCallback? onDoubleTap;

  @override
  State<MobileLinkPreviewVideo> createState() => _MobileLinkPreviewVideoState();
}

class _MobileLinkPreviewVideoState extends State<MobileLinkPreviewVideo> {
  Player? _player;
  VideoController? _controller;
  StreamSubscription<int?>? _widthSubscription;
  StreamSubscription<int?>? _heightSubscription;
  int? _naturalWidth;
  int? _naturalHeight;
  bool _opening = false;
  String? _error;
  bool _fullscreenOpen = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoplay) unawaited(_play());
  }

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
    _widthSubscription = player.stream.width.listen((value) {
      if (mounted && value != null && value > 0) {
        setState(() => _naturalWidth = value);
      }
    });
    _heightSubscription = player.stream.height.listen((value) {
      if (mounted && value != null && value > 0) {
        setState(() => _naturalHeight = value);
      }
    });
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

  Future<void> _showFullscreen() async {
    final player = _player;
    final controller = _controller;
    if (player == null || controller == null || _fullscreenOpen || !mounted) {
      return;
    }
    setState(() => _fullscreenOpen = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: _MobileFullscreenVideo(
          player: player,
          controller: controller,
          onClose: () => Navigator.pop(dialogContext),
        ),
      ),
    );
    if (mounted) setState(() => _fullscreenOpen = false);
  }

  @override
  void dispose() {
    _widthSubscription?.cancel();
    _heightSubscription?.cancel();
    final player = _player;
    if (player != null) unawaited(player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = (_naturalWidth ?? widget.width)?.toDouble() ?? 16;
    final height = (_naturalHeight ?? widget.height)?.toDouble() ?? 9;
    final ratio = width > 0 && height > 0
        ? (width / height).clamp(0.25, 4.0)
        : 16 / 9;
    final player = _player;
    final controller = _controller;
    final surface = AspectRatio(
      aspectRatio: ratio.toDouble(),
      child: _fullscreenOpen
          ? const ColoredBox(color: Colors.black)
          : player != null && controller != null
          ? Video(
              controller: controller,
              controls: NoVideoControls,
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _play,
      onDoubleTap: widget.onDoubleTap ?? _showFullscreen,
      child: Stack(
        children: [
          surface,
          if (player != null && !_fullscreenOpen)
            Positioned(
              right: 6,
              bottom: 6,
              child: IconButton(
                tooltip: 'Fullscreen',
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                  foregroundColor: Colors.white,
                ),
                onPressed: _showFullscreen,
                icon: const Icon(Icons.fullscreen),
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
