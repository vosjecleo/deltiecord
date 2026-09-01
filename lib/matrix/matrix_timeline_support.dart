part of 'matrix_backend.dart';

/// Decrypts timeline events and progressively hydrates optional metadata.
///
/// Text is published before avatars, replies, and previews. Hydration passes
/// are serialized because sync bursts can otherwise duplicate network work and
/// let stale room results outlive a fast room switch.
extension _MatrixTimelineSupport on MatrixBackend {
  int get _timelineWindowCapacity => TimelineWindowPolicy.hardCap(
    chunkSize: _preferences.timelineChunkSize,
    chunkCap: _preferences.timelineChunkCap,
  );

  List<Event> _timelineWindowEvents(Timeline timeline) {
    final start = _timelineWindowStart.clamp(0, timeline.events.length);
    final end = min(timeline.events.length, start + _timelineWindowCapacity);
    return timeline.events.sublist(start, end);
  }

  void _setTimelineWindowStart(Timeline timeline, int start) {
    final maximum = TimelineWindowPolicy.maximumWindowStart(
      eventCount: timeline.events.length,
      capacity: _timelineWindowCapacity,
    );
    _timelineWindowStart = start.clamp(0, maximum);
    _timelineHasPrunedNewerEvents = _timelineWindowStart > 0;
    _timelineWindowHeadEventId = timeline.events.isEmpty
        ? null
        : timeline.events[_timelineWindowStart].eventId;
  }

  void _setTimelineWindowStartPreserving(
    Timeline timeline,
    int start,
    String? anchorEventId,
  ) {
    final anchorIndex = anchorEventId == null
        ? null
        : timeline.events.indexWhere((event) => event.eventId == anchorEventId);
    _setTimelineWindowStart(
      timeline,
      TimelineWindowPolicy.preserveAnchor(
        desiredStart: start,
        eventCount: timeline.events.length,
        capacity: _timelineWindowCapacity,
        anchorIndex: anchorIndex == -1 ? null : anchorIndex,
      ),
    );
  }

  void _stabilizeTimelineWindow(Timeline timeline) {
    if (!_timelineHasPrunedNewerEvents) return;
    final head = _timelineWindowHeadEventId;
    if (head == null) return;
    final index = timeline.events.indexWhere((event) => event.eventId == head);
    if (index >= 0) _setTimelineWindowStart(timeline, index);
  }

  Future<void> _hydrateSenderAvatars(Timeline timeline) async {
    final missing = <(String, Uri)>[];
    final seen = <String>{};
    for (final event in _timelineWindowEvents(timeline)) {
      if (!seen.add(event.senderId)) continue;
      final sender = event.senderFromMemoryOrFallback;
      final avatar = sender.avatarUrl;
      if (_senderAvatarUris.containsKey(event.senderId) &&
          _senderAvatarUris[event.senderId] == avatar &&
          _senderAvatarBytes[event.senderId] != null) {
        continue;
      }
      _senderAvatarUris[event.senderId] = avatar;
      _senderAvatarBytes.remove(event.senderId);
      if (avatar == null || !avatar.isScheme('mxc')) continue;

      final profile = _profileCache[event.senderId];
      if (profile?.avatarUri == avatar &&
          profile?.profile.avatarBytes != null) {
        final bytes = profile!.profile.avatarBytes!;
        _avatarMediaPool.seed(avatar, bytes, AvatarMediaPool.profileDimension);
        _senderAvatarBytes[event.senderId] = bytes;
        continue;
      }
      final pooled = _avatarMediaPool.peek(
        avatar,
        AvatarMediaPool.rowDimension,
      );
      if (pooled != null) {
        _senderAvatarBytes[event.senderId] = pooled;
        continue;
      }
      missing.add((event.senderId, avatar));
    }

    for (var start = 0; start < missing.length; start += 4) {
      final end = min(start + 4, missing.length);
      await Future.wait(
        missing.sublist(start, end).map((entry) async {
          try {
            final bytes = await _avatarMedia(
              entry.$2,
              AvatarMediaPool.rowDimension,
            );
            if (bytes != null && _senderAvatarUris[entry.$1] == entry.$2) {
              _senderAvatarBytes[entry.$1] = bytes;
            }
          } catch (_) {
            // Missing profile media should fall back to an initial.
          }
        }),
      );
      if (identical(_timeline, timeline)) _notifyBackendListeners();
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
      // Keep the original event ID as the navigation target, but render its
      // latest replacement so reply previews cannot preserve a stale body.
      final originalEventId = repliedTo.eventId;
      final displayEvent = repliedTo.getDisplayEvent(timeline);
      _replyPreviews[event.eventId] = ReplyPreview(
        eventId: originalEventId,
        sender: displayEvent.senderFromMemoryOrFallback.calcDisplayname(),
        body: displayEvent.calcUnlocalizedBody(
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
    final timeline = _timeline;
    if (timeline != null) {
      _stabilizeTimelineWindow(timeline);
      _notifyBackendListeners();
      unawaited(_hydrateCurrentTimeline(timeline, generation));
      unawaited(_markSelectedRoomRead());
    }
  }

  Future<void> _hydrateCurrentTimeline(
    Timeline timeline,
    int generation,
  ) async {
    if (!_isCurrentTimeline(timeline, generation)) return;
    _timelineHydrationRequested = true;
    if (_timelineHydrationRunning) return;
    _timelineHydrationRunning = true;
    try {
      while (_timelineHydrationRequested) {
        _timelineHydrationRequested = false;
        final currentTimeline = _timeline;
        final currentGeneration = _timelineGeneration;
        if (currentTimeline == null ||
            !_isCurrentTimeline(currentTimeline, currentGeneration)) {
          continue;
        }
        final metadataTimer = Stopwatch()..start();
        await _hydrateTimelineMetadata(currentTimeline);
        if (!_isCurrentTimeline(currentTimeline, currentGeneration)) continue;
        _roomMessageCache[currentTimeline.room.id] = List.unmodifiable(
          _mappedMessages,
        );
        _debugRoomOpenTiming(
          'metadata_ms=${metadataTimer.elapsedMilliseconds} '
          'events=${currentTimeline.events.length}',
        );
      }
    } finally {
      _timelineHydrationRunning = false;
      // A timeline update can race the final loop condition. Reschedule rather
      // than allowing two hydration passes to overlap network and cache work.
      if (_timelineHydrationRequested && _timeline != null) {
        unawaited(_hydrateCurrentTimeline(_timeline!, _timelineGeneration));
      }
    }
  }

  Future<void> _markSelectedRoomRead() async {
    if (!_preferences.sendReadReceipts || !_mayAdvanceReadMarker) return;
    final initialTimeline = _timeline;
    if (initialTimeline == null || initialTimeline.room.id != _selectedRoomId) {
      return;
    }
    final roomId = initialTimeline.room.id;
    if (_roomsMarkingRead.contains(roomId)) return;
    _roomsMarkingRead.add(roomId);
    try {
      while (identical(initialTimeline, _timeline) &&
          roomId == _selectedRoomId &&
          _mayAdvanceReadMarker) {
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
