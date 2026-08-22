import 'package:cineo_flutter/core/models/media.dart';
import 'package:cineo_flutter/core/models/paged_media.dart';
import 'package:cineo_flutter/core/theme/cineo_theme.dart';
import 'package:cineo_flutter/features/search/category_browse_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  MediaItem media(String title) {
    return MediaItem(
      id: title,
      title: title,
      description: '测试内容',
      year: 2026,
      kind: MediaKind.movie,
      posterUrl: '',
      backdropUrl: '',
      genres: const ['剧情'],
      rating: 8,
      duration: const Duration(minutes: 100),
    );
  }

  Widget buildSubject({
    required Future<PagedMedia> Function(int page) onLoad,
    List<MediaItem> initialItems = const [],
  }) {
    return MaterialApp(
      theme: buildCineoTheme(),
      home: CategoryBrowseScreen(
        title: '电影',
        initialItems: initialItems,
        onOpenMedia: (_) {},
        onLoad: onLoad,
      ),
    );
  }

  testWidgets('requests page one and appends page two at the bottom',
      (tester) async {
    final pages = <int>[];
    await tester.pumpWidget(buildSubject(onLoad: (page) async {
      pages.add(page);
      return PagedMedia(
        items: page == 1
            ? [media('第一项'), ...List.generate(15, (i) => media('首屏$i'))]
            : [media('第一项'), media('第二页')],
        page: page,
        pageCount: 2,
        total: 18,
        limit: 16,
        hasMore: page == 1,
      );
    }));
    await tester.pumpAndSettle();

    expect(pages, [1]);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1400));
    await tester.pumpAndSettle();

    expect(pages, [1, 2]);
    expect(find.text('第二页'), findsOneWidget);
  });

  testWidgets('remote first page replaces preview items', (tester) async {
    await tester.pumpWidget(buildSubject(
      initialItems: [media('首页预览')],
      onLoad: (page) async => PagedMedia(
        items: [media('远程首屏')],
        page: page,
        pageCount: 1,
        total: 1,
        limit: 1,
        hasMore: false,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('远程首屏'), findsOneWidget);
    expect(find.text('首页预览'), findsNothing);
  });

  testWidgets('shows a scroll-to-top action after scrolling and returns home',
      (tester) async {
    await tester.pumpWidget(buildSubject(
      onLoad: (page) async => PagedMedia(
        items: List.generate(30, (index) => media('资源$index')),
        page: page,
        pageCount: 1,
        total: 30,
        limit: 30,
        hasMore: false,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byTooltip('回到顶部'), findsNothing);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await tester.pumpAndSettle();

    expect(find.byTooltip('回到顶部'), findsOneWidget);
    await tester.tap(find.byTooltip('回到顶部'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('回到顶部'), findsNothing);
  });
}
