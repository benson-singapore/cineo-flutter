import 'dart:async';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../../core/models/media.dart';
import '../../core/models/media_source.dart';
import '../repositories/local_media_repository.dart';
import 'hub_sync_api.dart';
import 'hub_sync_keys.dart';
import 'hub_sync_models.dart';
import 'hub_sync_policy.dart';

class HubSyncEngine {
  HubSyncEngine({
    required this.repository,
    required this.api,
    this.onCloudSettings,
    this.onCloudSettingsCleared,
  });
  final LocalMediaRepository repository;
  final HubSyncApi api;
  final Future<void> Function(Map<String, Object?> settings)? onCloudSettings;
  final Future<void> Function()? onCloudSettingsCleared;
  final Set<String> _activeOperations = {};
  bool get _pushRunning => _activeOperations.contains('push');
  bool get _pullRunning => _activeOperations.contains('pull');
  bool get _pushAllRunning => _activeOperations.contains('pushAll');
  int _retryAttempt = 0;
  Timer? _retryTimer;
  bool get isRunning => _pushRunning || _pullRunning || _pushAllRunning;

  Future<void> bind(
      {required String hubUrl,
      required String pin,
      required String deviceName}) async {
    await api.bind(hubUrl: hubUrl, pin: pin, deviceName: deviceName);
    final db = await repository.hubDatabase;
    await db.transaction((txn) async {
      await txn.delete('hub_sync_state');
      await _writeState(txn, 'cursor', '0');
      await _writeState(txn, 'generation', '0');
      await _writeState(txn, 'revoked', 'false');
      await _queueLocalData(txn);
    });
  }

  Future<void> pushProgress(MediaItem media, WatchProgress progress) async {
    final db = await repository.hubDatabase;
    final rows = await db.rawQuery('''
      SELECT m.title,m.category,m.remote_id,s.base_url
      FROM media_snapshots m LEFT JOIN sources s ON s.id=m.source_id
      WHERE m.media_id=? LIMIT 1
    ''', [media.id]);
    if (rows.isEmpty ||
        rows.single['remote_id'] == null ||
        rows.single['base_url'] == null) return;
    final row = rows.single;
    final sourceKey = hubSourceKey(row['base_url']! as String);
    final key = hubMediaKey(
        sourceKey: sourceKey,
        vodId: row['remote_id']! as String,
        lineName: progress.episodeLabel,
        episodeIndex: progress.episodeNumber == null
            ? null
            : progress.episodeNumber! - 1);
    await enqueue(
        db,
        SyncEnvelope(
            entity: 'progress',
            key: key,
            updatedAt: progress.updatedAt.millisecondsSinceEpoch,
            deleted: false,
            payload: {
              'title': row['title'] ?? media.title,
              'category': row['category'] ?? '',
              'line_name': progress.episodeLabel ?? '',
              'episode_index': (progress.episodeNumber ?? 1) - 1,
              'position_ms': progress.position.inMilliseconds,
              'duration_ms': progress.duration.inMilliseconds
            }));
    await _pushSingle(db, 'progress', key, 'auto_progress');
  }

  Future<void> queueFavorite(MediaItem media, bool isFavorite) async {
    final db = await repository.hubDatabase;
    final rows = await db.rawQuery('''
      SELECT m.title,m.category,m.remote_id,s.base_url
      FROM media_snapshots m LEFT JOIN sources s ON s.id=m.source_id
      WHERE m.media_id=? LIMIT 1
    ''', [media.id]);
    if (rows.isEmpty ||
        rows.single['remote_id'] == null ||
        rows.single['base_url'] == null) return;
    final row = rows.single;
    final key = hubMediaKey(
        sourceKey: hubSourceKey(row['base_url']! as String),
        vodId: row['remote_id']! as String);
    final updatedAt = DateTime.now().millisecondsSinceEpoch;
    await enqueue(
        db,
        SyncEnvelope(
            entity: 'favorite',
            key: key,
            updatedAt: updatedAt,
            deleted: !isFavorite,
            payload: isFavorite
                ? {
                    'title': row['title'] ?? media.title,
                    'category': row['category'] ?? '',
                    'added_at': updatedAt
                  }
                : null));
    await _pushSingle(db, 'favorite', key, 'auto_favorite');
  }

