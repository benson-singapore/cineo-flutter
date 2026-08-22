import 'package:cineo_flutter/core/models/media.dart';
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
  List<String> selectedSourceCategoryIds = const [],
  Future<void> Function()? onRefresh,
}) {
  return MaterialApp(
    theme: buildCineoTheme(),
    home: HomeScreen(
      items: items,
      continueWatching: const [],
      onOpenMedia: (_) {},
      selectedSourceCategoryIds: selectedSourceCategoryIds,
      onSeeAll: onSeeAll,
      onRefresh: onRefresh,
    ),
  );
}

void main() {
  testWidgets('short drama rail sends its real category id', (tester) async {
    final items = [
      _media('1', '短剧一', categoryId: 'tid-short', genres: ['短剧']),
      _media('2', '短剧二', categoryId: 'tid-short', genres: ['短剧']),
      _media('3', '电影', categoryId: 'tid-movie', genres: ['电影']),
    ];
    String? title;
    List<String>? categoryIds;

    await tester.pumpWidget(
      _subject(
        items: items,
        onSeeAll: (railTitle, _, ids) {
          title = railTitle;
          categoryIds = ids;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byType(CustomScrollView),
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('查看全部短剧').first);

    expect(title, '短剧');
    expect(categoryIds, ['tid-short']);
  });

  testWidgets('recommendation rail sends selected source category ids',
      (tester) async {
    final items = [
      _media('1', '推荐一', categoryId: 'tid-a'),
      _media('2', '推荐二', categoryId: 'tid-b'),
    ];
    List<String>? categoryIds;

    await tester.pumpWidget(
      _subject(
        items: items,
        selectedSourceCategoryIds: const ['tid-series', 'tid-series', 'tid-b'],
        onSeeAll: (_, __, ids) => categoryIds = ids,
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byType(CustomScrollView),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('查看全部为你推荐').first);

    expect(categoryIds, ['tid-series', 'tid-b']);
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
