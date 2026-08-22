import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cineo_flutter/core/models/tmdb_media.dart';
import 'package:cineo_flutter/data/cache/tmdb_disk_cache.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory =
        await Directory.systemTemp.createTemp('cineo-tmdb-cache-');
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  TmdbDiskCache createCache(
      {DateTime Function()? clock, TmdbImageFetcher? fetcher}) {
    return TmdbDiskCache(
      directoryProvider: () async => temporaryDirectory,
      clock: clock,
      imageFetcher: fetcher,
    );
  }

  test('stores metadata with the default thirty day TTL', () async {
    final now = DateTime.utc(2026, 8, 22);
    final cache = createCache(clock: () => now);

    await cache.putMetadata(
      mediaId: 'media-1',
      data: <String, dynamic>{'title': '测试剧', 'overview': '简介'},
    );

    expect(await cache.getMetadata('media-1'), <String, dynamic>{
      'title': '测试剧',
      'overview': '简介',
    });
    final metadataFile = await _findFile(temporaryDirectory, '.json');
    final raw = await metadataFile.readAsString();
    expect(raw, contains('2026-09-21'));
  });

  test('expires metadata and supports a configurable TTL', () async {
    var now = DateTime.utc(2026, 8, 22);
    final cache = createCache(clock: () => now);
    await cache.putMetadata(
      mediaId: 'short-lived',
      data: <String, dynamic>{'title': '短缓存'},
      ttl: const Duration(hours: 1),
    );

    now = now.add(const Duration(hours: 1, minutes: 1));
    expect(await cache.getMetadata('short-lived'), isNull);
    expect(
      await cache.getMetadata('short-lived', allowExpired: true),
      <String, dynamic>{'title': '短缓存'},
    );
  });

  test('caches images through an injected fetcher and reuses fresh bytes',
      () async {
    var fetchCount = 0;
    final cache = createCache(
      fetcher: (uri) async {
        fetchCount++;
        expect(uri.toString(), 'https://image.tmdb.org/t/p/w500/test.jpg');
        return <int>[1, 2, 3, 4];
      },
    );
    const url = 'https://image.tmdb.org/t/p/w500/test.jpg';

    final first = await cache.cacheImage(url);
    final second = await cache.cacheImage(url);

    expect(await first.readAsBytes(), <int>[1, 2, 3, 4]);
    expect(second.path, first.path);
    expect(fetchCount, 1);
    expect(await cache.getCachedImagePath(url), first.path);
  });

  test('persists manual TMDB overrides without storing sensitive metadata',
      () async {
    final cache = createCache();
    const match = TmdbMediaMatch(
      id: 42,
      mediaType: TmdbMediaType.tv,
      title: '匹配剧',
      originalTitle: 'Matched Show',
      overview: '简介',
      year: 2024,
      posterUrl: 'https://image.tmdb.org/poster.jpg',
      backdropUrl: '',
      rating: 8.5,
    );

    await cache.setOverride(cineoMediaId: 'cineo-42', match: match);
    await cache.putMetadata(
      mediaId: 'cineo-42',
      data: <String, dynamic>{
        'match': <String, dynamic>{
          'title': '匹配剧',
          'api_token': 'must-not-write'
        },
        'Authorization': 'Bearer secret',
      },
    );

    expect((await cache.getOverride('cineo-42'))?.id, 42);
    final files = await _allFiles(temporaryDirectory);
    final contents =
        await Future.wait(files.map((file) => file.readAsString()));
    expect(contents.join(), isNot(contains('must-not-write')));
    expect(contents.join(), isNot(contains('Bearer secret')));
  });

  test(
      'reports disk statistics and clears cache while retaining overrides by default',
      () async {
    final cache = createCache(fetcher: (_) async => <int>[1, 2, 3]);
    await cache.putMetadata(
      mediaId: 'media-1',
      data: <String, dynamic>{'title': '测试'},
    );
    await cache.cacheImage('https://image.tmdb.org/test.jpg');
    await cache.setOverride(
      cineoMediaId: 'media-1',
      match: const TmdbMediaMatch(
        id: 7,
        mediaType: TmdbMediaType.movie,
        title: '电影',
        originalTitle: 'Movie',
        overview: '',
        year: null,
        posterUrl: '',
        backdropUrl: '',
        rating: 0,
      ),
    );

    final stats = await cache.getStats();
    expect(stats.metadataCount, 1);
    expect(stats.imageCount, 1);
    expect(stats.overrideCount, 1);
    expect(stats.totalBytes, greaterThan(0));

    await cache.clearAll();
    final afterClear = await cache.getStats();
    expect(afterClear.metadataCount, 0);
    expect(afterClear.imageCount, 0);
    expect(afterClear.overrideCount, 1);
    expect(await cache.getOverride('media-1'), isNotNull);

    await cache.clearAll(includeOverrides: true);
    expect((await cache.getStats()).overrideCount, 0);
  });

  test('clears files that exceed a configured retention age', () async {
    var now = DateTime.utc(2026, 8, 22);
    final cache = createCache(
      clock: () => now,
      fetcher: (_) async => <int>[1, 2, 3],
    );
    await cache.putMetadata(
      mediaId: 'aged-media',
      data: <String, dynamic>{'title': '旧资料'},
      ttl: const Duration(days: 90),
    );
    await cache.cacheImage(
      'https://image.tmdb.org/aged.jpg',
      ttl: const Duration(days: 90),
    );

    now = now.add(const Duration(days: 31));
    final removed = await cache.clearExpired(
      maxAge: const Duration(days: 30),
    );

    expect(removed, greaterThanOrEqualTo(3));
    expect(await cache.getMetadata('aged-media'), isNull);
    expect(await cache.getCachedImagePath('https://image.tmdb.org/aged.jpg'),
        isNull);
  });
}

Future<File> _findFile(Directory directory, String extension) async {
  await for (final entity in directory.list(recursive: true)) {
    if (entity is File && entity.path.endsWith(extension)) return entity;
  }
  throw StateError('No $extension file found');
}

Future<List<File>> _allFiles(Directory directory) async {
  final files = <File>[];
  await for (final entity in directory.list(recursive: true)) {
    if (entity is File) files.add(entity);
  }
  return files;
}