  Future<void> _pushSingle(
      Database db, String entity, String key, String trigger) async {
    if (_pushRunning || _pushAllRunning) throw StateError('已有推送任务进行中');
    if (!await api.credentials.isBound) return;
    final rows = await db.query('hub_outbox',
        where: 'entity=? AND record_key=?', whereArgs: [entity, key], limit: 1);
    if (rows.isEmpty) return;
    final row = rows.single;
    final item = <String, Object?>{
      'entity': entity,
      'key': key,
      'updated_at': row['updated_at'],
      'deleted': row['deleted'] == 1,
      'payload': row['payload_json'] == null
          ? null
          : jsonDecode(row['payload_json']! as String)
    };
    _activeOperations.add('push');
    try {
      await api.push([item], trigger: trigger);
      await db.delete('hub_outbox',
          where: 'entity=? AND record_key=?', whereArgs: [entity, key]);
    } on HubApiException catch (error) {
      if (error.revoked) {
        await _writeState(db, 'revoked', 'true');
      } else {
        _scheduleRetry(retryAfterSeconds: error.retryAfterSeconds);
      }
      await _writeState(db, 'last_error', error.safeMessage);
      rethrow;
    } finally {
      _activeOperations.remove('push');
    }
  }

  Future<void> unbindLocally() async {
    _retryTimer?.cancel();
    await api.credentials.clear();
    await api.credentials.clearCloudSettings();
    await onCloudSettingsCleared?.call();
    final db = await repository.hubDatabase;
    await db.transaction((txn) async {
      await txn.delete('hub_outbox');
      await txn.delete('hub_sync_state');
    });
  }

  Future<int> get staleOutboxCount async {
    if (await _state(await repository.hubDatabase, 'resync_pending') !=
        'true') {
      return 0;
    }
    final rows = await (await repository.hubDatabase)
        .rawQuery('SELECT COUNT(*) AS count FROM hub_outbox');
    return (rows.single['count'] as int?) ?? 0;
  }

  Future<void> discardStaleOutboxAndRebuildFromLocal() async {
    final db = await repository.hubDatabase;
    if (await _state(db, 'resync_pending') != 'true') return;
    await db.transaction((txn) async {
      await txn.delete('hub_outbox');
      await txn.delete('hub_sync_state', where: "state_key LIKE 'local_%'");
      await _writeState(txn, 'resync_pending', 'false');
      await _queueLocalData(txn);
    });
  }

  Future<void> pushOutbox({String trigger = 'retry'}) async {
    if (_pushRunning || _pushAllRunning) {
      throw StateError('已有推送任务进行中');
    }
    if (!await api.credentials.isBound) return;
    final db = await repository.hubDatabase;
    if (await _state(db, 'revoked') == 'true' ||
        await _state(db, 'resync_pending') == 'true') {
      return;
    }
    _activeOperations.add('push');
    try {
      final rows = await db.query('hub_outbox', orderBy: 'updated_at');
      if (rows.isEmpty) return;
      final items = rows
          .map((row) => <String, Object?>{
                'entity': row['entity'],
                'key': row['record_key'],
                'updated_at': row['updated_at'],
                'deleted': row['deleted'] == 1,
                'payload': row['payload_json'] == null
                    ? null
                    : jsonDecode(row['payload_json']! as String),
              })
          .toList();
      await api.push(items, trigger: trigger);
      await db.transaction((txn) async {
        for (final row in rows) {
          await txn.delete('hub_outbox',
              where: 'entity=? AND record_key=?',
              whereArgs: [row['entity'], row['record_key']]);
        }
      });
      _retryAttempt = 0;
      _retryTimer?.cancel();
    } on HubApiException catch (error) {
      if (error.revoked) {
        await _writeState(db, 'revoked', 'true');
      } else {
        _scheduleRetry(retryAfterSeconds: error.retryAfterSeconds);
      }
      await _writeState(db, 'last_error', error.safeMessage);
      rethrow;
    } finally {
      _activeOperations.remove('push');
    }
  }

