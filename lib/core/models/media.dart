enum MediaKind { movie, series }

class Episode {
  const Episode({
    required this.id,
    required this.title,
    required this.season,
    required this.number,
    this.duration = const Duration(minutes: 42),
  });

  final String id;
  final String title;
  final int season;
  final int number;
  final Duration duration;
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
}

class WatchProgress {
  const WatchProgress({
    required this.mediaId,
    required this.position,
    required this.duration,
    required this.updatedAt,
    this.episodeId,
  });

  final String mediaId;
  final String? episodeId;
  final Duration position;
  final Duration duration;
  final DateTime updatedAt;

  double get fraction => duration.inMilliseconds == 0
      ? 0
      : (position.inMilliseconds / duration.inMilliseconds).clamp(0, 1);

  bool get isComplete => fraction >= .95;
}
