import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/models/media.dart';
import '../../core/models/paged_media.dart';
import '../../core/theme/cineo_theme.dart';
import '../../shared/widgets/media_image.dart';

/// A standalone full-library view that can be opened from a home rail.
class CategoryBrowseScreen extends StatefulWidget {
  const CategoryBrowseScreen({
    super.key,
    required this.title,
    required this.initialItems,
    required this.onOpenMedia,
    this.onLoad,
    this.imageAspectRatio,
  });

  final String title;
  final List<MediaItem> initialItems;
  final Future<void> Function(MediaItem) onOpenMedia;
  final Future<PagedMedia> Function(int page)? onLoad;
  final double? imageAspectRatio;

  @override
  State<CategoryBrowseScreen> createState() => _CategoryBrowseScreenState();
}

class _CategoryBrowseScreenState extends State<CategoryBrowseScreen> {
  final _scrollController = ScrollController();
  List<MediaItem> _items = const [];
  Object? _error;
  Object? _paginationError;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 0;
  int _revision = 0;
  bool _showScrollToTop = false;

  @override
  void initState() {
    super.initState();
    _items = widget.initialItems;
    _scrollController
      ..addListener(_onScroll)
      ..addListener(_updateScrollToTopVisibility);
    if (widget.onLoad != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients ||
        _scrollController.position.extentAfter > 360 ||
        _loadingMore ||
        _loading ||
        !_hasMore) {
      return;
    }
    _loadPage(_page + 1, revision: _revision);
  }

  void _updateScrollToTopVisibility() {
    if (!_scrollController.hasClients) return;
    final shouldShow = _scrollController.offset > 360;
    if (shouldShow != _showScrollToTop && mounted) {
      setState(() => _showScrollToTop = shouldShow);
    }
  }

  Future<void> _scrollToTop() async {
    if (!_scrollController.hasClients || _scrollController.offset <= 0) {
      return;
    }
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _load({bool preserveItems = false}) async {
    final loader = widget.onLoad;
    if (loader == null) return;
    final revision = ++_revision;
    setState(() {
      _loading = true;
      _error = null;
      _paginationError = null;
      if (!preserveItems) {
        // The remote first page is authoritative; homepage preview items must
        // not mask its initial loading or error state.
        _items = const [];
        _page = 0;
        _hasMore = false;
      }
    });
    await _loadPage(1, revision: revision);
  }

  Future<void> _loadPage(int page, {required int revision}) async {
    final loader = widget.onLoad;
    if (loader == null || revision != _revision) return;
    if (page > 1) {
      if (_loadingMore || !_hasMore) return;
      setState(() {
        _loadingMore = true;
        _paginationError = null;
      });
    }
    try {
      final result = await loader(page);
      if (!mounted || revision != _revision) return;
      setState(() {
        _items = page == 1
            ? _appendUnique(const [], result.items)
            : _appendUnique(_items, result.items);
        _page = result.page;
        _hasMore = result.hasMore;
        _loading = false;
        _loadingMore = false;
        _paginationError = null;
      });
    } catch (error) {
      if (!mounted || revision != _revision) return;
      setState(() {
        if (page == 1) {
          if (_items.isEmpty) _error = error;
          _loading = false;
        } else {
          _paginationError = error;
          _loadingMore = false;
        }
      });
    }
  }

  List<MediaItem> _appendUnique(List<MediaItem> current, List<MediaItem> next) {
    final seen = current.map((item) => item.id).toSet();
    return [...current, ...next.where((item) => seen.add(item.id))];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: CineoColors.background,
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (widget.onLoad != null)
            IconButton(
              onPressed: _loading ? null : _load,
              tooltip: '刷新',
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _loading && _items.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : _error != null && _items.isEmpty
                ? _BrowseError(onRetry: _load)
                : RefreshIndicator(
                    onRefresh: () => _load(preserveItems: true),
                    child: CustomScrollView(
                      key: const PageStorageKey('cineo-category-browse-scroll'),
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      slivers: [
                        if (_loading && _items.isNotEmpty)
                          const SliverToBoxAdapter(
                            child: LinearProgressIndicator(minHeight: 2),
                          ),
                        if (_items.isEmpty)
                          const SliverFillRemaining(
                            hasScrollBody: false,
                            child: _BrowseEmpty(
                              icon: Icons.video_library_outlined,
                              title: '这个分类还没有内容',
                              message: '稍后刷新试试',
                            ),
                          )
                        else
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 88),
                            sliver: SliverGrid(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) => BrowseMediaCard(
                                  media: _items[index],
                                  onTap: () =>
                                      widget.onOpenMedia(_items[index]),
                                  imageAspectRatio:
                                      widget.imageAspectRatio ?? .69,
                                ),
                                childCount: _items.length,
                              ),
                              gridDelegate: widget.imageAspectRatio == null
                                  ? const SliverGridDelegateWithMaxCrossAxisExtent(
                                      maxCrossAxisExtent: 176,
                                      mainAxisSpacing: 18,
                                      crossAxisSpacing: 12,
                                      childAspectRatio: .62,
                                    )
                                  : BrowseMediaGridDelegate(
                                      imageAspectRatio:
                                          widget.imageAspectRatio!,
                                    ),
                            ),
                          ),
                        if (_loadingMore || _paginationError != null)
                          SliverToBoxAdapter(
                            child: _CategoryPaginationFooter(
                              loading: _loadingMore,
                              onRetry: () =>
                                  _loadPage(_page + 1, revision: _revision),
                            ),
                          ),
                      ],
                    ),
                  ),
      ),
      floatingActionButton: _showScrollToTop
          ? FloatingActionButton.small(
              onPressed: _scrollToTop,
              tooltip: '回到顶部',
              child: const Icon(Icons.keyboard_arrow_up_rounded),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

class _CategoryPaginationFooter extends StatelessWidget {
  const _CategoryPaginationFooter({
    required this.loading,
    required this.onRetry,
  });

  final bool loading;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      child: Center(
        child: OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('下一页加载失败，重试'),
        ),
      ),
    );
  }
}