  Future<void> pullAndApply({String trigger = 'manual_pull'}) async {
    if (_pullRunning || _pushAllRunning) {
      throw StateError('已有同步任务进行中');
    }
    if (!await api.credentials.isBound) return;
    final db = await repository.hubDatabase;
    if (await _state(db, 'revoked') == 'true') return;
    _activeOperations.add('pull');
    try {
      final rebuilt = await _pull(db, trigger: trigger);
      if (rebuilt) {
        final count =
            await db.rawQuery('SELECT COUNT(*) AS count FROM hub_outbox');
        await _writeState(db, 'resync_pending',
            '${(count.single['count'] as int? ?? 0) > 0}');
      }
      final settings = await api.settings();
      final prefs =
          (settings['preferences'] as Map?)?.cast<String, Object?>() ??
              const {};
      final tmdbKey = settings['tmdb_key'] as String?;
      await api.credentials.saveCloudSettings(tmdbKey: tmdbKey);
      await _writeState(
          db, 'cloud_tmdb_key_configured', '${tmdbKey?.isNotEmpty == true}');
      await _writeState(db, 'cloud_tmdb_language',
          prefs['tmdb_language'] as String? ?? 'zh-CN');
      await _writeState(
          db, 'cloud_include_adult', '${prefs['include_adult'] == true}');
      await _writeState(
          db, 'cloud_settings_updated_at', '${settings['updated_at'] ?? 0}');
      await onCloudSettings?.call(settings);
      await _writeState(db, 'last_error', '');
    } on HubApiException catch (error) {
      if (error.revoked) await _writeState(db, 'revoked', 'true');
      await _writeState(db, 'last_error', error.safeMessage);
      rethrow;
    } finally {
      _activeOperations.remove('pull');
    }
  }

  Future<Map<String, Object?>> pushAll(
      {void Function(int sent, int total)? onProgress}) async {
    if (_pushAllRunning || _pushRunning || _pullRunning) {
      return {
        'sent': 0,
        'total': 0,
        'accepted': 0,
        'ignored': 0,
        'failed': 0,
        'error': '已有同步任务进行中'
      };
    }
    _activeOperations.add('pushAll');
    try {
      final db = await repository.hubDatabase;
      await _queueLocalData(db);
      final total = Sqflite.firstIntValue(
              await db.rawQuery('SELECT COUNT(*) FROM hub_outbox')) ??
          0;
      var sent = 0;
      var accepted = 0;
      var ignored = 0;
      var failed = 0;
      String? errorMessage;
      while (sent + failed < total) {
        final rows =
            await db.query('hub_outbox', orderBy: 'updated_at', limit: 500);
        if (rows.isEmpty) break;
        final batch = <Map<String, Object?>>[];
        var bytes = utf8.encode('{"items":[]}').length;
        for (final row in rows) {
          final item = <String, Object?>{
            'entity': row['entity'],
            'key': row['record_key'],
            'updated_at': row['updated_at'],
            'deleted': row['deleted'] == 1,
            'payload': row['payload_json'] == null
                ? null
                : jsonDecode(row['payload_json']! as String),
          };
          final itemBytes =
              utf8.encode(jsonEncode(item)).length + (batch.isEmpty ? 0 : 1);
          if (batch.isNotEmpty && bytes + itemBytes > 1024 * 1024) break;
          if (itemBytes + utf8.encode('{"items":[]}').length > 1024 * 1024) {
            failed++;
            errorMessage = '单条记录超过 1 MB，已跳过';
            await db.delete('hub_outbox',
                where: 'entity=? AND record_key=?',
                whereArgs: [item['entity'], item['key']]);
            continue;
          }
          batch.add(item);
          bytes += itemBytes;
        }
        if (batch.isEmpty) continue;
        try {
          final result = await api.push(batch, trigger: 'full_push');
          accepted += (result['accepted'] as num?)?.toInt() ?? 0;
          ignored += (result['ignored'] as num?)?.toInt() ?? 0;
          for (final item in batch) {
            await db.delete('hub_outbox',
                where: 'entity=? AND record_key=?',
                whereArgs: [item['entity'], item['key']]);
          }
          sent += batch.length;
          onProgress?.call(sent + failed, total);
        } on HubApiException catch (error) {
          failed += total - sent - failed;
          errorMessage = error.safeMessage;
          break;
        }
      }
      return {
        'sent': sent,
        'total': total,
        'accepted': accepted,
        'ignored': ignored,
        'failed': failed,
        if (errorMessage != null) 'error': errorMessage
      };
    } finally {
      _activeOperations.remove('pushAll');
    }
  }

