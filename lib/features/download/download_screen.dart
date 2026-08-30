import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models/download_models.dart';
import '../../core/models/media.dart';
import '../../core/models/tmdb_media.dart';
import '../../data/repositories/media_repository.dart';
import '../../data/repositories/tmdb_metadata_repository.dart';
import '../../core/theme/cineo_theme.dart';
import '../../data/download/download_service.dart';
import '../../shared/widgets/media_image.dart';
import '../player/player_screen.dart';
import '../settings/m3u8_filter_settings.dart';

Future<void> showDownloadSheet({
  required BuildContext context,
  required DownloadService service,
  required MediaItem media,
  required List<Episode> episodes,
  M3u8FilterConfig? m3u8FilterConfig,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: CineoColors.surface,
    builder: (_) => DownloadTaskSheet(
      service: service,
      media: media,
      episodes: episodes,
      m3u8FilterConfig: m3u8FilterConfig,
    ),
  );
}

class DownloadTaskSheet extends StatefulWidget {
  const DownloadTaskSheet({
    super.key,
    required this.service,
    required this.media,
    required this.episodes,
    this.m3u8FilterConfig,
  });

  final DownloadService service;
  final MediaItem media;
  final List<Episode> episodes;
  final M3u8FilterConfig? m3u8FilterConfig;

  @override
  State<DownloadTaskSheet> createState() => _DownloadTaskSheetState();
}

class _DownloadTaskSheetState extends State<DownloadTaskSheet> {
  late final StreamSubscription<List<DownloadTask>> _subscription;
  List<DownloadTask> _tasks = const [];

  @override
  void initState() {
    super.initState();
    _tasks = _mediaTasks;
    _subscription = widget.service.changes.listen((tasks) {
      if (mounted) setState(() => _tasks = _mediaTasksFrom(tasks));
    });
  }

  List<DownloadTask> get _mediaTasks => _mediaTasksFrom(widget.service.tasks);

  List<DownloadTask> _mediaTasksFrom(Iterable<DownloadTask> tasks) {
    return tasks.where((task) => task.mediaId == widget.media.id).toList()
      ..sort((a, b) => (a.episodeNumber ?? 0).compareTo(b.episodeNumber ?? 0));
  }

  bool _isHls(PlaybackOption option) =>
      option.isHls || option.url.toLowerCase().contains('.m3u8');

