import 'dart:typed_data';

import 'package:flutter/material.dart';

final Expando<Future<Color>> _avatarColours = Expando<Future<Color>>();

/// Derives and memoizes a representative colour for an already cached avatar.
///
/// Flutter's image quantizer downsamples before extracting the palette, so the
/// calculation does not keep a second full-size decoded avatar alive.
Future<Color> representativeAvatarColor(
  Uint8List? bytes, {
  Color fallback = const Color(0xff353846),
}) {
  if (bytes == null || bytes.isEmpty) return Future.value(fallback);
  return _avatarColours[bytes] ??= ColorScheme.fromImageProvider(
    provider: MemoryImage(bytes),
    brightness: Brightness.dark,
  ).then((scheme) => scheme.primaryContainer).onError((_, _) => fallback);
}
