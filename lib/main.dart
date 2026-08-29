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
import 'features/settings/m3u8_filter_settings.dart';
import 'features/settings/settings_screen.dart';
import 'features/settings/tmdb_settings.dart';
import 'features/settings/tmdb_disk_cache_controller.dart';
import 'features/sources/source_list_screen.dart';
import 'features/update/app_update_service.dart';
import 'features/update/app_update_screen.dart';

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
  final _m3u8FilterSettings = M3u8FilterSettings();
  final _tmdbSettings = TMDBSettings();
  final _tmdbCache = TmdbDiskCache();
  final _updateService = AppUpdateService();
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
    unawaited(_m3u8FilterSettings.initialize());
    unawaited(_tmdbSettings.initialize());
    unawaited(_tmdbCacheController.initialize());
    unawaited(_updateService.initialize());
  }

  @override
  void dispose() {
    _appLockController.dispose();
    _updateService.dispose();
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
          m3u8FilterSettings: _m3u8FilterSettings,
          tmdbSettings: _tmdbSettings,
          tmdbMetadata: _tmdbMetadata,
          tmdbCacheController: _tmdbCacheController,
          updateService: _updateService,
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
    required this.m3u8FilterSettings,
    required this.tmdbSettings,
    required this.tmdbMetadata,
    required this.tmdbCacheController,
    required this.updateService,
  });

  final LocalMediaRepository repository;
  final AppLockController appLockController;
  final AdultSourceSettings adultSourceSettings;
  final M3u8FilterSettings m3u8FilterSettings;
  final TMDBSettings tmdbSettings;
  final TmdbMetadataRepository tmdbMetadata;
  final TmdbDiskCacheController tmdbCacheController;
  final AppUpdateService updateService;

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
  bool _showHomeScrollToTop = false;
  bool _showLibraryScrollToTop = false;
  final _homeScrollController = ScrollController();
  final _libraryScrollController = ScrollController();

  // Stream to notify LibraryScreen when default source changes
  late final StreamController<void> _sourceChangedController =
      StreamController<void>.broadcast();

  @override
  void initState() {
    super.initState();
    _refresh();
    unawaited(_loadPlatformCapabilities());
  }

  @override
  void dispose() {
    _homeScrollController.dispose();
    _libraryScrollController.dispose();
    _sourceChangedController.close();
    super.dispose();
  }

  Future<void> _loadPlatformCapabilities() async {
    final available = await _pictureInPicture.isAvailable();
    if (mounted) setState(() => _pictureInPictureAvailable = available);
  }

  Future<void> _refresh({bool preserveContent = true}) async {
    final revision = ++_refreshRevision;
    final stopwatch = Stopwatch()..start();
    final showCachedContent = preserveContent && _hasHomeContent;
    _debugLog(
      'home_refresh phase=start revision=$revision',
    );
    if (mounted) {
      setState(() {
        _loading = !showCachedContent;
        _refreshing = true;
        if (!showCachedContent) _errorMessage = null;
      });
    }
    final localStateFuture = _loadLocalHomeState();
    final remoteRailsFuture = _loadRemoteHomeState();
    try {
      final localState = await localStateFuture;
      if (!mounted || revision != _refreshRevision) return;
      setState(() {
        _applyLocalHomeState(localState);
        _loading = !_hasHomeContent;
        if (_hasHomeContent) _errorMessage = null;
      });
    } catch (error, stackTrace) {
      _debugError(
        'home_refresh phase=local_restore_failed revision=$revision',
        error,
        stackTrace,
      );
      if (!mounted || revision != _refreshRevision) return;
      setState(() {
        _loading = !_hasHomeContent;
      });
    }

    try {
      final remoteState = await remoteRailsFuture;
      if (!mounted || revision != _refreshRevision) return;
      await _saveHomeCache(remoteState.rails);
      if (!mounted || revision != _refreshRevision) return;
      final items = remoteState.rails
          .expand((rail) => rail.items)
          .toList(growable: false);
      stopwatch.stop();
      _debugLog(
        'home_refresh phase=complete revision=$revision '
        'elapsedMs=${stopwatch.elapsedMilliseconds} rails=${remoteState.rails.length} '
        'items=${items.length}',
      );
      setState(() {
        _items = items;
        _homeCategoryRails = remoteState.rails;
        _categories = remoteState.categories;
        _loading = false;
        _refreshing = false;
        _errorMessage = null;
      });
    } catch (error, stackTrace) {
      stopwatch.stop();
      _debugError(
        'home_refresh phase=remote_failed revision=$revision '
        'elapsedMs=${stopwatch.elapsedMilliseconds}',
        error,
        stackTrace,
      );
      if (!mounted || revision != _refreshRevision) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        if (!_hasHomeContent) _errorMessage = _homeLoadError(error);
      });
    }
  }

  Future<_LocalHomeState> _loadLocalHomeState() async {
    final results = await Future.wait([
      widget.repository.cachedHomeCategoryRails(),
      widget.repository.watchHistory(includeAdult: _includeAdultHistory),
      widget.repository.searchHistory(),
      widget.repository.favorites(),
    ]);
    final rails = results[0] as List<HomeCategoryRail>;
    final progress = results[1] as List<WatchProgress>;
    final history = results[2] as List<String>;
    final favorites = results[3] as List<MediaItem>;
    final historyMedia = await Future.wait(
      progress.map((entry) => widget.repository.getById(entry.mediaId)),
    );
    final byId = <String, MediaItem>{
      for (final item in historyMedia.whereType<MediaItem>()) item.id: item,
    };
    final continueWatching = [
      for (final entry in progress)
        if (!entry.isComplete && byId[entry.mediaId] != null)
          byId[entry.mediaId]!,
    ];
    if (continueWatching.isNotEmpty) {
      try {
        final details = await widget.tmdbMetadata.loadCachedForMedia(
          continueWatching.first,
        );
        final posterUrl = details?.posterUrl.trim() ?? '';
        if (posterUrl.isNotEmpty) {
          continueWatching[0] = continueWatching.first.copyWith(
            posterUrl: posterUrl,
          );
        }
      } on Object {
        // A cache read must not prevent the home screen from loading.
      }
    }
    return _LocalHomeState(
      rails: rails,
      progress: progress,
      history: history,
      favorites: favorites,
      continueWatching: continueWatching,
    );
  }

  Future<_RemoteHomeState> _loadRemoteHomeState() async {
    final categories = await widget.repository.defaultSourceCategories();
    final rails = await widget.repository.browseDefaultHomeCategoryRails(
      categories,
    );
    return _RemoteHomeState(categories: categories, rails: rails);
  }

  Future<void> _saveHomeCache(List<HomeCategoryRail> rails) async {
    try {
      await widget.repository.saveHomeCategoryRails(rails);
    } on Object catch (error, stackTrace) {
      _debugError('home_cache phase=save_failed', error, stackTrace);
    }
  }

  void _applyLocalHomeState(_LocalHomeState state) {
    _homeCategoryRails = state.rails;
    _items = state.rails.expand((rail) => rail.items).toList(growable: false);
    _continueWatching = state.continueWatching;
    _favorites = state.favorites;
    _progressByMediaId = {
      for (final entry in state.progress) entry.mediaId: entry.fraction,
    };
    _searchHistory = state.history;
  }

  bool get _hasHomeContent =>
      _items.isNotEmpty ||
      _continueWatching.isNotEmpty ||
      _favorites.isNotEmpty;

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

  bool get _includeAdultHistory =>
      widget.adultSourceSettings.showAdultSources &&
      !widget.adultSourceSettings.hideAdultHistory;

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

    // Resolve only the title-match preview before navigation. Detailed TMDB
    // metadata continues loading inside the destination page.
    final tmdbDetails =
        widget.tmdbSettings.configured ? await _loadTmdbPreview(media) : null;
    if (!mounted) return;

    final detailsRoute = Navigator.of(context).push<void>(
      adaptivePageRoute(
        context,
        builder: (_) => MediaDetailsScreen(
          media: media,
          initialTmdbDetails: tmdbDetails,
          initialEpisodeId: null,
          favorite: false,
          repository: widget.repository,
          includeAdultHistory: _includeAdultHistory,
          onLoadWatchHistory: () => widget.repository.watchHistory(
            includeAdult: _includeAdultHistory,
          ),
          onLoadMediaDetails: (item) async {
            if (!skipPreferredSource) {
              final preferred = await widget.repository.preferredSourceFor(
                anchor,
                includeAdult: widget.adultSourceSettings.showAdultSources,
              );
              if (preferred != null) return preferred;
            }
            return widget.repository.loadDetails(item);
          },
          onLoadFavorite: widget.repository.isFavorite,
          onFavoriteChanged: (favoriteMedia, isFavorite) {
            unawaited(widget.repository.setFavorite(favoriteMedia, isFavorite));
            unawaited(_refresh());
          },
          onPlay: (playingMedia, option) =>
              unawaited(_openPlayer(playingMedia, option)),
          onLoadTmdbDetails:
              widget.tmdbSettings.configured ? _loadTmdbDetails : null,
          onLoadTmdbEnrichment:
              widget.tmdbSettings.configured ? _loadTmdbEnrichment : null,
          onSearchTmdbMatches: _searchTmdbMatches,
          onSelectTmdbMatch: (match) => _selectTmdbMatch(media, match),
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
    unawaited(detailsRoute.then((_) => _refresh()));
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
    final history = await widget.repository.watchHistory(
      includeAdult: _includeAdultHistory,
    );
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

  Future<TmdbMediaDetails?> _loadTmdbPreview(MediaItem media) async {
    final mediaType =
        media.kind == MediaKind.series ? TmdbMediaType.tv : TmdbMediaType.movie;

    // Skip TMDB if default source is adult
    final defaultSource = await widget.repository.defaultSource();
    if (defaultSource?.isAdult ?? false) {
      _debugLog(
        'tmdb_preview phase=skipped reason=adult_default_source '
        'type=${mediaType.name}',
      );
      return null;
    }

    try {
      final details = await widget.tmdbMetadata.loadPreviewForMedia(media);
      _debugLog(
        'tmdb_preview phase=complete type=${mediaType.name} '
        'matched=${details != null}',
      );
      return details;
    } on TmdbApiException catch (error) {
      _debugLog(
        'tmdb_preview phase=unavailable kind=${error.kind.name} '
        'type=${mediaType.name}',
      );
      return null;
    } on Object catch (error) {
      _debugLog(
        'tmdb_preview phase=failed errorType=${error.runtimeType} '
        'type=${mediaType.name}',
      );
      return null;
    }
  }

  Future<TmdbMediaDetails?> _loadTmdbDetails(MediaItem media) async {
    final mediaType =
        media.kind == MediaKind.series ? TmdbMediaType.tv : TmdbMediaType.movie;

    // Skip TMDB if default source is adult
    final defaultSource = await widget.repository.defaultSource();
    if (defaultSource?.isAdult ?? false) {
      _debugLog(
        'tmdb_details phase=skipped reason=adult_default_source '
        'type=${mediaType.name}',
      );
      return null;
    }

    try {
      final details = await widget.tmdbMetadata.loadDetailsForMedia(media);
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

  Future<TmdbMediaDetails?> _loadTmdbEnrichment(MediaItem media) async {
    // Skip TMDB if default source is adult
    final defaultSource = await widget.repository.defaultSource();
    if (defaultSource?.isAdult ?? false) {
      _debugLog('tmdb_enrichment phase=skipped reason=adult_default_source');
      return null;
    }

    try {
      return await widget.tmdbMetadata.loadEnrichmentForMedia(media);
    } on Object catch (error) {
      _debugLog('tmdb_enrichment phase=failed errorType=${error.runtimeType}');
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
    final history = await widget.repository.watchHistory(
      includeAdult: _includeAdultHistory,
    );
    final mediaHistory = history
        .where((entry) => entry.mediaId == media.id)
        .toList(growable: false);
    final episodePositions = <String, Duration>{
      for (final entry in mediaHistory)
        if (entry.episodeId != null) entry.episodeId!: entry.position,
    };
    final moviePosition = mediaHistory
        .where((entry) => entry.episodeId == null)
        .firstOrNull
        ?.position;
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
          m3u8FilterSettings: widget.m3u8FilterSettings,
          episodes: lineEpisodes,
          initialPosition:
              episodePositions[option.id] ?? moviePosition ?? Duration.zero,
          initialPositions: episodePositions,
          episodeId: option.id,
          pictureInPictureAvailable: _pictureInPictureAvailable,
          onPictureInPicture:
              _pictureInPictureAvailable ? _enterPictureInPicture : null,
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

  Future<bool> _enterPictureInPicture(PictureInPictureRequest request) =>
      _pictureInPicture.enter(request);

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
          onOpenMedia: _openMedia,
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
          onOpenMedia: _openMedia,
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
          includeAdultHistory: _includeAdultHistory,
          onMediaTap: _openMedia,
          onSourceChanged: _sourceChangedController.stream,
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
          onDefaultSourceChanged: () => _sourceChangedController.add(null),
        ),
      ),
    );
    await _refresh();
  }

  Future<void> _openAppLockSettings() async {
    await Navigator.of(context).push<void>(
      adaptivePageRoute(
        context,
        builder: (_) => AppLockSettingsScreen(
          controller: widget.appLockController,
        ),
      ),
    );
  }

  Future<void> _openSettings() {
    return Navigator.of(context).push<void>(
      adaptivePageRoute(
        context,
        builder: (_) => SettingsScreen(
          adultSourceSettings: widget.adultSourceSettings,
          m3u8FilterSettings: widget.m3u8FilterSettings,
          appLockController: widget.appLockController,
          tmdbSettings: widget.tmdbSettings,
          tmdbCacheController: widget.tmdbCacheController,
        ),
      ),
    );
  }

  Future<void> _openUpdates() async {
    await Navigator.of(context).push<void>(
      adaptivePageRoute(
        context,
        builder: (_) => AppUpdateScreen(updateService: widget.updateService),
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
        onOpenMedia: _openMedia,
        onContinueWatching: _resumeMedia,
        onOpenSearch: () => unawaited(_openSearch()),
        onSeeAll: (title, items, categoryIds) =>
            unawaited(_openCategoryBrowse(title, items, categoryIds)),
        scrollController: _homeScrollController,
        onScrollToTopVisibilityChanged: (visible) {
          if (mounted && visible != _showHomeScrollToTop) {
            setState(() => _showHomeScrollToTop = visible);
          }
        },
      ),
      SearchScreen(
        items: _items,
        history: _searchHistory,
        onSearch: (query) => unawaited(_recordSearch(query)),
        onOpenMedia: _openMedia,
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
        scrollController: _libraryScrollController,
        onScrollToTopVisibilityChanged: (visible) {
          if (mounted && visible != _showLibraryScrollToTop) {
            setState(() => _showLibraryScrollToTop = visible);
          }
        },
      ),
      ProfileScreen(
        appLockController: widget.appLockController,
        onOpenFavorites: () =>
            unawaited(_openLibrary(LibraryContentMode.favorites)),
        onOpenHistory: () =>
            unawaited(_openLibrary(LibraryContentMode.history)),
        onOpenSources: () => unawaited(_openSources()),
        onOpenAppLock: () => unawaited(_openAppLockSettings()),
        onLockNow: () => unawaited(widget.appLockController.lock()),
        onOpenSettings: () => unawaited(_openSettings()),
        updateService: widget.updateService,
        onOpenUpdates: () => unawaited(_openUpdates()),
      ),
    ];
    final showScrollToTop = (_selectedIndex == 0 && _showHomeScrollToTop) ||
        (_selectedIndex == 1 && _showLibraryScrollToTop);
    final scrollToTop =
        _selectedIndex == 0 ? _scrollHomeToTop : _scrollLibraryToTop;
    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _selectedIndex, children: pages),
      floatingActionButton:
          showScrollToTop ? _ScrollToTopButton(onPressed: scrollToTop) : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: AnimatedBuilder(
        animation: widget.updateService,
        builder: (context, _) => _GlassBottomNavigation(
          selectedIndex: _selectedIndex,
          showUpdateBadge: widget.updateService.hasUpdate,
          onDestinationSelected: (index) =>
              setState(() => _selectedIndex = index),
        ),
      ),
    );
  }

  Future<void> _scrollLibraryToTop() async {
    if (!_libraryScrollController.hasClients ||
        _libraryScrollController.offset <= 0) {
      return;
    }
    await _libraryScrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _scrollHomeToTop() async {
    if (!_homeScrollController.hasClients ||
        _homeScrollController.offset <= 0) {
      return;
    }
    await _homeScrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }
}

class _GlassBottomNavigation extends StatelessWidget {
  const _GlassBottomNavigation({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.showUpdateBadge,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final bool showUpdateBadge;

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
    final barHeight = isIos ? 64.0 : 68.0;
    return SafeArea(
      top: false,
      minimum: isIos
          ? const EdgeInsets.fromLTRB(16, 8, 16, 6)
          : const EdgeInsets.fromLTRB(20, 8, 20, 10),
      child: SizedBox(
        height: barHeight,
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
              child: Row(
                children: List.generate(_destinations.length, (index) {
                  final destination = _destinations[index];
                  return Expanded(
                    child: _GlassNavigationItem(
                      destination: destination,
                      selected: selectedIndex == index,
                      showBadge: index == 2 && showUpdateBadge,
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

class _ScrollToTopButton extends StatelessWidget {
  const _ScrollToTopButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.small(
      onPressed: onPressed,
      tooltip: '回到顶部',
      child: const Icon(Icons.keyboard_arrow_up_rounded),
    );
  }
}

class _GlassNavigationItem extends StatelessWidget {
  const _GlassNavigationItem({
    required this.destination,
    required this.selected,
    required this.onTap,
    required this.showBadge,
  });

  final _GlassNavigationDestination destination;
  final bool selected;
  final VoidCallback onTap;
  final bool showBadge;

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
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        selected ? destination.selectedIcon : destination.icon,
                        color: foreground,
                        size: 24,
                      ),
                      if (showBadge)
                        Positioned(
                          top: -2,
                          right: -5,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFF4D67),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
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

class _LocalHomeState {
  const _LocalHomeState({
    required this.rails,
    required this.progress,
    required this.history,
    required this.favorites,
    required this.continueWatching,
  });

  final List<HomeCategoryRail> rails;
  final List<WatchProgress> progress;
  final List<String> history;
  final List<MediaItem> favorites;
  final List<MediaItem> continueWatching;
}

class _RemoteHomeState {
  const _RemoteHomeState({required this.categories, required this.rails});

  final List<UnifiedCategory> categories;
  final List<HomeCategoryRail> rails;
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
