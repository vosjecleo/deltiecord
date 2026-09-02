part of 'chat_shell.dart';

enum _MediaAction { copyImage, copyReference, save, open, fullscreen }

Future<_MediaAction?> _showMediaContextMenu(
  BuildContext context,
  Offset position, {
  required bool image,
}) {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  return showMenu<_MediaAction>(
    context: context,
    position: RelativeRect.fromRect(
      position & const Size(1, 1),
      Offset.zero & overlay.size,
    ),
    items: [
      if (image)
        const PopupMenuItem(
          value: _MediaAction.copyImage,
          child: Text('Copy image'),
        ),
      PopupMenuItem(
        value: _MediaAction.copyReference,
        child: Text(image ? 'Copy image reference' : 'Copy video reference'),
      ),
      PopupMenuItem(
        value: _MediaAction.save,
        child: Text(image ? 'Save image as…' : 'Save video as…'),
      ),
      const PopupMenuItem(
        value: _MediaAction.open,
        child: Text('Open externally'),
      ),
      const PopupMenuItem(
        value: _MediaAction.fullscreen,
        child: Text('View fullscreen'),
      ),
    ],
  );
}

// Inline playback is implemented with media_kit rather than adapted player
// source. Attribution and upstream license details are in CREDITS.md.
class _LinkPreviewCard extends StatelessWidget {
  const _LinkPreviewCard({required this.preview});

  final LinkPreview preview;

