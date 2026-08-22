import 'package:flutter/material.dart';

import '../../core/models/media.dart';
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
  final Future<List<MediaItem>> Function()? onLoad;

  @override
  State<CategoryBrowseScreen> createState() => _CategoryBrowseScreenState();
}

class _CategoryBrowseScreenState extends State<CategoryBrowseScreen> {
  late List<MediaItem> _items = widget.initialItems;
  Object? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.onLoad != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  Future<void> _load() async {
    final loader = widget.onLoad;
    if (loader == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await loader();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
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
                : BrowseMediaGrid(
                    items: _items,
                    onOpenMedia: widget.onOpenMedia,
                    emptyTitle: '这个分类还没有内容',
                    emptyMessage: '换一个分类，或稍后刷新试试',
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
