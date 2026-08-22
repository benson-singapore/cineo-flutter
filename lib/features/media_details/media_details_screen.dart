import 'package:flutter/material.dart';

import '../../core/models/media.dart';
import '../../core/theme/cineo_theme.dart';

class MediaDetailsScreen extends StatefulWidget {
  const MediaDetailsScreen({
    super.key,
    required this.media,
    required this.favorite,
    required this.onFavoriteChanged,
    required this.onPlay,
    this.initialEpisodeId,
    this.onSearchOtherSources,
    this.onOpenAlternative,
  });

  final MediaItem media;
  final bool favorite;
  final ValueChanged<bool> onFavoriteChanged;
  final ValueChanged<PlaybackOption> onPlay;
  final String? initialEpisodeId;
  final Future<List<MediaItem>> Function(MediaItem media)? onSearchOtherSources;
  final ValueChanged<MediaItem>? onOpenAlternative;

  @override
  State<MediaDetailsScreen> createState() => _MediaDetailsScreenState();
}

class _MediaDetailsScreenState extends State<MediaDetailsScreen> {
  late bool _favorite = widget.favorite;
  String? _selectedSourceName;
  Episode? _selectedEpisode;
  bool _searchingOtherSources = false;

  List<PlaybackOption> get _options => widget.media.playbackOptions;

  List<PlaybackOption> get _sourceOptions {
    final seen = <String>{};
    return _options.where((option) => seen.add(_lineName(option))).toList();
  }

  String? get _activeSourceName =>
      _selectedSourceName ??
      (_sourceOptions.isEmpty ? null : _lineName(_sourceOptions.first));

  List<PlaybackOption> get _activeOptions => _options
      .where((option) => _lineName(option) == _activeSourceName)
      .toList();

  List<Episode> get _activeEpisodes {
    final episodesWithLines = widget.media.episodes
        .where((episode) => episode.playbackOption != null)
        .toList();
    if (episodesWithLines.isEmpty) return widget.media.episodes;

    final activeName = _activeSourceName;
    if (activeName == null) return const [];
    return episodesWithLines
        .where((episode) => _lineName(episode.playbackOption!) == activeName)
        .toList();
  }

  @override
  void initState() {
    super.initState();
    final initialEpisodeId = widget.initialEpisodeId;
    if (initialEpisodeId == null) return;
    for (final episode in widget.media.episodes) {
      final option = episode.playbackOption;
      if (episode.id == initialEpisodeId || option?.id == initialEpisodeId) {
        _selectedEpisode = episode;
        if (option != null) _selectedSourceName = _lineName(option);
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = widget.media;
    return Scaffold(
      backgroundColor: CineoColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: CineoColors.background,
            surfaceTintColor: Colors.transparent,
            title: const Text('详情'),
            actions: [
              IconButton(
                tooltip: _favorite ? '取消收藏' : '收藏',
                onPressed: () {
                  setState(() => _favorite = !_favorite);
                  widget.onFavoriteChanged(_favorite);
                },
                icon: Icon(_favorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded),
              ),
              const SizedBox(width: 8),
            ],
          ),
          SliverToBoxAdapter(child: _buildHero(context, media)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
            sliver: SliverToBoxAdapter(child: _buildBody(context, media)),
          ),
        ],
      ),
    );
  }

  Widget _buildHero(BuildContext context, MediaItem media) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 700;
        final image =
            _MediaImage(url: media.backdropUrl, aspectRatio: wide ? 2.3 : 1.55);
        return Stack(
          children: [
            image,
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      CineoColors.background.withOpacity(.15),
                      CineoColors.background,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 20,
              child: Text(
                media.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      height: 1.05,
                    ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, MediaItem media) {
    final metadata =
        '${media.year}  ·  ${media.kind == MediaKind.series ? '剧集' : '电影'}  ·  ${media.rating.toStringAsFixed(1)} 分';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(metadata,
            style: const TextStyle(color: CineoColors.textSecondary)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children:
              media.genres.map((genre) => Chip(label: Text(genre))).toList(),
        ),
        const SizedBox(height: 18),
        Text(media.description,
            style: const TextStyle(
                color: CineoColors.textSecondary, height: 1.55)),
        const SizedBox(height: 28),
        _sectionTitle('播放来源'),
        const SizedBox(height: 12),
        if (_sourceOptions.isEmpty)
          const _InlineEmpty(message: '暂无可用播放来源')
        else ...[
          _SourceSelector(
            sourceNames: _sourceOptions.map(_lineName).toList(),
            selectedSourceName: _activeSourceName,
            onChanged: (value) => setState(() {
              _selectedSourceName = value;
              _selectedEpisode = null;
            }),
          ),
        ],
        if (media.episodes.isNotEmpty) ...[
          const SizedBox(height: 28),
          _sectionTitle('剧集'),
          const SizedBox(height: 12),
          _EpisodeList(
            episodes: _activeEpisodes,
            selectedEpisode: _selectedEpisode,
            onSelected: (episode) {
              setState(() => _selectedEpisode = episode);
              if (episode.playbackOption != null) {
                widget.onPlay(episode.playbackOption!);
              }
            },
          ),
        ] else if (_activeOptions.isNotEmpty) ...[
          const SizedBox(height: 12),
          _PlaybackList(options: _activeOptions, onPlay: widget.onPlay),
        ],
        if (widget.onSearchOtherSources != null) ...[
          const SizedBox(height: 28),
          OutlinedButton.icon(
            onPressed: _searchingOtherSources ? null : _searchOtherSources,
            icon: _searchingOtherSources
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.travel_explore_outlined),
            label: Text(_searchingOtherSources ? '正在搜索其他站点...' : '在其他站点查找'),
          ),
        ],
      ],
    );
  }

  Future<void> _searchOtherSources() async {
    final finder = widget.onSearchOtherSources;
    if (finder == null) return;
    setState(() => _searchingOtherSources = true);
    try {
      final matches = await finder(widget.media);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => _OtherSourcesSheet(
          matches: matches,
          onOpen: (media) {
            Navigator.of(context).pop();
            widget.onOpenAlternative?.call(media);
          },
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('其他站点暂时无法完成搜索')),
      );
    } finally {
      if (mounted) setState(() => _searchingOtherSources = false);
    }
  }

  Widget _sectionTitle(String title) {
    return Text(title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800));
  }
}

