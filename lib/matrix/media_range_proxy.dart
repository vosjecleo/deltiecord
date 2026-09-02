import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:vodozemac/vodozemac.dart';

typedef RangeDecryptor =
    Uint8List Function(
      Uint8List input,
      Uint8List key,
      Uint8List iv,
      int blockOffset,
    );

typedef MediaProxyClock = DateTime Function();

/// Serves encrypted Matrix media to a local player using bounded HTTP ranges.
///
/// Matrix attachments use AES-CTR, so an aligned ciphertext range can be
/// decrypted independently by advancing the counter by its block offset. This
/// keeps seeking and playback streaming without exposing credentials or keys
/// in a URL visible outside the loopback interface.
class MediaRangeProxy {
  MediaRangeProxy({
    RangeDecryptor? decryptor,
    MediaProxyClock? clock,
    this.entryTtl = const Duration(minutes: 30),
    this.maximumEntries = 32,
  }) : assert(maximumEntries > 0),
       _decryptor = decryptor ?? _decryptAesCtrRange,
       _clock = clock ?? DateTime.now {
    _upstream
      ..connectionTimeout = const Duration(seconds: 10)
      ..idleTimeout = const Duration(seconds: 15);
  }

  final RangeDecryptor _decryptor;
  final MediaProxyClock _clock;
  final Duration entryTtl;
  final int maximumEntries;
  HttpServer? _server;
  final HttpClient _upstream = HttpClient();
  final Map<String, _EncryptedMedia> _entries = {};
  final Random _random = Random.secure();
  Timer? _cleanupTimer;
  Directory? _cacheDirectory;
  var _accessSequence = 0;

  Future<Uri> register({
    required Uri upstream,
    required String accessToken,
    required Uint8List key,
    required Uint8List iv,
    required int size,
    required String mimeType,
  }) async {
    final server = await _ensureServer();
    _removeExpired();
    while (_entries.length >= maximumEntries) {
      final oldest = _entries.entries.reduce(
        (a, b) => a.value.accessSequence < b.value.accessSequence ? a : b,
      );
      _removeEntry(oldest.key);
    }
    final token = List.generate(24, (_) => _random.nextInt(256));
    final id = base64UrlEncode(token).replaceAll('=', '');
    _entries[id] = _EncryptedMedia(
      upstream: upstream,
      accessToken: accessToken,
      key: key,
      iv: iv,
      size: size,
      mimeType: mimeType,
      lastAccess: _clock(),
      accessSequence: ++_accessSequence,
    );
    return Uri.parse('http://127.0.0.1:${server.port}/media/$id');
  }

  Future<HttpServer> _ensureServer() async {
    final existing = _server;
    if (existing != null) return existing;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    final cleanupEvery = Duration(
      microseconds: max(
        const Duration(seconds: 1).inMicroseconds,
        min(
          const Duration(minutes: 1).inMicroseconds,
          entryTtl.inMicroseconds ~/ 2,
        ),
      ),
    );
    _cleanupTimer = Timer.periodic(cleanupEvery, (_) => _removeExpired());
    unawaited(server.forEach(_handle));
    return server;
  }

