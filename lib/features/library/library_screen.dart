import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models/media.dart';
import '../../core/theme/cineo_theme.dart';
import '../../data/repositories/media_repository.dart';
import '../../shared/widgets/media_image.dart';

enum LibraryContentMode { favorites, history }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.repository,
    required this.mode,
    this.includeAdultHistory = true,
    this.onMediaTap,
    this.onSourceChanged,
  });

  final MediaRepository repository;
  final LibraryContentMode mode;
  final bool includeAdultHistory;
  final Future<void> Function(MediaItem)? onMediaTap;
  final Stream<void>?
      onSourceChanged; // Stream to trigger refresh when source changes

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<MediaItem> _favorites = const [];
  List<_HistoryEntry> _history = const [];
  bool _loading = true;
  Object? _error;
  StreamSubscription<void>? _sourceChangedSubscription;

  @override
  void initState() {
    super.initState();
    _load();
    // Listen for source changes and auto-refresh
    if (widget.onSourceChanged != null) {
      _sourceChangedSubscription = widget.onSourceChanged!.listen((_) {
        _load();
      });
    }
  }

  @override
  void dispose() {
    _sourceChangedSubscription?.cancel();
    super.dispose();
  }

  /// Public method to refresh library data (called from parent when source changes)
  Future<void> refreshLibraryData() => _load();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (widget.mode == LibraryContentMode.favorites) {
        final favorites = await widget.repository.favorites();
        if (!mounted) return;
        setState(() {
          _favorites = favorites;
          _history = const [];
          _loading = false;
        });
        return;
      }

      final savedProgress = await widget.repository.watchHistory(
        includeAdult: widget.includeAdultHistory,
      );
      // Each episode keeps its own resume position locally. The history view
      // presents only the most recently watched episode for each title.
      final progressByMediaId = <String, WatchProgress>{};
      for (final entry in savedProgress) {
        progressByMediaId.putIfAbsent(entry.mediaId, () => entry);
      }
      final progress = progressByMediaId.values.toList(growable: false);
      final media = <String, MediaItem>{};
      for (final item in await Future.wait(
        progress.map((entry) => widget.repository.getById(entry.mediaId)),
      )) {
        if (item != null) media[item.id] = item;
      }
      final entries = await Future.wait(
        [
          for (final entry in progress)
            if (media[entry.mediaId] != null)
              _resolveHistoryEntry(
                _HistoryEntry(
                  media: media[entry.mediaId]!,
                  progress: entry,
                ),
              ),
        ],
      );
      if (!mounted) return;
      setState(() {
        _favorites = const [];
        _history = entries;
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

  Future<void> _removeHistory(String mediaId) async {
    await widget.repository.removeHistory(mediaId);
    await _load();
  }

  Future<void> _removeFavorite(MediaItem media) async {
    try {
      await widget.repository.setFavorite(media, false);
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('取消收藏失败，请稍后重试')),
      );
    }
  }

  Future<void> _clearHistory() async {
    if (_history.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空播放历史？'),
        content: const Text('将删除所有本地播放进度，此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.repository.clearHistory();
    await _load();
  }

  Future<_HistoryEntry> _resolveHistoryEntry(_HistoryEntry entry) async {
    final progress = entry.progress;
    if (progress.episodeId == null ||
        (progress.episodeNumber != null && progress.episodeCount != null)) {
      return entry;
    }

    MediaItem media = entry.media;
    PlaybackOption? matchedOption;
    List<PlaybackOption> lineEpisodes = const [];
    try {
      final details = await widget.repository.loadDetails(entry.media);
      if (details != null) {
        media = details;
        matchedOption = details.playbackOptions
            .where((option) => option.id == progress.episodeId)
            .firstOrNull;
        if (matchedOption != null) {
          lineEpisodes = details.playbackOptions
              .where((option) => option.quality == matchedOption!.quality)
              .toList(growable: false);
        }
      }
    } catch (_) {
      // Offline history should remain useful even when the source is down.
    }

    final episodeNumber = matchedOption == null
        ? _episodeNumberFromLegacyId(progress.episodeId)
        : lineEpisodes.indexWhere((option) => option.id == matchedOption!.id) +
            1;
    final episodeCount = lineEpisodes.isEmpty ? null : lineEpisodes.length;
    final episodeLabel = matchedOption == null
        ? progress.episodeLabel
        : _episodeLabel(matchedOption);
    final resolvedProgress = WatchProgress(
      mediaId: progress.mediaId,
      episodeId: progress.episodeId,
      episodeLabel: episodeLabel,
      episodeNumber: episodeNumber ?? progress.episodeNumber,
      episodeCount: episodeCount ?? progress.episodeCount,
      position: progress.position,
      duration: progress.duration,
      updatedAt: progress.updatedAt,
    );
    if (resolvedProgress.episodeNumber != progress.episodeNumber ||
        resolvedProgress.episodeCount != progress.episodeCount ||
        resolvedProgress.episodeLabel != progress.episodeLabel) {
      try {
        await widget.repository.saveProgress(resolvedProgress, media: media);
      } catch (_) {
        // The display update is still valid when a local write fails.
      }
    }
    return _HistoryEntry(media: media, progress: resolvedProgress);
  }

  int? _episodeNumberFromLegacyId(String? episodeId) {
    final match = RegExp(r':(\d+)$').firstMatch(episodeId ?? '');
    final index = int.tryParse(match?.group(1) ?? '');
    return index == null ? null : index + 1;
  }

  String _episodeLabel(PlaybackOption option) {
    final match = RegExp(r'第\s*(\d+)\s*集').firstMatch(option.label);
    final number = int.tryParse(match?.group(1) ?? '');
    return number == null ? option.label : '第$number集';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.mode == LibraryContentMode.favorites ? '我的收藏' : '播放历史',
        ),
        actions: [
          if (widget.mode == LibraryContentMode.history && _history.isNotEmpty)
            IconButton(
              tooltip: '清空播放历史',
              onPressed: _clearHistory,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
          IconButton(
            tooltip: '刷新',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(message: '本地数据加载失败', onRetry: _load)
              : widget.mode == LibraryContentMode.favorites
                  ? _MediaGrid(
                      items: _favorites,
                      emptyTitle: '还没有收藏内容',
                      emptyIcon: Icons.bookmark_border,
                      onTap: widget.onMediaTap,
                      onRemove: _removeFavorite,
                    )
                  : _HistoryList(
                      entries: _history,
                      onTap: widget.onMediaTap,
                      onDelete: _removeHistory,
                    ),
    );
  }
}

class _MediaGrid extends StatelessWidget {
  const _MediaGrid({
    required this.items,
    required this.emptyTitle,
    required this.emptyIcon,
    this.onTap,
    this.onRemove,
  });

  final List<MediaItem> items;
  final String emptyTitle;
  final IconData emptyIcon;
  final Future<void> Function(MediaItem)? onTap;
  final ValueChanged<MediaItem>? onRemove;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return _EmptyState(title: emptyTitle, icon: emptyIcon);
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 172,
        mainAxisSpacing: 20,
        crossAxisSpacing: 12,
        childAspectRatio: .61,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => _MediaTile(
        media: items[index],
        onTap: onTap == null ? null : () => onTap!(items[index]),
        onRemove: onRemove == null ? null : () => onRemove!(items[index]),
      ),
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList(
      {required this.entries, this.onTap, required this.onDelete});

  final List<_HistoryEntry> entries;
  final Future<void> Function(MediaItem)? onTap;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const _EmptyState(title: '还没有播放记录', icon: Icons.history);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return _HistoryTile(
          entry: entry,
          onTap: onTap == null ? null : () => onTap!(entry.media),
          onDelete: () => onDelete(entry.media.id),
        );
      },
    );
  }
}

