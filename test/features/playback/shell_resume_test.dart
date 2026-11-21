import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:cineo_flutter/main.dart';
import 'package:cineo_flutter/core/models/media.dart';
import 'package:cineo_flutter/core/models/paged_media.dart';
import 'package:cineo_flutter/core/models/home_category_rail.dart';
import 'package:cineo_flutter/data/cache/tmdb_disk_cache.dart';
import 'package:cineo_flutter/data/download/download_service.dart';
import 'package:cineo_flutter/data/download/sqlite_download_task_store.dart';
import 'package:cineo_flutter/data/hub/hub_sync_api.dart';
import 'package:cineo_flutter/data/hub/hub_sync_engine.dart';
import 'package:cineo_flutter/data/hub/hub_sync_keys.dart';
import 'package:cineo_flutter/data/hub/hub_sync_trigger_coordinator.dart';
import 'package:cineo_flutter/data/remote/media_category_adapter.dart';
import 'package:cineo_flutter/data/repositories/local_media_repository.dart';
import 'package:cineo_flutter/data/repositories/tmdb_metadata_repository.dart';
import 'package:cineo_flutter/features/app_lock/app_lock.dart';
import 'package:cineo_flutter/features/home/home_screen.dart';
import 'package:cineo_flutter/features/settings/adult_source_settings.dart';
import 'package:cineo_flutter/features/settings/m3u8_filter_settings.dart';
import 'package:cineo_flutter/features/settings/tmdb_settings.dart';
import 'package:cineo_flutter/features/settings/tmdb_disk_cache_controller.dart';
import 'package:cineo_flutter/features/update/app_update_service.dart';
import 'package:cineo_flutter/shared/widgets/media_poster_card.dart';

class _Repo extends LocalMediaRepository {
  _Repo(String path) : super(databasePath: path);
  late MediaItem detail;
  @override
  Future<PagedMedia> browseDefaultSourcePage(
          {List<String> categoryIds = const [], int page = 1}) async =>
      PagedMedia(
          items: const [],
          page: page,
          pageCount: 0,
          total: 0,
          limit: 20,
          hasMore: false);
  @override
  Future<MediaItem?> loadDetails(MediaItem item) async => detail;
  @override
  Future<MediaItem?> preferredSourceFor(MediaItem media,
          {required bool includeAdult}) async =>
      null;
  @override
  Future<List<UnifiedCategory>> defaultSourceCategories() async => [];
  @override
  Future<List<HomeCategoryRail>> browseDefaultHomeCategoryRails(
          List<UnifiedCategory> categories) async =>
      [];
}

class _Video extends VideoPlayerPlatform {
  final seeks = <Duration>[];
  final urls = <String?>[];
  final streams = <int, StreamController<VideoEvent>>{};
  @override
  Future<void> init() async {}
  @override
  Future<int?> create(DataSource dataSource) async {
    urls.add(dataSource.uri);
    final stream = StreamController<VideoEvent>();
    streams[0] = stream;
    stream.add(VideoEvent(
        eventType: VideoEventType.initialized,
        duration: const Duration(minutes: 20),
        size: const Size(1920, 1080)));
    return 0;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int id) => streams[id]!.stream;
  @override
  Future<void> seekTo(int id, Duration position) async {
    seeks.add(position);
  }

  @override
  Future<Duration> getPosition(int id) async => Duration.zero;
  @override
  Future<void> setLooping(int id, bool value) async {}
  @override
  Future<void> setVolume(int id, double value) async {}
  @override
  Future<void> setPlaybackSpeed(int id, double value) async {}
  @override
  Future<void> setMixWithOthers(bool value) async {}
  @override
  Future<void> play(int id) async {}
  @override
  Future<void> pause(int id) async {}
  @override
  Future<void> dispose(int id) async {
    await streams.remove(id)?.close();
  }

