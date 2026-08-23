import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cineo_flutter/core/models/media.dart';
import 'package:cineo_flutter/core/models/tmdb_media.dart';
import 'package:cineo_flutter/data/cache/tmdb_disk_cache.dart';
import 'package:cineo_flutter/data/remote/tmdb_client.dart';
import 'package:cineo_flutter/data/repositories/tmdb_metadata_repository.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('cineo-tmdb-repository-');
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('uses a preview cache without waiting for image downloads', () async {
    var requestCount = 0;
    final cache = TmdbDiskCache(
      directoryProvider: () async => directory,
      imageFetcher: (_) async => <int>[1, 2, 3],
    );
    final repository = TmdbMetadataRepository(
      cache: cache,
      readToken: () async => 'test-token',
      retention: () => const Duration(days: 30),
      clientFactory: (token) => _client(token, () => requestCount++),
    );

    final first = await repository.loadPreviewForMedia(_media());
    final requestsAfterFirst = requestCount;
    final second = await repository.loadPreviewForMedia(_media());

    expect(first?.title, '测试电影');
    expect(first?.level, TmdbDetailsLevel.preview);
    expect(second?.level, TmdbDetailsLevel.preview);
    expect(requestCount, requestsAfterFirst);
  });

  test('manual override takes precedence over automatic matching', () async {
    final requestedPaths = <String>[];
    final cache = TmdbDiskCache(
      directoryProvider: () async => directory,
      imageFetcher: (_) async => <int>[1],
    );
    final repository = TmdbMetadataRepository(
      cache: cache,
      readToken: () async => 'test-token',
      retention: () => const Duration(days: 30),
      clientFactory: (token) => TmdbClient(
        bearerToken: token,
        fetcher: (uri, _) async {
          requestedPaths.add(uri.path);
          return TmdbHttpResponse(
            statusCode: 200,
            body: jsonEncode({
              'id': 77,
              'title': '手动选中电影',
              'original_title': 'Manual Film',
              'release_date': '2024-01-01',
              'overview': '手动匹配详情',
              'vote_average': 8.4,
              'runtime': 100,
            }),
          );
        },
      ),
    );
    const match = TmdbMediaMatch(
      id: 77,
      mediaType: TmdbMediaType.movie,
      title: '手动选中电影',
      originalTitle: 'Manual Film',
      overview: '',
      year: 2024,
      posterUrl: '',
      backdropUrl: '',
      rating: 8.4,
    );

    final selected = await repository.selectForMedia(_media(), match);
    await cache.clearAll();
    final loaded = await repository.loadForMedia(_media());

    expect(selected?.id, 77);
    expect(loaded?.id, 77);
    expect(
        requestedPaths.where((path) => path.endsWith('/movie/77')).length, 1);
    expect(requestedPaths.where((path) => path.contains('/search/')), isEmpty);
  });

  test('reads cached preview metadata without requesting TMDB again', () async {
    var requestCount = 0;
    final cache = TmdbDiskCache(
      directoryProvider: () async => directory,
      imageFetcher: (_) async => <int>[1, 2, 3],
    );
    final repository = TmdbMetadataRepository(
      cache: cache,
      readToken: () async => 'test-token',
      retention: () => const Duration(days: 30),
      clientFactory: (token) => _client(token, () => requestCount++),
    );

    await repository.loadPreviewForMedia(_media());
    final requestsAfterLoad = requestCount;
    final cached = await repository.loadCachedForMedia(_media());

    expect(cached?.posterUrl, 'https://image.tmdb.org/t/p/w500/poster.jpg');
    expect(requestCount, requestsAfterLoad);
  });

  test('upgrades a preview to base details and then enrichment', () async {
    var requestCount = 0;
    final cache = TmdbDiskCache(
      directoryProvider: () async => directory,
      imageFetcher: (_) async => <int>[1, 2, 3],
    );
    await cache.putDetails(
      mediaId: _media().id,
      details: const TmdbMediaDetails(
        id: 12,
        mediaType: TmdbMediaType.movie,
        title: '测试电影',
        originalTitle: 'Test Film',
        overview: '搜索结果',
        year: 2024,
        posterUrl: '',
        backdropUrl: '',
        rating: 8.2,
        runtime: null,
        level: TmdbDetailsLevel.preview,
      ),
    );
    final repository = TmdbMetadataRepository(
      cache: cache,
      readToken: () async => 'test-token',
      retention: () => const Duration(days: 30),
      clientFactory: (token) => _client(token, () => requestCount++),
    );

    final base = await repository.loadDetailsForMedia(_media());
    final enriched = await repository.loadEnrichmentForMedia(_media());

    expect(base?.level, TmdbDetailsLevel.base);
    expect(enriched?.level, TmdbDetailsLevel.enriched);
    expect(requestCount, 2);
  });

  test('upgrades legacy metadata that has no staged loading level', () async {
    var requestCount = 0;
    final cache = TmdbDiskCache(
      directoryProvider: () async => directory,
      imageFetcher: (_) async => <int>[1],
    );
    await cache.putMetadata(
      mediaId: _media().id,
      data: <String, dynamic>{
        'id': 12,
        'media_type': 'movie',
        'title': '测试电影',
        'original_title': 'Test Film',
        'overview': '旧缓存',
        'year': 2024,
        'poster_url': '',
        'backdrop_url': '',
        'rating': 8.2,
        'runtime': 120,
        'seasons': <Object>[],
        'cast': <Object>[],
      },
    );
    final repository = TmdbMetadataRepository(
      cache: cache,
      readToken: () async => 'test-token',
      retention: () => const Duration(days: 30),
      clientFactory: (token) => _client(token, () => requestCount++),
    );

    final details = await repository.loadEnrichmentForMedia(_media());

    expect(details?.level, TmdbDetailsLevel.enriched);
    expect(requestCount, 1);
    expect((await cache.getDetails(_media().id))?.level,
        TmdbDetailsLevel.enriched);
  });
}

MediaItem _media() => const MediaItem(
      id: 'cineo-media-1',
      title: '自动匹配标题',
      description: '',
      year: 2024,
      kind: MediaKind.movie,
      posterUrl: '',
      backdropUrl: '',
      genres: [],
      rating: 0,
      duration: Duration.zero,
    );

TmdbClient _client(String token, void Function() countRequest) {
  return TmdbClient(
    bearerToken: token,
    fetcher: (uri, _) async {
      countRequest();
      if (uri.path.endsWith('/search/movie')) {
        return TmdbHttpResponse(
          statusCode: 200,
          body: jsonEncode({
            'results': [
              {
                'id': 12,
                'title': '测试电影',
                'original_title': 'Test Film',
                'release_date': '2024-01-01',
                'poster_path': '/poster.jpg',
                'backdrop_path': '/backdrop.jpg',
                'vote_average': 8.2,
              },
            ],
          }),
        );
      }
      return TmdbHttpResponse(
        statusCode: 200,
        body: jsonEncode({
          'id': 12,
          'title': '测试电影',
          'original_title': 'Test Film',
          'release_date': '2024-01-01',
          'overview': '电影简介',
          'poster_path': '/poster.jpg',
          'backdrop_path': '/backdrop.jpg',
          'vote_average': 8.2,
          'runtime': 120,
        }),
      );
    },
  );
}
