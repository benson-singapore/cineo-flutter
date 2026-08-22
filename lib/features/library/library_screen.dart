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
    this.onMediaTap,
  });

  final MediaRepository repository;
  final LibraryContentMode mode;
  final ValueChanged<MediaItem>? onMediaTap;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<MediaItem> _favorites = const [];
  List<_HistoryEntry> _history = const [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

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

      final savedProgress = await widget.repository.watchHistory();
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
                    )
                  : _HistoryList(entries: _history, onTap: widget.onMediaTap),
    );
  }
}

class _MediaGrid extends StatelessWidget {
  const _MediaGrid({
    required this.items,
    required this.emptyTitle,
    required this.emptyIcon,
    this.onTap,
  });

  final List<MediaItem> items;
  final String emptyTitle;
  final IconData emptyIcon;
  final ValueChanged<MediaItem>? onTap;

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
      ),
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.entries, this.onTap});

  final List<_HistoryEntry> entries;
  final ValueChanged<MediaItem>? onTap;

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
        );
      },
    );
  }
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({required this.media, this.onTap});

  final MediaItem media;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: MediaImage(url: media.posterUrl),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            media.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 3),
          Text(
            '${media.year}  ·  ${media.rating.toStringAsFixed(1)} 分',
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

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry, this.onTap});

  final _HistoryEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final progress = entry.progress.fraction;
    return Material(
      color: CineoColors.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
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
                  child: MediaImage(url: entry.media.posterUrl),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      entry.media.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _episodeSummary(entry.progress),
                      style: const TextStyle(
                        color: CineoColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _watchTimeSummary(entry.progress),
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
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: CineoColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
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
