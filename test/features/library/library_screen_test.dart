import 'package:cineo_flutter/core/models/media.dart';
import 'package:cineo_flutter/core/models/media_source.dart';
import 'package:cineo_flutter/core/models/source_group_config.dart';
import 'package:cineo_flutter/data/remote/media_category_adapter.dart';
import 'package:cineo_flutter/data/repositories/media_repository.dart';
import 'package:cineo_flutter/features/library/library_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeMediaRepository implements MediaRepository {
  _FakeMediaRepository(this._items);

  List<MediaItem> _items;
  MediaItem? removed;

  @override
  Future<List<MediaItem>> featured() async => const [];

  @override
  Future<List<MediaItem>> search(String query) async => const [];

  @override
  Future<MediaItem?> getById(String id) async => null;

  @override
  Future<List<MediaItem>> favorites() async => _items;

  @override
  Future<bool> isFavorite(String mediaId) async => false;

  @override
  Future<void> setFavorite(MediaItem media, bool isFavorite) async {
    if (!isFavorite) {
      removed = media;
      _items = _items.where((item) => item.id != media.id).toList();
    }
  }

  @override
  Future<List<WatchProgress>> watchHistory({bool includeAdult = true}) async =>
      const [];

  @override
  Future<void> saveProgress(
    WatchProgress progress, {
    MediaItem? media,
  }) async {}

  @override
  Future<MediaItem?> loadDetails(MediaItem item) async => item;

  @override
  Future<void> removeHistory(String mediaId) async {}

  @override
  Future<void> clearHistory() async {}

  @override
  Future<List<String>> searchHistory() async => const [];

  @override
  Future<void> addSearchHistory(String query) async {}

  @override
  Future<List<MediaSource>> sources() async => const [];

  @override
  Future<void> saveSource(MediaSource source) async {}

  @override
  Future<void> deleteSource(String id) async {}

  @override
  Future<bool> testSource(MediaSource source) async => true;

  @override
  Future<MediaSource?> defaultSource() async => null;

  @override
  Future<void> setDefaultSource(String id) async {}

  @override
  Future<List<SourceGroupConfig>> getSourceGroupConfigs(
          String sourceId) async =>
      const [];

  @override
  Future<void> saveSourceGroupConfig(SourceGroupConfig config) async {}

  @override
  Future<List<String>> getEnabledGroupIdsForSource(String sourceId) async =>
      const [];

  @override
  Future<void> initializeSourceGroupConfigs(
    String sourceId,
    List<UnifiedSubcategory> leafCategories,
  ) async {}

  @override
  Future<void> toggleSourceGroupConfig(
    String sourceId,
    String groupId,
    bool enable,
  ) async {}
}

MediaItem _media(String id, String title) {
  return MediaItem(
    id: id,
    title: title,
    description: '',
    year: 2026,
    kind: MediaKind.movie,
    posterUrl: '',
    backdropUrl: '',
    genres: const [],
    rating: 8,
    duration: const Duration(minutes: 90),
  );
}

void main() {
  testWidgets('removes a favorite directly from the collection grid',
      (tester) async {
    final repository = _FakeMediaRepository([
      _media('favorite-1', '我的收藏视频'),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          mode: LibraryContentMode.favorites,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('我的收藏视频'), findsOneWidget);
    await tester.tap(find.byTooltip('取消收藏'));
    await tester.pumpAndSettle();

    expect(repository.removed?.id, 'favorite-1');
    expect(find.text('我的收藏视频'), findsNothing);
    expect(find.text('还没有收藏内容'), findsOneWidget);
  });
}
