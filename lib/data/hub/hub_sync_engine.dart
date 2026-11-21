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

  Future<Map<String, int>> _acknowledgePush(Database db,
      List<Map<String, Object?>> rows, Map<String, Object?> result) async {
    final accepted = result['accepted'];
    final ignored = result['ignored'];
    final confirmed = <String>{};
    String identity(Object? entity, Object? key) => jsonEncode([entity, key]);
    final expected =
        rows.map((row) => identity(row['entity'], row['record_key'])).toSet();
    var acceptedCount = 0;
    var ignoredCount = 0;
    if (accepted is List && ignored is List) {
      for (final group in [accepted, ignored]) {
        for (final entry in group) {
          if (entry is! Map ||
              entry['entity'] is! String ||
              entry['key'] is! String) {
            throw const FormatException('服务器确认格式错误');
          }
          final key = identity(entry['entity'], entry['key']);
          if (!expected.contains(key) || !confirmed.add(key)) {
            throw const FormatException('服务器确认记录不匹配');
          }
        }
      }
      acceptedCount = accepted.length;
      ignoredCount = ignored.length;
    } else if (accepted is int &&
        ignored is int &&
        accepted >= 0 &&
        ignored >= 0 &&
        accepted + ignored == rows.length) {
      confirmed.addAll(expected);
      acceptedCount = accepted;
      ignoredCount = ignored;
    } else {
      throw const FormatException('服务器确认格式错误');
    }
    await db.transaction((txn) async {
      for (final row in rows) {
        if (!confirmed.contains(identity(row['entity'], row['record_key']))) {
          continue;
        }
        final payload = row['payload_json'];
        await txn.delete('hub_outbox',
            where:
                'entity=? AND record_key=? AND updated_at=? AND deleted=? AND '
                '${payload == null ? 'payload_json IS NULL' : 'payload_json=?'}',
            whereArgs: [
              row['entity'],
              row['record_key'],
              row['updated_at'],
              row['deleted'],
              if (payload != null) payload
            ]);
      }
    });
    return {
      'accepted': acceptedCount,
      'ignored': ignoredCount,
      'confirmed': confirmed.length
    };
  }

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

  Map<String, Object?> _syncVideo(Map<String, Object?> row) => {
        'id': row['media_id'] ?? '',
        'sourceId': row['source_id'] ?? '',
        'sourceName': row['source_name'] ?? '',
        'remoteId': row['remote_id'] ?? '',
        'title': row['title'] ?? '',
        'category': row['category'] ?? '',
        'year': '${row['year'] ?? ''}',
        'description': row['description'] ?? '',
        'posterUrl': row['poster_url'] ?? '',
        'rating': '${row['rating'] ?? ''}',
      };

  Future<void> pushProgress(MediaItem media, WatchProgress progress) async {
    if (!_unambiguousHistory(
        media.kind.index, progress.lineName, progress.episodeNumber)) {
      return;
    }
    final db = await repository.hubDatabase;
    final rows = await db.rawQuery('''
      SELECT m.media_id,m.title,m.category,m.kind,m.poster_url,m.remote_id,m.source_id,m.source_name,m.year,m.description,m.rating,s.base_url
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
        lineName: progress.lineName,
        episodeIndex: progress.episodeNumber == null
            ? null
            : progress.episodeNumber! - 1);
    final historyKey =
        hubMediaKey(sourceKey: sourceKey, vodId: row['remote_id']! as String);
    if (await _hasUnsafeHistoryForMedia(db, row['base_url']! as String,
        row['remote_id']! as String, historyKey)) {
      throw StateError('此视频的历史待同步记录存在冲突，已保留');
    }
    final payload = <String, Object?>{
      'title': row['title'] ?? media.title,
      'category': row['category'] ?? '',
      'cineo_media_kind': row['kind'],
      'source_api': row['base_url'],
      'source_key': sourceKey,
      'video': _syncVideo(row),
      'line_name': progress.lineName ?? '',
      'episode_title': progress.episodeLabel ?? '',
      'cineo_index_base': 0,
      'episode_index': (progress.episodeNumber ?? 1) - 1,
      'position_ms': progress.position.inMilliseconds,
      'duration_ms': progress.duration.inMilliseconds
    };
    await enqueue(
        db,
        SyncEnvelope(
            entity: 'progress',
            key: key,
            updatedAt: progress.updatedAt.millisecondsSinceEpoch,
            deleted: false,
            payload: payload));
    await _pushSingle(db, 'progress', key, 'auto_progress');
  }

  Future<void> queueFavorite(MediaItem media, bool isFavorite) async {
    final db = await repository.hubDatabase;
    final rows = await db.rawQuery('''
      SELECT m.title,m.category,m.poster_url,m.remote_id,s.base_url
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
                    'video': {
                      'posterUrl': row['poster_url'] ?? media.posterUrl
                    },
                    'added_at': updatedAt
                  }
                : null));
    await _pushSingle(db, 'favorite', key, 'auto_favorite');
  }

  Future<void> _pushSingle(
      Database db, String entity, String key, String trigger) async {
    if (_pushRunning || _pushAllRunning) throw StateError('已有推送任务进行中');
    if (!await api.credentials.isBound) return;
    if (await _state(db, 'resync_pending') == 'true') {
      throw StateError('待同步操作已隔离，请先处理重建');
    }
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
      if (!await _batchStillCurrent(db, rows)) {
        throw StateError('待同步记录已变化，请重试');
      }
      final result = await api.push([item], trigger: trigger);
      final ack = await _acknowledgePush(db, rows, result);
      if (ack['confirmed'] != rows.length) {
        throw const FormatException('服务器响应不完整，待同步记录已保留');
      }
    } on FormatException catch (error) {
      await _writeState(db, 'last_error', error.message.toString());
      if (entity != 'progress') {
        _scheduleRetry(operation: () => _pushSingle(db, entity, key, 'retry'));
      }
      rethrow;
    } on HubApiException catch (error) {
      if (error.revoked) {
        await _writeState(db, 'revoked', 'true');
      } else if (error.code == 40000) {
        _retryTimer?.cancel();
      } else {
        if (entity != 'progress') {
          _scheduleRetry(
              retryAfterSeconds: error.retryAfterSeconds,
              operation: () => _pushSingle(db, entity, key, 'retry'));
        }
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

  /// Candidates are limited to held legacy/deletion envelopes. Valid marked
  /// envelopes held only because another item conflicts are never discarded.
  Future<List<Map<String, Object?>>> _clearableConflicts(
      DatabaseExecutor db) async {
    final rows =
        await db.query('hub_outbox', where: "entity IN ('history','progress')");
    final safe = await _safeOutboxRows(db, rows);
    final safeIds =
        safe.map((row) => '${row['entity']}:${row['record_key']}').toSet();
    return rows.where((row) {
      if (safeIds.contains('${row['entity']}:${row['record_key']}')) {
        return false;
      }
      if (row['deleted'] == 1) return true;
      try {
        final payload = jsonDecode(row['payload_json'] as String);
        return payload is! Map || payload['cineo_index_base'] != 0;
      } catch (_) {
        return true;
      }
    }).toList();
  }

  Future<List<Map<String, Object?>>> conflictSnapshot() async =>
      _clearableConflicts(await repository.hubDatabase);

  Future<int> get clearableConflictCount async =>
      (await conflictSnapshot()).length;

  Future<int> clearConflictOutbox(List<Map<String, Object?>> snapshot) async {
    if (isRunning) throw StateError('同步进行中，请稍后重试');
    final db = await repository.hubDatabase;
    return db.transaction((txn) async {
      final rows = await _clearableConflicts(txn);
      final allowed = rows
          .map((row) => jsonEncode([
                row['entity'],
                row['record_key'],
                row['updated_at'],
                row['deleted'],
                row['payload_json']
              ]))
          .toSet();
      var removed = 0;
      for (final row in snapshot) {
        if (!allowed.contains(jsonEncode([
          row['entity'],
          row['record_key'],
          row['updated_at'],
          row['deleted'],
          row['payload_json']
        ]))) continue;
        final payload = row['payload_json'];
        removed += await txn.delete('hub_outbox',
            where:
                'entity=? AND record_key=? AND updated_at=? AND deleted=? AND '
                "${payload == null ? 'payload_json IS NULL' : 'payload_json=?'}",
            whereArgs: [
              row['entity'],
              row['record_key'],
              row['updated_at'],
              row['deleted'],
              if (payload != null) payload
            ]);
      }
      return removed;
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
      final queued = await db.query('hub_outbox', orderBy: 'updated_at');
      final rows = await _safeOutboxRows(db, queued);
      if (rows.isEmpty) return;
      var index = 0;
      while (index < rows.length) {
        final batchRows = <Map<String, Object?>>[];
        final items = <Map<String, Object?>>[];
        var bytes = utf8.encode('{"items":[]}').length;
        while (index < rows.length && items.length < 500) {
          final row = rows[index];
          final item = <String, Object?>{
            'entity': row['entity'],
            'key': row['record_key'],
            'updated_at': row['updated_at'],
            'deleted': row['deleted'] == 1,
            'payload': row['payload_json'] == null
                ? null
                : jsonDecode(row['payload_json']! as String),
          };
          final size =
              utf8.encode(jsonEncode(item)).length + (items.isEmpty ? 0 : 1);
          if (bytes + size > 1024 * 1024) {
            if (items.isEmpty) {
              throw const FormatException('单条记录超过 1 MB，待同步记录已保留');
            }
            break;
          }
          bytes += size;
          items.add(item);
          batchRows.add(row);
          index++;
        }
        if ((await _safeOutboxRows(db, batchRows)).length != batchRows.length) {
          throw StateError('历史待同步记录存在冲突，已保留');
        }
        if (!await _batchStillCurrent(db, batchRows)) {
          throw StateError('待同步记录已变化，请重试');
        }
        final result = await api.push(items, trigger: trigger);
        final ack = await _acknowledgePush(db, batchRows, result);
        if (ack['confirmed'] != batchRows.length) {
          throw const FormatException('服务器响应不完整，待同步记录已保留');
        }
      }
      _retryAttempt = 0;
      _retryTimer?.cancel();
    } on FormatException catch (error) {
      await _writeState(db, 'last_error', error.message.toString());
      if (error.message.toString().contains('超过 1 MB')) {
        _retryTimer?.cancel();
      } else {
        _scheduleRetry();
      }
      rethrow;
    } on HubApiException catch (error) {
      if (error.revoked) {
        await _writeState(db, 'revoked', 'true');
      } else if (error.code == 40000) {
        _retryTimer?.cancel();
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
      if (await _state(db, 'resync_pending') == 'true') {
        final count = Sqflite.firstIntValue(
                await db.rawQuery('SELECT COUNT(*) FROM hub_outbox')) ??
            0;
        return {
          'sent': 0,
          'total': count,
          'accepted': 0,
          'ignored': 0,
          'failed': count,
          'error': '旧待同步操作已隔离，请先处理重建'
        };
      }
      await _queueLocalData(db);
      final allRows = await db.query('hub_outbox', orderBy: 'updated_at');
      final safeRows = await _safeOutboxRows(db, allRows);
      final held = allRows.length - safeRows.length;
      final total = allRows.length;
      var sent = 0;
      var accepted = 0;
      var ignored = 0;
      var failed = 0;
      String? errorMessage;
      var offset = 0;
      while (offset < safeRows.length) {
        final rows = safeRows.skip(offset).take(500).toList();
        final batch = <Map<String, Object?>>[];
        final batchRows = <Map<String, Object?>>[];
        var bytes = utf8.encode('{"items":[]}').length;
        var oversized = false;
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
            oversized = true;
            break;
          }
          batch.add(item);
          batchRows.add(row);
          bytes += itemBytes;
        }
        if (batch.isEmpty && oversized) {
          failed = total - sent;
          errorMessage = '单条记录超过 1 MB，未发送的记录已保留';
          break;
        }
        if (batch.isEmpty) break;
        if ((await _safeOutboxRows(db, batchRows)).length != batchRows.length ||
            !await _batchStillCurrent(db, batchRows)) {
          failed = total - sent;
          errorMessage = '待同步记录已变化或存在冲突，已保留';
          break;
        }
        try {
          final result = await api.push(batch, trigger: 'full_push');
          final ack = await _acknowledgePush(db, batchRows, result);
          accepted += ack['accepted']!;
          ignored += ack['ignored']!;
          if (ack['confirmed'] != batch.length) {
            sent += ack['confirmed']!;
            failed = total - sent;
            errorMessage = '服务器未确认部分记录，未确认记录已保留';
            break;
          }
          sent += batch.length;
          offset += batch.length;
          onProgress?.call(sent + failed, total);
        } on FormatException {
          failed = total - sent;
          errorMessage = '服务器响应不完整或无效，本批可能已成功，待同步记录已保留';
          break;
        } on HubApiException catch (error) {
          failed += total - sent - failed;
          errorMessage = '${error.safeMessage}；本批可能已成功，待同步记录已保留';
          break;
        }
      }
      if (failed == 0 && held > 0) {
        failed = held;
        errorMessage = '保留 $held 条身份不明或存在冲突的待同步记录';
      }
      var postersUpdated = 0;
      if (failed == 0 || held > 0) {
        try {
          postersUpdated =
              await _fillLocalPosters(db, verifiedRemoteOnly: held > 0);
          if (held > 0) errorMessage = '$errorMessage；已补全 $postersUpdated 条封面';
        } on HubApiException catch (error) {
          errorMessage = '封面补全失败，可再次全量同步重试：${error.safeMessage}';
        } on FormatException {
          errorMessage = '封面补全响应无效，可再次全量同步重试';
        }
      }
      return {
        'sent': sent,
        'total': total,
        'accepted': accepted,
        'ignored': ignored,
        'failed': failed,
        'posters_updated': postersUpdated,
        if (errorMessage != null) 'error': errorMessage
      };
    } finally {
      _activeOperations.remove('pushAll');
    }
  }

  // Only exact cached Hub history keys can recover ambiguous legacy rows.
  Future<int> _fillLocalPosters(DatabaseExecutor db,
      {bool verifiedRemoteOnly = false}) async {
    Future<List<Map<String, Object?>>> collectCandidates() async {
      final counts = <String, int>{};
      final candidates = <String, Map<String, Object?>>{};
      for (final entity
          in verifiedRemoteOnly ? <String>[] : ['history', 'favorite']) {
        final rows = await db.rawQuery(entity == 'history'
            ? 'SELECT p.episode_label,p.episode_number,m.kind,m.poster_url,m.remote_id,s.base_url FROM progress p JOIN media_snapshots m ON m.media_id=p.media_id JOIN sources s ON s.id=m.source_id'
            : 'SELECT m.poster_url,m.remote_id,s.base_url FROM favorites f JOIN media_snapshots m ON m.media_id=f.media_id JOIN sources s ON s.id=m.source_id');
        for (final row in rows) {
          final base = row['base_url'] as String?;
          final vod = row['remote_id'] as String?;
          final poster = (row['poster_url'] as String? ?? '').trim();
          final uri = Uri.tryParse(poster);
          if (base == null || vod == null || vod.isEmpty) continue;
          final ambiguous = entity == 'history' &&
              !_unambiguousHistory(
                  row['kind'] as int?,
                  row['episode_label'] as String?,
                  row['episode_number'] as int?);
          try {
            final key = hubMediaKey(
                sourceKey: hubSourceKey(base),
                vodId: vod,
                lineName: entity == 'history'
                    ? row['episode_label'] as String?
                    : null,
                episodeIndex:
                    entity == 'history' ? row['episode_number'] as int? : null);
            final identity = jsonEncode([entity, key]);
            counts[identity] = (counts[identity] ?? 0) + 1;
            if (ambiguous) continue;
            if (uri == null ||
                !{'http', 'https'}.contains(uri.scheme) ||
                uri.host.isEmpty ||
                uri.userInfo.isNotEmpty ||
                poster.length > 4096) continue;
            candidates[identity] = {
              'entity': entity,
              'key': key,
              'poster_url': poster
            };
          } on FormatException {
            continue;
          }
        }
      }
      // Count legacy progress identities even when ordinary candidate creation
      // is disabled by a conflicting outbox. Duplicate rows are not evidence
      // that either mapping is safe.
      final legacyCounts = <String, int>{};
      final legacyRows = await db.rawQuery(
          'SELECT p.episode_label,p.line_name,p.episode_number,m.remote_id,s.base_url FROM progress p JOIN media_snapshots m ON m.media_id=p.media_id JOIN sources s ON s.id=m.source_id');
      for (final row in legacyRows) {
        final base = row['base_url'] as String?;
        final vod = row['remote_id'] as String?;
        final number = row['episode_number'] as int?;
        final possibleLines = <String>{
          if (row['episode_label'] is String &&
              (row['episode_label'] as String).isNotEmpty)
            row['episode_label'] as String,
          if (row['line_name'] is String &&
              (row['line_name'] as String).isNotEmpty)
            row['line_name'] as String,
        };
        if (base == null ||
            vod == null ||
            vod.isEmpty ||
            number == null ||
            number < 0) continue;
        try {
          for (final line in possibleLines) {
            final key = hubMediaKey(
                sourceKey: hubSourceKey(base),
                vodId: vod,
                lineName: line,
                episodeIndex: number);
            legacyCounts[key] = (legacyCounts[key] ?? 0) + 1;
          }
        } on FormatException {
          continue;
        }
      }
      // Cached envelopes retain the actual key, including legacy episode
      // indices. All same-source snapshots must agree on a valid cover.
      // An orphan snapshot with the same remote ID is ambiguous and blocks it.
      final snapshots = await db.rawQuery(
          'SELECT m.media_id,m.remote_id,m.poster_url,s.base_url FROM media_snapshots m LEFT JOIN sources s ON s.id=m.source_id');
      final mediaByKey = <String, List<String>>{};
      final unresolvedVods = <String>{};
      for (final row in snapshots) {
        final base = row['base_url'] as String?;
        final vod = row['remote_id'] as String?;
        if (vod == null || vod.isEmpty) continue;
        if (base == null) {
          unresolvedVods.add(vod);
          continue;
        }
        try {
          final key = hubMediaKey(sourceKey: hubSourceKey(base), vodId: vod);
          mediaByKey
              .putIfAbsent(key, () => [])
              .add(row['poster_url'] as String? ?? '');
        } on FormatException {
          unresolvedVods.add(vod);
          continue;
        }
      }
      final deletedPending = await db.query('hub_outbox',
          columns: ['record_key'], where: "entity='history' AND deleted=1");
      final pendingDeletes = deletedPending.map((r) => r['record_key']).toSet();
      final cached = await db.query('hub_sync_state',
          columns: ['state_key', 'value'],
          where: "state_key LIKE 'remote_history:%'");
      for (final row in cached) {
        // Never let a malformed cached envelope fall back to the weaker
        // ordinary candidate path for the same key.
        final stateKey = row['state_key'] as String;
        final cachedKey = stateKey.substring('remote_history:'.length);
        candidates.remove(jsonEncode(['history', cachedKey]));
        try {
          final value = jsonDecode(row['value'] as String);
          if (value is! Map) continue;
          final record = SyncEnvelope.fromJson(value.cast<String, Object?>());
          if (record.entity != 'history' ||
              row['state_key'] != 'remote_history:${record.key}') continue;
          // A cached record must always pass the stronger snapshot rule.
          final identity = jsonEncode(['history', record.key]);
          candidates.remove(identity);
          if (record.deleted || pendingDeletes.contains(record.key)) continue;
          final encodedParts = record.key.split(':');
          if (encodedParts.length != 2 && encodedParts.length != 4) continue;
          final parts = encodedParts.map(Uri.decodeComponent).toList();
          if (parts.any((part) => part.isEmpty) ||
              (parts.length == 4 &&
                  (int.tryParse(parts[3]) == null ||
                      int.parse(parts[3]) < 0)) ||
              parts.map(syncEncode).join(':') != record.key) continue;
          final mediaKey = hubMediaKey(sourceKey: parts[0], vodId: parts[1]);
          final posters = mediaByKey[mediaKey];
          if (unresolvedVods.contains(parts[1]) ||
              posters == null ||
              posters.isEmpty ||
              posters.any((value) => value != posters.first)) continue;
          final poster = posters.first;
          final uri = Uri.tryParse(poster);
          if (uri == null ||
              !{'http', 'https'}.contains(uri.scheme) ||
              uri.host.isEmpty ||
              uri.userInfo.isNotEmpty ||
              poster.length > 4096) continue;
          // A duplicate local progress mapping remains ambiguous.
          if ((counts[identity] ?? 0) > 1 ||
              (legacyCounts[record.key] ?? 0) > 1) {
            continue;
          }
          candidates[identity] = {
            'entity': 'history',
            'key': record.key,
            'poster_url': poster,
          };
          counts[identity] = 1;
        } on FormatException {
          continue;
        } on TypeError {
          continue;
        }
      }
      for (final key in pendingDeletes) {
        candidates.remove(jsonEncode(['history', key]));
      }
      return candidates.entries
          .where((e) => counts[e.key] == 1)
          .map((e) => e.value)
          .toList();
    }

    final items = await collectCandidates();
    var updated = 0;
    for (var i = 0; i < items.length; i += 100) {
      // Re-evaluate all evidence after the previous network request. A
      // changed mapping or cover invalidates the original candidate.
      final current = {
        for (final candidate in await collectCandidates())
          jsonEncode([candidate['entity'], candidate['key']]): candidate,
      };
      final batch =
          items.sublist(i, (i + 100).clamp(0, items.length)).where((item) {
        final candidate = current[jsonEncode([item['entity'], item['key']])];
        return candidate != null &&
            candidate['poster_url'] == item['poster_url'];
      }).toList();
      if (batch.isEmpty) continue;
      final response = await api.fillPosters(batch);
      final count = response['updated'];
      if (count is! int || count < 0 || count > batch.length) {
        throw const FormatException('封面补全响应无效');
      }
      updated += count;
    }
    return updated;
  }

  bool _unambiguousHistory(int? kind, String? line, int? number) {
    final hasLine = line != null && line.trim().isNotEmpty;
    if (hasLine && number != null && number > 0) return true;
    return !hasLine && number == null && kind == MediaKind.movie.index;
  }

  Future<bool> _hasUnsafeHistoryForMedia(
      DatabaseExecutor db, String base, String vod, String historyKey) async {
    final rows = await db.rawQuery('''
      SELECT p.line_name,p.episode_number,m.kind FROM progress p
      JOIN media_snapshots m ON m.media_id=p.media_id
      JOIN sources s ON s.id=m.source_id
      WHERE s.base_url=? AND m.remote_id=?
    ''', [base, vod]);
    final active = <String>{historyKey};
    for (final row in rows) {
      final line = row['line_name'] as String?;
      final number = row['episode_number'] as int?;
      if (!_unambiguousHistory(row['kind'] as int?, line, number)) return true;
      final key = hubMediaKey(
          sourceKey: hubSourceKey(base),
          vodId: vod,
          lineName: line,
          episodeIndex: number == null ? null : number - 1);
      if (!active.add('progress:$key')) return true;
    }
    final pending = await db.query('hub_outbox',
        columns: ['entity', 'record_key', 'deleted', 'payload_json'],
        where: "entity IN ('history','progress')");
    return pending.any((row) {
      final key = row['record_key'] as String;
      if (key != historyKey && !key.startsWith('$historyKey:')) return false;
      if (row['deleted'] == 1) return true;
      final exists = row['entity'] == 'history'
          ? key == historyKey
          : active.contains('progress:$key');
      if (!exists) return true;
      try {
        final payload = jsonDecode(row['payload_json'] as String);
        if (payload is! Map || payload['cineo_index_base'] != 0) return true;
        final video = payload['video'];
        if (payload['source_api'] != base ||
            video is! Map ||
            video['remoteId'] != vod) return true;
        if (row['entity'] == 'progress') {
          final line = payload['line_name'];
          final index = payload['episode_index'];
          if (line is! String || index is! int || index < 0) return true;
          final expected = line.isEmpty
              ? historyKey
              : hubMediaKey(
                  sourceKey: hubSourceKey(base),
                  vodId: vod,
                  lineName: line,
                  episodeIndex: index);
          if (key != expected) return true;
        }
        return false;
      } catch (_) {
        return true;
      }
    });
  }

  Future<List<Map<String, Object?>>> _safeOutboxRows(
      DatabaseExecutor db, List<Map<String, Object?>> rows) async {
    final media = await db.rawQuery(
        'SELECT DISTINCT m.remote_id,s.base_url FROM progress p JOIN media_snapshots m ON m.media_id=p.media_id JOIN sources s ON s.id=m.source_id');
    final identities = <String, (String, String)>{};
    for (final row in media) {
      final base = row['base_url'] as String?;
      final vod = row['remote_id'] as String?;
      if (base == null || vod == null || vod.isEmpty) continue;
      try {
        identities[hubMediaKey(sourceKey: hubSourceKey(base), vodId: vod)] =
            (base, vod);
      } on FormatException {
        continue;
      }
    }
    final safety = <String, bool>{};
    final safe = <Map<String, Object?>>[];
    for (final row in rows) {
      if (row['entity'] != 'history' && row['entity'] != 'progress') {
        safe.add(row);
        continue;
      }
      final parts = (row['record_key'] as String).split(':');
      if (parts.length != 2 && parts.length != 4) continue;
      final key = parts.take(2).join(':');
      final identity = identities[key];
      if (identity == null) continue;
      safety[key] ??=
          !await _hasUnsafeHistoryForMedia(db, identity.$1, identity.$2, key);
      if (safety[key]!) safe.add(row);
    }
    return safe;
  }

  Future<bool> _batchStillCurrent(
      DatabaseExecutor db, List<Map<String, Object?>> rows) async {
    for (final row in rows) {
      final current = await db.query('hub_outbox',
          where: 'entity=? AND record_key=?',
          whereArgs: [row['entity'], row['record_key']],
          limit: 1);
      if (current.isEmpty ||
          current.single['updated_at'] != row['updated_at'] ||
          current.single['deleted'] != row['deleted'] ||
          current.single['payload_json'] != row['payload_json']) return false;
    }
    return true;
  }

  Future<void> sync() async {
    await pullAndApply(trigger: 'launch_pull');
  }

  Future<bool> _pull(DatabaseExecutor db,
      {String trigger = 'launch_pull'}) async {
    var cursor = int.tryParse(await _state(db, 'cursor') ?? '') ?? 0;
    var generation = int.tryParse(await _state(db, 'generation') ?? '') ?? 0;
    var rebuilt = false;
    late Map<String, Object?> page;
    final snapshotKeys = <String>{};
    try {
      page = await api.pull(cursor, trigger: trigger);
    } on HubApiException catch (e) {
      if (!e.resyncRequired) rethrow;
      rebuilt = true;
      final originalGeneration = generation;
      final pages = <Map<String, Object?>>[];
      for (var attempt = 0;; attempt++) {
        pages.clear();
        var next = 0;
        try {
          while (true) {
            final current =
                await api.rebuild(generation: originalGeneration, cursor: next);
            pages.add(current);
            if (current['has_more'] != true) break;
            final following = (current['next_seq'] as num?)?.toInt();
            if (following == null || following <= next) {
              throw const FormatException('重建游标无效');
            }
            next = following;
          }
          break;
        } on HubApiException catch (failure) {
          if (!failure.resyncRequired || attempt >= 2) rethrow;
        }
      }
      for (final snapshotPage in pages) {
        generation =
            (snapshotPage['generation'] as num?)?.toInt() ?? generation;
        for (final raw
            in (snapshotPage['items'] as List? ?? const []).whereType<Map>()) {
          final envelope = SyncEnvelope.fromJson(raw.cast<String, Object?>());
          snapshotKeys.add('remote_${envelope.entity}:${envelope.key}');
          await _apply(db, envelope);
        }
        cursor = (snapshotPage['next_seq'] as num?)?.toInt() ?? cursor;
      }
      await _writeState(db, 'cursor', '$cursor');
      await _writeState(db, 'generation', '$generation');
    }
    if (!rebuilt) {
      do {
        generation = (page['generation'] as num?)?.toInt() ?? generation;
        for (final raw
            in (page['items'] as List? ?? const []).whereType<Map>()) {
          final envelope = SyncEnvelope.fromJson(raw.cast<String, Object?>());
          await _apply(db, envelope);
        }
        cursor = (page['next_seq'] as num?)?.toInt() ?? cursor;
        await _writeState(db, 'cursor', '$cursor');
        await _writeState(db, 'generation', '$generation');
        if (page['has_more'] != true) break;
        page = await api.pull(cursor, trigger: trigger);
      } while (true);
    }
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
                await _removeDerivedProgress(db, old);
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

  // History alone may have materialized an episode; only remove Hub-owned rows.
  Future<void> _removeDerivedProgress(
      DatabaseExecutor db, SyncEnvelope old) async {
    if (old.deleted || !const {'history', 'progress'}.contains(old.entity)) {
      return;
    }
    final parts = old.key.split(':');
    if (parts.length != 2 && parts.length != 4) return;
    final filmKey = parts.take(2).join(':');
    final pending = await db.query('hub_outbox',
        columns: ['record_key'], where: "entity IN ('history','progress')");
    if (pending.any((row) {
      final key = row['record_key'] as String;
      return key == filmKey || key.startsWith('$filmKey:');
    })) return;
    final sourceIds = <String>{};
    for (final source
        in await db.query('sources', columns: ['id', 'base_url'])) {
      try {
        if (hubSourceKey(source['base_url'] as String) == parts[0]) {
          sourceIds.add(source['id'] as String);
        }
      } on FormatException {
        continue;
      }
    }
    if (sourceIds.length != 1) return;
    final rows = await db.query('media_snapshots',
        columns: ['media_id'],
        where: 'source_id=? AND remote_id=?',
        whereArgs: [sourceIds.single, Uri.decodeComponent(parts[1])]);
    if (rows.length != 1) return;
    final mediaId = rows.single['media_id'] as String;
    final payload = old.payload ?? const <String, Object?>{};
    final line = payload['line_name'];
    final index = payload['episode_index'];
    if (payload['cineo_index_base'] == 0 &&
        line is String &&
        line.isNotEmpty &&
        index is int &&
        index >= 0) {
      if (parts.length == 4 &&
          (Uri.decodeComponent(parts[2]) != line ||
              int.tryParse(parts[3]) != index)) return;
      final episodeId = 'hub0:${syncEncode(line)}:$index';
      await db.delete('progress',
          where:
              'media_id=? AND episode_id=? AND line_name=? AND episode_number=? AND updated_at<=?',
          whereArgs: [mediaId, episodeId, line, index + 1, old.updatedAt]);
    } else if (parts.length == 2 &&
        payload['cineo_media_kind'] == MediaKind.movie.index) {
      final movieKey = '$mediaId:hubmovie:${syncEncode(old.key)}';
      await db.delete('progress',
          where: 'progress_key=? AND updated_at<=?',
          whereArgs: [movieKey, old.updatedAt]);
    }
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
    // New snapshots use the same identity as MacCMS detail results. Keep an
    // existing snapshot's identity intact so old progress is not orphaned.
    final canonicalMediaId = '$sourceId:$vodId';
    if (existingSnapshots.isEmpty) {
      final occupied = await db.query('media_snapshots',
          columns: ['media_id'],
          where: 'media_id=?',
          whereArgs: [canonicalMediaId],
          limit: 1);
      if (occupied.isNotEmpty) return;
    }
    final mediaId = existingSnapshots.isEmpty
        ? canonicalMediaId
        : existingSnapshots.first['media_id']! as String;
    final payload = item.payload ?? const <String, Object?>{};
    final video = payload['video'] is Map
        ? (payload['video'] as Map).cast<String, Object?>()
        : const <String, Object?>{};
    // A payload that supplies explicit source/video identity must agree with
    // its envelope key; never attach mismatched data to this source.
    if (payload['source_api'] is String &&
        (payload['source_api'] as String).isNotEmpty) {
      try {
        if (hubSourceKey(payload['source_api'] as String) != sourceKey) return;
      } on FormatException {
        return;
      }
    }
    if (video['remoteId'] is String && video['remoteId'] != vodId) return;
    final title = (payload['title'] is String
        ? payload['title']
        : video['title']) as String?;
    final poster =
        video['posterUrl'] is String ? video['posterUrl'] as String : '';
    if (existingSnapshots.isNotEmpty && !item.deleted) {
      final snapshot = existingSnapshots.first;
      final updates = <String, Object?>{};
      if ((snapshot['title'] == 'Hub 媒体' || snapshot['title'] == '') &&
          title != null &&
          title.trim().isNotEmpty) {
        updates['title'] = title;
      }
      if ((snapshot['poster_url'] as String? ?? '').isEmpty &&
          poster.trim().isNotEmpty) {
        updates['poster_url'] = poster;
      }
      if (updates.isNotEmpty) {
        await db.update('media_snapshots', updates,
            where: 'media_id=?', whereArgs: [mediaId]);
      }
    }
    if (existingSnapshots.isEmpty && !item.deleted) {
      await db.insert(
          'media_snapshots',
          {
            'media_id': mediaId,
            'title': title == null || title.trim().isEmpty ? 'Hub 媒体' : title,
            'description': '',
            'year': 0,
            'kind': payload['cineo_media_kind'] == MediaKind.movie.index ||
                    payload['cineo_media_kind'] == MediaKind.series.index
                ? payload['cineo_media_kind']
                : lineName == null
                    ? MediaKind.movie.index
                    : MediaKind.series.index,
            'poster_url': poster,
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
    if (item.deleted) {
      final filmKey = item.key.split(':').take(2).join(':');
      final pending = await db.query('hub_outbox',
          columns: ['record_key'], where: "entity IN ('history','progress')");
      if (pending.any((row) {
        final key = row['record_key'] as String;
        return key == filmKey || key.startsWith('$filmKey:');
      })) return;
      // Only a four-part progress tombstone identifies a particular episode.
      // Legacy records with ambiguous bases and local option IDs are retained.
      if (item.entity == 'progress' && parts.length == 2) {
        final movieKey = '$mediaId:hubmovie:${syncEncode(item.key)}';
        await db.delete('progress',
            where:
                'progress_key=? AND media_id=? AND episode_id IS NULL AND updated_at<=?',
            whereArgs: [movieKey, mediaId, item.updatedAt]);
      }
      if (item.entity == 'progress' &&
          parts.length == 4 &&
          lineName != null &&
          lineName.isNotEmpty &&
          episodeIndex != null &&
          episodeIndex >= 0) {
        final id = 'hub0:${syncEncode(lineName)}:$episodeIndex';
        await db.delete('progress',
            where:
                'media_id=? AND episode_id=? AND line_name=? AND episode_number=? AND updated_at<=?',
            whereArgs: [
              mediaId,
              id,
              lineName,
              episodeIndex + 1,
              item.updatedAt
            ]);
      }
      return;
    }
    // New writers explicitly declare the index base. Older payloads can
    // encode either base, so keep the previous conservative representation.
    final normalizedLine = payload['line_name'] is String
        ? (payload['line_name'] as String).trim()
        : '';
    final normalizedIndex = payload['episode_index'];
    var verifiedTvPayload = false;
    if (payload['cineo_index_base'] == null &&
        payload['source_api'] is String &&
        payload['line_index'] is int &&
        payload['episode_title'] is String &&
        video['remoteId'] == vodId) {
      try {
        verifiedTvPayload =
            hubSourceKey(payload['source_api'] as String) == sourceKey;
      } on FormatException {
        verifiedTvPayload = false;
      }
    }
    if (!item.deleted &&
        (payload['cineo_index_base'] == 0 || verifiedTvPayload) &&
        normalizedLine.isNotEmpty &&
        normalizedIndex is int &&
        normalizedIndex >= 0) {
      if (parts.length == 4 &&
          (lineName != normalizedLine || episodeIndex != normalizedIndex)) {
        return;
      }
      final remoteProgressKey = hubMediaKey(
          sourceKey: sourceKey,
          vodId: vodId,
          lineName: normalizedLine,
          episodeIndex: normalizedIndex);
      final tombstone = await _state(db, 'remote_progress:$remoteProgressKey');
      if (tombstone != null) {
        try {
          final decoded = jsonDecode(tombstone);
          if (decoded is Map) {
            final prior =
                SyncEnvelope.fromJson(decoded.cast<String, Object?>());
            if (prior.deleted && prior.updatedAt >= item.updatedAt) return;
          }
        } on FormatException {
          return;
        } on TypeError {
          return;
        }
      }
      final number = normalizedIndex + 1;
      // A pre-existing legacy row with the same raw key is ambiguous. Keep it
      // rather than guessing its index base or creating a duplicate row.
      final legacy = await db.query('progress',
          columns: ['progress_key'],
          where: 'media_id=? AND episode_id=? AND line_name IS NULL',
          whereArgs: [mediaId, '$normalizedLine:$normalizedIndex'],
          limit: 1);
      if (legacy.isNotEmpty) return;
      final existing = await db.query('progress',
          where: 'media_id=? AND line_name=? AND episode_number=?',
          whereArgs: [mediaId, normalizedLine, number]);
      if (existing.length > 1) return;
      if (existing.isNotEmpty &&
          (existing.single['updated_at'] as int) >= item.updatedAt) return;
      final id = 'hub0:${syncEncode(normalizedLine)}:$normalizedIndex';
      await db.insert(
          'progress',
          {
            'progress_key': existing.isEmpty
                ? '$mediaId:$id'
                : existing.single['progress_key'],
            'media_id': mediaId,
            'episode_id': existing.isEmpty ? id : existing.single['episode_id'],
            'episode_label': payload['episode_title'] is String
                ? payload['episode_title']
                : null,
            'line_name': normalizedLine,
            'episode_number': number,
            'episode_count':
                existing.isEmpty ? null : existing.single['episode_count'],
            'position_ms': (payload['position_ms'] as num?)?.toInt() ?? 0,
            'duration_ms': (payload['duration_ms'] as num?)?.toInt() ?? 0,
            'updated_at': item.updatedAt,
            'is_hidden': existing.isEmpty ? 0 : existing.single['is_hidden'],
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      return;
    }
    if (parts.length == 2 &&
        (item.entity == 'progress' ||
            payload['cineo_media_kind'] == MediaKind.movie.index) &&
        normalizedLine.isEmpty &&
        (existingSnapshots.isEmpty ||
            existingSnapshots.first['kind'] == MediaKind.movie.index)) {
      // A distinct local key records provenance without adopting a pre-existing
      // local or ambiguous history row as server-owned.
      final movieKey = '$mediaId:hubmovie:${syncEncode(item.key)}';
      final cachedProgress = await _state(db, 'remote_progress:${item.key}');
      if (cachedProgress != null) {
        try {
          final raw = jsonDecode(cachedProgress);
          if (raw is Map) {
            final prior = SyncEnvelope.fromJson(raw.cast<String, Object?>());
            if (prior.deleted && prior.updatedAt >= item.updatedAt) return;
          }
        } on FormatException {
          return;
        } on TypeError {
          return;
        }
      }
      final rows = await db.query('progress',
          where: 'media_id=? AND episode_id IS NULL', whereArgs: [mediaId]);
      if (rows.any((row) => row['progress_key'] != movieKey)) return;
      if (rows.isNotEmpty &&
          (rows.single['updated_at'] as int) >= item.updatedAt) return;
      await db.insert(
          'progress',
          {
            'progress_key': movieKey,
            'media_id': mediaId,
            'episode_id': null,
            'episode_label': null,
            'line_name': null,
            'episode_number': null,
            'episode_count': null,
            'position_ms': (payload['position_ms'] as num?)?.toInt() ?? 0,
            'duration_ms': (payload['duration_ms'] as num?)?.toInt() ?? 0,
            'updated_at': item.updatedAt,
            'is_hidden': 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
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
      final stateKey = 'remote_${item.entity}:${item.key}';
      final cached = await _state(db, stateKey);
      if (cached != null) {
        try {
          final json = jsonDecode(cached);
          if (json is Map) {
            final previous =
                SyncEnvelope.fromJson(json.cast<String, Object?>());
            if (item.updatedAt < previous.updatedAt ||
                (item.updatedAt == previous.updatedAt &&
                    previous.deleted &&
                    !item.deleted)) return;
            if (item.deleted && !previous.deleted) {
              await _removeDerivedProgress(db, previous);
            }
          }
        } on FormatException {
          return;
        } on TypeError {
          return;
        }
      }
      await _writeState(db, stateKey, jsonEncode(item.toJson()));
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

  void _scheduleRetry(
      {int? retryAfterSeconds, Future<void> Function()? operation}) {
    _retryTimer?.cancel();
    final delay = retryDelay(
        attempt: _retryAttempt++, retryAfterSeconds: retryAfterSeconds);
    _retryTimer = Timer(delay, () {
      unawaited((operation?.call() ?? pushOutbox(trigger: 'retry'))
          .catchError((Object _) {}));
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
    // A media history is one latest record; episode progress remains per line.
    // Legacy history markers are retained and never turned into tombstones.
    final progress = await db.rawQuery(
        'SELECT p.*,m.title,m.category,m.kind,m.poster_url,m.remote_id,m.source_id,m.source_name,m.year,m.description,m.rating,s.base_url FROM progress p LEFT JOIN media_snapshots m ON m.media_id=p.media_id LEFT JOIN sources s ON s.id=m.source_id ORDER BY p.updated_at DESC');
    final identities = <String, int>{};
    for (final row in progress) {
      final base = row['base_url'] as String?;
      final vod = row['remote_id'] as String?;
      final line = row['line_name'] as String?;
      final number = row['episode_number'] as int?;
      if (base == null ||
          vod == null ||
          vod.isEmpty ||
          !_unambiguousHistory(row['kind'] as int?, line, number)) continue;
      try {
        final key = hubMediaKey(
            sourceKey: hubSourceKey(base),
            vodId: vod,
            lineName: line,
            episodeIndex: number == null ? null : number - 1);
        identities[key] = (identities[key] ?? 0) + 1;
      } on FormatException {
        continue;
      }
    }
    final latestMedia = <String>{};
    final latestTimestamp = <String, int>{};
    final latestCount = <String, int>{};
    for (final row in progress) {
      final base = row['base_url'] as String?;
      final vod = row['remote_id'] as String?;
      if (base == null || vod == null || vod.isEmpty) continue;
      try {
        final key = hubMediaKey(sourceKey: hubSourceKey(base), vodId: vod);
        final timestamp = row['updated_at'] as int;
        if (!latestTimestamp.containsKey(key)) {
          latestTimestamp[key] = timestamp;
          latestCount[key] = 1;
        } else if (latestTimestamp[key] == timestamp) {
          latestCount[key] = latestCount[key]! + 1;
        }
      } on FormatException {
        continue;
      }
    }
    for (final row in progress) {
      final base = row['base_url'] as String?;
      final vod = row['remote_id'] as String?;
      final line = row['line_name'] as String?;
      final number = row['episode_number'] as int?;
      if (base == null ||
          vod == null ||
          vod.isEmpty ||
          !_unambiguousHistory(row['kind'] as int?, line, number)) continue;
      try {
        final sourceKey = hubSourceKey(base);
        final historyKey = hubMediaKey(sourceKey: sourceKey, vodId: vod);
        if (await _hasUnsafeHistoryForMedia(db, base, vod, historyKey)) {
          continue;
        }
        final progressKey = hubMediaKey(
            sourceKey: sourceKey,
            vodId: vod,
            lineName: line,
            episodeIndex: number == null ? null : number - 1);
        if (identities[progressKey] != 1) continue;
        final payload = <String, Object?>{
          'title': row['title'] ?? '',
          'cineo_media_kind': row['kind'],
          'source_api': base,
          'source_key': sourceKey,
          'video': _syncVideo(row),
          'line_name': line ?? '',
          'episode_title': row['episode_label'] ?? '',
          'episode_index': (number ?? 1) - 1,
          'cineo_index_base': 0,
          'position_ms': row['position_ms'],
          'duration_ms': row['duration_ms'],
        };
        final updatedAt = row['updated_at'] as int;
        final progressMarker = 'local_v2_progress:$progressKey';
        if (int.tryParse(await _state(db, progressMarker) ?? '') != updatedAt) {
          await enqueue(
              db,
              SyncEnvelope(
                  entity: 'progress',
                  key: progressKey,
                  updatedAt: updatedAt,
                  deleted: false,
                  payload: payload));
          await _writeState(db, progressMarker, '$updatedAt');
        }
        if (latestTimestamp[historyKey] == updatedAt &&
            latestCount[historyKey] == 1 &&
            latestMedia.add(historyKey)) {
          final historyMarker = 'local_v2_history:$historyKey';
          if (int.tryParse(await _state(db, historyMarker) ?? '') !=
              updatedAt) {
            await enqueue(
                db,
                SyncEnvelope(
                    entity: 'history',
                    key: historyKey,
                    updatedAt: updatedAt,
                    deleted: false,
                    payload: payload));
            await _writeState(db, historyMarker, '$updatedAt');
          }
        }
      } on FormatException {
        continue;
      }
    }
    final activeFavoriteKeys = <String>{};
    final favorites = await db.rawQuery(
        'SELECT f.*,m.title,m.category,m.poster_url,m.remote_id,s.base_url FROM favorites f LEFT JOIN media_snapshots m ON m.media_id=f.media_id LEFT JOIN sources s ON s.id=m.source_id');
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
                    'video': {'posterUrl': row['poster_url'] ?? ''},
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

  Future<void> enqueue(DatabaseExecutor db, SyncEnvelope item) async {
    // Do not replace a newer queued write, or an equal-time tombstone. The
    // conditional upsert is atomic even when writers race on the same key.
    await db.rawInsert('''
      INSERT INTO hub_outbox(entity,record_key,updated_at,deleted,payload_json,attempts,next_attempt_at)
      VALUES(?,?,?,?,?,0,0)
      ON CONFLICT(entity,record_key) DO UPDATE SET
        updated_at=excluded.updated_at, deleted=excluded.deleted,
        payload_json=excluded.payload_json, attempts=0, next_attempt_at=0
      WHERE excluded.updated_at > hub_outbox.updated_at OR
        (excluded.updated_at = hub_outbox.updated_at AND excluded.deleted=1 AND hub_outbox.deleted=0)
    ''', [
      item.entity,
      item.key,
      item.updatedAt,
      item.deleted ? 1 : 0,
      item.payload == null ? null : jsonEncode(item.payload)
    ]);
  }

  Future<void> _writeState(DatabaseExecutor db, String key, String value) =>
      db.insert('hub_sync_state', {'state_key': key, 'value': value},
          conflictAlgorithm: ConflictAlgorithm.replace);
  Future<String?> _state(DatabaseExecutor db, String key) async {
    final rows = await db.query('hub_sync_state',
        columns: ['value'], where: 'state_key=?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.single['value'] as String;
  }
}
