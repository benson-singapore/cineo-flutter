import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'core/models/media.dart';
import 'core/models/home_category_rail.dart';
import 'core/models/tmdb_media.dart';
import 'core/platform/adaptive_navigation.dart';
import 'core/platform/picture_in_picture.dart';
import 'core/theme/cineo_theme.dart';
import 'data/cache/tmdb_disk_cache.dart';
import 'data/remote/tmdb_client.dart';
import 'data/repositories/local_media_repository.dart';
import 'data/repositories/tmdb_metadata_repository.dart';
import 'data/remote/media_category_adapter.dart';
import 'features/app_lock/app_lock.dart';
import 'features/home/home_screen.dart';
import 'features/library/library_screen.dart';
import 'features/media_details/media_details_screen.dart';
import 'features/player/player_screen.dart';
import 'features/profile/profile.dart';
import 'features/search/search_screen.dart';
import 'features/search/category_browse_screen.dart';
import 'features/settings/adult_source_settings.dart';
import 'features/settings/settings_screen.dart';
import 'features/settings/tmdb_settings.dart';
import 'features/settings/tmdb_disk_cache_controller.dart';
import 'features/sources/source_list_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CineoApp());
}

class CineoApp extends StatefulWidget {
  const CineoApp({super.key});

  @override
  State<CineoApp> createState() => _CineoAppState();
}

class _CineoAppState extends State<CineoApp> {
  final _appLockController = AppLockController();
  final _adultSourceSettings = AdultSourceSettings();
  final _tmdbSettings = TMDBSettings();
  final _tmdbCache = TmdbDiskCache();
  late final _tmdbCacheController = TmdbDiskCacheController(cache: _tmdbCache);
  late final _tmdbMetadata = TmdbMetadataRepository(
    cache: _tmdbCache,
    readToken: _tmdbSettings.readTokenForRequest,
    retention: () => Duration(days: _tmdbCacheController.retentionDays),
  );
  final _repository = createDemoLocalMediaRepository();

  @override
  void initState() {
    super.initState();
    unawaited(_adultSourceSettings.initialize());
    unawaited(_tmdbSettings.initialize());
    unawaited(_tmdbCacheController.initialize());
  }

  @override
  void dispose() {
    _appLockController.dispose();
    unawaited(_repository.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cineo',
      debugShowCheckedModeBanner: false,
      theme: buildCineoTheme(),
      home: AppLockGate(
        controller: _appLockController,
        child: CineoShell(
          repository: _repository,
          appLockController: _appLockController,
          adultSourceSettings: _adultSourceSettings,
          tmdbSettings: _tmdbSettings,
          tmdbMetadata: _tmdbMetadata,
          tmdbCacheController: _tmdbCacheController,
        ),
      ),
    );
  }
}

class CineoShell extends StatefulWidget {
  const CineoShell({
    super.key,
    required this.repository,
    required this.appLockController,
    required this.adultSourceSettings,
    required this.tmdbSettings,
    required this.tmdbMetadata,
    required this.tmdbCacheController,
  });

  final LocalMediaRepository repository;
  final AppLockController appLockController;
  final AdultSourceSettings adultSourceSettings;
  final TMDBSettings tmdbSettings;
  final TmdbMetadataRepository tmdbMetadata;
  final TmdbDiskCacheController tmdbCacheController;

  @override
  State<CineoShell> createState() => _CineoShellState();
}

class _CineoShellState extends State<CineoShell> {
  static const _pictureInPicture = PictureInPictureService();

