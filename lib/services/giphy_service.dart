import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../version.dart';
import 'bounded_http.dart';
import 'public_network_address.dart';
import 'private_file_store.dart';

class GifSearchResult {
  const GifSearchResult({
    required this.title,
    required this.previewUrl,
    required this.shareUrl,
  });

  final String title;
  final Uri previewUrl;
  final Uri shareUrl;

  Map<String, String> toJson() => {
    'title': title,
    'preview_url': previewUrl.toString(),
    'share_url': shareUrl.toString(),
  };

  static GifSearchResult? fromJson(Object? value) {
    if (value is! Map) return null;
    final previewUrl = Uri.tryParse(value['preview_url']?.toString() ?? '');
    final shareUrl = Uri.tryParse(value['share_url']?.toString() ?? '');
    if (previewUrl == null ||
        shareUrl == null ||
        !previewUrl.hasScheme ||
        !shareUrl.hasScheme) {
      return null;
    }
    return GifSearchResult(
      title: value['title']?.toString() ?? 'GIF',
      previewUrl: previewUrl,
      shareUrl: shareUrl,
    );
  }
}

/// Small client for GIPHY's public API (not adapted from a third-party picker).
/// Deltiecord's rate-limited server proxy adds the shared application key, so
/// neither source archives nor release binaries contain that credential.
class GiphyService {
  GiphyService();

  static const _proxyUrl = String.fromEnvironment(
    'GIPHY_PROXY_URL',
    defaultValue: 'https://deltie.net/api/servers/giphy/search',
  );
  static const _maximumSearchBytes = 2 * 1024 * 1024;
  static const _maximumGifBytes = 25 * 1024 * 1024;
  static const _requestTimeout = Duration(seconds: 10);
  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..idleTimeout = const Duration(seconds: 10)
    ..userAgent = 'Deltiecord/$deltiecordVersion';
  File? _favoritesFile;
  List<GifSearchResult>? _favorites;

  Future<List<GifSearchResult>> search(String query) => _request({'q': query});

  Future<List<GifSearchResult>> trending() async {
    try {
      return await _request(const {'mode': 'trending'});
    } on HttpException {
      // Older deployments of the proxy only expose search. Keep the picker
      // useful during a rolling server upgrade, albeit with approximate
      // trending results.
      return search('trending');
    }
  }

