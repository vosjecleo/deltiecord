import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../models/chat_models.dart';
import '../version.dart';
import 'bounded_http.dart';

const int maximumStickerPackItems = StickerPackDraft.maximumItems;
const int maximumStickerPackBytes = StickerPackDraft.maximumBytes;

String? telegramStickerSetName(String input) {
  final value = input.trim();
  if (RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,63}$').hasMatch(value)) {
    return value;
  }
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      !const {'t.me', 'telegram.me'}.contains(uri.host.toLowerCase()) ||
      uri.pathSegments.length != 2 ||
      uri.pathSegments.first.toLowerCase() != 'addstickers') {
    return null;
  }
  final name = uri.pathSegments[1];
  return RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,63}$').hasMatch(name) ? name : null;
}

final class TelegramStickerReference {
  const TelegramStickerReference({
    required this.index,
    required this.name,
    required this.mimeType,
    required this.width,
    required this.height,
    required this.size,
  });

  final int index;
  final String name;
  final String mimeType;
  final int width;
  final int height;
  final int size;
}

final class TelegramStickerPack {
  const TelegramStickerPack({
    required this.setName,
    required this.title,
    required this.stickers,
    required this.unsupportedCount,
  });

  final String setName;
  final String title;
  final List<TelegramStickerReference> stickers;
  final int unsupportedCount;
}

/// Imports public Telegram sticker sets through Deltiecord's bounded proxy.
///
/// Telegram's Bot API requires a secret bot token. Keeping that token on the
/// proxy avoids embedding a reusable credential in every distributed client.
final class TelegramStickerService {
  TelegramStickerService({Uri? proxyUri})
    : _proxyUri = proxyUri ?? Uri.parse(_defaultProxyUrl);

  static const _defaultProxyUrl = String.fromEnvironment(
    'TELEGRAM_STICKER_PROXY_URL',
    defaultValue: 'https://deltie.net/api/servers/telegram/stickers',
  );
  static const _metadataLimit = 256 * 1024;
  static const _stickerLimit = 1024 * 1024;
  static const _timeout = Duration(seconds: 12);

  final Uri _proxyUri;
  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..idleTimeout = const Duration(seconds: 12)
    ..userAgent = 'Deltiecord/$deltiecordVersion';
  final Map<String, Future<Uint8List>> _downloads = {};