  String _downloadUrl(PlaybackOption option) => playbackUrlForOption(
        option,
        widget.m3u8FilterConfig,
      );

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMovie = widget.media.kind == MediaKind.movie;
    final availableEpisodes = widget.episodes
        .where((episode) =>
            episode.playbackOption != null && _isHls(episode.playbackOption!))
        .toList(growable: false);
    final hasDownloadableContent = isMovie
        ? widget.media.playbackOptions.any(_isHls)
        : availableEpisodes.isNotEmpty;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 620),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '缓存下载',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                isMovie ? widget.media.title : '${widget.media.title} · 当前季',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: CineoColors.textSecondary),
              ),
              const SizedBox(height: 14),
              if (hasDownloadableContent && !isMovie)
                Row(
                  children: [
                    Text('${availableEpisodes.length} 集可缓存',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    FilledButton.tonalIcon(
                      onPressed: () => _enqueueEpisodes(availableEpisodes),
                      icon: const Icon(Icons.playlist_add_rounded, size: 18),
                      label: const Text('全部加入'),
                    ),
                  ],
                ),
              if (isMovie && hasDownloadableContent)
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonalIcon(
                    onPressed: () => _enqueueMovie(),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('加入下载'),
                  ),
                ),
              if (!hasDownloadableContent)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: Text('当前视频没有可下载的 HLS 地址')),
                )
              else ...[
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.separated(
                    itemCount: isMovie ? 1 : availableEpisodes.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final episode = isMovie ? null : availableEpisodes[index];
                      final task = _taskFor(episode);
                      return _DownloadTaskTile(
                        title: episode == null
                            ? widget.media.title
                            : '第 ${episode.number} 集${episode.title.isEmpty ? '' : ' · ${episode.title}'}',
                        task: task,
                        onDownload: task == null
                            ? () => episode == null
                                ? _enqueueMovie()
                                : _enqueueEpisode(episode)
                            : null,
                        onPause: task == null
                            ? null
                            : () => widget.service.pause(task.id),
                        onResume: task == null
                            ? null
                            : () => widget.service.resume(task.id),
                        onRetry: task == null
                            ? null
                            : () => widget.service.retry(task.id),
                        onCancel: task == null
                            ? null
                            : () => widget.service.cancel(task.id),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  DownloadTask? _taskFor(Episode? episode) {
    if (episode == null) {
      return _tasks.where((task) => task.episodeId == null).firstOrNull;
    }
    return _tasks.where((task) => task.episodeId == episode.id).firstOrNull;
  }

  Future<void> _enqueueMovie() async {
    final option = widget.media.playbackOptions.where(_isHls).firstOrNull;
    if (option == null) return;
    await widget.service.enqueue(DownloadRequest(
      mediaId: widget.media.id,
      sourceUrl: _downloadUrl(option),
      title: widget.media.title,
      seasonNumber:
          widget.episodes.isEmpty ? null : widget.episodes.first.season,
      posterUrl: widget.media.posterUrl,
      backdropUrl: widget.media.backdropUrl,
    ));
  }

  Future<void> _enqueueEpisode(Episode episode) async {
    final option = episode.playbackOption;
    if (option == null || !_isHls(option)) return;
    await widget.service.enqueue(DownloadRequest(
      mediaId: widget.media.id,
      sourceUrl: _downloadUrl(option),
      title: widget.media.title,
      episodeId: episode.id,
      seasonNumber: episode.season,
      episodeNumber: episode.number,
      episodeLabel: episode.title,
      posterUrl: widget.media.posterUrl,
      backdropUrl: widget.media.backdropUrl,
    ));
  }

  Future<void> _enqueueEpisodes(Iterable<Episode> episodes) async {
    await widget.service.enqueueAll(episodes.map((episode) {
      final option = episode.playbackOption!;
      return DownloadRequest(
        mediaId: widget.media.id,
        sourceUrl: _downloadUrl(option),
        title: widget.media.title,
        episodeId: episode.id,
        seasonNumber: episode.season,
        episodeNumber: episode.number,
        episodeLabel: episode.title,
        posterUrl: widget.media.posterUrl,
        backdropUrl: widget.media.backdropUrl,
      );
    }));
  }
}

class _DownloadTaskTile extends StatelessWidget {
  const _DownloadTaskTile({
    required this.title,
    required this.task,
    this.onDownload,
    this.onPause,
    this.onResume,
    this.onRetry,
    this.onCancel,
  });

  final String title;
  final DownloadTask? task;
  final VoidCallback? onDownload;
  final Future<void> Function()? onPause;
  final Future<void> Function()? onResume;
  final Future<void> Function()? onRetry;
  final Future<void> Function()? onCancel;

  @override
  Widget build(BuildContext context) {
    final current = task;
    final status = current?.status;
    final statusText = switch (status) {
      DownloadTaskStatus.queued => '等待中',
      DownloadTaskStatus.downloading => '下载中',
      DownloadTaskStatus.paused => '已暂停',
      DownloadTaskStatus.completed => '已完成',
      DownloadTaskStatus.failed => _failureLabel(current?.errorMessage),
      DownloadTaskStatus.cancelled => '已取消',
      null => '未加入',
    };
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: current == null
          ? Text(statusText,
              style: const TextStyle(color: CineoColors.textSecondary))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(statusText,
                    maxLines: status == DownloadTaskStatus.failed ? 3 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: CineoColors.textSecondary)),
                if (current.downloadedBytes > 0 || current.totalBytes > 0) ...[
                  const SizedBox(height: 3),
                  Text(
                    formatDownloadSizeProgress(current),
                    style: const TextStyle(
                      color: CineoColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                LinearProgressIndicator(value: current.progress),
              ],
            ),
      trailing: _action(context, status),
    );
  }

  String _failureLabel(String? error) {
    if (error == null || error.isEmpty) return '下载失败';
    if (error.contains('HTTP 401') || error.contains('HTTP 403')) {
      return '服务器拒绝了片段请求，请重试或更换线路';
    }
    if (error.contains('HTTP 404')) return '片段地址不存在，请重试或更换线路';
    if (error.contains('HTTP 5')) return '视频服务器暂时不可用，请稍后重试';
    if (error.contains('Empty HLS segment')) return '服务器返回了空片段';
    if (error.contains('Segment response truncated')) {
      return '片段传输不完整，请重试或更换线路';
    }
    if (error.contains('Playlist request failed')) {
      return '视频清单请求失败，请重试或更换线路';
    }
    if (error.contains('Live or incomplete playlists are unsupported')) {
      return '当前视频是直播或不完整清单，暂不支持缓存';
    }
    if (error.contains('HttpException') ||
        error.contains('Segment download failed') ||
        error.contains('片段下载失败')) {
      return '片段下载失败，请重试或更换线路';
    }
    return '下载失败，请重试或更换线路';
  }

  Widget _action(BuildContext context, DownloadTaskStatus? status) {
    if (onDownload != null) {
      return IconButton(
        tooltip: '加入下载',
        onPressed: onDownload,
        icon: const Icon(Icons.download_rounded),
      );
    }
    if (status == DownloadTaskStatus.downloading ||
        status == DownloadTaskStatus.queued) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: '暂停',
          onPressed: onPause == null ? null : () => unawaited(onPause!()),
          icon: const Icon(Icons.pause_rounded),
        ),
        IconButton(
          tooltip: '取消',
          onPressed: onCancel == null ? null : () => unawaited(onCancel!()),
          icon: const Icon(Icons.close_rounded),
        ),
      ]);
    }
    if (status == DownloadTaskStatus.paused) {
      return IconButton(
        tooltip: '继续',
        onPressed: onResume == null ? null : () => unawaited(onResume!()),
        icon: const Icon(Icons.play_arrow_rounded),
      );
    }
    if (status == DownloadTaskStatus.failed ||
        status == DownloadTaskStatus.cancelled) {
      return IconButton(
        tooltip: '重试',
        onPressed: onRetry == null ? null : () => unawaited(onRetry!()),
        icon: const Icon(Icons.refresh_rounded),
      );
    }
    return const Icon(Icons.check_circle_rounded, color: Color(0xFF35B885));
  }
}

