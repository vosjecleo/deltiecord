import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:deltiecord/services/link_preview_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rewrites X and Twitter links while preserving other hosts', () {
    expect(
      rewriteTwitterLinks('See https://x.com/alice/status/123?s=20'),
      'See https://fxtwitter.com/alice/status/123?s=20',
    );
    expect(
      rewriteTwitterLinks('Profile https://x.com/alice'),
      'Profile https://fxtwitter.com/alice',
    );
    expect(
      rewriteTwitterLinks('Docs https://example.com/x.com/alice'),
      'Docs https://example.com/x.com/alice',
    );
  });
  test(
    'live direct transport completes HTTPS and parses metadata',
    () async {
      final url = Platform.environment['DELTIECORD_LIVE_PREVIEW_URL'];
      final preview = await DirectLinkPreviewFetcher().fetch(
        Uri.parse(url ?? 'https://example.com/'),
      );
      expect(preview, isNotNull);
      if (url == null) expect(preview?.title, contains('Example Domain'));
      if (Platform.environment['DELTIECORD_LIVE_PREVIEW_EXPECT_VIDEO'] == '1') {
        expect(preview?.videoUrl, isNotNull);
      }
    },
    skip: Platform.environment['DELTIECORD_LIVE_PREVIEW_TEST'] == '1'
        ? false
        : 'Set DELTIECORD_LIVE_PREVIEW_TEST=1 for the opt-in network probe.',
  );

  test('extracts balanced URLs and drops prose punctuation', () {
    expect(
      extractPreviewUrls(
        'See (https://example.org/a_(b)). Then https://x.test/y!',
      ).map((item) => item.toString()),
      ['https://example.org/a_(b)', 'https://x.test/y'],
    );
  });

  test('normalizes homeserver preview metadata variants', () {
    final preview = parseHomeserverLinkPreview(
      url: Uri.parse('https://example.org'),
      properties: const {
        'title': 'A title',
        'description': 'Useful copy',
        'og:image:width': '640',
        'og:image:height': 360,
      },
    );
    expect(preview.title, 'A title');
    expect(preview.description, 'Useful copy');
    expect(preview.width, 640);
    expect(preview.height, 360);
  });

  test('direct fallback parses HTML and bounded image metadata', () async {
    final transport = _FakeTransport({
      'https://public.example/page': _response(
        '<meta property="og:title" content="Hello">'
        '<meta property="og:description" content="World">'
        '<meta property="og:image" content="/image.png">',
      ),
      'https://public.example/image.png': DirectPreviewResponse(
        statusCode: 200,
        contentType: 'image/png',
        contentLength: 3,
        body: Stream.value([1, 2, 3]),
      ),
    });
    final fetcher = DirectLinkPreviewFetcher(
      resolveHost: (_) async => [InternetAddress('93.184.216.34')],
      transport: transport,
    );
    final preview = await fetcher.fetch(
      Uri.parse('https://public.example/page'),
    );
    expect(preview?.title, 'Hello');
    expect(preview?.description, 'World');
    expect(preview?.imageBytes, [1, 2, 3]);
  });

  test(
    'direct fallback validates video metadata before exposing playback',
    () async {
      final transport = _FakeTransport({
        'https://public.example/page': _response(
          '<meta property="og:title" content="Clip">'
          '<meta property="og:video" content="https://cdn.example/clip.mp4">',
        ),
        'https://cdn.example/clip.mp4': DirectPreviewResponse(
          statusCode: HttpStatus.partialContent,
          contentType: 'video/mp4',
          contentLength: 1,
          contentRange: 'bytes 0-0/4096',
          body: Stream.value([0]),
        ),
      });
      final fetcher = DirectLinkPreviewFetcher(
        resolveHost: (_) async => [InternetAddress('93.184.216.34')],
        transport: transport,
      );

      final preview = await fetcher.fetch(
        Uri.parse('https://public.example/page'),
      );

      expect(preview?.videoUrl, Uri.parse('https://cdn.example/clip.mp4'));
      expect(transport.headers.last[HttpHeaders.rangeHeader], 'bytes=0-0');
    },
  );

  test('direct fallback keeps text metadata when its image fails', () async {
    final fetcher = DirectLinkPreviewFetcher(
      resolveHost: (_) async => [InternetAddress('93.184.216.34')],
      transport: _FakeTransport({
        'https://public.example/page': _response(
          '<meta property="og:title" content="Still useful">'
          '<meta property="og:description" content="Text survives">'
          '<meta property="og:image" content="/missing.png">',
        ),
        'https://public.example/missing.png': DirectPreviewResponse(
          statusCode: 404,
          contentType: 'text/plain',
          body: const Stream.empty(),
        ),
      }),
    );

    final preview = await fetcher.fetch(
      Uri.parse('https://public.example/page'),
    );
    expect(preview?.title, 'Still useful');
    expect(preview?.description, 'Text survives');
    expect(preview?.imageBytes, isNull);
  });

  test('rejects redirects to private hosts before connecting', () async {
    final transport = _FakeTransport({
      'https://public.example/page': DirectPreviewResponse(
        statusCode: 302,
        location: Uri.parse('http://127.0.0.1/admin'),
        body: const Stream.empty(),
      ),
    });
    final fetcher = DirectLinkPreviewFetcher(
      resolveHost: (host) async => [
        InternetAddress(
          host == 'public.example' ? '93.184.216.34' : '127.0.0.1',
        ),
      ],
      transport: transport,
    );
    await expectLater(
      fetcher.fetch(Uri.parse('https://public.example/page')),
      throwsA(isA<HttpException>()),
    );
    expect(transport.opened, ['https://public.example/page']);
  });

  test('rejects oversized and malformed preview documents', () async {
    final fetcher = DirectLinkPreviewFetcher(
      resolveHost: (_) async => [InternetAddress('93.184.216.34')],
      transport: _FakeTransport({
        'https://public.example/huge': DirectPreviewResponse(
          statusCode: 200,
          contentType: 'text/html',
          contentLength: 11,
          body: Stream.value(utf8.encode('01234567890')),
        ),
      }),
      maximumDocumentBytes: 10,
    );
    await expectLater(
      fetcher.fetch(Uri.parse('https://public.example/huge')),
      throwsA(isA<HttpException>()),
    );

    final malformed = DirectLinkPreviewFetcher(
      resolveHost: (_) async => [InternetAddress('93.184.216.34')],
      transport: _FakeTransport({
        'https://public.example/empty': _response('<html><body></body></html>'),
      }),
    );
    expect(
      await malformed.fetch(Uri.parse('https://public.example/empty')),
      isNull,
    );
  });

  test('times out stalled hosts', () async {
    final fetcher = DirectLinkPreviewFetcher(
      resolveHost: (_) => Completer<List<InternetAddress>>().future,
      requestTimeout: const Duration(milliseconds: 10),
    );
    await expectLater(
      fetcher.fetch(Uri.parse('https://slow.example/page')),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('preview cache is URL-scoped, bounded, and caches misses', () {
    final cache = LinkPreviewCache(maximumEntries: 2);
    final a = Uri.parse('https://example.org/a#first');
    cache.put(a, null);
    expect(cache.getEntry(Uri.parse('https://example.org/a#second')), (
      true,
      null,
    ));
    cache.put(Uri.parse('https://example.org/b'), null);
    cache.put(Uri.parse('https://example.org/c'), null);
    expect(cache.getEntry(a).$1, isFalse);
  });

  test('preview cache expires misses so an open room can recover', () async {
    final cache = LinkPreviewCache(
      failureLifetime: const Duration(milliseconds: 5),
    );
    final url = Uri.parse('https://example.org/recover');
    cache.put(url, null);
    expect(cache.getEntry(url), (true, null));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(cache.getEntry(url).$1, isFalse);
  });
}

DirectPreviewResponse _response(String html) {
  final bytes = utf8.encode(html);
  return DirectPreviewResponse(
    statusCode: 200,
    contentType: 'text/html; charset=utf-8',
    contentLength: bytes.length,
    body: Stream.value(bytes),
  );
}

class _FakeTransport implements DirectPreviewTransport {
  _FakeTransport(this.responses);
  final Map<String, DirectPreviewResponse> responses;
  final List<String> opened = [];
  final List<Map<String, String>> headers = [];

  @override
  Future<DirectPreviewResponse> get(
    Uri url,
    InternetAddress address, {
    required String accept,
    Map<String, String> headers = const {},
  }) async {
    opened.add(url.toString());
    this.headers.add(headers);
    return responses[url.toString()] ??
        (throw StateError('Unexpected request to $url'));
  }
}
