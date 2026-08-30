import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

const hlsDownloadUserAgent = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
    'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36';

typedef HlsPlaylistTextFetcher = Future<String> Function(Uri uri);
typedef HlsManifestFetcher = HlsPlaylistTextFetcher;
typedef HlsDownloadLogSink = void Function(String message);

class HlsPlaylistException implements Exception {
  const HlsPlaylistException(this.message);

  final String message;

  @override
  String toString() => 'HlsPlaylistException: $message';
}

class HlsSegment {
  const HlsSegment({
    required this.index,
    required this.uri,
    required this.duration,
    this.title = '',
  });

  final int index;
  final Uri uri;
  final Duration duration;
  final String title;
}

class HlsPlaylist {
  const HlsPlaylist({
    required this.uri,
    required this.segments,
    required this.targetDuration,
  });

  final Uri uri;
  final List<HlsSegment> segments;
  final Duration targetDuration;

  int get segmentCount => segments.length;
}

class HlsPlaylistParser {
  HlsPlaylistParser(
      {HlsPlaylistTextFetcher? fetcher, HlsDownloadLogSink? logger})
      : _fetcher = fetcher ?? _fetchText,
        _logger = logger ?? _debugLog;

  final HlsPlaylistTextFetcher _fetcher;
  final HlsDownloadLogSink _logger;

  Future<HlsPlaylist> parseUri(Uri playlistUri) async {
    _log('playlist_request uri=$playlistUri');
    try {
      final content = await _fetcher(playlistUri);
      _log('playlist_received uri=$playlistUri characters=${content.length}');
      final playlist = await parse(content, playlistUri);
      _log(
        'playlist_parsed uri=${playlist.uri} segments=${playlist.segmentCount} '
        'targetDurationMs=${playlist.targetDuration.inMilliseconds}',
      );
      return playlist;
    } catch (error, stackTrace) {
      _log('playlist_failed uri=$playlistUri error=$error');
      _debugStack(_logger, stackTrace);
      rethrow;
    }
  }

  Future<HlsPlaylist> parse(String content, Uri playlistUri) async {
    _validateUri(playlistUri);
    final lines = _lines(content);
    if (lines.isEmpty || lines.first.trim() != '#EXTM3U') {
      throw const HlsPlaylistException('Missing #EXTM3U header');
    }
    if (_isMaster(lines)) {
      final variants = _parseVariants(lines, playlistUri);
      if (variants.isEmpty) {
        throw const HlsPlaylistException('Master playlist has no variants');
      }
      variants.sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
      final selected = variants.first.uri;
      _log(
          'master_variant_selected uri=$selected bandwidth=${variants.first.bandwidth}');
      return parse(await _fetcher(selected), selected);
    }
    return _parseMedia(lines, playlistUri);
  }

  HlsPlaylist parseMedia(String content, Uri playlistUri) {
    _validateUri(playlistUri);
    final lines = _lines(content);
    if (lines.isEmpty || lines.first.trim() != '#EXTM3U') {
      throw const HlsPlaylistException('Missing #EXTM3U header');
    }
    return _parseMedia(lines, playlistUri);
  }

