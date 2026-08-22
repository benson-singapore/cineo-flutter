import 'dart:async';

import 'package:flutter/material.dart';

import 'core/models/media.dart';
import 'core/theme/cineo_theme.dart';
import 'data/repositories/local_media_repository.dart';
import 'data/remote/media_category_adapter.dart';
import 'features/app_lock/app_lock.dart';
import 'features/home/home_screen.dart';
import 'features/library/library_screen.dart';
import 'features/media_details/media_details_screen.dart';
import 'features/player/player_screen.dart';
import 'features/profile/profile.dart';
import 'features/search/search_screen.dart';
import 'features/settings/adult_source_settings.dart';
import 'features/settings/settings_screen.dart';
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
  final _repository = createDemoLocalMediaRepository();

  @override
  void initState() {
    super.initState();
    unawaited(_adultSourceSettings.initialize());
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
  });

  final LocalMediaRepository repository;
  final AppLockController appLockController;
  final AdultSourceSettings adultSourceSettings;

  @override
  State<CineoShell> createState() => _CineoShellState();
}

class _CineoShellState extends State<CineoShell> {
  List<MediaItem> _items = const [];
  List<MediaItem> _continueWatching = const [];
  List<String> _searchHistory = const [];
  Map<String, double> _progressByMediaId = const {};
  List<UnifiedCategory> _categories = const [];
  UnifiedCategory _selectedCategory = const UnifiedCategory(
    type: UnifiedMediaType.all,
    sourceCategoryIds: [],
  );
  bool _loading = true;
  String? _errorMessage;
  int _selectedIndex = 0;
  int _refreshRevision = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final revision = ++_refreshRevision;
    final stopwatch = Stopwatch()..start();
    _debugLog(
      'home_refresh phase=start revision=$revision '
      'category=${_selectedCategory.type.name} '
      'sourceCategories=${_selectedCategory.sourceCategoryIds.length}',
    );
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }
    try {
      final itemsFuture = widget.repository.browseDefaultSourceCategories(
        _selectedCategory.sourceCategoryIds,
      );
      final progressFuture = widget.repository.watchHistory();
      final historyFuture = widget.repository.searchHistory();
      final results = await Future.wait([
        itemsFuture,
        progressFuture,
        historyFuture,
      ]);
      final items = results[0] as List<MediaItem>;
      final progress = results[1] as List<WatchProgress>;
      final history = results[2] as List<String>;
      final byId = <String, MediaItem>{
        for (final item in items) item.id: item,
      };
      if (!mounted || revision != _refreshRevision) return;
      stopwatch.stop();
      _debugLog(
        'home_refresh phase=complete revision=$revision '
        'elapsedMs=${stopwatch.elapsedMilliseconds} items=${items.length} '
        'progress=${progress.length} searchHistory=${history.length}',
      );
      setState(() {
        _items = items;
        _continueWatching = [
          for (final entry in progress)
            if (!entry.isComplete && byId[entry.mediaId] != null)
              byId[entry.mediaId]!,
        ];
        _progressByMediaId = {
          for (final entry in progress) entry.mediaId: entry.fraction,
        };
        _searchHistory = history;
        _loading = false;
      });
      unawaited(_refreshCategories(revision));
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
        _errorMessage = _homeLoadError(error);
      });
    }
  }

  Future<void> _refreshCategories(int revision) async {
    try {
      final categories = await widget.repository.defaultSourceCategories();
      if (!mounted || revision != _refreshRevision) return;
      setState(() {
        _categories = categories;
        if (categories.isNotEmpty &&
            !categories.any(
              (category) => category.type == _selectedCategory.type,
            )) {
          _selectedCategory = categories.first;
        }
      });
    } catch (error, stackTrace) {
      _debugError(
        'category_refresh phase=failed revision=$revision',
        error,
        stackTrace,
      );
      // Category metadata is optional; the content list remains usable.
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

  Future<void> _selectCategory(UnifiedCategory category) async {
    if (_selectedCategory.type == category.type) return;
    setState(() => _selectedCategory = category);
    await _refresh();
  }

  Future<void> _recordSearch(String query) async {
    await widget.repository.addSearchHistory(query);
    await _refresh();
  }

  Future<void> _openMedia(MediaItem media) async {
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
    final favorite = await widget.repository.isFavorite(resolvedMedia.id);
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => MediaDetailsScreen(
          media: resolvedMedia,
          favorite: favorite,
          onFavoriteChanged: (isFavorite) {
            unawaited(
                widget.repository.setFavorite(resolvedMedia.id, isFavorite));
            unawaited(_refresh());
          },
          onPlay: (option) => unawaited(_openPlayer(resolvedMedia, option)),
          onSearchOtherSources: (item) => widget.repository.searchOtherSources(
            item,
            includeAdult: widget.adultSourceSettings.showAdultSources,
          ),
          onOpenAlternative: (alternative) {
            Navigator.of(context).pop();
            unawaited(_openMedia(alternative));
          },
        ),
      ),
    );
    await _refresh();
  }

  Future<void> _openPlayer(MediaItem media, PlaybackOption option) async {
    final history = await widget.repository.watchHistory();
    final position = history
        .where((entry) => entry.mediaId == media.id)
        .map((entry) => entry.position)
        .fold<Duration>(
          Duration.zero,
          (latest, value) => value > latest ? value : latest,
        );
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          media: media,
          option: option,
          initialPosition: position,
          episodeId: option.id,
          onProgressChanged: (progress) =>
              unawaited(widget.repository.saveProgress(progress)),
        ),
      ),
    );
    await _refresh();
  }

  Future<void> _openLibrary() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => LibraryScreen(
          repository: widget.repository,
          onMediaTap: (media) => unawaited(_openMedia(media)),
        ),
      ),
    );
    await _refresh();
  }

  Future<void> _openSources() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
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
      MaterialPageRoute(
        builder: (_) => PinSetupScreen(controller: widget.appLockController),
      ),
    );
  }

  Future<void> _openSettings() {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          adultSourceSettings: widget.adultSourceSettings,
          appLockController: widget.appLockController,
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
        progressByMediaId: _progressByMediaId,
        categories: _categories,
        selectedCategory: _selectedCategory.type,
        onCategorySelected: (category) => unawaited(_selectCategory(category)),
        isLoading: _loading,
        errorMessage: _errorMessage,
        onRetry: _refresh,
        onOpenMedia: (media) => unawaited(_openMedia(media)),
      ),
      SearchScreen(
        items: _items,
        history: _searchHistory,
        onSearch: (query) => unawaited(_recordSearch(query)),
        onOpenMedia: (media) => unawaited(_openMedia(media)),
        categories: _categories,
        onRemoteSearch: (query, categoryIds) => widget.repository
            .searchDefaultSource(query, categoryIds: categoryIds),
      ),
      ProfileScreen(
        appLockController: widget.appLockController,
        onOpenLibrary: () => unawaited(_openLibrary()),
        onOpenSources: () => unawaited(_openSources()),
        onOpenAppLock: () => unawaited(_openPinSetup()),
        onLockNow: () => unawaited(widget.appLockController.lock()),
        onOpenSettings: () => unawaited(_openSettings()),
      ),
    ];
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search),
            label: '搜索',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }
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
