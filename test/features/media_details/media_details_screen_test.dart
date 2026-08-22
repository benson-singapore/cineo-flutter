import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cineo_flutter/core/models/media.dart';
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
}
