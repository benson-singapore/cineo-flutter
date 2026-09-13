import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import '../../core/models/download_models.dart';
import 'download_directory.dart';
import 'download_local_server.dart';
import 'download_settings_store.dart';
import 'download_storage.dart';
import 'hls_playlist.dart';

typedef HlsSegmentFetcher = Future<List<int>> Function(Uri uri);

class _FetchedSegment {
  const _FetchedSegment({required this.bytes, required this.contentLength});

  final List<int> bytes;
  final int? contentLength;
}

class DownloadException implements Exception {
  const DownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DownloadService {
  DownloadService({
    DownloadDirectoryProvider? directoryProvider,
    DownloadTaskPersistence? taskStore,
    DownloadSettingsStore? settingsStore,
    HlsPlaylistParser? playlistParser,
    HlsSegmentFetcher? segmentFetcher,
    void Function(String message)? logger,
    this.maxSegmentRetries = 2,
  })  : _taskStore = taskStore ??
            DownloadTaskStore(
              directoryProvider:
                  directoryProvider ?? DownloadDirectoryProvider(),
            ),
        _settingsStore = settingsStore ?? DownloadSettingsStore(),
        _playlistParser = playlistParser ?? HlsPlaylistParser(),
        _segmentFetcher = segmentFetcher ?? _fetchSegment,
        _usesDefaultSegmentFetcher = segmentFetcher == null,
        _logger = logger ?? debugPrint;

  final DownloadTaskPersistence _taskStore;
  final DownloadSettingsStore _settingsStore;
  final HlsPlaylistParser _playlistParser;
  final HlsSegmentFetcher _segmentFetcher;
  final bool _usesDefaultSegmentFetcher;
  final void Function(String message) _logger;
  final int maxSegmentRetries;
  final _changes = StreamController<List<DownloadTask>>.broadcast();
  final _tasks = <String, DownloadTask>{};
  final _running = <String>{};
  final _operations = <Future<void>>{};
  final _pauseRequested = <String>{};
  final _cancelRequested = <String>{};
  DownloadSettings _settings = const DownloadSettings();
  bool _initialized = false;
  bool _backgroundSuspended = false;
  final _backgroundPaused = <String>{};
  DownloadLocalServer? _localServer;

  DownloadSettings get settings => _settings;
  List<DownloadTask> get tasks => List.unmodifiable(_tasks.values.toList());
  Stream<List<DownloadTask>> get changes => _changes.stream;
  Stream<List<DownloadTask>> get taskChanges => changes;

  /// Stops starting new work while the app is backgrounded. Running segment
  /// requests are interrupted at their next checkpoint when background work
  /// is disabled, so they can resume without losing completed segments.
  Future<void> setBackgrounded(bool backgrounded) async {
    await initialize();
    if (_settings.allowBackground) return;
    _backgroundSuspended = backgrounded;
    if (backgrounded) {
      _backgroundPaused.addAll(_running);
      _pauseRequested.addAll(_backgroundPaused);
    } else {
      _pauseRequested.removeAll(_backgroundPaused);
      final backgroundPaused = Set<String>.of(_backgroundPaused);
      _backgroundPaused.clear();
      for (final task in _tasks.values) {
        if (task.status == DownloadTaskStatus.paused &&
            backgroundPaused.contains(task.id) &&
            !_cancelRequested.contains(task.id)) {
          _setTask(task.copyWith(status: DownloadTaskStatus.queued));
        }
      }
      _pump();
    }
  }

  Future<String?> completedPathFor({
    required String mediaId,
    required String sourceUrl,
  }) async {
    await initialize();
    final task = _tasks.values
        .where((candidate) =>
            candidate.mediaId == mediaId &&
            candidate.sourceUrl == sourceUrl &&
            candidate.status == DownloadTaskStatus.completed)
        .firstOrNull;
    final outputPath = task?.outputPath;
    if (outputPath == null || outputPath.isEmpty) return null;
    return await File(outputPath).exists() ? outputPath : null;
  }

  /// Returns a loopback HLS URL for a completed cache playlist.
  ///
  /// Only the current local HLS representation is playable. Legacy
  /// concatenated `final.ts` files are deliberately ignored because their
  /// segment timestamp resets make them unreliable on AVPlayer.
  Future<String?> completedPlaybackUrlFor({
    required String mediaId,
    required String sourceUrl,
  }) async {
    await initialize();
    final task = _tasks.values
        .where((candidate) =>
            candidate.mediaId == mediaId &&
            candidate.sourceUrl == sourceUrl &&
            candidate.status == DownloadTaskStatus.completed)
        .firstOrNull;
    final outputPath = task?.outputPath;
    if (outputPath == null || !outputPath.toLowerCase().endsWith('.m3u8')) {
      return null;
    }
    return completedPlaybackSourceForTask(task!.id);
  }

  /// Resolves the source for an explicitly selected completed task.
  ///
  /// A completed task is playable only when it contains the current local
  /// HLS playlist. Legacy `final.ts` output is intentionally not returned.
  Future<String?> completedPlaybackSourceForTask(String taskId) async {
    await initialize();
    final task = _tasks[taskId];
    if (task == null || task.status != DownloadTaskStatus.completed) {
      return null;
    }
    final outputPath = task.outputPath;
    if (outputPath == null || outputPath.isEmpty) return null;
    if (!await File(outputPath).exists()) return null;
    if (outputPath.toLowerCase().endsWith('.m3u8')) {
      final root = await _taskStore.rootDirectory();
      _localServer ??= DownloadLocalServer(root);
      return _localServer!.urlFor(outputPath);
    }
    return null;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _settings = await _settingsStore.load();
    for (final task in await _taskStore.load()) {
      _tasks[task.id] = task.status == DownloadTaskStatus.downloading
          ? task.copyWith(status: DownloadTaskStatus.queued)
          : task;
    }
    _initialized = true;
    _emit();
    _pump();
  }

  Future<DownloadTask> enqueue(DownloadRequest request) async {
    await initialize();
    final duplicate =
        _tasks.values.where((task) => task.taskKey == request.stableKey);
    if (duplicate.isNotEmpty) return duplicate.first;
    final id = request.taskId?.trim().isNotEmpty == true
        ? request.taskId!.trim()
        : md5.convert(utf8.encode(request.stableKey)).toString();
    final now = DateTime.now().toUtc();
    final task = DownloadTask(
      taskId: id,
      taskKey: request.stableKey,
      mediaId: request.mediaId,
      sourceUrl: request.sourceUrl,
      title: request.title,
      episodeId: request.episodeId,
      seasonNumber: request.seasonNumber,
      episodeNumber: request.episodeNumber,
      episodeLabel: request.episodeLabel,
      posterUrl: request.posterUrl,
      backdropUrl: request.backdropUrl,
      status: DownloadTaskStatus.queued,
      createdAt: now,
      updatedAt: now,
    );
    _tasks[id] = task;
    await _persist();
    _emit();
    _pump();
    return task;
  }

  Future<List<DownloadTask>> enqueueAll(
    Iterable<DownloadRequest> requests,
  ) async {
    final result = <DownloadTask>[];
    for (final request in requests) {
      result.add(await enqueue(request));
    }
    return result;
  }

  Future<DownloadTask> add(DownloadRequest request) => enqueue(request);
  Future<List<DownloadTask>> addAll(Iterable<DownloadRequest> requests) =>
      enqueueAll(requests);

  Future<DownloadTask?> task(String id) async {
    await initialize();
    return _tasks[id];
  }

  Future<void> pause(String id) async {
    await initialize();
    final task = _tasks[id];
    if (task == null || task.isFinished) return;
    _pauseRequested.add(id);
    if (!_running.contains(id)) {
      _setTask(task.copyWith(status: DownloadTaskStatus.paused));
      await _persist();
    }
  }

  Future<void> resume(String id) async {
    await initialize();
    final task = _tasks[id];
    if (task == null || task.status == DownloadTaskStatus.completed) return;
    _pauseRequested.remove(id);
    _cancelRequested.remove(id);
    _setTask(
        task.copyWith(status: DownloadTaskStatus.queued, clearError: true));
    await _persist();
    _pump();
  }

  Future<void> cancel(String id) async {
    await initialize();
    final task = _tasks[id];
    if (task == null || task.status == DownloadTaskStatus.completed) return;
    _cancelRequested.add(id);
    _pauseRequested.remove(id);
    _setTask(task.copyWith(status: DownloadTaskStatus.cancelled));
    if (!_running.contains(id)) {
      await _taskStore.deleteTaskDirectory(id);
      await _persist();
    }
  }

  Future<void> retry(String id) async {
    await initialize();
    final task = _tasks[id];
    if (task == null) return;
    // The failed state is emitted just before _run releases its slot. Allow
    // an immediate retry from the UI; the completion callback will pump it
    // after the previous operation has fully left _running.
    if (_running.contains(id) &&
        task.status != DownloadTaskStatus.failed &&
        task.status != DownloadTaskStatus.cancelled) {
      return;
    }
    _cancelRequested.remove(id);
    _pauseRequested.remove(id);
    _setTask(
        task.copyWith(status: DownloadTaskStatus.queued, clearError: true));
    await _persist();
    _pump();
  }

  /// Replaces a completed legacy cache with the current local HLS format.
  ///
  /// Older releases wrote a concatenated `final.ts`. That file can be a valid
  /// MPEG-TS container while still being unplayable by AVPlayer because each
  /// source segment may reset its timestamps. Keep the task metadata, remove
  /// the old files, and let the normal scheduler download an HLS playlist plus
  /// independent segment files instead.
  Future<void> redownload(String id) async {
    await initialize();
    final task = _tasks[id];
    if (task == null) return;
    if (_running.contains(id)) return;

    _cancelRequested.remove(id);
    _pauseRequested.remove(id);
    await _taskStore.deleteTaskDirectory(id);
    _setTask(task.copyWith(
      status: DownloadTaskStatus.queued,
      totalSegments: 0,
      completedSegments: 0,
      totalBytes: 0,
      downloadedBytes: 0,
      clearOutputPath: true,
      clearError: true,
    ));
    await _persist();
    _pump();
  }

  Future<void> delete(String id) async {
    await initialize();
    _cancelRequested.add(id);
    _tasks.remove(id);
    await _taskStore.deleteTaskDirectory(id);
    await _persist();
    _emit();
  }

  Future<void> updateSettings(DownloadSettings settings) async {
    await initialize();
    _settings = settings.normalized();
    await _settingsStore.save(_settings);
    _emit();
    _pump();
  }

  Future<DownloadCacheStats> cacheStats() async {
    await initialize();
    final root = await _taskStore.rootDirectory();
    var bytes = 0;
    var files = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      final name = path.basename(entity.path);
      if (entity is File &&
          !name.endsWith('.json') &&
          !name.endsWith('.json.tmp') &&
          !name.endsWith('.tmp')) {
        bytes += await entity.length();
        files++;
      }
    }
    return DownloadCacheStats(
      totalBytes: bytes,
      fileCount: files,
      taskCount: _tasks.length,
    );
  }

