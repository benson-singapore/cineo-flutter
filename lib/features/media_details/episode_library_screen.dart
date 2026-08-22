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
          : CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  sliver: SliverGrid(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final episode = sortedEpisodes[index];
                        final metadata = _metadataFor(episode);
                        final title = metadata?.name.trim().isNotEmpty == true
                            ? metadata!.name
                            : '第${episode.number}集';
                        final overview = metadata?.overview.trim() ?? '';
                        return _EpisodeTile(
                          episode: episode,
                          title: title,
                          overview: overview,
                          imageUrl: _imageFor(metadata),
                          rating: metadata?.rating ?? 0,
                          onPlay: episode.playbackOption == null
                              ? null
                              : () => onPlay(episode.playbackOption!),
                        );
                      },
                      childCount: sortedEpisodes.length,
                    ),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 18,
                      childAspectRatio: .72,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    required this.episode,
    required this.title,
    required this.overview,
    required this.imageUrl,
    required this.rating,
    required this.onPlay,
  });

  final Episode episode;
  final String title;
  final String overview;
  final String imageUrl;
  final double rating;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: ValueKey('library-${episode.id}'),
      borderRadius: BorderRadius.circular(8),
      onTap: onPlay,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Stack(
              fit: StackFit.expand,
              children: [
                MediaImage(
                  url: imageUrl,
                  borderRadius: BorderRadius.circular(8),
                  placeholderIcon: Icons.live_tv_outlined,
                ),
                Positioned(
                  left: 8,
                  top: 8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(.78),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      child: Text('第${episode.number}集',
                          style: const TextStyle(fontSize: 11)),
                    ),
                  ),
                ),
                if (rating > 0)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Text(rating.toStringAsFixed(1),
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(
            overview.isEmpty ? '暂无简介' : overview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: CineoColors.textSecondary, fontSize: 12, height: 1.3),
          ),
        ],
      ),
    );
  }
}
