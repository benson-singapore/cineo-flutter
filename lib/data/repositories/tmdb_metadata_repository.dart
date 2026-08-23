import 'dart:async';
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

  /// Resolves enough TMDB metadata to render the detail page hero. It only
  /// performs a title match when no record exists, so first navigation is not
  /// held up by credits, season episodes, or image downloads.
  Future<TmdbMediaDetails?> loadPreviewForMedia(MediaItem media) async {
    final cached = await _cache.getDetails(media.id);
    if (cached != null) return _withCachedHeroImages(cached);

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
    final preview = _previewFromMatch(match);
    return _storeAndLocalize(media.id, preview);
  }

  /// Loads the core detail payload after the page has opened. This deliberately
  /// excludes credits and per-season episode payloads.
  Future<TmdbMediaDetails?> loadDetailsForMedia(MediaItem media) async {
    final cached = await _cache.getDetails(media.id);
    if (cached == null) return loadPreviewForMedia(media);
    if (cached.level != TmdbDetailsLevel.preview) {
      return _withCachedImages(cached);
    }
    final client = await _client();
    if (client == null) return _withCachedImages(cached);
    final details = await client.getDetails(cached);
    return details == null
        ? _withCachedImages(cached)
        : _storeAndLocalize(media.id, details);
  }

  /// Loads cast and per-season episode metadata after core TMDB details are
  /// visible. Image persistence remains background work.
  Future<TmdbMediaDetails?> loadEnrichmentForMedia(MediaItem media) async {
    // Read the persisted record rather than the localized return value from
    // loadDetailsForMedia. The latter may contain file:// image paths, which
    // must never be stored back as TMDB remote image URLs.
    var details = await _cache.getDetails(media.id);
    if (details == null || details.level == TmdbDetailsLevel.preview) {
      await loadDetailsForMedia(media);
      details = await _cache.getDetails(media.id);
    }
    if (details == null || details.level == TmdbDetailsLevel.enriched) {
      return details == null ? null : _withCachedImages(details);
    }
    final client = await _client();
    if (client == null) return _withCachedImages(details);
    final enriched = await client.getEnrichedDetails(details);
    return _storeAndLocalize(media.id, enriched);
  }

  /// Retained for callers that require the complete record before returning.
  Future<TmdbMediaDetails?> loadForMedia(MediaItem media) async {
    return loadEnrichmentForMedia(media);
  }

  /// Reads previously loaded metadata without initiating TMDB matching or a
  /// network request.
  ///
  /// Home uses this to show a stored poster immediately while keeping refreshes
  /// independent from TMDB availability.
  Future<TmdbMediaDetails?> loadCachedForMedia(MediaItem media) async {
    final cached = await _cache.getDetails(media.id);
    return cached == null ? null : _withCachedHeroImages(cached);
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
    unawaited(_cacheImages(details, ttl));
    return _withCachedImages(details);
  }

  Future<void> _cacheImages(TmdbMediaDetails details, Duration ttl) async {
    await Future.wait(_imageUrls(details).map((url) async {
      try {
        await _cache.cacheImage(url, ttl: ttl);
      } on Object {
        // Metadata remains useful when individual images cannot download.
      }
    }));
  }

  TmdbMediaDetails _previewFromMatch(TmdbMediaMatch match) {
    return TmdbMediaDetails(
      id: match.id,
      mediaType: match.mediaType,
      title: match.title,
      originalTitle: match.originalTitle,
      overview: match.overview,
      year: match.year,
      posterUrl: match.posterUrl,
      backdropUrl: match.backdropUrl,
      rating: match.rating,
      runtime: null,
      level: TmdbDetailsLevel.preview,
    );
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
      level: details.level,
    );
  }

  Future<TmdbMediaDetails> _withCachedHeroImages(
    TmdbMediaDetails details,
  ) async {
    Future<String> local(String url) async {
      if (url.trim().isEmpty) return url;
      final path = await _cache.getCachedImagePath(url);
      return path == null ? url : File(path).uri.toString();
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
      seasons: details.seasons,
      cast: details.cast,
      level: details.level,
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
