import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

import 'package:cineo_flutter/core/models/media.dart';
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
      expect(playbackUrlForOption(mp4, filter), mp4.url);
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
  });
}