  Future<void> dispose() async {
    await Future.wait(List<Future<void>>.of(_operations));
    await _persist();
    await _localServer?.close();
    await _changes.close();
  }

  void _pump() {
    if (_backgroundSuspended && !_settings.allowBackground) return;
    while (_initialized && _running.length < _settings.concurrency) {
      final queued = _tasks.values.where((task) =>
          task.status == DownloadTaskStatus.queued &&
          !_running.contains(task.id) &&
          !_cancelRequested.contains(task.id));
      if (queued.isEmpty) return;
      final task = queued.first;
      _running.add(task.id);
      final operation = _run(task.id).whenComplete(() {
        _running.remove(task.id);
        _pump();
      });
      _operations.add(operation);
      unawaited(operation.whenComplete(() => _operations.remove(operation)));
    }
  }

  Future<void> _run(String id) async {
    try {
      final initialTask = _tasks[id];
      if (initialTask == null) return;
      var task = initialTask;
      _log(
        'task_start id=$id media=${task.mediaId} '
        'episode=${task.episodeNumber ?? 'movie'} playlist=${task.sourceUrl}',
      );
      _setTask(task = task.copyWith(status: DownloadTaskStatus.downloading));
      final playlist =
          await _playlistParser.parseUri(Uri.parse(task.sourceUrl));
      _log(
        'task_playlist_ready id=$id uri=${playlist.uri} '
        'segments=${playlist.segmentCount}',
      );
      final directory = await _taskStore.taskDirectory(id);
      final completed = (await _taskStore.loadCheckpoint(id))
          .where((index) => index >= 0 && index < playlist.segments.length)
          .toSet();
      var downloadedBytes = 0;
      var totalBytes = task.totalBytes;
      final segmentBytes = <int, int>{};
      for (final index in completed) {
        final part = await _partFileForResume(directory, index);
        if (await part.exists()) {
          final length = await part.length();
          downloadedBytes += length;
          segmentBytes[index] = length;
        }
      }
      totalBytes = _estimatedTotalBytes(
        segmentBytes,
        playlist.segments.length,
        fallback: totalBytes,
      );
      _setTask(task = task.copyWith(
        totalSegments: playlist.segments.length,
        completedSegments: completed.length,
        totalBytes: totalBytes,
        downloadedBytes: downloadedBytes,
      ));
      _log(
        'task_checkpoint_loaded id=$id completed=${completed.length}/'
        '${playlist.segments.length} bytes=$downloadedBytes',
      );
      for (var index = 0; index < playlist.segments.length; index++) {
        _checkInterrupted(id);
        if (completed.contains(index)) continue;
        _log(
          'segment_start task=$id index=${index + 1}/${playlist.segments.length} '
          'uri=${playlist.segments[index].uri}',
        );
        final fetched = await _fetch(
          playlist.segments[index].uri,
          referer: playlist.uri,
          taskId: id,
          segmentIndex: index,
          segmentCount: playlist.segments.length,
        );
        final bytes = fetched.bytes;
        _checkInterrupted(id);
        await File(pathForPart(directory, index))
            .writeAsBytes(bytes, flush: true);
        completed.add(index);
        downloadedBytes += bytes.length;
        segmentBytes[index] =
            fetched.contentLength != null && fetched.contentLength! > 0
                ? fetched.contentLength!
                : bytes.length;
        totalBytes = _estimatedTotalBytes(
          segmentBytes,
          playlist.segments.length,
          fallback: totalBytes,
        );
        await _taskStore.saveCheckpoint(
            taskId: id, completedSegments: completed);
        _setTask(task = task.copyWith(
          completedSegments: completed.length,
          totalBytes: totalBytes,
          downloadedBytes: downloadedBytes,
        ));
        _log(
          'segment_complete task=$id index=${index + 1}/'
          '${playlist.segments.length} bytes=${bytes.length} '
          'downloaded=$downloadedBytes',
        );
      }
      _checkInterrupted(id);
      final output = File(pathForOutput(directory));
      await _writeLocalPlaylist(output, playlist);
      await _taskStore.deleteCheckpoint(id);
      final outputBytes = downloadedBytes;
      _setTask(task.copyWith(
        status: DownloadTaskStatus.completed,
        completedSegments: playlist.segments.length,
        totalBytes: outputBytes,
        downloadedBytes: outputBytes,
        outputPath: output.path,
      ));
      _log('task_complete id=$id output=${output.path} bytes=$outputBytes');
    } on _DownloadInterrupted {
      _log('task_interrupted id=$id');
      final task = _tasks[id];
      if (task != null && task.status != DownloadTaskStatus.cancelled) {
        _setTask(task.copyWith(status: DownloadTaskStatus.paused));
      }
    } on Object catch (error) {
      _log('task_failed id=$id error=$error');
      final task = _tasks[id];
      if (task != null && !_cancelRequested.contains(id)) {
        _setTask(task.copyWith(
          status: DownloadTaskStatus.failed,
          errorMessage: '$error',
        ));
      }
    } finally {
      if (_cancelRequested.contains(id) ||
          _tasks[id]?.status == DownloadTaskStatus.cancelled) {
        await _taskStore.deleteTaskDirectory(id);
      }
      await _persist();
      _emit();
    }
  }

