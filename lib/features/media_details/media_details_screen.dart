import 'package:flutter/material.dart';

import '../../core/platform/adaptive_navigation.dart';
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
    this.initialTmdbDetails,
    this.onLoadFavorite,
    this.onSearchOtherSources,
    this.onLoadAlternative,
    this.onLoadTmdbDetails,
    this.onSearchTmdbMatches,
    this.onSelectTmdbMatch,
    this.repository,
    this.includeAdultHistory = false,
  });

  final MediaItem media;
  final bool favorite;
  final void Function(MediaItem media, bool isFavorite) onFavoriteChanged;
  final void Function(MediaItem media, PlaybackOption option) onPlay;
  final String? initialEpisodeId;
  final TmdbMediaDetails? initialTmdbDetails;
  final Future<bool> Function(String mediaId)? onLoadFavorite;
  final Future<List<MediaItem>> Function(MediaItem media)? onSearchOtherSources;
  final Future<MediaItem?> Function(MediaItem media)? onLoadAlternative;
  final Future<TmdbMediaDetails?> Function(MediaItem media)? onLoadTmdbDetails;
  final Future<List<TmdbMediaMatch>> Function(
      String query, TmdbMediaType? type, int? year)? onSearchTmdbMatches;
  final Future<TmdbMediaDetails?> Function(TmdbMediaMatch match)?
      onSelectTmdbMatch;
  final dynamic repository;
  final bool includeAdultHistory;

  @override
  State<MediaDetailsScreen> createState() => _MediaDetailsScreenState();
}

class _MediaDetailsScreenState extends State<MediaDetailsScreen> {
  late bool _favorite = widget.favorite;
  late MediaItem _media = widget.media;
  String? _selectedSourceName;
  bool _searchingOtherSources = false;
  bool _loadingMediaDetails = false;
  late TmdbMediaDetails? _tmdbDetails = widget.initialTmdbDetails;
  bool _tmdbLoading = false;
  int? _selectedSeason;
  bool _favoriteChangedByUser = false;

