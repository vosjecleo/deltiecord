import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as image;

Future<Uint8List?> showProfileImageCropper(
  BuildContext context, {
  required Uint8List bytes,
  required String title,
  required double aspectRatio,
  required int maximumWidth,
  bool circularPreview = false,
}) => showDialog<Uint8List>(
  context: context,
  barrierDismissible: false,
  builder: (context) => _ProfileImageCropper(
    bytes: bytes,
    title: title,
    aspectRatio: aspectRatio,
    maximumWidth: maximumWidth,
    circularPreview: circularPreview,
  ),
);

@immutable
class ProfileCropRegion {
  const ProfileCropRegion({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;
}

ProfileCropRegion calculateProfileCropRegion({
  required int imageWidth,
  required int imageHeight,
  required double aspectRatio,
  required double zoom,
  required double horizontalPosition,
  required double verticalPosition,
}) {
  final sourceRatio = imageWidth / imageHeight;
  final baseWidth = sourceRatio > aspectRatio
      ? imageHeight * aspectRatio
      : imageWidth.toDouble();
  final baseHeight = sourceRatio > aspectRatio
      ? imageHeight.toDouble()
      : imageWidth / aspectRatio;
  final width = baseWidth / zoom;
  final height = baseHeight / zoom;
  return ProfileCropRegion(
    left: (imageWidth - width) * horizontalPosition.clamp(0, 1),
    top: (imageHeight - height) * verticalPosition.clamp(0, 1),
    width: width,
    height: height,
  );
}

class _ProfileImageCropper extends StatefulWidget {
  const _ProfileImageCropper({
    required this.bytes,
    required this.title,
    required this.aspectRatio,
    required this.maximumWidth,
    required this.circularPreview,
  });

  final Uint8List bytes;
  final String title;
  final double aspectRatio;
  final int maximumWidth;
  final bool circularPreview;

  @override
  State<_ProfileImageCropper> createState() => _ProfileImageCropperState();
}

class _ProfileImageCropperState extends State<_ProfileImageCropper> {
  int? _imageWidth;
  int? _imageHeight;
  double _zoom = 1;
  double _horizontal = 0.5;
  double _vertical = 0.5;
  bool _processing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _readDimensions();
  }

  Future<void> _readDimensions() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.bytes);
      final frame = await codec.getNextFrame();
      final width = frame.image.width;
      final height = frame.image.height;
      frame.image.dispose();
      codec.dispose();
      if (mounted) {
        setState(() {
          _imageWidth = width;
          _imageHeight = height;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'This image could not be decoded.');
    }
  }

  ProfileCropRegion get _region => calculateProfileCropRegion(
    imageWidth: _imageWidth!,
    imageHeight: _imageHeight!,
    aspectRatio: widget.aspectRatio,
    zoom: _zoom,
    horizontalPosition: _horizontal,
    verticalPosition: _vertical,
  );

  Future<void> _apply() async {
    if (_imageWidth == null || _processing) return;
    setState(() {
      _processing = true;
      _error = null;
    });
    try {
      final region = _region;
      final result = await compute(_cropProfileImage, (
        bytes: widget.bytes,
        left: region.left.round(),
        top: region.top.round(),
        width: region.width.round(),
        height: region.height.round(),
        maximumWidth: widget.maximumWidth,
      ));
      if (mounted) Navigator.of(context).pop(result);
    } catch (_) {
      if (mounted) {
        setState(() {
          _processing = false;
          _error = 'Deltiecord could not crop this image.';
        });
      }
    }
  }

  void _pan(DragUpdateDetails details, Size viewport) {
    setState(() {
      _horizontal = (_horizontal - details.delta.dx / viewport.width).clamp(
        0,
        1,
      );
      _vertical = (_vertical - details.delta.dy / viewport.height).clamp(0, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final previewWidth = widget.circularPreview ? 360.0 : 720.0;
    final previewHeight = previewWidth / widget.aspectRatio;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 820),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              const Text(
                'Drag the preview or use the position controls. Zooming crops '
                'more tightly; only the visible area will be uploaded.',
              ),
              const SizedBox(height: 14),
              Flexible(
                child: Center(
                  child: SizedBox(
                    width: previewWidth,
                    height: previewHeight,
                    child: _imageWidth == null
                        ? const Center(child: CircularProgressIndicator())
                        : GestureDetector(
                            onPanUpdate: (details) => _pan(
                              details,
                              Size(previewWidth, previewHeight),
                            ),
                            child: _CropPreview(
                              bytes: widget.bytes,
                              imageWidth: _imageWidth!,
                              imageHeight: _imageHeight!,
                              region: _region,
                              circular: widget.circularPreview,
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _CropSlider(
                label: 'Zoom',
                value: _zoom,
                min: 1,
                max: 4,
                onChanged: (value) => setState(() => _zoom = value),
              ),
              _CropSlider(
                label: 'Horizontal',
                value: _horizontal,
                onChanged: (value) => setState(() => _horizontal = value),
              ),
              _CropSlider(
                label: 'Vertical',
                value: _vertical,
                onChanged: (value) => setState(() => _vertical = value),
              ),
              if (_error case final error?)
                Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _processing ? null : Navigator.of(context).pop,
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _processing ? null : _apply,
                    icon: _processing
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.crop),
                    label: const Text('Use crop'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CropPreview extends StatelessWidget {
  const _CropPreview({
    required this.bytes,
    required this.imageWidth,
    required this.imageHeight,
    required this.region,
    required this.circular,
  });

  final Uint8List bytes;
  final int imageWidth;
  final int imageHeight;
  final ProfileCropRegion region;
  final bool circular;

  @override
  Widget build(BuildContext context) {
    final preview = LayoutBuilder(
      builder: (context, constraints) {
        final scale = constraints.maxWidth / region.width;
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              left: -region.left * scale,
              top: -region.top * scale,
              width: imageWidth * scale,
              height: imageHeight * scale,
              child: Image.memory(bytes, fit: BoxFit.fill),
            ),
          ],
        );
      },
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black,
        shape: circular ? BoxShape.circle : BoxShape.rectangle,
        border: Border.all(
          color: Theme.of(context).colorScheme.primary,
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: circular ? ClipOval(child: preview) : ClipRect(child: preview),
      ),
    );
  }
}

class _CropSlider extends StatelessWidget {
  const _CropSlider({
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(width: 90, child: Text(label)),
      Expanded(
        child: Slider(value: value, min: min, max: max, onChanged: onChanged),
      ),
    ],
  );
}

Uint8List _cropProfileImage(
  ({
    Uint8List bytes,
    int left,
    int top,
    int width,
    int height,
    int maximumWidth,
  })
  request,
) {
  final decoded = image.decodeImage(request.bytes);
  if (decoded == null) throw const FormatException('Unsupported image');
  final oriented = image.bakeOrientation(decoded);
  final cropWidth = request.width.clamp(1, oriented.width);
  final cropHeight = request.height.clamp(1, oriented.height);
  final cropLeft = request.left.clamp(0, oriented.width - cropWidth);
  final cropTop = request.top.clamp(0, oriented.height - cropHeight);
  var cropped = image.copyCrop(
    oriented,
    x: cropLeft,
    y: cropTop,
    width: cropWidth,
    height: cropHeight,
  );
  if (cropped.width > request.maximumWidth) {
    cropped = image.copyResize(
      cropped,
      width: request.maximumWidth,
      interpolation: image.Interpolation.cubic,
    );
  }
  return Uint8List.fromList(image.encodePng(cropped, level: 6));
}
