import 'package:cineo_flutter/data/download/hls_playlist.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const uri = 'https://cdn.example.test/video/index.m3u8';
  const media = '''#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:10
#EXT-X-MEDIA-SEQUENCE:0
#EXTINF:9.5,
segments/one.ts
#EXTINF:8,
/parts/two.ts
#EXT-X-ENDLIST
''';

  test('resolves relative and root-relative segment URLs', () {
    final playlist = HlsPlaylistParser().parseMedia(media, Uri.parse(uri));
    expect(playlist.segments, hasLength(2));
    expect(playlist.segments[0].uri.toString(),
        'https://cdn.example.test/video/segments/one.ts');
    expect(playlist.segments[1].uri.toString(),
        'https://cdn.example.test/parts/two.ts');
  });

  test('carries a playlist query token to bare relative segments', () {
    final playlist = HlsPlaylistParser().parseMedia(
      media,
      Uri.parse('https://cdn.example.test/video/index.m3u8?token=abc'),
    );
    expect(playlist.segments[0].uri.toString(),
        'https://cdn.example.test/video/segments/one.ts?token=abc');
    expect(playlist.segments[1].uri.toString(),
        'https://cdn.example.test/parts/two.ts?token=abc');
  });

  test('selects highest bandwidth master variant', () async {
    final playlist = await HlsPlaylistParser(fetcher: (selected) async {
      expect(selected.toString(), 'https://cdn.example.test/high/index.m3u8');
      return media;
    }).parse('''#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=100
low/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=900
high/index.m3u8
''', Uri.parse('https://cdn.example.test/master.m3u8'));
    expect(playlist.uri.toString(), 'https://cdn.example.test/high/index.m3u8');
  });

  test('carries a master playlist query token to the selected variant',
      () async {
    final playlist = await HlsPlaylistParser(fetcher: (selected) async {
      expect(selected.toString(),
          'https://cdn.example.test/high/index.m3u8?token=abc');
      return media;
    }).parse('''#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=900
high/index.m3u8
''', Uri.parse('https://cdn.example.test/master.m3u8?token=abc'));
    expect(playlist.uri.toString(),
        'https://cdn.example.test/high/index.m3u8?token=abc');
  });

  test('rejects encryption, byte ranges, and live playlists', () {
    expect(
        () => HlsPlaylistParser().parseMedia(
              media.replaceFirst('#EXT-X-ENDLIST',
                  '#EXT-X-KEY:METHOD=AES-128,URI="key"\n#EXT-X-ENDLIST'),
              Uri.parse(uri),
            ),
        throwsA(isA<HlsPlaylistException>()));
    expect(
        () => HlsPlaylistParser().parseMedia(
              media.replaceFirst(
                  '#EXT-X-ENDLIST', '#EXT-X-BYTERANGE:100@0\n#EXT-X-ENDLIST'),
              Uri.parse(uri),
            ),
        throwsA(isA<HlsPlaylistException>()));
    expect(
        () => HlsPlaylistParser().parseMedia(
              media.replaceFirst('#EXT-X-ENDLIST', ''),
              Uri.parse(uri),
            ),
        throwsA(isA<HlsPlaylistException>()));
  });
}
