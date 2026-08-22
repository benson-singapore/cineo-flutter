import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cineo_flutter/core/models/media_source.dart';
import 'package:cineo_flutter/data/remote/mac_cms_client.dart';

void main() {
  const source = MediaSource(
    id: 'family',
    name: '家庭媒体库',
    type: MediaSourceType.macCmsApi,
    baseUrl: 'https://media.example.test/api.php/provide/vod/',
  );

  test('builds an encoded MacCMS search request and parses list media',
      () async {
    late Uri requestedUri;
    final client = MacCmsClient(fetcher: (uri) async {
      requestedUri = uri;
      return jsonEncode({
        'code': 1,
        'list': [
          {
            'vod_id': 42,
            'vod_name': '示例剧集',
            'vod_pic': '/poster.jpg',
            'vod_content': '<p>简介</p>',
            'vod_year': '2025',
            'vod_score': '8.6',
            'type_name': '电视剧',
          },
        ],
      });
    });

    final items = await client.list(source, query: '示例 剧集');

    expect(requestedUri.queryParameters['ac'], 'list');
    expect(requestedUri.queryParameters['wd'], '示例 剧集');
    expect(items, hasLength(1));
    expect(items.single.id, 'family:42');
    expect(items.single.remoteId, '42');
    expect(items.single.description, '简介');
    expect(items.single.posterUrl, 'https://media.example.test/poster.jpg');
  });

  test('parses grouped MacCMS playback options and episodes', () async {
    final client = MacCmsClient(fetcher: (_) async => jsonEncode({
          'list': [
            {
              'vod_id': '42',
              'vod_name': '示例剧集',
              'vod_pic': 'https://cdn.example.test/poster.jpg',
              'vod_play_from': r'线路 A$$$线路 B',
              'vod_play_url':
                  r'第1集$https://cdn.example.test/1.m3u8#第2集$https://cdn.example.test/2.mp4$$$正片$https://cdn.example.test/movie.m3u8',
            },
          ],
        }));

    final item = await client.detail(source, '42');

    expect(item, isNotNull);
    expect(item!.playbackOptions, hasLength(3));
    expect(item.episodes, hasLength(3));
    expect(item.episodes.first.playbackOption?.isHls, isTrue);
    expect(item.episodes[1].playbackOption?.isHls, isFalse);
    expect(item.playbackOptions.last.label, '线路 B · 正片');
  });

  test('isolates probe errors as a result', () async {
    final client = MacCmsClient(fetcher: (_) => throw Exception('offline'));

    final result = await client.probe(source);

    expect(result.isReachable, isFalse);
    expect(result.error, contains('offline'));
  });
}
