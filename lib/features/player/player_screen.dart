import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/models/media.dart';
import '../../core/theme/cineo_theme.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.media,
    required this.option,
    required this.initialPosition,
    required this.onProgressChanged,
  });

  final MediaItem media;
  final PlaybackOption option;
  final Duration initialPosition;
  final ValueChanged<WatchProgress> onProgressChanged;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final VideoPlayerController _controller;
  Timer? _saveTimer;
  String? _error;
  bool _controlsVisible = true;

  @override
  void initState() {
    super.initState();
    _controller =
        VideoPlayerController.networkUrl(Uri.parse(widget.option.url));
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();
      if (widget.initialPosition > Duration.zero) {
        await _controller.seekTo(widget.initialPosition);
      }
      await _controller.play();
      _saveTimer = Timer.periodic(const Duration(seconds: 10), (_) => _save());
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _error = '此播放地址暂时无法播放');
    }
  }

  void _save() {
    if (!_controller.value.isInitialized) return;
    widget.onProgressChanged(WatchProgress(
      mediaId: widget.media.id,
      position: _controller.value.position,
      duration: _controller.value.duration,
      updatedAt: DateTime.now(),
    ));
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _save();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = _controller.value;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_error != null)
              _PlayerFailure(
                  error: _error!, onClose: () => Navigator.pop(context))
            else if (!value.isInitialized)
              const Center(
                  child: CircularProgressIndicator(color: CineoColors.primary))
            else
              Center(
                child: AspectRatio(
                  aspectRatio: value.aspectRatio,
                  child: VideoPlayer(_controller),
                ),
              ),
            if (_error == null && value.isInitialized)
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () =>
                    setState(() => _controlsVisible = !_controlsVisible),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: _controlsVisible ? 1 : 0,
                  child: _PlayerControls(
                    controller: _controller,
                    title: widget.media.title,
                    onClose: () => Navigator.pop(context),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlayerControls extends StatelessWidget {
  const _PlayerControls({
    required this.controller,
    required this.title,
    required this.onClose,
  });

  final VideoPlayerController controller;
  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black45,
      child: Column(
        children: [
          Row(children: [
            IconButton(onPressed: onClose, icon: const Icon(Icons.arrow_back)),
            Expanded(
                child:
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 48)
          ]),
          const Spacer(),
          IconButton(
            iconSize: 56,
            onPressed: () => controller.value.isPlaying
                ? controller.pause()
                : controller.play(),
            icon: Icon(controller.value.isPlaying
                ? Icons.pause_circle_filled
                : Icons.play_circle_fill),
          ),
          VideoProgressIndicator(controller,
              allowScrubbing: true,
              colors: const VideoProgressColors(
                  playedColor: CineoColors.primary,
                  bufferedColor: Colors.white38,
                  backgroundColor: Colors.white24)),
          const SizedBox(height: 16),
        ],
      ),
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
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.play_disabled_outlined,
                size: 52, color: CineoColors.textSecondary),
            const SizedBox(height: 16),
            Text(error),
            const SizedBox(height: 16),
            FilledButton(onPressed: onClose, child: const Text('返回详情')),
          ]),
        ),
      );
}
