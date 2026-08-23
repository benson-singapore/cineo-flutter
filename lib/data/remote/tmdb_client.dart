import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/models/tmdb_media.dart';

typedef TmdbFetcher = Future<TmdbHttpResponse> Function(
  Uri uri,
  Map<String, String> headers,
);

class TmdbHttpResponse {
  const TmdbHttpResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

enum TmdbErrorKind {
  invalidConfiguration,
  unauthorized,
  forbidden,
  notFound,
  rateLimited,
  server,
  network,
  invalidResponse,
}

class TmdbApiException implements Exception {
  const TmdbApiException({
    required this.kind,
    required this.message,
    this.statusCode,
  });

  final TmdbErrorKind kind;
  final String message;
  final int? statusCode;

  @override
  String toString() => 'TmdbApiException: $message';
}

/// Small TMDB v3 client. The token is sent as a Bearer header and never put in
/// a URL or included in an exception message.
class TmdbClient {
  TmdbClient({
    required String bearerToken,
    TmdbFetcher? fetcher,
    this.timeout = const Duration(seconds: 15),
    Uri? baseUri,
  })  : _bearerToken = bearerToken.trim(),
        _fetcher = fetcher ?? _defaultFetch,
        _baseUri = baseUri ?? Uri.parse('https://api.themoviedb.org/3/') {
    if (_bearerToken.isEmpty) {
      throw const TmdbApiException(
        kind: TmdbErrorKind.invalidConfiguration,
        message: 'TMDB API Token 未配置',
      );
    }
    if (!_baseUri.hasScheme || _baseUri.host.isEmpty) {
      throw const TmdbApiException(
        kind: TmdbErrorKind.invalidConfiguration,
        message: 'TMDB API 地址无效',
      );
    }
  }

  final String _bearerToken;
  final TmdbFetcher _fetcher;
  final Duration timeout;
  final Uri _baseUri;

  Future<List<TmdbMediaMatch>> search(
    String title, {
    TmdbMediaType? type,
    int? year,
  }) async {
    final query = title.trim();
    if (query.isEmpty) return const [];
    final endpoint = type == TmdbMediaType.movie
        ? 'search/movie'
        : type == TmdbMediaType.tv
            ? 'search/tv'
            : 'search/multi';
    final payload = await _request(endpoint, <String, String>{
      'query': query,
      'language': 'zh-CN',
      'include_adult': 'false',
      if (year != null && type == TmdbMediaType.movie) 'year': '$year',
      if (year != null && type == TmdbMediaType.tv)
        'first_air_date_year': '$year',
    });
    final results = _list(payload['results']);
    return results
        .map((item) => _matchFromMap(item, fallbackType: type))
        .whereType<TmdbMediaMatch>()
        .where((item) => type == null || item.mediaType == type)
        .toList(growable: false);
  }

  Future<TmdbMediaMatch?> findBestMatch(
    String title, {
    TmdbMediaType? type,
    int? year,
  }) async {
    final matches = await search(title, type: type, year: year);
    if (matches.isEmpty) return null;
    final normalizedQuery = _normalize(title);
    final ranked = [...matches]..sort((left, right) =>
        _matchScore(right, normalizedQuery, year, type)
            .compareTo(_matchScore(left, normalizedQuery, year, type)));
    return ranked.first;
  }

  Future<TmdbMediaDetails?> getDetails(TmdbMediaMatch match) async {
    final path = match.mediaType == TmdbMediaType.tv
        ? 'tv/${match.id}'
        : 'movie/${match.id}';
    final payload = await _request(path, const {'language': 'zh-CN'});
    return _detailsFromMap(payload, match);
  }

