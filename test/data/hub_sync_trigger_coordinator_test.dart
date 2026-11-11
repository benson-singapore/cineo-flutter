import 'dart:async';
import 'dart:convert';
import 'dart:io';

// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
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
import 'package:cineo_flutter/data/hub/hub_sync_trigger_coordinator.dart';
import 'package:cineo_flutter/data/repositories/local_media_repository.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDirectory;
  late LocalMediaRepository repository;
  late List<http.Request> requests;
  late List<Future<void>> pending;
  late HubSyncEngine engine;
  late MediaItem media;
  late WatchProgress progress;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('hub_triggers_');
    repository =
        LocalMediaRepository(databasePath: '${tempDirectory.path}/cineo.db');
    FlutterSecureStoragePlatform.instance =
        TestFlutterSecureStoragePlatform(<String, String>{});
    final credentials = HubDeviceCredentials();
    await credentials.save(
      hubUrl: 'https://hub.example.test',
      deviceId: 'device-1',
      token: 'device-token',
    );
    requests = [];
    pending = [];
    engine = HubSyncEngine(
      repository: repository,
      api: HubSyncApi(
        credentials: credentials,
        client: MockClient((request) async {
          requests.add(request);
          final data = request.url.path.endsWith('/push')
              ? {'accepted': 1, 'ignored': 0}
              : {
                  'items': [],
                  'next_seq': 0,
                  'generation': 1,
                  'has_more': false
                };
          return http.Response(
              jsonEncode({'code': 200, 'message': 'ok', 'data': data}), 200,
              headers: const {'content-type': 'application/json'});
        }),
      ),
    );
    final source = (await repository.sources()).single;
    media = MediaItem(
      id: 'trigger-media',
      title: 'Trigger media',
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
      remoteId: 'remote-trigger-media',
      category: '电影',
    );
    progress = WatchProgress(
      mediaId: media.id,
      position: const Duration(seconds: 12),
      duration: media.duration,
      updatedAt: DateTime.utc(2026),
    );
    await repository.saveProgress(progress, media: media);
  });

  tearDown(() async {
    await repository.close();
    await tempDirectory.delete(recursive: true);
  });

  HubSyncTriggerCoordinator createCoordinator(DateTime Function() now) =>
      HubSyncTriggerCoordinator(
        pushFavorite: (item, favorite) {
          final future = engine.queueFavorite(item, favorite);
          pending.add(future);
          return future;
        },
        pushProgress: (item, value) {
          final future = engine.pushProgress(item, value);
          pending.add(future);
          return future;
        },
        pushOutbox: () {
          final future = engine.pushOutbox(trigger: 'auto_progress');
          pending.add(future);
          return future;
        },
        intervalSeconds: () => 5,
        now: now,
        dispatch: (operation) => Zone.root.run<Future<void>>(operation),
        checkEvery: const Duration(seconds: 1),
      );

  test('favorite debounce sends only last state after two seconds', () async {
    late HubSyncTriggerCoordinator triggers;
    fakeAsync((async) {
      triggers = createCoordinator(() =>
          DateTime.fromMillisecondsSinceEpoch(async.elapsed.inMilliseconds));
      triggers.favoriteChanged(media, true);
      async.elapse(const Duration(seconds: 1));
      triggers.favoriteChanged(media, false);
      async.elapse(const Duration(seconds: 2));
    });
    await Future.wait(pending);
    expect(requests, hasLength(1));
    expect(requests.single.url.path, '/api/v1/device/sync/push');
    expect(requests.single.headers['x-sync-trigger'], 'auto_favorite');
    expect((jsonDecode(requests.single.body) as Map)['items'].single['deleted'],
        isTrue);
    triggers.dispose();
  });

  test('resume does not pull while background only pushes outbox', () async {
    final db = await repository.hubDatabase;
    await db.insert('hub_outbox', {
      'entity': 'favorite',
      'record_key': 'background',
      'updated_at': 1,
      'deleted': 0,
      'payload_json': '{"title":"background"}',
      'attempts': 0,
      'next_attempt_at': 0,
    });
    late HubSyncTriggerCoordinator triggers;
    fakeAsync((async) {
      triggers = createCoordinator(() =>
          DateTime.fromMillisecondsSinceEpoch(async.elapsed.inMilliseconds));
      triggers.onLifecycleResumed();
      async.flushMicrotasks();
      triggers.onLifecycleBackgrounded();
    });
    await Future.wait(pending);
    expect(requests, hasLength(1));
    expect(requests.single.url.path, '/api/v1/device/sync/push');
    expect(requests.single.headers['x-sync-trigger'], 'auto_progress');
    triggers.dispose();
  });

  test('periodic progress push requires elapsed interval and changed position',
      () async {
    late HubSyncTriggerCoordinator triggers;
    fakeAsync((async) {
      triggers = createCoordinator(() =>
          DateTime.fromMillisecondsSinceEpoch(async.elapsed.inMilliseconds));
      triggers.trackProgress(media, progress);
      async.elapse(const Duration(seconds: 5));
      triggers.trackProgress(
          media, progress.copyWith(position: const Duration(seconds: 12)));
      async.elapse(const Duration(seconds: 5));
      triggers.trackProgress(
          media, progress.copyWith(position: const Duration(seconds: 18)));
      async.elapse(const Duration(seconds: 5));
    });
    await Future.wait(pending);
    expect(requests, hasLength(2));
    expect(
        requests
            .every((request) => request.url.path == '/api/v1/device/sync/push'),
        isTrue);
    expect(
        requests.every(
            (request) => request.headers['x-sync-trigger'] == 'auto_progress'),
        isTrue);
    triggers.dispose();
  });

  test('periodic progress follows the current item after switching back',
      () async {
    final source = (await repository.sources()).single;
    final mediaB = MediaItem(
      id: 'trigger-media-b',
      title: 'Trigger media B',
      description: '',
      year: 2026,
      kind: MediaKind.series,
      posterUrl: '',
      backdropUrl: '',
      genres: const [],
      rating: 0,
      duration: const Duration(minutes: 30),
      sourceId: source.id,
      sourceName: source.name,
      remoteId: 'remote-trigger-media-b',
      category: '剧集',
    );
    final progressA1 = progress.copyWith(
      episodeId: 'episode-1',
      episodeLabel: 'Episode A1',
      episodeNumber: 1,
      position: const Duration(seconds: 10),
    );
    final progressB = WatchProgress(
      mediaId: mediaB.id,
      episodeId: 'episode-2',
      episodeLabel: 'Episode B',
      episodeNumber: 2,
      position: const Duration(seconds: 20),
      duration: mediaB.duration,
      updatedAt: DateTime.utc(2026),
    );
    final progressA2 = progressA1.copyWith(
      position: const Duration(seconds: 35),
    );
    late HubSyncTriggerCoordinator triggers;
    fakeAsync((async) {
      triggers = createCoordinator(() =>
          DateTime.fromMillisecondsSinceEpoch(async.elapsed.inMilliseconds));
      triggers.trackProgress(media, progressA1);
      triggers.trackProgress(mediaB, progressB);
      triggers.trackProgress(media, progressA2);
      async.elapse(const Duration(seconds: 5));
    });
    await Future.wait(pending);
    expect(requests, hasLength(1));
    expect(requests.single.url.path, '/api/v1/device/sync/push');
    expect(requests.single.headers['x-sync-trigger'], 'auto_progress');
    final item = (jsonDecode(requests.single.body) as Map)['items'].single;
    expect(item['payload']['line_name'], 'Episode A1');
    expect(item['payload']['position_ms'], 35000);
    triggers.dispose();
  });

  test(
      'pause or exit flush pushes once and next interval does not duplicate it',
      () async {
    late HubSyncTriggerCoordinator triggers;
    fakeAsync((async) {
      triggers = createCoordinator(() =>
          DateTime.fromMillisecondsSinceEpoch(async.elapsed.inMilliseconds));
      triggers.trackProgress(media, progress);
      unawaited(triggers.flushProgress(media, progress));
      async.elapse(const Duration(seconds: 5));
    });
    await Future.wait(pending);
    expect(requests, hasLength(1));
    expect(requests.single.url.path, '/api/v1/device/sync/push');
    expect(requests.single.headers['x-sync-trigger'], 'auto_progress');
    triggers.dispose();
  });
}
