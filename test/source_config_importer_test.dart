import 'package:flutter_test/flutter_test.dart';

import 'package:cineo_flutter/core/models/media_source.dart';
import 'package:cineo_flutter/features/sources/source_config_importer.dart';

void main() {
  group('parseMacCmsSourceConfig', () {
    test('imports valid MacCMS entries and preserves shared metadata', () {
      const rawJson = '''
      {
        "cache_time": 7200,
        "api_site": {
          "movie": {
            "api": "https://media.example.test/api.php/provide/vod",
            "name": "电影资源",
            "detail": "https://media.example.test",
            "is_adult": false
          }
        }
      }
      ''';

      final result = parseMacCmsSourceConfig(rawJson);

      expect(result.issues, isEmpty);
      expect(result.sources, hasLength(1));
      final source = result.sources.single;
      expect(source.id, 'movie');
      expect(source.externalId, 'movie');
      expect(source.name, '电影资源');
      expect(source.type, MediaSourceType.macCmsApi);
      expect(source.baseUrl, 'https://media.example.test/api.php/provide/vod');
      expect(source.detailUrl, 'https://media.example.test');
      expect(source.isAdult, isFalse);
      expect(source.cacheTtlSeconds, 7200);
    });

    test('reports invalid root and entry fields without throwing', () {
      const rawJson = '''
      {
        "api_site": {
          "not_object": "bad",
          "missing_api": {"name": "没有地址"},
          "bad_url": {"api": "ftp://example.test/vod", "name": "FTP"},
          "missing_name": {"api": "https://example.test/vod"},
          "bad_host": {"api": "https://", "name": "无主机"},
          "bad_adult": {
            "api": "https://example.test/vod",
            "name": "错误标记",
            "is_adult": "false"
          }
        }
      }
      ''';

      final result = parseMacCmsSourceConfig(rawJson);

      expect(result.sources, isEmpty);
      expect(result.issues, hasLength(6));
      expect(
        result.issues.map((issue) => issue.sourceKey),
        containsAll(<String?>[
          'not_object',
          'missing_api',
          'bad_url',
          'missing_name',
          'bad_host',
          'bad_adult',
        ]),
      );
    });

    test('imports adult entries by default and can filter them on request', () {
      const rawJson = '''
      {
        "api_site": {
          "adult": {
            "api": "https://adult.example.test/api.php/provide/vod",
            "name": "成人源",
            "is_adult": true
          },
          "regular": {
            "api": "https://regular.example.test/api.php/provide/vod",
            "name": "普通源"
          }
        }
      }
      ''';

      final included = parseMacCmsSourceConfig(rawJson);
      expect(included.sources.map((source) => source.id), ['adult', 'regular']);
      expect(included.sources.first.isAdult, isTrue);
      expect(included.issues, isEmpty);

      final filtered = parseMacCmsSourceConfig(rawJson, includeAdult: false);
      expect(filtered.sources.map((source) => source.id), ['regular']);
      expect(filtered.issues.single.sourceKey, 'adult');
    });

    test('skips HTTP by default and imports it only with explicit opt-in', () {
      const rawJson = '''
      {
        "api_site": {
          "legacy": {
            "api": "http://legacy.example.test/api.php/provide/vod",
            "name": "旧站点",
            "detail": "http://legacy.example.test"
          }
        }
      }
      ''';

      final skipped = parseMacCmsSourceConfig(rawJson);
      expect(skipped.sources, isEmpty);
      expect(skipped.issues.single.sourceKey, 'legacy');

      final included = parseMacCmsSourceConfig(
        rawJson,
        allowInsecureHttp: true,
      );
      expect(included.issues, isEmpty);
      expect(included.sources.single.baseUrl, startsWith('http://'));
    });

    test('returns a nonfatal issue for malformed JSON', () {
      final result = parseMacCmsSourceConfig('{"api_site":');

      expect(result.sources, isEmpty);
      expect(result.issues, hasLength(1));
      expect(result.issues.single.sourceKey, isNull);
      expect(result.issues.single.message, contains('JSON'));
    });
  });
}
