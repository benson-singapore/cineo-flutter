import '../../core/models/media.dart';
import '../../core/models/media_source.dart';
import '../../core/models/source_group_config.dart';
import '../remote/media_category_adapter.dart';

abstract class MediaRepository {
  Future<List<MediaItem>> featured();
  Future<List<MediaItem>> search(String query);
  Future<MediaItem?> getById(String id);
  Future<List<MediaItem>> favorites();
  Future<bool> isFavorite(String mediaId);
  Future<void> setFavorite(MediaItem media, bool isFavorite);
  Future<List<WatchProgress>> watchHistory({bool includeAdult = true});
  Future<void> saveProgress(WatchProgress progress, {MediaItem? media});
  Future<MediaItem?> loadDetails(MediaItem item);
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
  Future<List<SourceGroupConfig>> getSourceGroupConfigs(String sourceId);
  Future<List<SourceGroupConfig>> syncSourceGroupConfigs(String sourceId);
  Future<void> saveSourceGroupConfig(SourceGroupConfig config);
  Future<List<String>> getEnabledGroupIdsForSource(String sourceId);
  Future<void> initializeSourceGroupConfigs(
    String sourceId,
    List<UnifiedSubcategory> leafCategories,
  );
  Future<void> toggleSourceGroupConfig(
    String sourceId,
    String groupId,
    bool enable,
  );
}
