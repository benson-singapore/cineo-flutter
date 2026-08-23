import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cineo_flutter/core/models/media.dart';
import 'package:cineo_flutter/shared/widgets/media_rail.dart';

MediaItem _media(String id, String title) {
  return MediaItem(
    id: id,
    title: title,
    description: 'description',
    year: 2024,
    kind: MediaKind.movie,
    posterUrl: '',
    backdropUrl: '',
    genres: const [],
    rating: 8,
    duration: const Duration(minutes: 100),
  );
}

Widget _host({required Widget child}) {
  return MaterialApp(
    theme: ThemeData.dark(),
    home: Scaffold(
      body: CustomScrollView(slivers: [child]),
    ),
  );
}

void main() {
  testWidgets('view all invokes callback with rail title and items',
      (tester) async {
    final items = [_media('1', '第一部'), _media('2', '第二部')];
    String? title;
    List<MediaItem>? receivedItems;

    await tester.pumpWidget(
      _host(
        child: MediaRail(
          title: '为你推荐',
          items: items,
          onOpenMedia: (_) async {},
          onSeeAll: () {
            title = '为你推荐';
            receivedItems = items;
          },
        ),
      ),
    );

    await tester.tap(find.byTooltip('查看全部为你推荐'));

    expect(title, '为你推荐');
    expect(receivedItems, same(items));
  });

  testWidgets('view all remains disabled when callback is omitted',
      (tester) async {
    await tester.pumpWidget(
      _host(
        child: MediaRail(
          title: '为你推荐',
          items: [_media('1', '第一部')],
          onOpenMedia: (_) async {},
        ),
      ),
    );

    final button = tester.widget<IconButton>(find.byType(IconButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('shows loading while the selected poster is opening',
      (tester) async {
    final opening = Completer<void>();
    var openCalls = 0;

    await tester.pumpWidget(
      _host(
        child: MediaRail(
          title: '为你推荐',
          items: [_media('slow', '加载中的视频')],
          onOpenMedia: (_) {
            openCalls++;
            return opening.future;
          },
        ),
      ),
    );

    await tester.tap(find.text('加载中的视频'));
    await tester.pump();

    expect(openCalls, 1);
    expect(
        find.byKey(const ValueKey('media-card-loading-slow')), findsOneWidget);

    await tester.tap(find.text('加载中的视频'));
    await tester.pump();
    expect(openCalls, 1);

    opening.complete();
    await tester.pump();
    expect(find.byKey(const ValueKey('media-card-loading-slow')), findsNothing);
  });
}
