import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../core/models/tmdb_media.dart';
import 'tmdb_cache_models.dart';

typedef TmdbCacheDirectoryProvider = Future<Directory> Function();
typedef TmdbImageFetcher = Future<List<int>> Function(Uri uri);
typedef TmdbCacheClock = DateTime Function();

class TmdbCacheStats {
  const TmdbCacheStats({
    required this.totalBytes,
    required this.metadataCount,
    required this.imageCount,
    required this.overrideCount,
  });

  final int totalBytes;
  final int metadataCount;
  final int imageCount;
  final int overrideCount;

  double get totalMegabytes => totalBytes / (1024 * 1024);
}

/// A small file-backed cache for TMDB details, images, and manual matches.
///
/// The cache owns its directory below the application support directory. Its
/// dependencies are injectable so tests and offline callers do not need a
/// platform channel or a real network connection.
class TmdbDiskCache {
  TmdbDiskCache({
    TmdbCacheDirectoryProvider? directoryProvider,
    TmdbImageFetcher? imageFetcher,
    TmdbCacheClock? clock,
    this.defaultTtl = const Duration(days: 30),
  })  : _directoryProvider = directoryProvider ?? _defaultDirectoryProvider,
        _imageFetcher = imageFetcher ?? _fetchImage,
        _clock = clock ?? DateTime.now {
    if (defaultTtl <= Duration.zero) {
      throw ArgumentError.value(defaultTtl, 'defaultTtl', 'must be positive');
    }
  }

  static const cacheDirectoryName = 'cineo_tmdb_cache';
  static const cacheVersion = 1;
  static const _metadataDirectoryName = 'metadata';
  static const _imageDirectoryName = 'images';
  static const _overrideFileName = 'overrides.json';

  final Duration defaultTtl;
  final TmdbCacheDirectoryProvider _directoryProvider;
  final TmdbImageFetcher _imageFetcher;
  final TmdbCacheClock _clock;

  Future<Directory>? _rootFuture;

  Future<void> initialize() async {
    await _rootDirectory();
  }

  Future<void> putMetadata({
    required String mediaId,
    required Map<String, dynamic> data,
    Duration? ttl,
  }) async {
    _validateKey(mediaId, 'mediaId');
    final duration = _validatedTtl(ttl);
    final now = _clock().toUtc();
    final record = <String, dynamic>{
      'version': cacheVersion,
      'media_id': mediaId,
      'cached_at': now.toIso8601String(),
      'expires_at': now.add(duration).toIso8601String(),
      'data': _sanitizeJson(data),
    };
    final file = await _metadataFile(mediaId);
    await _writeJsonAtomically(file, record);
  }