String _lineName(PlaybackOption option) {
  final name = option.quality.trim();
  return name.isEmpty ? '播放源' : name;
}

class _MediaImage extends StatelessWidget {
  const _MediaImage({required this.url, required this.aspectRatio});

  final String url;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const ColoredBox(
          color: CineoColors.surfaceElevated,
          child: Center(
            child: Icon(Icons.landscape_outlined,
                size: 52, color: CineoColors.textSecondary),
          ),
        ),
      ),
    );
  }
}

class _SourceSelector extends StatelessWidget {
  const _SourceSelector({
    required this.sourceNames,
    required this.selectedSourceName,
    required this.onChanged,
  });

  final List<String> sourceNames;
  final String? selectedSourceName;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: selectedSourceName,
      decoration: const InputDecoration(
        labelText: '选择来源',
        prefixIcon: Icon(Icons.dns_outlined),
      ),
      items: sourceNames
          .map((name) => DropdownMenuItem(
                value: name,
                child: Text(name, overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}

class _PlaybackList extends StatelessWidget {
  const _PlaybackList({required this.options, required this.onPlay});

  final List<PlaybackOption> options;
  final ValueChanged<PlaybackOption> onPlay;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const _InlineEmpty(message: '当前来源暂无播放地址');
    return Column(
      children: options
          .map((option) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  tileColor: CineoColors.surface,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  leading: const Icon(Icons.play_circle_outline_rounded,
                      color: CineoColors.primary),
                  title: Text(option.label),
                  subtitle: Text(option.isHls
                      ? 'HLS · ${option.quality}'
                      : option.quality),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => onPlay(option),
                ),
              ))
          .toList(),
    );
  }
}

class _EpisodeList extends StatelessWidget {
  const _EpisodeList({
    required this.episodes,
    required this.selectedEpisode,
    required this.onSelected,
  });

  final List<Episode> episodes;
  final Episode? selectedEpisode;
  final ValueChanged<Episode> onSelected;

  @override
  Widget build(BuildContext context) {
    return _EpisodePicker(
      episodes: episodes,
      selectedEpisode: selectedEpisode,
      onSelected: onSelected,
    );
  }
}

/// Formats an episode using the source label when it contains a usable number.
/// MacCMS labels are inconsistent, so the model number remains the fallback.
String formatEpisodeLabel(Episode episode) {
  final candidates = <String>[
    episode.playbackOption?.label ?? '',
    episode.title,
  ];
  final markedNumberPattern = RegExp(r'第\s*0*(\d+)\s*(?:集|话|期)');
  final plainNumberPattern = RegExp(r'^0*(\d+)$');
  for (final candidate in candidates) {
    if (candidate.contains('正片')) return '正片';
    final match = markedNumberPattern.firstMatch(candidate.trim()) ??
        plainNumberPattern.firstMatch(candidate.trim());
    final value = int.tryParse(match?.group(1) ?? '');
    if (value != null && value > 0) return '第$value集';
  }
  if (episode.number > 0) return '第${episode.number}集';
  return episode.title.trim().isEmpty ? '正片' : episode.title.trim();
}

