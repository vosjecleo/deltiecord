import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../models/chat_models.dart';
import '../version.dart';
import 'bounded_http.dart';
import 'public_network_address.dart';

const _maximumPreviewDocumentBytes = 1024 * 1024;
const _maximumPreviewImageBytes = 5 * 1024 * 1024;
const _maximumRedirects = 4;
const _requestTimeout = Duration(seconds: 8);

/// Extracts safe HTTP(S) candidates without treating trailing prose as a URL.
List<Uri> extractPreviewUrls(String text) {
  final result = <Uri>[];
  for (final match in RegExp(
    r'''https?://[^\s<>"']+''',
    caseSensitive: false,
  ).allMatches(text)) {
    var candidate = match.group(0)!;
    while (candidate.isNotEmpty &&
        '.,;:!?'.contains(candidate[candidate.length - 1])) {
      candidate = candidate.substring(0, candidate.length - 1);
    }
    for (final pair in const [('(', ')'), ('[', ']'), ('{', '}')]) {
      while (candidate.endsWith(pair.$2) &&
          RegExp(RegExp.escape(pair.$1)).allMatches(candidate).length <
              RegExp(RegExp.escape(pair.$2)).allMatches(candidate).length) {
        candidate = candidate.substring(0, candidate.length - 1);
      }
    }
    final uri = Uri.tryParse(candidate);
    if (uri != null &&
        (uri.isScheme('http') || uri.isScheme('https')) &&
        uri.host.isNotEmpty) {
      result.add(uri);
    }
  }
  return result;
}

/// Normalizes the inconsistent OpenGraph shapes returned by Matrix servers.
///
/// Synapse-compatible servers commonly return numbers as either JSON numbers
/// or strings and may use unprefixed title/description fields. Keeping this
/// parser independent from matrix-dart-sdk makes the compatibility behavior
/// directly regression-testable.
LinkPreview parseHomeserverLinkPreview({
  required Uri url,
  required Map<String, Object?> properties,
  Uint8List? imageBytes,
}) {
  String? stringValue(List<String> keys, {int maximumLength = 4096}) {
    for (final key in keys) {
      final raw = properties[key];
      if (raw is! String) continue;
      final value = raw.trim();
      if (value.isNotEmpty) {
        return value.length <= maximumLength
            ? value
            : value.substring(0, maximumLength);
      }
    }
    return null;
  }

  int? intValue(List<String> keys) {
    for (final key in keys) {
      final raw = properties[key];
      final value = raw is num ? raw.toInt() : int.tryParse('$raw');
      if (value != null && value > 0 && value <= 100000) return value;
    }
    return null;
  }

  return LinkPreview(
    url: url,
    title: stringValue(const ['og:title', 'title'], maximumLength: 512),
    description: stringValue(const ['og:description', 'description']),
    siteName: stringValue(const [
      'og:site_name',
      'site_name',
    ], maximumLength: 128),
    imageBytes: imageBytes,
    // Remote video URLs are deliberately not passed to media_kit. Doing so
    // would bypass the direct-preview opt-in and the validated HTTP client.
    videoUrl: null,
    width: intValue(const ['og:video:width', 'og:image:width']),
    height: intValue(const ['og:video:height', 'og:image:height']),
  );
}

bool hasUsefulPreview(LinkPreview preview) =>
    preview.title != null ||
    preview.description != null ||
    preview.imageBytes != null ||
    preview.videoUrl != null;

/// Small URL-level cache shared by every event linking to the same resource.
class LinkPreviewCache {
  LinkPreviewCache({
    this.maximumEntries = 128,
    this.successLifetime = const Duration(hours: 6),
    this.failureLifetime = const Duration(minutes: 2),
  });

  final int maximumEntries;
  final Duration successLifetime;
  final Duration failureLifetime;
  final LinkedHashMap<String, _CachedPreview> _entries = LinkedHashMap();

  bool contains(Uri url) => getEntry(url).$1;

  LinkPreview? get(Uri url) => getEntry(url).$2;

  (bool, LinkPreview?) getEntry(Uri url) {
    final key = _cacheKey(url);
    final entry = _entries.remove(key);
    if (entry == null) return (false, null);
    if (DateTime.now().isAfter(entry.expiresAt)) return (false, null);
    _entries[key] = entry;
    return (true, entry.preview);
  }

