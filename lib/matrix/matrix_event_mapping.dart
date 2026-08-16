part of 'matrix_backend.dart';

extension _MatrixEventMapping on MatrixBackend {
  List<Room> _roomsForSpace(String spaceId) {
    final space = _client?.getRoomById(spaceId);
    if (space == null || !space.isSpace) return const [];
    final children = space.spaceChildren
        .map((child) => _client?.getRoomById(child.roomId ?? ''))
        .whereType<Room>()
        .where((room) => room.membership == Membership.join && !room.isSpace);
    return children.toList(growable: false);
  }

  RoomSummary? get _selectedRoomSummary {
    final room = _client?.getRoomById(_selectedRoomId ?? '');
    return room == null ? null : _roomSummary(room);
  }

  bool get _selectedRoomIsMuted =>
      _client?.getRoomById(_selectedRoomId ?? '')?.pushRuleState ==
      PushRuleState.dontNotify;

  List<ChatMessage> get _mappedMessages {
    final timeline = _timeline;
    if (timeline == null) return const [];
    return timeline.events
        .where((event) => _isVisibleTimelineEvent(event))
        .where((event) => event.relationshipType != RelationshipTypes.edit)
        .map((event) {
          final displayEvent = event.type == EventTypes.Message
              ? event.getDisplayEvent(timeline)
              : event;
          final isMessage =
              displayEvent.type == EventTypes.Message ||
              displayEvent.type == EventTypes.Encrypted;
          final attachment = _attachmentFor(displayEvent);
          final blocked = _matrix.ignoredUsers.contains(event.senderId);
          final body = blocked
              ? 'Message from blocked user'
              : event.redacted
              ? 'Message deleted'
              : displayEvent.type == EventTypes.Encrypted
              ? 'Unable to decrypt this message'
              : !isMessage
              ? _systemEventBody(displayEvent)
              : attachment?.caption ??
                    (attachment == null
                        ? displayEvent.calcUnlocalizedBody(
                            hideReply: true,
                            hideEdit: true,
                            plaintextBody: true,
                          )
                        : '');
          return ChatMessage(
            id: event.eventId,
            sender: event.senderFromMemoryOrFallback.calcDisplayname(),
            body: body,
            timestamp: event.originServerTs,
            pending: event.status.isSending,
            failed: event.status.isError,
            transferStatus: switch (event.fileSendingStatus) {
              FileSendingStatus.generatingThumbnail => 'Preparing preview…',
              FileSendingStatus.encrypting => 'Encrypting…',
              FileSendingStatus.uploading => 'Uploading…',
              null => null,
            },
            system: !isMessage,
            own: event.senderId == _matrix.userID,
            canRedact: event.canRedact && !event.redacted,
            edited: displayEvent.eventId != event.eventId,
            redacted: event.redacted,
            reactions: _reactionSummaries(event, timeline),
            attachment: blocked ? null : attachment,
            formattedBody:
                !blocked &&
                    displayEvent.isRichMessage &&
                    (attachment == null || attachment.caption != null)
                ? displayEvent.formattedText
                : null,
            reply: _replyPreviews[event.eventId],
            avatarBytes: _senderAvatarBytes[event.senderId],
            linkPreview: blocked ? null : _linkPreviews[event.eventId],
            senderId: event.senderId,
            readBy: _readersFor(event, timeline),
            blocked: blocked,
            queued: _offlineSendRooms.containsKey(event.eventId),
          );
        })
        .toList(growable: false);
  }

  List<ReceiptReaderSummary> _readersFor(Event event, Timeline timeline) {
    if (event.senderId != _matrix.userID || event.status.isSending) {
      return const [];
    }
    final room = event.room;
    if (room.getParticipants().length >
        _preferences.readReceiptMemberThreshold) {
      return const [];
    }
    final eventIndex = timeline.events.indexOf(event);
    if (eventIndex < 0) return const [];
    final readers = <ReceiptReaderSummary>[];
    for (final entry in room.receiptState.global.otherUsers.entries) {
      if (entry.key == _matrix.userID) continue;
      final receiptIndex = timeline.events.indexWhere(
        (candidate) => candidate.eventId == entry.value.eventId,
      );
      if (receiptIndex >= 0 && receiptIndex <= eventIndex) {
        final user = room.unsafeGetUserFromMemoryOrFallback(entry.key);
        readers.add(
          ReceiptReaderSummary(
            userId: entry.key,
            displayName: user.calcDisplayname(),
          ),
        );
      }
    }
    return readers;
  }

