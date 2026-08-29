import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../../core/demo/demo_content.dart';
import '../../core/models/home_category_rail.dart';
import '../../core/models/media.dart';
import '../../core/models/media_source.dart';
import '../../core/models/paged_media.dart';
import '../../core/models/source_group_config.dart';
import '../remote/mac_cms_client.dart';
import '../remote/media_category_adapter.dart';
import 'media_repository.dart';

/// SQLite-backed storage for local user state.
///
/// The catalog is supplied by the caller because this repository stores local
/// state, while search and media metadata can come from any authorized source.
class LocalMediaRepository implements MediaRepository {
  LocalMediaRepository({
    this.catalog = const <MediaItem>[],
    this.databasePath,
    MacCmsClient? macCmsClient,
  }) : _macCmsClient = macCmsClient ?? MacCmsClient();

  final List<MediaItem> catalog;
  final String? databasePath;
  final MacCmsClient _macCmsClient;
  late final Future<Database> _database = _openDatabase();

  static const _builtInRuyiSource = MediaSource(
    id: 'built-in-ruyi',
    name: '如意视频源',
    type: MediaSourceType.macCmsApi,
    baseUrl: 'https://cj.rycjapi.com/api.php/provide/vod',
    enabled: true,
    isDefault: true,
  );

  Future<Database> _openDatabase() async {
    final resolvedPath = databasePath ??
        path.join(await getDatabasesPath(), 'cineo_local_media.db');
    final database = await openDatabase(
      resolvedPath,
      version: 9,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE favorites (
            media_id TEXT PRIMARY KEY,
            created_at INTEGER NOT NULL
          )
        ''');
        await database.execute('''
          CREATE TABLE progress (
            progress_key TEXT PRIMARY KEY,
            media_id TEXT NOT NULL,
            episode_id TEXT,
            episode_label TEXT,
            episode_number INTEGER,
            episode_count INTEGER,
            position_ms INTEGER NOT NULL,
            duration_ms INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await database.execute('''
          CREATE TABLE sources (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            type INTEGER NOT NULL,
            base_url TEXT NOT NULL,
            enabled INTEGER NOT NULL,
          last_checked_at INTEGER,
            last_error TEXT,
            external_id TEXT,
            detail_url TEXT,
            is_adult INTEGER NOT NULL DEFAULT 0,
            cache_ttl_seconds INTEGER,
            is_default INTEGER NOT NULL DEFAULT 0,
            last_latency_ms INTEGER,
            is_favorite INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await database.execute('''
          CREATE TABLE search_history (
            query TEXT PRIMARY KEY,
            updated_at INTEGER NOT NULL
          )
        ''');
        await database.execute('''
          CREATE TABLE media_source_preferences (
            media_key TEXT PRIMARY KEY,
            source_id TEXT NOT NULL,
            remote_id TEXT NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await _createMediaSnapshotsTable(database);
        await _createHomeCategoryCacheTable(database);
        await _createSourceGroupConfigTable(database);
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await database
              .execute('ALTER TABLE sources ADD COLUMN external_id TEXT');
          await database
              .execute('ALTER TABLE sources ADD COLUMN detail_url TEXT');
          await database.execute(
            'ALTER TABLE sources ADD COLUMN is_adult INTEGER NOT NULL DEFAULT 0',
          );
          await database.execute(
            'ALTER TABLE sources ADD COLUMN cache_ttl_seconds INTEGER',
          );
        }
        if (oldVersion < 3) {
          await database.execute(
            'ALTER TABLE sources ADD COLUMN is_default INTEGER NOT NULL DEFAULT 0',
          );
          await database.execute(
            'ALTER TABLE sources ADD COLUMN last_latency_ms INTEGER',
          );
        }
        if (oldVersion < 4) {
          await database.execute(
            'ALTER TABLE sources ADD COLUMN is_favorite INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 5) {
          await database.execute('''
            CREATE TABLE media_source_preferences (
              media_key TEXT PRIMARY KEY,
              source_id TEXT NOT NULL,
              remote_id TEXT NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
        }
        if (oldVersion < 6) await _createMediaSnapshotsTable(database);
        if (oldVersion < 7) {
          await database
              .execute('ALTER TABLE progress ADD COLUMN episode_label TEXT');
          await database.execute(
              'ALTER TABLE progress ADD COLUMN episode_number INTEGER');
          await database
              .execute('ALTER TABLE progress ADD COLUMN episode_count INTEGER');
        }
        if (oldVersion < 8) {
          await _createHomeCategoryCacheTable(database);
        }
        if (oldVersion < 9) {
          await _createSourceGroupConfigTable(database);
        }
      },
    );
    // A previous build may have recorded version 9 without creating the
    // table. Re-checking it here repairs that state without touching data.
    await _ensureSourceGroupConfigTable(database);
    await _ensureBuiltInSource(database);
    return database;
  }

  /// A fresh installation starts with one usable source. Existing source
  /// configurations are user-owned, so this never replaces or removes them.
  Future<void> _ensureBuiltInSource(Database database) async {
    final rows = await database.query('sources', columns: ['id'], limit: 1);
    if (rows.isNotEmpty) return;
    await database.insert('sources', _sourceToRow(_builtInRuyiSource));
  }

  Future<Database> get _db => _database;

  @override
  Future<List<MediaItem>> featured() async {
    final source = await defaultSource();
    if (source == null) return catalog.take(10).toList();
    return _macCmsClient.list(source);
  }

  @override
  Future<List<MediaItem>> search(String query) async {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return featured();
    final source = await defaultSource();
    if (source != null) {
      return _macCmsClient.list(source, query: normalizedQuery);
    }
    return catalog.where((media) {
      final searchable = [
        media.title,
        media.description,
        ...media.genres,
      ].join(' ').toLowerCase();
      return searchable.contains(normalizedQuery);
    }).toList();
  }

  @override
  Future<MediaItem?> getById(String id) async {
    final rows = await (await _db).query(
      'media_snapshots',
      where: 'media_id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isNotEmpty) return _mediaFromSnapshotRow(rows.single);
    for (final media in catalog) {
      if (media.id == id) return media;
    }
    return _restoreLegacySnapshot(id);
  }

  Future<MediaItem?> _restoreLegacySnapshot(String mediaId) async {
    final separator = mediaId.indexOf(':');
    if (separator < 1 || separator == mediaId.length - 1) return null;
    final sourceId = mediaId.substring(0, separator);
    final remoteId = mediaId.substring(separator + 1);
    final sourceRows = await (await _db).query(
      'sources',
      where: 'id = ? AND enabled = 1',
      whereArgs: [sourceId],
      limit: 1,
    );
    if (sourceRows.isEmpty) return null;
    final source = _sourceFromRow(sourceRows.single);
    if (source.type != MediaSourceType.macCmsApi &&
        source.type != MediaSourceType.jsonApi) {
      return null;
    }
    try {
      final media = await _macCmsClient.detail(source, remoteId);
      if (media == null) return null;
      await _saveMediaSnapshot(media, database: await _db);
      return media;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<MediaItem>> favorites() async {
    final rows = await (await _db).query(
      'favorites',
      orderBy: 'created_at DESC',
    );
    final items = await Future.wait(
      rows.map((row) => getById(row['media_id'] as String)),
    );
    return items.whereType<MediaItem>().toList(growable: false);
  }

  /// Restores the last successful homepage snapshot without contacting a
  /// remote source. Missing media snapshots are ignored so a partial cache
  /// never prevents the rest of the homepage from appearing.
  Future<List<HomeCategoryRail>> cachedHomeCategoryRails() async {
    final rows = await (await _db).query(
      'home_category_rails',
      orderBy: 'position ASC',
    );
    final rails = <HomeCategoryRail>[];
    for (final row in rows) {
      final mediaIds = _decodeStringList(row['media_ids_json']);
      final items = await Future.wait(
        mediaIds.map((mediaId) => getById(mediaId)),
      );
      rails.add(
        HomeCategoryRail(
          title: row['title'] as String,
          categoryIds: _decodeStringList(row['category_ids_json']),
          items: items.whereType<MediaItem>().toList(growable: false),
        ),
      );
    }
    return rails;
  }

  /// Persists the complete homepage result as one replaceable snapshot.
  /// User state such as favorites and progress remains in its own tables.
  Future<void> saveHomeCategoryRails(List<HomeCategoryRail> rails) async {
    final database = await _db;
    await database.transaction((transaction) async {
      for (final rail in rails) {
        for (final item in rail.items) {
          await _saveMediaSnapshot(item, database: transaction);
        }
      }
      await transaction.delete('home_category_rails');
      for (var index = 0; index < rails.length; index++) {
        final rail = rails[index];
        await transaction.insert('home_category_rails', {
          'rail_key': '$index:${rail.title}',
          'title': rail.title,
          'category_ids_json': jsonEncode(rail.categoryIds),
          'media_ids_json': jsonEncode(
            rail.items.map((item) => item.id).toList(growable: false),
          ),
          'position': index,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        });
      }
    });
  }

  @override
  Future<bool> isFavorite(String mediaId) async {
    final rows = await (await _db).query(
      'favorites',
      columns: ['media_id'],
      where: 'media_id = ?',
      whereArgs: [mediaId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  @override
  Future<void> setFavorite(MediaItem media, bool isFavorite) async {
    final database = await _db;
    if (isFavorite) {
      await _saveMediaSnapshot(media, database: database);
      await database.insert(
        'favorites',
        {
          'media_id': media.id,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else {
      await database.delete(
        'favorites',
        where: 'media_id = ?',
        whereArgs: [media.id],
      );
    }
  }

  @override
  Future<List<WatchProgress>> watchHistory({bool includeAdult = true}) async {
    final database = await _db;
    final rows = includeAdult
        ? await database.query('progress', orderBy: 'updated_at DESC')
        : await database.rawQuery('''
            SELECT progress.*
            FROM progress
            LEFT JOIN media_snapshots
              ON media_snapshots.media_id = progress.media_id
            LEFT JOIN sources
              ON sources.id = media_snapshots.source_id
            WHERE COALESCE(sources.is_adult, 0) = 0
            ORDER BY progress.updated_at DESC
          ''');
    return rows.map(_progressFromRow).toList();
  }

  @override
  Future<void> saveProgress(WatchProgress progress, {MediaItem? media}) async {
    final episodeKey = progress.episodeId ?? '';
    final database = await _db;
    if (media != null) await _saveMediaSnapshot(media, database: database);
    await database.insert(
      'progress',
      {
        'progress_key': '${progress.mediaId}:$episodeKey',
        'media_id': progress.mediaId,
        'episode_id': progress.episodeId,
        'episode_label': progress.episodeLabel,
        'episode_number': progress.episodeNumber,
        'episode_count': progress.episodeCount,
        'position_ms': progress.position.inMilliseconds,
        'duration_ms': progress.duration.inMilliseconds,
        'updated_at': progress.updatedAt.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> removeHistory(String mediaId) async {
    await (await _db).delete(
      'progress',
      where: 'media_id = ?',
      whereArgs: [mediaId],
    );
  }

  @override
  Future<void> clearHistory() async {
    await (await _db).delete('progress');
  }

  @override
  Future<List<String>> searchHistory() async {
    final rows = await (await _db).query(
      'search_history',
      orderBy: 'updated_at DESC',
    );
    return rows.map((row) => row['query'] as String).toList();
  }

  @override
  Future<void> addSearchHistory(String query) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) return;
    await (await _db).insert(
      'search_history',
      {
        'query': normalizedQuery,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<MediaSource>> sources() async {
    final rows =
        await (await _db).query('sources', orderBy: 'name COLLATE NOCASE');
    return rows.map(_sourceFromRow).toList();
  }

  @override
  Future<void> saveSource(MediaSource source) async {
    final database = await _db;
    await database.transaction((transaction) async {
      if (source.isDefault) {
        await transaction.update('sources', {'is_default': 0});
      }
      await transaction.insert(
        'sources',
        _sourceToRow(source),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  @override
  Future<void> deleteSource(String id) async {
    await (await _db).delete('sources', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<bool> testSource(MediaSource source) async {
    if (source.type == MediaSourceType.demo) return true;
    final uri = Uri.tryParse(source.baseUrl.trim());
    if (uri == null || !{'http', 'https'}.contains(uri.scheme.toLowerCase())) {
      return false;
    }
    if (source.type == MediaSourceType.direct) {
      final lowerPath = uri.path.toLowerCase();
      return lowerPath.endsWith('.m3u8') || lowerPath.endsWith('.mp4');
    }
    final result = await _macCmsClient.probe(source);
    await saveSource(source.copyWith(
      lastCheckedAt: DateTime.now(),
      lastLatencyMs: result.latencyMs,
      lastError: result.error,
      clearLastError: result.isReachable,
    ));
    return result.isReachable;
  }

  @override
  Future<MediaSource?> defaultSource() async {
    final rows = await (await _db).query(
      'sources',
      where: 'is_default = 1 AND enabled = 1',
      limit: 1,
    );
    return rows.isEmpty ? null : _sourceFromRow(rows.single);
  }

  @override
  Future<void> setDefaultSource(String id) async {
    final database = await _db;
    await database.transaction((transaction) async {
      final row = await transaction.query('sources',
          where: 'id = ?', whereArgs: [id], limit: 1);
      if (row.isEmpty) throw StateError('未找到视频源');
      final source = _sourceFromRow(row.single);
      if (!source.enabled ||
          (source.type != MediaSourceType.macCmsApi &&
              source.type != MediaSourceType.jsonApi)) {
        throw StateError('仅可将已启用的 API 视频源设为默认');
      }
      await transaction.update('sources', {'is_default': 0});
      await transaction.update('sources', {'is_default': 1},
          where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Saves or updates a source group configuration in the database.
  @override
  Future<void> saveSourceGroupConfig(SourceGroupConfig config) async {
    final database = await _db;
    await database.insert(
      'source_group_configs',
      {
        'source_id': config.sourceId,
        'category_id': config.categoryId,
        'category_name': config.categoryName,
        'is_enabled': config.isEnabled ? 1 : 0,
        'created_at': config.createdAt.millisecondsSinceEpoch,
        'updated_at': config.updatedAt.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Retrieves all category configurations for a source.
  @override
  Future<List<SourceGroupConfig>> getSourceGroupConfigs(String sourceId) async {
    final database = await _db;
    final rows = await database.query(
      'source_group_configs',
      where: 'source_id = ?',
      whereArgs: [sourceId],
      orderBy: 'category_name',
    );
    return rows.map(_groupConfigFromRow).toList();
  }

  /// Fetches the source's native leaf categories and merges them into the
  /// user's saved visibility settings.
  @override
  Future<List<SourceGroupConfig>> syncSourceGroupConfigs(
      String sourceId) async {
    final sourceRows = await (await _db).query(
      'sources',
      where: 'id = ?',
      whereArgs: [sourceId],
      limit: 1,
    );
    if (sourceRows.isEmpty) throw StateError('未找到视频源');
    final source = _sourceFromRow(sourceRows.single);
    if (source.type != MediaSourceType.macCmsApi &&
        source.type != MediaSourceType.jsonApi) {
      throw StateError('该视频源不支持片库分组');
    }

    final categories = MediaCategoryAdapter.adapt(
      await _macCmsClient.categories(source),
      isAdult: source.isAdult,
    );
    final leavesById = <String, UnifiedSubcategory>{};
    for (final category in categories) {
      for (final leaf in category.subcategories) {
        leavesById.putIfAbsent(leaf.id, () => leaf);
      }
    }

    final database = await _db;
    await database.transaction((transaction) async {
      final existingRows = await transaction.query(
        'source_group_configs',
        where: 'source_id = ?',
        whereArgs: [sourceId],
      );
      final existingById = <String, Map<String, Object?>>{
        for (final row in existingRows)
          if (_stringValue(row['category_id']).isNotEmpty)
            _stringValue(row['category_id']): row,
      };
      final now = DateTime.now().millisecondsSinceEpoch;

      final staleIds = existingById.keys
          .where((id) => !leavesById.containsKey(id))
          .toList(growable: false);
      if (staleIds.isNotEmpty) {
        final placeholders = List.filled(staleIds.length, '?').join(', ');
        await transaction.delete(
          'source_group_configs',
          where: 'source_id = ? AND category_id IN ($placeholders)',
          whereArgs: [sourceId, ...staleIds],
        );
      }

      for (final leaf in leavesById.values) {
        final existing = existingById[leaf.id];
        if (existing == null) {
          await transaction.insert('source_group_configs', {
            'source_id': sourceId,
            'category_id': leaf.id,
            'category_name': leaf.name,
            'is_enabled': 1,
            'created_at': now,
            'updated_at': now,
          });
        } else if (_stringValue(existing['category_name']) != leaf.name) {
          await transaction.update(
            'source_group_configs',
            {'category_name': leaf.name, 'updated_at': now},
            where: 'source_id = ? AND category_id = ?',
            whereArgs: [sourceId, leaf.id],
          );
        }
      }
    });

    return getSourceGroupConfigs(sourceId);
  }

  /// Gets only the enabled category IDs for a source.
  /// Used for filtering API requests to show only enabled categories.
  @override
  Future<List<String>> getEnabledGroupIdsForSource(String sourceId) async {
    final database = await _db;
    final rows = await database.query(
      'source_group_configs',
      columns: ['category_id', 'is_enabled'],
      where: 'source_id = ?',
      whereArgs: [sourceId],
    );
    return rows
        .where((row) => _safeParseInt(row['is_enabled']) == 1)
        .map((row) => _stringValue(row['category_id']))
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
  }

  /// Initializes all group configurations for a source based on remote leaf categories.
  /// All groups start as enabled by default.
  /// Groups are based on the source's native subcategories.
  /// Initializes all category configurations for a source.
  /// Called when first setting up a new adult source.
  /// All categories start enabled by default.
  @override
  Future<void> initializeSourceGroupConfigs(
    String sourceId,
    List<UnifiedSubcategory> leafCategories,
  ) async {
    final database = await _db;
    final now = DateTime.now();

    await database.transaction((transaction) async {
      // Clear existing configs for this source
      await transaction.delete(
        'source_group_configs',
        where: 'source_id = ?',
        whereArgs: [sourceId],
      );
      // Insert new configs - all enabled by default
      for (final category in leafCategories) {
        await transaction.insert(
          'source_group_configs',
          {
            'source_id': sourceId,
            'category_id': category.id,
            'category_name': category.name,
            'is_enabled': 1,
            'created_at': now.millisecondsSinceEpoch,
            'updated_at': now.millisecondsSinceEpoch,
          },
        );
      }
    });
  }

  /// Toggles a category's enabled/disabled state.
  /// Simple toggle - no parent/child sync needed for flat category lists.
  @override
  Future<void> toggleSourceGroupConfig(
    String sourceId,
    String groupId,
    bool enable,
  ) async {
    final database = await _db;
    await database.update(
      'source_group_configs',
      {
        'is_enabled': enable ? 1 : 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'source_id = ? AND category_id = ?',
      whereArgs: [sourceId, groupId],
    );
  }

  Future<List<MediaItem>> browseDefaultSource({String? category}) async {
    return (await browseDefaultSourcePage(
      categoryIds: category == null ? const [] : [category],
    ))
        .items;
  }

  Future<PagedMedia> browseDefaultSourcePage({
    List<String> categoryIds = const [],
    int page = 1,
  }) async {
    final source = await defaultSource();
    if (source == null) {
      final filtered = categoryIds.isEmpty
          ? catalog
          : catalog
              .where((item) => _matchesLocalCategory(item, categoryIds))
              .toList(growable: false);
      return _localPage(filtered, page);
    }

    final groupFilter = await _sourceGroupFilter(source.id);

    final ids = _normalizedCategoryIds(categoryIds);

    // For an unqualified browse, request each enabled leaf so disabled groups
    // cannot leak into the all-category result.
    final requestedIds =
        ids.isEmpty && groupFilter.hasConfig ? groupFilter.enabledIds : ids;
    final filteredIds = groupFilter.hasConfig
        ? requestedIds
            .where((id) => groupFilter.enabledIds.contains(id))
            .toList(growable: false)
        : requestedIds;

    if (filteredIds.isEmpty && groupFilter.hasConfig) {
      // All specified categories are disabled
      return PagedMedia(
        items: const [],
        page: page,
        pageCount: 0,
        limit: 0,
        total: 0,
        hasMore: false,
      );
    }

    if (filteredIds.isEmpty) {
      return _macCmsClient.listPage(source, page: page);
    }
    final pages = await Future.wait(
      filteredIds.map(
          (id) => _macCmsClient.listPage(source, category: id, page: page)),
    );
    return _combinePages(pages, page);
  }

  Future<List<MediaItem>> browseDefaultSourceCategories(
    List<String> categoryIds,
  ) async {
    return (await browseDefaultSourcePage(categoryIds: categoryIds)).items;
  }

  /// Loads fixed home rows from source APIs instead of grouping one generic
  /// first-page response locally. Every non-empty row issues `ac=videolist`
  /// requests with its matched source category IDs.
  Future<List<HomeCategoryRail>> browseDefaultHomeCategoryRails(
    List<UnifiedCategory> categories,
  ) async {
    final source = await defaultSource();
    if (source == null) {
      return _homeCategoryDefinitions
          .map(
            (definition) => HomeCategoryRail(
              title: definition.title,
              categoryIds: const [],
              items: catalog
                  .where(
                    (item) => definition.matches(item.genres.join(' ')),
                  )
                  .toList(growable: false),
            ),
          )
          .toList(growable: false);
    }

    if (source.isAdult) {
      return _browseAdultHomeCategoryRails(categories);
    }

    final idsByRail = [
      for (final definition in _homeCategoryDefinitions)
        _homeCategoryIds(definition, categories),
    ];
    final pages = await Future.wait(
      List.generate(
        _homeCategoryDefinitions.length,
        (index) => _browseHomeCategoryRailItems(
          title: _homeCategoryDefinitions[index].title,
          categoryIds: idsByRail[index],
        ),
      ),
    );
    return List<HomeCategoryRail>.generate(
      _homeCategoryDefinitions.length,
      (index) => HomeCategoryRail(
        title: _homeCategoryDefinitions[index].title,
        categoryIds: idsByRail[index],
        items: pages[index],
      ),
      growable: false,
    );
  }

  Future<List<HomeCategoryRail>> _browseAdultHomeCategoryRails(
    List<UnifiedCategory> categories,
  ) async {
    final adultCategory = categories
        .where((category) => category.type == UnifiedMediaType.adult)
        .firstOrNull;
    final subcategories = adultCategory?.subcategories ?? const [];

    // For adult sources, load resources lightly to avoid freezing:
    // - Show all first-level categories as separate rails
    // - Only preload the first category with actual resources
    // - Other categories show as empty placeholders for on-demand loading

    if (subcategories.isEmpty) {
      return [
        const HomeCategoryRail(
          title: '成人资源',
          categoryIds: <String>[],
          items: <MediaItem>[],
        ),
      ];
    }

    final rails = <HomeCategoryRail>[];
    for (int i = 0; i < subcategories.length; i++) {
      final category = subcategories[i];
      if (i == 0) {
        // Load only the first category eagerly
        final items = await _browseHomeCategoryRailItems(
          title: category.name,
          categoryIds: category.sourceCategoryIds,
        );
        rails.add(
          HomeCategoryRail(
            title: category.name,
            categoryIds: category.sourceCategoryIds,
            items: items,
          ),
        );
      } else {
        // Other categories: empty placeholders for on-demand loading
        rails.add(
          HomeCategoryRail(
            title: category.name,
            categoryIds: category.sourceCategoryIds,
            items: const <MediaItem>[],
          ),
        );
      }
    }

    return rails;
  }

  /// Keeps independent home rails available when one source category fails.
  Future<List<MediaItem>> _browseHomeCategoryRailItems({
    required String title,
    required List<String> categoryIds,
  }) async {
    final ids = _normalizedCategoryIds(categoryIds);
    if (ids.isEmpty) return const [];

    final pages = await Future.wait(
      ids.map((categoryId) async {
        try {
          return await browseDefaultSourcePage(categoryIds: [categoryId]);
        } on Object catch (error, stackTrace) {
          _debugHomeRailError(
            title: title,
            categoryId: categoryId,
            error: error,
            stackTrace: stackTrace,
          );
          return null;
        }
      }),
    );
    return _combinePages(pages.whereType<PagedMedia>().toList(), 1).items;
  }

  static void _debugHomeRailError({
    required String title,
    required String categoryId,
    required Object error,
    required StackTrace stackTrace,
  }) {
    assert(() {
      debugPrint(
        '[Cineo][Repository] home_rail phase=load_failed '
        'title=$title categoryId=$categoryId '
        'error=${error.runtimeType}: $error',
      );
      debugPrintStack(
        label: '[Cineo][Repository] home_rail stack',
        stackTrace: stackTrace,
        maxFrames: 12,
      );
      return true;
    }());
  }

  Future<List<UnifiedCategory>> defaultSourceCategories() async {
    final source = await defaultSource();
    if (source == null) {
      return const [
        UnifiedCategory(type: UnifiedMediaType.all, sourceCategoryIds: []),
        UnifiedCategory(type: UnifiedMediaType.movie, sourceCategoryIds: []),
        UnifiedCategory(type: UnifiedMediaType.series, sourceCategoryIds: []),
      ];
    }
    final categories = MediaCategoryAdapter.adapt(
      await _macCmsClient.categories(source),
      isAdult: source.isAdult,
    );
    return _filterCategoriesByGroupConfig(
      categories,
      await _sourceGroupFilter(source.id),
    );
  }

  List<String> _homeCategoryIds(
    _HomeCategoryDefinition definition,
    List<UnifiedCategory> categories,
  ) {
    final typeCategories = categories
        .where((category) => category.type == definition.type)
        .toList(growable: false);
    if (typeCategories.isEmpty) return const [];
    final category = typeCategories.first;
    if (definition.useAllTypeIds) return category.sourceCategoryIds;
    final ids = <String>{};
    for (final subcategory in category.subcategories) {
      final text = subcategory.matchText.isEmpty
          ? subcategory.name
          : subcategory.matchText;
      if (definition.matches(text)) ids.addAll(subcategory.sourceCategoryIds);
    }
    return ids.toList(growable: false);
  }

  Future<List<MediaItem>> searchDefaultSource(
    String query, {
    List<String> categoryIds = const [],
  }) async {
    return (await searchDefaultSourcePage(query, categoryIds: categoryIds))
        .items;
  }

  Future<PagedMedia> searchDefaultSourcePage(
    String query, {
    List<String> categoryIds = const [],
    int page = 1,
  }) async {
    final normalizedQuery = query.trim();
    final source = await defaultSource();
    if (source == null) {
      final normalized = normalizedQuery.toLowerCase();
      final filtered = catalog.where((media) {
        final matchesText = normalized.isEmpty ||
            [media.title, media.description, ...media.genres]
                .join(' ')
                .toLowerCase()
                .contains(normalized);
        return matchesText &&
            (categoryIds.isEmpty || _matchesLocalCategory(media, categoryIds));
      }).toList(growable: false);
      return _localPage(filtered, page);
    }
    final ids = _normalizedCategoryIds(categoryIds);
    final groupFilter = await _sourceGroupFilter(source.id);
    final requestedIds =
        ids.isEmpty && groupFilter.hasConfig ? groupFilter.enabledIds : ids;
    final filteredIds = groupFilter.hasConfig
        ? requestedIds
            .where((id) => groupFilter.enabledIds.contains(id))
            .toList(growable: false)
        : requestedIds;

    if (filteredIds.isEmpty && groupFilter.hasConfig) {
      return PagedMedia(
        items: const [],
        page: page,
        pageCount: 0,
        limit: 0,
        total: 0,
        hasMore: false,
      );
    }
    if (filteredIds.isEmpty) {
      return _macCmsClient.listPage(source, query: normalizedQuery, page: page);
    }
    final pages =
        await Future.wait(filteredIds.map((id) => _macCmsClient.listPage(
              source,
              query: normalizedQuery,
              category: id,
              page: page,
            )));
    return _combinePages(pages, page);
  }

  List<String> _normalizedCategoryIds(List<String> categoryIds) => categoryIds
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList(growable: false);

  Future<_SourceGroupFilter> _sourceGroupFilter(String sourceId) async {
    try {
      final configs = await getSourceGroupConfigs(sourceId);
      return _SourceGroupFilter(
        hasConfig: configs.isNotEmpty,
        enabledIds: configs
            .where((config) => config.isEnabled)
            .map((config) => config.categoryId)
            .toSet()
            .toList(growable: false),
      );
    } catch (_) {
      // A missing or unreadable config table must not break normal browsing.
      return const _SourceGroupFilter.unconfigured();
    }
  }

  List<UnifiedCategory> _filterCategoriesByGroupConfig(
    List<UnifiedCategory> categories,
    _SourceGroupFilter groupFilter,
  ) {
    if (!groupFilter.hasConfig) return categories;

    final filtered = <UnifiedCategory>[];
    for (final category in categories) {
      if (category.type == UnifiedMediaType.all) {
        filtered.add(category);
        continue;
      }
      final subcategories = category.subcategories
          .where(
              (subcategory) => groupFilter.enabledIds.contains(subcategory.id))
          .toList(growable: false);
      final sourceCategoryIds = category.sourceCategoryIds
          .where((id) => groupFilter.enabledIds.contains(id))
          .toList(growable: false);
      if (subcategories.isEmpty && sourceCategoryIds.isEmpty) continue;
      filtered.add(
        UnifiedCategory(
          type: category.type,
          sourceCategoryIds: sourceCategoryIds,
          displayName: category.displayName,
          subcategories: subcategories,
        ),
      );
    }
    return List.unmodifiable(filtered);
  }

  PagedMedia _localPage(List<MediaItem> items, int requestedPage) {
    final page = requestedPage < 1 ? 1 : requestedPage;
    final pageItems = page == 1 ? items : const <MediaItem>[];
    return PagedMedia(
      items: pageItems,
      page: page,
      pageCount: 1,
      limit: items.length,
      total: items.length,
      hasMore: false,
    );
  }

  PagedMedia _combinePages(List<PagedMedia> pages, int requestedPage) {
    final seen = <String>{};
    final items = pages
        .expand((result) => result.items)
        .where((item) => seen.add(item.id))
        .toList(growable: false);
    return PagedMedia(
      items: items,
      page: requestedPage,
      pageCount: pages.fold<int>(
          1, (max, result) => result.pageCount > max ? result.pageCount : max),
      limit: pages.fold<int>(0, (sum, result) => sum + result.limit),
      total: pages.fold<int>(0, (sum, result) => sum + result.total),
      hasMore: pages.any((result) => result.hasMore),
    );
  }

  bool _matchesLocalCategory(MediaItem item, List<String> categoryIds) {
    // Demo content has no source category IDs. Its filtering remains a
    // graceful fallback until the user selects a configured API source.
    return categoryIds.isEmpty ||
        item.categoryId == null ||
        categoryIds.contains(item.categoryId);
  }

  @override
  Future<MediaItem?> loadDetails(MediaItem item) async {
    if (item.sourceId == null || item.remoteId == null) return item;
    final sourceRows = await (await _db).query('sources',
        where: 'id = ?', whereArgs: [item.sourceId], limit: 1);
    if (sourceRows.isEmpty) return item;
    return _macCmsClient.detail(
        _sourceFromRow(sourceRows.single), item.remoteId!);
  }

  /// Resolves the most recently selected source for this title. Preferences
  /// store only source and remote IDs, never stream URLs or credentials.
  Future<MediaItem?> preferredSourceFor(
    MediaItem media, {
    required bool includeAdult,
  }) async {
    final rows = await (await _db).query(
      'media_source_preferences',
      where: 'media_key = ?',
      whereArgs: [_mediaSourcePreferenceKey(media)],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final sourceId = rows.single['source_id'] as String;
    final sourceRows = await (await _db).query(
      'sources',
      where: 'id = ? AND enabled = 1',
      whereArgs: [sourceId],
      limit: 1,
    );
    if (sourceRows.isEmpty) return null;
    final source = _sourceFromRow(sourceRows.single);
    if (source.isAdult && !includeAdult) return null;
    if (source.type != MediaSourceType.macCmsApi &&
        source.type != MediaSourceType.jsonApi) {
      return null;
    }

    try {
      return await _macCmsClient.detail(
          source, rows.single['remote_id'] as String);
    } catch (_) {
      return null;
    }
  }

  Future<void> savePreferredSource(
    MediaItem media,
    MediaItem selectedMedia,
  ) async {
    final sourceId = selectedMedia.sourceId?.trim();
    final remoteId = selectedMedia.remoteId?.trim();
    if (sourceId == null ||
        sourceId.isEmpty ||
        remoteId == null ||
        remoteId.isEmpty) {
      return;
    }
    await (await _db).insert(
      'media_source_preferences',
      {
        'media_key': _mediaSourcePreferenceKey(media),
        'source_id': sourceId,
        'remote_id': remoteId,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  String _mediaSourcePreferenceKey(MediaItem media) {
    final normalizedTitle = media.title
        .toLowerCase()
        .replaceAll(RegExp(r'[\s\p{P}\p{S}]', unicode: true), '');
    return '${media.kind.name}:$normalizedTitle';
  }

  Future<List<MediaItem>> searchOtherSources(MediaItem media,
      {bool includeAdult = false}) async {
    final allSources = await sources();
    final candidates = allSources
        .where((source) =>
            source.enabled &&
            source.id != media.sourceId &&
            (source.type == MediaSourceType.macCmsApi ||
                source.type == MediaSourceType.jsonApi) &&
            (includeAdult || !source.isAdult))
        .toList();

    // Use concurrent requests with a fixed pool size (10-15 concurrent) for better performance
    const concurrentLimit = 12;
    final results = <List<MediaItem>>[];

    for (var i = 0; i < candidates.length; i += concurrentLimit) {
      final batch = candidates.sublist(
        i,
        i + concurrentLimit > candidates.length
            ? candidates.length
            : i + concurrentLimit,
      );

      final batchResults = await Future.wait(batch.map((source) async {
        try {
          return await _macCmsClient.list(source, query: media.title);
        } catch (_) {
          return const <MediaItem>[];
        }
      }));

      results.addAll(batchResults);
    }

    return results.expand((items) => items).toList(growable: false);
  }

  Future<void> close() async {
    if (_databaseInitialized) await (await _db).close();
  }

  bool get _databaseInitialized => true;

  Future<void> _createMediaSnapshotsTable(DatabaseExecutor database) {
    return database.execute('''
      CREATE TABLE media_snapshots (
        media_id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT NOT NULL,
        year INTEGER NOT NULL,
        kind INTEGER NOT NULL,
        poster_url TEXT NOT NULL,
        backdrop_url TEXT NOT NULL,
        genres_json TEXT NOT NULL,
        rating REAL NOT NULL,
        duration_ms INTEGER NOT NULL,
        source_id TEXT,
        source_name TEXT,
        remote_id TEXT,
        category TEXT,
        category_id TEXT,
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _createHomeCategoryCacheTable(DatabaseExecutor database) {
    return database.execute('''
      CREATE TABLE home_category_rails (
        rail_key TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        category_ids_json TEXT NOT NULL,
        media_ids_json TEXT NOT NULL,
        position INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _createSourceGroupConfigTable(DatabaseExecutor database) {
    return database.execute('''
      CREATE TABLE IF NOT EXISTS source_group_configs (
        source_id TEXT NOT NULL,
        category_id TEXT NOT NULL,
        category_name TEXT NOT NULL,
        is_enabled INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (source_id, category_id)
      )
    ''');
  }

  /// Repairs partially-created group tables left by older iOS migrations.
  ///
  /// `CREATE TABLE IF NOT EXISTS` does not validate an existing table's
  /// columns, so a table with a legacy/corrupt schema can still make inserts
  /// fail. Rebuild only this table and copy values from known legacy names.
  Future<void> _ensureSourceGroupConfigTable(Database database) async {
    final info =
        await database.rawQuery('PRAGMA table_info(source_group_configs)');
    if (info.isEmpty) {
      await _createSourceGroupConfigTable(database);
      return;
    }

    final columns = <String>{
      for (final row in info) _stringValue(row['name']).toLowerCase(),
    };
    const required = {
      'source_id',
      'category_id',
      'category_name',
      'is_enabled',
      'created_at',
      'updated_at',
    };
    if (required.every(columns.contains)) return;

    await database.transaction((transaction) async {
      await transaction.execute(
        'ALTER TABLE source_group_configs RENAME TO source_group_configs_legacy',
      );
      await _createSourceGroupConfigTable(transaction);

      final legacyRows = await transaction.query('source_group_configs_legacy');
      final legacyInfo = await transaction.rawQuery(
        'PRAGMA table_info(source_group_configs_legacy)',
      );
      final actualNames = <String, String>{
        for (final row in legacyInfo)
          _stringValue(row['name']).toLowerCase(): _stringValue(row['name']),
      };

      Object? value(Map<String, Object?> row, List<String> candidates) {
        for (final candidate in candidates) {
          final actual = actualNames[candidate.toLowerCase()];
          if (actual != null && row.containsKey(actual)) return row[actual];
        }
        return null;
      }

      for (final row in legacyRows) {
        final sourceId = _stringValue(value(row, ['source_id', 'sourceId']));
        final categoryId =
            _stringValue(value(row, ['category_id', 'categoryId']));
        if (sourceId.isEmpty || categoryId.isEmpty) continue;

        final categoryName = _stringValue(
          value(row, ['category_name', 'categoryName']),
        );
        final enabledValue = value(row, ['is_enabled', 'isEnabled']);
        await transaction.insert(
          'source_group_configs',
          {
            'source_id': sourceId,
            'category_id': categoryId,
            'category_name': categoryName.isEmpty ? categoryId : categoryName,
            'is_enabled': enabledValue == null
                ? 1
                : _safeParseInt(enabledValue) == 0
                    ? 0
                    : 1,
            'created_at': _safeParseInt(
              value(row, ['created_at', 'createdAt']),
            ),
            'updated_at': _safeParseInt(
              value(row, ['updated_at', 'updatedAt']),
            ),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await transaction.execute('DROP TABLE source_group_configs_legacy');
    });
  }

  Future<void> _saveMediaSnapshot(
    MediaItem media, {
    required DatabaseExecutor database,
  }) {
    return database.insert(
      'media_snapshots',
      {
        'media_id': media.id,
        'title': media.title,
        'description': media.description,
        'year': media.year,
        'kind': media.kind.index,
        'poster_url': media.posterUrl,
        'backdrop_url': media.backdropUrl,
        'genres_json': jsonEncode(media.genres),
        'rating': media.rating,
        'duration_ms': media.duration.inMilliseconds,
        'source_id': media.sourceId,
        'source_name': media.sourceName,
        'remote_id': media.remoteId,
        'category': media.category,
        'category_id': media.categoryId,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  MediaItem _mediaFromSnapshotRow(Map<String, Object?> row) {
    final kindIndex = row['kind'] as int;
    final kind = kindIndex >= 0 && kindIndex < MediaKind.values.length
        ? MediaKind.values[kindIndex]
        : MediaKind.movie;
    final decodedGenres = jsonDecode(row['genres_json'] as String);
    final genres = decodedGenres is List
        ? decodedGenres.whereType<String>().toList(growable: false)
        : const <String>[];
    return MediaItem(
      id: row['media_id'] as String,
      title: row['title'] as String,
      description: row['description'] as String,
      year: _safeParseInt(row['year']),
      kind: kind,
      posterUrl: row['poster_url'] as String,
      backdropUrl: row['backdrop_url'] as String,
      genres: genres,
      rating: (row['rating'] as num).toDouble(),
      duration: Duration(milliseconds: _safeParseInt(row['duration_ms'])),
      sourceId: row['source_id'] as String?,
      sourceName: row['source_name'] as String?,
      remoteId: row['remote_id'] as String?,
      category: row['category'] as String?,
      categoryId: row['category_id'] as String?,
    );
  }

  WatchProgress _progressFromRow(Map<String, Object?> row) {
    return WatchProgress(
      mediaId: row['media_id'] as String,
      episodeId: row['episode_id'] as String?,
      episodeLabel: row['episode_label'] as String?,
      episodeNumber: _safeParseIntNullable(row['episode_number']),
      episodeCount: _safeParseIntNullable(row['episode_count']),
      position: Duration(milliseconds: _safeParseInt(row['position_ms'])),
      duration: Duration(milliseconds: _safeParseInt(row['duration_ms'])),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    );
  }

  Map<String, Object?> _sourceToRow(MediaSource source) {
    return {
      'id': source.id,
      'name': source.name,
      'type': source.type.index,
      'base_url': source.baseUrl,
      'enabled': source.enabled ? 1 : 0,
      'last_checked_at': source.lastCheckedAt?.millisecondsSinceEpoch,
      'last_error': source.lastError,
      'external_id': source.externalId,
      'detail_url': source.detailUrl,
      'is_adult': source.isAdult ? 1 : 0,
      'cache_ttl_seconds': source.cacheTtlSeconds,
      'is_default': source.isDefault ? 1 : 0,
      'last_latency_ms': source.lastLatencyMs,
      'is_favorite': source.isFavorite ? 1 : 0,
    };
  }

  MediaSource _sourceFromRow(Map<String, Object?> row) {
    final typeIndex = row['type'] as int;
    final type = typeIndex >= 0 && typeIndex < MediaSourceType.values.length
        ? MediaSourceType.values[typeIndex]
        : MediaSourceType.direct;
    final checkedAt = row['last_checked_at'] as int?;
    return MediaSource(
      id: row['id'] as String,
      name: row['name'] as String,
      type: type,
      baseUrl: row['base_url'] as String,
      enabled: (row['enabled'] as int) == 1,
      lastCheckedAt: checkedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(checkedAt),
      lastError: row['last_error'] as String?,
      externalId: row['external_id'] as String?,
      detailUrl: row['detail_url'] as String?,
      isAdult: (row['is_adult'] as int? ?? 0) == 1,
      cacheTtlSeconds: row['cache_ttl_seconds'] as int?,
      isDefault: (row['is_default'] as int? ?? 0) == 1,
      lastLatencyMs: row['last_latency_ms'] as int?,
      isFavorite: (row['is_favorite'] as int? ?? 0) == 1,
    );
  }

  SourceGroupConfig _groupConfigFromRow(Map<String, Object?> row) {
    return SourceGroupConfig(
      sourceId: _stringValue(row['source_id']),
      categoryId: _stringValue(row['category_id']),
      categoryName: _stringValue(row['category_name']),
      isEnabled: _safeParseInt(row['is_enabled'] ?? 1) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        _safeParseInt(row['created_at']),
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        _safeParseInt(row['updated_at']),
      ),
    );
  }

  String _stringValue(Object? value) => value?.toString().trim() ?? '';

  int _safeParseInt(Object? value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    if (value is num) return value.toInt();
    return 0;
  }

  int? _safeParseIntNullable(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    if (value is num) return value.toInt();
    return null;
  }

  List<String> _decodeStringList(Object? value) {
    if (value is! String) return const [];
    final decoded = jsonDecode(value);
    if (decoded is! List) return const [];
    return decoded.whereType<String>().toList(growable: false);
  }
}

class _SourceGroupFilter {
  const _SourceGroupFilter({
    required this.hasConfig,
    required this.enabledIds,
  });

  const _SourceGroupFilter.unconfigured()
      : hasConfig = false,
        enabledIds = const [];

  final bool hasConfig;
  final List<String> enabledIds;
}

class _HomeCategoryDefinition {
  const _HomeCategoryDefinition({
    required this.title,
    required this.type,
    required this.pattern,
    this.useAllTypeIds = false,
  });

  final String title;
  final UnifiedMediaType type;
  final RegExp pattern;
  final bool useAllTypeIds;

  bool matches(String text) => pattern.hasMatch(text);
}

final _homeCategoryDefinitions = <_HomeCategoryDefinition>[
  _HomeCategoryDefinition(
    title: '电影',
    type: UnifiedMediaType.movie,
    pattern: RegExp(r'电影|影片|movie|film', caseSensitive: false),
    useAllTypeIds: true,
  ),
  _HomeCategoryDefinition(
    title: '国产剧',
    type: UnifiedMediaType.series,
    pattern: RegExp(r'国产剧|国剧|内地剧|大陆剧|华语剧'),
  ),
  _HomeCategoryDefinition(
    title: '韩剧',
    type: UnifiedMediaType.series,
    pattern: RegExp(r'韩剧|韩国剧'),
  ),
  _HomeCategoryDefinition(
    title: '国漫',
    type: UnifiedMediaType.animation,
    pattern: RegExp(r'国漫|国产动漫|国产动画'),
  ),
  _HomeCategoryDefinition(
    title: '短剧',
    type: UnifiedMediaType.series,
    pattern: RegExp(r'短剧|微短剧|短视频剧'),
  ),
];

/// Convenience repository for screens that need a local demo catalog.
LocalMediaRepository createDemoLocalMediaRepository({String? databasePath}) {
  return LocalMediaRepository(catalog: demoMedia, databasePath: databasePath);
}