  Future<void> _showVideoFullscreen(BuildContext context, Uri video) =>
      showDialog<void>(
        context: context,
        barrierColor: Colors.black,
        builder: (dialogContext) => Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(dialogContext).width,
                    maxHeight: MediaQuery.sizeOf(dialogContext).height,
                  ),
                  child: _LinkVideoPlayer(
                    uri: video,
                    thumbnail: preview.imageBytes,
                    aspectRatio: (preview.width ?? 16) / (preview.height ?? 9),
                    autoplay: true,
                  ),
                ),
              ),
              Positioned(
                right: 18,
                top: 18,
                child: IconButton.filled(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(dialogContext),
                  icon: const Icon(Icons.close),
                ),
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final video = preview.videoUrl;
    final screen = MediaQuery.sizeOf(context);
    final maxWidth = screen.width * 0.5;
    final maxHeight = screen.height * 0.5;
    final sourceWidth = preview.width?.toDouble() ?? 16;
    final sourceHeight = preview.height?.toDouble() ?? 9;
    final aspectRatio = sourceWidth > 0 && sourceHeight > 0
        ? sourceWidth / sourceHeight
        : 16 / 9;
    final mediaWidth = maxWidth / maxHeight > aspectRatio
        ? maxHeight * aspectRatio
        : maxWidth;
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: mediaWidth,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: context.deltiecord.elevated,
            borderRadius: DeltiecordCorners.borderRadius,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (video != null)
                SizedBox(
                  width: mediaWidth,
                  child: _LinkVideoPlayer(
                    uri: video,
                    thumbnail: preview.imageBytes,
                    aspectRatio: aspectRatio,
                    onDoubleTap: () => _showVideoFullscreen(context, video),
                  ),
                )
              else if (preview.imageBytes case final image?)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: maxWidth,
                    maxHeight: maxHeight,
                  ),
                  child: Image.memory(image, fit: BoxFit.contain),
                ),
              InkWell(
                onTap: () => launchUrl(preview.url),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 9, 12, 11),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        preview.siteName ?? preview.url.host,
                        style: TextStyle(
                          color: context.deltiecord.muted,
                          fontSize: DeltiecordTypeScale.normal,
                        ),
                      ),
                      if (preview.title case final title?) ...[
                        const SizedBox(height: 3),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (preview.description case final description?) ...[
                        const SizedBox(height: 4),
                        Text(
                          description,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: DeltiecordTypeScale.normal,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LinkVideoPlayer extends StatefulWidget {
  const _LinkVideoPlayer({
    required this.uri,
    this.thumbnail,
    this.aspectRatio = 16 / 9,
    this.autoplay = false,
    this.onDoubleTap,
  });

  final Uri uri;
  final Uint8List? thumbnail;
  final double aspectRatio;
  final bool autoplay;
  final VoidCallback? onDoubleTap;

  @override
  State<_LinkVideoPlayer> createState() => _LinkVideoPlayerState();
}

class _LinkVideoPlayerState extends State<_LinkVideoPlayer> {
  Player? _player;
  VideoController? _controller;
  StreamSubscription<int?>? _widthSubscription;
  StreamSubscription<int?>? _heightSubscription;
  int? _naturalWidth;
  int? _naturalHeight;
  bool _opened = false;
  bool _opening = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.autoplay) unawaited(_toggle());
  }

  Future<void> _toggle() async {
    final existing = _player;
    if (_opened && existing != null) {
      await existing.playOrPause();
      return;
    }
    if (_opening) return;
    final player =
        existing ??
        Player(
          configuration: const PlayerConfiguration(
            bufferSize: 64 * 1024 * 1024,
          ),
        );
    _player = player;
    _controller ??= VideoController(player);
    _widthSubscription ??= player.stream.width.listen((value) {
      if (mounted && value != null && value > 0) {
        setState(() => _naturalWidth = value);
      }
    });
    _heightSubscription ??= player.stream.height.listen((value) {
      if (mounted && value != null && value > 0) {
        setState(() => _naturalHeight = value);
      }
    });
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      await player.open(Media(widget.uri.toString()), play: true);
      _opened = true;
    } catch (exception) {
      _error = safeErrorMessage(exception);
      await player.dispose();
      _player = null;
      _controller = null;
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  void dispose() {
    _widthSubscription?.cancel();
    _heightSubscription?.cancel();
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    final controller = _controller;
    final naturalRatio = _naturalWidth != null && _naturalHeight != null
        ? _naturalWidth! / _naturalHeight!
        : widget.aspectRatio;
    final surface = AspectRatio(
      aspectRatio: naturalRatio.clamp(0.25, 4.0).toDouble(),
      child: player == null || controller == null
          ? _VideoPoster(
              onPlay: _toggle,
              thumbnail: widget.thumbnail == null
                  ? null
                  : Image.memory(widget.thumbnail!, fit: BoxFit.cover),
              tooltip: 'Play embedded video',
              error: _error,
            )
          : _DeltiecordVideoSurface(
              player: player,
              controller: controller,
              opened: _opened,
              loading: _opening,
              onToggle: _toggle,
              thumbnail: widget.thumbnail == null
                  ? null
                  : Image.memory(widget.thumbnail!, fit: BoxFit.cover),
              playTooltip: 'Play embedded video',
            ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: player == null ? _toggle : null,
      onDoubleTap: widget.onDoubleTap,
      child: surface,
    );
  }
}

class _VideoPoster extends StatelessWidget {
  const _VideoPoster({
    required this.onPlay,
    required this.tooltip,
    this.thumbnail,
    this.error,
  });

  final Future<void> Function() onPlay;
  final String tooltip;
  final Widget? thumbnail;
  final String? error;

  ButtonStyle _playButtonStyle(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final foreground =
        ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
        ? Colors.white
        : Colors.black;
    return IconButton.styleFrom(
      backgroundColor: accent,
      foregroundColor: foreground,
      disabledBackgroundColor: accent.withValues(alpha: 0.75),
      disabledForegroundColor: foreground.withValues(alpha: 0.75),
    );
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: DeltiecordCorners.borderRadius,
    child: ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ?thumbnail,
          Center(
            child: IconButton.filled(
              tooltip: tooltip,
              onPressed: onPlay,
              style: _playButtonStyle(context),
              icon: const Icon(Icons.play_arrow),
            ),
          ),
          if (error != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: Text(
                error!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70),
              ),
            ),
        ],
      ),
    ),
  );
}

/// A bounded video surface with controls that always remain inside the media.
/// media_kit's desktop controls assume a wider viewport and can overflow on
/// portrait clips, so Deltiecord owns this compact overlay instead.
class _DeltiecordVideoSurface extends StatelessWidget {
  const _DeltiecordVideoSurface({
    required this.player,
    required this.controller,
    required this.opened,
    required this.onToggle,
    required this.playTooltip,
    this.thumbnail,
    this.loading = false,
    this.onFullscreen,
  });

  final Player player;
  final VideoController controller;
  final bool opened;
  final Future<void> Function() onToggle;
  final String playTooltip;
  final Widget? thumbnail;
  final bool loading;
  final VoidCallback? onFullscreen;

