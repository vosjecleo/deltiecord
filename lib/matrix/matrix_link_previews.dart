part of 'matrix_backend.dart';

extension _MatrixLinkPreviews on MatrixBackend {
  /// Hydrates preview metadata after timeline text is already available.
  ///
  /// The Matrix homeserver remains the primary and privacy-preserving fetcher.
  /// Direct origin requests are made only after explicit user opt-in and only
  /// by [DirectLinkPreviewFetcher], which pins public DNS results to sockets.
  Future<void> _hydrateLinkPreviews(Timeline timeline) async {
    final pending = <(Event, Event)>[];
    for (final event in timeline.events) {
      final retryAfter = _linkPreviewRetryAfter[event.eventId];
      final displayEvent = event.type == EventTypes.Message
          ? event.getDisplayEvent(timeline)
          : event;
      if (_linkPreviews.containsKey(event.eventId) ||
          (retryAfter != null && DateTime.now().isBefore(retryAfter)) ||
          displayEvent.type != EventTypes.Message ||
          displayEvent.hasAttachment ||
          event.relationshipType == RelationshipTypes.edit) {
        continue;
      }
      pending.add((event, displayEvent));
    }

    // Limit parallel homeserver requests. This keeps an embed-heavy room from
    // serially delaying previews while avoiding an unbounded request burst.
    for (var offset = 0; offset < pending.length; offset += 4) {
      final end = min(offset + 4, pending.length);
      await Future.wait(
        pending
            .sublist(offset, end)
            .map(
              (candidate) => _hydrateEventPreview(
                sourceEvent: candidate.$1,
                displayEvent: candidate.$2,
              ),
            ),
      );
      if (!identical(timeline, _timeline)) return;
    }
  }

  Future<void> _hydrateEventPreview({
    required Event sourceEvent,
    required Event displayEvent,
  }) async {
    final urls = extractPreviewUrls(
      displayEvent.calcUnlocalizedBody(
        hideReply: true,
        hideEdit: true,
        plaintextBody: true,
      ),
    );
    if (urls.isEmpty) {
      // Do not turn an event into a permanent miss. A late edit/replacement
      // can add a URL without replacing the original event ID used by the UI.
      return;
    }
    final url = urls.first;
    final cached = _linkPreviewUrlCache.getEntry(url);
    if (cached.$1) {
      if (cached.$2 case final preview?) {
        _linkPreviews[sourceEvent.eventId] = preview;
      }
      return;
    }

    LinkPreview? result;
    Object? homeserverFailure;
    try {
      final response = await _matrix.getUrlPreview(
        url,
        ts: sourceEvent.originServerTs.millisecondsSinceEpoch,
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
        // Preview media is optional. A stale/missing MXC thumbnail must not
        // discard otherwise useful OpenGraph title and description metadata.
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
      result = parseHomeserverLinkPreview(
        url: url,
        properties: properties,
        imageBytes: imageBytes,
      );
      if (!hasUsefulPreview(result)) result = null;
    } catch (exception) {
      homeserverFailure = exception;
    }

    if (result == null &&
        LinkPreviewNetworkPolicy.allowsDirectFallback(
          _preferences.fetchDirectLinkPreviews,
        )) {
      try {
        result = await _directPreviewFetcher.fetch(url);
      } catch (exception) {
        developer.log(
          'Opt-in direct URL preview failed (${exception.runtimeType}).',
          name: 'deltiecord.preview',
        );
      }
    }

    if (result != null) {
      _linkPreviews[sourceEvent.eventId] = result;
      _linkPreviewUrlCache.put(url, result);
      _linkPreviewRetryAfter.remove(sourceEvent.eventId);
      _linkPreviewAttempts.remove(sourceEvent.eventId);
      return;
    }

    if (homeserverFailure == null) {
      // Keep a valid empty response only in the expiring URL cache. Storing a
      // null event result made it impossible for the same timeline to recover
      // when a server's preview cache populated later.
      _linkPreviewUrlCache.put(url, null);
      return;
    }

    final attempts = (_linkPreviewAttempts[sourceEvent.eventId] ?? 0) + 1;
    _linkPreviewAttempts[sourceEvent.eventId] = attempts;
    developer.log(
      'Homeserver URL preview attempt failed '
      '(${homeserverFailure.runtimeType}).',
      name: 'deltiecord.preview',
    );
    if (attempts >= 3) {
      // The homeserver can legitimately omit the preview API. Cache the URL
      // miss briefly, but leave the event retryable and allow the opt-in
      // direct fallback to work immediately after its preference is enabled.
      _linkPreviewUrlCache.put(url, null);
      _linkPreviewAttempts.remove(sourceEvent.eventId);
      _linkPreviewRetryAfter[sourceEvent.eventId] = DateTime.now().add(
        _linkPreviewUrlCache.failureLifetime,
      );
      return;
    }
    _linkPreviewRetryAfter[sourceEvent.eventId] = DateTime.now().add(
      const Duration(seconds: 30),
    );
    final timeline = _timeline;
    if (timeline != null) _scheduleLinkPreviewRetry(timeline);
  }

  int? _previewPropertyInt(Map<String, Object?> properties, List<String> keys) {
    for (final key in keys) {
      final value = properties[key];
      final parsed = value is num ? value.toInt() : int.tryParse('$value');
      if (parsed != null && parsed >= 0) return parsed;
    }
    return null;
  }

  void _scheduleLinkPreviewRetry(Timeline timeline) {
    if (_linkPreviewRetryTimer?.isActive == true) return;
    _linkPreviewRetryTimer = Timer(const Duration(seconds: 31), () async {
      _linkPreviewRetryTimer = null;
      if (!identical(timeline, _timeline)) return;
      await _hydrateLinkPreviews(timeline);
      if (identical(timeline, _timeline)) _notifyBackendListeners();
    });
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
