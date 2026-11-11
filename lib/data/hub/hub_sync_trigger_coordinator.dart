import 'dart:async';

import '../../core/models/media.dart';
import 'hub_sync_policy.dart';

class HubSyncTriggerCoordinator {
  HubSyncTriggerCoordinator({
    required Future<void> Function(MediaItem media, bool favorite) pushFavorite,
    required Future<void> Function(MediaItem media, WatchProgress progress)
        pushProgress,
    required Future<void> Function() pushOutbox,
    required int Function() intervalSeconds,
    DateTime Function()? now,
    Timer Function(Duration, void Function())? createTimer,
    Timer Function(Duration, void Function())? createPeriodicTimer,
    Future<void> Function(Future<void> Function())? dispatch,
    this.checkEvery = const Duration(seconds: 1),
    this.favoriteDebounce = const Duration(seconds: 2),
  })  : _pushFavorite = pushFavorite,
        _pushProgress = pushProgress,
        _pushOutbox = pushOutbox,
        _intervalSeconds = intervalSeconds,
        _now = now ?? DateTime.now,
        _createTimer = createTimer ?? Timer.new,
        _createPeriodicTimer = createPeriodicTimer ??
            ((duration, callback) =>
                Timer.periodic(duration, (_) => callback())),
        _dispatch = dispatch ?? ((operation) => operation());

  final Future<void> Function(MediaItem, bool) _pushFavorite;
  final Future<void> Function(MediaItem, WatchProgress) _pushProgress;
  final Future<void> Function() _pushOutbox;
  final int Function() _intervalSeconds;
  final DateTime Function() _now;
  final Timer Function(Duration, void Function()) _createTimer;
  final Timer Function(Duration, void Function()) _createPeriodicTimer;
  final Future<void> Function(Future<void> Function()) _dispatch;
  final Duration checkEvery;
  final Duration favoriteDebounce;
  final Map<String, Timer> _favoriteTimers = {};
  final Map<String, (MediaItem, bool)> _pendingFavorites = {};
  (String, MediaItem, WatchProgress)? _currentProgress;
  final Map<String, int> _lastPushedPositions = {};
  Timer? _progressTimer;
  DateTime? _lastProgressPushAt;
  int? _intervalOverride;
  bool _disposed = false;

  void updateInterval(int seconds) {
    _intervalOverride = normalizeProgressPushInterval(seconds);
  }

  void favoriteChanged(MediaItem media, bool favorite) {
    if (_disposed) return;
    final key = media.id;
    _pendingFavorites[key] = (media, favorite);
    _favoriteTimers.remove(key)?.cancel();
    _favoriteTimers[key] = _createTimer(favoriteDebounce, () {
      _favoriteTimers.remove(key);
      _flushFavorite(key);
    });
  }

  void onLifecycleResumed() {
    // Pulling is intentionally limited to launch and explicit user requests.
  }

  void onLifecycleBackgrounded() {
    if (!_disposed) {
      unawaited(_dispatch(_pushOutbox).catchError((Object _) {}));
    }
  }

  void trackProgress(MediaItem media, WatchProgress progress) {
    if (_disposed) return;
    final key = _progressKey(media, progress);
    _currentProgress = (key, media, progress);
    _lastProgressPushAt ??= _now();
    _progressTimer ??= _createPeriodicTimer(checkEvery, _checkProgress);
  }

  Future<void> flushProgress(MediaItem media, WatchProgress progress) async {
    if (_disposed) return;
    final key = _progressKey(media, progress);
    if (_lastPushedPositions[key] == progress.position.inMilliseconds) return;
    _currentProgress = (key, media, progress);
    _lastPushedPositions[key] = progress.position.inMilliseconds;
    _lastProgressPushAt = _now();
    await _dispatch(() => _pushProgress(media, progress));
  }

  void _checkProgress() {
    final current = _currentProgress;
    if (_disposed || current == null) return;
    final lastPush = _lastProgressPushAt;
    if (lastPush != null &&
        _now().difference(lastPush) <
            Duration(
                seconds: _intervalOverride ??
                    normalizeProgressPushInterval(_intervalSeconds()))) {
      return;
    }
    final (key, media, progress) = current;
    final position = progress.position.inMilliseconds;
    if (_lastPushedPositions[key] == position) return;
    _lastPushedPositions[key] = position;
    _lastProgressPushAt = _now();
    unawaited(_dispatch(() => _pushProgress(media, progress))
        .catchError((Object _) {}));
  }

  void _flushFavorite(String key) {
    final pending = _pendingFavorites.remove(key);
    if (pending != null) {
      unawaited(_dispatch(() => _pushFavorite(pending.$1, pending.$2))
          .catchError((Object _) {}));
    }
  }

  String _progressKey(MediaItem media, WatchProgress progress) =>
      '${media.id}:${progress.episodeId ?? ''}';

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final timer in _favoriteTimers.values) {
      timer.cancel();
    }
    _favoriteTimers.clear();
    for (final key in _pendingFavorites.keys.toList()) {
      final pending = _pendingFavorites.remove(key);
      if (pending != null) {
        unawaited(_dispatch(() => _pushFavorite(pending.$1, pending.$2))
            .catchError((Object _) {}));
      }
    }
    _progressTimer?.cancel();
  }
}