  Future<List<GifSearchResult>> _request(
    Map<String, String> queryParameters,
  ) async {
    final base = Uri.parse(_proxyUrl);
    if (base.scheme != 'https') {
      throw StateError('The GIF search proxy must use HTTPS.');
    }
    final uri = base.replace(queryParameters: queryParameters);
    final request = await _http.getUrl(uri).timeout(_requestTimeout);
    request
      ..followRedirects = false
      ..headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close().timeout(_requestTimeout);
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException('GIF search returned ${response.statusCode}.');
    }
    if (!hasContentType(response, const ['application/json'])) {
      await response.drain<void>();
      throw const HttpException('GIF search returned an unexpected response.');
    }
    if (response.contentLength > _maximumSearchBytes) {
      await response.drain<void>();
      throw const HttpException('GIF search response is too large.');
    }
    final body = utf8.decode(
      await readBoundedResponse(
        response,
        maximumBytes: _maximumSearchBytes,
        inactivityTimeout: _requestTimeout,
      ),
    );
    final json = jsonDecode(body) as Map<String, Object?>;
    final data = json['data'];
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((item) {
          final images = item['images'] as Map?;
          final preview =
              (images?['fixed_width_still'] as Map?) ??
              (images?['fixed_width'] as Map?);
          // Originals can be tens of megabytes. A downsized rendition keeps
          // chat quality while making selection, encryption, and upload much
          // faster for every client involved.
          final send =
              (images?['downsized_medium'] as Map?) ??
              (images?['downsized'] as Map?) ??
              (images?['original'] as Map?);
          return GifSearchResult(
            title: item['title']?.toString() ?? 'GIF',
            previewUrl: Uri.parse(preview?['url']?.toString() ?? ''),
            shareUrl: Uri.parse(send?['url']?.toString() ?? ''),
          );
        })
        .where((gif) => gif.previewUrl.hasScheme && gif.shareUrl.hasScheme)
        .toList();
  }

  Future<List<GifSearchResult>> favorites() async {
    final loaded = _favorites;
    if (loaded != null) return List.unmodifiable(loaded);
    try {
      final support = await getApplicationSupportDirectory();
      _favoritesFile = File(
        path.join(support.path, 'deltiecord', 'giphy_favorites.json'),
      );
      final file = _favoritesFile!;
      if (!await file.exists()) {
        _favorites = [];
      } else {
        final decoded = jsonDecode(await file.readAsString()) as List;
        _favorites = decoded
            .map(GifSearchResult.fromJson)
            .whereType<GifSearchResult>()
            .toList();
      }
    } catch (_) {
      _favorites = [];
    }
    return List.unmodifiable(_favorites!);
  }

  Future<bool> toggleFavorite(GifSearchResult gif) async {
    await favorites();
    final existing = _favorites!.indexWhere(
      (favorite) => favorite.shareUrl == gif.shareUrl,
    );
    final nowFavorite = existing < 0;
    if (nowFavorite) {
      _favorites!.insert(0, gif);
      if (_favorites!.length > 100) _favorites!.removeLast();
    } else {
      _favorites!.removeAt(existing);
    }
    final file = _favoritesFile;
    if (file != null) {
      await writePrivateTextFile(
        file,
        jsonEncode(_favorites!.map((favorite) => favorite.toJson()).toList()),
      );
    }
    return nowFavorite;
  }

  bool isFavorite(GifSearchResult gif) =>
      _favorites?.any((favorite) => favorite.shareUrl == gif.shareUrl) ?? false;

  Future<Uint8List> download(GifSearchResult gif) async {
    final uri = gif.shareUrl;
    if (uri.scheme != 'https' ||
        !(uri.host == 'giphy.com' || uri.host.endsWith('.giphy.com'))) {
      throw StateError('GIPHY returned an unexpected media URL.');
    }
    final response = await _openGiphyMedia(uri);
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException('GIPHY media returned ${response.statusCode}.');
    }
    if (!hasContentType(response, const ['image'])) {
      await response.drain<void>();
      throw const HttpException('GIPHY returned unexpected media content.');
    }
    if (response.contentLength > _maximumGifBytes) {
      await response.drain<void>();
      throw const HttpException('GIPHY media exceeds the 25 MiB safety limit.');
    }
    return readBoundedResponse(
      response,
      maximumBytes: _maximumGifBytes,
      inactivityTimeout: _requestTimeout,
    );
  }

  Future<HttpClientResponse> _openGiphyMedia(Uri initialUri) async {
    var uri = initialUri;
    for (var redirects = 0; redirects <= 3; redirects++) {
      if (!_isGiphyMediaUri(uri)) {
        throw const HttpException('GIPHY redirected to an untrusted host.');
      }
      final addresses = await InternetAddress.lookup(
        uri.host,
      ).timeout(_requestTimeout);
      if (addresses.isEmpty || !addresses.every(isPublicInternetAddress)) {
        throw const HttpException('GIPHY media resolved to a private address.');
      }
      final request = await _http.getUrl(uri).timeout(_requestTimeout);
      request
        ..followRedirects = false
        ..headers.set(HttpHeaders.acceptHeader, 'image/gif,image/*;q=0.8');
      final response = await request.close().timeout(_requestTimeout);
      if (!_isRedirect(response.statusCode)) return response;
      final location = response.headers.value(HttpHeaders.locationHeader);
      await response.drain<void>();
      if (location == null || redirects == 3) {
        throw const HttpException('GIPHY returned an invalid redirect.');
      }
      uri = uri.resolve(location);
    }
    throw const HttpException('Too many GIPHY redirects.');
  }

  bool _isGiphyMediaUri(Uri uri) =>
      uri.scheme == 'https' &&
      (uri.host == 'giphy.com' || uri.host.endsWith('.giphy.com'));

  bool _isRedirect(int status) =>
      status == HttpStatus.movedPermanently ||
      status == HttpStatus.found ||
      status == HttpStatus.seeOther ||
      status == HttpStatus.temporaryRedirect ||
      status == HttpStatus.permanentRedirect;

  void dispose() => _http.close(force: true);
}
