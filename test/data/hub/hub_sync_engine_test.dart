import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cineo_flutter/core/models/media.dart';
import 'package:cineo_flutter/data/hub/hub_sync_api.dart';
import 'package:cineo_flutter/data/hub/hub_sync_engine.dart';
import 'package:cineo_flutter/data/hub/hub_sync_keys.dart';
import 'package:cineo_flutter/data/repositories/local_media_repository.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDirectory;
  late LocalMediaRepository repository;
  late Map<String, String> secureData;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('cineo_hub_engine_');
    repository = LocalMediaRepository(
      databasePath: '${tempDirectory.path}/cineo.db',
    );
    secureData = <String, String>{};
    FlutterSecureStoragePlatform.instance =
        TestFlutterSecureStoragePlatform(secureData);
  });

  tearDown(() async {
    await repository.close();
    await tempDirectory.delete(recursive: true);
  });

  Future<HubDeviceCredentials> boundCredentials() async {
    final credentials = HubDeviceCredentials();
    await credentials.save(
      hubUrl: 'https://hub.example.test',
      deviceId: 'device-1',
      token: 'device-token',
    );
    return credentials;
  }

  http.Response envelope(int status, Object? data, {int? code}) {
    final body = jsonEncode({
      'code': code ?? status,
      'message': 'ok',
      'data': data,
    });
    return http.Response(
      body,
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );
  }

  test('push and pull requests carry their sync trigger', () async {
    final seen = <String, String?>{};
    final api = HubSyncApi(
      credentials: await boundCredentials(),
      client: MockClient((request) async {
        seen[request.url.path] = request.headers['x-sync-trigger'];
        return envelope(200,
            {'items': [], 'next_seq': 0, 'generation': 1, 'has_more': false});
      }),
    );

    await api.push([], trigger: 'auto_favorite');
    await api.pull(0, trigger: 'manual_pull');

    expect(seen['/api/v1/device/sync/push'], 'auto_favorite');
    expect(seen['/api/v1/device/sync/pull'], 'manual_pull');
  });

  test('progress push sends only the changed single progress envelope',
      () async {
    final source = (await repository.sources()).single;
    final media = MediaItem(
        id: 'progress-media',
        title: 'Progress',
        description: '',
        year: 2026,
        kind: MediaKind.movie,
        posterUrl: '',
        backdropUrl: '',
        genres: const [],
        rating: 0,
        duration: const Duration(minutes: 20),
        sourceId: source.id,
        sourceName: source.name,
        remoteId: 'remote-progress',
        category: '电影');
    final progress = WatchProgress(
        mediaId: media.id,
        position: const Duration(seconds: 12),
        duration: media.duration,
        updatedAt: DateTime.utc(2026, 1, 1));
    await repository.saveProgress(progress, media: media);
    final sent = <List<dynamic>>[];
    final api = HubSyncApi(
        credentials: await boundCredentials(),
        client: MockClient((request) async {
          if (request.url.path.endsWith('/device/sync/push')) {
            sent.add((jsonDecode(request.body) as Map)['items'] as List);
            return envelope(200, {'accepted': 1});
          }
          return envelope(200, {'items': [], 'next_seq': 0, 'generation': 1});
        }));
    final engine = HubSyncEngine(repository: repository, api: api);

    await engine.pushProgress(media, progress);

    expect(sent, hasLength(1));
    expect(sent.single, hasLength(1));
    expect((sent.single.single as Map)['entity'], 'progress');
    expect((sent.single.single as Map)['payload']['position_ms'], 12000);
    expect(await (await repository.hubDatabase).query('hub_outbox'), isEmpty);
  });

  test('favorite push sends a deleted tombstone for removal', () async {
    final source = (await repository.sources()).single;
    final media = MediaItem(
        id: 'favorite-media',
        title: 'Favorite',
        description: '',
        year: 2026,
        kind: MediaKind.movie,
        posterUrl: '',
        backdropUrl: '',
        genres: const [],
        rating: 0,
        duration: Duration.zero,
        sourceId: source.id,
        sourceName: source.name,
        remoteId: 'remote-favorite',
        category: '电影');
    await repository.saveProgress(
        WatchProgress(
            mediaId: media.id,
            position: Duration.zero,
            duration: Duration.zero,
            updatedAt: DateTime.utc(2026)),
        media: media);
    final sent = <Map<String, dynamic>>[];
    final api = HubSyncApi(
        credentials: await boundCredentials(),
        client: MockClient((request) async {
          if (request.url.path.endsWith('/device/sync/push')) {
            sent.add((jsonDecode(request.body) as Map)['items'].single
                as Map<String, dynamic>);
            return envelope(200, {'accepted': 1});
          }
          return envelope(200, {'items': [], 'next_seq': 0, 'generation': 1});
        }));
    final engine = HubSyncEngine(repository: repository, api: api);

    await engine.queueFavorite(media, false);

    expect(sent.single['entity'], 'favorite');
    expect(sent.single['deleted'], isTrue);
    expect(sent.single['payload'], isNull);
  });

  test('pushAll splits outbox records into batches of at most 500', () async {
    final db = await repository.hubDatabase;
    for (var index = 0; index < 501; index++) {
      await db.insert('hub_outbox', {
        'entity': 'favorite',
        'record_key': 'batch-$index',
        'updated_at': index,
        'deleted': 0,
        'payload_json': '{"title":"batch"}',
        'attempts': 0,
        'next_attempt_at': 0,
      });
    }
    final batchSizes = <int>[];
    final api = HubSyncApi(
      credentials: await boundCredentials(),
      client: MockClient((request) async {
        final items = (jsonDecode(request.body) as Map)['items'] as List;
        batchSizes.add(items.length);
        return envelope(200, {'accepted': items.length, 'ignored': 0});
      }),
    );
    final engine = HubSyncEngine(repository: repository, api: api);

    final result = await engine.pushAll();

    expect(batchSizes.length, greaterThanOrEqualTo(2));
    expect(batchSizes.every((size) => size <= 500), isTrue);
    expect(result['sent'], result['total']);
    expect(result['failed'], 0);
  });

  test(
      'pushAll counts every remaining outbox row as failed after a batch error',
      () async {
    final db = await repository.hubDatabase;
    for (var index = 0; index < 3; index++) {
      await db.insert('hub_outbox', {
        'entity': 'favorite',
        'record_key': 'failure-$index',
        'updated_at': index,
        'deleted': 0,
        'payload_json': '{"title":"failure"}',
        'attempts': 0,
        'next_attempt_at': 0,
      });
    }
    final api = HubSyncApi(
      credentials: await boundCredentials(),
      client: MockClient((request) async => envelope(500, null, code: 50000)),
    );
    final engine = HubSyncEngine(repository: repository, api: api);

    final result = await engine.pushAll();

    expect(result['total'], greaterThanOrEqualTo(3));
    expect(result['failed'], result['total']);
    expect(result['error'], isNotNull);
  });

  test('pushAll skips and counts a single envelope larger than 1 MiB',
      () async {
    final db = await repository.hubDatabase;
    await db.insert('hub_outbox', {
      'entity': 'favorite',
      'record_key': 'oversize',
      'updated_at': 1,
      'deleted': 0,
      'payload_json': jsonEncode({'title': 'x' * (1024 * 1024)}),
      'attempts': 0,
      'next_attempt_at': 0,
    });
    final pushedKeys = <String>[];
    final api = HubSyncApi(
      credentials: await boundCredentials(),
      client: MockClient((request) async {
        final items = (jsonDecode(request.body) as Map)['items'] as List;
        pushedKeys.addAll(items.map((item) => (item as Map)['key'] as String));
        return envelope(200, {'accepted': items.length, 'ignored': 0});
      }),
    );
    final result =
        await HubSyncEngine(repository: repository, api: api).pushAll();

    expect(pushedKeys, isNot(contains('oversize')));
    expect(result['total'], greaterThanOrEqualTo(1));
    expect(result['failed'], 1);
    expect(result['error'], contains('超过 1 MB'));
  });

  test('scheduled retry only sends push with retry trigger', () async {
    final db = await repository.hubDatabase;
    await db.insert('hub_outbox', {
      'entity': 'favorite',
      'record_key': 'retry-favorite',
      'updated_at': 1,
      'deleted': 0,
      'payload_json': '{"title":"retry"}',
      'attempts': 0,
      'next_attempt_at': 0,
    });
    final requests = <(String, String?)>[];
    var pushAttempt = 0;
    final api = HubSyncApi(
      credentials: await boundCredentials(),
      client: MockClient((request) async {
        requests.add((request.url.path, request.headers['x-sync-trigger']));
        if (request.url.path.endsWith('/device/sync/push') &&
            pushAttempt++ == 0) {
          return envelope(500, null, code: 50000);
        }
        if (request.url.path.endsWith('/device/sync/push')) {
          return envelope(200, {'accepted': 1});
        }
        return envelope(200, {
          'items': [],
          'next_seq': 0,
          'generation': 1,
          'has_more': false,
        });
      }),
    );
    final engine = HubSyncEngine(repository: repository, api: api);

    await expectLater(engine.pushOutbox(trigger: 'auto_favorite'),
        throwsA(isA<HubApiException>()));
    await Future<void>.delayed(const Duration(milliseconds: 1200));

    expect(requests, [
      ('/api/v1/device/sync/push', 'auto_favorite'),
      ('/api/v1/device/sync/push', 'retry'),
    ]);
    expect(await db.query('hub_outbox'), isEmpty);
  });

  test('MockClient returns a successful Hub envelope', () async {
    final client = MockClient((_) async =>
        http.Response('{"code":200,"message":"ok","data":{"items":[]}}', 200));
    final api = HubSyncApi(
      credentials: await boundCredentials(),
      client: client,
    );

    expect(await api.pull(0), {'items': []});
  });

  test('materializes pulled favorites and history into local tables', () async {
    final source = (await repository.sources()).single;
    final key = hubMediaKey(
      sourceKey: hubSourceKey(source.baseUrl),
      vodId: 'remote-42',
    );
    final updatedAt = DateTime.utc(2026, 1, 2).millisecondsSinceEpoch;
    var pushed = false;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/device/sync/pull')) {
        final response = envelope(200, {
          'items': [
            {
              'entity': 'favorite',
              'key': key,
              'updated_at': updatedAt,
              'deleted': false,
              'payload': {
                'title': '跨端收藏剧集',
                'category': '剧集',
                'added_at': updatedAt,
              },
            },
            for (final entity in ['history', 'progress'])
              {
                'entity': entity,
                'key': key,
                'updated_at': updatedAt,
                'deleted': false,
                'payload': {
                  'title': '跨端收藏剧集',
                  'line_name': '',
                  'episode_index': 0,
                  'position_ms': 42000,
                  'duration_ms': 180000,
                },
              },
          ],
          'next_seq': 3,
          'generation': 1,
          'has_more': false,
        });
        return response;
      }
      if (request.url.path.endsWith('/device/sync/push')) {
        pushed = true;
        return envelope(200, {'accepted': 1});
      }
      if (request.url.path.endsWith('/device/settings')) {
        return envelope(200, {
          'tmdb_key': null,
          'preferences': {'tmdb_language': 'zh-CN', 'include_adult': false},
          'updated_at': updatedAt,
        });
      }
      return envelope(404, null, code: 40400);
    });
    final api =
        HubSyncApi(credentials: await boundCredentials(), client: client);
    final engine = HubSyncEngine(repository: repository, api: api);

    await engine.pullAndApply(trigger: 'manual_pull');
    final favorites = await repository.favorites();
    expect(favorites.map((item) => item.title), contains('跨端收藏剧集'));
    final history = await repository.watchHistory();
    expect(history, hasLength(1));
    expect(history.single.position.inMilliseconds, 42000);
    expect(history.single.duration.inMilliseconds, 180000);
    expect(pushed, isFalse, reason: 'pull must not trigger a push');
  });

  test('pull does not push even when local source rows are invalid', () async {
    final db = await repository.hubDatabase;
    await db.insert('sources', {
      'id': 'bad-source',
      'name': 'Invalid source',
      'type': 1,
      'base_url': 'https://',
      'enabled': 1,
      'is_adult': 0,
      'is_default': 0,
      'cover_mode': 0,
    });
    var pushRequests = 0;
    var pullRequests = 0;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/device/sync/pull')) {
        pullRequests++;
        return envelope(200, {
          'items': [],
          'next_seq': 0,
          'generation': 1,
          'has_more': false,
        });
      }
      if (request.url.path.endsWith('/device/sync/push')) {
        pushRequests++;
        return envelope(200, {'accepted': 1});
      }
      if (request.url.path.endsWith('/device/settings')) {
        return envelope(200, {
          'tmdb_key': null,
          'preferences': const {},
          'updated_at': 0,
        });
      }
      return envelope(404, null, code: 40400);
    });
    final engine = HubSyncEngine(
      repository: repository,
      api: HubSyncApi(credentials: await boundCredentials(), client: client),
    );

    await engine.pullAndApply(trigger: 'manual_pull');

    expect(pullRequests, 1);
    expect(pushRequests, 0, reason: 'pull must not trigger a push');
    final outbox = await db.query('hub_outbox');
    expect(outbox, isEmpty);
  });

  test('unknown remote site type removes the previously usable source',
      () async {
    final db = await repository.hubDatabase;
    await db.insert('sources', {
      'id': 'hub-unknown-key',
      'name': 'Previously known',
      'type': 1,
      'base_url': 'https://known.example/api',
      'enabled': 1,
      'external_id': 'unknown-key',
      'is_adult': 0,
      'is_default': 0,
      'cover_mode': 0,
    });
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/device/sync/pull')) {
        return envelope(200, {
          'items': [
            {
              'entity': 'site',
              'key': 'unknown-key',
              'updated_at': 123,
              'deleted': false,
              'payload': {
                'name': 'Future site',
                'api': 'https://future.example/api',
                'site_type': 'future-type',
              },
            },
          ],
          'next_seq': 1,
          'generation': 1,
          'has_more': false,
        });
      }
      return envelope(200, {
        'tmdb_key': null,
        'preferences': const {},
        'updated_at': 0,
      });
    });
    final engine = HubSyncEngine(
      repository: repository,
      api: HubSyncApi(credentials: await boundCredentials(), client: client),
    );

    await engine.pullAndApply(trigger: 'manual_pull');

    expect(
        await db.query('sources',
            where: 'external_id=?', whereArgs: ['unknown-key']),
        isEmpty);
    final state = await db.query('hub_sync_state',
        where: 'state_key=?', whereArgs: ['remote_site:unknown-key']);
    expect(state.single['value'], contains('future-type'));
  });

  test('a revoked device stops making later sync requests', () async {
    var pullRequests = 0;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/device/sync/pull')) {
        pullRequests++;
        return envelope(403, null, code: 40301);
      }
      return envelope(200, {'items': [], 'next_seq': 0, 'generation': 1});
    });
    final engine = HubSyncEngine(
      repository: repository,
      api: HubSyncApi(credentials: await boundCredentials(), client: client),
    );

    await expectLater(engine.sync(), throwsA(isA<HubApiException>()));
    await engine.pullAndApply(trigger: 'manual_pull');

    expect(pullRequests, 1);
    expect(await engine.staleOutboxCount, 0);
    final rows = await (await repository.hubDatabase)
        .query('hub_sync_state', where: 'state_key=?', whereArgs: ['revoked']);
    expect(rows.single['value'], 'true');
  });

  test('resync holds old outbox until the user rebuilds from local data',
      () async {
    var pullRequests = 0;
    var pushRequests = 0;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/device/sync/pull')) {
        pullRequests++;
        if (pullRequests == 1) return envelope(409, null, code: 40900);
        return envelope(200, {
          'items': [],
          'next_seq': 1,
          'generation': 2,
          'has_more': false,
        });
      }
      if (request.url.path.endsWith('/device/sync/rebuild')) {
        return envelope(200, {
          'items': [],
          'next_seq': 1,
          'generation': 2,
          'has_more': false,
        });
      }
      if (request.url.path.endsWith('/device/sync/push')) {
        pushRequests++;
        return envelope(200, {'accepted': 1});
      }
      return envelope(200, {
        'tmdb_key': null,
        'preferences': const {},
        'updated_at': 0,
      });
    });
    final engine = HubSyncEngine(
      repository: repository,
      api: HubSyncApi(credentials: await boundCredentials(), client: client),
    );

    await engine.pullAndApply(trigger: 'manual_pull');
    expect(await engine.staleOutboxCount, 0);
    await engine.pullAndApply(trigger: 'manual_pull');
    expect(pushRequests, 0);

    await engine.discardStaleOutboxAndRebuildFromLocal();
    await engine.pullAndApply(trigger: 'manual_pull');
    expect(pushRequests, 0, reason: 'pull/rebuild must not trigger a push');
    expect(await engine.staleOutboxCount, 0);
  });
}
