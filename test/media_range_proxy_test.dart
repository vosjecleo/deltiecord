import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:deltiecord/matrix/media_range_proxy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'serves a non-aligned decrypted byte range without full download',
    () async {
      final plaintext = Uint8List.fromList(
        utf8.encode(
          List.filled(200, 'Deltiecord encrypted streaming range test ').join(),
        ),
      );
      final key = Uint8List.fromList(List.generate(32, (index) => index));
      final iv = Uint8List.fromList([
        12,
        34,
        56,
        78,
        90,
        12,
        34,
        56,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
      ]);
      Uint8List xorRange(
        Uint8List input,
        Uint8List key,
        Uint8List _,
        int blockOffset,
      ) => Uint8List.fromList([
        for (var index = 0; index < input.length; index++)
          input[index] ^ key[(blockOffset * 16 + index) % key.length],
      ]);
      final ciphertext = xorRange(plaintext, key, iv, 0);
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var bytesServed = 0;
      upstream.listen((request) async {
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer token',
        );
        final range = request.headers.value(HttpHeaders.rangeHeader)!;
        final match = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range)!;
        final start = int.parse(match.group(1)!);
        final end = int.parse(match.group(2)!);
        final bytes = ciphertext.sublist(start, end + 1);
        bytesServed += bytes.length;
        request.response
          ..statusCode = HttpStatus.partialContent
          ..headers.contentLength = bytes.length
          ..headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $start-$end/${ciphertext.length}',
          )
          ..add(bytes);
        await request.response.close();
      });

      final proxy = MediaRangeProxy(decryptor: xorRange);
      addTearDown(() async {
        await proxy.close();
        await upstream.close(force: true);
      });
      final local = await proxy.register(
        upstream: Uri.parse(
          'http://127.0.0.1:${upstream.port}/encrypted-video',
        ),
        accessToken: 'token',
        key: key,
        iv: iv,
        size: ciphertext.length,
        mimeType: 'video/mp4',
      );

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.getUrl(local);
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=37-412');
      final response = await request.close();
      final actual = await response.fold<BytesBuilder>(
        BytesBuilder(),
        (builder, chunk) => builder..add(chunk),
      );

      expect(response.statusCode, HttpStatus.partialContent);
      expect(actual.takeBytes(), plaintext.sublist(37, 413));
      expect(bytesServed, lessThan(plaintext.length));
    },
  );

  test('serves HTTP suffix ranges from the end of encrypted media', () async {
    final plaintext = Uint8List.fromList(List.generate(1024, (index) => index));
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) async {
      final match = RegExp(
        r'bytes=(\d+)-(\d+)',
      ).firstMatch(request.headers.value(HttpHeaders.rangeHeader)!)!;
      final start = int.parse(match.group(1)!);
      final end = int.parse(match.group(2)!);
      request.response
        ..statusCode = HttpStatus.partialContent
        ..headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/${plaintext.length}',
        )
        ..add(plaintext.sublist(start, end + 1));
      await request.response.close();
    });
    final proxy = MediaRangeProxy(decryptor: (input, _, _, _) => input);
    addTearDown(() async {
      await proxy.close();
      await upstream.close(force: true);
    });
    final local = await proxy.register(
      upstream: Uri.parse('http://127.0.0.1:${upstream.port}/media'),
      accessToken: 'token',
      key: Uint8List(32),
      iv: Uint8List(16),
      size: plaintext.length,
      mimeType: 'video/mp4',
    );
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final request = await client.getUrl(local);
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=-64');
    final response = await request.close();
    final bytes = await response.fold<BytesBuilder>(
      BytesBuilder(),
      (builder, value) => builder..add(value),
    );
    expect(bytes.takeBytes(), plaintext.sublist(plaintext.length - 64));
  });

  test('serves a disjoint forward seek from its requested offset', () async {
    final plaintext = Uint8List.fromList(
      List.generate(1024 * 1024, (index) => index % 251),
    );
    final requestedRanges = <String>[];
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) async {
      final range = request.headers.value(HttpHeaders.rangeHeader)!;
      requestedRanges.add(range);
      final match = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range)!;
      final start = int.parse(match.group(1)!);
      final end = int.parse(match.group(2)!);
      request.response
        ..statusCode = HttpStatus.partialContent
        ..headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/${plaintext.length}',
        )
        ..add(plaintext.sublist(start, end + 1));
      await request.response.close();
    });
    final proxy = MediaRangeProxy(decryptor: (input, _, _, _) => input);
    addTearDown(() async {
      await proxy.close();
      await upstream.close(force: true);
    });
    final local = await proxy.register(
      upstream: Uri.parse('http://127.0.0.1:${upstream.port}/media'),
      accessToken: 'token',
      key: Uint8List(32),
      iv: Uint8List(16),
      size: plaintext.length,
      mimeType: 'video/mp4',
    );
    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    final request = await client.getUrl(local);
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=700003-701026');
    final response = await request.close();
    final bytes = await response.fold<BytesBuilder>(
      BytesBuilder(),
      (builder, value) => builder..add(value),
    );

    expect(bytes.takeBytes(), plaintext.sublist(700003, 701027));
    expect(requestedRanges, ['bytes=700000-701026']);
  });

  test('streams the first decrypted block before upstream completes', () async {
    final plaintext = Uint8List.fromList(
      List.generate(512, (index) => index % 251),
    );
    final releaseUpstream = Completer<void>();
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) async {
      final range = RegExp(
        r'bytes=(\d+)-(\d+)',
      ).firstMatch(request.headers.value(HttpHeaders.rangeHeader)!)!;
      final start = int.parse(range.group(1)!);
      final end = int.parse(range.group(2)!);
      request.response
        ..bufferOutput = false
        ..statusCode = HttpStatus.partialContent
        ..headers.contentLength = plaintext.length
        ..headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/${plaintext.length}',
        )
        ..add(plaintext.sublist(0, 64));
      await request.response.flush();
      await releaseUpstream.future;
      request.response.add(plaintext.sublist(64));
      await request.response.close();
    });
    final proxy = MediaRangeProxy(decryptor: (input, _, _, _) => input);
    addTearDown(() async {
      if (!releaseUpstream.isCompleted) releaseUpstream.complete();
      await proxy.close();
      await upstream.close(force: true);
    });
    final local = await proxy.register(
      upstream: Uri.parse('http://127.0.0.1:${upstream.port}/media'),
      accessToken: 'token',
      key: Uint8List(32),
      iv: Uint8List(16),
      size: plaintext.length,
      mimeType: 'video/mp4',
    );

    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final request = await client.getUrl(local);
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-511');
    final response = await request.close();
    final received = BytesBuilder(copy: false);
    final firstChunk = Completer<void>();
    final finished = Completer<void>();
    response.listen(
      (chunk) {
        received.add(chunk);
        if (!firstChunk.isCompleted) firstChunk.complete();
      },
      onError: finished.completeError,
      onDone: finished.complete,
    );

    await firstChunk.future.timeout(const Duration(seconds: 2));
    expect(received.length, greaterThanOrEqualTo(64));
    expect(received.length, lessThan(plaintext.length));
    releaseUpstream.complete();
    await finished.future;
    expect(received.takeBytes(), plaintext);
  });

  test('fails a nonzero seek when upstream ignores Range', () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) async {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentLength = 1024 * 1024;
      for (var index = 0; index < 1024; index++) {
        request.response.add(Uint8List(1024));
        await request.response.flush();
      }
      await request.response.close();
    });
    final proxy = MediaRangeProxy(decryptor: (input, _, _, _) => input);
    addTearDown(() async {
      await proxy.close();
      await upstream.close(force: true);
    });
    final local = await proxy.register(
      upstream: Uri.parse('http://127.0.0.1:${upstream.port}/media'),
      accessToken: 'token',
      key: Uint8List(32),
      iv: Uint8List(16),
      size: 1024 * 1024,
      mimeType: 'video/mp4',
    );
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final request = await client.getUrl(local);
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=524288-525311');
    final response = await request.close();
    expect(response.statusCode, HttpStatus.badGateway);
    expect(await response.fold<int>(0, (sum, chunk) => sum + chunk.length), 0);
  });

  test('rejects malformed Content-Range and truncated upstream data', () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var malformed = true;
    upstream.listen((request) async {
      request.response
        ..statusCode = HttpStatus.partialContent
        ..headers.set(
          HttpHeaders.contentRangeHeader,
          malformed ? 'nonsense' : 'bytes 0-31/64',
        )
        ..add(Uint8List(malformed ? 64 : 16));
      await request.response.close();
    });
    final proxy = MediaRangeProxy(decryptor: (input, _, _, _) => input);
    addTearDown(() async {
      await proxy.close();
      await upstream.close(force: true);
    });
    final local = await proxy.register(
      upstream: Uri.parse('http://127.0.0.1:${upstream.port}/media'),
      accessToken: 'token',
      key: Uint8List(32),
      iv: Uint8List(16),
      size: 64,
      mimeType: 'video/mp4',
    );
    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    Future<HttpClientResponse> fetch() async {
      final request = await client.getUrl(local);
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-31');
      return request.close();
    }

    final malformedResponse = await fetch();
    expect(malformedResponse.statusCode, HttpStatus.badGateway);
    await malformedResponse.drain<void>();
    malformed = false;
    final truncatedResponse = await fetch();
    expect(truncatedResponse.statusCode, HttpStatus.partialContent);
    await expectLater(
      truncatedResponse.drain<void>(),
      throwsA(isA<HttpException>()),
    );
  });

  test('supports HEAD, rejects invalid ranges, and expires entries', () async {
    var now = DateTime.utc(2026);
    final proxy = MediaRangeProxy(
      decryptor: (input, _, _, _) => input,
      clock: () => now,
      entryTtl: const Duration(milliseconds: 20),
    );
    addTearDown(proxy.close);
    final local = await proxy.register(
      upstream: Uri.parse('http://127.0.0.1:9/media'),
      accessToken: 'token',
      key: Uint8List(32),
      iv: Uint8List(16),
      size: 64,
      mimeType: 'video/mp4',
    );
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final head = await (await client.openUrl('HEAD', local)).close();
    expect(head.statusCode, HttpStatus.ok);
    expect(head.contentLength, 64);

    final invalidRequest = await client.getUrl(local);
    invalidRequest.headers.set(HttpHeaders.rangeHeader, 'bytes=99-100');
    final invalid = await invalidRequest.close();
    expect(invalid.statusCode, HttpStatus.requestedRangeNotSatisfiable);

    now = now.add(const Duration(milliseconds: 21));
    final expired = await (await client.getUrl(local)).close();
    expect(expired.statusCode, HttpStatus.notFound);
  });

  test(
    'unregister removes capabilities and LRU bounds retained entries',
    () async {
      final proxy = MediaRangeProxy(
        decryptor: (input, _, _, _) => input,
        maximumEntries: 2,
      );
      addTearDown(proxy.close);
      final uris = <Uri>[];
      for (var index = 0; index < 3; index++) {
        uris.add(
          await proxy.register(
            upstream: Uri.parse('http://127.0.0.1:9/media/$index'),
            accessToken: 'secret-$index',
            key: Uint8List(32),
            iv: Uint8List(16),
            size: 64,
            mimeType: 'video/mp4',
          ),
        );
      }
      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      final evicted = await (await client.openUrl('HEAD', uris.first)).close();
      expect(evicted.statusCode, HttpStatus.notFound);
      final retained = await (await client.openUrl('HEAD', uris.last)).close();
      expect(retained.statusCode, HttpStatus.ok);

      proxy.unregister(uris.last);
      final removed = await (await client.openUrl('HEAD', uris.last)).close();
      expect(removed.statusCode, HttpStatus.notFound);
    },
  );
}
