import 'dart:convert';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cineo_flutter/data/hub/hub_sync_api.dart';

void main() {
  test('lists sessions and submits complete text with device authentication',
      () async {
    FlutterSecureStoragePlatform.instance =
        TestFlutterSecureStoragePlatform({});
    final credentials = HubDeviceCredentials();
    await credentials.save(
        hubUrl: 'https://hub.example', deviceId: 'phone', token: 'secret');
    final seen = <http.Request>[];
    final api = HubSyncApi(
        credentials: credentials,
        client: MockClient((request) async {
          seen.add(request);
          return http.Response(
              jsonEncode({
                'code': 200,
                'data': request.method == 'GET'
                    ? {
                        'sessions': [
                          {'id': 'tv-session'}
                        ]
                      }
                    : {}
              }),
              200);
        }));
    expect((await api.inputSessions())['sessions'], hasLength(1));
    await api.submitInput('tv-session', '电影 🎬');
    expect(seen[0].url.path, '/api/v1/device/input-sessions');
    expect(seen[1].url.path, '/api/v1/device/input-sessions/tv-session/submit');
    expect(seen[1].headers['Authorization'], 'Bearer secret');
    expect(jsonDecode(seen[1].body), {'text': '电影 🎬'});
  });
}
