import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

import 'package:cineo_flutter/core/models/media.dart';
import 'package:cineo_flutter/core/platform/picture_in_picture.dart';
import 'package:cineo_flutter/features/player/player_screen.dart';
import 'package:cineo_flutter/features/settings/m3u8_filter_settings.dart';

void main() {
  PlaybackOption option(String id, String label) => PlaybackOption(
        id: id,
        sourceId: 'source',
        label: label,
        url: 'https://example.com/$id.m3u8',
        quality: '线路一',
      );

  group('player helpers', () {
    test('serializes the native PiP handoff request', () {
      const request = PictureInPictureRequest(
        url: 'https://example.com/video.m3u8',
        title: '示例视频',
        position: Duration(seconds: 42),
        aspectRatio: 16 / 9,
        isPlaying: true,
      );

      expect(request.toMap(), <String, Object>{
        'url': 'https://example.com/video.m3u8',
        'title': '示例视频',
        'positionMilliseconds': 42000,
        'aspectRatio': 16 / 9,
        'isPlaying': true,
      });
    });

    test('formats playback durations for short and long videos', () {
      expect(formatPlaybackDuration(Duration.zero), '0:00');
      expect(
        formatPlaybackDuration(const Duration(minutes: 1, seconds: 9)),
        '1:09',
      );
      expect(
        formatPlaybackDuration(
          const Duration(hours: 1, minutes: 2, seconds: 3),
        ),
        '1:02:03',
      );
    });

    test('keeps ten-second seeks inside the video duration', () {
      const duration = Duration(minutes: 2);

      expect(
        seekPositionBy(
          position: const Duration(seconds: 5),
          offset: const Duration(seconds: -10),
          duration: duration,
        ),
        Duration.zero,
      );
      expect(
        seekPositionBy(
          position: const Duration(seconds: 20),
          offset: const Duration(seconds: -10),
          duration: duration,
        ),
        const Duration(seconds: 10),
      );
      expect(
        seekPositionBy(
          position: const Duration(seconds: 115),
          offset: const Duration(seconds: 10),
          duration: duration,
        ),
        duration,
      );
    });

    test('normalizes source-prefixed episode labels', () {
      expect(episodeDisplayLabel(option('1', 'rym3u8 · 第01集')), '第1集');
      expect(episodeDisplayLabel(option('2', '特别篇')), '特别篇');
      expect(episodeDisplayLabel(option('3', '')), '未命名剧集');
    });

    test('finds episode index and clamps unknown ids to the first item', () {
      final episodes = [option('1', '第1集'), option('2', '第2集')];
      expect(playbackEpisodeIndex(episodes, '2'), 1);
      expect(playbackEpisodeIndex(episodes, 'missing'), 0);
    });

    test('exposes the supported playback speed choices', () {
      expect(supportedPlaybackSpeeds, [0.5, 0.75, 1, 1.25, 1.5, 2]);
    });

    test('uses the active filter for HLS URLs only', () {
      const filter = M3u8FilterConfig(
        id: 'filter',
        name: '广告过滤',
        template:
            'https://filter.example.test/proxy?url=$m3u8FilterUrlPlaceholder',
        enabled: true,
      );
      final hls = option('hls', '第1集');
      const mp4 = PlaybackOption(
        id: 'mp4',
        sourceId: 'source',
        label: '正片',
        url: 'https://example.com/video.mp4',
        quality: '线路一',
      );

      expect(
        playbackUrlForOption(hls, filter),
        contains('https://example.com/hls.m3u8'),
      );
      expect(
        playbackUrlCandidatesForOption(hls, filter),
        <String>[
          'https://filter.example.test/proxy?url=https://example.com/hls.m3u8',
          hls.url,
        ],
      );
      expect(playbackUrlForOption(mp4, filter), mp4.url);
      expect(playbackUrlCandidatesForOption(mp4, filter), <String>[mp4.url]);
      expect(playbackUrlForOption(hls, null), hls.url);
    });

    test('hints HLS format even when the source URL has no m3u8 suffix', () {
      final hls = option('hls', '第1集');
      const proxyResolvedHls = PlaybackOption(
        id: 'proxy-hls',
        sourceId: 'source',
        label: '代理地址',
        url: 'https://filter.example.test/api/proxy?rule=auto_full&url=video',
        quality: '线路一',
        isHls: true,
      );
      const mp4 = PlaybackOption(
        id: 'mp4',
        sourceId: 'source',
        label: '正片',
        url: 'https://example.com/video.mp4',
        quality: '线路一',
      );

      expect(playbackFormatHintForOption(hls), VideoFormat.hls);
      expect(playbackFormatHintForOption(proxyResolvedHls), VideoFormat.hls);
      expect(playbackFormatHintForOption(mp4), isNull);
    });

    test('resolves an existing completed local file', () async {
      final file =
          await File('${Directory.systemTemp.path}/cineo-final.ts').create();
      addTearDown(() async {
        if (await file.exists()) await file.delete();
      });

      final resolved = await localPlaybackFileForOption(
        option('cached', '第1集'),
        (_) async => file.path,
      );

      expect(resolved?.path, file.path);
    });

    test('treats a missing local file as a remote cache miss', () async {
      final resolved = await localPlaybackFileForOption(
        option('missing', '第1集'),
        (_) async => '${Directory.systemTemp.path}/does-not-exist.ts',
      );

      expect(resolved, isNull);
    });

    test('accepts a loopback HLS URL as a local playback source', () async {
      final resolved = await localPlaybackSourceForOption(
        option('cached', '第1集'),
        (_) async => 'http://127.0.0.1:12345/task/index.m3u8',
      );

      expect(resolved, 'http://127.0.0.1:12345/task/index.m3u8');
    });

    test('does not query local storage when no resolver is supplied', () async {
      final resolved =
          await localPlaybackFileForOption(option('remote', '第1集'), null);

      expect(resolved, isNull);
    });
  });
}
