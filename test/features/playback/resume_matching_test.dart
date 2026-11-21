import 'package:flutter_test/flutter_test.dart';
import 'package:cineo_flutter/core/models/media.dart';
import 'package:cineo_flutter/features/playback/resume_matching.dart';

void main() {
  const a1 = PlaybackOption(
      id: 's:42:0:0', sourceId: 's', label: 'A · 第1集', url: 'a1', quality: 'A');
  const a2 = PlaybackOption(
      id: 's:42:0:1', sourceId: 's', label: 'A · 第2集', url: 'a2', quality: 'A');
  const b1 = PlaybackOption(
      id: 's:42:1:0', sourceId: 's', label: 'B · 第1集', url: 'b1', quality: 'B');
  const media = MediaItem(
      id: 's:42',
      sourceId: 's',
      remoteId: '42',
      title: 'x',
      description: '',
      year: 0,
      kind: MediaKind.series,
      posterUrl: '',
      backdropUrl: '',
      genres: [],
      rating: 0,
      duration: Duration.zero,
      playbackOptions: [a1, a2, b1]);
  const old = MediaItem(
      id: 'hub:old:42',
      sourceId: 's',
      remoteId: '42',
      title: 'x',
      description: '',
      year: 0,
      kind: MediaKind.series,
      posterUrl: '',
      backdropUrl: '',
      genres: [],
      rating: 0,
      duration: Duration.zero);
  WatchProgress record(String? id,
          {int? number,
          String? label,
          String? line,
          String mediaId = 'hub:old:42'}) =>
      WatchProgress(
          mediaId: mediaId,
          episodeId: id,
          episodeNumber: number,
          episodeLabel: label,
          lineName: line,
          position: const Duration(minutes: 6),
          duration: const Duration(minutes: 20),
          updatedAt: DateTime(2026));
  test('old media id and exact second episode preserve the position', () {
    final result = matchResumeHistory(media, [record(a2.id)], original: old);
    expect(result.single.episodeId, a2.id);
    expect(result.single.position, const Duration(minutes: 6));
  });
  test('hub0 maps first and second episodes across named lines', () {
    expect(
        matchResumeHistory(media, [record('hub0:B:0', number: 1, line: 'B')],
                original: old)
            .single
            .episodeId,
        b1.id);
    final mapped = matchResumeHistory(
        media, [record('hub0:A:1', number: 2, line: 'A')],
        original: old);
    expect(mapped.single.episodeId, a2.id);
    expect(mapped.single.position, const Duration(minutes: 6));
    expect(
        matchResumeHistory(media, [record('A:1', number: 1, label: 'A')],
            original: old),
        isEmpty);
  });
  test('legacy Hub first episode needs the same media and a unique line', () {
    final mapped = matchResumeHistory(
        media, [record('B:0', number: 0, label: 'B')],
        original: old);
    expect(mapped.single.episodeId, b1.id);
    expect(mapped.single.position, const Duration(minutes: 6));
    expect(
        matchResumeHistory(media, [record('B:0', number: 0, label: 'B')],
            original: old.copyWith(sourceId: 'other')),
        isEmpty);
    final duplicate = media.copyWith(playbackOptions: [
      b1,
      const PlaybackOption(
          id: 's:42:2:0', sourceId: 's', label: 'B', url: 'x', quality: 'B')
    ]);
    expect(
        matchResumeHistory(duplicate, [record('B:0', number: 0, label: 'B')],
            original: old),
        isEmpty);
    expect(
        matchResumeHistory(media, [record('A:1', number: 1, label: 'A')],
            original: old),
        isEmpty);
  });
  test('encoded Unicode and colon lines and conflicting fields', () {
    const encodedOption = PlaybackOption(
        id: 's:42:2:1', sourceId: 's', label: 'x', url: 'x', quality: '线路:一');
    final target = media.copyWith(playbackOptions: [encodedOption]);
    expect(
        matchResumeHistory(
                target,
                [
                  record('hub0:%E7%BA%BF%E8%B7%AF%3A%E4%B8%80:1',
                      number: 2, line: '线路:一')
                ],
                original: old)
            .single
            .episodeId,
        encodedOption.id);
    for (final bad in [
      record('hub0:A:1', number: 1, line: 'A'),
      record('hub0:A:1', number: 2, line: 'B'),
      record('hub0:%ZZ:0', number: 1, line: 'A'),
      record('hub0:A:-1', number: 0, line: 'A'),
      record('hub0:A:99', number: 100, line: 'A')
    ]) {
      expect(matchResumeHistory(media, [bad], original: old), isEmpty);
    }
  });
  test('does not match other media or source, or ambiguous line names', () {
    expect(
        matchResumeHistory(media, [record(a1.id, mediaId: 'other')],
            original: old),
        isEmpty);
    expect(
        matchResumeHistory(media, [record(a1.id)],
            original: old.copyWith(sourceId: 'other')),
        isEmpty);
    final duplicate = media.copyWith(playbackOptions: [
      a1,
      const PlaybackOption(
          id: 's:42:1:0',
          sourceId: 's',
          label: 'A · 第1集',
          url: 'b',
          quality: 'A')
    ]);
    expect(
        matchResumeHistory(
            duplicate, [record('hub0:A:0', number: 1, line: 'A')],
            original: old),
        isEmpty);
  });
  test('new media id exact episode works without original', () {
    expect(
        matchResumeHistory(media, [record(a2.id, mediaId: media.id)])
            .single
            .episodeId,
        a2.id);
  });
}