  bool _isVisibleTimelineEvent(Event event) =>
      event.type == EventTypes.Message ||
      event.type == EventTypes.Encrypted ||
      event.type == EventTypes.RoomMember ||
      event.type == EventTypes.RoomName ||
      event.type == EventTypes.RoomTopic ||
      event.type == EventTypes.RoomAvatar ||
      event.type == EventTypes.Encryption;

  String _systemEventBody(Event event) {
    final actor = event.senderFromMemoryOrFallback.calcDisplayname();
    if (event.type == EventTypes.RoomMember) {
      final user =
          event.stateKeyUser?.calcDisplayname() ?? event.stateKey ?? actor;
      return switch (event.roomMemberChangeType) {
        RoomMemberChangeType.join => '$user joined the room',
        RoomMemberChangeType.acceptInvite => '$user accepted the invitation',
        RoomMemberChangeType.rejectInvite => '$user rejected the invitation',
        RoomMemberChangeType.withdrawInvitation =>
          '$actor withdrew the invitation for $user',
        RoomMemberChangeType.leave => '$user left the room',
        RoomMemberChangeType.kick => '$actor removed $user from the room',
        RoomMemberChangeType.invite => '$actor invited $user',
        RoomMemberChangeType.ban => '$actor banned $user',
        RoomMemberChangeType.unban => '$actor unbanned $user',
        RoomMemberChangeType.knock => '$user requested to join',
        RoomMemberChangeType.avatar => '$user changed their profile picture',
        RoomMemberChangeType.displayname => _displayNameChange(event, user),
        RoomMemberChangeType.other => '$user updated their room profile',
      };
    }
    return switch (event.type) {
      EventTypes.RoomName =>
        '$actor changed the room name to ${event.content.tryGet<String>('name') ?? 'an unnamed room'}',
      EventTypes.RoomTopic =>
        '$actor changed the topic to ${event.content.tryGet<String>('topic') ?? ''}',
      EventTypes.RoomAvatar => '$actor changed the room picture',
      EventTypes.Encryption => '$actor enabled end-to-end encryption',
      _ => '$actor updated the room',
    };
  }

  String _displayNameChange(Event event, String currentName) {
    final previousName = event.prevContent?.tryGet<String>('displayname');
    if (previousName == null || previousName.isEmpty) {
      return '${event.stateKey ?? currentName} is now known as $currentName';
    }
    return '$previousName changed their name to $currentName';
  }

  ChatAttachment? _attachmentFor(Event event) {
    if (!event.hasAttachment) return null;
    final kind = switch (event.messageType) {
      MessageTypes.Image => AttachmentKind.image,
      MessageTypes.Video => AttachmentKind.video,
      MessageTypes.Audio => AttachmentKind.audio,
      _ => AttachmentKind.file,
    };
    final name = event.content.tryGet<String>('filename') ?? event.body;
    final caption =
        event.body.trim().isNotEmpty && event.body.trim() != name.trim()
        ? event.body.trim()
        : null;
    return ChatAttachment(
      kind: kind,
      name: name,
      mimeType: event.attachmentMimetype,
      size: event.infoMap.tryGet<int>('size'),
      encrypted: event.isAttachmentEncrypted,
      spoiler:
          event.content.tryGet<bool>(
                'page.codeberg.everypizza.msc4193.spoiler',
              ) ==
              true ||
          event.content.tryGet<bool>('m.spoiler') == true,
      caption: caption,
      hasThumbnail: event.hasThumbnail,
      animated: event.attachmentMimetype == 'image/gif',
      width: event.infoMap.tryGet<int>('w'),
      height: event.infoMap.tryGet<int>('h'),
    );
  }

  List<ReactionSummary> _reactionSummaries(Event event, Timeline timeline) {
    final reactions = event.aggregatedEvents(
      timeline,
      RelationshipTypes.reaction,
    );
    final counts = <String, int>{};
    final mine = <String>{};
    for (final reaction in reactions.where((reaction) => !reaction.redacted)) {
      final key = reaction.content
          .tryGetMap<String, Object?>('m.relates_to')
          ?.tryGet<String>('key');
      if (key == null || key.isEmpty) continue;
      counts.update(key, (count) => count + 1, ifAbsent: () => 1);
      if (reaction.senderId == _matrix.userID) mine.add(key);
    }
    final summaries = counts.entries
        .map(
          (entry) => ReactionSummary(
            key: entry.key,
            count: entry.value,
            reactedByMe: mine.contains(entry.key),
          ),
        )
        .toList(growable: false);
    summaries.sort((a, b) => a.key.compareTo(b.key));
    return summaries;
  }
}
