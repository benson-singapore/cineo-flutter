import 'media.dart';

class SourceSearchProgress {
  const SourceSearchProgress({
    required this.searched,
    required this.total,
    this.matches = const <MediaItem>[],
    this.isComplete = false,
  });

  final int searched;
  final int total;
  final List<MediaItem> matches;
  final bool isComplete;
}
