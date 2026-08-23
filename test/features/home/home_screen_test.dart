import 'package:cineo_flutter/core/models/media.dart';
import 'package:cineo_flutter/core/models/home_category_rail.dart';
import 'package:cineo_flutter/core/theme/cineo_theme.dart';
import 'package:cineo_flutter/features/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

MediaItem _media(
  String id,
  String title, {
  String? categoryId,
  List<String> genres = const [],
}) {
  return MediaItem(
    id: id,
    title: title,
    description: '测试内容',
    year: 2026,
    kind: MediaKind.series,
    posterUrl: '',
    backdropUrl: '',
    genres: genres,
    rating: 8,
    duration: const Duration(minutes: 42),
    categoryId: categoryId,
  );
}

Widget _subject({
  required List<MediaItem> items,
  required HomeRailSeeAllCallback onSeeAll,
  List<HomeCategoryRail> categoryRails = const [],
  Future<void> Function()? onRefresh,
  List<MediaItem> continueWatching = const [],
  List<MediaItem> favorites = const [],
  Future<void> Function(MediaItem)? onContinueWatching,
  VoidCallback? onOpenSearch,
}) {
  return MaterialApp(
    theme: buildCineoTheme(),
    home: HomeScreen(
      items: items,
      continueWatching: continueWatching,
      favorites: favorites,
      onOpenMedia: (_) async {},
      onContinueWatching: onContinueWatching,
      categoryRails: categoryRails,
      onSeeAll: onSeeAll,
      onRefresh: onRefresh,
      onOpenSearch: onOpenSearch,
    ),
  );
}

void main() {
  testWidgets('hero prioritizes and resumes the latest continued media',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final recommended = _media('recommended-1', '推荐视频');
    final resumed = _media('resume-1', '上次观看的视频');
    MediaItem? selected;

    await tester.pumpWidget(
      _subject(
        items: [recommended],
        continueWatching: [resumed],
        onContinueWatching: (media) async {
          selected = media;
        },
        onSeeAll: (_, __, ___) {},
      ),
    );
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('home-hero-media-resume-1')), findsOneWidget);
    expect(find.text('继续观看'), findsWidgets);

    await tester.ensureVisible(find.byKey(const ValueKey('home-hero-action')));
    await tester.tap(find.byKey(const ValueKey('home-hero-action')));
    expect(selected, same(resumed));
  });

  testWidgets('hero cover fills the available top width without side gaps',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final featured = _media('featured', '顶部封面');

    await tester.pumpWidget(
      _subject(
        items: [featured],
        onSeeAll: (_, __, ___) {},
      ),
    );
    await tester.pumpAndSettle();

    final hero = tester.getSize(
      find.byKey(const ValueKey('home-hero-media-featured')),
    );
    expect(hero.width, 800);
    expect(hero.height, closeTo(800 * 4 / 3, .1));
  });

  testWidgets('top bar opens search when the search action is tapped',
      (tester) async {
    var searchOpened = false;
    await tester.pumpWidget(
      _subject(
        items: [_media('featured', '顶部封面')],
        onSeeAll: (_, __, ___) {},
        onOpenSearch: () => searchOpened = true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('搜索'));

    expect(searchOpened, isTrue);
  });

  testWidgets('shows all favorite media below continue watching',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final favorites = [
      _media('favorite-1', '收藏一'),
      _media('favorite-2', '收藏二'),
    ];

    await tester.pumpWidget(
      _subject(
        items: [_media('featured', '首页资源')],
        continueWatching: [_media('resume', '继续观看资源')],
        favorites: favorites,
        onSeeAll: (_, __, ___) {},
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('我的收藏'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('我的收藏'), findsOneWidget);
    expect(find.text('收藏一'), findsOneWidget);
    expect(find.text('收藏二'), findsOneWidget);
  });

  testWidgets('fixed short drama rail sends its source category id',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final items = [_media('1', '短剧一')];
    final shortDrama = [
      _media('short-1', '短剧一', categoryId: 'tid-short', genres: ['短剧']),
      _media('short-2', '短剧二', categoryId: 'tid-short', genres: ['短剧']),
    ];
    String? title;
    List<String>? categoryIds;

    await tester.pumpWidget(
      _subject(
        items: items,
        categoryRails: [
          HomeCategoryRail(
            title: '短剧',
            categoryIds: const ['tid-short'],
            items: shortDrama,
          ),
        ],
        onSeeAll: (railTitle, _, ids) {
          title = railTitle;
          categoryIds = ids;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byTooltip('查看全部短剧'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byTooltip('查看全部短剧').first);

    expect(title, '短剧');
    expect(categoryIds, ['tid-short']);
  });

  testWidgets('fixed movie rail sends its configured source category ids',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final items = [
      _media('1', '电影一', categoryId: 'tid-a'),
      _media('2', '电影二', categoryId: 'tid-b'),
    ];
    List<String>? categoryIds;

    await tester.pumpWidget(
      _subject(
        items: items,
        categoryRails: [
          HomeCategoryRail(
            title: '电影',
            categoryIds: const ['tid-movie-a', 'tid-movie-b'],
            items: items,
          ),
        ],
        onSeeAll: (_, __, ids) => categoryIds = ids,
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byTooltip('查看全部电影'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byTooltip('查看全部电影').first);

    expect(categoryIds, ['tid-movie-a', 'tid-movie-b']);
  });

  testWidgets('removes the homepage category filter strip', (tester) async {
    await tester.pumpWidget(
      _subject(
        items: [_media('1', '电影')],
        categoryRails: [
          HomeCategoryRail(
            title: '电影',
            categoryIds: const ['movie'],
            items: [_media('1', '电影')],
          ),
        ],
        onSeeAll: (_, __, ___) {},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.text('全部'), findsNothing);
    expect(find.text('电影'), findsWidgets);
  });

  testWidgets('pulling down refreshes while keeping loaded content visible',
      (tester) async {
    var refreshCount = 0;
    await tester.pumpWidget(
      _subject(
        items: [_media('1', '已缓存内容')],
        onSeeAll: (_, __, ___) {},
        onRefresh: () async => refreshCount++,
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 420));
    await tester.pumpAndSettle();

    expect(refreshCount, 1);
    expect(find.text('已缓存内容'), findsWidgets);
  });
}
