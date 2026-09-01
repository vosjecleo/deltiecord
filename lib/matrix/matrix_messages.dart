part of 'matrix_backend.dart';

extension _MatrixMessages on MatrixBackend {
  Future<List<ChatMessage>> _loadPinnedMessages() async {
    final room = _matrix.getRoomById(_selectedRoomId ?? '');
    if (room == null || room.pinnedEventIds.isEmpty) return const [];
    final roomId = room.id;
    final results = <ChatMessage>[];
    for (final eventId in room.pinnedEventIds) {
      try {
        var event = await room.getEventById(eventId);
        if (_selectedRoomId != roomId) return const [];
        if (event == null) continue;
        if (event.type == EventTypes.Encrypted && _matrix.encryption != null) {
          event = await _matrix.encryption!.decryptRoomEvent(event);
        }
        if (event.type == EventTypes.Message) {
          results.add(_searchResultFromEvent(event));
        }
      } catch (_) {
        // A redacted or inaccessible pin must not prevent other pins loading.
      }
    }
    results.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return results;
  }

  Future<List<ChatMessage>> _searchRoomHistory(String query) async {
    final normalized = query.trim();
    final room = _matrix.getRoomById(_selectedRoomId ?? '');
    if (normalized.isEmpty || room == null) return const [];
    final roomId = room.id;
    try {
      final result = await room.searchEvents(
        searchTerm: normalized,
        limit: max(100, _preferences.timelineChunkSize),
      );
      if (_selectedRoomId != roomId) return const [];
      final matches = <String, ChatMessage>{
        for (final message in searchMessages(normalized)) message.id: message,
      };
      for (var event in result.events) {
        if (event.type == EventTypes.Encrypted && _matrix.encryption != null) {
          try {
            event = await _matrix.encryption!.decryptRoomEvent(event);
          } catch (_) {
            continue;
          }
        }
        if (event.type != EventTypes.Message) continue;
        final message = _searchResultFromEvent(event);
        if (!matchesMessageSearch(
          body: message.body,
          sender: message.sender,
          query: normalized,
        )) {
          continue;
        }
        matches[message.id] = message;
      }
      final sorted = matches.values.toList(growable: false)
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return sorted;
    } catch (exception) {
      if (_selectedRoomId == roomId) {
        _error = _friendlyError(exception);
        _notifyBackendListeners();
      }
      rethrow;
    }
  }

  ChatMessage _searchResultFromEvent(Event event) => ChatMessage(
    id: event.eventId,
    sender: event.senderFromMemoryOrFallback.calcDisplayname(),
    senderId: event.senderId,
    body: event.calcUnlocalizedBody(
      hideReply: true,
      hideEdit: true,
      plaintextBody: true,
    ),
    timestamp: event.originServerTs,
    pending: false,
    own: event.senderId == _matrix.userID,
    avatarBytes: _senderAvatarBytes[event.senderId],
  );

