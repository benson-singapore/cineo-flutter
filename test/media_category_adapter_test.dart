import 'package:flutter_test/flutter_test.dart';

import 'package:cineo_flutter/data/remote/media_category_adapter.dart';

void main() {
  test('maps nested source categories through their parent type', () {
    final categories = [
      const RemoteCategory(id: '2', name: '电视剧'),
      const RemoteCategory(id: '21', name: '国产剧', parentId: '2'),
      const RemoteCategory(id: '3', name: '综艺'),
      const RemoteCategory(id: '4', name: '动漫'),
    ];

    final types = MediaCategoryAdapter.adapt(categories);

    expect(types.map((item) => item.type), containsAll([
      UnifiedMediaType.all,
      UnifiedMediaType.series,
      UnifiedMediaType.variety,
      UnifiedMediaType.animation,
    ]));
    expect(
      types.firstWhere((item) => item.type == UnifiedMediaType.series).sourceCategoryIds,
      contains('21'),
    );
  });

  test('maps flat source categories without guessing unknown categories', () {
    final types = MediaCategoryAdapter.adapt(const [
      RemoteCategory(id: '1', name: '电影'),
      RemoteCategory(id: '9', name: '纪录片'),
    ]);

    expect(types.map((item) => item.type), contains(UnifiedMediaType.movie));
    expect(types.map((item) => item.type), isNot(contains(UnifiedMediaType.series)));
  });
}
