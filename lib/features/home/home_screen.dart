import 'package:flutter/material.dart';

import '../../core/models/home_category_rail.dart';
import '../../core/models/media.dart';
import '../../core/theme/cineo_theme.dart';
import '../../shared/widgets/cineo_brand_mark.dart';
import '../../shared/widgets/content_state_view.dart';
import '../../shared/widgets/media_image.dart';
import '../../shared/widgets/media_rail.dart';

typedef HomeRailSeeAllCallback = void Function(
  String title,
  List<MediaItem> items,
  List<String> categoryIds,
);

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.items,
    required this.continueWatching,
    this.favorites = const [],
    required this.onOpenMedia,
    this.isLoading = false,
    this.isRefreshing = false,
    this.errorMessage,
    this.onRetry,
    this.onRefresh,
    this.progressByMediaId = const {},
    this.categoryRails = const [],
    this.onSeeAll,
    this.onContinueWatching,
    this.onOpenSearch,
  });

  final List<MediaItem> items;
  final List<MediaItem> continueWatching;
  final List<MediaItem> favorites;
  final Future<void> Function(MediaItem) onOpenMedia;
  final bool isLoading;
  final bool isRefreshing;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final Future<void> Function()? onRefresh;
  final Map<String, double> progressByMediaId;
  final List<HomeCategoryRail> categoryRails;

  final HomeRailSeeAllCallback? onSeeAll;
  final Future<void> Function(MediaItem)? onContinueWatching;
  final VoidCallback? onOpenSearch;

  @override
  Widget build(BuildContext context) {
    final state = _contentState;
    return Scaffold(
      backgroundColor: CineoColors.background,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: onRefresh ?? () async {},
          child: CustomScrollView(
            key: const PageStorageKey('cineo-home-scroll'),
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              _buildTopBar(context),
              if (isRefreshing)
                const SliverToBoxAdapter(
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              if (state != null)
                ContentStateView(
                  state: state,
                  message: errorMessage,
                  onRetry: onRetry,
                )
              else ...[
                SliverToBoxAdapter(
                  child: _HeroBanner(
                    media: continueWatching.isNotEmpty
                        ? continueWatching.first
                        : items.first,
                    resumeAvailable: continueWatching.isNotEmpty,
                    onTap: continueWatching.isNotEmpty
                        ? onContinueWatching ?? onOpenMedia
                        : onOpenMedia,
                  ),
                ),
                if (continueWatching.isNotEmpty)
                  MediaRail(
                    title: '继续观看',
                    items: continueWatching,
                    progressByMediaId: progressByMediaId,
                    onOpenMedia: onOpenMedia,
                  ),
                if (favorites.isNotEmpty)
                  MediaRail(
                    title: '我的收藏',
                    items: favorites,
                    onOpenMedia: onOpenMedia,
                  ),
                ..._fixedCategoryRails(),
                const SliverToBoxAdapter(child: SizedBox(height: 132)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  ContentState? get _contentState {
    if (isLoading && items.isEmpty) return ContentState.loading;
    if (errorMessage != null) return ContentState.error;
    if (items.isEmpty) return ContentState.empty;
    return null;
  }

  void _notifySeeAll(
    String title,
    List<MediaItem> initialItems,
    List<String> categoryIds,
  ) {
    onSeeAll?.call(title, initialItems, categoryIds);
  }

  SliverAppBar _buildTopBar(BuildContext context) {
    return SliverAppBar(
      pinned: false,
      toolbarHeight: 64,
      backgroundColor: CineoColors.background,
      surfaceTintColor: Colors.transparent,
      titleSpacing: 20,
      title: const CineoBrandMark(),
      actions: [
        IconButton(
          onPressed: onOpenSearch,
          tooltip: '搜索',
          icon: const Icon(Icons.search_rounded, size: 25),
        ),
        const SizedBox(width: 12),
      ],
    );
  }

  List<Widget> _fixedCategoryRails() {
    return categoryRails
        .where((rail) => rail.items.isNotEmpty)
        .map(
          (rail) => MediaRail(
            title: rail.title,
            items: rail.items,
            onOpenMedia: onOpenMedia,
            onSeeAll: onSeeAll == null
                ? null
                : () => _notifySeeAll(
                      rail.title,
                      rail.items,
                      _stableNonEmptyIds(rail.categoryIds),
                    ),
          ),
        )
        .toList(growable: false);
  }

  List<String> _stableNonEmptyIds(Iterable<String?> ids) {
    final seen = <String>{};
    final result = <String>[];
    for (final id in ids) {
      final value = id?.trim();
      if (value == null || value.isEmpty || !seen.add(value)) continue;
      result.add(value);
    }
    return List.unmodifiable(result);
  }
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({
    required this.media,
    required this.resumeAvailable,
    required this.onTap,
  });

  final MediaItem media;
  final bool resumeAvailable;
  final Future<void> Function(MediaItem) onTap;

  @override
  Widget build(BuildContext context) {
    final imageUrl =
        media.posterUrl.trim().isNotEmpty ? media.posterUrl : media.backdropUrl;
    return SizedBox(
      width: double.infinity,
      child: AspectRatio(
        key: ValueKey('home-hero-media-${media.id}'),
        aspectRatio: 3 / 4,
        child: Stack(
          fit: StackFit.expand,
          children: [
            MediaImage(
              url: imageUrl,
              alignment: Alignment.center,
              placeholderIcon: Icons.movie_outlined,
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    CineoColors.background.withOpacity(.04),
                    CineoColors.background.withOpacity(.28),
                    CineoColors.background.withOpacity(.96),
                  ],
                  stops: const [.05, .48, 1],
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FeaturedLabel(
                        label: resumeAvailable ? '继续观看' : '本周精选',
                      ),
                      const SizedBox(height: 10),
                      Text(
                        media.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w900,
                              height: 1.05,
                              color: Colors.white,
                            ),
                      ),
                      const SizedBox(height: 8),
                      _MetaLine(media: media),
                      const SizedBox(height: 10),
                      Text(
                        media.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withOpacity(.78),
                              height: 1.35,
                            ),
                      ),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        key: const ValueKey('home-hero-action'),
                        onPressed: () => onTap(media),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(resumeAvailable ? '继续观看' : '立即播放'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeaturedLabel extends StatelessWidget {
  const _FeaturedLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: CineoColors.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Colors.white.withOpacity(.85),
                fontWeight: FontWeight.w700,
                letterSpacing: .4,
              ),
        ),
      ],
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.media});

  final MediaItem media;

  @override
  Widget build(BuildContext context) {
    final duration = media.duration.inHours > 0
        ? '${media.duration.inHours}小时${media.duration.inMinutes.remainder(60)}分钟'
        : '${media.duration.inMinutes}分钟';
    return Wrap(
      spacing: 8,
      runSpacing: 5,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('${media.year}', style: _style),
        _Dot(),
        Text(media.kind == MediaKind.series ? '剧集' : '电影', style: _style),
        _Dot(),
        Text(duration, style: _style),
        _Dot(),
        Text('评分 ${media.rating.toStringAsFixed(1)}', style: _style),
      ],
    );
  }

  TextStyle get _style => const TextStyle(
        color: Colors.white,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      );
}

class _Dot extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Text('·', style: TextStyle(color: CineoColors.textSecondary));
  }
}
