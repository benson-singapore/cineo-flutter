import 'package:flutter_test/flutter_test.dart';

import 'package:cineo_flutter/core/models/media.dart';
import 'package:cineo_flutter/features/player/player_screen.dart';

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
  });
}
