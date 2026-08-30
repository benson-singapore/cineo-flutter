import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cineo_flutter/core/models/media.dart';
import 'package:cineo_flutter/core/models/tmdb_media.dart';
import 'package:cineo_flutter/core/theme/cineo_theme.dart';
import 'package:cineo_flutter/data/download/download_service.dart';
import 'package:cineo_flutter/features/media_details/episode_library_screen.dart';
import 'package:cineo_flutter/features/media_details/media_details_screen.dart';

class _DelayedDetailsRepository {
  _DelayedDetailsRepository(this.detailsFuture);

  final Future<MediaItem?> detailsFuture;

  Future<MediaItem?> loadDetails(MediaItem item) => detailsFuture;
}

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

  MediaItem buildSeries({
    String description = '测试简介',
    String? sourceId,
    String? sourceName,
  }) {
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
      sourceId: sourceId,
      sourceName: sourceName,
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
    List<WatchProgress> watchHistory = const [],
    double imageAspectRatio = 2 / 3,
    DownloadService? downloadService,
  }) {
    return MaterialApp(
      theme: buildCineoTheme(),
      home: MediaDetailsScreen(
        media: buildSeries(description: description),
        favorite: false,
        initialWatchHistory: watchHistory,
        onFavoriteChanged: (_, __) {},
        onPlay: (_, option) => (onPlay ?? (_) {})(option),
        imageAspectRatio: imageAspectRatio,
        downloadService: downloadService,
      ),
    );
  }

  testWidgets('shows play and resumes the latest unfinished episode',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    PlaybackOption? played;
    final history = [
      WatchProgress(
        mediaId: 'series',
        episodeId: lineAEpisodeTwo.id,
        episodeLabel: '第2集',
        episodeNumber: 2,
        episodeCount: 2,
        position: const Duration(minutes: 12),
        duration: const Duration(minutes: 40),
        updatedAt: DateTime(2026, 1, 2),
      ),
    ];

    await tester.pumpWidget(buildScreen(
      watchHistory: history,
      onPlay: (option) => played = option,
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('primary-play-button')), findsOneWidget);
    expect(find.text('继续播放'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('episode-progress-episode-a-2')),
      findsOneWidget,
    );

    await _scrollDetailPage(tester);
    await tester.tap(find.byKey(const ValueKey('primary-play-button')));
    expect(played?.id, lineAEpisodeTwo.id);
  });

  testWidgets('shows the download button for HLS episodes and opens the sheet',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final service = DownloadService();

    await tester.pumpWidget(buildScreen(downloadService: service));
    await tester.pump(const Duration(milliseconds: 100));
    await _scrollDetailPageWithPump(tester);

    expect(find.byKey(const ValueKey('download-button')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('download-button'))).dx,
      lessThan(tester.getTopLeft(find.byTooltip('收藏')).dx),
    );

    await tester.tap(find.byKey(const ValueKey('download-button')));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('缓存下载'), findsOneWidget);
    expect(find.text('全部加入'), findsOneWidget);
    expect(find.textContaining('第 1 集'), findsWidgets);
  });

  testWidgets('hides the download button when all playback options are MP4',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const mp4Episode = Episode(
      id: 'episode-mp4',
      title: '正片',
      season: 1,
      number: 1,
      playbackOption: lineBEpisode,
    );
    final mp4Media = buildSeries().copyWith(
      playbackOptions: const [lineBEpisode],
      episodes: [mp4Episode],
    );

    final service = DownloadService();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildCineoTheme(),
        home: MediaDetailsScreen(
          media: mp4Media,
          favorite: false,
          onFavoriteChanged: (_, __) {},
          onPlay: (_, __) {},
          downloadService: service,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await _scrollDetailPageWithPump(tester);

    expect(find.byKey(const ValueKey('download-button')), findsNothing);
    expect(find.byTooltip('收藏'), findsOneWidget);
  });

  testWidgets('uses the configured image aspect ratio for the hero poster',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(buildScreen(imageAspectRatio: 16 / 9));
    await tester.pumpAndSettle();

    final posterSize = tester.getSize(
      find.byKey(const ValueKey('detail-poster')),
    );
    expect(posterSize.width, 800);
    expect(posterSize.height, closeTo(450, 0.1));
  });

  testWidgets('defaults the primary button to the first available episode',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    PlaybackOption? played;

    await tester.pumpWidget(buildScreen(onPlay: (option) => played = option));
    await tester.pumpAndSettle();

    expect(find.text('播放'), findsOneWidget);
    await _scrollDetailPage(tester);
    await tester.tap(find.byKey(const ValueKey('primary-play-button')));
    expect(played?.id, lineAEpisode.id);
  });

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

    await _scrollDetailPage(tester);
    await tester.tap(find.text('展开简介'));
    await tester.pumpAndSettle();
    expect(find.text('收起简介'), findsOneWidget);

    await tester.tap(find.text('收起简介'));
    await tester.pumpAndSettle();
    expect(find.text('展开简介'), findsOneWidget);
  });

  testWidgets('uses a poster hero without a fixed detail app bar',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.byType(SliverAppBar), findsNothing);
    expect(find.byTooltip('返回'), findsOneWidget);
    expect(tester.getTopLeft(find.byTooltip('返回')).dx, lessThan(100));
    final poster = tester.getSize(find.byKey(const ValueKey('detail-poster')));
    expect(poster.width / poster.height, closeTo(2 / 3, .01));
  });

  testWidgets('uses a five-line summary and 16:9 episode previews',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final longDescription = List.filled(6, '这是用于简介折叠展示的内容。').join('\n');

    await tester.pumpWidget(buildScreen(description: longDescription));
    await tester.pumpAndSettle();

    expect(find.text('展开简介'), findsOneWidget);
    final image = tester.getSize(
      find.byKey(const ValueKey('preview-image-episode-a-1')),
    );
    expect(image.width / image.height, closeTo(16 / 9, .01));
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

  testWidgets('shows episode loading until repository details resolve',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final details = buildSeries();
    final completer = Completer<MediaItem?>();

    await tester.pumpWidget(MaterialApp(
      theme: buildCineoTheme(),
      home: MediaDetailsScreen(
        media: details.copyWith(episodes: const [], playbackOptions: const []),
        favorite: false,
        onFavoriteChanged: (_, __) {},
        onPlay: (_, __) {},
        repository: _DelayedDetailsRepository(completer.future),
      ),
    ));
    await tester.pump();

    expect(find.text('剧集'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('episode-loading')), findsOneWidget);
    expect(find.byKey(const ValueKey('preview-episode-a-1')), findsNothing);

    completer.complete(details);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('episode-loading')), findsNothing);
    expect(find.byKey(const ValueKey('preview-episode-a-1')), findsOneWidget);
  });

  testWidgets('starts the supplied detail loader after the page is built',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final completer = Completer<MediaItem?>();
    var loadCount = 0;

    await tester.pumpWidget(MaterialApp(
      theme: buildCineoTheme(),
      home: MediaDetailsScreen(
        media: buildSeries().copyWith(
          episodes: const [],
          playbackOptions: const [],
        ),
        favorite: false,
        onFavoriteChanged: (_, __) {},
        onPlay: (_, __) {},
        onLoadMediaDetails: (_) {
          loadCount++;
          return completer.future;
        },
      ),
    ));
    await tester.pump();

    expect(loadCount, 1);
    expect(find.byKey(const ValueKey('episode-loading')), findsOneWidget);

    completer.complete(buildSeries());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('preview-episode-a-1')), findsOneWidget);
  });

  testWidgets('shows the existing empty episode state after loading',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final completer = Completer<MediaItem?>();

    await tester.pumpWidget(MaterialApp(
      theme: buildCineoTheme(),
      home: MediaDetailsScreen(
        media: buildSeries().copyWith(
          episodes: const [],
          playbackOptions: const [],
        ),
        favorite: false,
        onFavoriteChanged: (_, __) {},
        onPlay: (_, __) {},
        repository: _DelayedDetailsRepository(completer.future),
      ),
    ));
    await tester.pump();
    expect(find.byKey(const ValueKey('episode-loading')), findsOneWidget);

    completer.complete(null);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('episode-loading')), findsNothing);
    expect(find.text('当前季暂无可播放剧集'), findsOneWidget);
  });

  testWidgets('groups playback options by line and filters episode previews',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('线路 A'), findsOneWidget);
    expect(find.text('线路 A · 第01集'), findsNothing);
    expect(find.byKey(const ValueKey('preview-episode-a-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('preview-episode-a-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('preview-episode-b-1')), findsNothing);

    final sourceB = find.byKey(
      const ValueKey('source-线路 B'),
      skipOffstage: false,
    );
    await _scrollDetailPage(tester);
    await tester.tap(sourceB);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('preview-episode-a-1')), findsNothing);
    expect(find.byKey(const ValueKey('preview-episode-a-2')), findsNothing);
    expect(find.byKey(const ValueKey('preview-episode-b-1')), findsOneWidget);
  });

  testWidgets('removes the inline episode picker from the detail screen',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.text('查看全部'), findsOneWidget);
  });

  testWidgets('chooses an alternative media site from the detail sheet',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final current = buildSeries(
      sourceId: 'site-1',
      sourceName: '当前资源站',
    );
    const alternative = MediaItem(
      id: 'site-2:remote-2',
      sourceId: 'site-2',
      sourceName: '如意资源站',
      remoteId: 'remote-2',
      title: '测试剧集',
      description: '备用站点版本',
      year: 2026,
      kind: MediaKind.series,
      posterUrl: '',
      backdropUrl: '',
      genres: ['剧情'],
      rating: 8,
      duration: Duration(minutes: 40),
      category: '韩国剧',
    );
    MediaItem? loaded;

    await tester.pumpWidget(MaterialApp(
      theme: buildCineoTheme(),
      home: MediaDetailsScreen(
        media: current,
        favorite: false,
        onFavoriteChanged: (_, __) {},
        onPlay: (_, __) {},
        onSearchOtherSources: (_) async => [alternative],
        onLoadAlternative: (media) async {
          loaded = media;
          return media;
        },
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final switchSite = find.byKey(const ValueKey('switch-media-site'));
    await _scrollDetailPage(tester);
    await tester.tap(switchSite);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('选择资源站'), findsOneWidget);
    expect(find.text('当前资源站'), findsNWidgets(2));
    expect(find.text('如意资源站'), findsOneWidget);
    expect(find.byKey(const ValueKey('media-site-site-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('media-site-site-2')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('media-site-site-2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(loaded?.sourceId, 'site-2');
    expect(find.text('选择资源站'), findsNothing);
    expect(find.text('如意资源站'), findsOneWidget);
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
      cast: [
        TmdbCastMember(
          id: 99,
          name: '演员甲',
          character: '主角',
          profileUrl: '',
        ),
      ],
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
        onFavoriteChanged: (_, __) {},
        onPlay: (_, __) {},
        onLoadTmdbDetails: (_) async => tmdb,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('TMDB 剧集名'), findsOneWidget);
    expect(find.text('来自 TMDB 的简介'), findsOneWidget);
    expect(find.textContaining('8.6 分'), findsOneWidget);
    expect(find.textContaining('开端'), findsOneWidget);
    expect(find.byKey(const ValueKey('cast-section')), findsOneWidget);
    expect(find.text('演员甲'), findsOneWidget);

    await _scrollDetailPage(tester);
    await tester.tap(find.text('查看全部'));
    await tester.pumpAndSettle();
    expect(find.text('第1季 · 全部剧集'), findsOneWidget);
    expect(find.byKey(const ValueKey('library-episode-a-1')), findsOneWidget);
    expect(find.textContaining('开端'), findsOneWidget);
    expect(find.byKey(const ValueKey('episode-sort-toggle')), findsOneWidget);
    expect(find.text('正序'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('episode-sort-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('倒序'), findsOneWidget);
  });

  testWidgets('can return to the top of the episode library', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final episodes = List<Episode>.generate(
      10,
      (index) => Episode(
        id: 'library-episode-${index + 1}',
        title: '第${index + 1}集',
        season: 1,
        number: index + 1,
        playbackOption: PlaybackOption(
          id: 'library-option-${index + 1}',
          sourceId: 'site-1',
          label: '第${index + 1}集',
          url: 'https://example.test/${index + 1}.m3u8',
          quality: '线路 A',
          isHls: true,
        ),
      ),
    );

    await tester.pumpWidget(MaterialApp(
      theme: buildCineoTheme(),
      home: EpisodeLibraryScreen(
        media: buildSeries(),
        episodes: episodes,
        tmdbSeason: null,
        fallbackPosterUrl: '',
        onPlay: (_) {},
      ),
    ));
    await tester.pumpAndSettle();

    final firstEpisodeBefore = tester.getTopLeft(
      find.byKey(const ValueKey('library-library-episode-1')),
    );
    expect(firstEpisodeBefore.dy, greaterThan(0));

    await tester.tap(find.byKey(const ValueKey('episode-sort-toggle')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('library-library-episode-10')),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('library-library-episode-10')),
      400,
      scrollable: find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('episode-back-to-top')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('episode-back-to-top')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('episode-back-to-top')), findsNothing);
  });

  testWidgets('uses supplied TMDB details without loading them again',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const tmdb = TmdbMediaDetails(
      id: 7,
      mediaType: TmdbMediaType.tv,
      title: '预取 TMDB 剧集名',
      originalTitle: 'Prefetched Show',
      overview: '预取的 TMDB 简介',
      year: 2025,
      posterUrl: '',
      backdropUrl: '',
      rating: 8.7,
      runtime: 45,
    );
    var loadCount = 0;

    await tester.pumpWidget(MaterialApp(
      theme: buildCineoTheme(),
      home: MediaDetailsScreen(
        media: buildSeries(),
        favorite: false,
        onFavoriteChanged: (_, __) {},
        onPlay: (_, __) {},
        initialTmdbDetails: tmdb,
        onLoadTmdbDetails: (_) async {
          loadCount++;
          return null;
        },
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('预取 TMDB 剧集名'), findsOneWidget);
    expect(find.text('预取的 TMDB 简介'), findsOneWidget);
    expect(loadCount, 0);
  });

  testWidgets('upgrades a supplied TMDB preview after the page opens',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const preview = TmdbMediaDetails(
      id: 7,
      mediaType: TmdbMediaType.tv,
      title: '预览标题',
      originalTitle: 'Preview Show',
      overview: '搜索返回的简介',
      year: 2025,
      posterUrl: '',
      backdropUrl: '',
      rating: 8.0,
      runtime: null,
      level: TmdbDetailsLevel.preview,
    );
    const base = TmdbMediaDetails(
      id: 7,
      mediaType: TmdbMediaType.tv,
      title: '完整标题',
      originalTitle: 'Preview Show',
      overview: '基础详情简介',
      year: 2025,
      posterUrl: '',
      backdropUrl: '',
      rating: 8.4,
      runtime: 45,
      level: TmdbDetailsLevel.base,
    );
    const enriched = TmdbMediaDetails(
      id: 7,
      mediaType: TmdbMediaType.tv,
      title: '完整标题',
      originalTitle: 'Preview Show',
      overview: '基础详情简介',
      year: 2025,
      posterUrl: '',
      backdropUrl: '',
      rating: 8.4,
      runtime: 45,
      level: TmdbDetailsLevel.enriched,
      cast: [
        TmdbCastMember(
          id: 1,
          name: '异步演员',
          character: '角色',
          profileUrl: '',
        ),
      ],
    );
    var baseCalls = 0;
    var enrichmentCalls = 0;
    final baseCompleter = Completer<TmdbMediaDetails?>();
    final enrichmentCompleter = Completer<TmdbMediaDetails?>();

    await tester.pumpWidget(MaterialApp(
      theme: buildCineoTheme(),
      home: MediaDetailsScreen(
        media: buildSeries(),
        favorite: false,
        onFavoriteChanged: (_, __) {},
        onPlay: (_, __) {},
        initialTmdbDetails: preview,
        onLoadTmdbDetails: (_) {
          baseCalls++;
          return baseCompleter.future;
        },
        onLoadTmdbEnrichment: (_) {
          enrichmentCalls++;
          return enrichmentCompleter.future;
        },
      ),
    ));

    expect(find.text('预览标题'), findsOneWidget);
    expect(baseCalls, 1);
    expect(enrichmentCalls, 0);

    baseCompleter.complete(base);
    await tester.pump();
    await tester.pump();

    expect(find.text('完整标题'), findsOneWidget);
    expect(enrichmentCalls, 1);

    enrichmentCompleter.complete(enriched);
    await tester.pump();
    await tester.pump();

    expect(baseCalls, 1);
    expect(enrichmentCalls, 1);
    expect(find.text('完整标题'), findsOneWidget);
    expect(find.byKey(const ValueKey('cast-section')), findsOneWidget);
    expect(find.text('异步演员'), findsOneWidget);
  });

  testWidgets('falls back when TMDB loading fails', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: buildCineoTheme(),
      home: MediaDetailsScreen(
        media: buildSeries(),
        favorite: false,
        onFavoriteChanged: (_, __) {},
        onPlay: (_, __) {},
        onLoadTmdbDetails: (_) async => throw StateError('offline'),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('测试剧集'), findsOneWidget);
    expect(find.text('测试简介'), findsOneWidget);
    expect(find.text('查看全部'), findsOneWidget);
    expect(find.text('8.0 分'), findsNothing);
    expect(find.text('40 分钟'), findsNothing);
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
        onFavoriteChanged: (_, __) {},
        onPlay: (_, __) {},
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

    final manualMatch = find.byTooltip('手动匹配');
    await _scrollDetailPage(tester);
    expect(manualMatch, findsOneWidget);
    await tester.tap(manualMatch);
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

Future<void> _scrollDetailPage(WidgetTester tester) async {
  await tester.drag(
    find.byType(CustomScrollView),
    const Offset(0, -900),
  );
  await tester.pumpAndSettle();
}

Future<void> _scrollDetailPageWithPump(WidgetTester tester) async {
  await tester.drag(
    find.byType(CustomScrollView),
    const Offset(0, -900),
  );
  await tester.pump(const Duration(milliseconds: 100));
}
