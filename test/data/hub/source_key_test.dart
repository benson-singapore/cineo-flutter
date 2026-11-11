import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cineo_flutter/data/hub/hub_sync_keys.dart';

void main() {
  test('preserves raw escaped path and query fragments when hashing', () {
    expect(
      hubSourceKey('https://example.test/a/../a%2Fb/?z=%2f&b=2&z=%2F#section'),
      '9d3b50a8a7461790c7715907da7807c57b0b4255370a48745278ae3ad75252fa',
    );
  });

  test('source keys match every shared contract vector', () async {
    final vectors = jsonDecode(
      await File('test/resources/site-sourcekey-vectors.json').readAsString(),
    ) as Map<String, dynamic>;

    for (final vector in vectors['vectors'] as List<dynamic>) {
      final entry = vector as Map<String, dynamic>;
      final expected = entry['expected_source_key'] as String?;
      if (expected == null) {
        expect(() => hubSourceKey(entry['input_url'] as String),
            throwsFormatException,
            reason: entry['name'] as String);
      } else {
        expect(hubSourceKey(entry['input_url'] as String), expected,
            reason: entry['name'] as String);
      }
    }
  });
}