  List<PlaybackOption> get _options => _media.playbackOptions;

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
    final episodesWithLines = _media.episodes
        .where((episode) => episode.playbackOption != null)
        .toList();
    final episodes = episodesWithLines.isEmpty
        ? _media.episodes.toList()
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
    final sourceEpisodes = _media.episodes.where((episode) {
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
      : _media.title;

  String get _displayDescription =>
      _tmdbDetails?.overview.trim().isNotEmpty == true
          ? _tmdbDetails!.overview
          : _media.description;

  String get _displayBackdrop {
    final tmdb = _tmdbDetails?.backdropUrl.trim() ?? '';
    if (tmdb.isNotEmpty) return tmdb;
    final source = _media.backdropUrl.trim();
    return source.isNotEmpty ? source : _media.posterUrl;
  }

  String get _displayPoster {
    final tmdb = _tmdbDetails?.posterUrl.trim() ?? '';
    if (tmdb.isNotEmpty) return tmdb;
    final source = _media.posterUrl.trim();
    return source.isNotEmpty ? source : _displayBackdrop;
  }

  double get _displayRating =>
      (_tmdbDetails?.rating ?? 0) > 0 ? _tmdbDetails!.rating : _media.rating;

  int get _displayYear => _tmdbDetails?.year ?? _media.year;

  String? get _displayRuntime {
    final minutes = _tmdbDetails?.runtime;
    if ((minutes ?? 0) > 0) return '$minutes 分钟';
    if (_media.duration.inMinutes > 0) {
      return '${_media.duration.inMinutes} 分钟';
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
    _loadingMediaDetails = widget.repository != null;
    final initialEpisodeId = widget.initialEpisodeId;
    if (initialEpisodeId != null) {
      for (final episode in _media.episodes) {
        final option = episode.playbackOption;
        if (episode.id == initialEpisodeId || option?.id == initialEpisodeId) {
          _selectedSeason = episode.season > 0 ? episode.season : null;
          if (option != null) _selectedSourceName = _lineName(option);
          break;
        }
      }
    }
    if (_selectedSeason == null && _sourceSeasons.isNotEmpty) {
      _selectedSeason = _sourceSeasons.first;
    }
    if (_selectedSeason == null && _availableSeasons.isNotEmpty) {
      _selectedSeason = _availableSeasons.first;
    }
    _loadFavoriteAsync();
    _loadMediaDataAsync();
  }

  Future<void> _loadFavoriteAsync() async {
    final loader = widget.onLoadFavorite;
    if (loader == null) return;
    try {
      final favorite = await loader(_media.id);
      if (!mounted || _favoriteChangedByUser) return;
      setState(() => _favorite = favorite);
    } catch (_) {
      // Favorite state is non-critical and remains usable with its initial value.
    }
  }

  Future<void> _loadMediaDataAsync() async {
    final repo = widget.repository;

    if (repo == null) {
      if (_tmdbDetails == null && widget.onLoadTmdbDetails != null) {
        _loadTmdbDetails();
      }
      return;
    }

    try {
      final resolvedMedia = await repo.loadDetails(_media) ?? _media;
      if (!mounted) return;

      setState(() {
        _media = resolvedMedia;
        if (_selectedSourceName == null && _sourceOptions.isNotEmpty) {
          _selectedSourceName = _lineName(_sourceOptions.first);
        }
        if (_selectedSeason == null && _sourceSeasons.isNotEmpty) {
          _selectedSeason = _sourceSeasons.first;
        }
      });
    } catch (error) {
      assert(() {
        debugPrint('[Cineo][Details] resolve phase=failed '
            'errorType=${error.runtimeType}');
        return true;
      }());
    } finally {
      if (mounted) setState(() => _loadingMediaDetails = false);
    }

    if (_tmdbDetails == null && widget.onLoadTmdbDetails != null) {
      _loadTmdbDetails();
    }
  }

  Future<void> _loadTmdbDetails() async {
    final loader = widget.onLoadTmdbDetails;
    if (loader == null) return;
    setState(() => _tmdbLoading = true);
    try {
      final details = await loader(_media);
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

  Future<void> _openManualTmdbMatch() async {
    final search = widget.onSearchTmdbMatches;
    final select = widget.onSelectTmdbMatch;
    if (search == null || select == null) return;

    final match = await showDialog<TmdbMediaMatch>(
      context: context,
      builder: (_) => _ManualTmdbMatchDialog(
        initialQuery: _displayTitle,
        initialYear: _displayYear > 0 ? _displayYear : null,
        initialType: _media.kind == MediaKind.series
            ? TmdbMediaType.tv
            : TmdbMediaType.movie,
        onSearch: search,
      ),
    );
    if (match == null || !mounted) return;

    setState(() => _tmdbLoading = true);
    try {
      final details = await select(match);
      if (!mounted) return;
      if (details == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法加载所选匹配的详情')),
        );
        return;
      }
      setState(() {
        _tmdbDetails = details;
        if (_selectedSeason == null && _availableSeasons.isNotEmpty) {
          _selectedSeason = _availableSeasons.first;
        }
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('手动匹配暂时无法完成')),
      );
      assert(() {
        debugPrint('[Cineo][TMDB] manual_match phase=failed '
            'errorType=${error.runtimeType}');
        return true;
      }());
    } finally {
      if (mounted) setState(() => _tmdbLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = _media;
    return Scaffold(
      backgroundColor: CineoColors.background,
      body: CustomScrollView(
        slivers: [
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
        return Stack(
          children: [
            AspectRatio(
              key: const ValueKey('detail-poster'),
              aspectRatio: 2 / 3,
              child: MediaImage(
                url: _displayPoster,
                fit: BoxFit.cover,
                alignment: Alignment.center,
              ),
            ),
            Positioned.fill(
              child: SafeArea(
                bottom: false,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12, top: 12),
                    child: IconButton(
                      tooltip: '返回',
                      color: Colors.white,
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, MediaItem media) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _displayTitle,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w900,
                height: 1.12,
              ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: CineoColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: CineoColors.divider),
          ),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (_displayRating > 0)
                _InfoBadge(
                  icon: Icons.star_rounded,
                  label: '${_displayRating.toStringAsFixed(1)} 分',
                  color: CineoColors.primary,
                ),
              if (_displayYear > 0)
                _InfoBadge(
                  icon: Icons.calendar_today_rounded,
                  label: '$_displayYear',
                ),
              _InfoBadge(
                icon: media.kind == MediaKind.series
                    ? Icons.tv_rounded
                    : Icons.movie_outlined,
                label: media.kind == MediaKind.series ? '剧集' : '电影',
              ),
              if (_displayRuntime != null)
                _InfoBadge(
                  icon: Icons.schedule_rounded,
                  label: _displayRuntime!,
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
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
            child: LinearProgressIndicator(
              minHeight: 2,
              color: CineoColors.primary,
              backgroundColor: CineoColors.surfaceOverlay,
            ),
          ),
        _DescriptionSection(
          description: _displayDescription,
          trailing: _buildDescriptionActions(),
        ),
        const SizedBox(height: 28),
        _sectionTitle('播放来源'),
        const SizedBox(height: 12),
        if (widget.onSearchOtherSources != null) ...[
          _SiteSwitchTile(
            sourceName: _siteDisplayName(media),
            isLoading: _searchingOtherSources,
            onTap: _searchingOtherSources ? null : _searchOtherSources,
          ),
          const SizedBox(height: 12),
        ],
        if (_sourceOptions.isEmpty)
          const _InlineEmpty(message: '暂无可用播放来源')
        else ...[
          _SourceSelector(
            sourceNames: _sourceOptions.map(_lineName).toList(),
            selectedSourceName: _activeSourceName,
            onChanged: (value) => setState(() {
              _selectedSourceName = value;
              final seasons = _sourceSeasons;
              _selectedSeason = seasons.isEmpty ? null : seasons.first;
            }),
          ),
        ],
        if (_loadingMediaDetails) ...[
          const SizedBox(height: 28),
          _buildEpisodesHeader(context, isLoading: true),
          const SizedBox(height: 12),
          const _EpisodeLoadingPlaceholder(),
        ] else if (media.episodes.isNotEmpty) ...[
          const SizedBox(height: 28),
          _buildEpisodesHeader(context),
          const SizedBox(height: 12),
          if (_availableSeasons.length > 1) ...[
            _SeasonSelector(
              seasons: _availableSeasons,
              selectedSeason: _selectedSeason,
              onChanged: (season) => setState(() {
                _selectedSeason = season;
              }),
            ),
            const SizedBox(height: 14),
          ],
          _buildEpisodePreview(context),
        ] else if (_activeOptions.isNotEmpty) ...[
          const SizedBox(height: 12),
          _PlaybackList(
            options: _activeOptions,
            onPlay: (option) => widget.onPlay(_media, option),
          ),
        ] else if (widget.repository != null) ...[
          const SizedBox(height: 28),
          _buildEpisodesHeader(context),
          const SizedBox(height: 12),
          const _InlineEmpty(message: '当前季暂无可播放剧集'),
        ],
        if (_tmdbDetails?.cast.isNotEmpty == true) ...[
          const SizedBox(height: 30),
          _CastSection(cast: _tmdbDetails!.cast),
        ],
      ],
    );
  }

  Widget _buildEpisodesHeader(
    BuildContext context, {
    bool isLoading = false,
  }) {
    final count = _activeEpisodes.length;
    return Row(
      children: [
        _sectionTitle('剧集'),
        const Spacer(),
        if (isLoading)
          const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else if (count > 0) ...[
          Text('$count 集',
              style: const TextStyle(color: CineoColors.textSecondary)),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: _openEpisodeLibrary,
            icon: const Icon(Icons.grid_view_rounded, size: 18),
            label: const Text('查看全部'),
          ),
        ],
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
          height: 184,
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
                      : _media.posterUrl);
              return SizedBox(
                width: 220,
                child: InkWell(
                  key: ValueKey('preview-${episode.id}'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: episode.playbackOption == null
                      ? null
                      : () {
                          widget.onPlay(_media, episode.playbackOption!);
                        },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AspectRatio(
                        key: ValueKey('preview-image-${episode.id}'),
                        aspectRatio: 16 / 9,
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
      ],
    );
  }

  void _openEpisodeLibrary() {
    Navigator.of(context).push<void>(
      adaptivePageRoute(
        context,
        builder: (_) => EpisodeLibraryScreen(
          media: _media,
          episodes: _activeEpisodes,
          tmdbSeason: _selectedTmdbSeason,
          fallbackPosterUrl: _media.posterUrl,
          onPlay: (option) => widget.onPlay(_media, option),
        ),
      ),
    );
  }

  Future<void> _searchOtherSources() async {
    final finder = widget.onSearchOtherSources;
    if (finder == null) return;
    setState(() => _searchingOtherSources = true);
    try {
      final matches = await finder(_media);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        backgroundColor: CineoColors.surface,
        builder: (context) => _OtherSourcesSheet(
          matches: <MediaItem>[_media, ...matches],
          activeSourceId: _media.sourceId,
          onOpen: (media) async {
            Navigator.of(context).pop();
            if (media.sourceId != _media.sourceId) {
              await _switchAlternative(media);
            }
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

  Future<void> _switchAlternative(MediaItem alternative) async {
    final loader = widget.onLoadAlternative;
    if (loader == null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _searchingOtherSources = true);
    try {
      final loaded = await loader(alternative);
      if (!mounted || loaded == null) return;
      setState(() {
        _media = loaded;
        _selectedSourceName = null;
        final seasons = _sourceSeasons;
        _selectedSeason = seasons.isEmpty ? null : seasons.first;
      });
      messenger.showSnackBar(
        SnackBar(content: Text('已切换到${_siteDisplayName(loaded)}')),
      );
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('切换资源站失败，请稍后重试')),
        );
      }
    } finally {
      if (mounted) setState(() => _searchingOtherSources = false);
    }
  }

  Widget _sectionTitle(String title) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 3,
          height: 18,
          decoration: BoxDecoration(
            color: CineoColors.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      ],
    );
  }

  Widget _buildDescriptionActions() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.onSearchTmdbMatches != null &&
            widget.onSelectTmdbMatch != null)
          IconButton(
            tooltip: '手动匹配',
            onPressed: _tmdbLoading ? null : _openManualTmdbMatch,
            icon: const Icon(Icons.manage_search_rounded),
          ),
        IconButton(
          tooltip: _favorite ? '取消收藏' : '收藏',
          onPressed: () {
            setState(() {
              _favoriteChangedByUser = true;
              _favorite = !_favorite;
            });
            widget.onFavoriteChanged(_media, _favorite);
          },
          icon: Icon(_favorite
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded),
        ),
      ],
    );
  }
}

class _InfoBadge extends StatelessWidget {
  const _InfoBadge({
    required this.icon,
    required this.label,
    this.color = CineoColors.textSecondary,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: color == CineoColors.primary
                ? FontWeight.w800
                : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _DescriptionSection extends StatefulWidget {
  const _DescriptionSection({required this.description, this.trailing});

  final String description;
  final Widget? trailing;

  @override
  State<_DescriptionSection> createState() => _DescriptionSectionState();
}

class _DescriptionSectionState extends State<_DescriptionSection> {
  static const _collapsedLineLimit = 5;
  bool _expanded = false;

  String get _formattedDescription =>
      formatMediaDescription(widget.description);

  bool get _isLong {
    final text = _formattedDescription;
    return text.length > 200 || '\n'.allMatches(text).length >= 5;
  }

  @override
  Widget build(BuildContext context) {
    final description = _formattedDescription;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('简介',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const Spacer(),
            if (widget.trailing != null) widget.trailing!,
          ],
        ),
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

class _CastSection extends StatelessWidget {
  const _CastSection({required this.cast});

  final List<TmdbCastMember> cast;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('cast-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('演员',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        SizedBox(
          height: 146,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: cast.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final member = cast[index];
              return SizedBox(
                width: 82,
                child: Column(
                  children: [
                    ClipOval(
                      child: SizedBox.square(
                        dimension: 76,
                        child: MediaImage(
                          url: member.profileUrl,
                          placeholderIcon: Icons.person_outline_rounded,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      member.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (member.character.isNotEmpty)
                      Text(
                        member.character,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          color: CineoColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

String _lineName(PlaybackOption option) {
  final name = option.quality.trim();
  return name.isEmpty ? '播放源' : name;
}

String _siteDisplayName(MediaItem media) {
  final name = media.sourceName?.trim() ?? '';
  if (name.isNotEmpty) return name;
  final sourceId = media.sourceId?.trim() ?? '';
  return sourceId.isEmpty ? '当前资源站' : sourceId;
}

class _SiteSwitchTile extends StatelessWidget {
  const _SiteSwitchTile({
    required this.sourceName,
    required this.isLoading,
    required this.onTap,
  });

  final String sourceName;
  final bool isLoading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CineoColors.surfaceElevated,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        key: const ValueKey('switch-media-site'),
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.dns_rounded, color: CineoColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '资源站',
                      style: TextStyle(
                        color: CineoColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sourceName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              if (isLoading)
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(
                  Icons.swap_horiz_rounded,
                  color: CineoColors.primaryLight,
                ),
            ],
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
    return SizedBox(
      height: 50,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: sourceNames.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final name = sourceNames[index];
          final selected = name == selectedSourceName;
          return Semantics(
            selected: selected,
            button: true,
            label: '播放来源 $name',
            child: Material(
              color: selected
                  ? CineoColors.primary.withOpacity(.16)
                  : CineoColors.surface,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                key: ValueKey('source-$name'),
                borderRadius: BorderRadius.circular(8),
                onTap: () => onChanged(name),
                child: Container(
                  constraints: const BoxConstraints(minWidth: 116),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected
                          ? CineoColors.primary
                          : CineoColors.textSecondary.withOpacity(.22),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        selected
                            ? Icons.play_circle_filled_rounded
                            : Icons.play_circle_outline_rounded,
                        size: 20,
                        color: selected
                            ? CineoColors.primary
                            : CineoColors.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w600,
                            color: selected
                                ? CineoColors.textPrimary
                                : CineoColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
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

class _EpisodeLoadingPlaceholder extends StatefulWidget {
  const _EpisodeLoadingPlaceholder();

  @override
  State<_EpisodeLoadingPlaceholder> createState() =>
      _EpisodeLoadingPlaceholderState();
}

class _EpisodeLoadingPlaceholderState extends State<_EpisodeLoadingPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      key: const ValueKey('episode-loading'),
      opacity: Tween<double>(begin: .45, end: 1).animate(_controller),
      child: SizedBox(
        height: 184,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: 3,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, index) => const SizedBox(
            width: 220,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: CineoColors.surface,
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
                SizedBox(height: 6),
                SizedBox(
                  width: 110,
                  height: 16,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: CineoColors.surface,
                      borderRadius: BorderRadius.all(Radius.circular(4)),
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

class _OtherSourcesSheet extends StatelessWidget {
  const _OtherSourcesSheet({
    required this.matches,
    required this.activeSourceId,
    required this.onOpen,
  });

  final List<MediaItem> matches;
  final String? activeSourceId;
  final ValueChanged<MediaItem> onOpen;

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(24, 8, 24, 40),
        child: Text('已搜索所有已启用的视频源，暂未找到匹配内容。'),
      );
    }
    final sites = <String, MediaItem>{};
    for (final media in matches) {
      final sourceId = media.sourceId?.trim() ?? '';
      if (sourceId.isNotEmpty) sites.putIfAbsent(sourceId, () => media);
    }
    final orderedSites = sites.values.toList()
      ..sort((left, right) {
        final leftActive = left.sourceId == activeSourceId;
        final rightActive = right.sourceId == activeSourceId;
        if (leftActive == rightActive) return 0;
        return leftActive ? -1 : 1;
      });
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .76,
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                '选择资源站',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: Text(
                '切换后会记住此剧集的最近选择，并优先使用该站点播放。',
                style: TextStyle(color: CineoColors.textSecondary),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                itemCount: orderedSites.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final media = orderedSites[index];
                  return _SourceSiteCard(
                    media: media,
                    selected: media.sourceId == activeSourceId,
                    onTap: () => onOpen(media),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceSiteCard extends StatelessWidget {
  const _SourceSiteCard({
    required this.media,
    required this.selected,
    required this.onTap,
  });

  final MediaItem media;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final detail = <String>[
      if (media.year > 0) '${media.year}',
      if (media.category?.trim().isNotEmpty == true) media.category!.trim(),
    ].join('  ·  ');
    return Material(
      color:
          selected ? CineoColors.primaryContainer : CineoColors.surfaceElevated,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: ValueKey('media-site-${media.sourceId}'),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? CineoColors.primary : CineoColors.divider,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 58,
                height: 78,
                child: MediaImage(
                  url: media.posterUrl,
                  borderRadius: BorderRadius.circular(6),
                  placeholderIcon: Icons.movie_outlined,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      media.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: CineoColors.surfaceOverlay,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        _siteDisplayName(media),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: CineoColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (detail.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: CineoColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle_rounded,
                  color: CineoColors.primary,
                  size: 30,
                )
              else
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
}

class _ManualTmdbMatchDialog extends StatefulWidget {
  const _ManualTmdbMatchDialog({
    required this.initialQuery,
    required this.initialYear,
    required this.initialType,
    required this.onSearch,
  });

  final String initialQuery;
  final int? initialYear;
  final TmdbMediaType initialType;
  final Future<List<TmdbMediaMatch>> Function(
      String query, TmdbMediaType? type, int? year) onSearch;

  @override
  State<_ManualTmdbMatchDialog> createState() => _ManualTmdbMatchDialogState();
}

class _ManualTmdbMatchDialogState extends State<_ManualTmdbMatchDialog> {
  late final TextEditingController _queryController =
      TextEditingController(text: widget.initialQuery);
  late final TextEditingController _yearController = TextEditingController(
      text: widget.initialYear == null ? '' : '${widget.initialYear}');
  late TmdbMediaType _type = widget.initialType;
  List<TmdbMediaMatch> _matches = const [];
  bool _loading = false;
  String? _errorMessage;
  bool _hasSearched = false;

  @override
  void dispose() {
    _queryController.dispose();
    _yearController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) {
      setState(() => _errorMessage = '请输入影片或剧集名称');
      return;
    }
    final yearText = _yearController.text.trim();
    final year = yearText.isEmpty ? null : int.tryParse(yearText);
    if (yearText.isNotEmpty && (year == null || year < 1800 || year > 2200)) {
      setState(() => _errorMessage = '请输入有效的年份');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _errorMessage = null;
      _hasSearched = true;
    });
    try {
      final matches = await widget.onSearch(query, _type, year);
      if (!mounted) return;
      setState(() => _matches = matches);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _matches = const [];
        _errorMessage = '搜索失败，请稍后重试';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('手动匹配'),
      content: SizedBox(
        width: 560,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 620),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _queryController,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                decoration: const InputDecoration(
                  labelText: '影片或剧集名称',
                  prefixIcon: Icon(Icons.title_rounded),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<TmdbMediaType>(
                      value: _type,
                      decoration: const InputDecoration(
                        labelText: '类型',
                        prefixIcon: Icon(Icons.category_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: TmdbMediaType.movie,
                          child: Text('电影'),
                        ),
                        DropdownMenuItem(
                          value: TmdbMediaType.tv,
                          child: Text('剧集'),
                        ),
                      ],
                      onChanged: _loading
                          ? null
                          : (value) {
                              if (value != null) setState(() => _type = value);
                            },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _yearController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _search(),
                      decoration: const InputDecoration(
                        labelText: '年份（可选）',
                        prefixIcon: Icon(Icons.calendar_today_outlined),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _loading ? null : _search,
                icon: _loading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search_rounded),
                label: Text(_loading ? '搜索中...' : '搜索匹配项'),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (_loading) ...[
                const SizedBox(height: 14),
                const LinearProgressIndicator(minHeight: 2),
              ],
              if (!_loading &&
                  _hasSearched &&
                  _matches.isEmpty &&
                  _errorMessage == null) ...[
                const SizedBox(height: 18),
                const Center(
                  child: Text('没有找到匹配内容',
                      style: TextStyle(color: CineoColors.textSecondary)),
                ),
              ],
              if (_matches.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Text('选择匹配结果',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _matches.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: CineoColors.divider),
                    itemBuilder: (context, index) {
                      final match = _matches[index];
                      return _TmdbMatchTile(
                        match: match,
                        onTap: () => Navigator.of(context).pop(match),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }
}

class _TmdbMatchTile extends StatelessWidget {
  const _TmdbMatchTile({required this.match, required this.onTap});

  final TmdbMediaMatch match;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final year = match.year == null ? '' : '${match.year}';
    final details = [
      if (match.originalTitle.trim().isNotEmpty) match.originalTitle.trim(),
      if (year.isNotEmpty) year,
      if (match.rating > 0) '${match.rating.toStringAsFixed(1)} 分',
    ].join('  ·  ');
    final poster =
        match.posterUrl.trim().isNotEmpty ? match.posterUrl : match.backdropUrl;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 56,
              height: 82,
              child: MediaImage(
                url: poster,
                borderRadius: BorderRadius.circular(6),
                placeholderIcon: Icons.movie_outlined,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    match.title.trim().isEmpty ? '未命名' : match.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(details,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: CineoColors.textSecondary, fontSize: 12)),
                  ],
                  const SizedBox(height: 8),
                  Text(match.mediaType == TmdbMediaType.tv ? '剧集' : '电影',
                      style: const TextStyle(
                          color: CineoColors.primary, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}
