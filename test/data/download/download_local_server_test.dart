import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cineo_flutter/data/download/download_local_server.dart';

void main() {
  test('serves local playlists and segments through loopback HTTP', () async {
    final root = await Directory.systemTemp.createTemp('cineo-local-server-');
    final task = Directory('${root.path}/task')..createSync();
    final playlist = File('${task.path}/index.m3u8')
      ..writeAsStringSync('#EXTM3U\n#EXT-X-ENDLIST\n');
    final segment = File('${task.path}/segment_000000.ts')
      ..writeAsBytesSync(<int>[0, 1, 2, 3]);
    final server = DownloadLocalServer(root);
    final client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await server.close();
      if (await root.exists()) await root.delete(recursive: true);
    });

    final playlistUrl = await server.urlFor(playlist.path);
    final playlistResponse = await client.getUrl(Uri.parse(playlistUrl));
    final playlistResult = await playlistResponse.close();
    expect(playlistResult.statusCode, HttpStatus.ok);
    expect(playlistResult.headers.contentType?.mimeType,
        'application/vnd.apple.mpegurl');
    expect(await playlistResult.transform(utf8.decoder).join(),
        contains('#EXTM3U'));

    final segmentUrl = await server.urlFor(segment.path);
    final segmentRequest = await client.getUrl(Uri.parse(segmentUrl));
    final segmentResult = await segmentRequest.close();
    expect(segmentResult.statusCode, HttpStatus.ok);
    expect(segmentResult.headers.contentType?.mimeType, 'video/mp2t');
    expect(
        await segmentResult.fold<List<int>>(<int>[], (all, bytes) {
          return all..addAll(bytes);
        }),
        <int>[0, 1, 2, 3]);
  });
}
