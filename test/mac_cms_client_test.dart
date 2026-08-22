import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cineo_flutter/core/models/media_source.dart';
import 'package:cineo_flutter/core/models/paged_media.dart';
import 'package:cineo_flutter/data/remote/mac_cms_client.dart';

void main() {
  const source = MediaSource(
    id: 'family',
    name: '家庭媒体库',
    type: MediaSourceType.macCmsApi,
    baseUrl: 'https://media.example.test/api.php/provide/vod/',
  );

  test('builds an encoded MacCMS videolist search request and parses media',
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
            'vod_content': '<p>简介&nbsp;&amp; 内容</p><script>忽略</script>',
            'vod_year': '2025',
            'vod_score': '8.6',
            'type_name': '电视剧',
          },
        ],
      });
    });

    final items = await client.list(source, query: '示例 剧集');

    expect(requestedUri.queryParameters['ac'], 'videolist');
    expect(requestedUri.queryParameters['wd'], '示例 剧集');
    expect(requestedUri.queryParameters['_'], isNotEmpty);
    expect(items, hasLength(1));
    expect(items.single.id, 'family:42');
    expect(items.single.remoteId, '42');
    expect(items.single.description, '简介 & 内容');
    expect(items.single.posterUrl, 'https://media.example.test/poster.jpg');
  });

  test('listPage sends category and page and parses pagination metadata',
      () async {
    late Uri requestedUri;
    final client = MacCmsClient(fetcher: (uri) async {
      requestedUri = uri;
      return jsonEncode({
        'code': 1,
        'page': '2',
        'pagecount': 5,
        'limit': '20',
        'total': '91',
        'list': [
          {
            'vod_id': 7,
            'vod_name': '第二页影片',
            'type_id': '12',
            'type_name': '电影',
          },
        ],
      });
    });

    final page = await client.listPage(
      source,
      query: '星际',
      category: '12',
      page: 2,
    );

    expect(requestedUri.queryParameters['ac'], 'videolist');
    expect(requestedUri.queryParameters['t'], '12');
    expect(requestedUri.queryParameters['wd'], '星际');
    expect(requestedUri.queryParameters['pg'], '2');
    expect(page, isA<PagedMedia>());
    expect(page.page, 2);
    expect(page.pageCount, 5);
    expect(page.limit, 20);
    expect(page.total, 91);
    expect(page.hasMore, isTrue);
    expect(page.items.single.title, '第二页影片');
  });

  test('list remains a compatibility wrapper around the first page items',
      () async {
    final client = MacCmsClient(
      fetcher: (_) async => jsonEncode({
        'page': 1,
        'pagecount': 3,
        'limit': 1,
        'total': 3,
        'list': [
          {'vod_id': 8, 'vod_name': '兼容影片'},
        ],
      }),
    );

    final items = await client.list(source, page: 1);

    expect(items, hasLength(1));
    expect(items.single.title, '兼容影片');
  });

  test('derives page count from total and limit when pagecount is absent',
      () async {
    final client = MacCmsClient(
      fetcher: (_) async => jsonEncode({
        'page': 2,
        'limit': '20',
        'total': 41,
        'list': [
          {'vod_id': 9, 'vod_name': '推导分页影片'},
        ],
      }),
    );

    final page = await client.listPage(source, page: 2);

    expect(page.pageCount, 3);
    expect(page.hasMore, isTrue);
  });

  test('normalizes invalid page metadata from nonstandard sources', () async {
    late Uri requestedUri;
    final client = MacCmsClient(
      fetcher: (uri) async {
        requestedUri = uri;
        return jsonEncode({
          'page': 0,
          'pagecount': 0,
          'limit': -1,
          'total': -1,
          'list': [
            {'vod_id': 10, 'vod_name': '非标准分页影片'},
          ],
        });
      },
    );

    final page = await client.listPage(source, page: 0);

    expect(requestedUri.queryParameters['pg'], '1');
    expect(page.page, 1);
    expect(page.pageCount, 1);
    expect(page.limit, 1);
    expect(page.total, 1);
    expect(page.hasMore, isFalse);
  });

  test('parses grouped MacCMS playback options and episodes', () async {
    final client = MacCmsClient(
        fetcher: (_) async => jsonEncode({
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

  test('retries one transient source connection failure', () async {
    var attempts = 0;
    final client = MacCmsClient(
      retryDelay: Duration.zero,
      fetcher: (_) async {
        attempts++;
        if (attempts == 1) {
          throw const HttpException('Connection closed while receiving data');
        }
        return jsonEncode({
          'list': [
            {
              'vod_id': '99',
              'vod_name': '重试成功的影片',
              'type_name': '电影',
            },
          ],
        });
      },
    );

    final items = await client.list(source);

    expect(attempts, 2);
    expect(items.single.title, '重试成功的影片');
  });

  test('does not retry deterministic HTTP status errors', () async {
    var attempts = 0;
    final client = MacCmsClient(
      retryDelay: Duration.zero,
      fetcher: (_) async {
        attempts++;
        throw const HttpException('站点返回 HTTP 404');
      },
    );

    await expectLater(client.list(source), throwsA(isA<HttpException>()));
    expect(attempts, 1);
  });

  test('accepts complete JSON when a source closes a chunked response early',
      () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((socket) async {
      await socket.first;
      final body = jsonEncode({
        'list': [
          {
            'vod_id': '101',
            'vod_name': '非标准传输的影片',
            'vod_pic': '/poster.jpg',
          },
        ],
      });
      socket.add(utf8.encode(
        'HTTP/1.1 200 OK\r\n'
        'Content-Type: application/json\r\n'
        'Transfer-Encoding: chunked\r\n'
        'Connection: close\r\n'
        '\r\n'
        '${utf8.encode(body).length.toRadixString(16)}\r\n'
        '$body\r\n',
      ));
      await socket.flush();
      await socket.close();
    });
    final localSource = MediaSource(
      id: 'early-close',
      name: '提前断开的视频源',
      type: MediaSourceType.macCmsApi,
      baseUrl: 'http://${server.address.address}:${server.port}/vod',
    );

    final items = await MacCmsClient(maxAttempts: 1).list(localSource);

    expect(items.single.title, '非标准传输的影片');
    expect(items.single.posterUrl, contains('/poster.jpg'));
  });

  test('keeps the HTTP client open while a large response is streaming',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"list":[');
      for (var index = 0; index < 80; index++) {
        if (index > 0) request.response.write(',');
        request.response.write(jsonEncode({
          'vod_id': '$index',
          'vod_name': '分块影片 $index',
          'vod_content': List.filled(1000, '内容').join(),
        }));
        await request.response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      request.response.write(']}');
      await request.response.close();
    });
    final localSource = MediaSource(
      id: 'streaming',
      name: '分块响应视频源',
      type: MediaSourceType.macCmsApi,
      baseUrl: 'http://${server.address.address}:${server.port}/vod',
    );

    final items = await MacCmsClient(maxAttempts: 1).list(localSource);

    expect(items, hasLength(80));
    expect(items.last.title, '分块影片 79');
  });
}