class _MediaTile extends StatefulWidget {
  const _MediaTile({required this.media, this.onTap, this.onRemove});

  final MediaItem media;
  final Future<void> Function()? onTap;
  final VoidCallback? onRemove;

  @override
  State<_MediaTile> createState() => _MediaTileState();
}

class _MediaTileState extends State<_MediaTile> {
  var _opening = false;

  Future<void> _open() async {
    if (_opening || widget.onTap == null) return;
    setState(() => _opening = true);
    try {
      await widget.onTap!();
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _opening || widget.onTap == null ? null : _open,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: MediaImage(url: widget.media.posterUrl),
                ),
                if (_opening)
                  DecoratedBox(
                    key: ValueKey('library-card-loading-${widget.media.id}'),
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
                if (widget.onRemove != null)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Material(
                      color: Colors.black.withOpacity(.68),
                      shape: const CircleBorder(),
                      child: IconButton(
                        tooltip: '取消收藏',
                        onPressed: widget.onRemove,
                        constraints: const BoxConstraints.tightFor(
                          width: 36,
                          height: 36,
                        ),
                        padding: EdgeInsets.zero,
                        iconSize: 20,
                        color: Colors.white,
                        icon: const Icon(Icons.favorite_rounded),
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
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 3),
          Text(
            '${widget.media.year}  ·  ${widget.media.rating.toStringAsFixed(1)} 分',
            style: const TextStyle(
              color: CineoColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatefulWidget {
  const _HistoryTile({required this.entry, this.onTap, required this.onDelete});

  final _HistoryEntry entry;
  final Future<void> Function()? onTap;
  final VoidCallback onDelete;

  @override
  State<_HistoryTile> createState() => _HistoryTileState();
}

class _HistoryTileState extends State<_HistoryTile> {
  var _opening = false;

  Future<void> _open() async {
    if (_opening || widget.onTap == null) return;
    setState(() => _opening = true);
    try {
      await widget.onTap!();
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.entry.progress.fraction;
    return Stack(
      children: [
        Material(
          color: CineoColors.surface,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: _opening || widget.onTap == null ? null : _open,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  SizedBox(
                    width: 68,
                    height: 94,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: MediaImage(url: widget.entry.media.posterUrl),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.entry.media.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _episodeSummary(widget.entry.progress),
                          style: const TextStyle(
                            color: CineoColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _watchTimeSummary(widget.entry.progress),
                          style: const TextStyle(
                            color: CineoColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(value: progress, minHeight: 4),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '删除此记录',
                    onPressed: widget.onDelete,
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_opening)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                key: ValueKey('history-card-loading-${widget.entry.media.id}'),
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
            ),
          ),
      ],
    );
  }

  String _episodeSummary(WatchProgress progress) {
    if (progress.episodeId == null) return '电影';
    final number = progress.episodeNumber;
    final count = progress.episodeCount;
    if (number != null && count != null) return '共 $count 集 · 当前第 $number 集';
    if (number != null) return '当前第 $number 集';
    if (progress.episodeLabel != null && progress.episodeLabel!.isNotEmpty) {
      return progress.episodeLabel!;
    }
    return '已观看剧集';
  }

  String _watchTimeSummary(WatchProgress progress) {
    final percentage = (progress.fraction * 100).round();
    return '已播 ${_formatDuration(progress.position)} / '
        '${_formatDuration(progress.duration)} · $percentage%';
  }

  String _formatDuration(Duration duration) {
    final seconds = duration.inSeconds.clamp(0, 359999);
    final hours = seconds ~/ Duration.secondsPerHour;
    final minutes =
        (seconds % Duration.secondsPerHour) ~/ Duration.secondsPerMinute;
    final remainder = seconds % Duration.secondsPerMinute;
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return hours == 0
        ? '${twoDigits(minutes)}:${twoDigits(remainder)}'
        : '${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(remainder)}';
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: CineoColors.textSecondary),
          const SizedBox(height: 14),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: CineoColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }
}

class _HistoryEntry {
  const _HistoryEntry({required this.media, required this.progress});

  final MediaItem media;
  final WatchProgress progress;
}
