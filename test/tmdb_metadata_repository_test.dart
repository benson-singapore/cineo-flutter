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
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('uses fresh metadata cache and local cached image URIs', () async {
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

    final first = await repository.loadForMedia(_media());
    final requestsAfterFirst = requestCount;
    final second = await repository.loadForMedia(_media());

    expect(first?.title, '测试电影');
    expect(first?.posterUrl, startsWith('file:'));
    expect(first?.backdropUrl, startsWith('file:'));
    expect(second?.posterUrl, startsWith('file:'));
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
        requestedPaths.where((path) => path.endsWith('/movie/77')).length, 2);
    expect(requestedPaths.where((path) => path.contains('/search/')), isEmpty);
  });

  test('reads cached metadata without requesting TMDB again', () async {
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

    await repository.loadForMedia(_media());
    final requestsAfterLoad = requestCount;
    final cached = await repository.loadCachedForMedia(_media());

    expect(cached?.posterUrl, startsWith('file:'));
    expect(requestCount, requestsAfterLoad);
  });

  test('refreshes cached details that have no poster when opening media',
      () async {
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
        overview: '旧详情',
        year: 2024,
        posterUrl: '',
        backdropUrl: '',
        rating: 8.2,
        runtime: 120,
      ),
    );
    final repository = TmdbMetadataRepository(
      cache: cache,
      readToken: () async => 'test-token',
      retention: () => const Duration(days: 30),
      clientFactory: (token) => _client(token, () => requestCount++),
    );

    final refreshed = await repository.loadForMedia(_media());

    expect(refreshed?.posterUrl, startsWith('file:'));
    expect(requestCount, 1);
    expect((await cache.getDetails(_media().id))?.posterUrl, isNotEmpty);
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
