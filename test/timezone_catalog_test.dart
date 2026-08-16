import 'package:deltiecord/services/timezone_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('public timezone labels expose only an offset', () {
    final label = TimezoneCatalog.offsetLabel('Europe/Amsterdam');

    expect(label, startsWith('UTC+'));
    expect(label, isNot(contains('Europe/Amsterdam')));
    expect(
      TimezoneCatalog.localTimeLabel('Europe/Amsterdam'),
      endsWith('local time'),
    );
  });
}
