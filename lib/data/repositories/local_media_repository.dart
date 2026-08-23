import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../../core/demo/demo_content.dart';
import '../../core/models/home_category_rail.dart';
import '../../core/models/media.dart';
import '../../core/models/media_source.dart';
import '../../core/models/paged_media.dart';
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
      version: 7,
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
      },
    );
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
    final ids = _normalizedCategoryIds(categoryIds);
    if (ids.isEmpty) {
      return _macCmsClient.listPage(source, page: page);
    }
    final pages = await Future.wait(
      ids.map((id) => _macCmsClient.listPage(source, category: id, page: page)),
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

    final idsByRail = [
      for (final definition in _homeCategoryDefinitions)
        _homeCategoryIds(definition, categories),
    ];
    final pages = await Future.wait(
      idsByRail.map(
        (ids) => ids.isEmpty
            ? Future<List<MediaItem>>.value(const [])
            : browseDefaultSourcePage(categoryIds: ids)
                .then((page) => page.items),
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

  Future<List<UnifiedCategory>> defaultSourceCategories() async {
    final source = await defaultSource();
    if (source == null) {
      return const [
        UnifiedCategory(type: UnifiedMediaType.all, sourceCategoryIds: []),
        UnifiedCategory(type: UnifiedMediaType.movie, sourceCategoryIds: []),
        UnifiedCategory(type: UnifiedMediaType.series, sourceCategoryIds: []),
      ];
    }
    return MediaCategoryAdapter.adapt(await _macCmsClient.categories(source));
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
    if (ids.isEmpty) {
      return _macCmsClient.listPage(source, query: normalizedQuery, page: page);
    }
    final pages = await Future.wait(ids.map((id) => _macCmsClient.listPage(
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