  Future<TmdbMediaDetails> getEnrichedDetails(TmdbMediaDetails details) async {
    final path = details.mediaType == TmdbMediaType.tv
        ? 'tv/${details.id}'
        : 'movie/${details.id}';
    final creditsFuture =
        _request('$path/credits', const {'language': 'zh-CN'});
    final seasonsFuture = details.mediaType == TmdbMediaType.tv
        ? Future.wait(
            details.seasons.map(
              (season) => getSeason(details.id, season.seasonNumber),
            ),
          )
        : Future.value(const <TmdbSeasonMetadata>[]);
    final results = await Future.wait<Object>([creditsFuture, seasonsFuture]);
    return TmdbMediaDetails(
      id: details.id,
      mediaType: details.mediaType,
      title: details.title,
      originalTitle: details.originalTitle,
      overview: details.overview,
      year: details.year,
      posterUrl: details.posterUrl,
      backdropUrl: details.backdropUrl,
      rating: details.rating,
      runtime: details.runtime,
      seasons: results[1] as List<TmdbSeasonMetadata>,
      cast: _castFromCredits(results[0] as Map<String, dynamic>),
      level: TmdbDetailsLevel.enriched,
    );
  }

  Future<TmdbMediaDetails?> findDetails(
    String title, {
    TmdbMediaType? type,
    int? year,
  }) async {
    final match = await findBestMatch(title, type: type, year: year);
    return match == null ? null : getDetails(match);
  }

  Future<TmdbSeasonMetadata> getSeason(
    int tvId,
    int seasonNumber,
  ) async {
    if (tvId <= 0 || seasonNumber < 0) {
      throw const TmdbApiException(
        kind: TmdbErrorKind.invalidConfiguration,
        message: 'TMDB 剧集或季数无效',
      );
    }
    final payload = await _request(
      'tv/$tvId/season/$seasonNumber',
      const {'language': 'zh-CN'},
    );
    return _seasonFromMap(payload, seasonNumber: seasonNumber);
  }

  Future<Map<String, dynamic>> _request(
    String path,
    Map<String, String> parameters,
  ) async {
    final uri = _baseUri.resolve(path).replace(queryParameters: parameters);
    final headers = <String, String>{
      HttpHeaders.acceptHeader: 'application/json',
      HttpHeaders.authorizationHeader: 'Bearer $_bearerToken',
    };
    late TmdbHttpResponse response;
    try {
      response =
          await _fetcher(uri, Map.unmodifiable(headers)).timeout(timeout);
    } on TmdbApiException {
      rethrow;
    } on TimeoutException {
      throw const TmdbApiException(
        kind: TmdbErrorKind.network,
        message: 'TMDB 请求超时',
      );
    } on Object catch (error) {
      throw TmdbApiException(
        kind: TmdbErrorKind.network,
        message: 'TMDB 网络请求失败（${error.runtimeType}）',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _exceptionForStatus(response.statusCode);
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) throw const FormatException();
      return Map<String, dynamic>.from(decoded);
    } on Object {
      throw const TmdbApiException(
        kind: TmdbErrorKind.invalidResponse,
        message: 'TMDB 返回的不是有效 JSON 对象',
      );
    }
  }

  TmdbMediaDetails? _detailsFromMap(
    Map<String, dynamic> raw,
    TmdbMediaMatch match,
  ) {
    final type = match.mediaType;
    if (type == TmdbMediaType.movie) {
      return TmdbMediaDetails(
        id: _int(raw['id']) ?? match.id,
        mediaType: type,
        title: _text(raw['title'], fallback: match.title),
        originalTitle:
            _text(raw['original_title'], fallback: match.originalTitle),
        overview: _text(raw['overview'], fallback: match.overview),
        year: _year(raw['release_date']) ?? match.year,
        posterUrl: _imageUrl(raw['poster_path']) == ''
            ? match.posterUrl
            : _imageUrl(raw['poster_path']),
        backdropUrl: _imageUrl(raw['backdrop_path'], size: 'w780') == ''
            ? match.backdropUrl
            : _imageUrl(raw['backdrop_path'], size: 'w780'),
        rating: _number(raw['vote_average']) ?? match.rating,
        runtime: _int(raw['runtime']),
        level: TmdbDetailsLevel.base,
      );
    }
    return TmdbMediaDetails(
      id: _int(raw['id']) ?? match.id,
      mediaType: type,
      title: _text(raw['name'], fallback: match.title),
      originalTitle: _text(raw['original_name'], fallback: match.originalTitle),
      overview: _text(raw['overview'], fallback: match.overview),
      year: _year(raw['first_air_date']) ?? match.year,
      posterUrl: _imageUrl(raw['poster_path']).isEmpty
          ? match.posterUrl
          : _imageUrl(raw['poster_path']),
      backdropUrl: _imageUrl(raw['backdrop_path'], size: 'w780').isEmpty
          ? match.backdropUrl
          : _imageUrl(raw['backdrop_path'], size: 'w780'),
      rating: _number(raw['vote_average']) ?? match.rating,
      runtime: _firstRuntime(raw['episode_run_time']),
      seasons: _seasonSkeletons(raw),
      level: TmdbDetailsLevel.base,
    );
  }

