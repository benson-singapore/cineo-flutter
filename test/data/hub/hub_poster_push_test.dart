import 'dart:convert';
import 'dart:io';

import 'package:cineo_flutter/core/models/media.dart';
import 'package:cineo_flutter/data/hub/hub_sync_api.dart';
import 'package:cineo_flutter/data/hub/hub_sync_engine.dart';
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
  test('history, progress and favorite carry the snapshot poster', () async {
    final dir = await Directory.systemTemp.createTemp('hub_poster_');
    final repository = LocalMediaRepository(databasePath: '${dir.path}/db');
    addTearDown(() async {
      await repository.close();
      await dir.delete(recursive: true);
    });
    FlutterSecureStoragePlatform.instance =
        TestFlutterSecureStoragePlatform(<String, String>{});
    final credentials = HubDeviceCredentials();
    await credentials.save(
        hubUrl: 'https://hub.example.test', deviceId: 'device', token: 'token');
    final source = (await repository.sources()).single;
    const poster = 'https://example.test/poster.jpg';
    final media = MediaItem(
        id: 'poster-media',
        title: 'Poster',
        description: '',
        year: 2026,
        kind: MediaKind.movie,
        posterUrl: poster,
        backdropUrl: '',
        genres: const [],
        rating: 0,
        duration: const Duration(minutes: 20),
        sourceId: source.id,
        sourceName: source.name,
        remoteId: '42',
        category: '电影');
    final progress = WatchProgress(
        mediaId: media.id,
        episodeLabel: '第2集',
        lineName: '线路一',
        episodeNumber: 2,
        position: const Duration(seconds: 12),
        duration: media.duration,
        updatedAt: DateTime.utc(2026));
    await repository.saveProgress(progress, media: media);
    final sent = <Map<String, dynamic>>[];
    final repairs = <Map<String, dynamic>>[];
    final api = HubSyncApi(
        credentials: credentials,
        client: MockClient((request) async {
          final items = (jsonDecode(request.body) as Map)['items'] as List;
          if (request.url.path.endsWith('/posters')) {
            repairs.addAll(items.cast<Map<String, dynamic>>());
            return http.Response(
                jsonEncode({
                  'code': 200,
                  'data': {'updated': 0}
                }),
                200,
                headers: {'content-type': 'application/json'});
          }
          sent.addAll(items.cast<Map<String, dynamic>>());
          return http.Response(
              jsonEncode({
                'code': 200,
                'message': 'ok',
                'data': {'accepted': items.length, 'ignored': 0}
              }),
              200,
              headers: {'content-type': 'application/json'});
        }));
    final engine = HubSyncEngine(repository: repository, api: api);
    await engine.pushProgress(media, progress);
    expect(sent.map((item) => item['entity']), ['progress', 'history']);
    final automaticProgress = sent.first;
    final automaticHistory = sent.last;
    await repository.setFavorite(media, true);
    sent.clear();
    await engine.pushAll();
    expect(repairs.map((item) => item['entity']),
        containsAll(['history', 'favorite']));
    repairs.clear();
    await engine.pushAll();
    expect(repairs.map((item) => item['entity']),
        containsAll(['history', 'favorite']));
    final fullHistory = sent.singleWhere((item) => item['entity'] == 'history');
    final fullProgress =
        sent.singleWhere((item) => item['entity'] == 'progress');
    for (final item in [
      automaticProgress,
      automaticHistory,
      fullProgress,
      fullHistory
    ]) {
      final payload = item['payload'] as Map;
      final video = payload['video'] as Map;
      expect(payload['source_api'], source.baseUrl);
      expect(video['id'], media.id);
      expect(video['sourceId'], source.id);
      expect(video['remoteId'], media.remoteId);
      expect(video['title'], media.title);
      expect(payload['line_name'], '线路一');
      expect(payload['cineo_index_base'], 0);
      expect(payload['position_ms'], 12000);
    }
    expect(fullProgress['key'], automaticProgress['key']);
    expect(fullProgress['payload']['episode_index'], 1);
    expect(automaticProgress['payload']['episode_index'], 1);
    expect(automaticHistory['key'], fullHistory['key']);
    expect(automaticHistory['payload']['episode_index'],
        fullHistory['payload']['episode_index']);
    expect(fullHistory['payload']['episode_index'], 1);
    for (final entity in ['history', 'progress', 'favorite']) {
      expect(sent.where((item) => item['entity'] == entity), isNotEmpty);
      for (final item in sent.where((item) => item['entity'] == entity)) {
        expect(item['payload']['video']['posterUrl'], poster);
      }
    }
    final db = await repository.hubDatabase;
    final oldHistoryKey = automaticHistory['key'];
    await db.insert('hub_outbox', {
      'entity': 'history',
      'record_key': oldHistoryKey,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
      'deleted': 1,
      'payload_json': null,
      'attempts': 0,
      'next_attempt_at': 0,
    });
    for (final fields in [
      {'line_name': '线路一', 'episode_number': null},
      {'line_name': null, 'episode_number': 2},
    ]) {
      await db.update('progress', fields,
          where: 'media_id=?', whereArgs: [media.id]);
      repairs.clear();
      sent.clear();
      await engine.pushAll();
      expect(repairs.where((item) => item['entity'] == 'history'), isEmpty);
      expect(
          sent.where((item) =>
              item['entity'] == 'history' || item['entity'] == 'progress'),
          isEmpty);
      expect(
          await db.query('hub_sync_state',
              where: 'state_key=?',
              whereArgs: ['local_v2_history:$oldHistoryKey']),
          isNotEmpty);
      await expectLater(engine.pushOutbox(), throwsStateError);
      expect(
          await db.query('hub_outbox',
              where: 'entity=? AND record_key=?',
              whereArgs: ['history', oldHistoryKey]),
          isNotEmpty);
    }
    await db.update('progress', {'line_name': '线路一', 'episode_number': 2},
        where: 'media_id=?', whereArgs: [media.id]);
    await db.update('progress',
        {'updated_at': progress.updatedAt.millisecondsSinceEpoch + 1},
        where: 'media_id=?', whereArgs: [media.id]);
    sent.clear();
    final blocked = await engine.pushAll();
    expect(blocked['error'], isNotNull);
    expect(sent.where((item) => item['entity'] == 'history'), isEmpty);
    expect(
        (await db.query('hub_outbox',
                where: 'entity=? AND record_key=?',
                whereArgs: ['history', oldHistoryKey]))
            .single['deleted'],
        1);
    await expectLater(engine.pushOutbox(), throwsStateError);
    await db.update('media_snapshots', {'kind': MediaKind.series.index},
        where: 'media_id=?', whereArgs: [media.id]);
    await db.update('progress', {'line_name': null, 'episode_number': null},
        where: 'media_id=?', whereArgs: [media.id]);
    repairs.clear();
    await engine.pushAll();
    expect(repairs.where((item) => item['entity'] == 'history'), isEmpty);
    await db.delete('progress', where: 'media_id=?', whereArgs: [media.id]);
    await db.update(
        'hub_outbox', {'deleted': 0, 'payload_json': '{"title":"old"}'},
        where: 'entity=? AND record_key=?',
        whereArgs: ['history', oldHistoryKey]);
    await expectLater(engine.pushOutbox(), throwsStateError);
    expect(
        (await db.query('hub_outbox',
                where: 'entity=? AND record_key=?',
                whereArgs: ['history', oldHistoryKey]))
            .single['deleted'],
        0);
  });
}
