import 'media.dart';

/// One of Cineo's fixed home rows, backed by source-native category IDs.
class HomeCategoryRail {
  const HomeCategoryRail({
    required this.title,
    required this.categoryIds,
    required this.items,
  });

  final String title;
  final List<String> categoryIds;
  final List<MediaItem> items;
}
