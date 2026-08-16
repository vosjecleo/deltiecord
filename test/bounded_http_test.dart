import 'dart:async';
import 'dart:io';

import 'package:deltiecord/services/bounded_http.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bounded reader accepts data at the limit', () async {
    final result = await readBoundedResponse(
      Stream.fromIterable(const [
        <int>[1, 2],
        <int>[3, 4],
      ]),
      maximumBytes: 4,
    );
    expect(result, [1, 2, 3, 4]);
  });

  test('bounded reader rejects oversized and stalled responses', () async {
    await expectLater(
      readBoundedResponse(
        Stream.fromIterable(const [
          <int>[1, 2, 3],
        ]),
        maximumBytes: 2,
      ),
      throwsA(isA<HttpException>()),
    );
    await expectLater(
      readBoundedResponse(
        Stream<List<int>>.fromFuture(
          Future<List<int>>.delayed(const Duration(seconds: 1), () => [1]),
        ),
        maximumBytes: 2,
        inactivityTimeout: const Duration(milliseconds: 10),
      ),
      throwsA(isA<TimeoutException>()),
    );
  });
}