class BrowseMediaGridDelegate extends SliverGridDelegate {
  const BrowseMediaGridDelegate({required this.imageAspectRatio});

  final double imageAspectRatio;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    const maxCrossAxisExtent = 176.0;
    const crossAxisSpacing = 12.0;
    const mainAxisSpacing = 18.0;
    final crossAxisCount = ((constraints.crossAxisExtent + crossAxisSpacing) /
            (maxCrossAxisExtent + crossAxisSpacing))
        .ceil()
        .clamp(1, 100);
    final tileWidth = (constraints.crossAxisExtent -
            crossAxisSpacing * (crossAxisCount - 1)) /
        crossAxisCount;
    final imageHeight = tileWidth / imageAspectRatio;
    final tileHeight = imageHeight + 8 + 20 + 3 + 18;
    return SliverGridRegularTileLayout(
      crossAxisCount: crossAxisCount,
      mainAxisStride: tileHeight + mainAxisSpacing,
      crossAxisStride: tileWidth + crossAxisSpacing,
      childMainAxisExtent: tileHeight,
      childCrossAxisExtent: tileWidth,
      reverseCrossAxis: axisDirectionIsReversed(constraints.crossAxisDirection),
    );
  }

  @override
  bool shouldRelayout(covariant BrowseMediaGridDelegate oldDelegate) {
    return oldDelegate.imageAspectRatio != imageAspectRatio;
  }
}

class BrowseMediaGrid extends StatelessWidget {
  const BrowseMediaGrid({
    super.key,
    required this.items,
    required this.onOpenMedia,
    this.emptyTitle = '没有内容',
    this.emptyMessage = '暂时没有可展示的资源',
    this.imageAspectRatio,
  });

  final List<MediaItem> items;
  final Future<void> Function(MediaItem) onOpenMedia;
  final String emptyTitle;
  final String emptyMessage;
  final double? imageAspectRatio;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return _BrowseEmpty(
        icon: Icons.video_library_outlined,
        title: emptyTitle,
        message: emptyMessage,
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      gridDelegate: imageAspectRatio == null
          ? const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 176,
              mainAxisSpacing: 18,
              crossAxisSpacing: 12,
              childAspectRatio: .62,
            )
          : BrowseMediaGridDelegate(imageAspectRatio: imageAspectRatio!),
      itemCount: items.length,
      itemBuilder: (context, index) => BrowseMediaCard(
        media: items[index],
        onTap: () => onOpenMedia(items[index]),
        imageAspectRatio: imageAspectRatio ?? .69,
      ),
    );
  }
}

class BrowseMediaCard extends StatefulWidget {
  const BrowseMediaCard({
    super.key,
    required this.media,
    required this.onTap,
    this.imageAspectRatio = .69,
  });

  final MediaItem media;
  final Future<void> Function() onTap;
  final double imageAspectRatio;

  @override
  State<BrowseMediaCard> createState() => _BrowseMediaCardState();
}

class _BrowseMediaCardState extends State<BrowseMediaCard> {
  var _opening = false;

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await widget.onTap();
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.media.kind == MediaKind.series ? '剧集' : '电影';
    final metadata = [
      if (widget.media.year > 0) widget.media.year.toString(),
      kind,
      if (widget.media.rating > 0) widget.media.rating.toStringAsFixed(1),
    ].join(' · ');
    return Semantics(
      button: true,
      enabled: !_opening,
      label: '打开 ${widget.media.title}',
      child: InkWell(
        onTap: _opening ? null : _open,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MediaImage(
                    url: widget.media.posterUrl,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  if (_opening)
                    DecoratedBox(
                      key: ValueKey('browse-card-loading-${widget.media.id}'),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(.56),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.media.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 3),
            Text(
              metadata,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: CineoColors.textSecondary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrowseEmpty extends StatelessWidget {
  const _BrowseEmpty({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 46, color: CineoColors.textSecondary),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: CineoColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrowseError extends StatelessWidget {
  const _BrowseError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 44, color: CineoColors.textSecondary),
            const SizedBox(height: 12),
            const Text('资源加载失败，请稍后重试'),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
