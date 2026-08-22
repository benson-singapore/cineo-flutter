import 'package:flutter/material.dart';

import '../../core/models/media.dart';
import '../../core/models/tmdb_media.dart';
import '../../core/theme/cineo_theme.dart';
import '../../shared/widgets/media_image.dart';

class EpisodeLibraryScreen extends StatelessWidget {
  const EpisodeLibraryScreen({
    super.key,
    required this.media,
    required this.episodes,
    required this.tmdbSeason,
    required this.fallbackPosterUrl,
    required this.onPlay,
  });

  final MediaItem media;
  final List<Episode> episodes;
  final TmdbSeasonMetadata? tmdbSeason;
  final String fallbackPosterUrl;
  final ValueChanged<PlaybackOption> onPlay;

  TmdbEpisodeMetadata? _metadataFor(Episode episode) {
    for (final item in tmdbSeason?.episodes ?? const <TmdbEpisodeMetadata>[]) {
      if (item.episodeNumber == episode.number) return item;
    }
    return null;
  }

  String _imageFor(TmdbEpisodeMetadata? metadata) {
    final still = metadata?.stillUrl.trim() ?? '';
    if (still.isNotEmpty) return still;
    final seasonPoster = tmdbSeason?.posterUrl.trim() ?? '';
    if (seasonPoster.isNotEmpty) return seasonPoster;
    final poster = fallbackPosterUrl.trim();
    if (poster.isNotEmpty) return poster;
    return media.backdropUrl;
  }

  @override
  Widget build(BuildContext context) {
    final sortedEpisodes = [...episodes]
      ..sort((left, right) => left.number.compareTo(right.number));
    final seasonName = tmdbSeason?.seasonNumber == null
        ? '剧集列表'
        : '第${tmdbSeason!.seasonNumber}季 · 全部剧集';
    return Scaffold(
      backgroundColor: CineoColors.background,
      appBar: AppBar(title: Text(seasonName)),
      body: sortedEpisodes.isEmpty
          ? const Center(
              child: Text('当前来源暂无剧集',
                  style: TextStyle(color: CineoColors.textSecondary)),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 760
                    ? 4
                    : constraints.maxWidth >= 520
                        ? 3
                        : 2;
                return CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: Row(
                          children: [
                            Container(
                              width: 3,
                              height: 18,
                              decoration: BoxDecoration(
                                color: CineoColors.primary,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${sortedEpisodes.length} 集',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const Spacer(),
                            const Icon(Icons.swipe_rounded,
                                size: 16, color: CineoColors.textSecondary),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      sliver: SliverGrid(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final episode = sortedEpisodes[index];
                            final metadata = _metadataFor(episode);
                            final title =
                                metadata?.name.trim().isNotEmpty == true
                                    ? metadata!.name
                                    : '第${episode.number}集';
                            return _EpisodeTile(
                              episode: episode,
                              title: title,
                              imageUrl: _imageFor(metadata),
                              rating: metadata?.rating ?? 0,
                              onPlay: episode.playbackOption == null
                                  ? null
                                  : () => onPlay(episode.playbackOption!),
                            );
                          },
                          childCount: sortedEpisodes.length,
                        ),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 18,
                          childAspectRatio: columns >= 4 ? 1.25 : 1.3,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    required this.episode,
    required this.title,
    required this.imageUrl,
    required this.rating,
    required this.onPlay,
  });

  final Episode episode;
  final String title;
  final String imageUrl;
  final double rating;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: ValueKey('library-${episode.id}'),
      borderRadius: BorderRadius.circular(8),
      onTap: onPlay,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: CineoColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: CineoColors.divider),
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MediaImage(
                        url: imageUrl,
                        borderRadius: BorderRadius.circular(6),
                        placeholderIcon: Icons.live_tv_outlined,
                      ),
                      Positioned(
                        left: 7,
                        top: 7,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(.78),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            child: Text(
                              '第${episode.number}集',
                              style: const TextStyle(
                                color: CineoColors.primaryLight,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (rating > 0)
                        Positioned(
                          right: 7,
                          bottom: 7,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(.72),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              child: Text(
                                rating.toStringAsFixed(1),
                                style: const TextStyle(
                                  color: CineoColors.primaryLight,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 7),
              Text(
                '第${episode.number}集${title.trim().isEmpty ? '' : ' · $title'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
