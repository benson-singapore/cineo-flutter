import 'package:flutter_test/flutter_test.dart';
import 'package:cineo_flutter/data/hub/hub_sync_policy.dart';

void main() {
  test(
      'progress push interval accepts only supported values and defaults to 10',
      () {
    expect(normalizeProgressPushInterval(null), 10);
    expect(normalizeProgressPushInterval(5), 5);
    expect(normalizeProgressPushInterval(60), 60);
    expect(normalizeProgressPushInterval(4), 10);
    expect(normalizeProgressPushInterval(11), 10);
    expect(normalizeProgressPushInterval(120), 10);
  });

  test('progress push requires a changed value and elapsed configured interval',
      () {
    expect(
        shouldPushProgress(
            lastValue: 100,
            currentValue: 100,
            elapsed: const Duration(seconds: 30),
            intervalSeconds: 10),
        isFalse);
    expect(
        shouldPushProgress(
            lastValue: 100,
            currentValue: 101,
            elapsed: const Duration(seconds: 9),
            intervalSeconds: 10),
        isFalse);
    expect(
        shouldPushProgress(
            lastValue: 100,
            currentValue: 101,
            elapsed: const Duration(seconds: 10),
            intervalSeconds: 10),
        isTrue);
  });

  test('favorite debounce keeps the latest state for a record key', () {
    final values = coalesceFavoriteChanges([
      ('site:1', true),
      ('site:2', true),
      ('site:1', false),
    ]);
    expect(values, {'site:1': false, 'site:2': true});
  });
}
