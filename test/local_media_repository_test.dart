import 'dart:convert';
import 'dart:io';

import 'package:cineo_flutter/core/models/media.dart';
import 'package:cineo_flutter/core/models/media_source.dart';
import 'package:cineo_flutter/core/models/home_category_rail.dart';
import 'package:cineo_flutter/core/models/source_group_config.dart';
import 'package:cineo_flutter/data/remote/mac_cms_client.dart';
import 'package:cineo_flutter/data/remote/media_category_adapter.dart';
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

  test('keeps successful home rails when another category request fails',
      () async {
    repository = LocalMediaRepository(
      databasePath: '${tempDirectory.path}/cineo.db',
      macCmsClient: MacCmsClient(
        maxAttempts: 1,
        fetcher: (uri) async {
          switch (uri.queryParameters['t']) {
            case 'cn':
              throw const HttpException('站点返回 HTTP 500');
            case 'kr':
              return jsonEncode({
                'list': [
                  {
                    'vod_id': '18',
                    'vod_name': '成功加载的韩剧',
                    'type_id': 'kr',
                    'type_name': '韩剧',
                  },
                ],
              });
            default:
              return '{"list":[]}';
          }
        },
      ),
    );
    const categories = [
      UnifiedCategory(
        type: UnifiedMediaType.series,
        sourceCategoryIds: ['cn', 'kr'],
        subcategories: [
          UnifiedSubcategory(
            id: 'cn',
            name: '国产剧',
            sourceCategoryIds: ['cn'],
            matchText: '电视剧 国产剧',
          ),
          UnifiedSubcategory(
            id: 'kr',
            name: '韩剧',
            sourceCategoryIds: ['kr'],
            matchText: '电视剧 韩剧',
          ),
        ],
      ),
    ];

    final rails = await repository.browseDefaultHomeCategoryRails(categories);

    final domestic = rails.singleWhere((rail) => rail.title == '国产剧');
    final korean = rails.singleWhere((rail) => rail.title == '韩剧');
    expect(domestic.categoryIds, ['cn']);
    expect(domestic.items, isEmpty);
    expect(korean.categoryIds, ['kr']);
    expect(korean.items.single.title, '成功加载的韩剧');
  });

  test('syncs source leaf groups without resetting saved visibility', () async {
    var includeVariety = false;
    repository = LocalMediaRepository(
      databasePath: '${tempDirectory.path}/cineo.db',
      macCmsClient: MacCmsClient(
        maxAttempts: 1,
        fetcher: (uri) async {
          if (uri.queryParameters['ac'] != 'list') return '{"list":[]}';
          final categories = <Map<String, String>>[
            {'type_id': '1', 'type_name': '连续剧', 'type_pid': '0'},
            {'type_id': '13', 'type_name': '国产剧', 'type_pid': '1'},
            {'type_id': '15', 'type_name': '韩剧', 'type_pid': '1'},
          ];
          if (includeVariety) {
            categories.addAll([
              {'type_id': '3', 'type_name': '综艺片', 'type_pid': '0'},
              {'type_id': '25', 'type_name': '大陆综艺', 'type_pid': '3'},
            ]);
          }
          return jsonEncode({'class': categories});
        },
      ),
    );

    final initial = await repository.syncSourceGroupConfigs('built-in-ruyi');
    expect(initial.map((config) => config.categoryName), ['国产剧', '韩剧']);

    await repository.toggleSourceGroupConfig('built-in-ruyi', '15', false);
    includeVariety = true;

    final refreshed = await repository.syncSourceGroupConfigs('built-in-ruyi');
    expect(
      refreshed.map((config) => config.categoryName).toSet(),
      {'大陆综艺', '国产剧', '韩剧'},
    );
    expect(
      refreshed.singleWhere((config) => config.categoryId == '15').isEnabled,
      isFalse,
    );
    expect(
      refreshed.singleWhere((config) => config.categoryId == '25').isEnabled,
      isTrue,
    );
  });

  test('syncs 360-style numeric category fields', () async {
    repository = LocalMediaRepository(
      databasePath: '${tempDirectory.path}/cineo.db',
      macCmsClient: MacCmsClient(
        maxAttempts: 1,
        fetcher: (uri) async => jsonEncode({
          'class': [
            {'type_id': 1, 'type_name': '电影', 'type_pid': 0},
            {'type_id': 2, 'type_name': '动作片', 'type_pid': 1},
            {'type_id': 13, 'type_name': '连续剧', 'type_pid': 0},
            {'type_id': 14, 'type_name': '国产剧', 'type_pid': 13},
            {'type_id': 15, 'type_name': '香港剧', 'type_pid': 13},
            {'type_id': 16, 'type_name': '韩国剧', 'type_pid': 13},
            {'type_id': 17, 'type_name': '欧美剧', 'type_pid': 13},
          ],
        }),
      ),
    );

    final configs = await repository.syncSourceGroupConfigs('built-in-ruyi');

    expect(
      configs.map((config) => config.categoryName),
      containsAll(['动作片', '国产剧', '香港剧', '韩国剧', '欧美剧']),
    );
    expect(
        configs,
        everyElement(predicate<SourceGroupConfig>(
          (config) => config.isEnabled,
        )));
  });

  test(
      'returns an empty configuration for categories without recognized leaves',
      () async {
    repository = LocalMediaRepository(
      databasePath: '${tempDirectory.path}/cineo.db',
      macCmsClient: MacCmsClient(
        maxAttempts: 1,
        fetcher: (uri) async => jsonEncode({
          'class': [
            {'type_id': 7, 'type_name': '体育', 'type_pid': 0},
          ],
        }),
      ),
    );

    final configs = await repository.syncSourceGroupConfigs('built-in-ruyi');

    expect(configs, isEmpty);
  });

  test('reads legacy group rows with numeric values stored as strings',
      () async {
    await repository.sources();
    await repository.close();

    final database = await databaseFactory.openDatabase(
      '${tempDirectory.path}/cineo.db',
      options: OpenDatabaseOptions(version: 9),
    );
    await database.insert('source_group_configs', {
      'source_id': 'built-in-ruyi',
      'category_id': '99',
      'category_name': '历史分类',
      'is_enabled': '1',
      'created_at': '1700000000000',
      'updated_at': '1700000001000',
    });
    await database.close();

    repository = LocalMediaRepository(
      databasePath: '${tempDirectory.path}/cineo.db',
    );
    final configs = await repository.getSourceGroupConfigs('built-in-ruyi');
    final legacy = configs.singleWhere((config) => config.categoryId == '99');

    expect(legacy.categoryName, '历史分类');
    expect(legacy.isEnabled, isTrue);
    expect(
      legacy.createdAt,
      DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );
  });

  test('repairs an existing group table with legacy column names', () async {
    await repository.sources();
    await repository.close();

    final database = await databaseFactory.openDatabase(
      '${tempDirectory.path}/cineo.db',
      options: OpenDatabaseOptions(version: 9),
    );
    await database.execute('DROP TABLE source_group_configs');
    await database.execute('''
      CREATE TABLE source_group_configs (
        sourceId TEXT NOT NULL,
        categoryId TEXT NOT NULL,
        categoryName TEXT NOT NULL,
        isEnabled TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');
    await database.insert('source_group_configs', {
      'sourceId': 'built-in-ruyi',
      'categoryId': '14',
      'categoryName': '国产剧',
      'isEnabled': '0',
      'createdAt': '1700000000000',
      'updatedAt': '1700000001000',
    });
    await database.close();

    repository = LocalMediaRepository(
      databasePath: '${tempDirectory.path}/cineo.db',
      macCmsClient: MacCmsClient(
        maxAttempts: 1,
        fetcher: (uri) async => jsonEncode({
          'class': [
            {'type_id': 1, 'type_name': '连续剧', 'type_pid': 0},
            {'type_id': 14, 'type_name': '国产剧', 'type_pid': 1},
          ],
        }),
      ),
    );

    final configs = await repository.syncSourceGroupConfigs('built-in-ruyi');
    final domestic = configs.singleWhere((config) => config.categoryId == '14');

    expect(domestic.categoryName, '国产剧');
    expect(domestic.isEnabled, isFalse);
  });

  test('filters categories and unqualified searches by enabled groups',
      () async {
    final requestedSearchCategories = <String?>[];
    repository = LocalMediaRepository(
      databasePath: '${tempDirectory.path}/cineo.db',
      macCmsClient: MacCmsClient(
        maxAttempts: 1,
        fetcher: (uri) async {
          if (uri.queryParameters['ac'] == 'list') {
            return jsonEncode({
              'class': [
                {'type_id': '1', 'type_name': '连续剧', 'type_pid': '0'},
                {'type_id': '13', 'type_name': '国产剧', 'type_pid': '1'},
                {'type_id': '15', 'type_name': '韩剧', 'type_pid': '1'},
              ],
            });
          }
          requestedSearchCategories.add(uri.queryParameters['t']);
          return jsonEncode({
            'list': [
              {
                'vod_id': uri.queryParameters['t'] ?? 'unfiltered',
                'vod_name':
                    uri.queryParameters['t'] == '13' ? '国产剧搜索结果' : '未分类搜索结果',
                'type_id': uri.queryParameters['t'] ?? '',
              },
            ],
          });
        },
      ),
    );

    await repository.syncSourceGroupConfigs('built-in-ruyi');
    await repository.toggleSourceGroupConfig('built-in-ruyi', '15', false);

    final categories = await repository.defaultSourceCategories();
    final series = categories.singleWhere(
      (category) => category.type == UnifiedMediaType.series,
    );
    expect(series.sourceCategoryIds, ['13']);
    expect(series.subcategories.map((category) => category.id), ['13']);

    final results = await repository.searchDefaultSourcePage('剧');
    expect(results.items.single.categoryId, '13');
    expect(requestedSearchCategories, ['13']);

    await repository.toggleSourceGroupConfig('built-in-ruyi', '13', false);
    requestedSearchCategories.clear();
    final empty = await repository.searchDefaultSourcePage('剧');
    expect(empty.items, isEmpty);
    expect(requestedSearchCategories, isEmpty);
  });

  test('repairs a missing group table in a version 9 database', () async {
    await repository.sources();
    await repository.close();

    final database = await databaseFactory.openDatabase(
      '${tempDirectory.path}/cineo.db',
      options: OpenDatabaseOptions(version: 9),
    );
    await database.execute('DROP TABLE source_group_configs');
    final version = await database.rawQuery('PRAGMA user_version');
    expect(version.single['user_version'], 9);
    await database.close();

    repository = LocalMediaRepository(
      databasePath: '${tempDirectory.path}/cineo.db',
      macCmsClient: MacCmsClient(
        maxAttempts: 1,
        fetcher: (uri) async => jsonEncode({
          'class': [
            {'type_id': '1', 'type_name': '连续剧', 'type_pid': '0'},
            {'type_id': '13', 'type_name': '国产剧', 'type_pid': '1'},
          ],
        }),
      ),
    );

    final configs = await repository.syncSourceGroupConfigs('built-in-ruyi');
    expect(configs.map((config) => config.categoryName), ['国产剧']);
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
