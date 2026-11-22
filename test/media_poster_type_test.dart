import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cineo_flutter/core/models/media.dart';
import 'package:cineo_flutter/shared/widgets/media_poster_card.dart';

void main() {
  testWidgets('封面根据来源分类显示类型，未知分类不猜测', (tester) async {
    MediaItem item(String category,
            {String? sourceId = 'source', MediaKind kind = MediaKind.series}) =>
        MediaItem(
          id: category,
          title: '测试影片',
          description: '',
          year: 0,
          kind: kind,
          posterUrl: '',
          backdropUrl: '',
          genres: const [],
          rating: 0,
          duration: Duration.zero,
          sourceId: sourceId,
          category: category,
        );
    for (final entry in {
      '电影': '电影',
      '动画电影': '电影',
      '国产剧': '剧集',
      '日本动漫': '动漫',
      '短剧': '短剧',
      '综艺': '综艺',
      '其他': null,
    }.entries) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MediaPosterCard(media: item(entry.key), onTap: () async {}),
        ),
      ));
      if (entry.value == null) {
        expect(find.text('剧集'), findsNothing);
        expect(find.text('电影'), findsNothing);
      } else {
        final label = find.text(entry.value!);
        expect(label, findsOneWidget);
        final decorated = tester.widget<DecoratedBox>(find
            .ancestor(
              of: label,
              matching: find.byWidgetPredicate((widget) =>
                  widget is DecoratedBox &&
                  widget.decoration is BoxDecoration &&
                  (widget.decoration as BoxDecoration).color != null),
            )
            .first);
        final expected = {
          '电影': const Color(0xFF286AA0),
          '剧集': const Color(0xFFAA591C),
          '动漫': const Color(0xFF7252B3),
          '短剧': const Color(0xFFAD3862),
          '综艺': const Color(0xFF267F75),
        };
        expect((decorated.decoration as BoxDecoration).color,
            expected[entry.value]);
      }
    }
    for (final kind in MediaKind.values) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
        body: MediaPosterCard(
            media: item('', sourceId: null, kind: kind), onTap: () async {}),
      )));
      expect(find.text(kind == MediaKind.movie ? '电影' : '剧集'), findsOneWidget);
    }
  });
}
