part of 'matrix_backend.dart';

extension _MatrixMedia on MatrixBackend {
  String? _getAttachmentReference(String messageId) {
    final event = _eventById(messageId);
    if (event == null || !event.hasAttachment) return null;
    final encryptedReference = event.content
        .tryGetMap<String, Object?>('file')
        ?.tryGet<String>('url');
    final reference = encryptedReference ?? event.content.tryGet<String>('url');
    final uri = Uri.tryParse(reference ?? '');
    // Only expose the stable MXC identifier. Download URLs can contain a
    // homeserver access token, and encrypted file metadata contains the key.
    return uri?.isScheme('mxc') == true ? uri.toString() : null;
  }

  Future<void> _refreshStorageUsage() async {
    _storageLoading = true;
    _notifyBackendListeners();
    try {
      final directory = await getDeltiecordDataDirectory();
      var total = 0;
      if (await directory.exists()) {
        await for (final entity in directory.list(recursive: true)) {
          if (entity is File) total += await entity.length();
        }
      }
      _storageUsageBytes = total;
    } finally {
      _storageLoading = false;
      _notifyBackendListeners();
    }
  }

  Future<void> _clearMediaCache() async {
    _mediaPlaybackSources.clear();
    _mediaPlaybackReferences.clear();
    _mediaRangeProxy.clear();
    _attachmentBytesCache.clear();
    _attachmentDownloads.clear();
    _attachmentBytesCacheSize = 0;
    _attachmentCacheGeneration++;
    _linkPreviews.clear();
    _linkPreviewRetryAfter.clear();
    _linkPreviewAttempts.clear();
    _linkPreviewRetryTimer?.cancel();
    _linkPreviewRetryTimer = null;
    _notifyBackendListeners();
    await _refreshStorageUsage();
  }

