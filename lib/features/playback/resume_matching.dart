import '../../core/models/media.dart';

/// Maps only records whose media identity and episode can be established.
List<WatchProgress> matchResumeHistory(
  MediaItem resolved,
  List<WatchProgress> history, {
  MediaItem? original,
}) {
  final sameSource = original != null &&
      original.sourceId != null &&
      original.sourceId!.isNotEmpty &&
      original.remoteId != null &&
      original.remoteId!.isNotEmpty &&
      original.sourceId == resolved.sourceId &&
      original.remoteId == resolved.remoteId;
  final eligible = history.where((entry) =>
      entry.mediaId == resolved.id ||
      (sameSource && entry.mediaId == original.id));
  final result = <WatchProgress>[];
  for (final entry in eligible) {
    if (resolved.kind == MediaKind.movie && entry.episodeId == null) {
      result.add(entry.copyWith(mediaId: resolved.id));
      continue;
    }
    final isHub0 = entry.episodeId?.startsWith('hub0:') ?? false;
    final exact = isHub0
        ? <PlaybackOption>[]
        : resolved.playbackOptions
            .where((o) => o.id == entry.episodeId)
            .toList();
    PlaybackOption? option = exact.length == 1 ? exact.single : null;
    if (isHub0) option = _matchHubEpisode(resolved, entry);
    if (option == null &&
        !isHub0 &&
        sameSource &&
        original.id.startsWith('hub:') &&
        entry.mediaId == original.id &&
        entry.episodeNumber == 0 &&
        entry.episodeLabel != null &&
        entry.episodeLabel!.isNotEmpty &&
        entry.episodeId == '${entry.episodeLabel}:0') {
      // A legacy Hub snapshot encoded its line and zero-based first episode
      // as "line:0". Positive legacy indices remain ambiguous.
      option = _matchHubEpisode(
          resolved,
          entry.copyWith(
              episodeId: 'hub0:${Uri.encodeComponent(entry.episodeLabel!)}:0',
              lineName: entry.episodeLabel,
              episodeNumber: 1));
    }
    if (option != null) {
      result.add(entry.copyWith(mediaId: resolved.id, episodeId: option.id));
    }
  }
  result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return result;
}

PlaybackOption? _matchHubEpisode(MediaItem media, WatchProgress entry) {
  final source = media.sourceId;
  final remote = media.remoteId;
  final line = entry.lineName;
  if (source == null ||
      source.isEmpty ||
      remote == null ||
      remote.isEmpty ||
      line == null ||
      line.isEmpty) return null;
  final parts = entry.episodeId!.split(':');
  if (parts.length != 3 || !RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(parts[2])) {
    return null;
  }
  final int? index = int.tryParse(parts[2]);
  if (index == null || entry.episodeNumber != index + 1) return null;
  try {
    if (Uri.decodeComponent(parts[1]) != line) return null;
  } on FormatException {
    return null;
  } on ArgumentError {
    return null;
  }
  final prefix = '$source:$remote:';
  final groups = <String>{};
  final candidates = <PlaybackOption>[];
  for (final option in media.playbackOptions.where((o) => o.quality == line)) {
    if (option.sourceId != source || !option.id.startsWith(prefix)) return null;
    final match =
        RegExp(r'^(\d+):(\d+)$').firstMatch(option.id.substring(prefix.length));
    if (match == null) return null;
    groups.add(match.group(1)!);
    if (int.tryParse(match.group(2)!) == index) candidates.add(option);
  }
  return groups.length == 1 && candidates.length == 1
      ? candidates.single
      : null;
}
