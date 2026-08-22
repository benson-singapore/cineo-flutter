import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../core/models/media.dart';
import '../../core/models/media_source.dart';
import 'media_category_adapter.dart';

typedef MacCmsFetcher = Future<String> Function(Uri uri);

class SourceProbeResult {
  const SourceProbeResult({
    required this.isReachable,
    this.latencyMs,
    this.error,
  });

  final bool isReachable;
  final int? latencyMs;
  final String? error;
}

/// Minimal MacCMS-compatible JSON client for sources explicitly configured by
/// the user. It does not discover endpoints or make background requests.
class MacCmsClient {
  MacCmsClient({
    MacCmsFetcher? fetcher,
    this.timeout = const Duration(seconds: 10),
    this.maxAttempts = 2,
    this.retryDelay = const Duration(milliseconds: 250),
  })  : assert(maxAttempts > 0),
        _fetcher = fetcher ?? _defaultFetch;

  final MacCmsFetcher _fetcher;
  final Duration timeout;
  final int maxAttempts;
  final Duration retryDelay;
  int _requestSequence = 0;

  Future<List<MediaItem>> list(
    MediaSource source, {
    String? query,
    String? category,
    int page = 1,
  }) async {
    // MacCMS `list` responses often omit poster fields. `videolist` returns
    // the full records needed for browse cards, including `vod_pic`. Some
    // source CDNs incorrectly reuse a cached `list` response for this route,
    // so each content request carries a cache-busting marker.
    final parameters = <String, String>{
      'ac': 'videolist',
      'pg': '$page',
      '_': '${DateTime.now().microsecondsSinceEpoch}',
    };
    if (query != null && query.trim().isNotEmpty) {
      parameters['wd'] = query.trim();
    }
    if (category != null && category.trim().isNotEmpty) {
      parameters['t'] = category.trim();
    }
    final payload = await _get(source, parameters);
    return _itemsFromPayload(payload, source);
  }

  Future<MediaItem?> detail(MediaSource source, String remoteId) async {
    final payload = await _get(source, {'ac': 'detail', 'ids': remoteId});
    final items = _itemsFromPayload(payload, source, includePlayback: true);
    return items.isEmpty ? null : items.first;
  }

  Future<List<RemoteCategory>> categories(MediaSource source) async {
    final payload = await _get(source, const {'ac': 'list'});
    if (payload is! Map) {
      throw const FormatException('站点分类响应格式不正确');
    }
    final rawCategories = payload['class'] ??
        payload['types'] ??
        (payload['data'] is Map ? (payload['data'] as Map)['class'] : null);
    if (rawCategories is! List) return const [];
    return rawCategories
        .whereType<Map>()
        .map((raw) {
          final item = Map<String, Object?>.from(raw);
          final id = _string(item['type_id'] ?? item['id']);
          final name = _string(item['type_name'] ?? item['name']);
          final parentId = _string(item['type_pid'] ?? item['parent_id']);
          if (id.isEmpty || name.isEmpty) return null;
          return RemoteCategory(
            id: id,
            name: name,
            parentId: parentId.isEmpty || parentId == '0' ? null : parentId,
          );
        })
        .whereType<RemoteCategory>()
        .toList(growable: false);
  }

  Future<SourceProbeResult> probe(MediaSource source) async {
    final stopwatch = Stopwatch()..start();
    try {
      await _get(source, const {'ac': 'list', 'pg': '1'});
      stopwatch.stop();
      return SourceProbeResult(
          isReachable: true, latencyMs: stopwatch.elapsedMilliseconds);
    } catch (error) {
      stopwatch.stop();
      return SourceProbeResult(
        isReachable: false,
        latencyMs: stopwatch.elapsedMilliseconds,
        error: _messageFor(error),
      );
    }
  }