  Future<void> _loadMoreHistory() async {
    final timeline = _timeline;
    if (timeline == null || _historyLoading || !canLoadMoreHistory) {
      return;
    }
    final loadedWindowEnd = _timelineWindowStart + _timelineWindowCapacity;
    if (loadedWindowEnd < timeline.events.length) {
      _setTimelineWindowStart(
        timeline,
        TimelineWindowPolicy.moveOlder(
          currentStart: _timelineWindowStart,
          eventCount: timeline.events.length,
          capacity: _timelineWindowCapacity,
          pageSize: _preferences.timelineChunkSize,
        ),
      );
      _notifyBackendListeners();
      return;
    }
    _historyLoading = true;
    _notifyBackendListeners();
    try {
      final pageSize = _preferences.timelineChunkSize;
      var loaded = 0;
      var visibleLoaded = 0;
      // Relations, edits, and malformed events do not become visible rows. A
      // single raw 30-event page can therefore yield far fewer than 30 chat
      // rows. Continue through a bounded number of raw pages so opening a room
      // does not immediately strand the user behind another pagination click.
      for (
        var pass = 0;
        pass < 8 && visibleLoaded < pageSize && canLoadMoreHistory;
        pass++
      ) {
        final beforeIds = timeline.events.map((event) => event.eventId).toSet();
        var pageLoaded = 0;
        if (!_timelineDatabaseExhausted) {
          pageLoaded = await _appendStoredHistory(timeline, pageSize);
        }
        if (pageLoaded == 0 && _timelineDatabaseExhausted) {
          pageLoaded = await _appendServerHistory(timeline, pageSize);
        }
        loaded += pageLoaded;
        if (!identical(timeline, _timeline)) return;
        visibleLoaded += timeline.events.where((event) {
          return !beforeIds.contains(event.eventId) &&
              _isVisibleTimelineEvent(event) &&
              event.relationshipType != RelationshipTypes.edit;
        }).length;
        if (pageLoaded == 0 && !canLoadMoreHistory) break;
      }
      if (!identical(timeline, _timeline)) return;
      if (loaded == 0) return;
      // The SDK keeps the complete active-room event list so its relation and
      // pagination state remains authoritative. Only Deltiecord's independent
      // presentation window moves; this avoids corrupting the SDK list while
      // retaining the configured widget/mapping cap.
      _setTimelineWindowStart(
        timeline,
        max(0, timeline.events.length - _timelineWindowCapacity),
      );
      await _decryptTimelineEvents(timeline);
      if (!identical(timeline, _timeline)) return;
      unawaited(_hydrateCurrentTimeline(timeline, _timelineGeneration));
    } catch (exception) {
      _error = _friendlyError(exception);
    } finally {
      _historyLoading = false;
      _notifyBackendListeners();
    }
  }

  Future<int> _appendStoredHistory(Timeline timeline, int pageSize) async {
    var added = 0;
    final knownEventIds = timeline.events.map((event) => event.eventId).toSet();
    while (added < pageSize && !_timelineDatabaseExhausted) {
      final requested = pageSize - added;
      final stored = await _matrix.database.getEventList(
        timeline.room,
        start: _timelineDatabaseOffset,
        limit: requested,
      );
      _timelineDatabaseOffset = TimelineWindowPolicy.advanceDatabaseOffset(
        _timelineDatabaseOffset,
        stored.length,
      );
      if (stored.length < requested) _timelineDatabaseExhausted = true;
      if (stored.isEmpty) break;
      for (final event in stored) {
        if (!knownEventIds.add(event.eventId)) continue;
        timeline.addAggregatedEvent(event);
        timeline.events.add(event);
        added++;
      }
    }
    return added;
  }

  Future<int> _appendServerHistory(Timeline timeline, int pageSize) async {
    if (timeline.chunk.prevBatch.isEmpty) {
      timeline.chunk.prevBatch = timeline.room.prev_batch ?? '';
    }
    if (timeline.chunk.prevBatch.isEmpty) {
      _timelineServerExhausted = true;
      return 0;
    }
    // Once local history is consumed, paginate with the chunk token directly.
    // Deltiecord's separate database cursor may have consumed local rows even
    // when the SDK timeline still has a usable server continuation token.
    timeline.isFragmentedTimeline = true;
    final beforeIds = timeline.events.map((event) => event.eventId).toSet();
    final previousToken = timeline.chunk.prevBatch;
    await timeline.getRoomEvents(
      historyCount: pageSize,
      direction: Direction.b,
    );
    TimelineWindowPolicy.deduplicateBy(
      timeline.events,
      (event) => event.eventId,
    );
    final loaded = timeline.events
        .where((event) => !beforeIds.contains(event.eventId))
        .length;
    if (timeline.chunk.prevBatch.isEmpty ||
        timeline.chunk.prevBatch == previousToken) {
      _timelineServerExhausted = true;
    }
    return loaded;
  }

