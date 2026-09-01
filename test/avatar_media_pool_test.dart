import 'dart:io';
import 'dart:typed_data';

import 'package:deltiecord/services/avatar_media_pool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory cacheDirectory;

  setUp(() async {
    cacheDirectory = await Directory.systemTemp.createTemp(
      'deltiecord-avatar-pool-',
    );
  });

  tearDown(() async {
    if (await cacheDirectory.exists()) {
      await cacheDirectory.delete(recursive: true);
    }
  });

  test('coalesces concurrent requests for one MXC thumbnail', () async {
    final pool = AvatarMediaPool(directory: cacheDirectory);
    final uri = Uri.parse('mxc://example.org/alice');
    var loads = 0;
    Future<Uint8List?> loader() async {
      loads++;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      return Uint8List.fromList([1, 2, 3]);
    }

    final results = await Future.wait([
      pool.load(uri, AvatarMediaPool.rowDimension, loader),
      pool.load(uri, AvatarMediaPool.rowDimension, loader),
    ]);

    expect(loads, 1);
    expect(results[0], [1, 2, 3]);
    expect(results[1], [1, 2, 3]);
  });

  test('larger cached avatars satisfy smaller surfaces', () {
    final pool = AvatarMediaPool(directory: cacheDirectory);
    final uri = Uri.parse('mxc://example.org/alice');
    final bytes = Uint8List.fromList([4, 5, 6]);

    pool.seed(uri, bytes, AvatarMediaPool.profileDimension);

    expect(pool.peek(uri, AvatarMediaPool.rowDimension), same(bytes));
    expect(pool.peek(uri, AvatarMediaPool.profileDimension), same(bytes));
  });

  test('disk cache survives a new pool without another network load', () async {
    final uri = Uri.parse('mxc://example.org/alice');
    final first = AvatarMediaPool(directory: cacheDirectory);
    expect(
      await first.load(
        uri,
        AvatarMediaPool.rowDimension,
        () async => Uint8List.fromList([7, 8, 9]),
      ),
      [7, 8, 9],
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final second = AvatarMediaPool(directory: cacheDirectory);
    var networkLoads = 0;
    final result = await second.load(
      uri,
      AvatarMediaPool.rowDimension,
      () async {
        networkLoads++;
        return Uint8List.fromList([0]);
      },
    );

    expect(result, [7, 8, 9]);
    expect(networkLoads, 0);
  });
}
