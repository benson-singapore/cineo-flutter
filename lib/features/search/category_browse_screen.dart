import 'package:flutter/material.dart';

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
  });

  final String title;
  final List<MediaItem> initialItems;
  final ValueChanged<MediaItem> onOpenMedia;
  final Future<PagedMedia> Function(int page)? onLoad;

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

  @override
  void initState() {
    super.initState();
    _items = widget.initialItems;
    _scrollController.addListener(_onScroll);
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

  Future<void> _load() async {
    final loader = widget.onLoad;
    if (loader == null) return;
    final revision = ++_revision;
    setState(() {
      _loading = true;
      _error = null;
      _paginationError = null;
      // The remote first page is authoritative; homepage preview items must
      // not mask its loading or error state.
      _items = const [];
      _page = 0;
      _hasMore = false;
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
          _error = error;
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
                : CustomScrollView(
                    controller: _scrollController,
                    slivers: [
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
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                          sliver: SliverGrid(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) => BrowseMediaCard(
                                media: _items[index],
                                onTap: () => widget.onOpenMedia(_items[index]),
                              ),
                              childCount: _items.length,
                            ),
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 176,
                              mainAxisSpacing: 18,
                              crossAxisSpacing: 12,
                              childAspectRatio: .62,
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

class BrowseMediaGrid extends StatelessWidget {
  const BrowseMediaGrid({
    super.key,
    required this.items,
    required this.onOpenMedia,
    this.emptyTitle = '没有内容',
    this.emptyMessage = '暂时没有可展示的资源',
  });

  final List<MediaItem> items;
  final ValueChanged<MediaItem> onOpenMedia;
  final String emptyTitle;
  final String emptyMessage;

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
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 176,
        mainAxisSpacing: 18,
        crossAxisSpacing: 12,
        childAspectRatio: .62,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => BrowseMediaCard(
        media: items[index],
        onTap: () => onOpenMedia(items[index]),
      ),
    );
  }
}

class BrowseMediaCard extends StatelessWidget {
  const BrowseMediaCard({
    super.key,
    required this.media,
    required this.onTap,
  });

  final MediaItem media;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final kind = media.kind == MediaKind.series ? '剧集' : '电影';
    final metadata = [
      if (media.year > 0) media.year.toString(),
      kind,
      if (media.rating > 0) media.rating.toStringAsFixed(1),
    ].join(' · ');
    return Semantics(
      button: true,
      label: '打开 ${media.title}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: MediaImage(
                url: media.posterUrl,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              media.title,
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