  Future<void> sync() async {
    await pullAndApply(trigger: 'launch_pull');
  }

  Future<bool> _pull(DatabaseExecutor db,
      {String trigger = 'launch_pull'}) async {
    var cursor = int.tryParse(await _state(db, 'cursor') ?? '') ?? 0;
    var generation = int.tryParse(await _state(db, 'generation') ?? '') ?? 0;
    var rebuilt = false;
    Map<String, Object?> page;
    final snapshotKeys = <String>{};
    try {
      page = await api.pull(cursor, trigger: trigger);
    } on HubApiException catch (e) {
      if (!e.resyncRequired) rethrow;
      rebuilt = true;
      cursor = 0;
      page = await api.rebuild(generation: generation);
    }
    do {
      generation = (page['generation'] as num?)?.toInt() ?? generation;
      final records = (page['items'] as List? ?? const []).whereType<Map>();
      for (final raw in records) {
        final envelope = SyncEnvelope.fromJson(raw.cast<String, Object?>());
        snapshotKeys.add('remote_${envelope.entity}:${envelope.key}');
        await _apply(db, envelope);
      }
      cursor = (page['next_seq'] as num?)?.toInt() ?? cursor;
      await _writeState(db, 'cursor', '$cursor');
      await _writeState(db, 'generation', '$generation');
      if (page['has_more'] != true) break;
      page = await api.rebuild(generation: generation, cursor: cursor);
    } while (true);
    if (rebuilt) {
      final remote = await db.query('hub_sync_state',
          columns: ['state_key', 'value'], where: "state_key LIKE 'remote_%'");
      for (final row in remote) {
        final key = row['state_key']! as String;
        if (!snapshotKeys.contains(key)) {
          if (key.startsWith('remote_favorite:') ||
              key.startsWith('remote_history:') ||
              key.startsWith('remote_progress:')) {
            try {
              final raw = jsonDecode(row['value']! as String);
              if (raw is Map) {
                final old = SyncEnvelope.fromJson(raw.cast<String, Object?>());
                await _applyMediaEntity(
                    db, old.copyWith(deleted: true, payload: null));
              }
            } on FormatException {
              // Invalid cached envelopes are discarded with the stale state.
            } on TypeError {
              // Invalid cached envelopes are discarded with the stale state.
            }
          }
          await db
              .delete('hub_sync_state', where: 'state_key=?', whereArgs: [key]);
          if (key.startsWith('remote_site:')) {
            final sourceKey = key.substring('remote_site:'.length);
            await db.delete('sources',
                where: 'id=?', whereArgs: ['hub-$sourceKey']);
          }
        }
      }
    }
    await _materializeRemoteMediaRecords(db);
    return rebuilt;
  }

  Future<void> _materializeRemoteMediaRecords(DatabaseExecutor db) async {
    final rows = await db.query('hub_sync_state',
        where: "state_key LIKE 'remote_favorite:%' OR "
            "state_key LIKE 'remote_history:%' OR "
            "state_key LIKE 'remote_progress:%'");
    for (final row in rows) {
      try {
        final raw = jsonDecode(row['value']! as String);
        if (raw is Map) {
          await _applyMediaEntity(
              db, SyncEnvelope.fromJson(raw.cast<String, Object?>()));
        }
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      }
    }
  }

