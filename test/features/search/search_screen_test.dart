import 'package:cineo_flutter/core/models/media.dart';
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
    required Future<List<MediaItem>> Function(List<String>) onBrowse,
    Future<List<MediaItem>> Function(String, List<String>)? onSearch,
  }) {
    return MaterialApp(
      theme: buildCineoTheme(),
      home: SearchScreen(
        items: items,
        history: const [],
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
      ),
    );
  }

  testWidgets('loads the default resource library for an empty query',
      (tester) async {
    final browseCalls = <List<String>>[];
    await tester.pumpWidget(
      buildSubject(
        items: [media('首页电影')],
        onBrowse: (categoryIds) async {
          browseCalls.add(categoryIds);
          return [media('远程电影')];
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(browseCalls, [[]]);
    expect(find.text('远程电影'), findsOneWidget);
    expect(find.text('全部资源库'), findsOneWidget);
  });

  testWidgets('passes the selected category to browse and search callbacks',
      (tester) async {
    final browseCalls = <List<String>>[];
    final searchCalls = <(String, List<String>)>[];
    await tester.pumpWidget(
      buildSubject(
        items: [media('本地电影')],
        onBrowse: (categoryIds) async {
          browseCalls.add(categoryIds);
          return [media('分类资源')];
        },
        onSearch: (query, categoryIds) async {
          searchCalls.add((query, categoryIds));
          return [media('搜索结果')];
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, '电影'));
    await tester.pumpAndSettle();
    expect(browseCalls.last, ['movie-id']);

    await tester.enterText(find.byType(TextField), '星际');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(searchCalls, hasLength(1));
    expect(searchCalls.single.$1, '星际');
    expect(searchCalls.single.$2, ['movie-id']);
    expect(find.text('搜索结果'), findsOneWidget);
  });

  testWidgets('clearing a keyword returns to category browsing',
      (tester) async {
    var browseCount = 0;
    await tester.pumpWidget(
      buildSubject(
        items: [media('资源')],
        onBrowse: (_) async {
          browseCount++;
          return [media('分类资源')];
        },
        onSearch: (_, __) async => [media('关键词结果')],
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
        onBrowse: (_) async => [media('分类资源')],
        onSearch: (_, __) async {
          searchCount++;
          return [media('关键词结果')];
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
}