  Future<void> _sendAttachment(
    AttachmentDraft attachment, {
    String? roomId,
    String? replyToMessageId,
  }) async {
    final room = _matrix.getRoomById(roomId ?? _selectedRoomId ?? '');
    if (room == null) throw StateError('The selected room is unavailable.');
    try {
      await _validateUploadSize(attachment.bytes.length);
      await _prepareEncryptedSend(room);
      final replyEvent = replyToMessageId == null
          ? null
          : _eventById(replyToMessageId);
      // MatrixFile still derives m.image from the GIF MIME type, while
      // deliberately avoiding MatrixImageFile's synchronous GIF decode and
      // thumbnail generation on Flutter's UI isolate.
      final file = attachment.mimeType == 'image/gif'
          ? MatrixFile(
              bytes: attachment.bytes,
              name: attachment.name,
              mimeType: attachment.mimeType,
            )
          : MatrixFile.fromMimeType(
              bytes: attachment.bytes,
              name: attachment.name,
              mimeType: attachment.mimeType,
            );
      final transactionId = _matrix.generateUniqueTransactionId();
      final operation = room.sendFileEvent(
        file,
        txid: transactionId,
        inReplyTo: replyEvent,
        // Re-encoding large images here is CPU-heavy and stalls Flutter's UI
        // isolate. The SDK still generates a thumbnail, but uploads the
        // original image without a redundant full-resolution shrink pass.
        shrinkImageMaxDimension: null,
        extraContent:
            attachment.spoiler || attachment.caption?.trim().isNotEmpty == true
            ? {
                if (attachment.caption?.trim().isNotEmpty == true) ...{
                  'body': attachment.caption!.trim(),
                  'filename': attachment.name,
                },
                // MSC4193's unstable key is used by existing clients. Keep the
                // stable-looking key too so migration does not require a resend.
                if (attachment.spoiler) ...{
                  'page.codeberg.everypizza.msc4193.spoiler': true,
                  'm.spoiler': true,
                },
              }
            : null,
      );
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

  Future<void> _refreshMediaConfig() async {
    try {
      _maximumUploadBytes = (await _matrix.getConfig()).mUploadSize;
    } catch (_) {
      // The endpoint is advisory and not exposed by every homeserver. The
      // upload request itself remains the authoritative fallback.
    }
  }

  Future<void> _validateUploadSize(int byteLength) async {
    if (_maximumUploadBytes == null) await _refreshMediaConfig();
    final limit = _maximumUploadBytes;
    if (limit == null || byteLength <= limit) return;
    throw StateError(
      'This file is ${_formatByteSize(byteLength)}, but the homeserver allows '
      'uploads up to ${_formatByteSize(limit)}.',
    );
  }

  String _formatByteSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kib = bytes / 1024;
    if (kib < 1024) return '${kib.toStringAsFixed(1)} KiB';
    final mib = kib / 1024;
    if (mib < 1024) return '${mib.toStringAsFixed(1)} MiB';
    return '${(mib / 1024).toStringAsFixed(1)} GiB';
  }

  Future<Uint8List> _downloadAttachment(
    String messageId, {
    bool thumbnail = false,
  }) async {
    final cacheKey = '$messageId:${thumbnail ? 'thumbnail' : 'original'}';
    final cached = _attachmentBytesCache.remove(cacheKey);
    if (cached != null) {
      _attachmentBytesCache[cacheKey] = cached;
      return cached;
    }
    final pending = _attachmentDownloads[cacheKey];
    if (pending != null) return pending;
    final operation = _downloadAndCacheAttachment(
      cacheKey,
      messageId,
      thumbnail: thumbnail,
      generation: _attachmentCacheGeneration,
    );
    _attachmentDownloads[cacheKey] = operation;
    return operation.whenComplete(() {
      if (identical(_attachmentDownloads[cacheKey], operation)) {
        _attachmentDownloads.remove(cacheKey);
      }
    });
  }

  Future<Uint8List> _downloadAndCacheAttachment(
    String cacheKey,
    String messageId, {
    required bool thumbnail,
    required int generation,
  }) async {
    final event = _eventById(messageId);
    if (event == null || !event.hasAttachment) {
      throw StateError('That attachment is no longer available.');
    }
    final file = await event.downloadAndDecryptAttachment(
      getThumbnail: thumbnail && event.hasThumbnail,
    );
    final bytes = file.bytes;
    // Cache only bounded media. This avoids repeatedly downloading/decrypting
    // GIFs as virtualized rows leave and re-enter the viewport without turning
    // a single huge attachment into permanent process memory.
    if (generation == _attachmentCacheGeneration &&
        bytes.length <= 16 * 1024 * 1024) {
      _attachmentBytesCache[cacheKey] = bytes;
      _attachmentBytesCacheSize += bytes.length;
      while (_attachmentBytesCache.length >
              MatrixBackend._maximumCachedAttachments ||
          _attachmentBytesCacheSize >
              MatrixBackend._maximumCachedAttachmentBytes) {
        final oldestKey = _attachmentBytesCache.keys.first;
        final removed = _attachmentBytesCache.remove(oldestKey);
        _attachmentBytesCacheSize -= removed?.length ?? 0;
      }
    }
    return bytes;
  }

  Future<MediaPlaybackSource?> _getMediaPlaybackSource(String messageId) async {
    final event = _eventById(messageId);
    if (event == null || !event.hasAttachment) {
      return null;
    }
    final cached = _mediaPlaybackSources[messageId];
    if (cached != null) {
      _mediaPlaybackReferences.update(messageId, (value) => value + 1);
      return cached;
    }
    if (event.isAttachmentEncrypted) {
      final file = event.content.tryGetMap<String, Object?>('file');
      final mxc = Uri.tryParse(file?.tryGet<String>('url') ?? '');
      final keyText = file
          ?.tryGetMap<String, Object?>('key')
          ?.tryGet<String>('k');
      final ivText = file?.tryGet<String>('iv');
      final size = event.infoMap.tryGet<int>('size');
      final accessToken = _matrix.accessToken;
      if (mxc == null ||
          !mxc.isScheme('mxc') ||
          keyText == null ||
          ivText == null ||
          size == null ||
          size <= 0 ||
          accessToken == null) {
        return null;
      }
      final upstream = await mxc.getDownloadUri(_matrix, skipScanner: true);
      final localUri = await _mediaRangeProxy.register(
        upstream: upstream,
        accessToken: accessToken,
        key: base64Url.decode(base64.normalize(keyText)),
        iv: base64.decode(base64.normalize(ivText)),
        size: size,
        mimeType: event.attachmentMimetype,
      );
      final source = MediaPlaybackSource(uri: localUri, headers: const {});
      _mediaPlaybackSources[messageId] = source;
      _mediaPlaybackReferences[messageId] = 1;
      return source;
    }
    final uri = await event.getAttachmentUri(skipScanner: false);
    if (uri == null) return null;
    final source = MediaPlaybackSource(
      uri: uri,
      headers: {
        if (_matrix.accessToken case final token?)
          'Authorization': 'Bearer $token',
      },
    );
    _mediaPlaybackSources[messageId] = source;
    _mediaPlaybackReferences[messageId] = 1;
    return source;
  }

  void _releaseMediaPlaybackSource(String messageId) {
    final references = _mediaPlaybackReferences[messageId];
    if (references != null && references > 1) {
      _mediaPlaybackReferences[messageId] = references - 1;
      return;
    }
    _mediaPlaybackReferences.remove(messageId);
    final source = _mediaPlaybackSources.remove(messageId);
    if (source != null) _mediaRangeProxy.unregister(source.uri);
  }
}