  HlsPlaylist _parseMedia(List<String> lines, Uri playlistUri) {
    if (!lines.contains('#EXT-X-ENDLIST')) {
      throw const HlsPlaylistException(
          'Live or incomplete playlists are unsupported');
    }
    var targetDuration = 0.0;
    var pendingDuration = false;
    var duration = 0.0;
    var title = '';
    final segments = <HlsSegment>[];

    for (var i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#EXT-X-TARGETDURATION:')) {
        targetDuration = double.tryParse(line.substring(22)) ?? 0;
        if (targetDuration <= 0) {
          throw const HlsPlaylistException('Invalid target duration');
        }
      } else if (line.startsWith('#EXT-X-MEDIA-SEQUENCE:')) {
        // MEDIA-SEQUENCE is optional for a valid VOD playlist.
      } else if (line.startsWith('#EXT-X-KEY:')) {
        if (line.contains('METHOD=AES-128') || !line.contains('METHOD=NONE')) {
          throw const HlsPlaylistException('Encrypted HLS is unsupported');
        }
      } else if (line.startsWith('#EXT-X-BYTERANGE:') ||
          line.startsWith('#EXT-X-MAP:')) {
        throw const HlsPlaylistException(
            'Byte ranges or initialization maps are unsupported');
      } else if (line.startsWith('#EXTINF:')) {
        final value = line.substring(8);
        final comma = value.indexOf(',');
        final number = comma < 0 ? value : value.substring(0, comma);
        duration = double.tryParse(number) ?? 0;
        if (duration <= 0) {
          throw const HlsPlaylistException('Invalid segment duration');
        }
        title = comma < 0 ? '' : value.substring(comma + 1);
        pendingDuration = true;
      } else if (line.startsWith('#EXT-X-')) {
        continue;
      } else if (line.startsWith('#')) {
        continue;
      } else {
        if (!pendingDuration) {
          throw const HlsPlaylistException('Segment missing EXTINF');
        }

        final uri = _resolveReferenceUri(playlistUri, line);
        segments.add(HlsSegment(
          index: segments.length,
          uri: uri,
          duration: Duration(
              microseconds:
                  (duration * Duration.microsecondsPerSecond).round()),
          title: title,
        ));
        pendingDuration = false;
      }
    }
    if (pendingDuration || segments.isEmpty || targetDuration <= 0) {
      throw const HlsPlaylistException(
          'Malformed or incomplete media playlist');
    }
    return HlsPlaylist(
      uri: playlistUri,
      segments: List.unmodifiable(segments),
      targetDuration: Duration(milliseconds: (targetDuration * 1000).round()),
    );
  }

  bool _isMaster(List<String> lines) =>
      lines.any((line) => line.startsWith('#EXT-X-STREAM-INF:'));

  List<_Variant> _parseVariants(List<String> lines, Uri base) {
    final result = <_Variant>[];
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!line.startsWith('#EXT-X-STREAM-INF:')) continue;
      final bandwidth = _attribute(line.substring(18), 'BANDWIDTH');
      if (bandwidth == null) {
        throw const HlsPlaylistException('Variant missing BANDWIDTH');
      }
      String? next;
      for (var j = i + 1; j < lines.length; j++) {
        if (lines[j].trim().isEmpty) continue;
        next = lines[j].trim();
        break;
      }
      if (next == null || next.startsWith('#')) {
        throw const HlsPlaylistException('Variant missing URI');
      }
      result.add(
        _Variant(
            _resolveReferenceUri(base, next), int.tryParse(bandwidth) ?? 0),
      );
    }
    return result;
  }

  static String? _attribute(String value, String key) {
    final match = RegExp('(?:^|,)$key=([^,]+)').firstMatch(value);
    return match?.group(1)?.replaceAll('"', '');
  }

  static List<String> _lines(String content) =>
      LineSplitter.split(content).toList();

  /// Some providers put a signed token on the playlist URL and omit it from
  /// relative segment lines. Carrying it forward keeps those segment requests
  /// authorized while preserving explicit segment query parameters.
  static Uri _resolveReferenceUri(Uri baseUri, String reference) {
    final resolved = baseUri.resolve(reference);
    final parsedReference = Uri.tryParse(reference);
    if (baseUri.hasQuery &&
        resolved.query.isEmpty &&
        parsedReference != null &&
        !parsedReference.hasScheme &&
        !parsedReference.hasQuery) {
      return resolved.replace(query: baseUri.query);
    }
    return resolved;
  }

  static void _validateUri(Uri uri) {
    if (!uri.hasScheme || uri.host.isEmpty) {
      throw const HlsPlaylistException('Playlist URI must be absolute');
    }
  }

  static Future<String> _fetchText(Uri uri) async {
    final client = HttpClient()..autoUncompress = false;
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, hlsDownloadUserAgent);
      request.headers.set(HttpHeaders.acceptHeader, '*/*');
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      request.headers.set(HttpHeaders.refererHeader, uri.toString());
      request.headers.set('Origin', _originFor(uri));
      final response = await request.close();
      _debugLog(
        'playlist_response status=${response.statusCode} '
        'contentLength=${response.contentLength} '
        'contentType=${response.headers.contentType} uri=$uri',
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HlsPlaylistException(
            'Playlist request failed (HTTP ${response.statusCode}): $uri');
      }
      return await response.transform(utf8.decoder).join();
    } catch (error) {
      _debugLog('playlist_http_error uri=$uri error=$error');
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  void _log(String message) {
    _logger('[Cineo][Download] $message');
  }

  static void _debugLog(String message) {
    debugPrint(message);
  }

  static void _debugStack(HlsDownloadLogSink logger, StackTrace stackTrace) {
    if (stackTrace != StackTrace.empty) {
      debugPrintStack(
        label: '[Cineo][Download] stack',
        stackTrace: stackTrace,
        maxFrames: 10,
      );
    }
  }

  static String _originFor(Uri uri) {
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port';
  }
}

class _Variant {
  const _Variant(this.uri, this.bandwidth);
  final Uri uri;
  final int bandwidth;
}
