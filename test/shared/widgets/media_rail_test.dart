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
          onOpenMedia: (_) {},
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
          onOpenMedia: (_) {},
        ),
      ),
    );

    final button = tester.widget<IconButton>(find.byType(IconButton));
    expect(button.onPressed, isNull);
  });
}