class DownloadManagerScreen extends StatefulWidget {
  const DownloadManagerScreen({
    super.key,
    required this.service,
    this.repository,
    this.tmdbMetadata,
    this.onPlayTask,
  });

  final DownloadService service;
  final MediaRepository? repository;
  final TmdbMetadataRepository? tmdbMetadata;
  final Future<void> Function(DownloadTask task)? onPlayTask;

  @override
  State<DownloadManagerScreen> createState() => _DownloadManagerScreenState();
}

class _DownloadManagerScreenState extends State<DownloadManagerScreen> {
  late final StreamSubscription<List<DownloadTask>> _subscription;
  List<DownloadTask> _tasks = const [];
  DownloadCacheStats? _stats;
  Map<String, DownloadPresentation> _presentations = const {};
  int _presentationRevision = 0;

  @override
  void initState() {
    super.initState();
    _tasks = widget.service.tasks;
    _subscription = widget.service.changes.listen((tasks) {
      if (mounted) {
        setState(() => _tasks = tasks);
        _loadStats();
        _loadPresentations(tasks);
      }
    });
    _loadStats();
    _loadPresentations(_tasks);
  }

  Future<void> _loadStats() async {
    final stats = await widget.service.cacheStats();
    if (mounted) setState(() => _stats = stats);
  }

