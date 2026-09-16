import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// GIF providers commonly expose a short MP4/WebM rendition as their OpenGraph
/// video. It should retain GIF semantics and loop continuously.
bool shouldLoopLinkPreview(Uri pageUrl) {
  final host = pageUrl.host.toLowerCase();
  return host == 'giphy.com' ||
      host.endsWith('.giphy.com') ||
      host == 'tenor.com' ||
      host.endsWith('.tenor.com') ||
      pageUrl.path.toLowerCase().endsWith('.gif');
}

/// Displays animated bytes with a codec that is recreated after app resume.
///
/// Flutter's memory-image cache keys byte arrays by identity. Matrix's media
/// cache deliberately returns that same array, so merely rebuilding after an
/// Android freeze can reconnect to a decoder that is stopped at its last
/// frame. Animated media gets a fresh byte identity on resume; static images
/// keep the zero-copy path.
class LifecycleMemoryImage extends StatefulWidget {
  const LifecycleMemoryImage({
    required this.bytes,
    required this.animated,
    required this.autoplay,
    this.fit = BoxFit.contain,
    this.width,
    this.height,
    super.key,
  });

  final Uint8List bytes;
  final bool animated;
  final bool autoplay;
  final BoxFit fit;
  final double? width;
  final double? height;

  @override
  State<LifecycleMemoryImage> createState() => _LifecycleMemoryImageState();
}

class _LifecycleMemoryImageState extends State<LifecycleMemoryImage>
    with WidgetsBindingObserver {
  late Uint8List _renderBytes = widget.bytes;
  int _generation = 0;

  bool get _animated => widget.animated || _hasGifSignature(widget.bytes);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant LifecycleMemoryImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes)) {
      _renderBytes = widget.bytes;
      _generation++;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_animated || !widget.autoplay) {
      return;
    }
    // Animated attachments are bounded by the Matrix media cache. Copying on
    // resume is intentional: it produces a new MemoryImage cache key without
    // evicting another visible widget that uses the same event bytes.
    setState(() {
      _renderBytes = Uint8List.fromList(widget.bytes);
      _generation++;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_animated && !widget.autoplay) {
      return _FirstFrameMemoryImage(
        bytes: _renderBytes,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
      );
    }
    return Image.memory(
      _renderBytes,
      key: ValueKey(_generation),
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      gaplessPlayback: true,
    );
  }

  static bool _hasGifSignature(Uint8List bytes) =>
      bytes.length >= 6 &&
      bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x38 &&
      (bytes[4] == 0x37 || bytes[4] == 0x39) &&
      bytes[5] == 0x61;
}

class _FirstFrameMemoryImage extends StatefulWidget {
  const _FirstFrameMemoryImage({
    required this.bytes,
    required this.fit,
    this.width,
    this.height,
  });

  final Uint8List bytes;
  final BoxFit fit;
  final double? width;
  final double? height;

  @override
  State<_FirstFrameMemoryImage> createState() => _FirstFrameMemoryImageState();
}

class _FirstFrameMemoryImageState extends State<_FirstFrameMemoryImage> {
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
  void didUpdateWidget(covariant _FirstFrameMemoryImage oldWidget) {
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
          : RawImage(
              image: image,
              fit: widget.fit,
              width: widget.width,
              height: widget.height,
            );
    },
  );
}