  Future<TelegramStickerPack> inspect(String input) async {
    final setName = telegramStickerSetName(input);
    if (setName == null) {
      throw const FormatException(
        'Enter a Telegram sticker link or its public pack name.',
      );
    }
    _requireSecureProxy();
    final uri = _proxyUri.replace(queryParameters: {'set': setName});
    final response = await _get(uri, accept: 'application/json');
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException(
        response.statusCode == HttpStatus.serviceUnavailable
            ? 'Telegram sticker importing is temporarily unavailable.'
            : 'Telegram pack lookup returned ${response.statusCode}.',
      );
    }
    if (!hasContentType(response, const ['application/json'])) {
      await response.drain<void>();
      throw const HttpException('Telegram pack lookup returned invalid data.');
    }
    final decoded = jsonDecode(
      utf8.decode(
        await readBoundedResponse(
          response,
          maximumBytes: _metadataLimit,
          inactivityTimeout: _timeout,
        ),
      ),
    );
    if (decoded is! Map) {
      throw const FormatException('Telegram pack metadata is malformed.');
    }
    final rawStickers = decoded['stickers'];
    if (rawStickers is! List || rawStickers.length > maximumStickerPackItems) {
      throw const FormatException('Telegram pack has an invalid item count.');
    }
    var declaredBytes = 0;
    final stickers = <TelegramStickerReference>[];
    for (final raw in rawStickers) {
      if (raw is! Map) continue;
      final index = raw['index'];
      final width = raw['width'];
      final height = raw['height'];
      final size = raw['size'];
      final mimeType = raw['mime_type'];
      if (index is! int ||
          width is! int ||
          height is! int ||
          size is! int ||
          mimeType is! String ||
          index < 0 ||
          width <= 0 ||
          height <= 0 ||
          width > 512 ||
          height > 512 ||
          size <= 0 ||
          size > _stickerLimit ||
          !const {'image/png', 'image/webp'}.contains(mimeType)) {
        throw const FormatException('Telegram pack contains invalid media.');
      }
      declaredBytes += size;
      if (declaredBytes > maximumStickerPackBytes) {
        throw const FormatException('Telegram pack exceeds 100 MiB.');
      }
      final emoji = '${raw['emoji'] ?? ''}'.trim();
      stickers.add(
        TelegramStickerReference(
          index: index,
          name: emoji.isEmpty ? 'sticker_${index + 1}' : emoji,
          mimeType: mimeType,
          width: width,
          height: height,
          size: size,
        ),
      );
    }
    return TelegramStickerPack(
      setName: setName,
      title: '${decoded['title'] ?? setName}'.trim(),
      stickers: List.unmodifiable(stickers),
      unsupportedCount: max(0, (decoded['unsupported_count'] as int?) ?? 0),
    );
  }

  Future<Uint8List> preview(
    TelegramStickerPack pack,
    TelegramStickerReference sticker,
  ) => _download(pack, sticker);

  Future<List<StickerDraftItem>> downloadSelected(
    TelegramStickerPack pack,
    Set<int> selected, {
    void Function(int complete, int total)? onProgress,
  }) async {
    final references = pack.stickers
        .where((sticker) => selected.contains(sticker.index))
        .toList(growable: false);
    if (references.isEmpty) return const [];
    final output = List<StickerDraftItem?>.filled(references.length, null);
    var cursor = 0;
    var complete = 0;
    var totalBytes = 0;

    Future<void> worker() async {
      while (true) {
        final position = cursor++;
        if (position >= references.length) return;
        final reference = references[position];
        final bytes = await _download(pack, reference);
        totalBytes += bytes.length;
        if (totalBytes > maximumStickerPackBytes) {
          throw const HttpException('Telegram pack exceeds 100 MiB.');
        }
        output[position] = StickerDraftItem(
          shortcode: 'telegram_${reference.index + 1}',
          bytes: bytes,
          mimeType: _stickerMimeType(bytes),
          width: reference.width,
          height: reference.height,
        );
        complete++;
        onProgress?.call(complete, references.length);
      }
    }

    await Future.wait([
      for (var index = 0; index < min(4, references.length); index++) worker(),
    ]);
    return output.whereType<StickerDraftItem>().toList(growable: false);
  }

  Future<Uint8List> _download(
    TelegramStickerPack pack,
    TelegramStickerReference sticker,
  ) {
    final key = '${pack.setName}:${sticker.index}';
    return _downloads.putIfAbsent(key, () async {
      _requireSecureProxy();
      final path = _proxyUri.path.endsWith('/')
          ? '${_proxyUri.path}file'
          : '${_proxyUri.path}/file';
      final uri = _proxyUri.replace(
        path: path,
        queryParameters: {'set': pack.setName, 'index': '${sticker.index}'},
      );
      final response = await _get(uri, accept: sticker.mimeType);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw HttpException(
          'Telegram sticker download returned ${response.statusCode}.',
        );
      }
      if (!hasContentType(response, const ['image/png', 'image/webp']) ||
          response.contentLength > _stickerLimit) {
        await response.drain<void>();
        throw const HttpException('Telegram returned invalid sticker media.');
      }
      return readBoundedResponse(
        response,
        maximumBytes: _stickerLimit,
        inactivityTimeout: _timeout,
      );
    });
  }

  Future<HttpClientResponse> _get(Uri uri, {required String accept}) async {
    final request = await _http.getUrl(uri).timeout(_timeout);
    request
      ..followRedirects = false
      ..headers.set(HttpHeaders.acceptHeader, accept);
    return request.close().timeout(_timeout);
  }

  void _requireSecureProxy() {
    if (_proxyUri.scheme != 'https' || _proxyUri.host.isEmpty) {
      throw StateError('The Telegram sticker proxy must use HTTPS.');
    }
  }
}

String _stickerMimeType(Uint8List bytes) {
  if (bytes.length >= 12 &&
      ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
      ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP') {
    return 'image/webp';
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0d &&
      bytes[5] == 0x0a &&
      bytes[6] == 0x1a &&
      bytes[7] == 0x0a) {
    return 'image/png';
  }
  throw const FormatException('Telegram returned invalid sticker media.');
}
