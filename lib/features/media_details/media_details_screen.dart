import 'package:flutter/material.dart';

import '../../core/models/media.dart';
import '../../core/models/tmdb_media.dart';
import '../../core/theme/cineo_theme.dart';
import '../../core/text/media_description_formatter.dart';
import '../../shared/widgets/media_image.dart';
import 'episode_library_screen.dart';

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
    this.onLoadTmdbDetails,
  });

  final MediaItem media;
  final bool favorite;
  final ValueChanged<bool> onFavoriteChanged;
  final ValueChanged<PlaybackOption> onPlay;
  final String? initialEpisodeId;
  final Future<List<MediaItem>> Function(MediaItem media)? onSearchOtherSources;
  final ValueChanged<MediaItem>? onOpenAlternative;
  final Future<TmdbMediaDetails?> Function(MediaItem media)? onLoadTmdbDetails;

  @override
  State<MediaDetailsScreen> createState() => _MediaDetailsScreenState();
}

class _MediaDetailsScreenState extends State<MediaDetailsScreen> {
  late bool _favorite = widget.favorite;
  String? _selectedSourceName;
  Episode? _selectedEpisode;
  bool _searchingOtherSources = false;
  TmdbMediaDetails? _tmdbDetails;
  bool _tmdbLoading = false;
  int? _selectedSeason;

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
    final episodes = episodesWithLines.isEmpty
        ? widget.media.episodes.toList()
        : episodesWithLines;

    final activeName = _activeSourceName;
    final sourceEpisodes = episodesWithLines.isEmpty || activeName == null
        ? episodes
        : episodes
            .where(
                (episode) => _lineName(episode.playbackOption!) == activeName)
            .toList();
    final season = _selectedSeason;
    if (season == null) return sourceEpisodes;
    return sourceEpisodes.where((episode) => episode.season == season).toList();
  }

  List<int> get _sourceSeasons {
    final activeName = _activeSourceName;
    final sourceEpisodes = widget.media.episodes.where((episode) {
      final option = episode.playbackOption;
      return option == null ||
          activeName == null ||
          _lineName(option) == activeName;
    });
    final values = sourceEpisodes.map((episode) => episode.season).toSet()
      ..removeWhere((season) => season < 1);
    return values.toList()..sort();
  }

  String get _displayTitle => _tmdbDetails?.title.trim().isNotEmpty == true
      ? _tmdbDetails!.title
      : widget.media.title;

  String get _displayDescription =>
      _tmdbDetails?.overview.trim().isNotEmpty == true
          ? _tmdbDetails!.overview
          : widget.media.description;

  String get _displayBackdrop {
    final tmdb = _tmdbDetails?.backdropUrl.trim() ?? '';
    if (tmdb.isNotEmpty) return tmdb;
    final source = widget.media.backdropUrl.trim();
    return source.isNotEmpty ? source : widget.media.posterUrl;
  }

  double get _displayRating => (_tmdbDetails?.rating ?? 0) > 0
      ? _tmdbDetails!.rating
      : widget.media.rating;

  int get _displayYear => _tmdbDetails?.year ?? widget.media.year;

  String? get _displayRuntime {
    final minutes = _tmdbDetails?.runtime;
    if ((minutes ?? 0) > 0) return '$minutes 分钟';
    if (widget.media.duration.inMinutes > 0) {
      return '${widget.media.duration.inMinutes} 分钟';
    }
    return null;
  }

  List<int> get _availableSeasons {
    final values = <int>{..._sourceSeasons};
    for (final season
        in _tmdbDetails?.seasons ?? const <TmdbSeasonMetadata>[]) {
      if (season.seasonNumber > 0) values.add(season.seasonNumber);
    }
    final result = values.toList()..sort();
    return result;
  }

  TmdbSeasonMetadata? get _selectedTmdbSeason {
    final season = _selectedSeason;
    if (season == null) return null;
    for (final item in _tmdbDetails?.seasons ?? const <TmdbSeasonMetadata>[]) {
      if (item.seasonNumber == season) return item;
    }
    return null;
  }

  TmdbEpisodeMetadata? _tmdbEpisodeFor(Episode episode) {
    final season = _selectedTmdbSeason;
    if (season == null) return null;
    for (final item in season.episodes) {
      if (item.episodeNumber == episode.number) return item;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final initialEpisodeId = widget.initialEpisodeId;
    if (initialEpisodeId != null) {
      for (final episode in widget.media.episodes) {
        final option = episode.playbackOption;
        if (episode.id == initialEpisodeId || option?.id == initialEpisodeId) {
          _selectedEpisode = episode;
          _selectedSeason = episode.season > 0 ? episode.season : null;
          if (option != null) _selectedSourceName = _lineName(option);
          break;
        }
      }
    }
    if (_selectedSeason == null && _sourceSeasons.isNotEmpty) {
      _selectedSeason = _sourceSeasons.first;
    }
    if (widget.onLoadTmdbDetails != null) _loadTmdbDetails();
  }

  Future<void> _loadTmdbDetails() async {
    final loader = widget.onLoadTmdbDetails;
    if (loader == null) return;
    setState(() => _tmdbLoading = true);
    try {
      final details = await loader(widget.media);
      if (!mounted) return;
      setState(() {
        _tmdbDetails = details;
        if (_selectedSeason == null && _availableSeasons.isNotEmpty) {
          _selectedSeason = _availableSeasons.first;
        }
      });
    } catch (error) {
      assert(() {
        debugPrint('[Cineo][TMDB] detail_ui phase=failed '
            'errorType=${error.runtimeType}');
        return true;
      }());
    } finally {
      if (mounted) setState(() => _tmdbLoading = false);
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
        final image = AspectRatio(
          aspectRatio: wide ? 2.3 : 1.55,
          child: MediaImage(url: _displayBackdrop),
        );
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
                _displayTitle,
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
    final metadata = [
      if (_displayYear > 0) '$_displayYear',
      media.kind == MediaKind.series ? '剧集' : '电影',
      if (_displayRating > 0) '${_displayRating.toStringAsFixed(1)} 分',
      if (_displayRuntime != null) _displayRuntime!,
    ].join('  ·  ');
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
        if (_tmdbLoading)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        _DescriptionSection(description: _displayDescription),
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
              final seasons = _sourceSeasons;
              _selectedSeason = seasons.isEmpty ? null : seasons.first;
            }),
          ),
        ],
        if (media.episodes.isNotEmpty) ...[
          const SizedBox(height: 28),
          _buildEpisodesHeader(context),
          const SizedBox(height: 12),
          if (_availableSeasons.length > 1) ...[
            _SeasonSelector(
              seasons: _availableSeasons,
              selectedSeason: _selectedSeason,
              onChanged: (season) => setState(() {
                _selectedSeason = season;
                _selectedEpisode = null;
              }),
            ),
            const SizedBox(height: 14),
          ],
          _buildEpisodePreview(context),
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

  Widget _buildEpisodesHeader(BuildContext context) {
    final count = _activeEpisodes.length;
    return Row(
      children: [
        _sectionTitle('剧集'),
        const Spacer(),
        if (count > 0)
          Text('$count 集',
              style: const TextStyle(color: CineoColors.textSecondary)),
      ],
    );
  }

  Widget _buildEpisodePreview(BuildContext context) {
    final episodes = [..._activeEpisodes]
      ..sort((a, b) => a.number.compareTo(b.number));
    if (episodes.isEmpty) {
      return const _InlineEmpty(message: '当前季暂无可播放剧集');
    }
    final preview = episodes.take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 180,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: preview.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final episode = preview[index];
              final tmdbEpisode = _tmdbEpisodeFor(episode);
              final image = tmdbEpisode?.stillUrl.trim().isNotEmpty == true
                  ? tmdbEpisode!.stillUrl
                  : (_tmdbDetails?.posterUrl.trim().isNotEmpty == true
                      ? _tmdbDetails!.posterUrl
                      : widget.media.posterUrl);
              return SizedBox(
                width: 150,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: episode.playbackOption == null
                      ? null
                      : () {
                          setState(() => _selectedEpisode = episode);
                          widget.onPlay(episode.playbackOption!);
                        },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            MediaImage(
                              url: image,
                              borderRadius: BorderRadius.circular(8),
                              placeholderIcon: Icons.live_tv_outlined,
                            ),
                            Positioned(
                              left: 8,
                              bottom: 8,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(.75),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 3),
                                  child: Text('第 ${episode.number} 集',
                                      style: const TextStyle(fontSize: 11)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        tmdbEpisode?.name.trim().isNotEmpty == true
                            ? tmdbEpisode!.name
                            : '第 ${episode.number} 集',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => EpisodeLibraryScreen(
                  media: widget.media,
                  episodes: _activeEpisodes,
                  tmdbSeason: _selectedTmdbSeason,
                  fallbackPosterUrl: widget.media.posterUrl,
                  onPlay: widget.onPlay,
                ),
              ),
            ),
            icon: const Icon(Icons.grid_view_rounded, size: 18),
            label: const Text('查看全部'),
          ),
        ),
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

