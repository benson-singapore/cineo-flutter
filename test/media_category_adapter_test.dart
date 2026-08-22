import 'package:flutter_test/flutter_test.dart';

import 'package:cineo_flutter/data/remote/media_category_adapter.dart';

void main() {
  test('keeps a flat category as the request leaf', () {
    final types = MediaCategoryAdapter.adapt(const [
      RemoteCategory(id: '1', name: '电影'),
    ]);

    expect(
      types
          .firstWhere((item) => item.type == UnifiedMediaType.movie)
          .sourceCategoryIds,
      ['1'],
    );
  });

  test('uses the child leaf instead of requesting a parent and child', () {
    final categories = [
      const RemoteCategory(id: '2', name: '电视剧'),
      const RemoteCategory(id: '21', name: '国产剧', parentId: '2'),
      const RemoteCategory(id: '3', name: '综艺'),
      const RemoteCategory(id: '4', name: '动漫'),
    ];

    final types = MediaCategoryAdapter.adapt(categories);

    expect(
        types.map((item) => item.type),
        containsAll([
          UnifiedMediaType.all,
          UnifiedMediaType.series,
          UnifiedMediaType.variety,
          UnifiedMediaType.animation,
        ]));
    expect(
      types
          .firstWhere((item) => item.type == UnifiedMediaType.series)
          .sourceCategoryIds,
      ['21'],
    );
    expect(
      types
          .firstWhere((item) => item.type == UnifiedMediaType.series)
          .subcategories
          .single
          .name,
      '国产剧',
    );
    expect(
      types
          .firstWhere((item) => item.type == UnifiedMediaType.series)
          .sourceCategoryIds,
      isNot(contains('2')),
    );
  });

  test('uses only deepest leaves for a multi-level category tree', () {
    final types = MediaCategoryAdapter.adapt(const [
      RemoteCategory(id: '10', name: '电影'),
      RemoteCategory(id: '11', name: '华语电影', parentId: '10'),
      RemoteCategory(id: '12', name: '香港电影', parentId: '11'),
      RemoteCategory(id: '13', name: '欧美电影', parentId: '11'),
    ]);

    expect(
      types
          .firstWhere((item) => item.type == UnifiedMediaType.movie)
          .sourceCategoryIds,
      ['12', '13'],
    );
  });

  test('inherits a parent type for an unknown leaf category', () {
    final types = MediaCategoryAdapter.adapt(const [
      RemoteCategory(id: '20', name: '动漫'),
      RemoteCategory(id: '21', name: '国产', parentId: '20'),
      RemoteCategory(id: '22', name: '日本', parentId: '20'),
    ]);

    expect(
      types
          .firstWhere((item) => item.type == UnifiedMediaType.animation)
          .sourceCategoryIds,
      ['21', '22'],
    );
  });

  test('handles orphan parents and cycles without losing stable leaves', () {
    final types = MediaCategoryAdapter.adapt(const [
      RemoteCategory(id: '30', name: '电影', parentId: 'missing'),
      RemoteCategory(id: '31', name: '综艺', parentId: '32'),
      RemoteCategory(id: '32', name: '节目', parentId: '31'),
    ]);

    expect(
      types
          .firstWhere((item) => item.type == UnifiedMediaType.movie)
          .sourceCategoryIds,
      ['30'],
    );
    expect(
      types
          .firstWhere((item) => item.type == UnifiedMediaType.variety)
          .sourceCategoryIds,
      ['31', '32'],
    );
  });

  test('deduplicates repeated category IDs while preserving first order', () {
    final types = MediaCategoryAdapter.adapt(const [
      RemoteCategory(id: '40', name: '电影'),
      RemoteCategory(id: '40', name: '电影'),
      RemoteCategory(id: '41', name: '影片'),
    ]);

    expect(
      types
          .firstWhere((item) => item.type == UnifiedMediaType.movie)
          .sourceCategoryIds,
      ['40', '41'],
    );
  });

  test('keeps tree leaves as separately browsable secondary categories', () {
    final types = MediaCategoryAdapter.adapt(const [
      RemoteCategory(id: '2', name: '电视剧'),
      RemoteCategory(id: '21', name: '国产剧', parentId: '2'),
      RemoteCategory(id: '22', name: '日剧', parentId: '2'),
      RemoteCategory(id: '23', name: '韩剧', parentId: '2'),
    ]);

    final series =
        types.firstWhere((item) => item.type == UnifiedMediaType.series);
    expect(series.sourceCategoryIds, ['21', '22', '23']);
    expect(series.subcategories.map((item) => item.name), ['国产剧', '日剧', '韩剧']);
    expect(series.subcategories.map((item) => item.sourceCategoryIds), [
      ['21'],
      ['22'],
      ['23'],
    ]);
    expect(series.subcategories.last.matchText, contains('电视剧'));
    expect(series.subcategories.last.matchText, contains('韩剧'));
  });

  test('maps flat source categories without guessing unknown categories', () {
    final types = MediaCategoryAdapter.adapt(const [
      RemoteCategory(id: '1', name: '电影'),
      RemoteCategory(id: '9', name: '纪录片'),
    ]);

    expect(types.map((item) => item.type), contains(UnifiedMediaType.movie));
    expect(types.map((item) => item.type),
        isNot(contains(UnifiedMediaType.series)));
  });
}
