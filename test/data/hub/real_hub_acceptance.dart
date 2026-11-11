import 'dart:convert';
import 'dart:io';

import 'package:cineo_flutter/data/hub/hub_sync_keys.dart';
import 'package:http/http.dart' as http;

Future<void> main() async {
  final root = Platform.environment['HUB_API_URL'] ?? 'http://127.0.0.1:8080';
  final username = Platform.environment['HUB_ADMIN_USERNAME'];
  final password = Platform.environment['HUB_ADMIN_PASSWORD'];
  if (username == null || password == null) {
    stderr.writeln(
        'Set HUB_ADMIN_USERNAME and HUB_ADMIN_PASSWORD in the environment.');
    exitCode = 2;
    return;
  }
  final client = http.Client();
  final api = Uri.parse('${root.replaceFirst(RegExp(r'/+$'), '')}/api/v1/');
  Uri endpoint(String path) =>
      api.resolve(path.replaceFirst(RegExp(r'^/'), ''));
  String? cookie;
  String? csrf;
  String? deviceToken;
  String? deviceId;
  String? pushedSiteKey;
  String? adminSiteKey;
  final suffix = DateTime.now().microsecondsSinceEpoch.toString();
  final siteApi =
      'https://flutter-acceptance-$suffix.example/vod?key=masked-$suffix';
  final sourceKey = hubSourceKey(siteApi);
  pushedSiteKey = sourceKey;
  final historyKey =
      hubMediaKey(sourceKey: sourceKey, vodId: 'history-$suffix');
  final favoriteKey =
      hubMediaKey(sourceKey: sourceKey, vodId: 'favorite-$suffix');

  Future<Map<String, dynamic>> request(String method, String path,
      {Map<String, Object?>? body,
      bool admin = false,
      bool device = false}) async {
    final req = http.Request(method, endpoint(path));
    req.headers['Accept'] = 'application/json';
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    if (admin && cookie != null) {
      req.headers['Cookie'] = cookie!;
      if (csrf != null && method != 'GET') req.headers['X-CSRF-Token'] = csrf!;
    }
    if (device && deviceToken != null) {
      req.headers['Authorization'] = 'Bearer $deviceToken';
    }
    final response = await http.Response.fromStream(await client.send(req));
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (admin && path == '/admin/auth/login' && response.statusCode == 200) {
      cookie = (response.headers['set-cookie'] ?? '').split(';').first;
      csrf = (decoded['data'] as Map<String, dynamic>)['csrf_token'] as String?;
    }
    if (decoded['code'] != 200) {
      throw StateError('$method $path returned code ${decoded['code']}');
    }
    return (decoded['data'] as Map?)?.cast<String, dynamic>() ?? {};
  }

  var stage = 'login';
  try {
    stage = 'admin login';
    await request('POST', '/admin/auth/login',
        body: {'username': username, 'password': password}, admin: true);
    stage = 'PIN creation';
    final pinData = await request('POST', '/admin/pins', admin: true);
    final pin = pinData['pin'] as String;
    stage = 'device bind';
    final bound = await request('POST', '/device/bind', body: {
      'pin': pin,
      'device_name': 'Flutter acceptance $suffix',
      'device_type': 'flutter',
    });
    deviceId = bound['device_id'] as String;
    deviceToken = bound['device_token'] as String;

    final now = DateTime.now().millisecondsSinceEpoch;
    stage = 'device push';
    await request('POST', '/device/sync/push', device: true, body: {
      'items': [
        {
          'entity': 'site',
          'key': sourceKey,
          'updated_at': now,
          'deleted': false,
          'payload': {
            'name': 'Flutter acceptance $suffix',
            'api': siteApi,
            'detail_url': null,
            'enabled': true,
            'is_adult': false,
            'is_default': false,
            'site_type': 'maccms',
            'cover_mode': 'portrait',
            'cache_ttl_seconds': null,
          },
        },
        {
          'entity': 'favorite',
          'key': favoriteKey,
          'updated_at': now,
          'deleted': false,
          'payload': {
            'title': 'Flutter favorite $suffix',
            'category': '电影',
            'added_at': now
          },
        },
        {
          'entity': 'history',
          'key': historyKey,
          'updated_at': now,
          'deleted': false,
          'payload': {
            'title': 'Flutter history $suffix',
            'line_name': 'line 1',
            'episode_index': 2,
            'position_ms': 120000,
            'duration_ms': 3600000
          },
        },
        {
          'entity': 'progress',
          'key': historyKey,
          'updated_at': now,
          'deleted': false,
          'payload': {
            'title': 'Flutter history $suffix',
            'line_name': 'line 1',
            'episode_index': 2,
            'position_ms': 120000,
            'duration_ms': 3600000
          },
        },
      ],
    });
    final devicePull = await request(
        'GET', '/device/sync/pull?since=0&limit=500',
        device: true);
    final progressItems = (devicePull['items'] as List).cast<Map>();
    if (!progressItems.any(
        (row) => row['entity'] == 'progress' && row['key'] == historyKey)) {
      throw StateError(
          'device pull did not include the pushed progress record');
    }
    final adminSites =
        await request('GET', '/admin/sites?page=1&page_size=100', admin: true);
    final siteRows = (adminSites['items'] as List).cast<Map>();
    final pushed = siteRows
        .cast<Map<String, dynamic>>()
        .firstWhere((row) => row['source_key'] == sourceKey);
    final listedApi = pushed['api'] ?? (pushed['site'] as Map?)?['api'];
    if (listedApi is! String) {
      throw StateError('admin site list fields: ${pushed.keys.join(',')}');
    }
    if (listedApi.contains('masked-$suffix')) {
      throw StateError('admin site list revealed its API query');
    }
    final favorites =
        await request('GET', '/admin/favorites?limit=500', admin: true);
    final favoriteRows = (favorites['items'] as List).cast<Map>();
    if (!favoriteRows.any((row) => row['key'] == favoriteKey)) {
      throw StateError('admin favorites did not include the pushed record');
    }
    final history =
        await request('GET', '/admin/history?limit=500', admin: true);
    final historyRows = (history['items'] as List).cast<Map>();
    if (!historyRows.any((row) => row['key'] == historyKey)) {
      throw StateError('admin history did not include the pushed record');
    }

    final adminSite = await request('POST', '/admin/sites', admin: true, body: {
      'name': 'Admin acceptance $suffix',
      'api': 'https://admin-acceptance-$suffix.example/vod',
      'enabled': true,
      'is_adult': false,
      'is_default': false,
      'site_type': 'json',
      'cover_mode': 'landscape',
      'cache_ttl_seconds': 321,
    });
    adminSiteKey = adminSite['source_key'] as String;
    final pulled = await request('GET', '/device/sync/pull?since=0&limit=500',
        device: true);
    final pulledItems = (pulled['items'] as List).cast<Map<String, dynamic>>();
    if (!pulledItems.any(
        (item) => item['entity'] == 'site' && item['key'] == adminSiteKey)) {
      throw StateError('device pull did not include the admin-created site');
    }

    await request('DELETE', '/admin/devices/$deviceId', admin: true);
    final revokedReq =
        http.Request('GET', endpoint('/device/sync/pull?since=0&limit=500'))
          ..headers['Authorization'] = 'Bearer $deviceToken';
    final revoked =
        await http.Response.fromStream(await client.send(revokedReq));
    final revokedEnvelope = jsonDecode(revoked.body) as Map<String, dynamic>;
    if (revokedEnvelope['code'] != 40301) {
      throw StateError(
          'revoked device returned code ${revokedEnvelope['code']}');
    }
    stdout.writeln(
        'Live Hub acceptance passed: bind, push site/favorite/history/progress, admin read site/favorite/history, progress pull, admin site pull, revoke (40301).');
    stdout.writeln('Site API query remained masked in the admin site list.');
  } catch (error, stackTrace) {
    stderr.writeln('Live Hub acceptance failed during $stage: $error');
    stderr.writeln(stackTrace);
    exitCode = 1;
  } finally {
    if (deviceId != null && cookie != null) {
      try {
        await request('DELETE', '/admin/devices/$deviceId', admin: true);
      } catch (_) {}
    }
    if (cookie != null) {
      for (final key in [favoriteKey, historyKey]) {
        try {
          await request('DELETE', '/admin/favorites/$key', admin: true);
        } catch (_) {}
        try {
          await request('DELETE', '/admin/history/$key', admin: true);
        } catch (_) {}
      }
    }
    for (final key in [pushedSiteKey, adminSiteKey]) {
      if (key != null && csrf != null && cookie != null) {
        try {
          await request('DELETE', '/admin/sites/$key', admin: true);
        } catch (_) {}
      }
    }
    client.close();
  }
}
