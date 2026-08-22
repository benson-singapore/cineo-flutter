import '../../core/models/tmdb_media.dart';

/// JSON helpers for TMDB values persisted by [TmdbDiskCache].
class TmdbCacheModelCodec {
  const TmdbCacheModelCodec._();

  static Map<String, dynamic> encodeMatch(TmdbMediaMatch value) {
    return <String, dynamic>{
      'id': value.id,
      'media_type': value.mediaType.name,
      'title': value.title,
      'original_title': value.originalTitle,
      'overview': value.overview,
      'year': value.year,
      'poster_url': value.posterUrl,
      'backdrop_url': value.backdropUrl,
      'rating': value.rating,
    };
  }

  static TmdbMediaMatch decodeMatch(Map<String, dynamic> json) {
    return TmdbMediaMatch(
      id: _asInt(json['id']),
      mediaType: _mediaType(json['media_type']),
      title: _asString(json['title']),
      originalTitle: _asString(json['original_title']),
      overview: _asString(json['overview']),
      year: _asNullableInt(json['year']),
      posterUrl: _asString(json['poster_url']),
      backdropUrl: _asString(json['backdrop_url']),
      rating: _asDouble(json['rating']),
    );
  }

  static Map<String, dynamic> encodeDetails(TmdbMediaDetails value) {
    return <String, dynamic>{
      ...encodeMatch(value),
      'runtime': value.runtime,
      'seasons': value.seasons.map(encodeSeason).toList(),
    };
  }

  static TmdbMediaDetails decodeDetails(Map<String, dynamic> json) {
    final seasons = json['seasons'];
    return TmdbMediaDetails(
      id: _asInt(json['id']),
      mediaType: _mediaType(json['media_type']),
      title: _asString(json['title']),
      originalTitle: _asString(json['original_title']),
      overview: _asString(json['overview']),
      year: _asNullableInt(json['year']),
      posterUrl: _asString(json['poster_url']),
      backdropUrl: _asString(json['backdrop_url']),
      rating: _asDouble(json['rating']),
      runtime: _asNullableInt(json['runtime']),
      seasons: seasons is List
          ? seasons
              .whereType<Map>()
              .map((item) => decodeSeason(Map<String, dynamic>.from(item)))
              .toList()
          : const <TmdbSeasonMetadata>[],
    );
  }

  static Map<String, dynamic> encodeSeason(TmdbSeasonMetadata value) {
    return <String, dynamic>{
      'id': value.id,
      'season_number': value.seasonNumber,
      'name': value.name,
      'overview': value.overview,
      'poster_url': value.posterUrl,
      'episodes': value.episodes.map(encodeEpisode).toList(),
    };
  }

  static TmdbSeasonMetadata decodeSeason(Map<String, dynamic> json) {
    final episodes = json['episodes'];
    return TmdbSeasonMetadata(
      id: _asInt(json['id']),
      seasonNumber: _asInt(json['season_number']),
      name: _asString(json['name']),
      overview: _asString(json['overview']),
      posterUrl: _asString(json['poster_url']),
      episodes: episodes is List
          ? episodes
              .whereType<Map>()
              .map((item) => decodeEpisode(Map<String, dynamic>.from(item)))
              .toList()
          : const <TmdbEpisodeMetadata>[],
    );
  }

  static Map<String, dynamic> encodeEpisode(TmdbEpisodeMetadata value) {
    return <String, dynamic>{
      'id': value.id,
      'season_number': value.seasonNumber,
      'episode_number': value.episodeNumber,
      'name': value.name,
      'overview': value.overview,
      'still_url': value.stillUrl,
      'rating': value.rating,
      'runtime': value.runtime,
    };
  }

  static TmdbEpisodeMetadata decodeEpisode(Map<String, dynamic> json) {
    return TmdbEpisodeMetadata(
      id: _asInt(json['id']),
      seasonNumber: _asInt(json['season_number']),
      episodeNumber: _asInt(json['episode_number']),
      name: _asString(json['name']),
      overview: _asString(json['overview']),
      stillUrl: _asString(json['still_url']),
      rating: _asDouble(json['rating']),
      runtime: _asNullableInt(json['runtime']),
    );
  }

  static TmdbMediaType _mediaType(Object? value) {
    return value == TmdbMediaType.movie.name
        ? TmdbMediaType.movie
        : TmdbMediaType.tv;
  }

  static String _asString(Object? value) => value is String ? value : '';

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  static int? _asNullableInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value');
  }

  static double _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }
}
