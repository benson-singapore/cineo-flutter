enum TmdbMediaType { movie, tv }

enum TmdbDetailsLevel { preview, base, enriched }

class TmdbMediaMatch {
  const TmdbMediaMatch({
    required this.id,
    required this.mediaType,
    required this.title,
    required this.originalTitle,
    required this.overview,
    required this.year,
    required this.posterUrl,
    required this.backdropUrl,
    required this.rating,
  });

  final int id;
  final TmdbMediaType mediaType;
  final String title;
  final String originalTitle;
  final String overview;
  final int? year;
  final String posterUrl;
  final String backdropUrl;
  final double rating;
}

class TmdbMediaDetails extends TmdbMediaMatch {
  const TmdbMediaDetails({
    required super.id,
    required super.mediaType,
    required super.title,
    required super.originalTitle,
    required super.overview,
    required super.year,
    required super.posterUrl,
    required super.backdropUrl,
    required super.rating,
    required this.runtime,
    this.seasons = const [],
    this.cast = const [],
    this.level = TmdbDetailsLevel.enriched,
  });

  final int? runtime;
  final List<TmdbSeasonMetadata> seasons;
  final List<TmdbCastMember> cast;
  final TmdbDetailsLevel level;

  bool get isTv => mediaType == TmdbMediaType.tv;
}

class TmdbCastMember {
  const TmdbCastMember({
    required this.id,
    required this.name,
    required this.character,
    required this.profileUrl,
  });

  final int id;
  final String name;
  final String character;
  final String profileUrl;
}

class TmdbSeasonMetadata {
  const TmdbSeasonMetadata({
    required this.id,
    required this.seasonNumber,
    required this.name,
    required this.overview,
    required this.posterUrl,
    required this.episodes,
  });

  final int id;
  final int seasonNumber;
  final String name;
  final String overview;
  final String posterUrl;
  final List<TmdbEpisodeMetadata> episodes;
}

class TmdbEpisodeMetadata {
  const TmdbEpisodeMetadata({
    required this.id,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.name,
    required this.overview,
    required this.stillUrl,
    required this.rating,
    required this.runtime,
  });

  final int id;
  final int seasonNumber;
  final int episodeNumber;
  final String name;
  final String overview;
  final String stillUrl;
  final double rating;
  final int? runtime;
}
