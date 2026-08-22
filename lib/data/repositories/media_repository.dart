import '../../core/models/media.dart';
import '../../core/models/media_source.dart';

abstract class MediaRepository {
  Future<List<MediaItem>> featured();
  Future<List<MediaItem>> search(String query);
  Future<MediaItem?> getById(String id);
  Future<List<MediaItem>> favorites();
  Future<bool> isFavorite(String mediaId);
  Future<void> setFavorite(MediaItem media, bool isFavorite);
  Future<List<WatchProgress>> watchHistory();
  Future<void> saveProgress(WatchProgress progress, {MediaItem? media});
  Future<void> removeHistory(String mediaId);
  Future<void> clearHistory();
  Future<List<String>> searchHistory();
  Future<void> addSearchHistory(String query);
  Future<List<MediaSource>> sources();
  Future<void> saveSource(MediaSource source);
  Future<void> deleteSource(String id);
  Future<bool> testSource(MediaSource source);
  Future<MediaSource?> defaultSource();
  Future<void> setDefaultSource(String id);
}