class _DescriptionSection extends StatefulWidget {
  const _DescriptionSection({required this.description});

  final String description;

  @override
  State<_DescriptionSection> createState() => _DescriptionSectionState();
}

class _DescriptionSectionState extends State<_DescriptionSection> {
  static const _collapsedLineLimit = 8;
  bool _expanded = false;

  String get _formattedDescription =>
      formatMediaDescription(widget.description);

  bool get _isLong {
    final text = _formattedDescription;
    return text.length > 320 || '\n'.allMatches(text).length >= 8;
  }

  @override
  Widget build(BuildContext context) {
    final description = _formattedDescription;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('简介',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        if (description.isEmpty)
          const Text('暂无简介',
              style: TextStyle(color: CineoColors.textSecondary, height: 1.55))
        else ...[
          Text(
            description,
            maxLines: _isLong && !_expanded ? _collapsedLineLimit : null,
            overflow: _isLong && !_expanded
                ? TextOverflow.ellipsis
                : TextOverflow.clip,
            style: const TextStyle(
              color: CineoColors.textSecondary,
              height: 1.65,
            ),
          ),
          if (_isLong)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(_expanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded),
                label: Text(_expanded ? '收起简介' : '展开简介'),
              ),
            ),
        ],
      ],
    );
  }
}

String _lineName(PlaybackOption option) {
  final name = option.quality.trim();
  return name.isEmpty ? '播放源' : name;
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

class _SeasonSelector extends StatelessWidget {
  const _SeasonSelector({
    required this.seasons,
    required this.selectedSeason,
    required this.onChanged,
  });

  final List<int> seasons;
  final int? selectedSeason;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int>(
      value: selectedSeason,
      decoration: const InputDecoration(
        labelText: '选择季数',
        prefixIcon: Icon(Icons.layers_outlined),
      ),
      items: seasons
          .map((season) => DropdownMenuItem<int>(
                value: season,
                child: Text('第$season季'),
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
