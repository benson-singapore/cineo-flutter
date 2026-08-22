import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
// The storage plugin exposes its test platform through this transitive interface.
// ignore: depend_on_referenced_packages
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cineo_flutter/features/settings/tmdb_settings.dart';
import 'package:cineo_flutter/features/settings/tmdb_cache_settings.dart';
import 'package:cineo_flutter/features/settings/tmdb_settings_screen.dart';

class FakeTmdbCacheSettingsController extends TmdbCacheSettingsController {
  FakeTmdbCacheSettingsController({
    TmdbCacheStats stats = const TmdbCacheStats(bytes: 0, fileCount: 0),
    int retentionDays = 30,
  })  : _stats = stats,
        _retentionDays = retentionDays;

  TmdbCacheStats _stats;
  int _retentionDays;
  bool _initialized = false;
  final bool _isBusy = false;
  String? _errorMessage;
  int initializeCalls = 0;
  int cleanupCalls = 0;
  int clearCalls = 0;

  @override
  bool get initialized => _initialized;

  @override
  bool get isBusy => _isBusy;

  @override
  String? get errorMessage => _errorMessage;

  @override
  TmdbCacheStats get stats => _stats;

  @override
  int get retentionDays => _retentionDays;

  @override
  Future<void> initialize({bool force = false}) async {
    initializeCalls++;
    _initialized = true;
    notifyListeners();
  }

  @override
  Future<void> setRetentionDays(int days) async {
    _retentionDays = days;
    notifyListeners();
  }

  @override
  Future<void> cleanupExpired() async {
    cleanupCalls++;
    notifyListeners();
  }

  @override
  Future<void> clearAll() async {
    clearCalls++;
    _stats = const TmdbCacheStats.empty();
    notifyListeners();
  }
}

void main() {
  late Map<String, String> secureData;

  setUp(() {
    secureData = <String, String>{};
    FlutterSecureStoragePlatform.instance =
        TestFlutterSecureStoragePlatform(secureData);
  });

  test('initializes as not configured when no token is stored', () async {
    final settings = TMDBSettings();

    expect(settings.initialized, isFalse);
    await settings.initialize();

    expect(settings.initialized, isTrue);
    expect(settings.configured, isFalse);
    expect(settings.errorMessage, isNull);
  });

  test('trims and securely persists a token without exposing it as state',
      () async {
    final settings = TMDBSettings();

    await settings.saveToken('  test-token-value  ');

    expect(settings.initialized, isTrue);
    expect(settings.configured, isTrue);
    expect(secureData[TMDBSettings.tokenStorageKey], 'test-token-value');
  });

  test('reads configured state and clears the token', () async {
    secureData[TMDBSettings.tokenStorageKey] = 'stored-token';
    final settings = TMDBSettings();

    await settings.initialize();
    expect(settings.configured, isTrue);

    await settings.clearToken();

    expect(settings.configured, isFalse);
    expect(secureData.containsKey(TMDBSettings.tokenStorageKey), isFalse);
  });

  test('reads the token only for a request without adding it to state',
      () async {
    secureData[TMDBSettings.tokenStorageKey] = ' request-token ';
    final settings = TMDBSettings();

    final token = await settings.readTokenForRequest();

    expect(token, 'request-token');
    expect(settings.configured, isFalse);
    expect(settings.errorMessage, isNull);
  });

  test('rejects a blank token', () async {
    final settings = TMDBSettings();

    await expectLater(
      settings.saveToken(' \n\t '),
      throwsA(isA<ArgumentError>()),
    );

    expect(settings.configured, isFalse);
    expect(settings.errorMessage, '请输入有效的 TMDB API Token');
  });

  testWidgets('clears the input after saving and only shows configured state',
      (tester) async {
    final settings = TMDBSettings();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: TMDBSettingsScreen(settings: settings),
      ),
    );
    await tester.pumpAndSettle();

    const token = 'widget-test-token';
    await tester.enterText(find.byType(TextField), token);
    await tester.tap(find.text('保存配置'));
    await tester.pumpAndSettle();

    expect(settings.configured, isTrue);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    expect(find.text(token), findsNothing);
    expect(find.text('已配置'), findsOneWidget);
  });

  testWidgets('shows cache statistics and changes retention duration',
      (tester) async {
    final settings = TMDBSettings();
    final cache = FakeTmdbCacheSettingsController(
      stats: const TmdbCacheStats(bytes: 1572864, fileCount: 3),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: TMDBSettingsScreen(
          settings: settings,
          cacheController: cache,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = find.byType(Scrollable).first;
    await tester.drag(scrollable, const Offset(0, -700));
    await tester.pumpAndSettle();

    final retentionLabel = find.text('1 个月');
    expect(find.text('1.5 MB · 3 个文件'), findsOneWidget);
    expect(retentionLabel, findsOneWidget);
    expect(cache.initializeCalls, 1);

    await tester.tap(retentionLabel);
    await tester.pumpAndSettle();
    expect(find.text('选择缓存保留时间'), findsOneWidget);
    await tester.tap(find.text('3 个月'));
    await tester.pumpAndSettle();

    expect(cache.retentionDays, 90);
    expect(find.text('缓存保留时间已设为 3 个月'), findsOneWidget);
  });

  testWidgets('cleans expired cache and confirms clearing all cache',
      (tester) async {
    final settings = TMDBSettings();
    final cache = FakeTmdbCacheSettingsController(
      stats: const TmdbCacheStats(bytes: 2048, fileCount: 2),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: TMDBSettingsScreen(
          settings: settings,
          cacheController: cache,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -700));
    await tester.pumpAndSettle();

    final cleanupButton = find.text('清理过期缓存');
    await tester.tap(cleanupButton);
    await tester.pumpAndSettle();
    expect(cache.cleanupCalls, 1);
    expect(find.text('过期 TMDB 缓存已清理'), findsOneWidget);

    final clearButton = find.text('清空全部');
    await tester.tap(find.text('清空全部'));
    await tester.pumpAndSettle();
    expect(find.text('清空 TMDB 缓存？'), findsOneWidget);
    expect(cache.clearCalls, 0);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(cache.clearCalls, 0);

    await tester.tap(clearButton);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '清空'));
    await tester.pumpAndSettle();

    expect(cache.clearCalls, 1);
    expect(find.text('0 B · 0 个文件'), findsOneWidget);
  });
}
