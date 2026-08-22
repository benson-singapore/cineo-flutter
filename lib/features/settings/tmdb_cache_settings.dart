import 'package:flutter/foundation.dart';

/// A snapshot of the files stored by the TMDB image and metadata cache.
class TmdbCacheStats {
  const TmdbCacheStats({
    required this.bytes,
    required this.fileCount,
  });

  const TmdbCacheStats.empty()
      : bytes = 0,
        fileCount = 0;

  final int bytes;
  final int fileCount;
}

/// Storage-agnostic contract used by the TMDB settings page.
///
/// The concrete implementation can live beside the file cache and may use
/// path_provider, a database, or another local storage strategy. The settings
/// page only needs these observable values and operations.
abstract class TmdbCacheSettingsController extends ChangeNotifier {
  bool get initialized;

  bool get isBusy;

  String? get errorMessage;

  TmdbCacheStats get stats;

  int get retentionDays;

  Future<void> initialize({bool force = false});

  Future<void> setRetentionDays(int days);

  Future<void> cleanupExpired();

  Future<void> clearAll();
}

const tmdbCacheRetentionPresets = <int>[7, 30, 90, 365];

String tmdbCacheRetentionLabel(int days) {
  if (days == 1) return '1 天';
  if (days % 30 == 0 && days < 365) return '${days ~/ 30} 个月';
  if (days == 365) return '1 年';
  return '$days 天';
}

String formatTmdbCacheSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
