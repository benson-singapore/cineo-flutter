enum MediaKind { movie, series }

class Episode {
  const Episode({
    required this.id,
    required this.title,
    required this.season,
    required this.number,
    this.duration = const Duration(minutes: 42),
    this.playbackOption,
  });

  final String id;
  final String title;
  final int season;
  final int number;
  final Duration duration;
  final PlaybackOption? playbackOption;
}

class PlaybackOption {
  const PlaybackOption({
    required this.id,
    required this.sourceId,
    required this.label,
    required this.url,
    required this.quality,
    this.isHls = false,
  });

  final String id;
  final String sourceId;
  final String label;
  final String url;
  final String quality;
  final bool isHls;
}

class MediaItem {
  const MediaItem({
    required this.id,
    required this.title,
    required this.description,
    required this.year,
    required this.kind,
    required this.posterUrl,
    required this.backdropUrl,
    required this.genres,
    required this.rating,
    required this.duration,
    this.episodes = const [],
    this.playbackOptions = const [],
    this.sourceId,
    this.sourceName,
    this.remoteId,
    this.category,
    this.categoryId,
  });

  final String id;
  final String title;
  final String description;
  final int year;
  final MediaKind kind;
  final String posterUrl;
  final String backdropUrl;
  final List<String> genres;
  final double rating;
  final Duration duration;
  final List<Episode> episodes;
  final List<PlaybackOption> playbackOptions;
  final String? sourceId;
  final String? sourceName;
  final String? remoteId;
  final String? category;
  final String? categoryId;

  MediaItem copyWith({
    String? title,
    String? description,
    int? year,
    MediaKind? kind,
    String? posterUrl,
    String? backdropUrl,
    List<String>? genres,
    double? rating,
    Duration? duration,
    List<Episode>? episodes,
    List<PlaybackOption>? playbackOptions,
    String? sourceId,
    String? sourceName,
    String? remoteId,
    String? category,
    String? categoryId,
  }) {
    return MediaItem(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      year: year ?? this.year,
      kind: kind ?? this.kind,
      posterUrl: posterUrl ?? this.posterUrl,
      backdropUrl: backdropUrl ?? this.backdropUrl,
      genres: genres ?? this.genres,
      rating: rating ?? this.rating,
      duration: duration ?? this.duration,
      episodes: episodes ?? this.episodes,
      playbackOptions: playbackOptions ?? this.playbackOptions,
      sourceId: sourceId ?? this.sourceId,
      sourceName: sourceName ?? this.sourceName,
      remoteId: remoteId ?? this.remoteId,
      category: category ?? this.category,
      categoryId: categoryId ?? this.categoryId,
    );
  }
}

class WatchProgress {
  const WatchProgress({
    required this.mediaId,
    required this.position,
    required this.duration,
    required this.updatedAt,
    this.episodeId,
    this.episodeLabel,
    this.episodeNumber,
    this.episodeCount,
  });

  final String mediaId;
  final String? episodeId;
  final String? episodeLabel;
  final int? episodeNumber;
  final int? episodeCount;
  final Duration position;
  final Duration duration;
  final DateTime updatedAt;

  double get fraction => duration.inMilliseconds == 0
      ? 0
      : (position.inMilliseconds / duration.inMilliseconds).clamp(0, 1);

  bool get isComplete => fraction >= .95;
}