  List<TmdbSeasonMetadata> _seasonSkeletons(Map<String, dynamic> raw) {
    return _list(raw['seasons'])
        .map(
          (season) => TmdbSeasonMetadata(
            id: _int(season['id']) ?? 0,
            seasonNumber: _int(season['season_number']) ?? 0,
            name: _text(
              season['name'],
              fallback: '第${_int(season['season_number']) ?? 0}季',
            ),
            overview: _text(season['overview']),
            posterUrl: _imageUrl(season['poster_path']),
            episodes: const [],
          ),
        )
        .where((season) => season.seasonNumber >= 0)
        .toList(growable: false);
  }

  List<TmdbCastMember> _castFromCredits(Map<String, dynamic> raw) {
    return _list(raw['cast'])
        .map(_castMemberFromMap)
        .whereType<TmdbCastMember>()
        .take(20)
        .toList(growable: false);
  }

  TmdbCastMember? _castMemberFromMap(Map<String, dynamic> raw) {
    final id = _int(raw['id']);
    final name = _text(raw['name']);
    if (id == null || name.isEmpty) return null;
    return TmdbCastMember(
      id: id,
      name: name,
      character: _text(raw['character']),
      profileUrl: _imageUrl(raw['profile_path'], size: 'w185'),
    );
  }

  TmdbSeasonMetadata _seasonFromMap(
    Map<String, dynamic> raw, {
    required int seasonNumber,
  }) {
    return TmdbSeasonMetadata(
      id: _int(raw['id']) ?? 0,
      seasonNumber: _int(raw['season_number']) ?? seasonNumber,
      name: _text(raw['name'], fallback: '第$seasonNumber季'),
      overview: _text(raw['overview']),
      posterUrl: _imageUrl(raw['poster_path']),
      episodes: _list(raw['episodes'])
          .map((item) => _episodeFromMap(item, seasonNumber: seasonNumber))
          .whereType<TmdbEpisodeMetadata>()
          .toList(growable: false),
    );
  }

  TmdbEpisodeMetadata? _episodeFromMap(
    Map<String, dynamic> raw, {
    required int seasonNumber,
  }) {
    final episodeNumber = _int(raw['episode_number']);
    if (episodeNumber == null) return null;
    return TmdbEpisodeMetadata(
      id: _int(raw['id']) ?? 0,
      seasonNumber: _int(raw['season_number']) ?? seasonNumber,
      episodeNumber: episodeNumber,
      name: _text(raw['name'], fallback: '第$episodeNumber集'),
      overview: _text(raw['overview']),
      stillUrl: _imageUrl(raw['still_path']),
      rating: _number(raw['vote_average']) ?? 0,
      runtime: _int(raw['runtime']),
    );
  }

