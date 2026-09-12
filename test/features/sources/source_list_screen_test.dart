import 'package:cineo_flutter/core/models/media.dart';
import 'package:cineo_flutter/core/models/media_source.dart';
import 'package:cineo_flutter/core/models/source_group_config.dart';
import 'package:cineo_flutter/data/remote/media_category_adapter.dart';
import 'package:cineo_flutter/data/repositories/media_repository.dart';
import 'package:cineo_flutter/features/settings/adult_source_settings.dart';
import 'package:cineo_flutter/features/sources/source_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeMediaRepository implements MediaRepository {
  int setDefaultCalls = 0;
  String? lastDefaultSourceId;

  @override
  Future<List<MediaItem>> featured() async => const [];

  @override
  Future<List<MediaItem>> search(String query) async => const [];

  @override
  Future<MediaItem?> getById(String id) async => null;

  @override
  Future<List<MediaItem>> favorites() async => const [];

  @override
  Future<bool> isFavorite(String mediaId) async => false;

  @override
  Future<void> setFavorite(MediaItem media, bool isFavorite) async {}

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
  Future<List<MediaSource>> sources() async => const [
        MediaSource(
          id: 'regular',
          name: '普通视频源',
          type: MediaSourceType.macCmsApi,
          baseUrl: 'https://regular.example.test/api.php/provide/vod',
        ),
        MediaSource(
          id: 'adult',
          name: '成人视频源',
          type: MediaSourceType.macCmsApi,
          baseUrl: 'https://adult.example.test/api.php/provide/vod',
          isAdult: true,
        ),
      ];

  @override
  Future<void> saveSource(MediaSource source) async {}

  @override
  Future<void> deleteSource(String id) async {}

  @override
  Future<bool> testSource(MediaSource source) async => true;

  @override
  Future<MediaSource?> defaultSource() async => null;

  @override
  Future<void> setDefaultSource(String id) async {
    setDefaultCalls++;
    lastDefaultSourceId = id;
  }

  @override
  Future<List<SourceGroupConfig>> getSourceGroupConfigs(
          String sourceId) async =>
      const [];

  @override
  Future<List<SourceGroupConfig>> syncSourceGroupConfigs(
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

void main() {
  testWidgets('notifies when a default source is set successfully',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final adultSettings = AdultSourceSettings();
    await adultSettings.initialize();
    final repository = _FakeMediaRepository();
    var notifications = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: SourceListScreen(
          repository: repository,
          adultSourceSettings: adultSettings,
          onDefaultSourceChanged: () => notifications++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('普通源 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设为默认'));
    await tester.pumpAndSettle();

    expect(repository.setDefaultCalls, 1);
    expect(notifications, 1);
  });

  testWidgets('hides adult sources from every tab when disabled',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final adultSettings = AdultSourceSettings();
    await adultSettings.initialize();
    final repository = _FakeMediaRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: SourceListScreen(
          repository: repository,
          adultSourceSettings: adultSettings,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('普通源 1'));
    await tester.pumpAndSettle();

    expect(find.text('普通视频源'), findsOneWidget);
    expect(find.text('成人视频源'), findsNothing);
    expect(find.textContaining('成人源'), findsNothing);
  });

  testWidgets('loads the bundled default source config into the import field',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final adultSettings = AdultSourceSettings();
    await adultSettings.initialize();
    final repository = _FakeMediaRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: SourceListScreen(
          repository: repository,
          adultSourceSettings: adultSettings,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('导入 JSON 配置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('加载默认配置'));
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField).last);
    expect(field.controller?.text, contains('"cache_time": 7200'));
    expect(field.controller?.text, contains('"xiaomaomi"'));

    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();

    expect(repository.lastDefaultSourceId, 'ruyi');
  });

  testWidgets('falls back to the first source when ruyi is unavailable',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final adultSettings = AdultSourceSettings();
    await adultSettings.initialize();
    final repository = _FakeMediaRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: SourceListScreen(
          repository: repository,
          adultSourceSettings: adultSettings,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('导入 JSON 配置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('加载默认配置'));
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField).last);
    field.controller!.text = '''
    {
      "api_site": {
        "first": {
          "api": "https://first.example.test/vod",
          "name": "第一个来源"
        }
      }
    }
    ''';
    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();

    expect(repository.lastDefaultSourceId, 'first');
  });
}
