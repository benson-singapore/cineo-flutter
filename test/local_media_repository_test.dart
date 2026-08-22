import 'dart:io';

import 'package:cineo_flutter/core/models/media.dart';
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

  test('persists a display snapshot when remote playback progress is saved',
      () async {
    final progress = WatchProgress(
      mediaId: media.id,
      episodeId: 'source-a:42:1',
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
  });
}
