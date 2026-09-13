import 'package:flutter/material.dart';

import '../../core/models/media.dart';
import '../../core/models/tmdb_media.dart';
import '../../core/theme/cineo_theme.dart';
import '../../shared/widgets/media_image.dart';

class EpisodeLibraryScreen extends StatefulWidget {
  const EpisodeLibraryScreen({
    super.key,
    required this.media,
    required this.episodes,
    required this.tmdbSeason,
    required this.fallbackPosterUrl,
    this.progressByEpisodeId = const <String, WatchProgress>{},
    this.initialAscending = true,
    required this.onPlay,
  });

  final MediaItem media;
  final List<Episode> episodes;
  final TmdbSeasonMetadata? tmdbSeason;
  final String fallbackPosterUrl;
  final Map<String, WatchProgress> progressByEpisodeId;
  final bool initialAscending;
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
  State<EpisodeLibraryScreen> createState() => _EpisodeLibraryScreenState();
}

class _EpisodeLibraryScreenState extends State<EpisodeLibraryScreen> {
  final ScrollController _scrollController = ScrollController();
  late bool _ascending;
  bool _showBackToTop = false;

  MediaItem get media => widget.media;
  List<Episode> get episodes => widget.episodes;
  TmdbSeasonMetadata? get tmdbSeason => widget.tmdbSeason;
  String get fallbackPosterUrl => widget.fallbackPosterUrl;
  Map<String, WatchProgress> get progressByEpisodeId =>
      widget.progressByEpisodeId;
  ValueChanged<PlaybackOption> get onPlay => widget.onPlay;

  @override
  void initState() {
    super.initState();
    _ascending = widget.initialAscending;
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    final shouldShow =
        _scrollController.hasClients && _scrollController.offset > 40;
    if (shouldShow == _showBackToTop || !mounted) return;
    setState(() => _showBackToTop = shouldShow);
  }

  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final sortedEpisodes = [...episodes]..sort((left, right) => _ascending
        ? left.number.compareTo(right.number)
        : right.number.compareTo(left.number));
    final seasonName = tmdbSeason?.seasonNumber == null
        ? '剧集列表'
        : '第${tmdbSeason!.seasonNumber}季 · 全部剧集';
    return Scaffold(
      backgroundColor: CineoColors.background,
      appBar: AppBar(title: Text(seasonName)),
      floatingActionButton: _showBackToTop
          ? FloatingActionButton.small(
              key: const ValueKey('episode-back-to-top'),
              tooltip: '返回顶部',
              onPressed: _scrollToTop,
              child: const Icon(Icons.keyboard_arrow_up_rounded),
            )
          : null,
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
                  controller: _scrollController,
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
                            Tooltip(
                              message: _ascending ? '切换为倒序' : '切换为正序',
                              child: TextButton.icon(
                                key: const ValueKey('episode-sort-toggle'),
                                onPressed: () =>
                                    setState(() => _ascending = !_ascending),
                                icon: Icon(
                                  _ascending
                                      ? Icons.south_rounded
                                      : Icons.north_rounded,
                                  size: 18,
                                ),
                                label: Text(_ascending ? '正序' : '倒序'),
                              ),
                            ),
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
                            final metadata = widget._metadataFor(episode);
                            final title =
                                metadata?.name.trim().isNotEmpty == true
                                    ? metadata!.name
                                    : '第${episode.number}集';
                            return _EpisodeTile(
                              episode: episode,
                              title: title,
                              imageUrl: widget._imageFor(metadata),
                              rating: metadata?.rating ?? 0,
                              progress: progressByEpisodeId[episode.id] ??
                                  (episode.playbackOption == null
                                      ? null
                                      : progressByEpisodeId[
                                          episode.playbackOption!.id]),
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
    required this.progress,
    required this.onPlay,
  });

  final Episode episode;
  final String title;
  final String imageUrl;
  final double rating;
  final WatchProgress? progress;
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
                      if (progress != null)
                        Positioned(
                          key: ValueKey('library-progress-${episode.id}'),
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: LinearProgressIndicator(
                            value: progress!.fraction,
                            minHeight: 4,
                            backgroundColor: Colors.white24,
                            color: CineoColors.primary,
                          ),
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
