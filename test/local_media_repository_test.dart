import 'dart:convert';
import 'dart:io';

import 'package:cineo_flutter/core/models/media.dart';
import 'package:cineo_flutter/core/models/media_source.dart';
import 'package:cineo_flutter/core/models/source_group_config.dart';
import 'package:cineo_flutter/core/models/home_category_rail.dart';
import 'package:cineo_flutter/data/remote/mac_cms_client.dart';
import 'package:cineo_flutter/data/repositories/local_media_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDirectory;
  late LocalMediaRepository repository;

  const media = MediaItem(
    id: 'source-a:42',
    sourceId: 'source-a',
    sourceName: '测试资源站',
    remoteId: '42',
    title: '本地保存的剧集',
    description: '用于验证本地展示快照。',
    year: 2026,
    kind: MediaKind.series,
    posterUrl: 'https://example.test/poster.jpg',
    backdropUrl: 'https://example.test/backdrop.jpg',
    genres: ['剧情', '悬疑'],
    rating: 8.6,
    duration: Duration(minutes: 45),
    category: '韩国剧',
    categoryId: '16',
  );

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('cineo_repo_test_');
    repository = LocalMediaRepository(
      databasePath: '${tempDirectory.path}/cineo.db',
    );
  });

  tearDown(() async {
    await repository.close();
    await tempDirectory.delete(recursive: true);
  });

  test('seeds 如意视频源 as the only default source for a new database', () async {
    final sources = await repository.sources();

    expect(sources, hasLength(1));
    expect(sources.single.id, 'built-in-ruyi');
    expect(sources.single.name, '如意视频源');
    expect(
        sources.single.baseUrl, 'https://cj.rycjapi.com/api.php/provide/vod');
    expect(sources.single.type, MediaSourceType.macCmsApi);
    expect(sources.single.enabled, isTrue);
    expect(sources.single.isDefault, isTrue);
    expect((await repository.defaultSource())?.id, 'built-in-ruyi');
  });

  test('does not add a built-in source to an existing source configuration',
      () async {
    await repository.deleteSource('built-in-ruyi');
    await repository.saveSource(const MediaSource(
      id: 'my-source',
      name: '我的视频源',
      type: MediaSourceType.macCmsApi,
      baseUrl: 'https://example.test/api.php/provide/vod',
      isDefault: true,
    ));
    await repository.close();

    repository = LocalMediaRepository(
      databasePath: '${tempDirectory.path}/cineo.db',
    );

    final sources = await repository.sources();
    expect(sources, hasLength(1));
    expect(sources.single.id, 'my-source');
    expect(sources.single.isDefault, isTrue);
  });

  test('persists a display snapshot when a remote item is favorited', () async {
    await repository.setFavorite(media, true);

    final favorites = await repository.favorites();
    expect(favorites, hasLength(1));
    expect(favorites.single.id, media.id);
    expect(favorites.single.title, media.title);
    expect(favorites.single.posterUrl, media.posterUrl);
    expect(favorites.single.sourceName, media.sourceName);
    expect(favorites.single.genres, media.genres);
  });

  test('restores homepage category rails after the repository is recreated',
      () async {
    const cachedMedia = MediaItem(
      id: 'source-a:home-1',
      sourceId: 'source-a',
      sourceName: '测试资源站',
      remoteId: 'home-1',
      title: '缓存首页视频',
      description: '首页快照内容',
      year: 2026,
      kind: MediaKind.movie,
      posterUrl: 'https://example.test/home-poster.jpg',
      backdropUrl: 'https://example.test/home-backdrop.jpg',
      genres: ['电影'],
      rating: 8.2,
      duration: Duration(minutes: 90),
      categoryId: 'movie-1',
    );
    await repository.saveHomeCategoryRails([
      const HomeCategoryRail(
        title: '电影',
        categoryIds: ['movie-1'],
        items: [cachedMedia],
      ),
    ]);
    await repository.close();
    repository = LocalMediaRepository(
      databasePath: '${tempDirectory.path}/cineo.db',
    );

    final rails = await repository.cachedHomeCategoryRails();
    expect(rails, hasLength(1));
    expect(rails.single.title, '电影');
    expect(rails.single.categoryIds, ['movie-1']);
    expect(rails.single.items.single.title, cachedMedia.title);
    expect(rails.single.items.single.posterUrl, cachedMedia.posterUrl);
  });

  test('persists a display snapshot when remote playback progress is saved',
      () async {
    final progress = WatchProgress(
      mediaId: media.id,
      episodeId: 'source-a:42:0:2',
      episodeLabel: '第3集',
      episodeNumber: 3,
      episodeCount: 12,
      position: const Duration(minutes: 12),
      duration: const Duration(minutes: 45),
      updatedAt: DateTime(2026, 8, 22),
    );

    await repository.saveProgress(progress, media: media);

    final restored = await repository.getById(media.id);
    expect(restored, isNotNull);
    expect(restored!.title, media.title);
    expect(restored.posterUrl, media.posterUrl);
    expect(restored.remoteId, media.remoteId);
    expect(restored.playbackOptions, isEmpty);

    final history = await repository.watchHistory();
    expect(history, hasLength(1));
    expect(history.single.episodeId, 'source-a:42:0:2');
    expect(history.single.episodeLabel, '第3集');
    expect(history.single.episodeNumber, 3);
    expect(history.single.episodeCount, 12);
  });

  test('keeps local group state when the source returns no categories',
      () async {
    await repository.saveSourceGroupConfig(
      SourceGroupConfig(
        sourceId: 'built-in-ruyi',
        categoryId: '16',
        categoryName: '电视剧',
        isEnabled: false,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
    );

    await repository.close();
    repository = LocalMediaRepository(
      databasePath: '${tempDirectory.path}/cineo.db',
      macCmsClient: MacCmsClient(fetcher: (_) async => '{}'),
    );

    final refreshed =
        await repository.refreshSourceGroupConfigs('built-in-ruyi');

    expect(refreshed, hasLength(1));
    expect(refreshed.single.categoryId, '16');
    expect(refreshed.single.isEnabled, isFalse);
    expect(
      (await repository.getSourceGroupConfigs('built-in-ruyi'))
          .single
          .isEnabled,
      isFalse,
    );
  });

  test('leaves browse and search without explicit categories unfiltered',
      () async {
    final requestedUris = <Uri>[];
    await repository.saveSourceGroupConfig(
      SourceGroupConfig(
        sourceId: 'built-in-ruyi',
        categoryId: '16',
        categoryName: '电视剧',
        isEnabled: false,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
    );
    await repository.close();
    repository = LocalMediaRepository(
      databasePath: '${tempDirectory.path}/cineo.db',
      macCmsClient: MacCmsClient(
        fetcher: (uri) async {
          requestedUris.add(uri);
          return jsonEncode({'list': []});
        },
      ),
    );

    await repository.browseDefaultSourcePage();
    await repository.searchDefaultSourcePage('关键词');

    expect(requestedUris, hasLength(2));
    expect(requestedUris[0].queryParameters['t'], isNull);
    expect(requestedUris[1].queryParameters['t'], isNull);
    expect(requestedUris[1].queryParameters['wd'], '关键词');
  });

  test('filters explicit categories and returns an empty page when disabled',
      () async {
    final requestedUris = <Uri>[];
    final createdAt = DateTime(2026, 1, 1);
    await repository.saveSourceGroupConfig(
      SourceGroupConfig(
        sourceId: 'built-in-ruyi',
        categoryId: '16',
        categoryName: '电视剧',
        isEnabled: false,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    await repository.saveSourceGroupConfig(
      SourceGroupConfig(
        sourceId: 'built-in-ruyi',
        categoryId: '17',
        categoryName: '电影',
        isEnabled: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    await repository.close();
    repository = LocalMediaRepository(
      databasePath: '${tempDirectory.path}/cineo.db',
      macCmsClient: MacCmsClient(
        fetcher: (uri) async {
          requestedUris.add(uri);
          return jsonEncode({'list': []});
        },
      ),
    );

    final enabledPage = await repository.browseDefaultSourcePage(
      categoryIds: ['16', '17'],
    );
    final disabledPage = await repository.searchDefaultSourcePage(
      '关键词',
      categoryIds: ['16'],
    );

    expect(enabledPage.items, isEmpty);
    expect(requestedUris, hasLength(1));
    expect(requestedUris.single.queryParameters['t'], '17');
    expect(disabledPage.items, isEmpty);
    expect(disabledPage.pageCount, 0);
    expect(disabledPage.limit, 0);
    expect(disabledPage.total, 0);
    expect(disabledPage.hasMore, isFalse);
  });

  test('refreshes only source-native leaves and preserves matching state',
      () async {
    final createdAt = DateTime(2026, 1, 1);
    await repository.saveSourceGroupConfig(
      SourceGroupConfig(
        sourceId: 'built-in-ruyi',
        categoryId: '21',
        categoryName: '旧名称',
        isEnabled: false,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    await repository.close();
    repository = LocalMediaRepository(
      databasePath: '${tempDirectory.path}/cineo.db',
      macCmsClient: MacCmsClient(
        fetcher: (uri) async {
          if (uri.queryParameters['ac'] == 'list') {
            return jsonEncode({
              'class': [
                {'type_id': '2', 'type_name': '电视剧'},
                {'type_id': '21', 'type_name': '国产剧', 'type_pid': '2'},
                {'type_id': '22', 'type_name': '日剧', 'type_pid': '2'},
                {'type_id': '30', 'type_name': '综艺', 'type_pid': '31'},
                {'type_id': '31', 'type_name': '节目', 'type_pid': '30'},
              ],
            });
          }
          return jsonEncode({'list': []});
        },
      ),
    );

    final refreshed =
        await repository.refreshSourceGroupConfigs('built-in-ruyi');

    expect(
        refreshed.map((config) => config.categoryId), ['21', '22', '30', '31']);
    expect(
        refreshed.firstWhere((config) => config.categoryId == '21').isEnabled,
        isFalse);
    expect(refreshed.any((config) => config.categoryId == '2'), isFalse);
  });

  test('can hide playback history from adult sources', () async {
    await repository.saveSource(const MediaSource(
      id: 'adult-source',
      name: '成人测试源',
      type: MediaSourceType.macCmsApi,
      baseUrl: 'https://adult.example.test/api.php/provide/vod',
      isAdult: true,
    ));
    const adultMedia = MediaItem(
      id: 'adult-source:7',
      sourceId: 'adult-source',
      sourceName: '成人测试源',
      remoteId: '7',
      title: '成人测试内容',
      description: '',
      year: 2026,
      kind: MediaKind.movie,
      posterUrl: 'https://example.test/adult-poster.jpg',
      backdropUrl: 'https://example.test/adult-backdrop.jpg',
      genres: [],
      rating: 0,
      duration: Duration(minutes: 90),
    );
    await repository.saveProgress(
      WatchProgress(
        mediaId: adultMedia.id,
        position: const Duration(minutes: 2),
        duration: adultMedia.duration,
        updatedAt: DateTime(2026, 8, 22),
      ),
      media: adultMedia,
    );

    expect(await repository.watchHistory(includeAdult: false), isEmpty);
    expect(await repository.watchHistory(includeAdult: true), hasLength(1));
  });
}
