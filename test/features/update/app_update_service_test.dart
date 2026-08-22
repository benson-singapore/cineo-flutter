import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:cineo_flutter/features/update/app_update_service.dart';

void main() {
  test('uses the latest GitHub release tag for update detection', () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'api.github.com');
      return http.Response(
        jsonEncode({
          'tag_name': 'v1.0.4',
          'html_url':
              'https://github.com/benson-singapore/cineo-flutter/releases/tag/v1.0.4',
          'body': '修复播放体验\n优化设置页面',
          'published_at': '2026-08-22T08:00:00Z',
          'assets': [
            {
              'browser_download_url':
                  'https://github.com/benson-singapore/cineo-flutter/releases/download/v1.0.4/Cineo.apk',
            },
          ],
        }),
        200,
        headers: const {
          'content-type': 'application/json; charset=utf-8',
        },
      );
    });
    final service = AppUpdateService(client: client)..currentVersion = '1.0.3';

    await service.checkForUpdates();

    expect(service.latestVersion, 'v1.0.4');
    expect(service.hasUpdate, isTrue);
    expect(service.releaseNotes, contains('修复播放体验'));
    expect(service.latestReleaseUri?.path, contains('releases/tag/v1.0.4'));
    expect(service.latestDownloadUri?.path, contains('Cineo.apk'));
    service.dispose();
  });

  test('matches equal versions and supports historical build suffixes',
      () async {
    final client = MockClient(
      (_) async => http.Response('{"tag_name":"v1.0.3+9"}', 200),
    );
    final service = AppUpdateService(client: client)
      ..currentVersion = '1.0.3+4';

    await service.checkForUpdates();

    expect(service.hasUpdate, isFalse);
    service.dispose();
  });

  test('ignores an unavailable GitHub response', () async {
    final client = MockClient((_) async => http.Response('unavailable', 503));
    final service = AppUpdateService(client: client);

    await service.checkForUpdates();

    expect(service.latestVersion, isNull);
    expect(service.hasUpdate, isFalse);
    service.dispose();
  });
}
