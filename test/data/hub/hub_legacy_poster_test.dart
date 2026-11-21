import 'dart:convert';
import 'dart:io';

import 'package:cineo_flutter/core/models/media.dart';
import 'package:cineo_flutter/data/hub/hub_sync_api.dart';
import 'package:cineo_flutter/data/hub/hub_sync_engine.dart';
import 'package:cineo_flutter/data/hub/hub_sync_keys.dart';
import 'package:cineo_flutter/data/repositories/local_media_repository.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  test('repairs exact cached legacy keys while retaining conflicting queue',
      () async {
    final dir = await Directory.systemTemp.createTemp('legacy_poster_');
    final repo = LocalMediaRepository(databasePath: '${dir.path}/db');
    addTearDown(() async {
      await repo.close();
      await dir.delete(recursive: true);
    });
    FlutterSecureStoragePlatform.instance =
        TestFlutterSecureStoragePlatform(<String, String>{});
    final credentials = HubDeviceCredentials();
    await credentials.save(
        hubUrl: 'https://hub.example.test', deviceId: 'device', token: 'token');
    final source = (await repo.sources()).single;
    final media = MediaItem(
        id: 'local-42',
        title: 'series',
        description: '',
        year: 2026,
        kind: MediaKind.series,
        posterUrl: 'https://example.test/cover.jpg',
        backdropUrl: '',
        genres: const [],
        rating: 0,
        duration: const Duration(minutes: 1),
        sourceId: source.id,
        sourceName: source.name,
        remoteId: '42',
        category: 'series');
    await repo.saveProgress(
        WatchProgress(
            mediaId: media.id,
            episodeId: 'line:0',
            episodeLabel: 'line',
            episodeNumber: 0,
            position: const Duration(seconds: 10),
            duration: media.duration,
            updatedAt: DateTime.utc(2026)),
        media: media);
    final db = await repo.hubDatabase;
    final sourceKey = hubSourceKey(source.baseUrl);
    final two = hubMediaKey(sourceKey: sourceKey, vodId: '42');
    final four = hubMediaKey(
        sourceKey: sourceKey, vodId: '42', lineName: 'line', episodeIndex: 0);
    final deleted = hubMediaKey(
        sourceKey: sourceKey,
        vodId: '42',
        lineName: 'deleted',
        episodeIndex: 0);
    final tombstone = hubMediaKey(
        sourceKey: sourceKey,
        vodId: '42',
        lineName: 'pending',
        episodeIndex: 0);
    final tombstone2 = hubMediaKey(
        sourceKey: sourceKey,
        vodId: '42',
        lineName: 'pending2',
        episodeIndex: 0);
    final tombstone3 = hubMediaKey(
        sourceKey: sourceKey,
        vodId: '42',
        lineName: 'pending3',
        episodeIndex: 0);
    final missing = hubMediaKey(sourceKey: sourceKey, vodId: 'missing');
    final other = hubMediaKey(
        sourceKey: hubSourceKey('https://other.example/api'), vodId: '42');
    Future<void> cache(String key, {bool removed = false}) async {
      await db.insert('hub_sync_state', {
        'state_key': 'remote_history:$key',
        'value': jsonEncode({
          'entity': 'history',
          'key': key,
          'updated_at': 1,
          'deleted': removed,
          'payload': <String, Object>{}
        })
      });
    }

    for (final key in [
      two,
      four,
      tombstone,
      tombstone2,
      tombstone3,
      missing,
      other
    ]) {
      await cache(key);
    }
    await cache(deleted, removed: true);
    for (var i = 0; i < 13; i++) {
      await db.insert('hub_outbox', {
        'entity': i < 6
            ? 'history'
            : i < 12
                ? 'progress'
                : 'site',
        'record_key':
            i < 3 ? [tombstone, tombstone2, tombstone3][i] : 'conflict-$i',
        'updated_at': i,
        'deleted': i < 3 ? 1 : 0,
        'payload_json': i < 3 ? null : '{}',
        'attempts': 0,
        'next_attempt_at': 0
      });
    }
    final repairs = <Map<String, dynamic>>[];
    final requests = <String>[];
    String? injectDeletion;
    Map<String, Object?>? injectDuplicate;
    var injectSnapshotConflict = false;
    var posterCalls = 0;
    final api = HubSyncApi(
        credentials: credentials,
        client: MockClient((request) async {
          requests.add(request.url.path);
          final items = (jsonDecode(request.body) as Map)['items'] as List;
          if (request.url.path.endsWith('/push')) {
            return http.Response(
                jsonEncode({
                  'code': 200,
                  'data': {'accepted': items.length, 'ignored': 0}
                }),
                200,
                headers: {'content-type': 'application/json'});
          }
          repairs.addAll(items.cast<Map<String, dynamic>>());
          posterCalls++;
          if (injectDeletion != null && posterCalls == 1) {
            await db.insert('hub_outbox', {
              'entity': 'history',
              'record_key': injectDeletion,
              'updated_at': 100,
              'deleted': 1,
              'payload_json': null,
              'attempts': 0,
              'next_attempt_at': 0,
            });
          }
          if (injectDuplicate != null && posterCalls == 1) {
            await db.insert('progress', injectDuplicate);
          }
          if (injectSnapshotConflict && posterCalls == 1) {
            await db.update('media_snapshots',
                {'poster_url': 'https://example.test/conflict.jpg'},
                where: 'media_id=?', whereArgs: ['other-local-id']);
          }
          return http.Response(
              jsonEncode({
                'code': 200,
                'data': {'updated': items.length}
              }),
              200,
              headers: {'content-type': 'application/json'});
        }));
    final engine = HubSyncEngine(repository: repo, api: api);
    final result = await engine.pushAll();
    expect(result['failed'], 12);
    expect(result['sent'], 2);
    expect(result['posters_updated'], 2);
    expect(result['error'], contains('已补全 2 条封面'));
    expect(repairs.map((x) => x['key']).toSet(), {two, four});
    expect(requests.where((p) => p.endsWith('/push')), hasLength(1));
    expect(await db.query('hub_outbox'), hasLength(12));
    final originalProgress = Map<String, Object?>.from(
        (await db.query('progress', where: 'media_id=?', whereArgs: [media.id]))
            .single);
    originalProgress['progress_key'] = 'duplicate-legacy-progress';
    await db.insert('progress', originalProgress);
    repairs.clear();
    await engine.pushAll();
    expect(repairs.map((item) => item['key']), isNot(contains(four)));
    expect(repairs.map((item) => item['key']), contains(two));
    await db.delete('progress',
        where: 'progress_key=?', whereArgs: ['duplicate-legacy-progress']);

    final laterKeys = <String>[];
    for (var i = 0; i < 105; i++) {
      final key = hubMediaKey(
          sourceKey: sourceKey,
          vodId: '42',
          lineName: 'extra-$i',
          episodeIndex: 0);
      laterKeys.add(key);
      await cache(key);
    }
    injectDeletion = laterKeys.last;
    posterCalls = 0;
    repairs.clear();
    await engine.pushAll();
    expect(posterCalls, greaterThan(1));
    expect(repairs.map((item) => item['key']), isNot(contains(injectDeletion)));
    expect(
        (await db.query('hub_outbox',
                where: 'record_key=?', whereArgs: [injectDeletion]))
            .single['deleted'],
        1);
    await db.delete('hub_outbox',
        where: 'record_key=?', whereArgs: [injectDeletion]);
    injectDeletion = null;
    final extraProgress = Map<String, Object?>.from(originalProgress)
      ..['progress_key'] = 'extra-progress-1'
      ..['episode_label'] = 'extra-104';
    await db.insert('progress', extraProgress);
    injectDuplicate = Map<String, Object?>.from(extraProgress)
      ..['progress_key'] = 'extra-progress-2';
    posterCalls = 0;
    repairs.clear();
    await engine.pushAll();
    expect(posterCalls, greaterThan(1));
    expect(repairs.map((item) => item['key']), isNot(contains(laterKeys.last)));
    await db.delete('progress',
        where: 'progress_key IN (?,?)',
        whereArgs: ['extra-progress-1', 'extra-progress-2']);
    injectDuplicate = null;
    // Identical covers on two same-source snapshots remain eligible.
    final duplicate = Map<String, Object?>.from((await db.query(
            'media_snapshots',
            where: 'media_id=?',
            whereArgs: [media.id]))
        .single);
    duplicate['media_id'] = 'other-local-id';
    await db.insert('media_snapshots', duplicate);
    repairs.clear();
    final again = await engine.pushAll();
    expect(again['posters_updated'], greaterThan(0));
    expect(repairs.map((item) => item['key']), containsAll([two, four]));
    expect(repairs.map((item) => item['key']), isNot(contains(tombstone)));
    expect(repairs.map((item) => item['key']), isNot(contains(tombstone2)));
    expect(repairs.map((item) => item['key']), isNot(contains(tombstone3)));
    injectSnapshotConflict = true;
    posterCalls = 0;
    repairs.clear();
    await engine.pushAll();
    expect(posterCalls, 1);
    expect(repairs.map((item) => item['key']), isNot(contains(laterKeys.last)));
    injectSnapshotConflict = false;
    for (final conflictingPoster in [
      'https://example.test/different.jpg',
      ''
    ]) {
      await db.update('media_snapshots', {'poster_url': conflictingPoster},
          where: 'media_id=?', whereArgs: ['other-local-id']);
      repairs.clear();
      final blocked = await engine.pushAll();
      expect(blocked['posters_updated'], 0);
      expect(repairs, isEmpty);
    }
    expect(await db.query('hub_outbox'), hasLength(12));

    // With an otherwise sendable queue, broken cached envelopes must not
    // fall back to the ordinary less strict candidate.
    await db.delete('hub_outbox');
    await db.update('progress',
        {'episode_label': 'line', 'line_name': 'line', 'episode_number': 1},
        where: 'media_id=?', whereArgs: [media.id]);
    final rawKey = hubMediaKey(
        sourceKey: sourceKey, vodId: '42', lineName: 'line', episodeIndex: 1);
    for (final badValue in [
      '{',
      jsonEncode({
        'entity': 'history',
        'key': 'mismatched',
        'updated_at': 1,
        'deleted': false,
        'payload': {}
      })
    ]) {
      await db.insert('hub_sync_state',
          {'state_key': 'remote_history:$rawKey', 'value': badValue},
          conflictAlgorithm: ConflictAlgorithm.replace);
      repairs.clear();
      await engine.pushAll();
      expect(repairs.map((item) => item['key']), isNot(contains(rawKey)));
    }
  });
}