  List<MediaItem> _items = const [];
  List<HomeCategoryRail> _homeCategoryRails = const [];
  List<MediaItem> _continueWatching = const [];
  List<MediaItem> _favorites = const [];
  List<String> _searchHistory = const [];
  Map<String, double> _progressByMediaId = const {};
  List<UnifiedCategory> _categories = const [];
  bool _loading = true;
  bool _refreshing = false;
  String? _errorMessage;
  int _selectedIndex = 0;
  int _refreshRevision = 0;
  bool _pictureInPictureAvailable = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    unawaited(_loadPlatformCapabilities());
  }

  Future<void> _loadPlatformCapabilities() async {
    final available = await _pictureInPicture.isAvailable();
    if (mounted) setState(() => _pictureInPictureAvailable = available);
  }

  Future<void> _refresh({bool preserveContent = true}) async {
    final revision = ++_refreshRevision;
    final stopwatch = Stopwatch()..start();
    final showCachedContent = preserveContent && _homeCategoryRails.isNotEmpty;
    _debugLog(
      'home_refresh phase=start revision=$revision',
    );
    if (mounted) {
      setState(() {
        _loading = !showCachedContent;
        _refreshing = showCachedContent;
        if (!showCachedContent) _errorMessage = null;
      });
    }
    try {
      final categories = await widget.repository.defaultSourceCategories();
      if (!mounted || revision != _refreshRevision) return;
      final railsFuture = widget.repository.browseDefaultHomeCategoryRails(
        categories,
      );
      final progressFuture = widget.repository.watchHistory();
      final historyFuture = widget.repository.searchHistory();
      final favoritesFuture = widget.repository.favorites();
      final results = await Future.wait([
        railsFuture,
        progressFuture,
        historyFuture,
        favoritesFuture,
      ]);
      final rails = results[0] as List<HomeCategoryRail>;
      final items = rails.expand((rail) => rail.items).toList(growable: false);
      final progress = results[1] as List<WatchProgress>;
      final history = results[2] as List<String>;
      final favorites = results[3] as List<MediaItem>;
      final historyMedia = await Future.wait(
        progress.map((entry) => widget.repository.getById(entry.mediaId)),
      );
      final byId = <String, MediaItem>{
        for (final item in historyMedia.whereType<MediaItem>()) item.id: item,
      };
      if (!mounted || revision != _refreshRevision) return;
      stopwatch.stop();
      _debugLog(
        'home_refresh phase=complete revision=$revision '
        'elapsedMs=${stopwatch.elapsedMilliseconds} rails=${rails.length} '
        'items=${items.length} '
        'progress=${progress.length} searchHistory=${history.length}',
      );
      setState(() {
        _items = items;
        _homeCategoryRails = rails;
        _categories = categories;
        _continueWatching = [
          for (final entry in progress)
            if (!entry.isComplete && byId[entry.mediaId] != null)
              byId[entry.mediaId]!,
        ];
        _favorites = favorites;
        _progressByMediaId = {
          for (final entry in progress) entry.mediaId: entry.fraction,
        };
        _searchHistory = history;
        _loading = false;
        _refreshing = false;
        _errorMessage = null;
      });
    } catch (error, stackTrace) {
      stopwatch.stop();
      _debugError(
        'home_refresh phase=failed revision=$revision '
        'elapsedMs=${stopwatch.elapsedMilliseconds}',
        error,
        stackTrace,
      );
      if (!mounted || revision != _refreshRevision) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        if (!showCachedContent) _errorMessage = _homeLoadError(error);
      });
    }
  }

  String _homeLoadError(Object error) {
    final detail = error.toString().replaceFirst('Exception: ', '').trim();
    if (detail.contains('请求超时')) {
      return '默认视频源请求超时，请在视频源中执行连通性测试后重试';
    }
    if (detail.contains('HTTP')) {
      return '默认视频源返回了访问错误，请检查 API 地址和站点状态';
    }
    if (detail.contains('JSON') || detail.contains('响应格式')) {
      return '默认视频源未返回兼容的 JSON 数据，请检查站点接口类型';
    }
    return '默认视频源无法加载，请检查连通性和配置';
  }

  Future<void> _recordSearch(String query) async {
    await widget.repository.addSearchHistory(query);
    await _refresh();
  }

  Future<void> _openMedia(
    MediaItem media, {
    MediaItem? preferenceAnchor,
    bool skipPreferredSource = false,
  }) async {
    final anchor = preferenceAnchor ?? media;
    MediaItem selectedMedia = media;
    if (!skipPreferredSource) {
      final preferred = await widget.repository.preferredSourceFor(
        anchor,
        includeAdult: widget.adultSourceSettings.showAdultSources,
      );
      if (preferred != null) selectedMedia = preferred;
    }
    final resolvedMedia = await _resolveMediaDetails(selectedMedia);
    final favorite = await widget.repository.isFavorite(resolvedMedia.id);
    final history = await widget.repository.watchHistory();
    final recentEpisodeId = history
        .where((entry) => entry.mediaId == resolvedMedia.id)
        .map((entry) => entry.episodeId)
        .whereType<String>()
        .firstWhere(
          (episodeId) => resolvedMedia.playbackOptions
              .any((option) => option.id == episodeId),
          orElse: () => '',
        );
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      adaptivePageRoute(
        context,
        builder: (_) => MediaDetailsScreen(
          media: resolvedMedia,
          initialEpisodeId: recentEpisodeId.isEmpty ? null : recentEpisodeId,
          favorite: favorite,
          onFavoriteChanged: (favoriteMedia, isFavorite) {
            unawaited(widget.repository.setFavorite(favoriteMedia, isFavorite));
            unawaited(_refresh());
          },
          onPlay: (playingMedia, option) =>
              unawaited(_openPlayer(playingMedia, option)),
          onLoadTmdbDetails: _loadTmdbDetails,
          onSearchTmdbMatches: _searchTmdbMatches,
          onSelectTmdbMatch: (match) => _selectTmdbMatch(resolvedMedia, match),
          onSearchOtherSources: (item) => widget.repository.searchOtherSources(
            item,
            includeAdult: widget.adultSourceSettings.showAdultSources,
          ),
          onLoadAlternative: (alternative) async {
            await widget.repository.savePreferredSource(anchor, alternative);
            return _resolveMediaDetails(alternative);
          },
        ),
      ),
    );
    await _refresh();
  }

  Future<MediaItem> _resolveMediaDetails(MediaItem media) async {
    MediaItem resolvedMedia = media;
    try {
      resolvedMedia = await widget.repository.loadDetails(media) ?? media;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('详情加载失败，请检查视频源连通性')),
        );
      }
    }
    return resolvedMedia;
  }

  Future<void> _resumeMedia(MediaItem media) async {
    final resolvedMedia = await _resolveMediaDetails(media);
    final history = await widget.repository.watchHistory();
    PlaybackOption? selectedOption;
    for (final entry in history) {
      if (entry.mediaId != resolvedMedia.id || entry.episodeId == null) {
        continue;
      }
      for (final option in resolvedMedia.playbackOptions) {
        if (option.id == entry.episodeId) {
          selectedOption = option;
          break;
        }
      }
      if (selectedOption != null) break;
    }
    selectedOption ??= resolvedMedia.playbackOptions.firstOrNull;
    if (!mounted) return;
    if (selectedOption == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂时无法恢复此视频的播放地址')),
      );
      return;
    }
    await _openPlayer(resolvedMedia, selectedOption);
  }

  Future<TmdbMediaDetails?> _loadTmdbDetails(MediaItem media) async {
    final mediaType =
        media.kind == MediaKind.series ? TmdbMediaType.tv : TmdbMediaType.movie;
    try {
      final details = await widget.tmdbMetadata.loadForMedia(media);
      _debugLog(
        'tmdb_details phase=complete type=${mediaType.name} '
        'matched=${details != null}',
      );
      return details;
    } on TmdbApiException catch (error) {
      _debugLog(
        'tmdb_details phase=unavailable kind=${error.kind.name} '
        'type=${mediaType.name}',
      );
      return null;
    } on Object catch (error) {
      _debugLog(
        'tmdb_details phase=failed errorType=${error.runtimeType} '
        'type=${mediaType.name}',
      );
      return null;
    }
  }

  Future<List<TmdbMediaMatch>> _searchTmdbMatches(
    String query,
    TmdbMediaType? type,
    int? year,
  ) async {
    return widget.tmdbMetadata.search(query, type, year);
  }

  Future<TmdbMediaDetails?> _selectTmdbMatch(
    MediaItem media,
    TmdbMediaMatch match,
  ) async {
    try {
      final details = await widget.tmdbMetadata.selectForMedia(media, match);
      _debugLog(
        'tmdb_details phase=manual_match type=${match.mediaType.name} '
        'matched=${details != null}',
      );
      return details;
    } on TmdbApiException catch (error) {
      _debugLog(
        'tmdb_details phase=manual_unavailable kind=${error.kind.name} '
        'type=${match.mediaType.name}',
      );
      return null;
    } on Object catch (error) {
      _debugLog(
        'tmdb_details phase=manual_failed errorType=${error.runtimeType} '
        'type=${match.mediaType.name}',
      );
      return null;
    }
  }

  Future<void> _openPlayer(MediaItem media, PlaybackOption option) async {
    final history = await widget.repository.watchHistory();
    final episodePositions = <String, Duration>{
      for (final entry in history)
        if (entry.mediaId == media.id && entry.episodeId != null)
          entry.episodeId!: entry.position,
    };
    final lineName = option.quality.trim();
    final lineEpisodes = media.playbackOptions
        .where((candidate) => candidate.quality.trim() == lineName)
        .toList(growable: false);
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      adaptivePageRoute(
        context,
        builder: (_) => PlayerScreen(
          media: media,
          option: option,
          episodes: lineEpisodes,
          initialPosition: episodePositions[option.id] ?? Duration.zero,
          initialPositions: episodePositions,
          episodeId: option.id,
          pictureInPictureAvailable: _pictureInPictureAvailable,
          onPictureInPicture: _pictureInPictureAvailable
              ? () => unawaited(_enterPictureInPicture())
              : null,
          onProgressChanged: (playingMedia, progress) => unawaited(
            widget.repository.saveProgress(progress, media: playingMedia),
          ),
          onSearchOtherSources: (item) => widget.repository.searchOtherSources(
            item,
            includeAdult: widget.adultSourceSettings.showAdultSources,
          ),
          onLoadAlternative: (alternative) async {
            await widget.repository.savePreferredSource(media, alternative);
            return _resolveMediaDetails(alternative);
          },
        ),
      ),
    );
    await _refresh();
  }

  Future<void> _enterPictureInPicture() async {
    final entered = await _pictureInPicture.enter();
    if (!entered && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前设备无法进入画中画模式')),
      );
    }
  }

  Future<void> _openCategoryBrowse(
    String title,
    List<MediaItem> initialItems,
    List<String> categoryIds,
  ) {
    return Navigator.of(context).push<void>(
      adaptivePageRoute(
        context,
        builder: (_) => CategoryBrowseScreen(
          title: title,
          initialItems: initialItems,
          onOpenMedia: (media) => unawaited(_openMedia(media)),
          onLoad: (page) => widget.repository.browseDefaultSourcePage(
            categoryIds: categoryIds,
            page: page,
          ),
        ),
      ),
    );
  }

  Future<void> _openSearch() {
    return Navigator.of(context).push<void>(
      adaptivePageRoute(
        context,
        builder: (_) => SearchScreen(
          items: _items,
          history: _searchHistory,
          onSearch: (query) => unawaited(_recordSearch(query)),
          onOpenMedia: (media) => unawaited(_openMedia(media)),
          categories: _categories,
          onRemoteSearch: (query, categoryIds, page) =>
              widget.repository.searchDefaultSourcePage(
            query,
            categoryIds: categoryIds,
            page: page,
          ),
          onBrowseCategory: (categoryIds, page) =>
              widget.repository.browseDefaultSourcePage(
            categoryIds: categoryIds,
            page: page,
          ),
        ),
      ),
    );
  }

  Future<void> _openLibrary(LibraryContentMode mode) async {
    await Navigator.of(context).push<void>(
      adaptivePageRoute(
        context,
        builder: (_) => LibraryScreen(
          repository: widget.repository,
          mode: mode,
          onMediaTap: (media) => unawaited(_openMedia(media)),
        ),
      ),
    );
    await _refresh();
  }

  Future<void> _openSources() async {
    await Navigator.of(context).push<void>(
      adaptivePageRoute(
        context,
        builder: (_) => SourceListScreen(
          repository: widget.repository,
          adultSourceSettings: widget.adultSourceSettings,
        ),
      ),
    );
    await _refresh();
  }

  Future<void> _openPinSetup() async {
    await Navigator.of(context).push<void>(
      adaptivePageRoute(
        context,
        builder: (_) => PinSetupScreen(controller: widget.appLockController),
      ),
    );
  }

  Future<void> _openSettings() {
    return Navigator.of(context).push<void>(
      adaptivePageRoute(
        context,
        builder: (_) => SettingsScreen(
          adultSourceSettings: widget.adultSourceSettings,
          appLockController: widget.appLockController,
          tmdbSettings: widget.tmdbSettings,
          tmdbCacheController: widget.tmdbCacheController,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(
        items: _items,
        continueWatching: _continueWatching,
        favorites: _favorites,
        progressByMediaId: _progressByMediaId,
        categoryRails: _homeCategoryRails,
        isLoading: _loading,
        isRefreshing: _refreshing,
        errorMessage: _errorMessage,
        onRetry: _refresh,
        onRefresh: _refresh,
        onOpenMedia: (media) => unawaited(_openMedia(media)),
        onContinueWatching: (media) => unawaited(_resumeMedia(media)),
        onSeeAll: (title, items, categoryIds) =>
            unawaited(_openCategoryBrowse(title, items, categoryIds)),
      ),
      SearchScreen(
        items: _items,
        history: _searchHistory,
        onSearch: (query) => unawaited(_recordSearch(query)),
        onOpenMedia: (media) => unawaited(_openMedia(media)),
        categories: _categories,
        onRemoteSearch: (query, categoryIds, page) =>
            widget.repository.searchDefaultSourcePage(
          query,
          categoryIds: categoryIds,
          page: page,
        ),
        onBrowseCategory: (categoryIds, page) =>
            widget.repository.browseDefaultSourcePage(
          categoryIds: categoryIds,
          page: page,
        ),
        libraryMode: true,
        onOpenSearch: () => unawaited(_openSearch()),
      ),
      ProfileScreen(
        appLockController: widget.appLockController,
        onOpenFavorites: () =>
            unawaited(_openLibrary(LibraryContentMode.favorites)),
        onOpenHistory: () =>
            unawaited(_openLibrary(LibraryContentMode.history)),
        onOpenSources: () => unawaited(_openSources()),
        onOpenAppLock: () => unawaited(_openPinSetup()),
        onLockNow: () => unawaited(widget.appLockController.lock()),
        onOpenSettings: () => unawaited(_openSettings()),
      ),
    ];
    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _selectedIndex, children: pages),
      bottomNavigationBar: _GlassBottomNavigation(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
      ),
    );
  }
}

