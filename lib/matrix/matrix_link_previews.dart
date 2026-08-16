part of 'matrix_backend.dart';

extension _MatrixLinkPreviews on MatrixBackend {
  /// Resolves previews exclusively through the configured Matrix homeserver.
  ///
  /// A previous implementation contacted linked pages, FxTwitter, and remote
  /// preview images directly when Synapse returned no metadata. That exposed a
  /// reader's IP address and viewing time to arbitrary message-linked hosts.
  /// Failed or empty homeserver previews intentionally remain plain links.
  Future<void> _hydrateLinkPreviews(Timeline timeline) async {
    for (final event in timeline.events) {
      if (_linkPreviews.containsKey(event.eventId) ||
          event.type != EventTypes.Message ||
          event.hasAttachment) {
        continue;
      }
      final match = _webUrlPattern.firstMatch(
        event.calcUnlocalizedBody(
          hideReply: true,
          hideEdit: true,
          plaintextBody: true,
        ),
      );
      final rawUrl = match?.group(0)?.replaceFirst(RegExp(r'[.,;:!?]+$'), '');
      final url = rawUrl == null ? null : Uri.tryParse(rawUrl);
      if (url == null) {
        _linkPreviews[event.eventId] = null;
        continue;
      }
      // The standard endpoint lets the homeserver apply its SSRF protections
      // and cache metadata consistently with other Matrix clients.
      try {
        final preview = await _matrix.getUrlPreview(
          url,
          ts: event.originServerTs.millisecondsSinceEpoch,
        );
        final properties = preview.additionalProperties;
        Uint8List? imageBytes;
        final image = preview.ogImage;
        // Synapse normally stores fetched preview images as MXC content. Never
        // follow an arbitrary HTTP image URL returned in preview metadata.
        if (image != null && LinkPreviewNetworkPolicy.mayLoadMedia(image)) {
          imageBytes = await _previewImageBytes(image);
        }
        String? propertyString(String key) {
          final value = properties[key];
          return value is String && value.trim().isNotEmpty
              ? value.trim()
              : null;
        }

        int? propertyInt(String key) {
          final value = properties[key];
          return value is int ? value : int.tryParse(value?.toString() ?? '');
        }

        final result = LinkPreview(
          url: url,
          title: propertyString('og:title'),
          description: propertyString('og:description'),
          siteName: propertyString('og:site_name'),
          imageBytes: imageBytes,
          // A remote og:video URL would be fetched by media_kit from this
          // device. Keep preview playback disabled unless a future homeserver
          // API provides an authenticated MXC-backed playback source.
          videoUrl: null,
          width: propertyInt('og:video:width') ?? propertyInt('og:image:width'),
          height:
              propertyInt('og:video:height') ?? propertyInt('og:image:height'),
        );
        _linkPreviews[event.eventId] =
            result.title == null &&
                result.description == null &&
                result.imageBytes == null &&
                result.videoUrl == null
            ? null
            : result;
      } catch (_) {
        _linkPreviews[event.eventId] = null;
      }
    }
  }

  Future<Uint8List?> _previewImageBytes(Uri uri) async {
    if (uri.isScheme('mxc')) {
      final thumbnail = await _matrix.getContentThumbnail(
        uri.host,
        uri.pathSegments.join('/'),
        640,
        360,
        method: Method.scale,
        animated: true,
      );
      return thumbnail.data;
    }
    return null;
  }
}