  Future<void> _loadMoreFuture() async {
    final timeline = _timeline;
    if (timeline == null ||
        _historyLoading ||
        (!_timelineHasPrunedNewerEvents && !timeline.canRequestFuture)) {
      return;
    }
    _historyLoading = true;
    _notifyBackendListeners();
    try {
      if (_timelineWindowStart > 0) {
        _setTimelineWindowStart(
          timeline,
          TimelineWindowPolicy.moveNewer(
            currentStart: _timelineWindowStart,
            pageSize: _preferences.timelineChunkSize,
          ),
        );
        unawaited(_hydrateCurrentTimeline(timeline, _timelineGeneration));
        return;
      }
      if (timeline.canRequestFuture) {
        await timeline.requestFuture(
          historyCount: _preferences.timelineChunkSize,
        );
      }
      if (!identical(timeline, _timeline)) return;
      TimelineWindowPolicy.deduplicateBy(
        timeline.events,
        (event) => event.eventId,
      );
      _setTimelineWindowStart(timeline, 0);
      await _decryptTimelineEvents(timeline);
      if (!identical(timeline, _timeline)) return;
      unawaited(_hydrateCurrentTimeline(timeline, _timelineGeneration));
    } catch (exception) {
      _error = _friendlyError(exception);
    } finally {
      _historyLoading = false;
      _notifyBackendListeners();
    }
  }

  Future<void> _sendMessage(
    String text, {
    String? roomId,
    String? formattedBody,
    String? replyToMessageId,
    String? editMessageId,
  }) async {
    final originalValue = text.trim();
    final value = _preferences.improveTwitterLinks
        ? rewriteTwitterLinks(originalValue)
        : originalValue;
    final targetRoomId = roomId ?? _selectedRoomId;
    if (value.isEmpty || targetRoomId == null) return;
    try {
      final room = _matrix.getRoomById(targetRoomId);
      if (room == null) throw StateError('The selected room is unavailable.');
      await _prepareEncryptedSend(room);
      final transactionId = _matrix.generateUniqueTransactionId();
      final replyEvent = replyToMessageId == null
          ? null
          : _eventById(replyToMessageId);
      late final Future<String?> operation;
      final outgoingFormattedBody =
          formattedBody != null && _preferences.improveTwitterLinks
          ? rewriteTwitterLinks(formattedBody)
          : formattedBody;
      if (outgoingFormattedBody == null || outgoingFormattedBody.isEmpty) {
        operation = room.sendTextEvent(
          value,
          txid: transactionId,
          inReplyTo: replyEvent,
          editEventId: editMessageId,
          // Deltiecord does not expose the SDK's slash-command interface.
          // Treat Unix paths and other leading-slash text literally.
          parseCommands: false,
          // Rich markup is serialized by the composer and uses the branch
          // below; avoid a second, behaviorally different Markdown pass.
          parseMarkdown: false,
        );
      } else {
        operation = room.sendEvent(
          {
            'msgtype': MessageTypes.Text,
            'body': value,
            'format': 'org.matrix.custom.html',
            'formatted_body': outgoingFormattedBody,
            ..._mentionsFor(value, replyEvent),
          },
          inReplyTo: replyEvent,
          editEventId: editMessageId,
          txid: transactionId,
        );
      }
      if (_connectionStatus != ConnectionStatus.online) {
        _offlineSendRooms[transactionId] = room.id;
        _notifyBackendListeners();
        unawaited(_completeOfflineSend(transactionId, room.id, operation));
        return;
      }
      final eventId = await operation;
      if (eventId == null && _connectionStatus != ConnectionStatus.online) {
        _offlineSendRooms[transactionId] = room.id;
        _notifyBackendListeners();
      }
    } catch (exception) {
      _error = _friendlyError(exception);
      _notifyBackendListeners();
      rethrow;
    }
  }

  Future<void> _completeOfflineSend(
    String transactionId,
    String roomId,
    Future<String?> operation,
  ) async {
    if (_offlineSendRooms[transactionId] != roomId) return;
    try {
      final eventId = await operation;
      if (eventId != null) _offlineSendRooms.remove(transactionId);
    } catch (exception) {
      if (_connectionStatus == ConnectionStatus.online) {
        _offlineSendRooms.remove(transactionId);
        _error = _friendlyError(exception);
      }
    } finally {
      _notifyBackendListeners();
    }
  }

