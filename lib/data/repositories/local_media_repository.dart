import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../../core/demo/demo_content.dart';
import '../../core/models/media.dart';
import '../../core/models/media_source.dart';
import 'media_repository.dart';

/// SQLite-backed storage for local user state.
///
/// The catalog is supplied by the caller because this repository stores local
/// state, while search and media metadata can come from any authorized source.
class LocalMediaRepository implements MediaRepository {
  LocalMediaRepository({
    this.catalog = const <MediaItem>[],
    this.databasePath,
  });

  final List<MediaItem> catalog;
  final String? databasePath;
  late final Future<Database> _database = _openDatabase();

  Future<Database> _openDatabase() async {
    final resolvedPath = databasePath ??
        path.join(await getDatabasesPath(), 'cineo_local_media.db');
    return openDatabase(
      resolvedPath,
      version: 2,
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
            cache_ttl_seconds INTEGER
          )
        ''');
        await database.execute('''
          CREATE TABLE search_history (
            query TEXT PRIMARY KEY,
            updated_at INTEGER NOT NULL
          )
        ''');
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
      },
    );
  }

  Future<Database> get _db => _database;

  @override
  Future<List<MediaItem>> featured() async => catalog.take(10).toList();

  @override
  Future<List<MediaItem>> search(String query) async {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return featured();
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
    for (final media in catalog) {
      if (media.id == id) return media;
    }
    return null;
  }

  @override
  Future<List<MediaItem>> favorites() async {
    final rows = await (await _db).query(
      'favorites',
      orderBy: 'created_at DESC',
    );
    final mediaById = {
      for (final media in catalog) media.id: media,
    };
    return rows
        .map((row) => mediaById[row['media_id'] as String])
        .whereType<MediaItem>()
        .toList();
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
  Future<void> setFavorite(String mediaId, bool isFavorite) async {
    final database = await _db;
    if (isFavorite) {
      await database.insert(
        'favorites',
        {
          'media_id': mediaId,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else {
      await database.delete(
        'favorites',
        where: 'media_id = ?',
        whereArgs: [mediaId],
      );
    }
  }

  @override
  Future<List<WatchProgress>> watchHistory() async {
    final rows = await (await _db).query(
      'progress',
      orderBy: 'updated_at DESC',
    );
    return rows.map(_progressFromRow).toList();
  }

  @override
  Future<void> saveProgress(WatchProgress progress) async {
    final episodeKey = progress.episodeId ?? '';
    await (await _db).insert(
      'progress',
      {
        'progress_key': '${progress.mediaId}:$episodeKey',
        'media_id': progress.mediaId,
        'episode_id': progress.episodeId,
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
    await (await _db).insert(
      'sources',
      _sourceToRow(source),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
    return true;
  }

  Future<void> close() async {
    if (_databaseInitialized) await (await _db).close();
  }

  bool get _databaseInitialized => true;

  WatchProgress _progressFromRow(Map<String, Object?> row) {
    return WatchProgress(
      mediaId: row['media_id'] as String,
      episodeId: row['episode_id'] as String?,
      position: Duration(milliseconds: row['position_ms'] as int),
      duration: Duration(milliseconds: row['duration_ms'] as int),
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
    );
  }
}

/// Convenience repository for screens that need a local demo catalog.
LocalMediaRepository createDemoLocalMediaRepository({String? databasePath}) {
  return LocalMediaRepository(catalog: demoMedia, databasePath: databasePath);
}
