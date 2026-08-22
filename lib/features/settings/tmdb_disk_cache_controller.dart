import 'package:shared_preferences/shared_preferences.dart';

import '../../data/cache/tmdb_disk_cache.dart' as disk;
import 'tmdb_cache_settings.dart';

class TmdbDiskCacheController extends TmdbCacheSettingsController {
  TmdbDiskCacheController({
    required disk.TmdbDiskCache cache,
    Future<SharedPreferences> Function()? preferencesLoader,
  })  : _cache = cache,
        _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const _retentionDaysKey = 'cineo.tmdb.cache_retention_days';

  final disk.TmdbDiskCache _cache;
  final Future<SharedPreferences> Function() _preferencesLoader;

  TmdbCacheStats _stats = const TmdbCacheStats.empty();
  int _retentionDays = 30;
  bool _initialized = false;
  bool _isBusy = false;
  String? _errorMessage;

  @override
  bool get initialized => _initialized;

  @override
  bool get isBusy => _isBusy;

  @override
  String? get errorMessage => _errorMessage;

  @override
  TmdbCacheStats get stats => _stats;

  @override
  int get retentionDays => _retentionDays;

  @override
  Future<void> initialize({bool force = false}) async {
    if ((_initialized && !force) || _isBusy) return;
    await _run(() async {
      final preferences = await _preferencesLoader();
      final stored = preferences.getInt(_retentionDaysKey);
      if (stored != null && stored > 0) _retentionDays = stored;
      await _cache.initialize();
      await _refreshStats();
      _initialized = true;
    });
  }

  @override
  Future<void> setRetentionDays(int days) async {
    if (days <= 0) throw ArgumentError.value(days, 'days', 'must be positive');
    await _run(() async {
      await (await _preferencesLoader()).setInt(_retentionDaysKey, days);
      _retentionDays = days;
      _initialized = true;
      await _refreshStats();
    });
  }

  @override
  Future<void> cleanupExpired() async {
    await _run(() async {
      await _cache.clearExpired(
        maxAge: Duration(days: _retentionDays),
      );
      await _refreshStats();
      _initialized = true;
    });
  }

  @override
  Future<void> clearAll() async {
    await _run(() async {
      await _cache.clearAll();
      await _refreshStats();
      _initialized = true;
    });
  }

  Future<void> _refreshStats() async {
    final value = await _cache.getStats();
    _stats = TmdbCacheStats(
      bytes: value.totalBytes,
      fileCount: value.metadataCount + value.imageCount,
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await action();
    } catch (_) {
      _errorMessage = '无法管理 TMDB 缓存，请稍后重试';
      rethrow;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }
}