  Future<void> _retryOfflineSends() async {
    if (_retryingOfflineSends || _offlineSendRooms.isEmpty) return;
    _retryingOfflineSends = true;
    try {
      for (final entry in Map.of(_offlineSendRooms).entries) {
        if (_connectionStatus != ConnectionStatus.online) break;
        final room = _matrix.getRoomById(entry.value);
        if (room == null) {
          _offlineSendRooms.remove(entry.key);
          continue;
        }
        Event? event;
        try {
          event = await _matrix.database.getEventById(entry.key, room);
        } catch (_) {
          event = null;
        }
        if (event == null || event.status.isSent) {
          _offlineSendRooms.remove(entry.key);
          continue;
        }
        if (!event.status.isError) continue;
        try {
          final eventId = await event.sendAgain(txid: entry.key);
          if (eventId != null) _offlineSendRooms.remove(entry.key);
        } catch (_) {
          if (_connectionStatus == ConnectionStatus.online) {
            // A connected failure is authoritative (for example forbidden).
            _offlineSendRooms.remove(entry.key);
          }
        }
      }
    } finally {
      _retryingOfflineSends = false;
      _notifyBackendListeners();
    }
  }

  Map<String, Object> _mentionsFor(String text, Event? replyEvent) {
    final userIds = RegExp(r'@[A-Za-z0-9._=\-/]+:[^\s<>()]+')
        .allMatches(text)
        .map((match) => match.group(0)!)
        .where((userId) => userId != _matrix.userID)
        .toSet();
    if (replyEvent != null && replyEvent.senderId != _matrix.userID) {
      userIds.add(replyEvent.senderId);
    }
    final room = RegExp(r'(^|\s)@room(?=\s|$)').hasMatch(text);
    if (userIds.isEmpty && !room) return const {};
    return {
      'm.mentions': {
        if (userIds.isNotEmpty) 'user_ids': userIds.toList(growable: false),
        if (room) 'room': true,
      },
    };
  }

  Event? _eventById(String eventId) {
    final timeline = _timeline;
    if (timeline == null) return null;
    for (final event in timeline.events) {
      if (event.eventId == eventId) return event;
    }
    return null;
  }

  Future<void> _redactMessage(String messageId) async {
    final event = _eventById(messageId);
    if (event == null) throw StateError('That message is no longer available.');
    if (!event.canRedact) throw StateError('You cannot delete that message.');
    try {
      await event.redactEvent(redactAllEdits: true);
    } catch (exception) {
      _error = _friendlyError(exception);
      _notifyBackendListeners();
      rethrow;
    }
  }

  Future<void> _retryMessage(String messageId) async {
    final event = _eventById(messageId);
    if (event == null || !event.status.isError) {
      throw StateError('That failed message is no longer available.');
    }
    try {
      await _prepareEncryptedSend(event.room);
      await event.sendAgain();
    } catch (exception) {
      _error = _friendlyError(exception);
      _notifyBackendListeners();
      rethrow;
    }
  }

  Future<void> _cancelPendingMessage(String messageId) async {
    final event = _eventById(messageId);
    if (event == null || event.status.isSent) return;
    await event.cancelSend();
    _notifyBackendListeners();
  }

  Future<void> _toggleReaction(String messageId, String key) async {
    final value = key.trim();
    if (value.isEmpty) return;
    final timeline = _timeline;
    final event = _eventById(messageId);
    if (timeline == null || event == null) {
      throw StateError('That message is no longer available.');
    }
    try {
      final ownReaction = event
          .aggregatedEvents(timeline, RelationshipTypes.reaction)
          .where(
            (reaction) =>
                reaction.senderId == _matrix.userID &&
                !reaction.redacted &&
                reaction.content
                        .tryGetMap<String, Object?>('m.relates_to')
                        ?.tryGet<String>('key') ==
                    value,
          )
          .firstOrNull;
      if (ownReaction != null) {
        await ownReaction.redactEvent();
      } else {
        await _prepareEncryptedSend(event.room);
        await event.room.sendReaction(event.eventId, value);
      }
    } catch (exception) {
      _error = _friendlyError(exception);
      _notifyBackendListeners();
      rethrow;
    }
  }
}