  Future<void> _handle(HttpRequest request) async {
    final id =
        request.uri.pathSegments.length == 2 &&
            request.uri.pathSegments.first == 'media'
        ? request.uri.pathSegments.last
        : null;
    _removeExpired();
    final media = id == null ? null : _entries[id];
    if (media == null ||
        (request.method != 'GET' && request.method != 'HEAD')) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    media.lastAccess = _clock();
    media.accessSequence = ++_accessSequence;

    try {
      final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
      if (request.method == 'HEAD' && rangeHeader == null) {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
          ..headers.set(HttpHeaders.contentTypeHeader, media.mimeType)
          ..headers.set(HttpHeaders.contentLengthHeader, media.size);
        await request.response.close();
        return;
      }
      final requested = _parseRange(rangeHeader, media.size);
      final start = requested.$1;
      final end = requested.$2;
      final partial = requested.$3;
      final length = end - start + 1;
      final alignedStart = start - (start % 16);
      final cipherSource = request.method == 'HEAD'
          ? null
          : await _openEncryptedRange(
              media,
              fetchStart: alignedStart,
              requestedEnd: end,
            );
      final response = request.response
        ..bufferOutput = false
        ..statusCode = partial ? HttpStatus.partialContent : HttpStatus.ok
        ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..headers.set(HttpHeaders.contentTypeHeader, media.mimeType)
        ..headers.set(HttpHeaders.contentLengthHeader, length);
      if (partial) {
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/${media.size}',
        );
      }
      if (request.method == 'HEAD') {
        await response.close();
        return;
      }

      await _streamDecryptedRange(
        media,
        cipherSource: cipherSource!,
        fetchStart: alignedStart,
        requestedStart: start,
        requestedEnd: end,
        downstream: response,
      );
      await response.close();
    } on FormatException {
      try {
        request.response
          ..statusCode = HttpStatus.requestedRangeNotSatisfiable
          ..headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes */${media.size}',
          );
        await request.response.close();
      } catch (_) {}
    } catch (_) {
      // A streaming response may already have sent its headers. In that case
      // changing the status is no longer legal, but closing it still lets the
      // player retry the failed range safely.
      try {
        request.response.statusCode = HttpStatus.badGateway;
      } catch (_) {}
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  (int, int, bool) _parseRange(String? header, int size) {
    if (size <= 0) throw const FormatException('Empty media');
    if (header == null) {
      // A response to a non-range GET must describe and stream the complete
      // representation. Returning a synthetic 206 for only the first chunk
      // made libmpv treat that chunk as EOF on desktop and confused Android's
      // duration/seek probing. The body is streamed, never buffered in full.
      return (0, size - 1, false);
    }
    if (!header.startsWith('bytes=')) {
      throw const FormatException('Invalid media range');
    }
    final parts = header.substring(6).split('-');
    if (parts.length != 2) {
      throw const FormatException('Invalid media range');
    }
    final suffixLength = parts.first.isEmpty ? int.tryParse(parts[1]) : null;
    final int? start = suffixLength == null
        ? int.tryParse(parts.first)
        : max(0, size - min(size, suffixLength));
    if (start == null || suffixLength == 0) {
      throw const FormatException('Invalid media range');
    }
    final requestedEnd = suffixLength == null ? int.tryParse(parts[1]) : null;
    final end = min(size - 1, requestedEnd ?? size - 1);
    if (start < 0 || start >= size || end < start) {
      throw const FormatException('Invalid media range');
    }
    return (start, end, true);
  }

  /// Streams an independently decryptable AES-CTR range to the player.
  ///
  /// Only an incomplete cipher block is buffered between upstream chunks.
  /// Previously the full (up to 16 MiB) range was downloaded and decrypted
  /// before playback received any data, producing long startup stalls.
  Future<void> _streamDecryptedRange(
    _EncryptedMedia media, {
    required _CipherSource cipherSource,
    required int fetchStart,
    required int requestedStart,
    required int requestedEnd,
    required HttpResponse downstream,
  }) async {
    final cipherLength = requestedEnd - fetchStart + 1;
    final requestedLength = requestedEnd - requestedStart + 1;
    var upstreamSkip = cipherSource.skip;
    var cipherRemaining = cipherLength;
    var cipherOffset = fetchStart;
    var emitted = 0;
    var pending = Uint8List(0);

    await for (final rawChunk in cipherSource.stream.timeout(
      const Duration(seconds: 15),
    )) {
      var rawOffset = 0;
      if (upstreamSkip > 0) {
        final skipped = min(upstreamSkip, rawChunk.length);
        upstreamSkip -= skipped;
        rawOffset += skipped;
      }
      if (rawOffset >= rawChunk.length || cipherRemaining == 0) continue;

      final take = min(cipherRemaining, rawChunk.length - rawOffset);
      final combined = Uint8List(pending.length + take)
        ..setRange(0, pending.length, pending)
        ..setRange(pending.length, pending.length + take, rawChunk, rawOffset);
      cipherRemaining -= take;

      final processLength = cipherRemaining == 0
          ? combined.length
          : combined.length - (combined.length % 16);
      if (processLength == 0) {
        pending = combined;
        continue;
      }

      final encrypted = Uint8List.sublistView(combined, 0, processLength);
      final decrypted = _decryptor(
        encrypted,
        media.key,
        media.iv,
        cipherOffset ~/ 16,
      );
      final segmentStart = cipherOffset;
      final segmentEnd = cipherOffset + processLength;
      final outputStart = max(requestedStart, segmentStart) - segmentStart;
      final outputEnd = min(requestedEnd + 1, segmentEnd) - segmentStart;
      if (outputEnd > outputStart) {
        downstream.add(
          Uint8List.sublistView(decrypted, outputStart, outputEnd),
        );
        emitted += outputEnd - outputStart;
      }
      cipherOffset += processLength;
      pending = processLength == combined.length
          ? Uint8List(0)
          : Uint8List.sublistView(combined, processLength);
      if (cipherRemaining == 0) break;
    }

    if (cipherRemaining != 0 ||
        pending.isNotEmpty ||
        emitted != requestedLength) {
      throw const HttpException('Incomplete encrypted media range');
    }
  }

  Future<_CipherSource> _openEncryptedRange(
    _EncryptedMedia media, {
    required int fetchStart,
    required int requestedEnd,
  }) async {
    final cached = media.cachedCiphertext;
    if (cached != null) {
      return _CipherSource(
        cached.openRead(fetchStart, requestedEnd + 1),
        skip: 0,
      );
    }
    final cacheInProgress = media.cacheFuture;
    if (cacheInProgress != null) {
      final file = await cacheInProgress;
      return _CipherSource(
        file.openRead(fetchStart, requestedEnd + 1),
        skip: 0,
      );
    }
    final request = await _upstream
        .getUrl(media.upstream)
        .timeout(const Duration(seconds: 10));
    request.followRedirects = false;
    request.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer ${media.accessToken}')
      ..set(HttpHeaders.rangeHeader, 'bytes=$fetchStart-$requestedEnd');
    final response = await request.close().timeout(const Duration(seconds: 10));
    if (response.statusCode != HttpStatus.ok &&
        response.statusCode != HttpStatus.partialContent) {
      throw HttpException('Media server returned ${response.statusCode}');
    }
    if (response.statusCode == HttpStatus.ok && fetchStart != 0) {
      // Some Matrix media endpoints ignore Range. Never discard bytes until a
      // seek offset: that turns a small seek into an unbounded network read.
      // Instead cache exactly one size-validated ciphertext copy in a private
      // process-owned directory, then serve all seeks from that file.
      final file = await _cacheCompleteCiphertext(media, response);
      return _CipherSource(
        file.openRead(fetchStart, requestedEnd + 1),
        skip: 0,
      );
    }
    if (response.statusCode == HttpStatus.partialContent) {
      _validateContentRange(
        response.headers.value(HttpHeaders.contentRangeHeader),
        expectedStart: fetchStart,
        maximumEnd: requestedEnd,
        expectedSize: media.size,
      );
    }

    return _CipherSource(
      response,
      skip: response.statusCode == HttpStatus.ok ? fetchStart : 0,
    );
  }

  Future<File> _cacheCompleteCiphertext(
    _EncryptedMedia media,
    HttpClientResponse ignoredRangeResponse,
  ) async {
    final cached = media.cachedCiphertext;
    if (cached != null) {
      await ignoredRangeResponse.listen((_) {}).cancel();
      return cached;
    }
    final inProgress = media.cacheFuture;
    if (inProgress != null) {
      await ignoredRangeResponse.listen((_) {}).cancel();
      return inProgress;
    }

    final future = _writeCiphertextCache(media, ignoredRangeResponse);
    media.cacheFuture = future;
    try {
      final file = await future;
      if (media.removed) {
        await _deleteFile(file);
        throw const HttpException('Encrypted media entry expired');
      }
      media.cachedCiphertext = file;
      return file;
    } finally {
      media.cacheFuture = null;
    }
  }

  Future<File> _writeCiphertextCache(
    _EncryptedMedia media,
    HttpClientResponse response,
  ) async {
    final advertisedLength = response.contentLength;
    if (advertisedLength > media.size) {
      await response.listen((_) {}).cancel();
      throw const HttpException('Encrypted media exceeds declared size');
    }
    final directory = await _ensureCacheDirectory();
    final randomName = base64UrlEncode(
      List.generate(24, (_) => _random.nextInt(256)),
    ).replaceAll('=', '');
    final file = File('${directory.path}/$randomName.cipher');
    final sink = file.openWrite(mode: FileMode.writeOnly);
    var received = 0;
    try {
      await for (final chunk in response.timeout(const Duration(seconds: 15))) {
        received += chunk.length;
        if (received > media.size) {
          throw const HttpException('Encrypted media exceeds declared size');
        }
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
      if (received != media.size) {
        throw const HttpException('Incomplete encrypted media download');
      }
      await _restrictPermissions(file.path, directory: false);
      return file;
    } catch (_) {
      await sink.close().catchError((_) {});
      await _deleteFile(file);
      rethrow;
    }
  }

  Future<Directory> _ensureCacheDirectory() async {
    final existing = _cacheDirectory;
    if (existing != null) return existing;
    final directory = await Directory.systemTemp.createTemp(
      'deltiecord-encrypted-media-',
    );
    await _restrictPermissions(directory.path, directory: true);
    _cacheDirectory = directory;
    return directory;
  }

  Future<void> _restrictPermissions(
    String path, {
    required bool directory,
  }) async {
    if (!Platform.isLinux && !Platform.isMacOS) return;
    final result = await Process.run('chmod', [
      directory ? '700' : '600',
      path,
    ]);
    if (result.exitCode != 0) {
      throw const FileSystemException('Could not restrict media cache');
    }
  }

  Future<void> _deleteFile(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  void _validateContentRange(
    String? value, {
    required int expectedStart,
    required int maximumEnd,
    required int expectedSize,
  }) {
    final match = value == null
        ? null
        : RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(value.trim());
    final start = int.tryParse(match?.group(1) ?? '');
    final end = int.tryParse(match?.group(2) ?? '');
    final size = int.tryParse(match?.group(3) ?? '');
    if (start != expectedStart ||
        end == null ||
        end < expectedStart ||
        end > maximumEnd ||
        size != expectedSize) {
      throw const HttpException(
        'Media server returned malformed range metadata',
      );
    }
  }

  void unregister(Uri localUri) {
    if (localUri.host != InternetAddress.loopbackIPv4.address ||
        localUri.pathSegments.length != 2 ||
        localUri.pathSegments.first != 'media') {
      return;
    }
    _removeEntry(localUri.pathSegments.last);
  }

  void _removeExpired() {
    final cutoff = _clock().subtract(entryTtl);
    for (final id
        in _entries.entries
            .where((entry) => entry.value.lastAccess.isBefore(cutoff))
            .map((entry) => entry.key)
            .toList(growable: false)) {
      _removeEntry(id);
    }
  }

  void _removeEntry(String id) {
    final media = _entries.remove(id);
    if (media == null) return;
    media.removed = true;
    final cached = media.cachedCiphertext;
    if (cached != null) unawaited(_deleteFile(cached));
    final inProgress = media.cacheFuture;
    if (inProgress != null) {
      unawaited(inProgress.then(_deleteFile, onError: (_) {}));
    }
    media.key.fillRange(0, media.key.length, 0);
    media.iv.fillRange(0, media.iv.length, 0);
  }

  void clear() {
    for (final id in _entries.keys.toList(growable: false)) {
      _removeEntry(id);
    }
  }

  Future<void> close() async {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    clear();
    _upstream.close(force: true);
    await _server?.close(force: true);
    _server = null;
    final directory = _cacheDirectory;
    _cacheDirectory = null;
    if (directory != null) {
      try {
        if (await directory.exists()) await directory.delete(recursive: true);
      } catch (_) {}
    }
  }
}

Uint8List _decryptAesCtrRange(
  Uint8List input,
  Uint8List key,
  Uint8List iv,
  int blockOffset,
) =>
    CryptoUtils.aesCtr(input: input, key: key, iv: _counterAt(iv, blockOffset));

Uint8List _counterAt(Uint8List iv, int blockOffset) {
  final counter = Uint8List.fromList(iv);
  var carry = blockOffset;
  for (var index = counter.length - 1; index >= 8 && carry > 0; index--) {
    final value = counter[index] + (carry & 0xff);
    counter[index] = value & 0xff;
    carry = (carry >> 8) + (value >> 8);
  }
  if (carry != 0) throw StateError('Encrypted media counter overflow');
  return counter;
}

class _EncryptedMedia {
  _EncryptedMedia({
    required this.upstream,
    required this.accessToken,
    required this.key,
    required this.iv,
    required this.size,
    required this.mimeType,
    required this.lastAccess,
    required this.accessSequence,
  });

  final Uri upstream;
  final String accessToken;
  final Uint8List key;
  final Uint8List iv;
  final int size;
  final String mimeType;
  DateTime lastAccess;
  int accessSequence;
  File? cachedCiphertext;
  Future<File>? cacheFuture;
  bool removed = false;
}

class _CipherSource {
  const _CipherSource(this.stream, {required this.skip});

  final Stream<List<int>> stream;
  final int skip;
}
