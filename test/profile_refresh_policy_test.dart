import 'package:deltiecord/services/profile_refresh_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final origin = DateTime.utc(2026, 8, 17, 12);

  test('status and textual metadata use separate refresh clocks', () {
    expect(
      ProfileRefreshPolicy.statusIsStale(
        origin,
        origin.add(const Duration(seconds: 59)),
      ),
      isFalse,
    );
    expect(
      ProfileRefreshPolicy.statusIsStale(
        origin,
        origin.add(const Duration(minutes: 1)),
      ),
      isTrue,
    );
    expect(
      ProfileRefreshPolicy.metadataIsStale(
        origin,
        origin.add(const Duration(minutes: 4, seconds: 59)),
      ),
      isFalse,
    );
    expect(
      ProfileRefreshPolicy.metadataIsStale(
        origin,
        origin.add(const Duration(minutes: 5)),
      ),
      isTrue,
    );
  });

  test('only recently represented profiles remain on the polling set', () {
    expect(
      ProfileRefreshPolicy.wasRecentlyAccessed(
        origin,
        origin.add(const Duration(minutes: 9, seconds: 59)),
      ),
      isTrue,
    );
    expect(
      ProfileRefreshPolicy.wasRecentlyAccessed(
        origin,
        origin.add(const Duration(minutes: 10)),
      ),
      isFalse,
    );
  });
}