  Future<Object?> _get(
      MediaSource source, Map<String, String> parameters) async {
    final endpoint = Uri.tryParse(source.baseUrl.trim());
    if (endpoint == null || !{'http', 'https'}.contains(endpoint.scheme)) {
      throw const FormatException('视频源地址不是有效的 HTTP(S) API');
    }
    final uri = endpoint.replace(
      queryParameters: <String, String>{
        ...endpoint.queryParameters,
        ...parameters
      },
    );
    final requestId = ++_requestSequence;
    final operation = parameters['ac'] ?? 'unknown';
    final stopwatch = Stopwatch()..start();
    _debugLog(
      'request=$requestId phase=start source=${source.id} '
      'operation=$operation uri=${_safeUri(uri)}',
    );
    final raw = await _fetchWithRetry(uri, requestId: requestId);
    try {
      final payload = jsonDecode(raw);
      stopwatch.stop();
      _debugLog(
        'request=$requestId phase=decoded source=${source.id} '
        'operation=$operation elapsedMs=${stopwatch.elapsedMilliseconds} '
        'payload=${_payloadSummary(payload)}',
      );
      return payload;
    } on FormatException catch (error, stackTrace) {
      stopwatch.stop();
      _debugError(
        'request=$requestId phase=decode_failed source=${source.id} '
        'operation=$operation elapsedMs=${stopwatch.elapsedMilliseconds} '
        'characters=${raw.length}',
        error,
        stackTrace,
      );
      throw const FormatException('站点返回的不是有效 JSON');
    }
  }

