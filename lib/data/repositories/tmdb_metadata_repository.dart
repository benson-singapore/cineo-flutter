import 'dart:io';

import '../../core/models/media.dart';
import '../../core/models/tmdb_media.dart';
import '../cache/tmdb_disk_cache.dart';
import '../remote/tmdb_client.dart';

typedef TmdbTokenReader = Future<String?> Function();
typedef TmdbRetentionProvider = Duration Function();

/// Coordinates TMDB requests with the on-device cache. Cached records keep
/// remote URLs, while returned values prefer local `file://` image URIs.
class TmdbMetadataRepository {
  TmdbMetadataRepository({
    required TmdbDiskCache cache,
    required TmdbTokenReader readToken,
    required TmdbRetentionProvider retention,
    TmdbClient Function(String token)? clientFactory,
  })  : _cache = cache,
        _readToken = readToken,
        _retention = retention,
        _clientFactory =
            clientFactory ?? ((token) => TmdbClient(bearerToken: token));

  final TmdbDiskCache _cache;
  final TmdbTokenReader _readToken;
  final TmdbRetentionProvider _retention;
  final TmdbClient Function(String token) _clientFactory;

  Future<TmdbMediaDetails?> loadForMedia(MediaItem media) async {
    final cached = await _cache.getDetails(media.id);
    if (cached != null) {
      if (cached.posterUrl.trim().isNotEmpty) {
        return _withCachedImages(cached);
      }
      final client = await _client();
      if (client == null) return _withCachedImages(cached);
      final refreshed = await client.getDetails(cached);
      return refreshed == null
          ? _withCachedImages(cached)
          : _storeAndLocalize(media.id, refreshed);
    }

    final client = await _client();
    if (client == null) return null;
    final override = await _cache.getOverride(media.id);
    final type =
        media.kind == MediaKind.series ? TmdbMediaType.tv : TmdbMediaType.movie;
    final match = override ??
        await client.findBestMatch(
          media.title,
          type: type,
          year: media.year > 0 ? media.year : null,
        );
    if (match == null) return null;
    final details = await client.getDetails(match);
    if (details == null) return null;
    return _storeAndLocalize(media.id, details);
  }

  /// Reads previously loaded metadata without initiating TMDB matching or a
  /// network request.
  ///
  /// Home uses this to show a stored poster immediately while keeping refreshes
  /// independent from TMDB availability.
  Future<TmdbMediaDetails?> loadCachedForMedia(MediaItem media) async {
    final cached = await _cache.getDetails(media.id);
    return cached == null ? null : _withCachedImages(cached);
  }

  Future<List<TmdbMediaMatch>> search(
    String query,
    TmdbMediaType? type,
    int? year,
  ) async {
    final client = await _client();
    if (client == null) return const [];
    return client.search(query, type: type, year: year);
  }

  Future<TmdbMediaDetails?> selectForMedia(
    MediaItem media,
    TmdbMediaMatch match,
  ) async {
    final client = await _client();
    if (client == null) return null;
    final details = await client.getDetails(match);
    if (details == null) return null;
    await _cache.setOverride(cineoMediaId: media.id, match: match);
    return _storeAndLocalize(media.id, details);
  }

  Future<TmdbMediaDetails> _storeAndLocalize(
    String mediaId,
    TmdbMediaDetails details,
  ) async {
    final ttl = _retention();
    await _cache.putDetails(mediaId: mediaId, details: details, ttl: ttl);
    await Future.wait(
      _imageUrls(details).map(
        (url) async {
          try {
            await _cache.cacheImage(url, ttl: ttl);
          } on Object {
            // Metadata remains useful when individual images cannot download.
          }
        },
      ),
    );
    return _withCachedImages(details);
  }

  Future<TmdbClient?> _client() async {
    final token = await _readToken();
    return token == null ? null : _clientFactory(token);
  }

  Future<TmdbMediaDetails> _withCachedImages(TmdbMediaDetails details) async {
    Future<String> local(String url) async {
      if (url.trim().isEmpty) return url;
      final path = await _cache.getCachedImagePath(url);
      return path == null ? url : File(path).uri.toString();
    }

    final seasons = <TmdbSeasonMetadata>[];
    for (final season in details.seasons) {
      final episodes = <TmdbEpisodeMetadata>[];
      for (final episode in season.episodes) {
        episodes.add(TmdbEpisodeMetadata(
          id: episode.id,
          seasonNumber: episode.seasonNumber,
          episodeNumber: episode.episodeNumber,
          name: episode.name,
          overview: episode.overview,
          stillUrl: await local(episode.stillUrl),
          rating: episode.rating,
          runtime: episode.runtime,
        ));
      }
      seasons.add(TmdbSeasonMetadata(
        id: season.id,
        seasonNumber: season.seasonNumber,
        name: season.name,
        overview: season.overview,
        posterUrl: await local(season.posterUrl),
        episodes: episodes,
      ));
    }
    return TmdbMediaDetails(
      id: details.id,
      mediaType: details.mediaType,
      title: details.title,
      originalTitle: details.originalTitle,
      overview: details.overview,
      year: details.year,
      posterUrl: await local(details.posterUrl),
      backdropUrl: await local(details.backdropUrl),
      rating: details.rating,
      runtime: details.runtime,
      seasons: seasons,
      cast: await Future.wait(
        details.cast.map(
          (member) async => TmdbCastMember(
            id: member.id,
            name: member.name,
            character: member.character,
            profileUrl: await local(member.profileUrl),
          ),
        ),
      ),
    );
  }

  Iterable<String> _imageUrls(TmdbMediaDetails details) sync* {
    if (details.posterUrl.trim().isNotEmpty) yield details.posterUrl;
    if (details.backdropUrl.trim().isNotEmpty) yield details.backdropUrl;
    for (final season in details.seasons) {
      if (season.posterUrl.trim().isNotEmpty) yield season.posterUrl;
      for (final episode in season.episodes) {
        if (episode.stillUrl.trim().isNotEmpty) yield episode.stillUrl;
      }
    }
    for (final member in details.cast) {
      if (member.profileUrl.trim().isNotEmpty) yield member.profileUrl;
    }
  }
}