class _EpisodePicker extends StatefulWidget {
  const _EpisodePicker({
    required this.episodes,
    required this.selectedEpisode,
    required this.onSelected,
  });

  final List<Episode> episodes;
  final Episode? selectedEpisode;
  final ValueChanged<Episode> onSelected;

  @override
  State<_EpisodePicker> createState() => _EpisodePickerState();
}

class _EpisodePickerState extends State<_EpisodePicker> {
  final _scrollController = ScrollController();
  bool _ascending = true;
  bool _showBackToTop = false;

  List<Episode> get _sortedEpisodes {
    final result = [...widget.episodes];
    result.sort((a, b) {
      final comparison = a.number.compareTo(b.number);
      return _ascending ? comparison : -comparison;
    });
    return result;
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _scheduleSelectedEpisodeScroll();
  }

  @override
  void didUpdateWidget(covariant _EpisodePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedEpisode?.id != widget.selectedEpisode?.id ||
        oldWidget.episodes.length != widget.episodes.length) {
      _scheduleSelectedEpisodeScroll();
    }
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
        _scrollController.hasClients && _scrollController.offset > 180;
    if (shouldShow != _showBackToTop && mounted) {
      setState(() => _showBackToTop = shouldShow);
    }
  }

  void _scheduleSelectedEpisodeScroll() {
    final selectedId = widget.selectedEpisode?.id;
    if (selectedId == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final index =
          _sortedEpisodes.indexWhere((episode) => episode.id == selectedId);
      if (index < 0) return;
      final rows = (index / 3).floor();
      final target = (rows * 52).toDouble();
      final maxExtent = _scrollController.position.maxScrollExtent;
      _scrollController.animateTo(
        target > maxExtent ? maxExtent : target,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    });
  }

  void _toggleOrder() {
    setState(() => _ascending = !_ascending);
    _scheduleSelectedEpisodeScroll();
  }

  void _backToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.episodes.isEmpty) {
      return const _InlineEmpty(message: '当前线路暂无剧集');
    }
    final episodes = _sortedEpisodes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('${episodes.length} 集',
                style: const TextStyle(color: CineoColors.textSecondary)),
            const Spacer(),
            TextButton.icon(
              onPressed: _toggleOrder,
              icon:
                  Icon(_ascending ? Icons.south_rounded : Icons.north_rounded),
              label: Text(_ascending ? '正序' : '倒序'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 292,
          child: Stack(
            children: [
              GridView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.only(right: 4, bottom: 52),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 128,
                  mainAxisExtent: 44,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: episodes.length,
                itemBuilder: (context, index) {
                  final episode = episodes[index];
                  return ChoiceChip(
                    key: ValueKey(episode.id),
                    label: Text(formatEpisodeLabel(episode)),
                    selected: widget.selectedEpisode?.id == episode.id,
                    onSelected: (_) => widget.onSelected(episode),
                  );
                },
              ),
              if (_showBackToTop)
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: FloatingActionButton.small(
                    heroTag: null,
                    tooltip: '回到顶部',
                    onPressed: _backToTop,
                    child: const Icon(Icons.vertical_align_top_rounded),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: CineoColors.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(message,
          style: const TextStyle(color: CineoColors.textSecondary)),
    );
  }
}

class _OtherSourcesSheet extends StatelessWidget {
  const _OtherSourcesSheet({required this.matches, required this.onOpen});

  final List<MediaItem> matches;
  final ValueChanged<MediaItem> onOpen;

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(24, 8, 24, 40),
        child: Text('已搜索所有已启用的视频源，暂未找到匹配内容。'),
      );
    }
    final grouped = <String, List<MediaItem>>{};
    for (final media in matches) {
      grouped.putIfAbsent(media.sourceId ?? '其他来源', () => []).add(media);
    }
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          Text('其他站点结果', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ...grouped.entries.expand((entry) => [
                Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 4),
                  child: Text('来源 ${entry.key}',
                      style: const TextStyle(color: CineoColors.textSecondary)),
                ),
                ...entry.value.map(
                  (media) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(media.title),
                    subtitle: Text(media.category ?? '视频资源'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => onOpen(media),
                  ),
                ),
              ]),
        ],
      ),
    );
  }
}