  void _checkInterrupted(String id) {
    if (_pauseRequested.contains(id) || _cancelRequested.contains(id)) {
      throw const _DownloadInterrupted();
    }
  }

  Future<_FetchedSegment> _fetch(
    Uri uri, {
    Uri? referer,
    required String taskId,
    required int segmentIndex,
    required int segmentCount,
  }) async {
    Object? error;
    for (var attempt = 0; attempt <= maxSegmentRetries; attempt++) {
      try {
        _log(
          'segment_request task=$taskId index=${segmentIndex + 1}/$segmentCount '
          'attempt=${attempt + 1}/${maxSegmentRetries + 1} uri=$uri',
        );
        final fetched = _usesDefaultSegmentFetcher
            ? await _fetchSegmentWithMetadata(uri, referer: referer)
            : _FetchedSegment(
                bytes: await _segmentFetcher(uri),
                contentLength: null,
              );
        if (fetched.bytes.isEmpty) {
          throw const FormatException('Empty HLS segment');
        }
        return fetched;
      } on Object catch (caught) {
        error = caught;
        _log(
          'segment_request_failed task=$taskId index=${segmentIndex + 1}/'
          '$segmentCount attempt=${attempt + 1}/${maxSegmentRetries + 1} '
          'error=$caught',
        );
      }
    }
    throw DownloadException(
      '片段下载失败: ${_withoutRuntimeWrapper(error)}',
    );
  }

