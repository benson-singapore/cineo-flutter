import 'dart:convert';
import 'dart:io';
import 'package:cineo_flutter/core/models/media.dart';
import 'package:cineo_flutter/data/hub/hub_sync_api.dart';
import 'package:cineo_flutter/data/hub/hub_sync_engine.dart';
import 'package:cineo_flutter/data/hub/hub_sync_keys.dart';
import 'package:cineo_flutter/data/hub/hub_sync_models.dart';
import 'package:cineo_flutter/data/repositories/local_media_repository.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  test(
      'full push uses one latest media history and per-line zero based progress',
      () async {
    final dir = await Directory.systemTemp.createTemp('hub_identity_');
    final repo = LocalMediaRepository(databasePath: '${dir.path}/db');
    addTearDown(() async {
      await repo.close();
      await dir.delete(recursive: true);
    });
    FlutterSecureStoragePlatform.instance =
        TestFlutterSecureStoragePlatform(<String, String>{});
    final credentials = HubDeviceCredentials();
    await credentials.save(
        hubUrl: 'https://hub.example.test', deviceId: 'device', token: 'token');
    final source = (await repo.sources()).single;
    final media = MediaItem(
        id: 'media',
        title: 'Series',
        description: '',
        year: 2026,
        kind: MediaKind.series,
        posterUrl: '',
        backdropUrl: '',
        genres: const [],
        rating: 0,
        duration: const Duration(minutes: 20),
        sourceId: source.id,
        sourceName: source.name,
        remoteId: '42',
        category: 'series');
    for (final entry in [('A', 1, 1), ('A', 2, 2), ('B', 1, 3)]) {
      await repo.saveProgress(
          WatchProgress(
              mediaId: media.id,
              episodeId: '${entry.$1}-${entry.$2}',
              lineName: entry.$1,
              episodeLabel: '第${entry.$2}集',
              episodeNumber: entry.$2,
              position: Duration(seconds: entry.$3),
              duration: media.duration,
              updatedAt: DateTime.utc(2026, 1, 1, 0, 0, entry.$3)),
          media: media);
    }
    final pushed = <Map<String, dynamic>>[];
    final api = HubSyncApi(
        credentials: credentials,
        client: MockClient((request) async {
          final items = (jsonDecode(request.body) as Map)['items'] as List;
          if (request.url.path.endsWith('/push')) {
            pushed.addAll(items.cast<Map<String, dynamic>>());
          }
          return http.Response(
              jsonEncode({
                'code': 200,
                'data': request.url.path.endsWith('/posters')
                    ? {'updated': 0}
                    : {'accepted': items.length, 'ignored': 0}
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }));
    final engine = HubSyncEngine(repository: repo, api: api);
    final result = await engine.pushAll();
    expect(result['failed'], 0);
    final sourceKey = hubSourceKey(source.baseUrl);
    final history = pushed.where((e) => e['entity'] == 'history').toList();
    final progress = pushed.where((e) => e['entity'] == 'progress').toList();
    expect(history, hasLength(1));
    expect(
        history.single['key'], hubMediaKey(sourceKey: sourceKey, vodId: '42'));
    expect(history.single['payload']['line_name'], 'B');
    expect(progress.map((e) => e['key']).toSet(), {
      hubMediaKey(
          sourceKey: sourceKey, vodId: '42', lineName: 'A', episodeIndex: 0),
      hubMediaKey(
          sourceKey: sourceKey, vodId: '42', lineName: 'A', episodeIndex: 1),
      hubMediaKey(
          sourceKey: sourceKey, vodId: '42', lineName: 'B', episodeIndex: 0)
    });
    expect(progress.map((e) => e['payload']['episode_index']).toSet(), {0, 1});
    pushed.clear();
    expect((await engine.pushAll())['failed'], 0);
    expect(
        pushed.where(
            (e) => e['entity'] == 'history' || e['entity'] == 'progress'),
        isEmpty);
  });
  test(
      'pull keeps trusted line and one-based number; ambiguous legacy stays legacy',
      () async {
    final dir = await Directory.systemTemp.createTemp('hub_line_pull_');
    final repo = LocalMediaRepository(databasePath: '${dir.path}/db');
    addTearDown(() async {
      await repo.close();
      await dir.delete(recursive: true);
    });
    FlutterSecureStoragePlatform.instance =
        TestFlutterSecureStoragePlatform(<String, String>{});
    final credentials = HubDeviceCredentials();
    await credentials.save(
        hubUrl: 'https://hub.example.test', deviceId: 'device', token: 'token');
    final source = (await repo.sources()).single;
    final sourceKey = hubSourceKey(source.baseUrl);
    final mediaKey = hubMediaKey(sourceKey: sourceKey, vodId: '42');
    final firstKey = hubMediaKey(
        sourceKey: sourceKey, vodId: '42', lineName: 'A', episodeIndex: 0);
    final secondKey = hubMediaKey(
        sourceKey: sourceKey, vodId: '42', lineName: 'B', episodeIndex: 1);
    final oldKey = hubMediaKey(
        sourceKey: sourceKey, vodId: '99', lineName: 'legacy', episodeIndex: 1);
    Map<String, Object?> item(String key, int stamp, {bool legacy = false}) => {
          'entity': 'progress',
          'key': key,
          'updated_at': stamp,
          'deleted': false,
          'payload': legacy
              ? {'title': 'Old', 'position_ms': 100, 'duration_ms': 1000}
              : {
                  'title': 'Series',
                  'line_name': key == firstKey ? 'A' : 'B',
                  'episode_title': key == firstKey ? '第1集' : '第2集',
                  'episode_index': key == firstKey ? 0 : 1,
                  'cineo_index_base': 0,
                  'cineo_media_kind': MediaKind.series.index,
                  'position_ms': stamp,
                  'duration_ms': 1000,
                }
        };
    var pulls = 0;
    final engine = HubSyncEngine(
        repository: repo,
        api: HubSyncApi(
            credentials: credentials,
            client: MockClient((request) async {
              final Object data;
              if (request.url.path.endsWith('/pull')) {
                pulls++;
                data = {
                  'items': pulls == 1
                      ? [
                          {
                            'entity': 'progress',
                            'key': firstKey,
                            'updated_at': 100,
                            'deleted': false,
                            'payload': {
                              'video': {'remoteId': '42', 'title': 'Series'},
                              'source_api': source.baseUrl,
                              'line_name': 'A',
                              'line_index': 0,
                              'episode_title': '第1集',
                              'episode_index': 0,
                              'position_ms': 100,
                              'duration_ms': 1000
                            }
                          },
                          {
                            ...item(firstKey, 100),
                            'entity': 'history',
                            'key': mediaKey
                          },
                          item(secondKey, 200),
                          {
                            ...item(secondKey, 200),
                            'entity': 'history',
                            'key': mediaKey
                          },
                          item(oldKey, 50, legacy: true),
                          {
                            'entity': 'progress',
                            'key': hubMediaKey(
                                sourceKey: sourceKey,
                                vodId: 'wrong',
                                lineName: 'A',
                                episodeIndex: 0),
                            'updated_at': 100,
                            'deleted': false,
                            'payload': {
                              'video': {'remoteId': 'wrong'},
                              'source_api': 'https://other.example/api',
                              'line_name': 'A',
                              'line_index': 0,
                              'episode_title': '第1集',
                              'episode_index': 0
                            }
                          },
                        ]
                      : pulls == 2
                          ? [
                              {
                                'entity': 'progress',
                                'key': secondKey,
                                'updated_at': 300,
                                'deleted': true,
                                'payload': null
                              }
                            ]
                          : [],
                  'next_seq': 3,
                  'generation': 1,
                  'has_more': false
                };
              } else {
                data = {'preferences': <String, Object>{}};
              }
              return http.Response(jsonEncode({'code': 200, 'data': data}), 200,
                  headers: {'content-type': 'application/json; charset=utf-8'});
            })));
    await engine.pullAndApply();
    final first = (await repo.watchHistory())
        .where((x) => x.mediaId == '${source.id}:42')
        .toList();
    expect(first, hasLength(2));
    expect(first.map((x) => '${x.lineName}:${x.episodeNumber}').toSet(),
        {'A:1', 'B:2'});
    expect(first.map((x) => x.episodeId).toSet(), {'hub0:A:0', 'hub0:B:1'});
    expect(
        (await repo.watchHistory())
            .where((x) => x.mediaId == '${source.id}:wrong'),
        isEmpty);
    final legacy = (await repo.watchHistory())
        .singleWhere((x) => x.mediaId == '${source.id}:99');
    expect(legacy.lineName, isNull);
    expect(legacy.episodeId, 'legacy:1');
    expect(legacy.episodeNumber, 1);
    await engine.pullAndApply();
    var remaining = (await repo.watchHistory())
        .where((x) => x.mediaId == '${source.id}:42')
        .toList();
    expect(remaining, hasLength(1));
    expect(remaining.single.episodeId, 'hub0:A:0');
    await engine.pullAndApply();
    remaining = (await repo.watchHistory())
        .where((x) => x.mediaId == '${source.id}:42')
        .toList();
    expect(remaining, hasLength(1));
    expect(remaining.single.episodeId, 'hub0:A:0');
    final db = await repo.hubDatabase;
    await engine.enqueue(
        db,
        SyncEnvelope(
            entity: 'history',
            key: mediaKey,
            updatedAt: 500,
            deleted: false,
            payload: {'title': 'new'}));
    await engine.enqueue(
        db,
        SyncEnvelope(
            entity: 'history',
            key: mediaKey,
            updatedAt: 400,
            deleted: false,
            payload: {'title': 'old'}));
    var pending = (await db.query('hub_outbox',
            where: 'entity=? AND record_key=?',
            whereArgs: ['history', mediaKey]))
        .single;
    expect(pending['updated_at'], 500);
    expect(jsonDecode(pending['payload_json'] as String)['title'], 'new');
    await engine.enqueue(
        db,
        SyncEnvelope(
            entity: 'history',
            key: mediaKey,
            updatedAt: 500,
            deleted: true,
            payload: null));
    await engine.enqueue(
        db,
        SyncEnvelope(
            entity: 'history',
            key: mediaKey,
            updatedAt: 500,
            deleted: false,
            payload: {'title': 'stale'}));
    pending = (await db.query('hub_outbox',
            where: 'entity=? AND record_key=?',
            whereArgs: ['history', mediaKey]))
        .single;
    expect(pending['deleted'], 1);
  });
  test(
      'movie tombstone removes only remote-owned row and stale replay cannot revive it',
      () async {
    final dir = await Directory.systemTemp.createTemp('hub_movie_');
    final repo = LocalMediaRepository(databasePath: '${dir.path}/db');
    addTearDown(() async {
      await repo.close();
      await dir.delete(recursive: true);
    });
    FlutterSecureStoragePlatform.instance =
        TestFlutterSecureStoragePlatform(<String, String>{});
    final credentials = HubDeviceCredentials();
    await credentials.save(
        hubUrl: 'https://hub.example.test', deviceId: 'device', token: 'token');
    final source = (await repo.sources()).single;
    final key =
        hubMediaKey(sourceKey: hubSourceKey(source.baseUrl), vodId: 'movie42');
    var pulls = 0;
    final write = {
      'entity': 'progress',
      'key': key,
      'updated_at': 1000,
      'deleted': false,
      'payload': {
        'title': 'movie',
        'cineo_media_kind': MediaKind.movie.index,
        'position_ms': 400,
        'duration_ms': 1000
      }
    };
    final deleted = {
      'entity': 'progress',
      'key': key,
      'updated_at': 2000,
      'deleted': true,
      'payload': null
    };
    final engine = HubSyncEngine(
        repository: repo,
        api: HubSyncApi(
            credentials: credentials,
            client: MockClient((request) async {
              final data = request.url.path.endsWith('/pull')
                  ? {
                      'items': [++pulls == 2 ? deleted : write],
                      'next_seq': pulls,
                      'generation': 1,
                      'has_more': false
                    }
                  : {'preferences': <String, Object>{}};
              return http.Response(jsonEncode({'code': 200, 'data': data}), 200,
                  headers: {'content-type': 'application/json; charset=utf-8'});
            })));
    await engine.pullAndApply();
    expect(await repo.watchHistory(), hasLength(1));
    await engine.pullAndApply();
    expect(await repo.watchHistory(), isEmpty);
    await engine.pullAndApply();
    expect(await repo.watchHistory(), isEmpty);
  });
}
