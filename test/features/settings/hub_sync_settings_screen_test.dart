import 'dart:io';
import 'dart:ui' as ui;

import 'package:cineo_flutter/data/hub/hub_sync_api.dart';
import 'package:cineo_flutter/data/hub/hub_sync_engine.dart';
import 'package:cineo_flutter/data/repositories/local_media_repository.dart';
import 'package:cineo_flutter/features/settings/hub_sync_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory directory;
  late LocalMediaRepository repository;
  late HubSyncEngine engine;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStoragePlatform.instance =
        TestFlutterSecureStoragePlatform(<String, String>{});
    directory = await Directory.systemTemp.createTemp('hub_settings_test_');
    repository = LocalMediaRepository(databasePath: '${directory.path}/db');
    await repository.hubDatabase;
    engine = HubSyncEngine(
      repository: repository,
      api: HubSyncApi(credentials: HubDeviceCredentials()),
    );
  });
  tearDown(() async {
    await repository.close();
    await directory.delete(recursive: true);
  });

  for (final size in [const Size(320, 568), const Size(390, 844), const Size(600, 900)]) {
    testWidgets('sync controls remain usable with long status at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        await engine.api.credentials.save(hubUrl: 'https://hub.example.test', deviceId: 'device', token: 'token');
        final db = await repository.hubDatabase;
        await db.insert('hub_sync_state', {'state_key': 'last_error', 'value': '同步遇到问题，请检查网络设置后重试。' * 12});
      });
      const captureKey = Key('capture-sync-screen');
      await tester.pumpWidget(MaterialApp(home: RepaintBoundary(key: captureKey, child: HubSyncSettingsScreen(engine: engine, repository: repository))));
      await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();
      final push = find.widgetWithText(FilledButton, '推送全部');
      final clean = find.textContaining('清理旧冲突操作（');
      final pushRect = tester.getRect(push);
      final cleanRect = tester.getRect(find.ancestor(of: clean, matching: find.byType(OutlinedButton)).first);
      expect(cleanRect.top - pushRect.bottom, greaterThanOrEqualTo(8));
      await tester.ensureVisible(find.text('立即拉取'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('推送并拉取'));
      await tester.pumpAndSettle();
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(captureKey));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('/tmp/cineo-sync-${size.width.toInt()}x${size.height.toInt()}.png').writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      for (final label in ['推送全部', '立即拉取', '推送并拉取', '解除本机绑定']) {
        final item = find.text(label);
        await tester.ensureVisible(item);
        await tester.pumpAndSettle();
        expect(item, findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.ensureVisible(find.textContaining('同步遇到问题'));
      await tester.pumpAndSettle();
      expect(find.textContaining('同步遇到问题'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('bind button follows the eight digit PIN input', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: HubSyncSettingsScreen(engine: engine, repository: repository),
    ));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    final pin = find.widgetWithText(TextField, '8 位 PIN');
    final button = find.widgetWithText(FilledButton, '绑定设备');
    bool enabled() => tester.widget<FilledButton>(button).onPressed != null;

    expect(enabled(), isFalse);
    await tester.enterText(pin, '1234567');
    await tester.pump();
    expect(enabled(), isFalse);
    await tester.enterText(pin, '12345678');
    await tester.pump();
    expect(enabled(), isTrue);
    await tester.enterText(pin, '1234567');
    await tester.pump();
    expect(enabled(), isFalse);
    await tester.enterText(pin, '12a45678');
    await tester.pump();
    expect(enabled(), isFalse);
    await tester.enterText(pin, '123456789');
    await tester.pump();
    expect(tester.widget<TextField>(pin).controller!.text, '12345678');
    expect(enabled(), isTrue);
  });
  testWidgets(
      'conflict cleanup requires confirmation and preserves data on cancel',
      (tester) async {
    final db = await tester.runAsync(() async {
      await engine.api.credentials.save(
          hubUrl: 'https://hub.example.test',
          deviceId: 'device',
          token: 'token');
      final db = await repository.hubDatabase;
      await db.insert('hub_outbox', {
        'entity': 'history',
        'record_key': 'old',
        'updated_at': 1,
        'deleted': 0,
        'payload_json': '{}',
        'attempts': 0,
        'next_attempt_at': 0
      });
      return db;
    });
    await tester.pumpWidget(MaterialApp(
        home: HubSyncSettingsScreen(engine: engine, repository: repository)));
    await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    final button = find.text('清理旧冲突操作（1）');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.text('清理旧冲突操作？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    final before = await tester.runAsync(() => db!.query('hub_outbox'));
    expect(before, hasLength(1));
    await tester.tap(button);
    await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认清理'));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    final after = await tester.runAsync(() => db!.query('hub_outbox'));
    expect(after, isEmpty);
  });
}