class _GlassBottomNavigation extends StatelessWidget {
  const _GlassBottomNavigation({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  static const _destinations = [
    _GlassNavigationDestination(
      label: '首页',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
    ),
    _GlassNavigationDestination(
      label: '片库',
      icon: Icons.video_library_outlined,
      selectedIcon: Icons.video_library_rounded,
    ),
    _GlassNavigationDestination(
      label: '我的',
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isIos = Theme.of(context).platform == TargetPlatform.iOS;
    const borderRadius = BorderRadius.all(Radius.circular(30));
    return SafeArea(
      top: false,
      minimum: isIos
          ? const EdgeInsets.fromLTRB(16, 8, 16, 6)
          : const EdgeInsets.fromLTRB(20, 8, 20, 10),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: isIos ? 26 : 18,
            sigmaY: isIos ? 26 : 18,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: CineoColors.glass.withOpacity(isIos ? .78 : .9),
              borderRadius: borderRadius,
              border: Border.all(
                color: Colors.white.withOpacity(isIos ? .18 : .12),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isIos ? .3 : .38),
                  blurRadius: isIos ? 30 : 26,
                  offset: Offset(0, isIos ? 12 : 10),
                ),
              ],
            ),
            child: SizedBox(
              height: isIos ? 64 : 68,
              child: Row(
                children: List.generate(_destinations.length, (index) {
                  final destination = _destinations[index];
                  return Expanded(
                    child: _GlassNavigationItem(
                      destination: destination,
                      selected: selectedIndex == index,
                      onTap: () => onDestinationSelected(index),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassNavigationItem extends StatelessWidget {
  const _GlassNavigationItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _GlassNavigationDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground =
        selected ? CineoColors.primaryLight : CineoColors.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: const BorderRadius.all(Radius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: selected
                    ? CineoColors.primary.withOpacity(.16)
                    : Colors.transparent,
                borderRadius: const BorderRadius.all(Radius.circular(22)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    selected ? destination.selectedIcon : destination.icon,
                    color: foreground,
                    size: 24,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    destination.label,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassNavigationDestination {
  const _GlassNavigationDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

void _debugLog(String message) {
  assert(() {
    debugPrint('[Cineo][App] $message');
    return true;
  }());
}

void _debugError(
  String message,
  Object error,
  StackTrace stackTrace,
) {
  assert(() {
    debugPrint('[Cineo][App] $message error=${error.runtimeType}: $error');
    debugPrintStack(
      label: '[Cineo][App] stack',
      stackTrace: stackTrace,
      maxFrames: 12,
    );
    return true;
  }());
}
