import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cineo_flutter/core/theme/cineo_theme.dart';
import 'package:cineo_flutter/data/cache/tmdb_disk_cache.dart';
import 'package:cineo_flutter/data/download/download_service.dart';
import 'package:cineo_flutter/features/settings/adult_source_settings.dart';
import 'package:cineo_flutter/features/settings/m3u8_filter_settings.dart';
import 'package:cineo_flutter/features/settings/settings_screen.dart';
import 'package:cineo_flutter/features/settings/tmdb_settings.dart';
import 'package:cineo_flutter/features/settings/tmdb_disk_cache_controller.dart';

void main() {
  testWidgets('opens download settings as a separate detail page',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final service = DownloadService();
    final adultSettings = AdultSourceSettings();
    final filterSettings = M3u8FilterSettings();
    await adultSettings.initialize();
    await filterSettings.initialize();
    final cacheController = TmdbDiskCacheController(cache: TmdbDiskCache());
    addTearDown(() async {
      adultSettings.dispose();
      filterSettings.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: buildCineoTheme(),
        home: SettingsScreen(
          adultSourceSettings: adultSettings,
          m3u8FilterSettings: filterSettings,
          tmdbSettings: TMDBSettings(),
          tmdbCacheController: cacheController,
          downloadService: service,
          onOpenDownloadManager: () {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('缓存下载'), findsOneWidget);
    expect(find.text('下载设置'), findsAtLeastNWidgets(1));
    expect(find.textContaining('缓存路径'), findsNothing);

    await tester.tap(find.text('下载设置'));
    await tester.pumpAndSettle();

    expect(find.text('下载设置'), findsAtLeastNWidgets(1));
    expect(find.text('同时下载线程'), findsOneWidget);
    expect(find.text('5 个任务同时下载'), findsOneWidget);
    expect(find.text('允许后台下载'), findsOneWidget);
    expect(find.textContaining('缓存路径'), findsNothing);
    expect(find.textContaining('缓存位置'), findsNothing);
    expect(find.textContaining('缓存大小'), findsNothing);
  });
}
