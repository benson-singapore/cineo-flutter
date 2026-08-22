import 'media.dart';

/// A page returned by a remote media catalog.
class PagedMedia {
  const PagedMedia({
    required this.items,
    required this.page,
    required this.pageCount,
    required this.total,
    required this.limit,
    required this.hasMore,
  });

  final List<MediaItem> items;
  final int page;
  final int pageCount;
  final int total;
  final int limit;
  final bool hasMore;
}