  Future<void> _loadPresentations(Iterable<DownloadTask> tasks) async {
    final revision = ++_presentationRevision;
    final ids = tasks.map((task) => task.mediaId).toSet();
    final result = <String, DownloadPresentation>{};
    for (final mediaId in ids) {
      final media = await widget.repository?.getById(mediaId);
      TmdbMediaDetails? tmdb;
      if (media != null && widget.tmdbMetadata != null) {
        tmdb = await widget.tmdbMetadata!.loadCachedForMedia(media);
      }
      final mediaTasks = tasks.where((task) => task.mediaId == mediaId);
      final first = mediaTasks.first;
      result[mediaId] = DownloadPresentation(
        title: media?.title.trim().isNotEmpty == true
            ? media!.title
            : first.title?.trim().isNotEmpty == true
                ? first.title!
                : mediaId,
        posterUrl: tmdb?.posterUrl.trim().isNotEmpty == true
            ? tmdb!.posterUrl
            : media?.posterUrl.trim().isNotEmpty == true
                ? media!.posterUrl
                : first.posterUrl ?? '',
        backdropUrl: tmdb?.backdropUrl.trim().isNotEmpty == true
            ? tmdb!.backdropUrl
            : media?.backdropUrl.trim().isNotEmpty == true
                ? media!.backdropUrl
                : first.backdropUrl ?? '',
        tmdb: tmdb,
      );
    }
    if (mounted && revision == _presentationRevision) {
      setState(() => _presentations = result);
    }
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<DownloadTask>>{};
    for (final task in _tasks) {
      groups.putIfAbsent(task.mediaId, () => []).add(task);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('缓存下载'),
        actions: [
          if (_tasks.isNotEmpty)
            IconButton(
              tooltip: '清空全部缓存',
              onPressed: _clearAll,
              icon: const Icon(Icons.cleaning_services_outlined),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
        children: [
          _StorageSummary(stats: _stats),
          const SizedBox(height: 18),
          if (groups.isEmpty)
            const _EmptyDownloads()
          else
            ...groups.entries.map((entry) {
              final presentation = _presentations[entry.key] ??
                  DownloadPresentation.fromTask(entry.value.first);
              return _DownloadGroup(
                key: ValueKey(entry.key),
                tasks: entry.value,
                presentation: presentation,
                onOpen: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => DownloadGroupDetailsScreen(
                      service: widget.service,
                      mediaId: entry.key,
                      presentation: presentation,
                      repository: widget.repository,
                      onPlayTask: widget.onPlayTask,
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空全部缓存？'),
        content: const Text('已完成文件和未完成任务都会被删除，此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    for (final task in _tasks.toList()) {
      await widget.service.delete(task.id);
    }
    await _loadStats();
  }
}

class _StorageSummary extends StatelessWidget {
  const _StorageSummary({required this.stats});

  final DownloadCacheStats? stats;

  @override
  Widget build(BuildContext context) {
    final value = stats;
    final size = value == null
        ? '计算中…'
        : value.totalBytes < 1024 * 1024
            ? '${(value.totalBytes / 1024).toStringAsFixed(1)} KB'
            : '${value.totalMegabytes.toStringAsFixed(1)} MB';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: CineoColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: CineoColors.divider),
      ),
      child: Row(
        children: [
          const Icon(Icons.storage_rounded,
              color: CineoColors.primary, size: 30),
          const SizedBox(width: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('缓存占用',
                style: TextStyle(color: CineoColors.textSecondary)),
            const SizedBox(height: 3),
            Text(size,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ]),
          const Spacer(),
          Text('${value?.taskCount ?? 0} 集任务',
              style: const TextStyle(color: CineoColors.textSecondary)),
        ],
      ),
    );
  }
}

class DownloadPresentation {
  const DownloadPresentation({
    required this.title,
    required this.posterUrl,
    required this.backdropUrl,
    this.tmdb,
  });

  factory DownloadPresentation.fromTask(DownloadTask task) {
    return DownloadPresentation(
      title: task.title?.trim().isNotEmpty == true ? task.title! : task.mediaId,
      posterUrl: task.posterUrl ?? '',
      backdropUrl: task.backdropUrl ?? '',
    );
  }

  final String title;
  final String posterUrl;
  final String backdropUrl;
  final TmdbMediaDetails? tmdb;
}

class _DownloadGroup extends StatelessWidget {
  const _DownloadGroup({
    super.key,
    required this.tasks,
    required this.presentation,
    required this.onOpen,
  });

  final List<DownloadTask> tasks;
  final DownloadPresentation presentation;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final completed = tasks.where(_isPlayableLocalTask).length;
    final progress = tasks.isEmpty
        ? 0.0
        : tasks
                .map((task) =>
                    _isPlayableLocalTask(task) ? task.progress : task.progress)
                .reduce((a, b) => a + b) /
            tasks.length;
    final failed =
        tasks.where((task) => task.status == DownloadTaskStatus.failed).length;
    final season =
        tasks.map((task) => task.seasonNumber).whereType<int>().firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: CineoColors.surface,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 92,
                  height: 128,
                  child: MediaImage(
                    url: presentation.posterUrl,
                    borderRadius: BorderRadius.circular(10),
                    placeholderIcon: Icons.live_tv_outlined,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: SizedBox(
                    height: 128,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                presentation.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded,
                                color: CineoColors.textSecondary),
                          ],
                        ),
                        const SizedBox(height: 7),
                        Text(
                          season == null
                              ? '$completed/${tasks.length} 集已缓存'
                              : '第 $season 季 · $completed/${tasks.length} 集已缓存',
                          style: const TextStyle(
                              color: CineoColors.textSecondary, fontSize: 13),
                        ),
                        const Spacer(),
                        Text(
                          failed > 0
                              ? '$failed 集失败 · 点击查看详情'
                              : completed == tasks.length
                                  ? '已全部缓存完成'
                                  : '点击查看集数详情',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: failed > 0
                                ? const Color(0xFFFF9B8E)
                                : CineoColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(value: progress),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DownloadGroupDetailsScreen extends StatefulWidget {
  const DownloadGroupDetailsScreen({
    super.key,
    required this.service,
    required this.mediaId,
    required this.presentation,
    this.repository,
    this.onPlayTask,
  });

  final DownloadService service;
  final String mediaId;
  final DownloadPresentation presentation;
  final MediaRepository? repository;
  final Future<void> Function(DownloadTask task)? onPlayTask;

  @override
  State<DownloadGroupDetailsScreen> createState() =>
      _DownloadGroupDetailsScreenState();
}

class _DownloadGroupDetailsScreenState
    extends State<DownloadGroupDetailsScreen> {
  late final StreamSubscription<List<DownloadTask>> _subscription;
  List<DownloadTask> _tasks = const [];
  Map<String, WatchProgress> _watchProgress = const {};

  @override
  void initState() {
    super.initState();
    _tasks = _filtered(widget.service.tasks);
    _subscription = widget.service.changes.listen((tasks) {
      if (mounted) setState(() => _tasks = _filtered(tasks));
    });
    unawaited(_loadWatchProgress());
  }

  Future<void> _loadWatchProgress() async {
    final repository = widget.repository;
    if (repository == null) return;
    final history = await repository.watchHistory();
    if (!mounted) return;
    setState(() {
      _watchProgress = {
        for (final entry in history)
          if (entry.mediaId == widget.mediaId && entry.episodeId != null)
            entry.episodeId!: entry,
      };
    });
  }

  Future<void> _playTask(DownloadTask task) async {
    final callback = widget.onPlayTask;
    if (callback == null) return;
    await callback(task);
    await _loadWatchProgress();
  }

  List<DownloadTask> _filtered(Iterable<DownloadTask> tasks) {
    return tasks.where((task) => task.mediaId == widget.mediaId).toList()
      ..sort((a, b) {
        final left = a.episodeNumber ?? 0;
        final right = b.episodeNumber ?? 0;
        return left == right
            ? a.createdAt.compareTo(b.createdAt)
            : left.compareTo(right);
      });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final completed = _tasks.where(_isPlayableLocalTask).length;
    final progress = _tasks.isEmpty
        ? 0.0
        : _tasks.map((task) => task.progress).reduce((a, b) => a + b) /
            _tasks.length;
    final cachedBytes = _tasks
        .where((task) => task.status == DownloadTaskStatus.completed)
        .fold<int>(0, (total, task) => total + task.downloadedBytes);
    return Scaffold(
      appBar: AppBar(title: Text(widget.presentation.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _DownloadDetailHeader(
            presentation: widget.presentation,
            completed: completed,
            total: _tasks.length,
            progress: progress,
            cachedBytes: cachedBytes,
          ),
          const SizedBox(height: 18),
          ..._tasks.map((task) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _DownloadEpisodeCard(
                  task: task,
                  imageUrl: _episodeImage(task),
                  onPlay: _isPlayableLocalTask(task)
                      ? widget.onPlayTask == null
                          ? null
                          : () => unawaited(_playTask(task))
                      : null,
                  playbackProgress: _watchProgress[task.episodeId ?? task.id],
                  onPause: () => widget.service.pause(task.id),
                  onResume: () => widget.service.resume(task.id),
                  onRetry: () => widget.service.retry(task.id),
                  onRedownload: _isLegacyCompletedTask(task)
                      ? () => widget.service.redownload(task.id)
                      : null,
                  onDelete: () => widget.service.delete(task.id),
                ),
              )),
        ],
      ),
    );
  }

  String _episodeImage(DownloadTask task) {
    final season = widget.presentation.tmdb?.seasons
        .where((item) => item.seasonNumber == task.seasonNumber)
        .firstOrNull;
    final episode = season?.episodes
        .where((item) => item.episodeNumber == task.episodeNumber)
        .firstOrNull;
    if (episode?.stillUrl.trim().isNotEmpty == true) return episode!.stillUrl;
    final seasonPoster = season?.posterUrl.trim() ?? '';
    if (seasonPoster.isNotEmpty) return seasonPoster;
    return presentationFallback(widget.presentation);
  }
}

String presentationFallback(DownloadPresentation presentation) {
  return presentation.posterUrl.trim().isNotEmpty
      ? presentation.posterUrl
      : presentation.backdropUrl;
}

class _DownloadDetailHeader extends StatelessWidget {
  const _DownloadDetailHeader({
    required this.presentation,
    required this.completed,
    required this.total,
    required this.progress,
    required this.cachedBytes,
  });

  final DownloadPresentation presentation;
  final int completed;
  final int total;
  final double progress;
  final int cachedBytes;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 84,
          height: 116,
          child: MediaImage(
            url: presentationFallback(presentation),
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(presentation.title,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text('$completed/$total 集已缓存',
                  style: const TextStyle(color: CineoColors.textSecondary)),
              const SizedBox(height: 6),
              Text('总文件大小 ${formatDownloadBytes(cachedBytes)}',
                  style: const TextStyle(color: CineoColors.textSecondary)),
              if (completed < total) ...[
                const SizedBox(height: 14),
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 6),
                Text('${(progress * 100).round()}% 下载进度',
                    style: const TextStyle(
                        color: CineoColors.textSecondary, fontSize: 12)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DownloadEpisodeCard extends StatelessWidget {
  const _DownloadEpisodeCard({
    required this.task,
    required this.imageUrl,
    this.playbackProgress,
    this.onPlay,
    required this.onPause,
    required this.onResume,
    required this.onRetry,
    required this.onRedownload,
    required this.onDelete,
  });

  final DownloadTask task;
  final String imageUrl;
  final WatchProgress? playbackProgress;
  final VoidCallback? onPlay;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onRetry;
  final VoidCallback? onRedownload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final label = task.episodeNumber == null
        ? '电影'
        : '第 ${task.episodeNumber} 集${task.episodeLabel?.trim().isNotEmpty == true ? ' · ${task.episodeLabel}' : ''}';
    return Material(
      color: CineoColors.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPlay,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: CineoColors.divider),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 126,
                height: 76,
                child: MediaImage(
                  url: imageUrl,
                  borderRadius: BorderRadius.circular(8),
                  placeholderIcon: Icons.live_tv_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 5),
                    Text(_downloadStatusLabel(task),
                        maxLines:
                            task.status == DownloadTaskStatus.failed ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: task.status == DownloadTaskStatus.failed
                              ? const Color(0xFFFF9B8E)
                              : CineoColors.textSecondary,
                          fontSize: 12,
                        )),
                    const SizedBox(height: 3),
                    Text(
                      _isPlayableLocalTask(task)
                          ? _playbackProgressLabel(playbackProgress)
                          : formatDownloadSizeProgress(task),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: CineoColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 7),
                    LinearProgressIndicator(
                      value: _isPlayableLocalTask(task)
                          ? playbackProgress?.fraction ?? 0
                          : task.progress,
                    ),
                  ],
                ),
              ),
              _DownloadActionButtons(
                task: task,
                onPause: onPause,
                onResume: onResume,
                onRetry: onRetry,
                onRedownload: onRedownload,
                onDelete: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _playbackProgressLabel(WatchProgress? progress) {
  if (progress == null || progress.duration <= Duration.zero) {
    return '播放进度 0%';
  }
  return '播放进度 ${(progress.fraction * 100).round()}% · '
      '${formatPlaybackDuration(progress.position)} / '
      '${formatPlaybackDuration(progress.duration)}';
}

class _DownloadActionButtons extends StatelessWidget {
  const _DownloadActionButtons({
    required this.task,
    required this.onPause,
    required this.onResume,
    required this.onRetry,
    required this.onRedownload,
    required this.onDelete,
  });

  final DownloadTask task;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onRetry;
  final VoidCallback? onRedownload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final Widget primary;
    if (task.status == DownloadTaskStatus.downloading ||
        task.status == DownloadTaskStatus.queued) {
      primary = IconButton(
        tooltip: '暂停',
        onPressed: onPause,
        icon: const Icon(Icons.pause_rounded),
      );
    } else if (task.status == DownloadTaskStatus.paused) {
      primary = IconButton(
        tooltip: '继续',
        onPressed: onResume,
        icon: const Icon(Icons.play_arrow_rounded),
      );
    } else if (onRedownload != null) {
      primary = IconButton(
        tooltip: '重新下载',
        onPressed: onRedownload,
        icon: const Icon(Icons.refresh_rounded),
      );
    } else if (task.status == DownloadTaskStatus.failed ||
        task.status == DownloadTaskStatus.cancelled) {
      primary = IconButton(
        tooltip: '重试',
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded),
      );
    } else {
      primary =
          const Icon(Icons.check_circle_rounded, color: Color(0xFF35B885));
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        primary,
        IconButton(
          tooltip: '删除',
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ],
    );
  }
}

bool _isPlayableLocalTask(DownloadTask task) {
  return task.status == DownloadTaskStatus.completed &&
      task.outputPath?.toLowerCase().endsWith('.m3u8') == true;
}

bool _isLegacyCompletedTask(DownloadTask task) {
  return task.status == DownloadTaskStatus.completed &&
      task.outputPath?.toLowerCase().endsWith('.ts') == true;
}

String _downloadStatusLabel(DownloadTask task) {
  switch (task.status) {
    case DownloadTaskStatus.queued:
      return '等待下载 · ${(task.progress * 100).round()}%';
    case DownloadTaskStatus.downloading:
      return '下载中 · ${(task.progress * 100).round()}%';
    case DownloadTaskStatus.paused:
      return '已暂停 · ${(task.progress * 100).round()}%';
    case DownloadTaskStatus.completed:
      return _isLegacyCompletedTask(task) ? '缓存格式已过期，请重新下载' : '已完成';
    case DownloadTaskStatus.cancelled:
      return '已取消';
    case DownloadTaskStatus.failed:
      return _downloadFailureLabel(task.errorMessage);
  }
}

String formatDownloadSizeProgress(DownloadTask task) {
  final downloaded = formatDownloadBytes(task.downloadedBytes);
  if (task.totalBytes > 0) {
    return '已下载 $downloaded / ${formatDownloadBytes(task.totalBytes)}';
  }
  if (task.downloadedBytes > 0) return '已下载 $downloaded / 大小计算中';
  return '已下载 0 B / 大小计算中';
}

String formatDownloadBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

String _downloadFailureLabel(String? error) {
  if (error == null || error.isEmpty) return '下载失败，请重试';
  if (error.contains('HTTP 401') || error.contains('HTTP 403')) {
    return '服务器拒绝请求，请重试或更换线路';
  }
  if (error.contains('HTTP 404')) return '片段地址不存在，请重试或更换线路';
  if (error.contains('HTTP 5')) return '视频服务器暂时不可用，请稍后重试';
  if (error.contains('Segment response truncated')) return '片段传输不完整，请重试';
  if (error.contains('Empty HLS segment')) return '服务器返回了空片段，请重试';
  if (error.contains('Connection closed')) return '连接中断，请重试';
  if (error.contains('Playlist request failed')) {
    return '视频清单请求失败，请重试或更换线路';
  }
  if (error.contains('Live or incomplete playlists are unsupported')) {
    return '直播或不完整清单暂不支持缓存';
  }
  return '片段下载失败，请重试或更换线路';
}

class _EmptyDownloads extends StatelessWidget {
  const _EmptyDownloads();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 80),
      child: Column(children: [
        Icon(Icons.download_for_offline_outlined,
            size: 48, color: CineoColors.textSecondary),
        SizedBox(height: 12),
        Text('还没有缓存任务'),
        SizedBox(height: 4),
        Text('在视频详情页点击下载即可开始缓存',
            style: TextStyle(color: CineoColors.textSecondary)),
      ]),
    );
  }
}

class DownloadSettingsScreen extends StatefulWidget {
  const DownloadSettingsScreen({
    super.key,
    required this.service,
  });

  final DownloadService service;

  @override
  State<DownloadSettingsScreen> createState() => _DownloadSettingsScreenState();
}

class _DownloadSettingsScreenState extends State<DownloadSettingsScreen> {
  DownloadSettings get _settings => widget.service.settings;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('下载设置'),
        leading: const BackButton(),
      ),
      body: SafeArea(
        top: false,
        child: StreamBuilder<List<DownloadTask>>(
          stream: widget.service.changes,
          initialData: widget.service.tasks,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
            children: [
              Text(
                '配置缓存下载的运行方式',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: CineoColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 16),
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: CineoColors.surface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                      leading: const Icon(Icons.speed_rounded),
                      title: const Text('同时下载线程'),
                      subtitle: Text('${_settings.concurrency} 个任务同时下载'),
                      trailing: DropdownButton<int>(
                        value: _settings.concurrency,
                        items: [
                          for (var value = 1; value <= 10; value++)
                            DropdownMenuItem(
                              value: value,
                              child: Text('$value'),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            widget.service.updateSettings(
                              _settings.copyWith(concurrency: value),
                            );
                          }
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    SwitchListTile.adaptive(
                      contentPadding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                      secondary: const Icon(Icons.cloud_download_outlined),
                      title: const Text('允许后台下载'),
                      subtitle: const Text('应用进入后台时继续下载'),
                      value: _settings.allowBackground,
                      onChanged: (value) => widget.service.updateSettings(
                        _settings.copyWith(allowBackground: value),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
