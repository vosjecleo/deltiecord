import 'dart:typed_data';

import 'package:deltiecord/services/personal_sticker_packs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the standard Matrix personal image-pack slot stays interoperable', () {
    expect(
      personalImagePackIdForAccountDataType(
        matrixPersonalImagePackAccountDataType,
      ),
      'personal',
    );
    expect(
      accountDataContainsImagePack({
        'images': {
          'wave': {'url': 'mxc://example.org/wave'},
        },
      }),
      isTrue,
    );
    expect(accountDataContainsImagePack({'images': {}}), isFalse);
  });

  test('additional personal packs receive distinct opaque identities', () {
    final first = additionalPersonalImagePackAccountDataType(
      Uint8List.fromList(List<int>.generate(12, (index) => index)),
    );
    final second = additionalPersonalImagePackAccountDataType(
      Uint8List.fromList(List<int>.generate(12, (index) => index + 1)),
    );

    expect(first, startsWith(deltiecordPersonalImagePackAccountDataPrefix));
    expect(second, isNot(first));
    expect(isPersonalImagePackAccountDataType(first), isTrue);
    expect(
      personalImagePackIdForAccountDataType(first),
      startsWith('personal:'),
    );
    expect(
      () => additionalPersonalImagePackAccountDataType(Uint8List(11)),
      throwsArgumentError,
    );
  });

  test('merging preserves existing pack and equal aliases', () {
    final existing = <String, Object?>{
      'pack': {
        'display_name': 'Stickers',
        'usage': ['sticker'],
      },
      'images': {
        'wave': {
          'body': 'wave',
          'url': 'mxc://example.org/old',
          'usage': ['sticker'],
        },
      },
    };
    final emoji = <String, Object?>{
      'pack': {
        'display_name': 'Telegram emoji',
        'usage': ['emoticon'],
      },
      'images': {
        'wave': {
          'body': 'wave',
          'url': 'mxc://example.org/new',
          'usage': ['emoticon'],
          'net.deltiecord.asset_type': 'emoji',
        },
      },
    };

    final merged = mergePersonalImagePack(existing, emoji, packId: 'new_id');
    final packs = splitPersonalImagePacks(merged);

    expect(packs, hasLength(2));
    expect(
      packs.map((pack) => pack.content['pack']).toString(),
      contains('Telegram emoji'),
    );
    expect(
      (merged['images'] as Map).values
          .map((item) => (item as Map)['body'])
          .where((body) => body == 'wave'),
      hasLength(2),
    );
    expect(
      (merged['pack'] as Map)['usage'],
      containsAll(<String>['sticker', 'emoticon']),
    );
  });

  test('removing one merged pack leaves the other usable', () {
    var merged = mergePersonalImagePack(null, {
      'pack': {
        'display_name': 'First',
        'usage': ['emoticon'],
      },
      'images': {
        'one': {
          'body': 'one',
          'url': 'mxc://example.org/one',
          'usage': ['emoticon'],
        },
      },
    }, packId: 'first');
    merged = mergePersonalImagePack(merged, {
      'pack': {
        'display_name': 'Second',
        'usage': ['emoticon'],
      },
      'images': {
        'two': {
          'body': 'two',
          'url': 'mxc://example.org/two',
          'usage': ['emoticon'],
        },
      },
    }, packId: 'second');

    final remaining = splitPersonalImagePacks(
      removePersonalImagePack(merged, packId: 'first'),
    );
    expect(remaining, hasLength(1));
    expect((remaining.single.content['pack'] as Map)['display_name'], 'Second');
  });

  test('partially malformed registry never hides standard images', () {
    final packs = splitPersonalImagePacks({
      'pack': {'display_name': 'Fallback'},
      'images': {
        'visible': {'body': 'visible', 'url': 'mxc://example.org/visible'},
      },
      deltiecordPersonalPackRegistryKey: {
        'missing': {'display_name': 'Missing'},
      },
    });

    expect(packs, hasLength(1));
    expect(packs.single.id, 'legacy');
  });
}