  TmdbMediaMatch? _matchFromMap(
    Map<String, dynamic> raw, {
    TmdbMediaType? fallbackType,
  }) {
    final id = _int(raw['id']);
    final mediaType = _type(raw['media_type']) ?? fallbackType;
    if (id == null || mediaType == null) return null;
    final isTv = mediaType == TmdbMediaType.tv;
    return TmdbMediaMatch(
      id: id,
      mediaType: mediaType,
      title: _text(raw[isTv ? 'name' : 'title']),
      originalTitle: _text(raw[isTv ? 'original_name' : 'original_title']),
      overview: _text(raw['overview']),
      year: _year(raw[isTv ? 'first_air_date' : 'release_date']),
      posterUrl: _imageUrl(raw['poster_path']),
      backdropUrl: _imageUrl(raw['backdrop_path'], size: 'w780'),
      rating: _number(raw['vote_average']) ?? 0,
    );
  }

  int _matchScore(
    TmdbMediaMatch item,
    String query,
    int? year,
    TmdbMediaType? type,
  ) {
    final title = _normalize(item.title);
    final original = _normalize(item.originalTitle);
    var score = 0;
    if (title == query) score += 100;
    if (original == query) score += 85;
    if (title.contains(query) || query.contains(title)) score += 35;
    if (original.contains(query) || query.contains(original)) score += 20;
    if (year != null && item.year == year) score += 30;
    if (type != null && item.mediaType == type) score += 20;
    score += (item.rating * 2).round();
    return score;
  }

  static TmdbApiException _exceptionForStatus(int status) {
    final kind = switch (status) {
      401 => TmdbErrorKind.unauthorized,
      403 => TmdbErrorKind.forbidden,
      404 => TmdbErrorKind.notFound,
      429 => TmdbErrorKind.rateLimited,
      >= 500 => TmdbErrorKind.server,
      _ => TmdbErrorKind.invalidResponse,
    };
    final message = switch (kind) {
      TmdbErrorKind.unauthorized => 'TMDB API Token 无效或已过期',
      TmdbErrorKind.forbidden => 'TMDB 拒绝了本次请求',
      TmdbErrorKind.notFound => 'TMDB 资源不存在',
      TmdbErrorKind.rateLimited => 'TMDB 请求过于频繁，请稍后重试',
      TmdbErrorKind.server => 'TMDB 服务暂时不可用',
      _ => 'TMDB 请求失败（HTTP $status）',
    };
    return TmdbApiException(kind: kind, message: message, statusCode: status);
  }

  static Future<TmdbHttpResponse> _defaultFetch(
    Uri uri,
    Map<String, String> headers,
  ) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      headers.forEach(request.headers.set);
      final response = await request.close();
      return TmdbHttpResponse(
        statusCode: response.statusCode,
        body: await utf8.decodeStream(response),
      );
    } on SocketException {
      throw const TmdbApiException(
        kind: TmdbErrorKind.network,
        message: 'TMDB 网络连接失败',
      );
    } finally {
      client.close(force: true);
    }
  }

  static List<Map<String, dynamic>> _list(Object? value) => value is List
      ? value.whereType<Map>().map(Map<String, dynamic>.from).toList()
      : const [];

  static TmdbMediaType? _type(Object? value) {
    if (value == 'movie') return TmdbMediaType.movie;
    if (value == 'tv') return TmdbMediaType.tv;
    return null;
  }

  static int? _int(Object? value) =>
      value is num ? value.toInt() : int.tryParse('$value');
  static double? _number(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value');

  static int? _year(Object? value) {
    final match = RegExp(r'^(\d{4})').firstMatch('$value');
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  static int? _firstRuntime(Object? value) =>
      value is List && value.isNotEmpty ? _int(value.first) : null;

  static String _text(Object? value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[\s\p{P}\p{S}]+', unicode: true), '');

  static String _imageUrl(Object? path, {String size = 'w500'}) {
    final value = _text(path);
    if (value.isEmpty) return '';
    if (value.startsWith('https://image.tmdb.org/t/p/')) return value;
    final normalized = value.startsWith('/') ? value : '/$value';
    return 'https://image.tmdb.org/t/p/$size$normalized';
  }
}
