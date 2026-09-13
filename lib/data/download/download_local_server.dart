import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;

/// Serves completed HLS cache files through a loopback HTTP endpoint.
///
/// AVPlayer is more reliable with a local HLS URL than with a bare MPEG-TS
/// file, especially when individual HLS segments restart their timestamps.
class DownloadLocalServer {
  DownloadLocalServer(this.root);

  final Directory root;
  HttpServer? _server;

  Future<String> urlFor(String filePath) async {
    final server = await _ensureServer();
    final relative = path.relative(filePath, from: root.path);
    final segments = relative
        .split(path.separator)
        .where((segment) => segment.isNotEmpty && segment != '.')
        .map(Uri.encodeComponent)
        .join('/');
    return 'http://127.0.0.1:${server.port}/$segments';
  }

  Future<void> close() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  Future<HttpServer> _ensureServer() async {
    final current = _server;
    if (current != null) return current;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_handleRequest, onError: (_) {});
    _server = server;
    return server;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final relative =
        Uri.decodeComponent(request.uri.path).replaceFirst(RegExp(r'^/+'), '');
    final candidate = File(path.normalize(path.join(root.path, relative)));
    final rootPath = path.normalize(root.path);
    final candidatePath = path.normalize(candidate.path);
    if (!candidatePath.startsWith('$rootPath${path.separator}') ||
        !await candidate.exists()) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..close();
      return;
    }

    final extension = path.extension(candidate.path).toLowerCase();
    request.response.headers.contentType = switch (extension) {
      '.m3u8' =>
        ContentType('application', 'vnd.apple.mpegurl', charset: 'utf-8'),
      '.ts' || '.part' => ContentType('video', 'mp2t'),
      _ => ContentType.binary,
    };
    request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    await request.response.addStream(candidate.openRead());
    await request.response.close();
  }
}
