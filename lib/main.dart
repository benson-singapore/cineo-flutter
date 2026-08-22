import 'dart:async';

import 'package:flutter/material.dart';

import 'core/models/media.dart';
import 'core/theme/cineo_theme.dart';
import 'data/repositories/local_media_repository.dart';
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
  bool _loading = true;
  String? _errorMessage;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }
    try {
      final results = await Future.wait([
        widget.repository.featured(),
        widget.repository.watchHistory(),
        widget.repository.searchHistory(),
      ]);
      final items = results[0] as List<MediaItem>;
      final progress = results[1] as List<WatchProgress>;
      final history = results[2] as List<String>;
      final byId = <String, MediaItem>{
        for (final item in items) item.id: item,
      };
      if (!mounted) return;
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
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = '本地数据暂时无法加载';
      });
    }
  }

  Future<void> _recordSearch(String query) async {
    await widget.repository.addSearchHistory(query);
    await _refresh();
  }

  Future<void> _openMedia(MediaItem media) async {
    final favorite = await widget.repository.isFavorite(media.id);
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => MediaDetailsScreen(
          media: media,
          favorite: favorite,
          onFavoriteChanged: (isFavorite) {
            unawaited(widget.repository.setFavorite(media.id, isFavorite));
            unawaited(_refresh());
          },
          onPlay: (option) => unawaited(_openPlayer(media, option)),
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
