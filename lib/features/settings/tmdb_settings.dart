import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TMDBSettings extends ChangeNotifier {
  TMDBSettings({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const tokenStorageKey = 'cineo.tmdb.api_token';

  final FlutterSecureStorage _secureStorage;

  bool _initialized = false;
  bool _configured = false;
  bool _isBusy = false;
  bool _cloudManaged = false;
  String _cloudLanguage = 'zh-CN';
  bool _cloudIncludeAdult = false;
  String? _errorMessage;

  bool get initialized => _initialized;
  bool get configured => _configured;
  bool get isBusy => _isBusy;
  String? get errorMessage => _errorMessage;
  bool get isCloudManaged => _cloudManaged;
  String get cloudLanguage => _cloudLanguage;
  bool get cloudIncludeAdult => _cloudIncludeAdult;

  Future<void> applyCloudSettings({
    required String? tmdbKey,
    required String language,
    required bool includeAdult,
  }) async {
    final key = tmdbKey?.trim() ?? '';
    if (key.isEmpty) {
      await _secureStorage.delete(key: 'cineo.hub.cloud_tmdb_key');
    } else {
      await _secureStorage.write(key: 'cineo.hub.cloud_tmdb_key', value: key);
    }
    await _secureStorage.write(
        key: 'cineo.hub.cloud_settings_managed', value: 'true');
    await _secureStorage.write(key: 'cineo.hub.tmdb_language', value: language);
    await _secureStorage.write(
        key: 'cineo.hub.include_adult', value: '$includeAdult');
    _cloudManaged = true;
    _cloudLanguage = language;
    _cloudIncludeAdult = includeAdult;
    _configured = key.isNotEmpty;
    _initialized = true;
    notifyListeners();
  }

  Future<void> clearCloudSettings() async {
    await _secureStorage.delete(key: 'cineo.hub.cloud_tmdb_key');
    await _secureStorage.delete(key: 'cineo.hub.cloud_settings_managed');
    await _secureStorage.delete(key: 'cineo.hub.tmdb_language');
    await _secureStorage.delete(key: 'cineo.hub.include_adult');
    final token = await _secureStorage.read(key: tokenStorageKey);
    _cloudManaged = false;
    _configured = token?.trim().isNotEmpty ?? false;
    notifyListeners();
  }

  /// Reads the saved token only when a network request needs it.
  ///
  /// The value is deliberately not cached or exposed through widget state.
  Future<String?> readTokenForRequest() async {
    try {
      final managed = _cloudManaged ||
          await _secureStorage.read(key: 'cineo.hub.cloud_settings_managed') ==
              'true';
      final key = managed ? 'cineo.hub.cloud_tmdb_key' : tokenStorageKey;
      final token = await _secureStorage.read(key: key);
      final normalizedToken = token?.trim() ?? '';
      return normalizedToken.isEmpty ? null : normalizedToken;
    } catch (_) {
      return null;
    }
  }

  Future<void> initialize({bool force = false}) async {
    if ((_initialized && !force) || _isBusy) return;

    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final token = await _secureStorage.read(key: tokenStorageKey);
      final cloudManaged =
          await _secureStorage.read(key: 'cineo.hub.cloud_settings_managed');
      final cloudToken =
          await _secureStorage.read(key: 'cineo.hub.cloud_tmdb_key');
      _cloudManaged = cloudManaged == 'true';
      _cloudLanguage =
          await _secureStorage.read(key: 'cineo.hub.tmdb_language') ?? 'zh-CN';
      _cloudIncludeAdult =
          await _secureStorage.read(key: 'cineo.hub.include_adult') == 'true';
      _configured = _cloudManaged
          ? cloudToken?.trim().isNotEmpty ?? false
          : token?.trim().isNotEmpty ?? false;
      _initialized = true;
    } catch (_) {
      _initialized = true;
      _errorMessage = '无法读取 TMDB 配置，请重试';
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> saveToken(String token) async {
    if (_cloudManaged) {
      _errorMessage = 'TMDB 配置由云端管理';
      notifyListeners();
      throw StateError(_errorMessage!);
    }
    final normalizedToken = token.trim();
    if (normalizedToken.isEmpty) {
      _errorMessage = '请输入有效的 TMDB API Token';
      notifyListeners();
      throw ArgumentError.value(
        token,
        'token',
        'TMDB API Token cannot be empty',
      );
    }

    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _secureStorage.write(
        key: tokenStorageKey,
        value: normalizedToken,
      );
      _configured = true;
      _initialized = true;
    } catch (_) {
      _errorMessage = '无法保存 TMDB 配置，请重试';
      rethrow;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> clearToken() async {
    if (_cloudManaged) {
      _errorMessage = 'TMDB 配置由云端管理';
      notifyListeners();
      throw StateError(_errorMessage!);
    }
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _secureStorage.delete(key: tokenStorageKey);
      _configured = false;
      _initialized = true;
    } catch (_) {
      _errorMessage = '无法清除 TMDB 配置，请重试';
      rethrow;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }
}
