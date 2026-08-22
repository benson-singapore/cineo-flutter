import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cineo_flutter/core/models/tmdb_media.dart';
import 'package:cineo_flutter/data/remote/tmdb_client.dart';

void main() {
  const token = 'test-bearer-token';

  test('sends Bearer token and Chinese search parameters', () async {
    late Uri uri;
    late Map<String, String> headers;
    final client = TmdbClient(
      bearerToken: token,
      fetcher: (requested, requestHeaders) async {
        uri = requested;
        headers = requestHeaders;
        return TmdbHttpResponse(
          statusCode: 200,
          body: jsonEncode({
            'results': [
              {
                'id': 7,
                'media_type': 'tv',
                'name': '三体',
                'original_name': '3 Body Problem',
                'first_air_date': '2024-03-21',
                'poster_path': '/poster.jpg',
                'backdrop_path': null,
                'vote_average': 8.1,
              },
            ],
          }),
        );
      },
    );

    final results = await client.search('三体');

    expect(uri.path, endsWith('/3/search/multi'));
    expect(uri.queryParameters['query'], '三体');
    expect(uri.queryParameters['language'], 'zh-CN');
    expect(
      headers.entries
          .firstWhere((entry) => entry.key.toLowerCase() == 'authorization')
          .value,
      'Bearer $token',
    );
    expect(results.single.mediaType, TmdbMediaType.tv);
    expect(
        results.single.posterUrl, 'https://image.tmdb.org/t/p/w500/poster.jpg');
    expect(results.single.backdropUrl, isEmpty);
  });

  test('ranks exact title and year before a higher-rated loose match',
      () async {
    final client = TmdbClient(
      bearerToken: token,
      fetcher: (_, __) async => TmdbHttpResponse(
        statusCode: 200,
        body: jsonEncode({
          'results': [
            {
              'id': 1,
              'media_type': 'tv',
              'name': '庆余年 第二季',
              'first_air_date': '2024-05-16',
              'vote_average': 9.9,
            },
            {
              'id': 2,
              'media_type': 'tv',
              'name': '庆余年',
              'first_air_date': '2019-12-01',
              'vote_average': 7.5,
            },
          ],
        }),
      ),
    );

    final result = await client.findBestMatch('庆余年', year: 2019);

    expect(result?.id, 2);
  });

  test('loads TV details and episode metadata with image fallbacks', () async {
    final requestedPaths = <String>[];
    final client = TmdbClient(
      bearerToken: token,
      fetcher: (uri, _) async {
        requestedPaths.add(uri.path);
        if (uri.path.endsWith('/season/1')) {
          return TmdbHttpResponse(
            statusCode: 200,
            body: jsonEncode({
              'id': 80,
              'season_number': 1,
              'name': '第一季',
              'episodes': [
                {
                  'id': 801,
                  'episode_number': 1,
                  'name': '第一集',
                  'still_path': '/episode.jpg',
                  'overview': '第一集简介',
                  'vote_average': 8.5,
                  'runtime': 46,
                },
              ],
            }),
          );
        }
        return TmdbHttpResponse(
          statusCode: 200,
          body: jsonEncode({
            'id': 8,
            'name': '测试剧',
            'original_name': 'Test Show',
            'first_air_date': '2025-01-01',
            'overview': '剧集简介',
            'poster_path': '/show.jpg',
            'backdrop_path': '/backdrop.jpg',
            'vote_average': 8.6,
            'episode_run_time': [45],
            'seasons': [
              {
                'id': 80,
                'season_number': 1,
                'name': '第一季',
                'poster_path': null,
              },
            ],
          }),
        );
      },
    );

    final details = await client.getDetails(const TmdbMediaMatch(
      id: 8,
      mediaType: TmdbMediaType.tv,
      title: '测试剧',
      originalTitle: 'Test Show',
      overview: '',
      year: 2025,
      posterUrl: 'https://image.tmdb.org/t/p/w500/show.jpg',
      backdropUrl: '',
      rating: 8,
    ));

    expect(requestedPaths, ['/3/tv/8', '/3/tv/8/season/1']);
    expect(details?.seasons.single.episodes.single.stillUrl,
        'https://image.tmdb.org/t/p/w500/episode.jpg');
    expect(details?.seasons.single.posterUrl, isEmpty);
    expect(details?.runtime, 45);
  });

  test('parses a season endpoint and episode still image', () async {
    final client = TmdbClient(
      bearerToken: token,
      fetcher: (_, __) async => TmdbHttpResponse(
        statusCode: 200,
        body: jsonEncode({
          'id': 80,
          'season_number': 1,
          'name': '第一季',
          'episodes': [
            {
              'id': 801,
              'season_number': 1,
              'episode_number': 2,
              'name': '第二集',
              'overview': '这一集的简介',
              'still_path': '/still.jpg',
              'vote_average': 8.4,
              'runtime': 48,
            },
          ],
        }),
      ),
    );

    final season = await client.getSeason(8, 1);

    expect(season.episodes.single.episodeNumber, 2);
    expect(season.episodes.single.stillUrl,
        'https://image.tmdb.org/t/p/w500/still.jpg');
    expect(season.episodes.single.runtime, 48);
  });

  test('parses movie details and falls back when images are absent', () async {
    final client = TmdbClient(
      bearerToken: token,
      fetcher: (_, __) async => TmdbHttpResponse(
        statusCode: 200,
        body: jsonEncode({
          'id': 12,
          'title': '测试电影',
          'original_title': 'Test Movie',
          'release_date': '2023-09-02',
          'overview': '电影简介',
          'poster_path': null,
          'backdrop_path': null,
          'vote_average': 7.2,
          'runtime': 113,
        }),
      ),
    );

    final details = await client.getDetails(const TmdbMediaMatch(
      id: 12,
      mediaType: TmdbMediaType.movie,
      title: '测试电影',
      originalTitle: 'Test Movie',
      overview: '',
      year: 2023,
      posterUrl: 'https://image.tmdb.org/t/p/w500/fallback.jpg',
      backdropUrl: '',
      rating: 0,
    ));

    expect(details?.title, '测试电影');
    expect(details?.year, 2023);
    expect(details?.runtime, 113);
    expect(details?.posterUrl, 'https://image.tmdb.org/t/p/w500/fallback.jpg');
    expect(details?.seasons, isEmpty);
  });

  test('maps HTTP failures to typed errors without exposing the token',
      () async {
    final client = TmdbClient(
      bearerToken: token,
      fetcher: (_, __) async => const TmdbHttpResponse(
          statusCode: 401, body: '{"status_message":"bad token"}'),
    );

    await expectLater(
      client.search('测试'),
      throwsA(
        isA<TmdbApiException>()
            .having((error) => error.kind, 'kind', TmdbErrorKind.unauthorized)
            .having(
                (error) => error.toString(), 'message', isNot(contains(token))),
      ),
    );
  });

  test('rejects malformed JSON as an invalid response', () async {
    final client = TmdbClient(
      bearerToken: token,
      fetcher: (_, __) async =>
          const TmdbHttpResponse(statusCode: 200, body: 'not-json'),
    );

    await expectLater(
      client.search('测试'),
      throwsA(isA<TmdbApiException>().having(
          (error) => error.kind, 'kind', TmdbErrorKind.invalidResponse)),
    );
  });
}