  ButtonStyle _playButtonStyle(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final foreground =
        ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
        ? Colors.white
        : Colors.black;
    return IconButton.styleFrom(
      backgroundColor: accent,
      foregroundColor: foreground,
      disabledBackgroundColor: accent.withValues(alpha: 0.75),
      disabledForegroundColor: foreground.withValues(alpha: 0.75),
    );
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: DeltiecordCorners.borderRadius,
    child: ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!opened && thumbnail != null) thumbnail!,
          if (opened)
            Video(
              controller: controller,
              fit: BoxFit.contain,
              controls: NoVideoControls,
            ),
          StreamBuilder<bool>(
            stream: player.stream.playing,
            initialData: player.state.playing,
            builder: (context, playingSnapshot) {
              final playing = playingSnapshot.data ?? false;
              return Stack(
                fit: StackFit.expand,
                children: [
                  if (!playing)
                    Center(
                      child: IconButton.filled(
                        tooltip: playTooltip,
                        onPressed: loading ? null : onToggle,
                        style: _playButtonStyle(context),
                        icon: loading
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.play_arrow),
                      ),
                    ),
                  if (opened)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: _CompactVideoControls(
                        player: player,
                        playing: playing,
                        onToggle: onToggle,
                        onFullscreen: onFullscreen,
                      ),
                    ),
                  StreamBuilder<bool>(
                    stream: player.stream.buffering,
                    initialData: player.state.buffering,
                    builder: (context, snapshot) =>
                        snapshot.data == true && playing
                        ? const Center(
                            child: SizedBox.square(
                              dimension: 28,
                              child: CircularProgressIndicator(strokeWidth: 3),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );
}

class _CompactVideoControls extends StatefulWidget {
  const _CompactVideoControls({
    required this.player,
    required this.playing,
    required this.onToggle,
    this.onFullscreen,
  });

  final Player player;
  final bool playing;
  final Future<void> Function() onToggle;
  final VoidCallback? onFullscreen;

  @override
  State<_CompactVideoControls> createState() => _CompactVideoControlsState();
}

class _CompactVideoControlsState extends State<_CompactVideoControls> {
  double? _dragMilliseconds;
  int _seekGeneration = 0;

  Future<void> _commitSeek(double value) async {
    final generation = ++_seekGeneration;
    setState(() => _dragMilliseconds = value);
    try {
      await widget.player.seek(Duration(milliseconds: value.round()));
    } catch (_) {
      // A cancelled range during a second seek is harmless; the player keeps
      // its prior position and remains usable for another attempt.
    } finally {
      if (mounted && generation == _seekGeneration) {
        setState(() => _dragMilliseconds = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    height: 34,
    padding: const EdgeInsets.symmetric(horizontal: 4),
    color: const Color(0xaa000000),
    child: Row(
      children: [
        SizedBox.square(
          dimension: 30,
          child: IconButton(
            tooltip: widget.playing ? 'Pause' : 'Play',
            padding: EdgeInsets.zero,
            color: Colors.white,
            onPressed: widget.onToggle,
            icon: Icon(
              widget.playing ? Icons.pause : Icons.play_arrow,
              size: 20,
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<Duration>(
            stream: widget.player.stream.duration,
            initialData: widget.player.state.duration,
            builder: (context, durationSnapshot) => StreamBuilder<Duration>(
              stream: widget.player.stream.position,
              initialData: widget.player.state.position,
              builder: (context, positionSnapshot) {
                final duration = durationSnapshot.data ?? Duration.zero;
                final position = positionSnapshot.data ?? Duration.zero;
                final maximum = max(1, duration.inMilliseconds).toDouble();
                return SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 4,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 8,
                    ),
                  ),
                  child: Slider(
                    value: (_dragMilliseconds ?? position.inMilliseconds)
                        .clamp(0, maximum.toInt())
                        .toDouble(),
                    max: maximum,
                    onChangeStart: duration == Duration.zero
                        ? null
                        : (value) => setState(() => _dragMilliseconds = value),
                    onChanged: duration == Duration.zero
                        ? null
                        : (value) => setState(() => _dragMilliseconds = value),
                    onChangeEnd: duration == Duration.zero
                        ? null
                        : (value) => unawaited(_commitSeek(value)),
                  ),
                );
              },
            ),
          ),
        ),
        if (widget.onFullscreen != null)
          SizedBox.square(
            dimension: 30,
            child: IconButton(
              tooltip: 'View fullscreen',
              padding: EdgeInsets.zero,
              color: Colors.white,
              onPressed: widget.onFullscreen,
              icon: const Icon(Icons.fullscreen, size: 20),
            ),
          ),
      ],
    ),
  );
}

class _AttachmentView extends StatefulWidget {
  const _AttachmentView({
    required this.backend,
    required this.messageId,
    required this.attachment,
    required this.gallery,
  });

  final ChatBackend backend;
  final String messageId;
  final ChatAttachment attachment;
  final List<ChatMessage> gallery;

  @override
  State<_AttachmentView> createState() => _AttachmentViewState();
}

class _AttachmentViewState extends State<_AttachmentView> {
  Future<Uint8List>? _imageBytes;
  bool _revealed = false;
  bool _saving = false;
  bool _opening = false;

  Future<void> _copyReference() async {
    final reference = await widget.backend.getAttachmentReference(
      widget.messageId,
    );
    if (reference == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No safe media reference available')),
        );
      }
      return;
    }
    await Clipboard.setData(ClipboardData(text: reference));
  }

  Future<void> _copyImage() async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return;
    final bytes = await widget.backend.downloadAttachment(widget.messageId);
    final item = DataWriterItem(suggestedName: widget.attachment.name);
    switch (widget.attachment.mimeType) {
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

  Future<void> _showContextMenu(
    Offset position, {
    required bool image,
    VoidCallback? fullscreen,
  }) async {
    final action = await _showMediaContextMenu(context, position, image: image);
    switch (action) {
      case _MediaAction.copyImage:
        await _copyImage();
      case _MediaAction.copyReference:
        await _copyReference();
      case _MediaAction.save:
        await _save();
      case _MediaAction.open:
        await _open();
      case _MediaAction.fullscreen:
        fullscreen?.call();
      case null:
        return;
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final path = await FilePicker.saveFile(
      dialogTitle: 'Save attachment',
      fileName: widget.attachment.name,
    );
    if (path == null || !mounted) return;
    setState(() => _saving = true);
    try {
      final bytes = await widget.backend.downloadAttachment(widget.messageId);
      await File(path).writeAsBytes(bytes, flush: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final bytes = await widget.backend.downloadAttachment(widget.messageId);
      final file = await TemporaryAttachmentStore.instance.create(
        bytes: bytes,
        displayName: widget.attachment.name,
      );
      if (!await launchUrl(Uri.file(file.path))) {
        throw StateError('No application is available to open this file.');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open that attachment.')),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  void _showMedia() => showDialog<void>(
    context: context,
    builder: (context) => _MediaLightbox(
      backend: widget.backend,
      messages: widget.gallery,
      initialMessageId: widget.messageId,
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (widget.attachment.spoiler && !_revealed) {
      return Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: 208,
          height: 116,
          child: Material(
            color: context.deltiecord.input,
            borderRadius: DeltiecordCorners.borderRadius,
            child: InkWell(
              onTap: () => setState(() => _revealed = true),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.visibility_off_outlined, size: 17),
                    SizedBox(height: 2),
                    Text(
                      'Reveal spoiler',
                      style: TextStyle(fontSize: DeltiecordTypeScale.normal),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return switch (widget.attachment.kind) {
      AttachmentKind.image => _buildImage(),
      AttachmentKind.video => _InlineVideo(
        backend: widget.backend,
        messageId: widget.messageId,
        attachment: widget.attachment,
        onSave: _save,
        onOpen: _open,
        onContextMenu: (position, fullscreen) =>
            _showContextMenu(position, image: false, fullscreen: fullscreen),
        onFullscreen: _showMedia,
      ),
      AttachmentKind.audio => _InlineAudio(
        backend: widget.backend,
        messageId: widget.messageId,
        attachment: widget.attachment,
        onSave: _save,
        onOpen: _open,
      ),
      AttachmentKind.file => _buildFile(),
    };
  }

  Widget _buildImage() {
    _imageBytes ??= widget.backend.downloadAttachment(
      widget.messageId,
      thumbnail: !widget.attachment.animated,
    );
    final screen = MediaQuery.sizeOf(context);
    final metadataWidth = widget.attachment.width;
    final metadataHeight = widget.attachment.height;
    final ratio =
        metadataWidth != null &&
            metadataHeight != null &&
            metadataWidth > 0 &&
            metadataHeight > 0
        ? (metadataWidth / metadataHeight).clamp(0.25, 4.0).toDouble()
        : 3 / 4;
    final maxWidth = min(420.0, screen.width * 0.5);
    final maxHeight = min(520.0, screen.height * 0.5);
    final frame = maxWidth / maxHeight > ratio
        ? Size(maxHeight * ratio, maxHeight)
        : Size(maxWidth, maxWidth / ratio);
    return FutureBuilder<Uint8List>(
      future: _imageBytes,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _FileTile(
            attachment: widget.attachment,
            saving: _saving,
            onSave: _save,
            opening: _opening,
            onOpen: _open,
            error: 'Preview unavailable',
          );
        }
        final bytes = snapshot.data;
        if (bytes == null) {
          return SizedBox(
            width: frame.width,
            height: frame.height,
            child: ColoredBox(
              color: context.deltiecord.elevated,
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: frame.width,
            height: frame.height,
            child: InkWell(
              onTap: _showMedia,
              onSecondaryTapDown: (details) => _showContextMenu(
                details.globalPosition,
                image: true,
                fullscreen: _showMedia,
              ),
              child: _PreferenceAwareImage(
                bytes: bytes,
                animated: widget.attachment.animated,
                autoplay: widget.backend.preferences.autoplayGifs,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFile() => _FileTile(
    attachment: widget.attachment,
    saving: _saving,
    onSave: _save,
    opening: _opening,
    onOpen: _open,
  );
}

class _PreferenceAwareImage extends StatelessWidget {
  const _PreferenceAwareImage({
    required this.bytes,
    required this.animated,
    required this.autoplay,
  });

  final Uint8List bytes;
  final bool animated;
  final bool autoplay;

  @override
  Widget build(BuildContext context) {
    if (!animated || autoplay) {
      return Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true);
    }
    return _FirstFrameImage(bytes: bytes);
  }
}

class _FirstFrameImage extends StatefulWidget {
  const _FirstFrameImage({required this.bytes});

  final Uint8List bytes;

  @override
  State<_FirstFrameImage> createState() => _FirstFrameImageState();
}

class _FirstFrameImageState extends State<_FirstFrameImage> {
  late Future<ui.Image> _frame = _decode();
  ui.Image? _decoded;

  Future<ui.Image> _decode() async {
    final codec = await ui.instantiateImageCodec(widget.bytes);
    try {
      final frame = await codec.getNextFrame();
      _decoded = frame.image;
      return frame.image;
    } finally {
      codec.dispose();
    }
  }

  @override
  void didUpdateWidget(covariant _FirstFrameImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes)) {
      _decoded?.dispose();
      _decoded = null;
      _frame = _decode();
    }
  }

  @override
  void dispose() {
    _decoded?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ui.Image>(
    future: _frame,
    builder: (context, snapshot) {
      final image = snapshot.data;
      return image == null
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : RawImage(image: image, fit: BoxFit.contain);
    },
  );
}

class _FileTile extends StatelessWidget {
  const _FileTile({
    required this.attachment,
    required this.saving,
    required this.onSave,
    required this.opening,
    required this.onOpen,
    this.error,
  });

  final ChatAttachment attachment;
  final bool saving;
  final VoidCallback onSave;
  final bool opening;
  final VoidCallback onOpen;
  final String? error;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 460),
    padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
    decoration: BoxDecoration(
      color: context.deltiecord.elevated,
      borderRadius: DeltiecordCorners.borderRadius,
    ),
    child: Row(
      children: [
        Icon(
          attachment.kind == AttachmentKind.audio
              ? Icons.audio_file_outlined
              : Icons.insert_drive_file_outlined,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(attachment.name, overflow: TextOverflow.ellipsis),
              Text(
                error ?? _fileDetails(attachment),
                style: TextStyle(
                  fontSize: DeltiecordTypeScale.normal,
                  color: context.deltiecord.muted,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Open attachment',
          onPressed: opening ? null : onOpen,
          icon: opening
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.open_in_new, size: 18),
        ),
        IconButton(
          tooltip: 'Save attachment',
          onPressed: saving ? null : onSave,
          icon: saving
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download, size: 19),
        ),
      ],
    ),
  );

  String _fileDetails(ChatAttachment attachment) {
    final size = attachment.size;
    if (size == null) return attachment.mimeType;
    final amount = size >= 1024 * 1024
        ? '${(size / (1024 * 1024)).toStringAsFixed(1)} MB'
        : '${(size / 1024).toStringAsFixed(0)} KB';
    return '${attachment.mimeType} · $amount';
  }
}

class _InlineVideo extends StatefulWidget {
  const _InlineVideo({
    required this.backend,
    required this.messageId,
    required this.attachment,
    required this.onSave,
    required this.onOpen,
    required this.onContextMenu,
    required this.onFullscreen,
  });

  final ChatBackend backend;
  final String messageId;
  final ChatAttachment attachment;
  final VoidCallback onSave;
  final VoidCallback onOpen;
  final void Function(Offset position, VoidCallback fullscreen) onContextMenu;
  final VoidCallback onFullscreen;

  @override
  State<_InlineVideo> createState() => _InlineVideoState();
}

class _InlineVideoState extends State<_InlineVideo> {
  Player? _player;
  VideoController? _controller;
  bool _opening = false;
  bool _opened = false;
  bool _sourceRetained = false;
  String? _error;
  late final Future<Uint8List>? _thumbnail = widget.attachment.hasThumbnail
      ? widget.backend.downloadAttachment(widget.messageId, thumbnail: true)
      : null;

  Future<void> _play() async {
    if (_opening) return;
    final existing = _player;
    if (_opened && existing != null) {
      await existing.playOrPause();
      return;
    }
    final player =
        existing ??
        Player(
          configuration: const PlayerConfiguration(
            bufferSize: 64 * 1024 * 1024,
          ),
        );
    _player = player;
    _controller ??= VideoController(player);
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final source = await widget.backend.getMediaPlaybackSource(
        widget.messageId,
      );
      if (source == null) {
        throw StateError('Encrypted streaming is still being prepared.');
      }
      _sourceRetained = true;
      await player.open(
        Media(source.uri.toString(), httpHeaders: source.headers),
        play: true,
      );
      _opened = true;
    } catch (exception) {
      if (mounted) setState(() => _error = safeErrorMessage(exception));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  void _showFullscreen() {
    widget.onFullscreen();
  }

  @override
  void dispose() {
    if (_sourceRetained) {
      unawaited(widget.backend.releaseMediaPlaybackSource(widget.messageId));
    }
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final maxWidth = screen.width * 0.5;
    final maxHeight = screen.height * 0.5;
    final sourceWidth = widget.attachment.width?.toDouble() ?? 16;
    final sourceHeight = widget.attachment.height?.toDouble() ?? 9;
    final aspectRatio = sourceWidth > 0 && sourceHeight > 0
        ? sourceWidth / sourceHeight
        : 16 / 9;
    final width = maxWidth / maxHeight > aspectRatio
        ? maxHeight * aspectRatio
        : maxWidth;
    final height = width / aspectRatio;
    final player = _player;
    final controller = _controller;
    final thumbnail = _thumbnail == null
        ? null
        : FutureBuilder<Uint8List>(
            future: _thumbnail,
            builder: (context, snapshot) => snapshot.data == null
                ? const SizedBox.shrink()
                : Image.memory(snapshot.data!, fit: BoxFit.contain),
          );
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap: _showFullscreen,
              onSecondaryTapDown: (details) =>
                  widget.onContextMenu(details.globalPosition, _showFullscreen),
              child: player == null || controller == null
                  ? _VideoPoster(
                      onPlay: _play,
                      thumbnail: thumbnail,
                      tooltip: 'Stream video',
                      error: _error,
                    )
                  : _DeltiecordVideoSurface(
                      player: player,
                      controller: controller,
                      opened: _opened,
                      loading: _opening,
                      onToggle: _play,
                      onFullscreen: _showFullscreen,
                      playTooltip: 'Stream video',
                      thumbnail: thumbnail,
                    ),
            ),
            if (_error case final error?)
              Positioned(
                left: 3,
                right: 3,
                bottom: 36,
                child: Text(
                  error,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: DeltiecordTypeScale.normal,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MediaLightbox extends StatefulWidget {
  const _MediaLightbox({
    required this.backend,
    required this.messages,
    required this.initialMessageId,
  });

  final ChatBackend backend;
  final List<ChatMessage> messages;
  final String initialMessageId;

  @override
  State<_MediaLightbox> createState() => _MediaLightboxState();
}

class _MediaLightboxState extends State<_MediaLightbox> {
  late int _index = max(
    0,
    widget.messages.indexWhere(
      (message) => message.id == widget.initialMessageId,
    ),
  );
  final Map<String, Future<Uint8List>> _images = {};

  ChatMessage get _message => widget.messages[_index];
  ChatAttachment get _attachment => _message.attachment!;

  void _previous() {
    if (_index + 1 < widget.messages.length) setState(() => _index++);
  }

  void _next() {
    if (_index > 0) setState(() => _index--);
  }

  Future<void> _copyReference() async {
    final reference = await widget.backend.getAttachmentReference(_message.id);
    if (reference != null) {
      await Clipboard.setData(ClipboardData(text: reference));
    }
  }

  Future<void> _copyImage() async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null || _attachment.kind != AttachmentKind.image) return;
    final bytes = await widget.backend.downloadAttachment(_message.id);
    final item = DataWriterItem(suggestedName: _attachment.name);
    switch (_attachment.mimeType) {
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

  Future<void> _save() async {
    final path = await FilePicker.saveFile(
      dialogTitle: 'Save attachment',
      fileName: _attachment.name,
    );
    if (path == null) return;
    final bytes = await widget.backend.downloadAttachment(_message.id);
    await File(path).writeAsBytes(bytes, flush: true);
  }

  Future<void> _open() async {
    final bytes = await widget.backend.downloadAttachment(_message.id);
    final file = await TemporaryAttachmentStore.instance.create(
      bytes: bytes,
      displayName: _attachment.name,
    );
    await launchUrl(Uri.file(file.path));
  }

  Future<void> _contextMenu(Offset position) async {
    final image = _attachment.kind == AttachmentKind.image;
    final action = await _showMediaContextMenu(context, position, image: image);
    switch (action) {
      case _MediaAction.copyImage:
        await _copyImage();
      case _MediaAction.copyReference:
        await _copyReference();
      case _MediaAction.save:
        await _save();
      case _MediaAction.open:
        await _open();
      case _MediaAction.fullscreen || null:
        return;
    }
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.arrowLeft): _previous,
      const SingleActivator(LogicalKeyboardKey.arrowRight): _next,
    },
    child: Focus(
      autofocus: true,
      child: Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onSecondaryTapDown: (details) =>
                    _contextMenu(details.globalPosition),
                child: _attachment.kind == AttachmentKind.video
                    ? _LightboxVideo(
                        key: ValueKey(_message.id),
                        backend: widget.backend,
                        messageId: _message.id,
                      )
                    : FutureBuilder<Uint8List>(
                        future: _images.putIfAbsent(
                          _message.id,
                          () => widget.backend.downloadAttachment(_message.id),
                        ),
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return const Center(
                              child: Text('Image unavailable'),
                            );
                          }
                          if (snapshot.data case final bytes?) {
                            return InteractiveViewer(
                              key: ValueKey(_message.id),
                              minScale: 0.25,
                              maxScale: 8,
                              child: Center(child: Image.memory(bytes)),
                            );
                          }
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        },
                      ),
              ),
            ),
            if (_index + 1 < widget.messages.length)
              Positioned(
                left: 12,
                top: 0,
                bottom: 0,
                child: Center(
                  child: SizedBox.square(
                    dimension: 46,
                    child: IconButton.filledTonal(
                      tooltip: 'Previous attachment',
                      onPressed: _previous,
                      icon: const Icon(Icons.chevron_left),
                    ),
                  ),
                ),
              ),
            if (_index > 0)
              Positioned(
                right: 12,
                top: 0,
                bottom: 0,
                child: Center(
                  child: SizedBox.square(
                    dimension: 46,
                    child: IconButton.filledTonal(
                      tooltip: 'Next attachment',
                      onPressed: _next,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ),
                ),
              ),
            Positioned(
              right: 12,
              top: 12,
              child: Row(
                children: [
                  Text(
                    '${_index + 1}/${widget.messages.length}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Save attachment',
                    onPressed: _save,
                    icon: const Icon(Icons.download),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filledTonal(
                    tooltip: 'Open externally',
                    onPressed: _open,
                    icon: const Icon(Icons.open_in_new),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filledTonal(
                    tooltip: 'Close viewer',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
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

class _LightboxVideo extends StatefulWidget {
  const _LightboxVideo({
    required this.backend,
    required this.messageId,
    super.key,
  });

  final ChatBackend backend;
  final String messageId;

  @override
  State<_LightboxVideo> createState() => _LightboxVideoState();
}

class _LightboxVideoState extends State<_LightboxVideo> {
  late final Player _player = Player(
    configuration: const PlayerConfiguration(bufferSize: 64 * 1024 * 1024),
  );
  late final VideoController _controller = VideoController(_player);
  String? _error;
  bool _opened = false;
  bool _sourceRetained = false;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      final source = await widget.backend.getMediaPlaybackSource(
        widget.messageId,
      );
      if (source == null) throw StateError('Video playback is unavailable.');
      _sourceRetained = true;
      await _player.open(
        Media(source.uri.toString(), httpHeaders: source.headers),
        play: true,
      );
      if (mounted) setState(() => _opened = true);
    } catch (exception) {
      if (mounted) setState(() => _error = safeErrorMessage(exception));
    }
  }

  @override
  void dispose() {
    if (_sourceRetained) {
      unawaited(widget.backend.releaseMediaPlaybackSource(widget.messageId));
    }
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _error != null
      ? Center(child: Text(_error!))
      : !_opened
      ? const Center(child: CircularProgressIndicator())
      : Center(
          child: ConstrainedBox(
            constraints: BoxConstraints.tight(MediaQuery.sizeOf(context)),
            child: _DeltiecordVideoSurface(
              player: _player,
              controller: _controller,
              opened: true,
              onToggle: _player.playOrPause,
              playTooltip: 'Play video',
            ),
          ),
        );
}

class _InlineAudio extends StatefulWidget {
  const _InlineAudio({
    required this.backend,
    required this.messageId,
    required this.attachment,
    required this.onSave,
    required this.onOpen,
  });

  final ChatBackend backend;
  final String messageId;
  final ChatAttachment attachment;
  final VoidCallback onSave;
  final VoidCallback onOpen;

  @override
  State<_InlineAudio> createState() => _InlineAudioState();
}

class _InlineAudioState extends State<_InlineAudio> {
  late final Player _player = Player();
  bool _opening = false;
  bool _opened = false;
  bool _sourceRetained = false;
  String? _error;

  Future<void> _toggle() async {
    if (_opening) return;
    if (_opened) {
      await _player.playOrPause();
      return;
    }
    setState(() => _opening = true);
    try {
      final source = await widget.backend.getMediaPlaybackSource(
        widget.messageId,
      );
      if (source == null) throw StateError('Audio playback is unavailable.');
      _sourceRetained = true;
      await _player.open(
        Media(source.uri.toString(), httpHeaders: source.headers),
        play: true,
      );
      _opened = true;
    } catch (exception) {
      _error = safeErrorMessage(exception);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  void dispose() {
    if (_sourceRetained) {
      unawaited(widget.backend.releaseMediaPlaybackSource(widget.messageId));
    }
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 460),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: context.deltiecord.elevated,
      borderRadius: DeltiecordCorners.borderRadius,
    ),
    child: StreamBuilder<bool>(
      stream: _player.stream.playing,
      initialData: _player.state.playing,
      builder: (context, snapshot) => Row(
        children: [
          IconButton(
            tooltip: snapshot.data == true ? 'Pause' : 'Play audio',
            onPressed: _toggle,
            icon: _opening
                ? const SizedBox.square(
                    dimension: 17,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(snapshot.data == true ? Icons.pause : Icons.play_arrow),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.attachment.name, overflow: TextOverflow.ellipsis),
                if (_error case final error?)
                  Text(
                    error,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: DeltiecordTypeScale.normal,
                      color: Colors.redAccent,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Open audio externally',
            onPressed: widget.onOpen,
            icon: const Icon(Icons.open_in_new, size: 18),
          ),
          IconButton(
            tooltip: 'Save audio',
            onPressed: widget.onSave,
            icon: const Icon(Icons.download, size: 19),
          ),
        ],
      ),
    ),
  );
}
