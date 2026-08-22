import 'package:cineo_flutter/core/models/media.dart';
import 'package:cineo_flutter/core/models/paged_media.dart';
import 'package:cineo_flutter/core/theme/cineo_theme.dart';
import 'package:cineo_flutter/data/remote/media_category_adapter.dart';
import 'package:cineo_flutter/features/search/search_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const movieCategory = UnifiedCategory(
    type: UnifiedMediaType.movie,
    sourceCategoryIds: ['movie-id'],
  );
  const seriesCategory = UnifiedCategory(
    type: UnifiedMediaType.series,
    sourceCategoryIds: ['series-id'],
  );

  MediaItem media(String title, {MediaKind kind = MediaKind.movie}) {
    return MediaItem(
      id: title,
      title: title,
      description: '测试内容',
      year: 2026,
      kind: kind,
      posterUrl: '',
      backdropUrl: '',
      genres: const ['剧情'],
      rating: 8.0,
      duration: const Duration(minutes: 100),
    );
  }

  Widget buildSubject({
    required List<MediaItem> items,
    required Future<PagedMedia> Function(List<String>, int) onBrowse,
    Future<PagedMedia> Function(String, List<String>, int)? onSearch,
    List<String> history = const [],
    bool libraryMode = false,
    VoidCallback? onOpenSearch,
  }) {
    return MaterialApp(
      theme: buildCineoTheme(),
      home: SearchScreen(
        items: items,
        history: history,
        categories: const [
          UnifiedCategory(
            type: UnifiedMediaType.all,
            sourceCategoryIds: [],
          ),
          movieCategory,
          seriesCategory,
        ],
        onSearch: (_) {},
        onOpenMedia: (_) {},
        onBrowseCategory: onBrowse,
        onRemoteSearch: onSearch,
        libraryMode: libraryMode,
        onOpenSearch: onOpenSearch,
      ),
    );
  }

  testWidgets('loads the default resource library for an empty query',
      (tester) async {
    final browseCalls = <(List<String>, int)>[];
    await tester.pumpWidget(
      buildSubject(
        items: [media('首页电影')],
        onBrowse: (categoryIds, page) async {
          browseCalls.add((categoryIds, page));
          return PagedMedia(
            items: [media('远程电影')],
            page: page,
            pageCount: 1,
            total: 1,
            limit: 1,
            hasMore: false,
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(browseCalls, hasLength(1));
    expect(browseCalls.single.$1, isEmpty);
    expect(browseCalls.single.$2, 1);
    expect(find.text('远程电影'), findsOneWidget);
    expect(find.text('全部资源库'), findsOneWidget);
  });

  testWidgets('passes the selected category to browse and search callbacks',
      (tester) async {
    final browseCalls = <(List<String>, int)>[];
    final searchCalls = <(String, List<String>, int)>[];
    await tester.pumpWidget(
      buildSubject(
        items: [media('本地电影')],
        onBrowse: (categoryIds, page) async {
          browseCalls.add((categoryIds, page));
          return PagedMedia(
            items: [media('分类资源')],
            page: page,
            pageCount: 1,
            total: 1,
            limit: 1,
            hasMore: false,
          );
        },
        onSearch: (query, categoryIds, page) async {
          searchCalls.add((query, categoryIds, page));
          return PagedMedia(
            items: [media('搜索结果')],
            page: page,
            pageCount: 1,
            total: 1,
            limit: 1,
            hasMore: false,
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, '电影'));
    await tester.pumpAndSettle();
    expect(browseCalls.last.$1, ['movie-id']);
    expect(browseCalls.last.$2, 1);

    await tester.enterText(find.byType(TextField), '星际');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(searchCalls, hasLength(1));
    expect(searchCalls.single.$1, '星际');
    expect(searchCalls.single.$2, ['movie-id']);
    expect(searchCalls.single.$3, 1);
    expect(find.text('搜索结果'), findsOneWidget);
  });

  testWidgets('clearing a keyword returns to category browsing',
      (tester) async {
    var browseCount = 0;
    await tester.pumpWidget(
      buildSubject(
        items: [media('资源')],
        onBrowse: (_, page) async {
          browseCount++;
          return PagedMedia(
            items: [media('分类资源')],
            page: page,
            pageCount: 1,
            total: 1,
            limit: 1,
            hasMore: false,
          );
        },
        onSearch: (_, __, page) async => PagedMedia(
          items: [media('关键词结果')],
          page: page,
          pageCount: 1,
          total: 1,
          limit: 1,
          hasMore: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final initialBrowseCount = browseCount;

    await tester.enterText(find.byType(TextField), '关键词');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('关键词结果'), findsOneWidget);

    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pumpAndSettle();

    expect(browseCount, greaterThan(initialBrowseCount));
    expect(find.text('分类资源'), findsOneWidget);
    expect(find.text('全部资源库'), findsOneWidget);
  });

  testWidgets('typing alone keeps browsing until search is submitted',
      (tester) async {
    var searchCount = 0;
    await tester.pumpWidget(
      buildSubject(
        items: [media('资源')],
        onBrowse: (_, page) async => PagedMedia(
          items: [media('分类资源')],
          page: page,
          pageCount: 1,
          total: 1,
          limit: 1,
          hasMore: false,
        ),
        onSearch: (_, __, page) async {
          searchCount++;
          return PagedMedia(
            items: [media('关键词结果')],
            page: page,
            pageCount: 1,
            total: 1,
            limit: 1,
            hasMore: false,
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '星际');
    await tester.pumpAndSettle();

    expect(searchCount, 0);
    expect(find.text('分类资源'), findsOneWidget);
    expect(find.text('关键词结果'), findsNothing);

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(searchCount, 1);
    expect(find.text('关键词结果'), findsOneWidget);
  });

  testWidgets('requests page two at the bottom and appends unique results',
      (tester) async {
    final pages = <int>[];
    final pageOne = List.generate(16, (index) => media('资源$index'));
    await tester.pumpWidget(
      buildSubject(
        items: const [],
        onBrowse: (_, page) async {
          pages.add(page);
          return PagedMedia(
            items: page == 1
                ? [...pageOne, media('重复')]
                : [media('重复'), media('第二页')],
            page: page,
            pageCount: 2,
            total: 18,
            limit: 17,
            hasMore: page == 1,
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(pages, [1]);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1400));
    await tester.pumpAndSettle();

    expect(pages, [1, 2]);
    expect(find.text('第二页'), findsOneWidget);
    expect(find.text('重复'), findsOneWidget);
  });

  testWidgets(
      'pulling down refreshes the current library page without blanking it',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      buildSubject(
        items: const [],
        onBrowse: (_, page) async {
          calls++;
          return PagedMedia(
            items: [media('缓存内容')],
            page: page,
            pageCount: 1,
            total: 1,
            limit: 1,
            hasMore: false,
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('缓存内容'), findsOneWidget);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 420));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('缓存内容'), findsOneWidget);
  });

  testWidgets('library mode hides keyword search and history', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        items: const [],
        history: const ['最近看过'],
        libraryMode: true,
        onBrowse: (_, page) async => PagedMedia(
          items: const [],
          page: page,
          pageCount: 1,
          total: 0,
          limit: 20,
          hasMore: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('片库'), findsOneWidget);
    expect(find.text('搜索电影、剧集、类型'), findsNothing);
    expect(find.text('最近搜索'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('library mode opens the dedicated search action', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      buildSubject(
        items: const [],
        libraryMode: true,
        onOpenSearch: () => opened = true,
        onBrowse: (_, page) async => PagedMedia(
          items: const [],
          page: page,
          pageCount: 1,
          total: 0,
          limit: 20,
          hasMore: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('搜索'));

    expect(opened, isTrue);
  });

  testWidgets('normal mode keeps the keyword search field', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        items: const [],
        onBrowse: (_, page) async => PagedMedia(
          items: const [],
          page: page,
          pageCount: 1,
          total: 0,
          limit: 20,
          hasMore: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('搜索'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('搜索电影、剧集、类型'), findsOneWidget);
  });
}