  static String _withoutRuntimeWrapper(Object? error) {
    final text = '$error';
    return text
        .replaceFirst(RegExp(r'^Bad state:\s*'), '')
        .replaceFirst(RegExp(r'^DownloadException:\s*'), '');
  }

  static int _estimatedTotalBytes(
    Map<int, int> segmentBytes,
    int segmentCount, {
    required int fallback,
  }) {
    if (segmentBytes.isEmpty || segmentCount <= 0) return fallback;
    final knownBytes =
        segmentBytes.values.fold<int>(0, (sum, size) => sum + size);
    final estimate = (knownBytes / segmentBytes.length * segmentCount).round();
    return estimate > fallback ? estimate : fallback;
  }

  void _setTask(DownloadTask task) {
    _tasks[task.id] = task;
    _emit();
    unawaited(_persist());
  }

  Future<void> _persist() => _taskStore.save(_tasks.values);

  void _log(String message) {
    _logger('[Cineo][Download] $message');
  }

  void _emit() {
    if (!_changes.isClosed) _changes.add(tasks);
  }

  static String pathForPart(Directory directory, int index) => path.join(
      directory.path, 'segment_${index.toString().padLeft(6, '0')}.ts');

  static String pathForLegacyPart(Directory directory, int index) => path.join(
      directory.path, 'segment_${index.toString().padLeft(6, '0')}.part');

