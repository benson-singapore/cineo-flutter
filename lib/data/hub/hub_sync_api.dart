import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class HubApiException implements Exception {
  const HubApiException(this.code, this.safeMessage, {this.retryAfterSeconds});
  final int code;
  final String safeMessage;
  final int? retryAfterSeconds;
  bool get revoked => code == 40301;
  bool get resyncRequired => code == 40900;
  @override
  String toString() => safeMessage;
}

class HubDeviceCredentials {
  HubDeviceCredentials({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  static const _hubUrlKey = 'cineo_hub_url';
  static const _deviceIdKey = 'cineo_hub_device_id';
  static const _tokenKey = 'cineo_hub_device_token';
  static const cloudTmdbKey = 'cineo.hub.cloud_tmdb_key';
  static const cloudSettingsManagedKey = 'cineo.hub.cloud_settings_managed';
  Future<String?> get hubUrl => _storage.read(key: _hubUrlKey);
  Future<String?> get deviceId => _storage.read(key: _deviceIdKey);
  Future<String?> get token => _storage.read(key: _tokenKey);
  Future<bool> get isBound async => (await token)?.isNotEmpty == true;

  Future<void> save(
      {required String hubUrl,
      required String deviceId,
      required String token}) async {
    await _storage.write(key: _hubUrlKey, value: _normalizeHubUrl(hubUrl));
    await _storage.write(key: _deviceIdKey, value: deviceId);
    await _storage.write(key: _tokenKey, value: token);
  }

  Future<void> saveCloudSettings({required String? tmdbKey}) async {
    final normalized = tmdbKey?.trim() ?? '';
    if (normalized.isEmpty) {
      await _storage.delete(key: cloudTmdbKey);
    } else {
      await _storage.write(key: cloudTmdbKey, value: normalized);
    }
    await _storage.write(key: cloudSettingsManagedKey, value: 'true');
  }

  Future<void> clearCloudSettings() async {
    await _storage.delete(key: cloudTmdbKey);
    await _storage.delete(key: cloudSettingsManagedKey);
    await _storage.delete(key: 'cineo.hub.tmdb_language');
    await _storage.delete(key: 'cineo.hub.include_adult');
  }

  Future<void> clear() async {
    await _storage.delete(key: _deviceIdKey);
    await _storage.delete(key: _tokenKey);
  }

  Future<void> saveHubUrl(String value) async =>
      _storage.write(key: _hubUrlKey, value: _normalizeHubUrl(value));
}

class HubSyncApi {
  HubSyncApi({required this.credentials, http.Client? client})
      : _client = client ?? http.Client();
  final HubDeviceCredentials credentials;
  final http.Client _client;

  Future<Map<String, Object?>> bind(
      {required String hubUrl,
      required String pin,
      required String deviceName}) async {
    if (!RegExp(r'^\d{8}$').hasMatch(pin)) {
      throw const FormatException('PIN 必须为 8 位数字');
    }
    final name = deviceName.trim();
    final data = await _request('POST', '/device/bind',
        baseUrl: hubUrl,
        authenticated: false,
        body: {
          'pin': pin,
          'device_name': name.isEmpty
              ? 'Cineo Flutter'
              : name.substring(0, name.length.clamp(0, 64)),
          'device_type': 'flutter',
        });
    final id = data['device_id'];
    final token = data['device_token'];
    if (id is! String || token is! String) {
      throw const HubApiException(50000, 'Hub 响应格式错误');
    }
    await credentials.save(hubUrl: hubUrl, deviceId: id, token: token);
    return data;
  }

  Future<Map<String, Object?>> push(List<Map<String, Object?>> items,
          {String? trigger}) =>
      _request('POST', '/device/sync/push',
          body: {'items': items}, trigger: trigger);
  Future<Map<String, Object?>> pull(int since, {String? trigger}) =>
      _request('GET', '/device/sync/pull?since=$since&limit=500',
          trigger: trigger);
  Future<Map<String, Object?>> rebuild(
          {required int generation, int cursor = 0}) =>
      _request('POST', '/device/sync/rebuild', body: {
        'known_generation': generation,
        'cursor': cursor,
        'limit': 500
      });
  Future<Map<String, Object?>> settings() =>
      _request('GET', '/device/settings');

  Future<Map<String, Object?>> _request(String method, String route,
      {String? baseUrl,
      Map<String, Object?>? body,
      String? trigger,
      bool authenticated = true}) async {
    final root = baseUrl ?? await credentials.hubUrl;
    if (root == null || root.isEmpty) {
      throw const HubApiException(40000, '请先设置 Hub 地址');
    }
    final normalized = _normalizeHubUrl(root);
    final apiBase =
        normalized.endsWith('/api/v1') ? normalized : '$normalized/api/v1';
    final uri = Uri.parse('$apiBase$route');
    final headers = <String, String>{'Accept': 'application/json'};
    if (trigger != null) headers['X-Sync-Trigger'] = trigger;
    if (body != null) {
      headers['Content-Type'] = 'application/json; charset=utf-8';
    }
    if (authenticated) {
      final token = await credentials.token;
      if (token == null || token.isEmpty) {
        throw const HubApiException(40100, '设备尚未绑定');
      }
      headers['Authorization'] = 'Bearer $token';
    }
    try {
      final request = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) request.body = jsonEncode(body);
      final response = await http.Response.fromStream(
          await _client.send(request).timeout(const Duration(seconds: 20)));
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['code'] != 200) {
        final code = decoded is Map ? (decoded['code'] as num?)?.toInt() : null;
        throw HubApiException(
            code ?? response.statusCode * 100, _safeMessage(code),
            retryAfterSeconds: int.tryParse(
                  response.headers['retry-after'] ?? '',
                ) ??
                ((decoded['data'] as Map?)?['retry_after_seconds'] as num?)
                    ?.toInt());
      }
      final data = decoded['data'];
      if (data == null) return <String, Object?>{};
      if (data is! Map) throw const HubApiException(50000, 'Hub 响应格式错误');
      return data.cast<String, Object?>();
    } on HubApiException {
      rethrow;
    } on TimeoutException {
      throw const HubApiException(50000, 'Hub 请求超时');
    } on FormatException {
      throw const HubApiException(50000, 'Hub 响应格式错误');
    } catch (_) {
      throw const HubApiException(50000, 'Hub 暂时不可用');
    }
  }

  String _safeMessage(int? code) => switch (code) {
        40001 => 'PIN 无效或已过期',
        40301 => '设备已解绑，请重新绑定',
        40900 => '需要重新同步云端数据',
        42900 || 42901 => 'Hub 请求受限，请稍后重试',
        _ => 'Hub 请求失败（${code ?? '未知错误'}）',
      };
}

String _normalizeHubUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      !{'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw const FormatException('Hub 地址无效');
  }
  var result =
      uri.replace(path: uri.path.replaceFirst(RegExp(r'/+$'), '')).toString();
  if (result.endsWith('/')) result = result.substring(0, result.length - 1);
  return result;
}
