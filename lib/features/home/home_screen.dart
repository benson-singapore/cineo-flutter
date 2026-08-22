import 'package:flutter/material.dart';

import '../../core/models/media.dart';
import '../../core/theme/cineo_theme.dart';
import '../../data/remote/media_category_adapter.dart';
import '../../shared/widgets/content_state_view.dart';
import '../../shared/widgets/media_image.dart';
import '../../shared/widgets/media_rail.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.items,
    required this.continueWatching,
    required this.onOpenMedia,
    this.isLoading = false,
    this.errorMessage,
    this.onRetry,
    this.progressByMediaId = const {},
    this.categories = const [],
    this.selectedCategory = UnifiedMediaType.all,
    this.onCategorySelected,
  });

  final List<MediaItem> items;
  final List<MediaItem> continueWatching;
  final ValueChanged<MediaItem> onOpenMedia;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final Map<String, double> progressByMediaId;
  final List<UnifiedCategory> categories;
  final UnifiedMediaType selectedCategory;
  final ValueChanged<UnifiedCategory>? onCategorySelected;

  @override
  Widget build(BuildContext context) {
    final state = _contentState;
    return Scaffold(
      backgroundColor: CineoColors.background,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            _buildTopBar(context),
            if (state != null)
              ContentStateView(
                state: state,
                message: errorMessage,
                onRetry: onRetry,
              )
            else ...[
              SliverToBoxAdapter(
                  child: _HeroBanner(media: items.first, onTap: onOpenMedia)),
              if (categories.length > 1)
                SliverToBoxAdapter(
                  child: _CategoryStrip(
                    categories: categories,
                    selected: selectedCategory,
                    onSelected: onCategorySelected,
                  ),
                ),
              if (continueWatching.isNotEmpty)
                MediaRail(
                  title: '继续观看',
                  items: continueWatching,
                  progressByMediaId: progressByMediaId,
                  onOpenMedia: onOpenMedia,
                ),
              MediaRail(
                title: '为你推荐',
                items: items,
                onOpenMedia: onOpenMedia,
                showDescription: true,
              ),
              ..._categoryRails(),
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ],
        ),
      ),
    );
  }

  ContentState? get _contentState {
    if (isLoading) return ContentState.loading;
    if (errorMessage != null) return ContentState.error;
    if (items.isEmpty) return ContentState.empty;
    return null;
  }

  SliverAppBar _buildTopBar(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      toolbarHeight: 64,
      backgroundColor: CineoColors.background,
      surfaceTintColor: Colors.transparent,
      titleSpacing: 20,
      title: const _CineoWordmark(),
      actions: [
        IconButton(
          onPressed: () {},
          tooltip: '搜索',
          icon: const Icon(Icons.search_rounded),
        ),
        IconButton(
          onPressed: () {},
          tooltip: '通知',
          icon: const Icon(Icons.notifications_none_rounded),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  List<Widget> _categoryRails() {
    final seen = <String>{};
    final rails = <Widget>[];
    for (final media in items) {
      for (final genre in media.genres) {
        if (genre.isEmpty || seen.contains(genre)) continue;
        seen.add(genre);
        final categoryItems = items
            .where((item) => item.genres.contains(genre))
            .toList(growable: false);
        rails.add(
          MediaRail(
            title: genre,
            items: categoryItems,
            onOpenMedia: onOpenMedia,
          ),
        );
        if (rails.length == 3) return rails;
      }
    }
    return rails;
  }
}

class _CategoryStrip extends StatelessWidget {
  const _CategoryStrip({
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  final List<UnifiedCategory> categories;
  final UnifiedMediaType selected;
  final ValueChanged<UnifiedCategory>? onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, index) {
          final category = categories[index];
          final isSelected = category.type == selected;
          return ChoiceChip(
            label: Text(category.type.label),
            selected: isSelected,
            onSelected: (_) => onSelected?.call(category),
          );
        },
      ),
    );
  }
}

class _CineoWordmark extends StatelessWidget {
  const _CineoWordmark();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 25,
          height: 25,
          decoration: BoxDecoration(
            color: CineoColors.primary,
            borderRadius: BorderRadius.circular(7),
          ),
          child: const Icon(Icons.play_arrow_rounded, size: 18),
        ),
        const SizedBox(width: 9),
        const Text(
          'CINEO',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
          ),
        ),
      ],
    );
  }
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({required this.media, required this.onTap});

  final MediaItem media;
  final ValueChanged<MediaItem> onTap;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final height = width < 600 ? 430.0 : 490.0;
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          MediaImage(
            url: media.backdropUrl,
            alignment: Alignment.center,
            placeholderIcon: Icons.landscape_outlined,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  CineoColors.background.withOpacity(.08),
                  CineoColors.background.withOpacity(.2),
                  CineoColors.background,
                ],
                stops: const [.05, .48, 1],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _FeaturedLabel(),
                    const SizedBox(height: 12),
                    Text(
                      media.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            height: 1.02,
                            color: Colors.white,
                          ),
                    ),
                    const SizedBox(height: 10),
                    _MetaLine(media: media),
                    const SizedBox(height: 12),
                    Text(
                      media.description,
                      maxLines: width < 600 ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withOpacity(.78),
                            height: 1.45,
                          ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: () => onTap(media),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('立即播放'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        backgroundColor: CineoColors.primary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturedLabel extends StatelessWidget {
  const _FeaturedLabel();

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
          '本周精选',
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
