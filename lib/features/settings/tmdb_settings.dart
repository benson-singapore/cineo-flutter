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
  String? _errorMessage;

  bool get initialized => _initialized;
  bool get configured => _configured;
  bool get isBusy => _isBusy;
  String? get errorMessage => _errorMessage;

  /// Reads the saved token only when a network request needs it.
  ///
  /// The value is deliberately not cached or exposed through widget state.
  Future<String?> readTokenForRequest() async {
    try {
      final token = await _secureStorage.read(key: tokenStorageKey);
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
      _configured = token?.trim().isNotEmpty ?? false;
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
