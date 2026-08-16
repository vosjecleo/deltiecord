part of 'matrix_backend.dart';

extension _MatrixTimelineSupport on MatrixBackend {
  Future<void> _hydrateSenderAvatars(Timeline timeline) async {
    for (final event in timeline.events) {
      final sender = event.senderFromMemoryOrFallback;
      final avatar = sender.avatarUrl;
      if (_senderAvatarUris.containsKey(event.senderId) &&
          _senderAvatarUris[event.senderId] == avatar) {
        continue;
      }
      _senderAvatarUris[event.senderId] = avatar;
      _senderAvatarBytes.remove(event.senderId);
      if (avatar == null || !avatar.isScheme('mxc')) continue;
      try {
        final response = await _matrix.getContentThumbnail(
          avatar.host,
          avatar.pathSegments.join('/'),
          64,
          64,
          method: Method.crop,
          animated: false,
        );
        _senderAvatarBytes[event.senderId] = response.data;
      } catch (_) {
        // Missing profile media should fall back to an initial.
      }
    }
  }

  Future<void> _hydrateReplies(Timeline timeline) async {
    for (final event in timeline.events) {
      if (event.type != EventTypes.Message ||
          event.inReplyToEventId() == null ||
          _replyPreviews.containsKey(event.eventId)) {
        continue;
      }
      var repliedTo = await event.getReplyEvent(timeline);
      if (repliedTo == null) continue;
      if (repliedTo.type == EventTypes.Encrypted &&
          _matrix.encryption != null) {
        repliedTo = await _matrix.encryption!.decryptRoomEvent(repliedTo);
      }
      if (repliedTo.type != EventTypes.Message) continue;
      _replyPreviews[event.eventId] = ReplyPreview(
        eventId: repliedTo.eventId,
        sender: repliedTo.senderFromMemoryOrFallback.calcDisplayname(),
        body: repliedTo.calcUnlocalizedBody(
          hideReply: true,
          hideEdit: true,
          plaintextBody: true,
        ),
      );
    }
  }

  Future<void> _loadRoomBackupKeys(Room room) async {
    if (!room.encrypted || _loadedBackupRoomIds.contains(room.id)) return;
    final keyManager = _matrix.encryption?.keyManager;
    if (keyManager == null || !keyManager.enabled) return;
    if (!await keyManager.isCached()) return;
    try {
      await keyManager.loadAllKeysFromRoom(room.id);
      _loadedBackupRoomIds.add(room.id);
    } on MatrixException catch (exception) {
      if (exception.error != MatrixError.M_NOT_FOUND) rethrow;
    }
  }

  Future<void> _decryptTimelineEvents(Timeline timeline) async {
    final encryption = _matrix.encryption;
    if (encryption == null) return;
    await _matrix.database.transaction(() async {
      for (var index = 0; index < timeline.events.length; index++) {
        final event = timeline.events[index];
        if (event.type != EventTypes.Encrypted) continue;
        timeline.events[index] = await encryption.decryptRoomEvent(
          event,
          store: true,
          updateType: EventUpdateType.history,
        );
      }
    });
    _notifyBackendListeners();
  }

  Future<void> _hydrateTimelineMetadata(Timeline timeline) async {
    final retainedEventIds = timeline.events
        .map((event) => event.eventId)
        .toSet();
    _replyPreviews.removeWhere(
      (eventId, _) => !retainedEventIds.contains(eventId),
    );
    _linkPreviews.removeWhere(
      (eventId, _) => !retainedEventIds.contains(eventId),
    );
    for (final eventId
        in _mediaPlaybackSources.keys
            .where((eventId) => !retainedEventIds.contains(eventId))
            .toList(growable: false)) {
      final source = _mediaPlaybackSources.remove(eventId);
      _mediaPlaybackReferences.remove(eventId);
      if (source != null) _mediaRangeProxy.unregister(source.uri);
    }
    await Future.wait([
      _hydrateSenderAvatars(timeline),
      _hydrateReplies(timeline),
    ]);
    if (!identical(timeline, _timeline)) return;
    _notifyBackendListeners();
    await _hydrateLinkPreviews(timeline);
    if (!identical(timeline, _timeline)) return;
    _notifyBackendListeners();
  }

  Future<void> _prepareEncryptedSend(Room room) async {
    if (!room.encrypted || _outboundSessionsReset.contains(room.id)) return;
    final keyManager = _matrix.encryption?.keyManager;
    if (keyManager == null) {
      throw StateError('End-to-end encryption is not ready.');
    }
    // Sessions created under the earlier verified-only policy remember the
    // excluded devices. Rotate once so all current non-blocked devices receive
    // the new Megolm session before ciphertext is sent.
    await keyManager.loadOutboundGroupSession(room.id);
    await keyManager.clearOrUseOutboundGroupSession(room.id, wipe: true);
    _outboundSessionsReset.add(room.id);
  }

  bool _isCurrentSelection(String roomId, int generation) =>
      generation == _timelineGeneration && roomId == _selectedRoomId;

  bool _isCurrentTimeline(Timeline timeline, int generation) =>
      generation == _timelineGeneration && identical(timeline, _timeline);

  void _onTimelineUpdate(int generation) {
    if (generation != _timelineGeneration) return;
    _notifyBackendListeners();
    final timeline = _timeline;
    if (timeline != null) {
      unawaited(_hydrateCurrentTimeline(timeline, generation));
      unawaited(_markSelectedRoomRead());
    }
  }

  Future<void> _hydrateCurrentTimeline(
    Timeline timeline,
    int generation,
  ) async {
    if (!_isCurrentTimeline(timeline, generation)) return;
    await _hydrateTimelineMetadata(timeline);
    if (!_isCurrentTimeline(timeline, generation)) return;
    _roomMessageCache[timeline.room.id] = List.unmodifiable(_mappedMessages);
  }

  Future<void> _markSelectedRoomRead() async {
    if (!_preferences.sendReadReceipts) return;
    final initialTimeline = _timeline;
    if (initialTimeline == null || initialTimeline.room.id != _selectedRoomId) {
      return;
    }
    final roomId = initialTimeline.room.id;
    if (_roomsMarkingRead.contains(roomId)) return;
    _roomsMarkingRead.add(roomId);
    try {
      while (identical(initialTimeline, _timeline) &&
          roomId == _selectedRoomId) {
        String? newestSyncedEventId;
        for (final event in initialTimeline.events) {
          if (event.status.isSynced) {
            newestSyncedEventId = event.eventId;
            break;
          }
        }
        if (newestSyncedEventId == null ||
            newestSyncedEventId == _lastMarkedReadEventIds[roomId]) {
          return;
        }
        // Timeline.setReadMarker sends both the fully-read marker and the
        // account's configured public/private receipt for this event.
        await initialTimeline.setReadMarker(eventId: newestSyncedEventId);
        _lastMarkedReadEventIds[roomId] = newestSyncedEventId;
      }
    } catch (_) {
      // Receipt failures are non-fatal and will be retried on the next update.
    } finally {
      _roomsMarkingRead.remove(roomId);
    }
  }
}
