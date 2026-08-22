import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
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
  });

  final MediaItem media;
  final PlaybackOption option;
  final Duration initialPosition;
  final ValueChanged<WatchProgress> onProgressChanged;
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

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  VideoPlayerController? _controller;
  PlaybackOption? _activeOption;
  Timer? _saveTimer;
  String? _error;
  bool _controlsVisible = true;
  bool _episodePanelOpen = false;
  bool _showScrollToTop = false;
  double _playbackSpeed = 1;
  bool? _lastIsPlaying;
  int _loadGeneration = 0;
  late final ScrollController _episodeScrollController;

  List<PlaybackOption> get _episodes {
    final options = <PlaybackOption>[...widget.episodes];
    if (!options.any((option) => option.id == widget.option.id)) {
      options.insert(0, widget.option);
    }
    final seen = <String>{};
    return options
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
    _episodeScrollController = ScrollController()
      ..addListener(_onEpisodeScroll);
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

  Future<void> _loadOption(PlaybackOption option,
      {bool initial = false}) async {
    final generation = ++_loadGeneration;
    final previousController = _controller;
    if (previousController != null) {
      _save();
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
    widget.onProgressChanged(WatchProgress(
      mediaId: widget.media.id,
      // A newly selected option must write under its own id; otherwise a
      // caller's initial episodeId would make every switched episode share
      // one history record.
      episodeId: option.id,
      position: controller.value.position,
      duration: controller.value.duration,
      updatedAt: DateTime.now(),
    ));
  }

  void _toggleControls() {
    if (_episodePanelOpen) return;
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
    if (option.id == _activeOption?.id) {
      if (mounted) setState(() => _episodePanelOpen = false);
      return;
    }
    if (mounted) setState(() => _episodePanelOpen = false);
    await _loadOption(option);
  }

  void _openEpisodePanel() {
    setState(() => _episodePanelOpen = true);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _scrollToCurrentEpisode());
  }

  void _onEpisodeScroll() {
    final shouldShow = _episodeScrollController.hasClients &&
        _episodeScrollController.offset > 240;
    if (shouldShow != _showScrollToTop && mounted) {
      setState(() => _showScrollToTop = shouldShow);
    }
  }

  void _scrollToCurrentEpisode() {
    if (!_episodeScrollController.hasClients) return;
    final target = math.min(
      _currentEpisodeIndex * 58.0,
      _episodeScrollController.position.maxScrollExtent,
    );
    _episodeScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _loadGeneration++;
    _saveTimer?.cancel();
    _save();
    _episodeScrollController
      ..removeListener(_onEpisodeScroll)
      ..dispose();
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
                ignoring: !_controlsVisible || _episodePanelOpen,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: _controlsVisible && !_episodePanelOpen ? 1 : 0,
                  child: _PlayerControls(
                    controller: controller,
                    title: widget.media.title,
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
                    onPictureInPicture: () {
                      setState(() => _controlsVisible = false);
                      widget.onPictureInPicture?.call();
                    },
                  ),
                ),
              ),
            if (_episodePanelOpen) _buildEpisodePanel(context),
          ],
        ),
      ),
    );
  }

  Widget _buildEpisodePanel(BuildContext context) {
    final width = math.min(MediaQuery.sizeOf(context).width * .86, 360.0);
    return Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: width,
        child: Material(
          color: const Color(0xff171717),
          child: SafeArea(
            left: false,
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '选集  ${_episodes.length}集',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: '关闭选集',
                            onPressed: () =>
                                setState(() => _episodePanelOpen = false),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Colors.white12),
                    Expanded(
                      child: ListView.builder(
                        controller: _episodeScrollController,
                        itemExtent: 58,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _episodes.length,
                        itemBuilder: (context, index) {
                          final episode = _episodes[index];
                          final selected = episode.id == _activeOption?.id;
                          return ListTile(
                            dense: true,
                            selected: selected,
                            selectedTileColor:
                                CineoColors.primary.withOpacity(.18),
                            leading: Icon(
                              selected
                                  ? Icons.play_arrow
                                  : Icons.movie_outlined,
                              color: selected
                                  ? CineoColors.primary
                                  : CineoColors.textSecondary,
                            ),
                            title: Text(episodeDisplayLabel(episode)),
                            onTap: () => _selectEpisode(episode),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                if (_showScrollToTop)
                  Positioned(
                    right: 16,
                    bottom: 20,
                    child: FloatingActionButton.small(
                      heroTag: 'player-episodes-top',
                      tooltip: '回到顶部',
                      onPressed: () => _episodeScrollController.animateTo(
                        0,
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                      ),
                      child: const Icon(Icons.vertical_align_top),
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
  final VoidCallback? onPictureInPicture;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black45,
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: '返回',
                onPressed: onClose,
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child:
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              _PictureInPictureButton(
                available: pictureInPictureAvailable,
                onPressed: onPictureInPicture,
              ),
            ],
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: '上一集',
                onPressed: canGoPrevious ? onPrevious : null,
                icon: const Icon(Icons.skip_previous),
              ),
              IconButton(
                tooltip: isPlaying ? '暂停' : '播放',
                iconSize: 56,
                onPressed: onPlayPause,
                icon: Icon(
                  isPlaying
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_fill,
                ),
              ),
              IconButton(
                tooltip: '下一集',
                onPressed: canGoNext ? onNext : null,
                icon: const Icon(Icons.skip_next),
              ),
            ],
          ),
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
                  child: Text('${speed}x'),
                ),
              ),
              if (hasEpisodes)
                IconButton(
                  tooltip: '打开选集',
                  onPressed: onOpenEpisodes,
                  icon: const Icon(Icons.list_alt),
                ),
              const SizedBox(width: 8),
            ],
          ),
          const SizedBox(height: 8),
        ],
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