  Future<File> _partFileForResume(Directory directory, int index) async {
    final current = File(pathForPart(directory, index));
    if (await current.exists()) return current;
    final legacy = File(pathForLegacyPart(directory, index));
    if (await legacy.exists()) {
      await legacy.rename(current.path);
    }
    return current;
  }

  static String pathForOutput(Directory directory) =>
      path.join(directory.path, 'index.m3u8');

  static Future<void> _writeLocalPlaylist(
    File output,
    HlsPlaylist playlist,
  ) async {
    final targetDuration = playlist.targetDuration.inSeconds;
    final lines = <String>[
      '#EXTM3U',
      '#EXT-X-VERSION:3',
      '#EXT-X-TARGETDURATION:${targetDuration < 1 ? 1 : targetDuration}',
      '#EXT-X-MEDIA-SEQUENCE:0',
    ];
    for (var index = 0; index < playlist.segments.length; index++) {
      if (index > 0) lines.add('#EXT-X-DISCONTINUITY');
      final segment = playlist.segments[index];
      lines
        ..add('#EXTINF:${segment.duration.inMicroseconds / 1000000},')
        ..add(path.basename(pathForPart(output.parent, index)));
    }
    lines.add('#EXT-X-ENDLIST');
    final temporary = File('${output.path}.tmp');
    await temporary.writeAsString('${lines.join('\n')}\n', flush: true);
    if (await output.exists()) await output.delete();
    await temporary.rename(output.path);
  }