  @override
  Widget buildView(int id) => const SizedBox();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  for (final scenario in [
    'hub_first',
    'hub_second',
    'legacy_first',
    'ambiguous',
    'cross_source'
  ]) {
    testWidgets('home to player: $scenario', (tester) async {
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        FlutterSecureStoragePlatform.instance =
            TestFlutterSecureStoragePlatform(<String, String>{});
        final platform = _Video();
        VideoPlayerPlatform.instance = platform;
        final dir =
            await Directory.systemTemp.createTemp('cineo_shell_resume_');
        final repo = _Repo('${dir.path}/db');
        final credentials = HubDeviceCredentials();
        await credentials.save(
            hubUrl: 'https://hub.example.test',
            deviceId: 'device',
            token: 'token');
        final source = await repo.sources().then((s) => s.single);
        final old = MediaItem(
            id: 'hub:old:42',
            sourceId: source.id,
            remoteId: '42',
            title: '续播测试',
            description: '',
            year: 2026,
            kind: MediaKind.series,
            posterUrl: '',
            backdropUrl: '',
            genres: const [],
            rating: 0,
            duration: const Duration(minutes: 20));
        final a = PlaybackOption(
            id: '${source.id}:42:0:0',
            sourceId: source.id,
            label: 'A · 第1集',
            quality: 'A',
            url: 'https://example.test/a.mp4');
        final b = PlaybackOption(
            id: '${source.id}:42:1:0',
            sourceId: source.id,
            label: 'B · 第1集',
            quality: 'B',
            url: 'https://example.test/b.mp4');
        final detailSource =
            scenario == 'cross_source' ? 'other-source' : source.id;
        final a2 = PlaybackOption(
            id: '${source.id}:42:0:1',
            sourceId: source.id,
            label: 'A · 第2集',
            quality: 'A',
            url: 'https://example.test/a2.mp4');
        final duplicate = PlaybackOption(
            id: '${source.id}:42:2:0',
            sourceId: source.id,
            label: 'B · 第1集',
            quality: 'B',
            url: 'https://example.test/duplicate.mp4');
        repo.detail = MediaItem(
            id: '$detailSource:42',
            sourceId: detailSource,
            remoteId: '42',
            title: old.title,
            description: '',
            year: 2026,
            kind: MediaKind.series,
            posterUrl: '',
            backdropUrl: '',
            genres: const [],
            rating: 0,
            duration: old.duration,
            playbackOptions: [a, a2, b, if (scenario == 'ambiguous') duplicate],
            episodes: [
              Episode(
                  id: a.id,
                  title: '第1集',
                  season: 1,
                  number: 1,
                  playbackOption: a),
              Episode(
                  id: a2.id,
                  title: '第2集',
                  season: 1,
                  number: 2,
                  playbackOption: a2),
              Episode(
                  id: b.id,
                  title: '第1集',
                  season: 1,
                  number: 1,
                  playbackOption: b)
            ]);
        await repo.saveProgress(
            WatchProgress(
                mediaId: old.id,
                episodeId: 'seed',
                position: Duration.zero,
                duration: old.duration,
                updatedAt: DateTime(2020)),
            media: old);
        await (await repo.hubDatabase).delete('progress');
        final key = hubMediaKey(
            sourceKey: hubSourceKey(source.baseUrl),
            vodId: '42',
            lineName: scenario == 'hub_second' ? 'A' : 'B',
            episodeIndex: scenario == 'hub_second' ? 1 : 0);
        var firstPull = true;
        final api = HubSyncApi(
            credentials: credentials,
            client: MockClient((request) async {
              final data = request.url.path.endsWith('/pull')
                  ? <String, Object>{
                      'items': firstPull
                          ? [
                              {
                                'entity': 'progress',
                                'key': key,
                                'updated_at': 2000000,
                                'deleted': false,
                                'payload': {
                                  'title': old.title,
                                  'line_name':
                                      scenario == 'hub_second' ? 'A' : 'B',
                                  'episode_title':
                                      scenario == 'hub_second' ? '第2集' : '第1集',
                                  'episode_index':
                                      scenario == 'hub_second' ? 1 : 0,
                                  'cineo_index_base': 0,
                                  'cineo_media_kind': 1,
                                  'position_ms': 360000,
                                  'duration_ms': 1200000
                                }
                              }
                            ]
                          : [],
                      'next_seq': 1,
                      'generation': 1,
                      'has_more': false
                    }
                  : <String, Object>{'preferences': <String, Object>{}};
              firstPull = false;
              return http.Response(jsonEncode({'code': 200, 'data': data}), 200,
                  headers: {'content-type': 'application/json; charset=utf-8'});
            }));
        final engine = HubSyncEngine(repository: repo, api: api);
        await engine.pullAndApply();
        if (scenario == 'legacy_first') {
          await (await repo.hubDatabase).delete('progress');
          await repo.saveProgress(WatchProgress(
              mediaId: old.id,
              episodeId: 'B:0',
              episodeLabel: 'B',
              episodeNumber: 0,
              position: const Duration(minutes: 6),
              duration: old.duration,
              updatedAt: DateTime(2026)));
        } else {
          expect((await repo.watchHistory()).single.episodeId,
              scenario == 'hub_second' ? 'hub0:A:1' : 'hub0:B:0');
        }
        expect((await repo.watchHistory()).single.mediaId, old.id);
        final cache = TmdbDiskCache(directoryProvider: () async => dir);
        final tmdb = TMDBSettings();
        final controller = TmdbDiskCacheController(cache: cache);
        final metadata = TmdbMetadataRepository(
            cache: cache,
            readToken: () async => null,
            retention: () => const Duration(days: 30));
        final downloads =
            DownloadService(taskStore: SqliteDownloadTaskStore(repo));
        final triggers = HubSyncTriggerCoordinator(
            pushFavorite: (_, __) async {},
            pushProgress: (_, __) async {},
            intervalSeconds: () => 10);
        await tester.binding.setSurfaceSize(const Size(800, 1400));
        await tester.pumpWidget(MaterialApp(
            home: CineoShell(
                repository: repo,
                appLockController: AppLockController(),
                adultSourceSettings: AdultSourceSettings(),
                m3u8FilterSettings: M3u8FilterSettings(),
                tmdbSettings: tmdb,
                tmdbMetadata: metadata,
                tmdbCacheController: controller,
                updateService: AppUpdateService(),
                downloadService: downloads,
                hubSyncEngine: engine,
                hubSyncTriggers: triggers)));
        for (var i = 0; i < 30; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          await tester.pump(const Duration(milliseconds: 50));
          if (find.byType(MediaPosterCard).evaluate().isNotEmpty) break;
        }
        expect(find.byType(HomeScreen), findsOneWidget);
        await tester.drag(find.byType(HomeScreen), const Offset(0, -700));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.ensureVisible(find.byType(MediaPosterCard).first);
        await tester.tap(find.byType(MediaPosterCard).first);
        for (var i = 0; i < 30; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          await tester.pump(const Duration(milliseconds: 50));
          if (find
              .byKey(const ValueKey('primary-play-button'))
              .evaluate()
              .isNotEmpty) break;
        }
        final shouldResume =
            scenario != 'ambiguous' && scenario != 'cross_source';
        expect(find.text('继续播放'), shouldResume ? findsOneWidget : findsNothing);
        await tester.tap(find.byKey(const ValueKey('primary-play-button')));
        for (var i = 0; i < 30; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          await tester.pump(const Duration(milliseconds: 50));
          if (platform.urls.isNotEmpty &&
              (!shouldResume || platform.seeks.isNotEmpty)) break;
        }
        for (var i = 0; i < 10; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(platform.urls, isNotEmpty);
        if (shouldResume) {
          expect(
              platform.urls.single,
              scenario == 'hub_second'
                  ? 'https://example.test/a2.mp4'
                  : 'https://example.test/b.mp4');
          expect(platform.seeks, contains(const Duration(minutes: 6)));
        } else {
          expect(platform.seeks, isEmpty);
        }
        await tester.pumpWidget(const SizedBox());
        triggers.dispose();
        await downloads.dispose();
        await repo.close();
        await dir.delete(recursive: true);
        await tester.binding.setSurfaceSize(null);
      });
    });
  }
}
