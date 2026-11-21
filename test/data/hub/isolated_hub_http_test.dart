import 'dart:convert';
import 'dart:io';
import 'package:cineo_flutter/data/hub/hub_sync_api.dart';
import 'package:cineo_flutter/data/hub/hub_sync_engine.dart';
import 'package:cineo_flutter/data/hub/hub_sync_keys.dart';
import 'package:cineo_flutter/data/repositories/local_media_repository.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final fixturePath = Platform.environment['CINEO_ISOLATED_FIXTURE'];
  test('real Hub HTTP pull and deletion reconciliation', () async {
    expect(fixturePath, isNotNull);
    final fixture = jsonDecode(await File(fixturePath!).readAsString())
        as Map<String, dynamic>;
    final phone = fixture['phone'] as Map<String, dynamic>;
    final dir = await Directory.systemTemp.createTemp('cineo-real-http-');
    final repositories = <LocalMediaRepository>[];
    addTearDown(() async {
      for (final r in repositories) {
        await r.close();
      }
      await dir.delete(recursive: true);
    });
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    HttpOverrides.global = null;
    FlutterSecureStoragePlatform.instance =
        TestFlutterSecureStoragePlatform(<String, String>{});
    final credentials = HubDeviceCredentials();
    await credentials.save(
        hubUrl: 'http://127.0.0.1:18764',
        deviceId: phone['device_id'] as String,
        token: phone['device_token'] as String);
    final engines = <HubSyncEngine>[];
    final key = hubMediaKey(
        sourceKey: hubSourceKey('https://isolation.example.test/api'),
        vodId: '42');
    for (final name in ['deleted', 'pending', 'newer', 'unknown']) {
      final repo = LocalMediaRepository(databasePath: '${dir.path}/$name.db');
      repositories.add(repo);
      final engine = HubSyncEngine(
          repository: repo, api: HubSyncApi(credentials: credentials));
      engines.add(engine);
      await engine.pullAndApply();
      final db = await repo.hubDatabase;
      final progress = await db.query('progress');
      expect(progress, hasLength(1), reason: name);
      final history = await repo.watchHistory();
      expect(history, hasLength(1));
      final media = (await repo.getById(history.single.mediaId))!;
      expect(media.year, 2026);
      expect(media.category, '剧集');
      if (name == 'pending') {
        await db.insert('hub_outbox', {
          'entity': 'progress',
          'record_key': '$key:A:0',
          'updated_at': 9999999999999,
          'deleted': 0,
          'payload_json': '{}',
          'attempts': 0,
          'next_attempt_at': 0
        });
      } else if (name == 'newer') {
        await db.update('progress', {'updated_at': 9999999999999});
      } else if (name == 'unknown') {
        await db.update('progress', {'episode_id': 'legacy-episode'});
      }
    }
    final cookies = (fixture['cookies'] as Map<String, dynamic>)
        .entries
        .map((e) => '${e.key}=${e.value}')
        .join('; ');
    final response = await http.delete(
        Uri.parse(
            'http://127.0.0.1:18764/api/v1/admin/history/${Uri.encodeComponent(key)}'),
        headers: {
          'Cookie': cookies,
          'X-CSRF-Token': fixture['csrf'] as String
        });
    expect(response.statusCode, 200, reason: response.body);
    for (var i = 0; i < repositories.length; i++) {
      await engines[i].pullAndApply();
      final db = await repositories[i].hubDatabase;
      expect(await db.query('progress'), hasLength(i == 0 ? 0 : 1),
          reason: 'scenario $i');
      final outbox = await db.query('hub_outbox');
      expect(outbox, hasLength(i == 1 ? 1 : 0));
      if (i == 1) {
        expect(outbox.single['record_key'], '$key:A:0');
        expect(outbox.single['payload_json'], '{}');
      }
    }
  },
      skip: fixturePath == null
          ? 'Requires disposable isolated Hub fixture'
          : false);
}
