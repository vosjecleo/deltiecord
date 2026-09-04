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
}
