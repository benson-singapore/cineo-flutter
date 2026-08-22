import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cineo_flutter/core/models/media.dart';
import 'package:cineo_flutter/core/models/tmdb_media.dart';
import 'package:cineo_flutter/core/theme/cineo_theme.dart';
import 'package:cineo_flutter/features/media_details/media_details_screen.dart';

void main() {
  const lineAEpisode = PlaybackOption(
    id: 'line-a-1',
    sourceId: 'site-1',
    label: '线路 A · 第01集',
    url: 'https://example.test/a-1.m3u8',
    quality: '线路 A',
    isHls: true,
  );
  const lineAEpisodeTwo = PlaybackOption(
    id: 'line-a-2',
    sourceId: 'site-1',
    label: '线路 A · 第02集',
    url: 'https://example.test/a-2.m3u8',
    quality: '线路 A',
    isHls: true,
  );
  const lineBEpisode = PlaybackOption(
    id: 'line-b-1',
    sourceId: 'site-1',
    label: '线路 B · 第01集',
    url: 'https://example.test/b-1.mp4',
    quality: '线路 B',
  );

  MediaItem buildSeries({String description = '测试简介'}) {
    return MediaItem(
      id: 'series',
      title: '测试剧集',
      description: description,
      year: 2026,
      kind: MediaKind.series,
      posterUrl: '',
      backdropUrl: '',
      genres: ['剧情'],
      rating: 8,
      duration: const Duration(minutes: 40),
      playbackOptions: const [lineAEpisode, lineAEpisodeTwo, lineBEpisode],
      episodes: const [
        Episode(
          id: 'episode-a-1',
          title: '第01集',
          season: 1,
          number: 1,
          playbackOption: lineAEpisode,
        ),
        Episode(
          id: 'episode-a-2',
          title: '02',
          season: 1,
          number: 2,
          playbackOption: lineAEpisodeTwo,
        ),
        Episode(
          id: 'episode-b-1',
          title: '第01集',
          season: 1,
          number: 1,
          playbackOption: lineBEpisode,
        ),
      ],
    );
  }

  Widget buildScreen({
    ValueChanged<PlaybackOption>? onPlay,
    String description = '测试简介',
  }) {
    return MaterialApp(
      theme: buildCineoTheme(),
      home: MediaDetailsScreen(
        media: buildSeries(description: description),
        favorite: false,
        onFavoriteChanged: (_) {},
        onPlay: onPlay ?? (_) {},
      ),
    );
  }

  testWidgets('renders formatted HTML description with a collapsible section',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final longDescription = List.filled(
      12,
      '这是一段较长的简介内容，用于验证移动端默认折叠。',
    ).join('<br>');

    await tester.pumpWidget(buildScreen(
      description:
          '<p>第一段&nbsp;&amp; 第二段</p><script>不应显示</script>$longDescription',
    ));
    await tester.pumpAndSettle();

    expect(find.text('简介'), findsOneWidget);
    expect(find.textContaining('<p>'), findsNothing);
    expect(find.textContaining('不应显示'), findsNothing);
    expect(find.text('展开简介'), findsOneWidget);

    await tester.tap(find.text('展开简介'));
    await tester.pumpAndSettle();
    expect(find.text('收起简介'), findsOneWidget);

    await tester.tap(find.text('收起简介'));
    await tester.pumpAndSettle();
    expect(find.text('展开简介'), findsOneWidget);
  });

  testWidgets('shows a friendly empty state when description is missing',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildScreen(description: ''));
    await tester.pumpAndSettle();

    expect(find.text('简介'), findsOneWidget);
    expect(find.text('暂无简介'), findsOneWidget);
  });

  testWidgets('groups playback options by line and filters episodes',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('线路 A'), findsOneWidget);
    expect(find.text('线路 A · 第01集'), findsNothing);
    expect(find.byKey(const ValueKey('episode-a-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('episode-a-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('episode-b-1')), findsNothing);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.text('线路 B'), findsOneWidget);
    expect(find.text('线路 B · 第01集'), findsNothing);

    await tester.tap(find.text('线路 B').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('episode-a-1')), findsNothing);
    expect(find.byKey(const ValueKey('episode-a-2')), findsNothing);
    expect(find.byKey(const ValueKey('episode-b-1')), findsOneWidget);
  });

  testWidgets('toggles episode order and keeps concise episode labels',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('正序'), findsOneWidget);
    expect(find.text('第1集'), findsNWidgets(1));
    expect(find.text('第2集'), findsOneWidget);

    await tester.tap(find.text('正序'));
    await tester.pumpAndSettle();
    expect(find.text('倒序'), findsOneWidget);
  });

  test('formats inconsistent source episode labels', () {
    const sourceOption = PlaybackOption(
      id: 'source',
      sourceId: 'site',
      label: '线路 · 第01集',
      url: 'https://example.test/1',
      quality: '线路',
    );
    expect(
      formatEpisodeLabel(const Episode(
        id: 'one',
        title: '未使用的标题',
        season: 1,
        number: 99,
        playbackOption: sourceOption,
      )),
      '第1集',
    );
    expect(
      formatEpisodeLabel(const Episode(
        id: 'site-number',
        title: '线路 360',
        season: 1,
        number: 3,
        playbackOption: PlaybackOption(
          id: 'site-number-option',
          sourceId: 'site',
          label: '360 · 第03集',
          url: 'https://example.test/3',
          quality: '360',
        ),
      )),
      '第3集',
    );
    expect(
      formatEpisodeLabel(const Episode(
        id: 'two',
        title: '02',
        season: 1,
        number: 99,
      )),
      '第2集',
    );
    expect(
      formatEpisodeLabel(const Episode(
        id: 'movie',
        title: '正片',
        season: 1,
        number: 1,
      )),
      '正片',
    );
  });

  testWidgets('uses TMDB metadata and opens the selected season library',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const tmdb = TmdbMediaDetails(
      id: 123,
      mediaType: TmdbMediaType.tv,
      title: 'TMDB 剧集名',
      originalTitle: 'TMDB Show',
      overview: '来自 TMDB 的简介',
      year: 2025,
      posterUrl: '',
      backdropUrl: '',
      rating: 8.6,
      runtime: 45,
      seasons: [
        TmdbSeasonMetadata(
          id: 1,
          seasonNumber: 1,
          name: '第一季',
          overview: '',
          posterUrl: '',
          episodes: [
            TmdbEpisodeMetadata(
              id: 11,
              seasonNumber: 1,
              episodeNumber: 1,
              name: '开端',
              overview: '第一集简介',
              stillUrl: '',
              rating: 8.1,
              runtime: 45,
            ),
            TmdbEpisodeMetadata(
              id: 12,
              seasonNumber: 1,
              episodeNumber: 2,
              name: '转折',
              overview: '第二集简介',
              stillUrl: '',
              rating: 8.2,
              runtime: 45,
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp(
      theme: buildCineoTheme(),
      home: MediaDetailsScreen(
        media: buildSeries(),
        favorite: false,
        onFavoriteChanged: (_) {},
        onPlay: (_) {},
        onLoadTmdbDetails: (_) async => tmdb,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('TMDB 剧集名'), findsOneWidget);
    expect(find.text('来自 TMDB 的简介'), findsOneWidget);
    expect(find.textContaining('8.6 分'), findsOneWidget);
    expect(find.text('开端'), findsOneWidget);

    await tester.tap(find.text('查看全部'));
    await tester.pumpAndSettle();
    expect(find.text('第1季 · 全部剧集'), findsOneWidget);
    expect(find.byKey(const ValueKey('library-episode-a-1')), findsOneWidget);
    expect(find.text('开端'), findsOneWidget);
  });

  testWidgets('falls back when TMDB loading fails', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: buildCineoTheme(),
      home: MediaDetailsScreen(
        media: buildSeries(),
        favorite: false,
        onFavoriteChanged: (_) {},
        onPlay: (_) {},
        onLoadTmdbDetails: (_) async => throw StateError('offline'),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('测试剧集'), findsOneWidget);
    expect(find.text('测试简介'), findsOneWidget);
    expect(find.text('查看全部'), findsOneWidget);
  });

  testWidgets('manually searches and applies a TMDB match', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const match = TmdbMediaMatch(
      id: 321,
      mediaType: TmdbMediaType.tv,
      title: '正确剧集名',
      originalTitle: 'Correct Show',
      overview: '正确简介',
      year: 2024,
      posterUrl: '',
      backdropUrl: '',
      rating: 8.4,
    );
    const details = TmdbMediaDetails(
      id: 321,
      mediaType: TmdbMediaType.tv,
      title: '正确剧集名',
      originalTitle: 'Correct Show',
      overview: '正确简介',
      year: 2024,
      posterUrl: '',
      backdropUrl: '',
      rating: 8.4,
      runtime: 45,
    );
    String? query;
    TmdbMediaType? type;
    int? year;
    await tester.pumpWidget(MaterialApp(
      theme: buildCineoTheme(),
      home: MediaDetailsScreen(
        media: buildSeries(),
        favorite: false,
        onFavoriteChanged: (_) {},
        onPlay: (_) {},
        onSearchTmdbMatches: (value, valueType, valueYear) async {
          query = value;
          type = valueType;
          year = valueYear;
          return const [match];
        },
        onSelectTmdbMatch: (_) async => details,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byTooltip('手动匹配'), findsOneWidget);
    await tester.tap(find.byTooltip('手动匹配'));
    await tester.pumpAndSettle();
    expect(find.text('手动匹配'), findsOneWidget);
    expect(find.text('搜索匹配项'), findsOneWidget);

    await tester.tap(find.text('搜索匹配项'));
    await tester.pumpAndSettle();
    expect(query, '测试剧集');
    expect(type, TmdbMediaType.tv);
    expect(year, 2026);
    expect(find.text('正确剧集名'), findsOneWidget);
    expect(find.text('Correct Show  ·  2024  ·  8.4 分'), findsOneWidget);

    await tester.tap(find.text('正确剧集名'));
    await tester.pumpAndSettle();
    expect(find.text('正确简介'), findsOneWidget);
    expect(find.text('正确剧集名'), findsOneWidget);
  });
}
