import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../backend/chat_backend.dart';
import '../../models/chat_models.dart';
import '../../services/temporary_attachment_store.dart';

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
}

class _MobileImage extends StatelessWidget {
  const _MobileImage({required this.backend, required this.message});
  final ChatBackend backend;
  final ChatMessage message;

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: backend.downloadAttachment(message.id),
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
        onTap: () => showDialog<void>(
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
                Positioned(
                  right: 12,
                  top: 12,
                  child: SafeArea(
                    child: IconButton.filled(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
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
          borderRadius: BorderRadius.circular(10),
          child: Video(
            controller: _video!,
            controls: AdaptiveVideoControls,
            fit: BoxFit.contain,
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
            if (preview.imageBytes case final image?)
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