  void put(Uri url, LinkPreview? preview) {
    final key = _cacheKey(url);
    _entries.remove(key);
    _entries[key] = _CachedPreview(
      preview,
      DateTime.now().add(preview == null ? failureLifetime : successLifetime),
    );
    while (_entries.length > maximumEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  void clear() => _entries.clear();

  String _cacheKey(Uri url) => url.replace(fragment: '').toString();
}

class _CachedPreview {
  const _CachedPreview(this.preview, this.expiresAt);
  final LinkPreview? preview;
  final DateTime expiresAt;
}

/// Fetches privacy-sensitive fallback previews with pinned, validated sockets.
///
/// Every redirect is resolved again and every returned address must be public.
/// The actual HTTP connection is pinned to one of those validated addresses,
/// preventing a second DNS lookup from rebinding the hostname to a LAN target.
class DirectLinkPreviewFetcher {
  DirectLinkPreviewFetcher({
    Future<List<InternetAddress>> Function(String host)? resolveHost,
    DirectPreviewTransport? transport,
    this.requestTimeout = _requestTimeout,
    this.maximumDocumentBytes = _maximumPreviewDocumentBytes,
    this.maximumImageBytes = _maximumPreviewImageBytes,
  }) : _resolveHost = resolveHost ?? InternetAddress.lookup,
       _transport = transport ?? const PinnedDirectPreviewTransport();

  final Future<List<InternetAddress>> Function(String host) _resolveHost;
  final DirectPreviewTransport _transport;
  final Duration requestTimeout;
  final int maximumDocumentBytes;
  final int maximumImageBytes;

  Future<LinkPreview?> fetch(Uri initialUrl) async {
    var url = initialUrl;
    for (var redirects = 0; redirects <= _maximumRedirects; redirects++) {
      _validateScheme(url);
      final addresses = await _resolveHost(url.host).timeout(requestTimeout);
      if (addresses.isEmpty ||
          addresses.any((item) => !isPublicInternetAddress(item))) {
        throw const HttpException('Preview host did not resolve publicly.');
      }
      final response = await _transport
          .get(url, addresses.first, accept: 'text/html,application/xhtml+xml')
          .timeout(requestTimeout);
      if (_isRedirect(response.statusCode)) {
        await response.body.drain<void>();
        final location = response.location;
        if (location == null || redirects == _maximumRedirects) {
          throw const HttpException('Invalid or excessive preview redirect.');
        }
        url = url.resolveUri(location);
        continue;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.body.drain<void>();
        throw HttpException(
          'Preview server returned HTTP ${response.statusCode}.',
        );
      }
      if (!_isAllowedDocumentType(response.contentType)) {
        await response.body.drain<void>();
        throw const HttpException('Preview response was not HTML.');
      }
      if (response.contentLength > maximumDocumentBytes) {
        await response.body.drain<void>();
        throw const HttpException(
          'Preview document exceeded its safe size limit.',
        );
      }
      final bytes = await readBoundedResponse(
        response.body,
        maximumBytes: maximumDocumentBytes,
        inactivityTimeout: requestTimeout,
      );
      final document = html_parser.parse(
        utf8.decode(bytes, allowMalformed: true),
      );
      final metadata = _metadataFromDocument(document, url);
      Uint8List? imageBytes;
      final imageUrl = metadata.imageUrl;
      if (imageUrl != null) {
        // Images are an enhancement to the text card. Keep a valid title or
        // description when an origin's image is unavailable or exceeds the
        // bounded media policy.
        try {
          imageBytes = await _fetchImage(imageUrl);
        } on Exception {
          imageBytes = null;
        }
      }
      final preview = LinkPreview(
        url: initialUrl,
        title: metadata.title,
        description: metadata.description,
        siteName: metadata.siteName,
        imageBytes: imageBytes,
        videoUrl: null,
        width: metadata.width,
        height: metadata.height,
      );
      return hasUsefulPreview(preview) ? preview : null;
    }
    return null;
  }

  Future<Uint8List?> _fetchImage(Uri url) async {
    var current = url;
    for (var redirects = 0; redirects <= _maximumRedirects; redirects++) {
      _validateScheme(current);
      final addresses = await _resolveHost(
        current.host,
      ).timeout(requestTimeout);
      if (addresses.isEmpty ||
          addresses.any((item) => !isPublicInternetAddress(item))) {
        throw const HttpException(
          'Preview image host did not resolve publicly.',
        );
      }
      final response = await _transport
          .get(current, addresses.first, accept: 'image/*')
          .timeout(requestTimeout);
      if (_isRedirect(response.statusCode)) {
        await response.body.drain<void>();
        final location = response.location;
        if (location == null || redirects == _maximumRedirects) {
          throw const HttpException(
            'Invalid or excessive preview image redirect.',
          );
        }
        current = current.resolveUri(location);
        continue;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.body.drain<void>();
        return null;
      }
      final type = response.contentType?.toLowerCase();
      if (type == null || !type.startsWith('image/')) {
        await response.body.drain<void>();
        return null;
      }
      if (response.contentLength > maximumImageBytes) {
        await response.body.drain<void>();
        throw const HttpException(
          'Preview image exceeded its safe size limit.',
        );
      }
      return readBoundedResponse(
        response.body,
        maximumBytes: maximumImageBytes,
        inactivityTimeout: requestTimeout,
      );
    }
    return null;
  }

  static void _validateScheme(Uri url) {
    if ((!url.isScheme('http') && !url.isScheme('https')) || url.host.isEmpty) {
      throw const HttpException('Only public HTTP(S) previews are allowed.');
    }
    if (url.userInfo.isNotEmpty) {
      throw const HttpException(
        'Credential-bearing preview URLs are rejected.',
      );
    }
  }

  static bool _isRedirect(int status) =>
      status == 301 ||
      status == 302 ||
      status == 303 ||
      status == 307 ||
      status == 308;

  static bool _isAllowedDocumentType(String? type) {
    final normalized = type?.toLowerCase().split(';').first.trim();
    return normalized == 'text/html' || normalized == 'application/xhtml+xml';
  }
}

class _DocumentMetadata {
  const _DocumentMetadata({
    this.title,
    this.description,
    this.siteName,
    this.imageUrl,
    this.width,
    this.height,
  });
  final String? title;
  final String? description;
  final String? siteName;
  final Uri? imageUrl;
  final int? width;
  final int? height;
}

_DocumentMetadata _metadataFromDocument(Document document, Uri baseUrl) {
  String? meta(List<String> names, {int maximumLength = 4096}) {
    for (final name in names) {
      for (final element in document.querySelectorAll('meta')) {
        final key =
            (element.attributes['property'] ?? element.attributes['name'])
                ?.toLowerCase();
        if (key != name) continue;
        final value = element.attributes['content']?.trim();
        if (value != null && value.isNotEmpty) {
          return value.length <= maximumLength
              ? value
              : value.substring(0, maximumLength);
        }
      }
    }
    return null;
  }

  int? dimension(List<String> names) {
    final value = int.tryParse(meta(names, maximumLength: 16) ?? '');
    return value != null && value > 0 && value <= 100000 ? value : null;
  }

  final image = meta(const ['og:image', 'twitter:image'], maximumLength: 4096);
  final imageUrl = image == null ? null : Uri.tryParse(image);
  final resolvedImage = imageUrl == null ? null : baseUrl.resolveUri(imageUrl);
  final title =
      meta(const ['og:title', 'twitter:title'], maximumLength: 512) ??
      document.querySelector('title')?.text.trim();
  return _DocumentMetadata(
    title: title?.isEmpty == true ? null : title,
    description: meta(const [
      'og:description',
      'twitter:description',
      'description',
    ]),
    siteName: meta(const ['og:site_name'], maximumLength: 128) ?? baseUrl.host,
    imageUrl: resolvedImage,
    width: dimension(const ['og:image:width']),
    height: dimension(const ['og:image:height']),
  );
}

abstract interface class DirectPreviewTransport {
  Future<DirectPreviewResponse> get(
    Uri url,
    InternetAddress address, {
    required String accept,
  });
}

class DirectPreviewResponse {
  const DirectPreviewResponse({
    required this.statusCode,
    required this.body,
    this.contentType,
    this.contentLength = -1,
    this.location,
  });
  final int statusCode;
  final Stream<List<int>> body;
  final String? contentType;
  final int contentLength;
  final Uri? location;
}

class PinnedDirectPreviewTransport implements DirectPreviewTransport {
  const PinnedDirectPreviewTransport();

  @override
  Future<DirectPreviewResponse> get(
    Uri url,
    InternetAddress address, {
    required String accept,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = _requestTimeout
      ..idleTimeout = _requestTimeout
      ..autoUncompress = true;
    client.findProxy = (_) => 'DIRECT';
    client.connectionFactory = (target, _, _) => Socket.startConnect(
      address,
      target.hasPort ? target.port : (target.isScheme('https') ? 443 : 80),
    );
    try {
      final request = await client.getUrl(url).timeout(_requestTimeout);
      request
        ..followRedirects = false
        ..maxRedirects = 0
        ..headers.set(HttpHeaders.acceptHeader, accept)
        ..headers.set(
          HttpHeaders.userAgentHeader,
          'Deltiecord/$deltiecordVersion (link preview)',
        );
      final response = await request.close().timeout(_requestTimeout);
      StreamSubscription<List<int>>? subscription;
      late final StreamController<List<int>> controller;
      controller = StreamController<List<int>>(
        sync: true,
        onListen: () {
          subscription = response.listen(
            controller.add,
            onError: (Object error, StackTrace stack) {
              controller.addError(error, stack);
              unawaited(controller.close());
              client.close(force: true);
            },
            onDone: () {
              unawaited(controller.close());
              client.close();
            },
          );
        },
        onPause: () => subscription?.pause(),
        onResume: () => subscription?.resume(),
        onCancel: () async {
          await subscription?.cancel();
          client.close(force: true);
        },
      );
      final locationHeader = response.headers.value(HttpHeaders.locationHeader);
      return DirectPreviewResponse(
        statusCode: response.statusCode,
        contentType: response.headers.contentType?.mimeType,
        contentLength: response.contentLength,
        location: response.redirects.isNotEmpty
            ? response.redirects.last.location
            : locationHeader == null || locationHeader.trim().isEmpty
            ? null
            : Uri.tryParse(locationHeader),
        body: controller.stream,
      );
    } catch (_) {
      client.close(force: true);
      rethrow;
    }
  }
}
