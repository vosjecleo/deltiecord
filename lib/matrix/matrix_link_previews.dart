part of 'matrix_backend.dart';

extension _MatrixLinkPreviews on MatrixBackend {
  /// Hydrates up to three links per event after timeline text is usable.
  ///
  /// Homeserver previews remain the default. Direct origin requests happen
  /// only after explicit opt-in; a local domain card provides a deterministic
  /// non-network fallback so every HTTP(S) link still has an embed surface.
  Future<void> _hydrateLinkPreviews(Timeline timeline) async {
    final pending = <(Event, Event)>[];
    for (final event in timeline.events) {
      final displayEvent = event.type == EventTypes.Message
          ? event.getDisplayEvent(timeline)
          : event;
      if (_linkPreviews.containsKey(event.eventId) ||
          displayEvent.type != EventTypes.Message ||
          displayEvent.hasAttachment ||
          event.relationshipType == RelationshipTypes.edit) {
        continue;
      }
      pending.add((event, displayEvent));
    }

    for (var offset = 0; offset < pending.length; offset += 4) {
      final end = min(offset + 4, pending.length);
      await Future.wait(
        pending
            .sublist(offset, end)
            .map(
              (candidate) => _hydrateEventPreviews(
                sourceEvent: candidate.$1,
                displayEvent: candidate.$2,
              ),
            ),
      );
      if (!identical(timeline, _timeline)) return;
    }
  }

  Future<void> _hydrateEventPreviews({
    required Event sourceEvent,
    required Event displayEvent,
  }) async {
    final urls = extractPreviewUrls(
      displayEvent.calcUnlocalizedBody(
        hideReply: true,
        hideEdit: true,
        plaintextBody: true,
      ),
    ).toSet().take(3).toList(growable: false);
    if (urls.isEmpty) return;
    _linkPreviews[sourceEvent.eventId] = await Future.wait(
      urls.map((url) => _resolveLinkPreview(url, sourceEvent)),
    );
  }

  Future<LinkPreview> _resolveLinkPreview(Uri original, Event source) async {
    final cached = _linkPreviewUrlCache.getEntry(original);
    if (cached.$1 && cached.$2 != null) return cached.$2!;

    final requestUrl = _preferences.improveTwitterLinks
        ? fxTwitterUrl(original) ?? original
        : original;
    LinkPreview? result;
    try {
      final response = await _matrix.getUrlPreview(
        requestUrl,
        ts: source.originServerTs.millisecondsSinceEpoch,
      );
      final properties = Map<String, Object?>.from(
        response.additionalProperties,
      );
      Uint8List? imageBytes;
      final image = response.ogImage;
      final declaredImageSize =
          response.matrixImageSize ??
          _previewPropertyInt(properties, const [
            'matrix:image:size',
            'og:image:size',
          ]);
      if (image != null &&
          LinkPreviewNetworkPolicy.mayLoadMedia(image) &&
          (declaredImageSize == null || declaredImageSize <= 5 * 1024 * 1024)) {
        try {
          imageBytes = await _previewImageBytes(image);
        } catch (exception) {
          developer.log(
            'Homeserver preview image unavailable '
            '(${exception.runtimeType}).',
            name: 'deltiecord.preview',
          );
        }
      }
      final parsed = parseHomeserverLinkPreview(
        url: original,
        properties: properties,
        imageBytes: imageBytes,
      );
      if (hasUsefulPreview(parsed)) result = parsed;
    } catch (exception) {
      developer.log(
        'Homeserver URL preview failed (${exception.runtimeType}).',
        name: 'deltiecord.preview',
      );
    }

    if (result == null &&
        LinkPreviewNetworkPolicy.allowsDirectFallback(
          _preferences.fetchDirectLinkPreviews,
        )) {
      try {
        final fetched = await _directPreviewFetcher.fetch(requestUrl);
        if (fetched != null) result = _previewAtOriginalUrl(fetched, original);
      } catch (exception) {
        developer.log(
          'Opt-in direct URL preview failed (${exception.runtimeType}).',
          name: 'deltiecord.preview',
        );
      }
    }

    result ??= LinkPreview(
      url: original,
      title: original.host,
      siteName: original.host,
    );
    _linkPreviewUrlCache.put(original, result);
    return result;
  }

  LinkPreview _previewAtOriginalUrl(LinkPreview preview, Uri original) =>
      LinkPreview(
        url: original,
        title: preview.title,
        description: preview.description,
        siteName: preview.siteName,
        imageBytes: preview.imageBytes,
        videoUrl: preview.videoUrl,
        width: preview.width,
        height: preview.height,
      );

  int? _previewPropertyInt(Map<String, Object?> properties, List<String> keys) {
    for (final key in keys) {
      final value = properties[key];
      final parsed = value is num ? value.toInt() : int.tryParse('$value');
      if (parsed != null && parsed >= 0) return parsed;
    }
    return null;
  }

  Future<Uint8List?> _previewImageBytes(Uri uri) async {
    if (!uri.isScheme('mxc')) return null;
    final thumbnail = await _matrix.getContentThumbnail(
      uri.host,
      uri.pathSegments.join('/'),
      640,
      360,
      method: Method.scale,
      animated: true,
    );
    return thumbnail.data.length <= 5 * 1024 * 1024 ? thumbnail.data : null;
  }
}