  Future<String> _fetchWithRetry(Uri uri, {required int requestId}) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final stopwatch = Stopwatch()..start();
      try {
        _debugLog(
          'request=$requestId phase=fetch attempt=$attempt/$maxAttempts '
          'uri=${_safeUri(uri)}',
        );
        final response = await _fetcher(uri).timeout(timeout);
        stopwatch.stop();
        _debugLog(
          'request=$requestId phase=fetch_complete '
          'attempt=$attempt/$maxAttempts '
          'elapsedMs=${stopwatch.elapsedMilliseconds} '
          'characters=${response.length}',
        );
        return response;
      } catch (error, stackTrace) {
        stopwatch.stop();
        final canRetry =
            _isTransientNetworkError(error) && attempt < maxAttempts;
        _debugError(
          'request=$requestId phase=fetch_failed '
          'attempt=$attempt/$maxAttempts '
          'elapsedMs=${stopwatch.elapsedMilliseconds} retry=$canRetry '
          'uri=${_safeUri(uri)}',
          error,
          stackTrace,
          includeStack: !canRetry,
        );
        if (!canRetry) {
          Error.throwWithStackTrace(error, stackTrace);
        }
        await Future<void>.delayed(retryDelay);
      }
    }
    throw StateError('无法请求视频源');
  }

  bool _isTransientNetworkError(Object error) {
    if (error is SocketException || error is TimeoutException) {
      return true;
    }
    if (error is! HttpException) {
      return false;
    }

    // HTTP status errors are deterministic for this request. A closed stream
    // is represented as HttpException too, but is commonly resolved by one
    // fresh connection to a user-configured source.
    return !RegExp(r'\bHTTP\s+\d{3}\b', caseSensitive: false)
        .hasMatch(error.message);
  }

  List<MediaItem> _itemsFromPayload(
    Object? payload,
    MediaSource source, {
    bool includePlayback = false,
  }) {
    if (payload is! Map) throw const FormatException('站点响应格式不正确');
    final rawList = _findList(payload);
    if (rawList == null) return const [];
    return rawList
        .whereType<Map>()
        .map((raw) {
          final item = Map<String, Object?>.from(raw);
          return _itemFromMap(item, source, includePlayback: includePlayback);
        })
        .whereType<MediaItem>()
        .toList(growable: false);
  }

  List<Object?>? _findList(Map payload) {
    for (final key in const ['list', 'data']) {
      final candidate = payload[key];
      if (candidate is List) return List<Object?>.from(candidate);
      if (candidate is Map && candidate['list'] is List) {
        return List<Object?>.from(candidate['list'] as List);
      }
    }
    return null;
  }

  MediaItem? _itemFromMap(
    Map<String, Object?> item,
    MediaSource source, {
    required bool includePlayback,
  }) {
    final remoteId = _string(item['vod_id']);
    final title = _string(item['vod_name']);
    if (remoteId.isEmpty || title.isEmpty) return null;
    final typeName = _string(item['type_name']).isEmpty
        ? _string(item['vod_class'])
        : _string(item['type_name']);
    final playback =
        includePlayback ? _playback(item, source) : const _PlaybackData();
    return MediaItem(
      id: '${source.id}:$remoteId',
      sourceId: source.id,
      remoteId: remoteId,
      title: title,
      description: _stripHtml(_string(item['vod_content'])),
      year: _int(item['vod_year']),
      kind: _kindFor(typeName),
      posterUrl: _resolveUrl(source.baseUrl, _string(item['vod_pic'])),
      backdropUrl: _resolveUrl(source.baseUrl, _string(item['vod_pic'])),
      genres: typeName.isEmpty
          ? const []
          : typeName
              .split(RegExp(r'[,/， ]+'))
              .where((value) => value.isNotEmpty)
              .toList(),
      rating: _double(item['vod_score']),
      duration: const Duration(minutes: 45),
      category: typeName,
      categoryId: _string(item['type_id']),
      playbackOptions: playback.options,
      episodes: playback.episodes,
    );
  }

  _PlaybackData _playback(Map<String, Object?> item, MediaSource source) {
    final names = _string(item['vod_play_from']).split(r'$$$');
    final groups = _string(item['vod_play_url']).split(r'$$$');
    final options = <PlaybackOption>[];
    final episodes = <Episode>[];
    for (var groupIndex = 0; groupIndex < groups.length; groupIndex++) {
      final sourceName =
          groupIndex < names.length && names[groupIndex].trim().isNotEmpty
              ? names[groupIndex].trim()
              : '播放源 ${groupIndex + 1}';
      final entries = groups[groupIndex].split('#');
      for (var episodeIndex = 0;
          episodeIndex < entries.length;
          episodeIndex++) {
        final entry = entries[episodeIndex].trim();
        if (entry.isEmpty) continue;
        final separator = entry.indexOf(r'$');
        final label =
            (separator < 0 ? entry : entry.substring(0, separator)).trim();
        final address =
            (separator < 0 ? entry : entry.substring(separator + 1)).trim();
        if (address.isEmpty) continue;
        final option = PlaybackOption(
          id: '${source.id}:${_string(item['vod_id'])}:$groupIndex:$episodeIndex',
          sourceId: source.id,
          label: '$sourceName · ${label.isEmpty ? '播放' : label}',
          url: _resolveUrl(source.baseUrl, address),
          quality: sourceName,
          isHls: address.toLowerCase().contains('.m3u8'),
        );
        options.add(option);
        episodes.add(Episode(
          id: option.id,
          title: label.isEmpty ? '第${episodeIndex + 1}集' : label,
          season: 1,
          number: episodeIndex + 1,
          playbackOption: option,
        ));
      }
    }
    return _PlaybackData(options: options, episodes: episodes);
  }

  static Future<String> _defaultFetch(Uri uri) async {
    final client = HttpClient()..autoUncompress = false;
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      request.headers.set(HttpHeaders.pragmaHeader, 'no-cache');
      final response = await request.close();
      _debugLog(
        'phase=response_headers status=${response.statusCode} '
        'contentLength=${response.contentLength} '
        'encoding=${response.headers.value(HttpHeaders.contentEncodingHeader) ?? 'identity'} '
        'uri=${_safeUri(uri)}',
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('站点返回 HTTP ${response.statusCode}', uri: uri);
      }
      // Keep the client alive until the complete response stream is consumed.
      // Returning this future directly would enter `finally` immediately and
      // force-close larger responses before all chunks arrive.
      return await _readResponseBody(response, uri);
    } finally {
      client.close(force: true);
    }
  }

  static Future<String> _readResponseBody(
    HttpClientResponse response,
    Uri uri,
  ) {
    final completer = Completer<String>();
    final bytes = BytesBuilder(copy: false);
    late StreamSubscription<List<int>> subscription;
    subscription = response.listen(
      bytes.add,
      onError: (Object error, StackTrace stackTrace) {
        final receivedBytes = bytes.takeBytes();
        final body = _decodeCompleteJson(receivedBytes);
        if (_isPrematureClose(error) && body != null) {
          _debugLog(
            'phase=early_close_recovered bytes=${utf8.encode(body).length} '
            'uri=${_safeUri(uri)}',
          );
          completer.complete(body);
        } else {
          _debugError(
            'phase=response_stream_failed receivedBytes=${receivedBytes.length} '
            'completeJson=${body != null} uri=${_safeUri(uri)}',
            error,
            stackTrace,
          );
          completer.completeError(error, stackTrace);
        }
      },
      onDone: () {
        if (!completer.isCompleted) {
          try {
            completer.complete(utf8.decode(bytes.takeBytes()));
          } catch (error, stackTrace) {
            completer.completeError(error, stackTrace);
          }
        }
      },
      cancelOnError: true,
    );
    return completer.future.whenComplete(subscription.cancel);
  }

  static bool _isPrematureClose(Object error) =>
      error is HttpException &&
      error.message.contains('Connection closed while receiving data');

  static String? _decodeCompleteJson(Uint8List bytes) {
    try {
      final body = utf8.decode(bytes);
      jsonDecode(body);
      return body;
    } catch (_) {
      return null;
    }
  }

  static String _payloadSummary(Object? payload) {
    if (payload is! Map) return payload.runtimeType.toString();
    final list = payload['list'] ?? payload['data'];
    final count = list is List
        ? list.length
        : list is Map && list['list'] is List
            ? (list['list'] as List).length
            : null;
    return 'map keys=${payload.keys.take(8).join(',')} listCount=${count ?? 'unknown'}';
  }

  static Uri _safeUri(Uri uri) {
    final parameters = Map<String, String>.from(uri.queryParameters);
    if (parameters.containsKey('wd')) parameters['wd'] = '<redacted>';
    parameters.remove('_');
    return uri.replace(
      queryParameters: parameters.isEmpty ? null : parameters,
    );
  }

  static void _debugLog(String message) {
    assert(() {
      debugPrint('[Cineo][MacCMS] $message');
      return true;
    }());
  }

  static void _debugError(
    String message,
    Object error,
    StackTrace stackTrace, {
    bool includeStack = false,
  }) {
    assert(() {
      debugPrint(
        '[Cineo][MacCMS] $message error=${error.runtimeType}: $error',
      );
      if (includeStack) {
        debugPrintStack(
          label: '[Cineo][MacCMS] stack',
          stackTrace: stackTrace,
          maxFrames: 12,
        );
      }
      return true;
    }());
  }

  static String _string(Object? value) => value?.toString().trim() ?? '';
  static int _int(Object? value) => int.tryParse(_string(value)) ?? 0;
  static double _double(Object? value) => double.tryParse(_string(value)) ?? 0;
  static MediaKind _kindFor(String category) =>
      RegExp(r'剧|番|动漫|动画|综艺', caseSensitive: false).hasMatch(category)
          ? MediaKind.series
          : MediaKind.movie;
  static String _stripHtml(String value) =>
      value.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  static String _resolveUrl(String baseUrl, String value) {
    if (value.isEmpty) return '';
    final uri = Uri.tryParse(value);
    if (uri != null && uri.hasScheme) return value;
    return Uri.parse(baseUrl).resolve(value).toString();
  }

  static String _messageFor(Object error) => error is TimeoutException
      ? '请求超时'
      : error.toString().replaceFirst('Exception: ', '');
}

class _PlaybackData {
  const _PlaybackData({this.options = const [], this.episodes = const []});
  final List<PlaybackOption> options;
  final List<Episode> episodes;
}
