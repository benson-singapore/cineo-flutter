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
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  test('pull restores TV metadata and repairs existing placeholder', () async {
    final dir = await Directory.systemTemp.createTemp('hub_metadata_');
    final repository = LocalMediaRepository(databasePath: '${dir.path}/db');
    addTearDown(() async {
      await repository.close();
      await dir.delete(recursive: true);
    });
    FlutterSecureStoragePlatform.instance =
        TestFlutterSecureStoragePlatform(<String, String>{});
    final credentials = HubDeviceCredentials();
    await credentials.save(
        hubUrl: 'https://hub.example.test', deviceId: 'test', token: 'test');
    final source = (await repository.sources()).single;
    final key =
        hubMediaKey(sourceKey: hubSourceKey(source.baseUrl), vodId: '42');
    var pulls = 0;
    final engine = HubSyncEngine(
        repository: repository,
        api: HubSyncApi(
            credentials: credentials,
            client: MockClient((request) async {
              Object data;
              if (request.url.path.endsWith('/pull')) {
                pulls++;
                data = {
                  'items': pulls == 1
                      ? [
                          {
                            'entity': 'history',
                            'key': key,
                            'updated_at': 1000,
                            'deleted': false,
                            'payload': {
                              'video': {
                                'title': '测试影片',
                                'posterUrl': 'https://example.test/poster.jpg'
                              },
                              'position_ms': 1000,
                              'duration_ms': 10000
                            }
                          }
                        ]
                      : [],
                  'next_seq': 1,
                  'generation': 1,
                  'has_more': false
                };
              } else {
                data = {'preferences': <String, Object>{}, 'tmdb_key': null};
              }
              return http.Response(
                  jsonEncode({'code': 200, 'message': 'ok', 'data': data}), 200,
                  headers: const {
                    'content-type': 'application/json; charset=utf-8'
                  });
            })));
    await engine.pullAndApply();
    final history = await repository.watchHistory();
    final media = (await repository.getById(history.single.mediaId))!;
    expect(media.id, '${source.id}:42');
    expect(media.title, '测试影片');
    expect(media.posterUrl, 'https://example.test/poster.jpg');
    final db = await repository.hubDatabase;
    await db.update('media_snapshots', {'title': 'Hub 媒体', 'poster_url': ''},
        where: 'media_id=?', whereArgs: [media.id]);
    await engine.pullAndApply();
    final repaired = (await repository.getById(media.id))!;
    expect(repaired.title, '测试影片');
    expect(repaired.posterUrl, 'https://example.test/poster.jpg');
  });
}
