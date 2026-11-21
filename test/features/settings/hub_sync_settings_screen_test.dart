import 'dart:io';

import 'package:cineo_flutter/data/hub/hub_sync_api.dart';
import 'package:cineo_flutter/data/hub/hub_sync_engine.dart';
import 'package:cineo_flutter/data/repositories/local_media_repository.dart';
import 'package:cineo_flutter/features/settings/hub_sync_settings_screen.dart';
import 'package:flutter/material.dart';
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