  static Future<_FetchedSegment> _fetchSegmentWithMetadata(Uri uri,
      {Uri? referer}) async {
    final client = HttpClient()..autoUncompress = false;
    try {
      final request = await client.getUrl(uri);
      request.followRedirects = true;
      request.maxRedirects = 5;
      request.persistentConnection = false;
      request.headers.set(HttpHeaders.userAgentHeader, hlsDownloadUserAgent);
      request.headers.set(HttpHeaders.acceptHeader, '*/*');
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      request.headers.set(HttpHeaders.pragmaHeader, 'no-cache');
      if (referer != null) {
        request.headers.set(HttpHeaders.refererHeader, referer.toString());
        request.headers.set('Origin', _originFor(referer));
      }
      final response = await request.close();
      debugPrint(
        '[Cineo][Download] segment_response status=${response.statusCode} '
        'finalUri=${response.redirects.isEmpty ? uri : response.redirects.last.location} '
        'contentLength=${response.contentLength} '
        'contentType=${response.headers.contentType} '
        'contentEncoding=${response.headers.value(HttpHeaders.contentEncodingHeader) ?? 'identity'} '
        'uri=$uri',
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final preview = await _responsePreview(response);
        debugPrint(
          '[Cineo][Download] segment_http_body_preview '
          'status=${response.statusCode} preview=$preview uri=$uri',
        );
        throw HttpException(
          'Segment request failed (HTTP ${response.statusCode})'
          '${preview.isEmpty ? '' : ': $preview'}: $uri',
        );
      }
      final expectedLength = response.contentLength;
      final bytes = BytesBuilder(copy: false);
      try {
        await for (final chunk in response) {
          bytes.add(chunk);
        }
        final result = bytes.takeBytes();
        if (expectedLength >= 0 && result.length != expectedLength) {
          throw HttpException(
            'Segment response truncated (received ${result.length}/'
            '$expectedLength bytes): $uri',
          );
        }
        debugPrint(
          '[Cineo][Download] segment_body_complete bytes=${result.length} '
          'uri=$uri',
        );
        return _FetchedSegment(
          bytes: result,
          contentLength: expectedLength >= 0 ? expectedLength : null,
        );
      } catch (error) {
        debugPrint(
          '[Cineo][Download] segment_body_failed received=${bytes.length} '
          'expected=$expectedLength uri=$uri error=$error',
        );
        // A few HLS CDNs use a chunked response and close the stream after
        // the final chunk without sending a clean HTTP stream terminator.
        // There is no declared length to contradict the bytes already read,
        // so those bytes are usable. Never recover a response that declares
        // a larger Content-Length than the data received.
        if (_isPrematureClose(error) &&
            bytes.length > 0 &&
            (expectedLength < 0 || bytes.length >= expectedLength)) {
          final recovered = bytes.takeBytes();
          debugPrint(
            '[Cineo][Download] segment_body_recovered '
            'bytes=${recovered.length} uri=$uri',
          );
          return _FetchedSegment(
            bytes: recovered,
            contentLength: expectedLength >= 0 ? expectedLength : null,
          );
        }
        rethrow;
      }
    } catch (error) {
      debugPrint('[Cineo][Download] segment_http_failed uri=$uri error=$error');
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  static Future<List<int>> _fetchSegment(Uri uri) async {
    return (await _fetchSegmentWithMetadata(uri)).bytes;
  }

  static Future<String> _responsePreview(HttpClientResponse response) async {
    try {
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
        if (bytes.length >= 512) break;
      }
      final preview = utf8
          .decode(bytes, allowMalformed: true)
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      return preview.length > 240 ? '${preview.substring(0, 240)}...' : preview;
    } catch (error) {
      debugPrint(
          '[Cineo][Download] segment_http_body_preview_failed error=$error');
      return '';
    }
  }

  static String _originFor(Uri uri) {
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port';
  }

  static bool _isPrematureClose(Object error) =>
      error is HttpException &&
      error.message.contains('Connection closed while receiving data');
}

String pathForPart(Directory directory, int index) =>
    DownloadService.pathForPart(directory, index);
String pathForOutput(Directory directory) =>
    DownloadService.pathForOutput(directory);

class _DownloadInterrupted implements Exception {
  const _DownloadInterrupted();
}