  Future<Map<String, dynamic>?> getMetadata(
    String mediaId, {
    bool allowExpired = false,
  }) async {
    _validateKey(mediaId, 'mediaId');
    final file = await _metadataFile(mediaId, create: false);
    if (!await file.exists()) return null;

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      final record = Map<String, dynamic>.from(decoded);
      final expiresAt = DateTime.tryParse('${record['expires_at']}');
      if (!allowExpired &&
          expiresAt != null &&
          !_clock().toUtc().isBefore(expiresAt)) {
        return null;
      }
      final data = record['data'];
      return data is Map ? Map<String, dynamic>.from(data) : null;
    } on FormatException {
      return null;
    } on IOException {
      return null;
    }
  }

  Future<void> putDetails({
    required String mediaId,
    required TmdbMediaDetails details,
    Duration? ttl,
  }) {
    return putMetadata(
      mediaId: mediaId,
      data: TmdbCacheModelCodec.encodeDetails(details),
      ttl: ttl,
    );
  }

  Future<TmdbMediaDetails?> getDetails(
    String mediaId, {
    bool allowExpired = false,
  }) async {
    final data = await getMetadata(mediaId, allowExpired: allowExpired);
    if (data == null) return null;
    try {
      return TmdbCacheModelCodec.decodeDetails(data);
    } on FormatException {
      return null;
    }
  }

  Future<File> cacheImage(String url, {Duration? ttl}) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw ArgumentError.value(url, 'url', 'must be an absolute URL');
    }
    final duration = _validatedTtl(ttl);
    final imageFile = await _imageFile(url);
    final stampFile = await _imageStampFile(url);
    if (await imageFile.exists() && await stampFile.exists()) {
      final stamp = await _readStamp(stampFile);
      if (stamp != null && _clock().toUtc().isBefore(stamp)) return imageFile;
    }

    final bytes = await _imageFetcher(uri);
    if (bytes.isEmpty) throw const FormatException('TMDB image was empty');
    await _writeBytesAtomically(imageFile, bytes);
    await _writeJsonAtomically(stampFile, <String, dynamic>{
      'cached_at': _clock().toUtc().toIso8601String(),
      'expires_at': _clock().toUtc().add(duration).toIso8601String(),
    });
    return imageFile;
  }

  Future<String?> getCachedImagePath(
    String url, {
    bool allowExpired = false,
  }) async {
    final imageFile = await _imageFile(url, create: false);
    final stampFile = await _imageStampFile(url, create: false);
    if (!await imageFile.exists() || !await stampFile.exists()) return null;
    if (!allowExpired) {
      final stamp = await _readStamp(stampFile);
      if (stamp == null || !_clock().toUtc().isBefore(stamp)) return null;
    }
    return imageFile.path;
  }

  Future<void> setOverride({
    required String cineoMediaId,
    required TmdbMediaMatch match,
  }) async {
    _validateKey(cineoMediaId, 'cineoMediaId');
    final overrides = await _readOverrides();
    overrides[cineoMediaId] = TmdbCacheModelCodec.encodeMatch(match);
    await _writeJsonAtomically(await _overrideFile(), overrides);
  }

  Future<TmdbMediaMatch?> getOverride(String cineoMediaId) async {
    _validateKey(cineoMediaId, 'cineoMediaId');
    final value = (await _readOverrides())[cineoMediaId];
    if (value is! Map) return null;
    try {
      return TmdbCacheModelCodec.decodeMatch(Map<String, dynamic>.from(value));
    } on FormatException {
      return null;
    }
  }

  Future<void> removeOverride(String cineoMediaId) async {
    _validateKey(cineoMediaId, 'cineoMediaId');
    final overrides = await _readOverrides();
    if (overrides.remove(cineoMediaId) != null) {
      await _writeJsonAtomically(await _overrideFile(), overrides);
    }
  }

  Future<TmdbCacheStats> getStats() async {
    final root = await _rootDirectory();
    var totalBytes = 0;
    var metadataCount = 0;
    var imageCount = 0;
    if (await root.exists()) {
      await for (final entity
          in root.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final size = await entity.length();
        totalBytes += size;
        if (path.dirname(entity.path).endsWith(_metadataDirectoryName)) {
          if (path.extension(entity.path) == '.json') metadataCount++;
        } else if (path.dirname(entity.path).endsWith(_imageDirectoryName) &&
            path.extension(entity.path) == '.bin') {
          imageCount++;
        }
      }
    }
    final overrides = await _readOverrides();
    return TmdbCacheStats(
      totalBytes: totalBytes,
      metadataCount: metadataCount,
      imageCount: imageCount,
      overrideCount: overrides.length,
    );
  }

  /// Deletes expired metadata records and image files, returning the number of
  /// deleted files. Manual match overrides are configuration and are retained.
  Future<int> clearExpired({Duration? maxAge}) async {
    final root = await _rootDirectory();
    final now = _clock().toUtc();
    final ageLimit = maxAge == null ? null : _validatedTtl(maxAge);
    var removed = 0;

    final metadataDirectory = Directory(
      path.join(root.path, _metadataDirectoryName),
    );
    if (await metadataDirectory.exists()) {
      await for (final entity in metadataDirectory.list(followLinks: false)) {
        if (entity is! File || path.extension(entity.path) != '.json') continue;
        if (await _isExpiredRecord(entity, now, maxAge: ageLimit)) {
          await entity.delete();
          removed++;
        }
      }
    }

    final imageDirectory = Directory(path.join(root.path, _imageDirectoryName));
    if (await imageDirectory.exists()) {
      await for (final entity in imageDirectory.list(followLinks: false)) {
        if (entity is! File || !entity.path.endsWith('.stamp.json')) continue;
        if (!await _isExpiredRecord(entity, now, maxAge: ageLimit)) continue;
        final imagePath = entity.path.replaceFirst('.stamp.json', '.bin');
        final image = File(imagePath);
        if (await image.exists()) {
          await image.delete();
          removed++;
        }
        await entity.delete();
        removed++;
      }
    }
    return removed;
  }

  /// Removes cached metadata and images. Manual match overrides are settings,
  /// so they remain unless [includeOverrides] is explicitly requested.
  Future<void> clearAll({bool includeOverrides = false}) async {
    final root = await _rootDirectory();
    final overrides =
        includeOverrides ? <String, dynamic>{} : await _readOverrides();
    if (await root.exists()) await root.delete(recursive: true);
    if (includeOverrides) return;
    if (overrides.isNotEmpty) {
      await _writeJsonAtomically(await _overrideFile(), overrides);
    }
  }

  Future<Directory> _rootDirectory() {
    return _rootFuture ??= _directoryProvider().then((base) async {
      final root = Directory(path.join(base.path, cacheDirectoryName));
      await Directory(path.join(root.path, _metadataDirectoryName))
          .create(recursive: true);
      await Directory(path.join(root.path, _imageDirectoryName))
          .create(recursive: true);
      return root;
    });
  }

  Future<File> _metadataFile(String key, {bool create = true}) async {
    final root = await _rootDirectory();
    if (create) {
      await Directory(path.join(root.path, _metadataDirectoryName))
          .create(recursive: true);
    }
    return File(
      path.join(root.path, _metadataDirectoryName, '${_hash(key)}.json'),
    );
  }

  Future<File> _imageFile(String url, {bool create = true}) async {
    final root = await _rootDirectory();
    if (create) {
      await Directory(path.join(root.path, _imageDirectoryName))
          .create(recursive: true);
    }
    return File(
      path.join(root.path, _imageDirectoryName, '${_hash(url)}.bin'),
    );
  }

  Future<File> _imageStampFile(String url, {bool create = true}) {
    return _imageStampFileInternal(url, create: create);
  }

  Future<File> _imageStampFileInternal(String url, {bool create = true}) async {
    final root = await _rootDirectory();
    if (create) {
      await Directory(path.join(root.path, _imageDirectoryName))
          .create(recursive: true);
    }
    return File(
      path.join(root.path, _imageDirectoryName, '${_hash(url)}.stamp.json'),
    );
  }

  Future<File> _overrideFile() async {
    final root = await _rootDirectory();
    return File(path.join(root.path, _overrideFileName));
  }

  Future<Map<String, dynamic>> _readOverrides() async {
    final file = await _overrideFile();
    if (!await file.exists()) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } on FormatException {
      return <String, dynamic>{};
    } on IOException {
      return <String, dynamic>{};
    }
  }

  Future<DateTime?> _readStamp(File file) async {
    try {
      final decoded = jsonDecode(await file.readAsString());
      return DateTime.tryParse('${decoded['expires_at']}');
    } on FormatException {
      return null;
    } on IOException {
      return null;
    }
  }

  Future<bool> _isExpiredRecord(
    File file,
    DateTime now, {
    Duration? maxAge,
  }) async {
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return true;
      final expiresAt = DateTime.tryParse('${decoded['expires_at']}');
      final cachedAt = DateTime.tryParse('${decoded['cached_at']}');
      if (expiresAt == null || !now.isBefore(expiresAt.toUtc())) return true;
      if (maxAge == null || cachedAt == null) return false;
      return !now.isBefore(cachedAt.toUtc().add(maxAge));
    } on FormatException {
      return true;
    } on IOException {
      return true;
    }
  }

  Future<void> _writeJsonAtomically(File target, Object value) async {
    await target.parent.create(recursive: true);
    final temporary =
        File('${target.path}.${_hash(_clock().toIso8601String())}.tmp');
    await temporary.writeAsString(jsonEncode(value), flush: true);
    try {
      await temporary.rename(target.path);
    } on FileSystemException {
      if (await target.exists()) await target.delete();
      await temporary.rename(target.path);
    }
  }

  Future<void> _writeBytesAtomically(File target, List<int> bytes) async {
    await target.parent.create(recursive: true);
    final temporary =
        File('${target.path}.${_hash(_clock().toIso8601String())}.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    try {
      await temporary.rename(target.path);
    } on FileSystemException {
      if (await target.exists()) await target.delete();
      await temporary.rename(target.path);
    }
  }

  Duration _validatedTtl(Duration? ttl) {
    final value = ttl ?? defaultTtl;
    if (value <= Duration.zero) {
      throw ArgumentError.value(value, 'ttl', 'must be positive');
    }
    return value;
  }

  static void _validateKey(String value, String name) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(value, name, 'required');
    }
  }

  static String _hash(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  static Object? _sanitizeJson(Object? value, [String? key]) {
    if (_isSensitiveKey(key)) return null;
    if (value is Map) {
      final output = <String, dynamic>{};
      value.forEach((rawKey, rawValue) {
        final childKey = '$rawKey';
        if (!_isSensitiveKey(childKey)) {
          output[childKey] = _sanitizeJson(rawValue, childKey);
        }
      });
      return output;
    }
    if (value is Iterable) {
      return value.map((item) => _sanitizeJson(item)).toList();
    }
    return value;
  }

  static bool _isSensitiveKey(String? key) {
    if (key == null) return false;
    final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return normalized.contains('token') ||
        normalized.contains('authorization') ||
        normalized.contains('apikey') ||
        normalized.contains('bearer');
  }

  static Future<Directory> _defaultDirectoryProvider() {
    return getApplicationSupportDirectory();
  }

  static Future<List<int>> _fetchImage(Uri uri) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('TMDB image request failed', uri: uri);
      }
      return response.fold<List<int>>(<int>[], (bytes, chunk) {
        bytes.addAll(chunk);
        return bytes;
      });
    } finally {
      client.close(force: true);
    }
  }
}
