import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../core/models/media.dart';
import '../../core/theme/cineo_theme.dart';

const List<double> supportedPlaybackSpeeds = <double>[
  0.5,
  0.75,
  1,
  1.25,
  1.5,
  2,
];

/// Keeps episode labels readable when a source prefixes its own name, such
/// as "source-a · 第01集".
String episodeDisplayLabel(PlaybackOption option) {
  final match = RegExp(r'第\s*(\d+)\s*集').firstMatch(option.label);
  final episodeNumber = int.tryParse(match?.group(1) ?? '');
  if (episodeNumber != null) return '第$episodeNumber集';

  final label = option.label.trim();
  return label.isEmpty ? '未命名剧集' : label;
}

int playbackEpisodeIndex(List<PlaybackOption> episodes, String optionId) {
  final index = episodes.indexWhere((episode) => episode.id == optionId);
  return index < 0 ? 0 : index;
}

enum _PlayerOrientation { portrait, landscape }

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.media,
    required this.option,
    required this.initialPosition,
    required this.onProgressChanged,
    this.episodeId,
    this.episodes = const <PlaybackOption>[],
    this.initialPositions = const <String, Duration>{},
    this.initialPositionForEpisode,
    this.onPictureInPicture,
    this.pictureInPictureAvailable = false,
    this.onSearchOtherSources,
    this.onLoadAlternative,
  });

  final MediaItem media;
  final PlaybackOption option;
  final Duration initialPosition;
  final void Function(MediaItem media, WatchProgress progress)
      onProgressChanged;
  final String? episodeId;

  /// Options from the currently selected playback line, in episode order.
  /// The old single-option call remains valid when this is omitted.
  final List<PlaybackOption> episodes;

  /// Progress keyed by PlaybackOption.id, supplied by the caller when it has
  /// already loaded local watch history.
  final Map<String, Duration> initialPositions;

  /// Optional lazy lookup for callers that do not want to build a map.
  final Duration Function(String episodeId)? initialPositionForEpisode;

  /// Platform-specific PiP is injected by the caller. video_player itself does
  /// not expose a portable Flutter PiP API.
  final VoidCallback? onPictureInPicture;
  final bool pictureInPictureAvailable;
  final Future<List<MediaItem>> Function(MediaItem media)? onSearchOtherSources;
  final Future<MediaItem?> Function(MediaItem media)? onLoadAlternative;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  VideoPlayerController? _controller;
  PlaybackOption? _activeOption;
  late MediaItem _media = widget.media;
  Timer? _saveTimer;
  String? _error;
  bool _controlsVisible = true;
  double _playbackSpeed = 1;
  bool? _lastIsPlaying;
  int _loadGeneration = 0;
  _PlayerOrientation _orientation = _PlayerOrientation.portrait;
  bool _searchingOtherSources = false;

  List<PlaybackOption> get _episodes {
    final activeQuality = _activeOption?.quality ?? widget.option.quality;
    final options = _media.playbackOptions
        .where((option) => option.quality == activeQuality)
        .toList(growable: false);
    final resolved = options.isEmpty
        ? <PlaybackOption>[..._media.playbackOptions]
        : <PlaybackOption>[...options];
    if (resolved.isEmpty) resolved.add(widget.option);
    final seen = <String>{};
    return resolved
        .where((option) => seen.add(option.id))
        .toList(growable: false);
  }

  int get _currentEpisodeIndex => playbackEpisodeIndex(
        _episodes,
        _activeOption?.id ?? widget.option.id,
      );

  VideoPlayerController? get _initializedController {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return null;
    return controller;
  }

  @override
  void initState() {
    super.initState();
    _loadOption(widget.option, initial: true);
  }

  Duration _positionFor(PlaybackOption option, {required bool initial}) {
    final mapped = widget.initialPositions[option.id];
    if (mapped != null) return mapped;

    final callbackPosition = widget.initialPositionForEpisode?.call(option.id);
    if (callbackPosition != null) return callbackPosition;

    if (initial &&
        (widget.episodeId == null || widget.episodeId == option.id)) {
      return widget.initialPosition;
    }
    return Duration.zero;
  }

  Future<void> _loadOption(
    PlaybackOption option, {
    bool initial = false,
    bool savePrevious = true,
  }) async {
    final generation = ++_loadGeneration;
    final previousController = _controller;
    if (previousController != null) {
      if (savePrevious) _save();
      _controller = null;
      previousController.removeListener(_onControllerChanged);
      await previousController.dispose();
    }
    if (!mounted || generation != _loadGeneration) return;

    final controller = VideoPlayerController.networkUrl(Uri.parse(option.url));
    _controller = controller;
    _activeOption = option;
    _lastIsPlaying = null;
    _error = null;
    if (mounted) setState(() {});
    controller.addListener(_onControllerChanged);

    try {
      await controller.initialize();
      if (!mounted || generation != _loadGeneration) {
        controller.removeListener(_onControllerChanged);
        await controller.dispose();
        return;
      }

      final requestedPosition = _positionFor(option, initial: initial);
      if (requestedPosition > Duration.zero) {
        final maxPosition = controller.value.duration;
        await controller.seekTo(
          requestedPosition > maxPosition ? maxPosition : requestedPosition,
        );
      }
      await controller.setPlaybackSpeed(_playbackSpeed);
      await controller.play();
      _saveTimer ??=
          Timer.periodic(const Duration(seconds: 10), (_) => _save());
      if (mounted) setState(() {});
    } catch (_) {
      if (generation != _loadGeneration) return;
      if (mounted) setState(() => _error = '此播放地址暂时无法播放');
    }
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final isPlaying = _controller?.value.isPlaying;
    if (_lastIsPlaying == isPlaying) return;
    _lastIsPlaying = isPlaying;
    setState(() {});
  }

  void _save() {
    final controller = _controller;
    final option = _activeOption;
    if (controller == null ||
        option == null ||
        !controller.value.isInitialized) {
      return;
    }
    widget.onProgressChanged(
        _media,
        WatchProgress(
          mediaId: _media.id,
          // A newly selected option must write under its own id; otherwise a
          // caller's initial episodeId would make every switched episode share
          // one history record.
          episodeId: option.id,
          episodeLabel: episodeDisplayLabel(option),
          episodeNumber: _currentEpisodeIndex + 1,
          episodeCount: _episodes.length,
          position: controller.value.position,
          duration: controller.value.duration,
          updatedAt: DateTime.now(),
        ));
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
  }

  Future<void> _togglePlayPause() async {
    final controller = _initializedController;
    if (controller == null) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
  }

  Future<void> _setPlaybackSpeed(double speed) async {
    _playbackSpeed = speed;
    final controller = _initializedController;
    if (controller != null) await controller.setPlaybackSpeed(speed);
    if (mounted) setState(() {});
  }

  Future<void> _selectRelativeEpisode(int offset) async {
    final index = _currentEpisodeIndex + offset;
    if (index < 0 || index >= _episodes.length) return;
    await _selectEpisode(_episodes[index]);
  }

  Future<void> _selectEpisode(PlaybackOption option) async {
    if (option.id == _activeOption?.id) return;
    await _loadOption(option);
  }

  Future<void> _openEpisodePanel() async {
    final activeOptionId = _activeOption?.id ?? widget.option.id;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _EpisodeBottomSheet(
        episodes: _episodes,
        activeOptionId: activeOptionId,
        onSelected: (option) {
          Navigator.of(sheetContext).pop();
          unawaited(_selectEpisode(option));
        },
      ),
    );
  }

  Future<void> _openSourcePanel() async {
    final finder = widget.onSearchOtherSources;
    final loader = widget.onLoadAlternative;
    if (finder == null || loader == null || _searchingOtherSources) return;
    setState(() => _searchingOtherSources = true);
    try {
      final matches = await finder(_media);
      if (!mounted) return;
      final selected = await showModalBottomSheet<MediaItem>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        backgroundColor: CineoColors.surface,
        builder: (context) => _PlayerSourceSheet(
          matches: <MediaItem>[_media, ...matches],
          activeSourceId: _media.sourceId,
        ),
      );
      if (selected == null ||
          selected.sourceId == _media.sourceId ||
          !mounted) {
        return;
      }
      await _switchSource(selected, loader);
    } catch (_) {
      _showMessage('其他站点暂时无法完成搜索');
    } finally {
      if (mounted) setState(() => _searchingOtherSources = false);
    }
  }

  Future<void> _switchSource(
    MediaItem alternative,
    Future<MediaItem?> Function(MediaItem media) loader,
  ) async {
    _save();
    final loaded = await loader(alternative);
    if (!mounted || loaded == null) {
      _showMessage('切换资源站失败，请稍后重试');
      return;
    }
    final option = _matchingOption(loaded, _activeOption) ??
        loaded.playbackOptions.firstOrNull;
    if (option == null) {
      _showMessage('该资源站暂无可播放剧集');
      return;
    }
    setState(() => _media = loaded);
    await _loadOption(option, savePrevious: false);
    if (mounted) _showMessage('已切换到${loaded.sourceName ?? '其他资源站'}');
  }

  PlaybackOption? _matchingOption(
    MediaItem media,
    PlaybackOption? current,
  ) {
    if (current == null) return null;
    final currentNumber = _episodeNumber(current);
    if (currentNumber == null) return null;
    for (final option in media.playbackOptions) {
      if (_episodeNumber(option) == currentNumber) return option;
    }
    return null;
  }

  int? _episodeNumber(PlaybackOption option) {
    final match = RegExp(r'第\s*0*(\d+)\s*集').firstMatch(option.label);
    return int.tryParse(match?.group(1) ?? '');
  }

  Future<void> _openInExternalBrowser() async {
    final rawUrl = _activeOption?.url;
    final uri = rawUrl == null ? null : Uri.tryParse(rawUrl);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      _showMessage('当前播放地址不可用');
      return;
    }
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) _showMessage('无法使用系统浏览器打开此播放地址');
  }

  Future<void> _toggleOrientation() async {
    final landscape = _orientation == _PlayerOrientation.landscape;
    await SystemChrome.setPreferredOrientations(
      landscape
          ? const <DeviceOrientation>[DeviceOrientation.portraitUp]
          : const <DeviceOrientation>[
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ],
    );
    if (mounted) {
      setState(() {
        _orientation = landscape
            ? _PlayerOrientation.portrait
            : _PlayerOrientation.landscape;
      });
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _loadGeneration++;
    _saveTimer?.cancel();
    _save();
    unawaited(SystemChrome.setPreferredOrientations(DeviceOrientation.values));
    final controller = _controller;
    if (controller != null) {
      controller.removeListener(_onControllerChanged);
      unawaited(controller.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final value = controller?.value;
    final isReady = value?.isInitialized == true;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_error != null)
              _PlayerFailure(
                error: _error!,
                onClose: () => Navigator.pop(context),
              )
            else if (!isReady || controller == null)
              const Center(
                child: CircularProgressIndicator(color: CineoColors.primary),
              )
            else
              Center(
                child: AspectRatio(
                  aspectRatio:
                      value!.aspectRatio > 0 ? value.aspectRatio : 16 / 9,
                  child: VideoPlayer(controller),
                ),
              ),
            if (_error == null && isReady && controller != null)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _toggleControls,
                ),
              ),
            if (_error == null && isReady && controller != null)
              IgnorePointer(
                ignoring: !_controlsVisible,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: _controlsVisible ? 1 : 0,
                  child: _PlayerControls(
                    controller: controller,
                    title: _media.title,
                    isPlaying: value!.isPlaying,
                    speed: _playbackSpeed,
                    canGoPrevious: _currentEpisodeIndex > 0,
                    canGoNext: _currentEpisodeIndex < _episodes.length - 1,
                    hasEpisodes: _episodes.length > 1,
                    pictureInPictureAvailable:
                        widget.pictureInPictureAvailable &&
                            widget.onPictureInPicture != null,
                    onClose: () => Navigator.pop(context),
                    onPlayPause: _togglePlayPause,
                    onPrevious: () => _selectRelativeEpisode(-1),
                    onNext: () => _selectRelativeEpisode(1),
                    onSpeedChanged: _setPlaybackSpeed,
                    onOpenEpisodes: _openEpisodePanel,
                    canSwitchSource: widget.onSearchOtherSources != null &&
                        widget.onLoadAlternative != null,
                    isSwitchingSource: _searchingOtherSources,
                    onOpenSource: _openSourcePanel,
                    isLandscape: _orientation == _PlayerOrientation.landscape,
                    onOpenInBrowser: _openInExternalBrowser,
                    onToggleOrientation: _toggleOrientation,
                    onPictureInPicture: () {
                      setState(() => _controlsVisible = false);
                      widget.onPictureInPicture?.call();
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EpisodeBottomSheet extends StatefulWidget {
  const _EpisodeBottomSheet({
    required this.episodes,
    required this.activeOptionId,
    required this.onSelected,
  });

  final List<PlaybackOption> episodes;
  final String activeOptionId;
  final ValueChanged<PlaybackOption> onSelected;

  @override
  State<_EpisodeBottomSheet> createState() => _EpisodeBottomSheetState();
}

class _PlayerSourceSheet extends StatelessWidget {
  const _PlayerSourceSheet({
    required this.matches,
    required this.activeSourceId,
  });

  final List<MediaItem> matches;
  final String? activeSourceId;

  @override
  Widget build(BuildContext context) {
    final sites = <String, MediaItem>{};
    for (final media in matches) {
      final sourceId = media.sourceId?.trim() ?? '';
      if (sourceId.isNotEmpty) sites.putIfAbsent(sourceId, () => media);
    }
    final ordered = sites.values.toList()
      ..sort((left, right) {
        if (left.sourceId == activeSourceId) return -1;
        if (right.sourceId == activeSourceId) return 1;
        return 0;
      });
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .68,
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                '切换资源站',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: Text(
                '将自动定位到相同集数；目标源未提供时播放其第一集。',
                style: TextStyle(color: CineoColors.textSecondary),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                itemCount: ordered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final media = ordered[index];
                  final selected = media.sourceId == activeSourceId;
                  final sourceName = media.sourceName?.trim().isNotEmpty == true
                      ? media.sourceName!.trim()
                      : '资源站';
                  return Material(
                    color: selected
                        ? CineoColors.primaryContainer
                        : CineoColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      key: ValueKey('player-media-site-${media.sourceId}'),
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => Navigator.of(context).pop(media),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Icon(
                              selected
                                  ? Icons.check_circle_rounded
                                  : Icons.video_library_outlined,
                              color: selected
                                  ? CineoColors.primary
                                  : CineoColors.textSecondary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    sourceName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    media.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: CineoColors.textSecondary,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              selected
                                  ? Icons.check_rounded
                                  : Icons.chevron_right_rounded,
                              color: selected
                                  ? CineoColors.primary
                                  : CineoColors.textSecondary,
                            ),
                          ],
                        ),
                      ),
                    ),
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

class _EpisodeBottomSheetState extends State<_EpisodeBottomSheet> {
  static const _itemExtent = 54.0;
  static const _itemSpacing = 8.0;
  late final ScrollController _scrollController;
  bool _showCurrentEpisodeShortcut = false;

  int get _currentEpisodeIndex =>
      playbackEpisodeIndex(widget.episodes, widget.activeOptionId);

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
  }

  void _onScroll() {
    final isAwayFromCurrent = _scrollController.hasClients &&
        (_scrollController.offset -
                    _currentEpisodeIndex * (_itemExtent + _itemSpacing))
                .abs() >
            180;
    if (isAwayFromCurrent != _showCurrentEpisodeShortcut && mounted) {
      setState(() => _showCurrentEpisodeShortcut = isAwayFromCurrent);
    }
  }

  void _scrollToCurrent() {
    if (!_scrollController.hasClients) return;
    final target = math.min(
      math.max(
        0.0,
        _currentEpisodeIndex * (_itemExtent + _itemSpacing) - _itemExtent,
      ),
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = math.min(MediaQuery.sizeOf(context).height * .72, 620.0);
    final currentLabel =
        episodeDisplayLabel(widget.episodes[_currentEpisodeIndex]);
    return SizedBox(
      height: height,
      child: Material(
        color: CineoColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(top: 10, bottom: 8),
                      decoration: BoxDecoration(
                        color: CineoColors.divider,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 8, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '选集',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${widget.episodes.length} 集 · 正在播放 $currentLabel',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: CineoColors.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭选集',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: CineoColors.divider),
                  Expanded(
                    child: ListView.separated(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                      itemCount: widget.episodes.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: _itemSpacing),
                      itemBuilder: (context, index) {
                        final episode = widget.episodes[index];
                        final selected = episode.id == widget.activeOptionId;
                        return SizedBox(
                          height: _itemExtent,
                          child: Material(
                            color: selected
                                ? CineoColors.primaryContainer
                                : CineoColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(10),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => widget.onSelected(episode),
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 14),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 28,
                                      height: 28,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? CineoColors.primary
                                            : CineoColors.surfaceOverlay,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        selected
                                            ? Icons.play_arrow_rounded
                                            : Icons.movie_outlined,
                                        size: 17,
                                        color: selected
                                            ? const Color(0xff251300)
                                            : CineoColors.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        episodeDisplayLabel(episode),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: selected
                                              ? CineoColors.primaryLight
                                              : CineoColors.textPrimary,
                                          fontWeight: selected
                                              ? FontWeight.w800
                                              : FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    if (selected)
                                      const Text(
                                        '播放中',
                                        style: TextStyle(
                                          color: CineoColors.primaryLight,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
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
                  ),
                ],
              ),
              if (_showCurrentEpisodeShortcut)
                Positioned(
                  right: 20,
                  bottom: 20,
                  child: FloatingActionButton.small(
                    heroTag: 'player-current-episode',
                    tooltip: '定位当前集',
                    onPressed: _scrollToCurrent,
                    child: const Icon(Icons.my_location_rounded),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerControls extends StatelessWidget {
  const _PlayerControls({
    required this.controller,
    required this.title,
    required this.isPlaying,
    required this.speed,
    required this.canGoPrevious,
    required this.canGoNext,
    required this.hasEpisodes,
    required this.pictureInPictureAvailable,
    required this.onClose,
    required this.onPlayPause,
    required this.onPrevious,
    required this.onNext,
    required this.onSpeedChanged,
    required this.onOpenEpisodes,
    required this.canSwitchSource,
    required this.isSwitchingSource,
    required this.onOpenSource,
    required this.isLandscape,
    required this.onOpenInBrowser,
    required this.onToggleOrientation,
    required this.onPictureInPicture,
  });

  final VideoPlayerController controller;
  final String title;
  final bool isPlaying;
  final double speed;
  final bool canGoPrevious;
  final bool canGoNext;
  final bool hasEpisodes;
  final bool pictureInPictureAvailable;
  final VoidCallback onClose;
  final VoidCallback onPlayPause;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<double> onSpeedChanged;
  final VoidCallback onOpenEpisodes;
  final bool canSwitchSource;
  final bool isSwitchingSource;
  final VoidCallback onOpenSource;
  final bool isLandscape;
  final VoidCallback onOpenInBrowser;
  final VoidCallback onToggleOrientation;
  final VoidCallback? onPictureInPicture;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black54, Colors.transparent, Color(0xCC000000)],
          stops: [0, .32, 1],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: '返回',
                    onPressed: onClose,
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '在浏览器打开',
                    onPressed: onOpenInBrowser,
                    icon: const Icon(Icons.open_in_browser_rounded),
                  ),
                  if (canSwitchSource)
                    IconButton(
                      tooltip: '切换资源站',
                      onPressed: isSwitchingSource ? null : onOpenSource,
                      icon: isSwitchingSource
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.switch_video_rounded),
                    ),
                  IconButton(
                    tooltip: isLandscape ? '竖屏播放' : '横屏播放',
                    onPressed: onToggleOrientation,
                    icon: Icon(
                      isLandscape
                          ? Icons.stay_current_portrait_rounded
                          : Icons.screen_rotation_alt_rounded,
                    ),
                  ),
                  _PictureInPictureButton(
                    available: pictureInPictureAvailable,
                    onPressed: onPictureInPicture,
                  ),
                ],
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(.42),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '上一集',
                      onPressed: canGoPrevious ? onPrevious : null,
                      icon: const Icon(Icons.skip_previous_rounded),
                    ),
                    IconButton(
                      tooltip: isPlaying ? '暂停' : '播放',
                      iconSize: 54,
                      color: CineoColors.primary,
                      onPressed: onPlayPause,
                      icon: Icon(
                        isPlaying
                            ? Icons.pause_circle_filled_rounded
                            : Icons.play_circle_fill_rounded,
                      ),
                    ),
                    IconButton(
                      tooltip: '下一集',
                      onPressed: canGoNext ? onNext : null,
                      icon: const Icon(Icons.skip_next_rounded),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              VideoProgressIndicator(
                controller,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: CineoColors.primary,
                  bufferedColor: Colors.white38,
                  backgroundColor: Colors.white24,
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  PopupMenuButton<double>(
                    tooltip: '播放速度',
                    initialValue: speed,
                    onSelected: onSpeedChanged,
                    itemBuilder: (context) => supportedPlaybackSpeeds
                        .map(
                          (value) => PopupMenuItem<double>(
                            value: value,
                            child: Text('${value}x'),
                          ),
                        )
                        .toList(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        '${speed}x',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  if (hasEpisodes)
                    IconButton(
                      tooltip: '打开选集',
                      onPressed: onOpenEpisodes,
                      icon: const Icon(Icons.list_alt_rounded),
                    ),
                  const SizedBox(width: 8),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PictureInPictureButton extends StatelessWidget {
  const _PictureInPictureButton({
    required this.available,
    required this.onPressed,
  });

  final bool available;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: available ? '画中画' : '画中画不可用',
      onPressed: available ? onPressed : null,
      icon: const Icon(Icons.picture_in_picture_alt),
    );
  }
}

class _PlayerFailure extends StatelessWidget {
  const _PlayerFailure({required this.error, required this.onClose});

  final String error;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.play_disabled_outlined,
                size: 52,
                color: CineoColors.textSecondary,
              ),
              const SizedBox(height: 16),
              Text(error),
              const SizedBox(height: 16),
              FilledButton(onPressed: onClose, child: const Text('返回详情')),
            ],
          ),
        ),
      );
}