  Future<void> _applyMediaEntity(DatabaseExecutor db, SyncEnvelope item) async {
    if (!const {'favorite', 'history', 'progress'}.contains(item.entity)) {
      return;
    }
    final parts = item.key.split(':').map(Uri.decodeComponent).toList();
    if (parts.length < 2 || parts.length > 4) {
      return;
    }
    final sourceKey = parts[0];
    final vodId = parts[1];
    final lineName = parts.length == 4 ? parts[2] : null;
    final episodeIndex = parts.length == 4 ? int.tryParse(parts[3]) : null;
    final sourceRows = await db.query('sources',
        columns: ['id', 'name', 'base_url'],
        where: 'external_id=?',
        whereArgs: [sourceKey]);
    Map<String, Object?>? source;
    if (sourceRows.isNotEmpty) {
      source = sourceRows.first;
    } else {
      for (final candidate
          in await db.query('sources', columns: ['id', 'name', 'base_url'])) {
        try {
          if (hubSourceKey(candidate['base_url']! as String) == sourceKey) {
            source = candidate;
            break;
          }
        } on FormatException {
          continue;
        }
      }
    }
    if (source == null) return;
    final sourceId = source['id']! as String;
    final existingSnapshots = await db.query('media_snapshots',
        where: 'source_id=? AND remote_id=?',
        whereArgs: [sourceId, vodId],
        limit: 1);
    final mediaId = existingSnapshots.isEmpty
        ? 'hub:$sourceKey:${syncEncode(vodId)}'
        : existingSnapshots.first['media_id']! as String;
    final payload = item.payload ?? const <String, Object?>{};
    if (existingSnapshots.isEmpty && !item.deleted) {
      await db.insert(
          'media_snapshots',
          {
            'media_id': mediaId,
            'title': payload['title'] as String? ?? 'Hub 媒体',
            'description': '',
            'year': 0,
            'kind': lineName == null
                ? MediaKind.movie.index
                : MediaKind.series.index,
            'poster_url': '',
            'backdrop_url': '',
            'genres_json': '[]',
            'rating': 0.0,
            'duration_ms': (payload['duration_ms'] as num?)?.toInt() ?? 0,
            'source_id': sourceId,
            'source_name': source['name'],
            'remote_id': vodId,
            'category': payload['category'] as String? ?? '',
            'category_id': null,
            'updated_at': item.updatedAt,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    if (item.entity == 'favorite') {
      if (item.deleted) {
        await db.delete('favorites', where: 'media_id=?', whereArgs: [mediaId]);
      } else {
        await db.insert(
            'favorites',
            {
              'media_id': mediaId,
              'created_at':
                  (payload['added_at'] as num?)?.toInt() ?? item.updatedAt,
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      return;
    }
    final hasEpisode = lineName != null || episodeIndex != null;
    final progressRows = await db.query('progress',
        where: hasEpisode
            ? 'media_id=? AND episode_label=? AND episode_number=?'
            : 'media_id=? AND episode_label IS NULL AND episode_number IS NULL',
        whereArgs: hasEpisode
            ? [mediaId, lineName ?? '', episodeIndex ?? 0]
            : [mediaId],
        limit: 1);
    if (item.deleted) {
      if (progressRows.isNotEmpty) {
        await db.delete('progress',
            where: 'progress_key=?',
            whereArgs: [progressRows.first['progress_key']]);
      }
      return;
    }
    final episodeId =
        lineName == null ? null : '$lineName:${episodeIndex ?? 0}';
    final progressKey = progressRows.isNotEmpty
        ? progressRows.first['progress_key']! as String
        : '$mediaId:${episodeId ?? ''}';
    await db.insert(
        'progress',
        {
          'progress_key': progressKey,
          'media_id': mediaId,
          'episode_id': episodeId,
          'episode_label': lineName,
          'episode_number': episodeIndex,
          'episode_count': null,
          'position_ms': (payload['position_ms'] as num?)?.toInt() ?? 0,
          'duration_ms': (payload['duration_ms'] as num?)?.toInt() ?? 0,
          'updated_at': item.updatedAt,
          'is_hidden': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _apply(DatabaseExecutor db, SyncEnvelope item) async {
    if (item.entity != 'site') {
      await _writeState(
          db, 'remote_${item.entity}:${item.key}', jsonEncode(item.toJson()));
      await _applyMediaEntity(db, item);
      return;
    }
    final rows = await db.query('sources', columns: ['id', 'base_url']);
    if (item.deleted) {
      for (final row in rows) {
        try {
          if (hubSourceKey(row['base_url']! as String) == item.key) {
            await db.delete('sources', where: 'id=?', whereArgs: [row['id']]);
          }
        } on FormatException {
          continue;
        }
      }
      return;
    }
    final payload = item.payload ?? const <String, Object?>{};
    await _writeState(db, 'remote_site:${item.key}', jsonEncode(payload));
    final site = decodeSitePayload(item.key, payload);
    if (!site.isKnownType) {
      await db.delete('sources',
          where: 'external_id=? OR id=?',
          whereArgs: [item.key, 'hub-${item.key}']);
      return;
    }
    final type = switch (site.siteType) {
      'json' => MediaSourceType.jsonApi,
      'direct' => MediaSourceType.direct,
      _ => MediaSourceType.macCmsApi
    };
    await db.insert(
        'sources',
        {
          'id': 'hub-${item.key}',
          'name': payload['name'] ?? 'Hub 站点',
          'type': type.index,
          'base_url': payload['api'] ?? '',
          'enabled': payload['enabled'] == false ? 0 : 1,
          'external_id': item.key,
          'detail_url': payload['detail_url'],
          'is_adult': payload['is_adult'] == true ? 1 : 0,
          'cache_ttl_seconds': payload['cache_ttl_seconds'],
          'is_default': payload['is_default'] == true ? 1 : 0,
          'cover_mode': payload['cover_mode'] == 'landscape' ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  void _scheduleRetry({int? retryAfterSeconds}) {
    _retryTimer?.cancel();
    final delay = retryDelay(
        attempt: _retryAttempt++, retryAfterSeconds: retryAfterSeconds);
    _retryTimer = Timer(delay, () {
      unawaited(pushOutbox(trigger: 'retry').catchError((Object _) {}));
    });
  }

  Future<void> _queueLocalData(DatabaseExecutor db) async {
    final sources = await db.query('sources');
    for (final row in sources) {
      final index = row['type'] as int;
      if (index < 0 || index >= MediaSourceType.values.length) continue;
      final source = MediaSource(
          id: row['id'] as String,
          name: row['name'] as String,
          type: MediaSourceType.values[index],
          baseUrl: row['base_url'] as String,
          enabled: row['enabled'] == 1,
          detailUrl: row['detail_url'] as String?,
          isAdult: row['is_adult'] == 1,
          cacheTtlSeconds: row['cache_ttl_seconds'] as int?,
          isDefault: row['is_default'] == 1,
          coverMode: row['cover_mode'] == 1
              ? MediaCoverMode.landscape
              : MediaCoverMode.portrait);
      SyncEnvelope? envelope;
      try {
        envelope = siteEnvelope(source,
            updatedAt: DateTime.now().millisecondsSinceEpoch);
      } on FormatException {
        // A malformed local URL must not prevent other entities syncing.
        continue;
      }
      if (envelope != null) {
        final marker = 'local_site:${envelope.key}';
        final serialized = jsonEncode(envelope.payload);
        if (await _state(db, marker) != serialized) {
          await enqueue(db, envelope);
          await _writeState(db, marker, serialized);
        }
      }
    }
    final activeHistoryKeys = <String>{};
    final progress = await db.rawQuery(
        'SELECT p.*,m.title,m.remote_id,s.base_url FROM progress p LEFT JOIN media_snapshots m ON m.media_id=p.media_id LEFT JOIN sources s ON s.id=m.source_id');
    for (final row in progress) {
      final base = row['base_url'] as String?;
      final vod = row['remote_id'] as String?;
      if (base == null || vod == null) continue;
      try {
        final key = hubMediaKey(
            sourceKey: hubSourceKey(base),
            vodId: vod,
            lineName: row['episode_label'] as String?,
            episodeIndex: row['episode_number'] as int?);
        final payload = <String, Object?>{
          'title': row['title'] ?? '',
          'line_name': row['episode_label'] ?? '',
          'episode_index': row['episode_number'] ?? 0,
          'position_ms': row['position_ms'],
          'duration_ms': row['duration_ms']
        };
        final sentKey = 'local_history:$key';
        activeHistoryKeys.add(sentKey);
        final updatedAt = row['updated_at'] as int;
        if (int.tryParse(await _state(db, sentKey) ?? '') != updatedAt) {
          await enqueue(
              db,
              SyncEnvelope(
                  entity: 'history',
                  key: key,
                  updatedAt: updatedAt,
                  deleted: false,
                  payload: payload));
          await enqueue(
              db,
              SyncEnvelope(
                  entity: 'progress',
                  key: key,
                  updatedAt: updatedAt,
                  deleted: false,
                  payload: payload));
          await _writeState(db, sentKey, '$updatedAt');
        }
      } on FormatException {
        continue;
      }
    }
    final previousHistory = await db.query('hub_sync_state',
        columns: ['state_key'], where: "state_key LIKE 'local_history:%'");
    for (final row in previousHistory) {
      final marker = row['state_key']! as String;
      if (activeHistoryKeys.contains(marker)) continue;
      final key = marker.substring('local_history:'.length);
      final updatedAt = DateTime.now().millisecondsSinceEpoch;
      for (final entity in ['history', 'progress']) {
        await enqueue(
            db,
            SyncEnvelope(
              entity: entity,
              key: key,
              updatedAt: updatedAt,
              deleted: true,
              payload: null,
            ));
      }
      await db
          .delete('hub_sync_state', where: 'state_key=?', whereArgs: [marker]);
    }
    final activeFavoriteKeys = <String>{};
    final favorites = await db.rawQuery(
        'SELECT f.*,m.title,m.category,m.remote_id,s.base_url FROM favorites f LEFT JOIN media_snapshots m ON m.media_id=f.media_id LEFT JOIN sources s ON s.id=m.source_id');
    for (final row in favorites) {
      final base = row['base_url'] as String?;
      final vod = row['remote_id'] as String?;
      if (base == null || vod == null) continue;
      try {
        final updatedAt = row['created_at'] as int;
        final key = hubMediaKey(sourceKey: hubSourceKey(base), vodId: vod);
        final sentKey = 'local_favorite:$key';
        activeFavoriteKeys.add(sentKey);
        if (int.tryParse(await _state(db, sentKey) ?? '') != updatedAt) {
          await enqueue(
              db,
              SyncEnvelope(
                  entity: 'favorite',
                  key: key,
                  updatedAt: updatedAt,
                  deleted: false,
                  payload: {
                    'title': row['title'] ?? '',
                    'category': row['category'] ?? '',
                    'added_at': updatedAt
                  }));
          await _writeState(db, sentKey, '$updatedAt');
        }
      } on FormatException {
        continue;
      }
    }
    final previousFavorites = await db.query('hub_sync_state',
        columns: ['state_key'], where: "state_key LIKE 'local_favorite:%'");
    for (final row in previousFavorites) {
      final marker = row['state_key']! as String;
      if (activeFavoriteKeys.contains(marker)) continue;
      final key = marker.substring('local_favorite:'.length);
      await enqueue(
          db,
          SyncEnvelope(
            entity: 'favorite',
            key: key,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
            deleted: true,
            payload: null,
          ));
      await db
          .delete('hub_sync_state', where: 'state_key=?', whereArgs: [marker]);
    }
  }

  Future<void> enqueue(DatabaseExecutor db, SyncEnvelope item) => db.insert(
      'hub_outbox',
      {
        'entity': item.entity,
        'record_key': item.key,
        'updated_at': item.updatedAt,
        'deleted': item.deleted ? 1 : 0,
        'payload_json': item.payload == null ? null : jsonEncode(item.payload),
        'attempts': 0,
        'next_attempt_at': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> _writeState(DatabaseExecutor db, String key, String value) =>
      db.insert('hub_sync_state', {'state_key': key, 'value': value},
          conflictAlgorithm: ConflictAlgorithm.replace);
  Future<String?> _state(DatabaseExecutor db, String key) async {
    final rows = await db.query('hub_sync_state',
        columns: ['value'], where: 'state_key=?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.single['value'] as String;
  }
}
