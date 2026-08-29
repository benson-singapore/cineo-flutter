import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/foundation.dart';

class AppUpdateService extends ChangeNotifier {
  AppUpdateService({http.Client? client}) : _client = client ?? http.Client();

  static final releasesUri = Uri.parse(
    'https://github.com/benson-singapore/cineo-flutter/releases',
  );
  static final _latestReleaseUri = Uri.parse(
    'https://api.github.com/repos/benson-singapore/cineo-flutter/releases/latest',
  );
  static final _releasesAtomUri = Uri.parse(
    'https://github.com/benson-singapore/cineo-flutter/releases.atom',
  );

  final http.Client _client;

  String currentVersion = '1.0.3';
  String? latestVersion;
  Uri? latestReleaseUri;
  Uri? latestDownloadUri;
  String? releaseNotes;
  DateTime? latestPublishedAt;
  String? checkError;
  bool isChecking = false;

  bool get hasUpdate {
    final latest = latestVersion;
    if (latest == null) return false;
    return _ComparableVersion.parse(latest) >
        _ComparableVersion.parse(currentVersion);
  }

  Future<void> initialize() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (packageInfo.version.trim().isNotEmpty) {
        currentVersion = packageInfo.version.trim();
        notifyListeners();
      }
    } catch (_) {
      // Keep the version from the app's release configuration when unavailable.
    }
    await checkForUpdates();
  }

  Future<void> checkForUpdates() async {
    if (isChecking) return;
    isChecking = true;
    checkError = null;
    notifyListeners();
    try {
      var loaded = false;
      try {
        loaded = await _loadLatestReleaseFromApi();
      } catch (error) {
        _logCheckFailure(error);
      }
      if (!loaded) {
        try {
          loaded = await _loadLatestReleaseFromAtom();
        } catch (error) {
          _logCheckFailure(error);
        }
      }
      if (!loaded) {
        checkError = '暂时无法连接版本服务，请稍后重试';
      }
    } finally {
      isChecking = false;
      notifyListeners();
    }
  }

  Future<bool> _loadLatestReleaseFromApi() async {
    final response = await _client.get(
      _latestReleaseUri,
      headers: const {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    );
    if (response.statusCode != 200) return false;
    final payload = jsonDecode(response.body);
    if (payload is! Map<String, dynamic>) return false;
    final tagName = payload['tag_name'];
    if (tagName is! String || tagName.trim().isEmpty) return false;

    _applyRelease(
      tagName: tagName.trim(),
      releaseUri: _uriFrom(payload['html_url']) ?? releasesUri,
      notes: _stringFrom(payload['body']),
      publishedAt: DateTime.tryParse(_stringFrom(payload['published_at'])),
    );
    final assets = payload['assets'];
    if (assets is List) {
      for (final asset in assets) {
        if (asset is Map<String, dynamic>) {
          final url = _uriFrom(asset['browser_download_url']);
          if (url != null) {
            latestDownloadUri = url;
            break;
          }
        }
      }
    }
    return true;
  }

  Future<bool> _loadLatestReleaseFromAtom() async {
    final response = await _client.get(
      _releasesAtomUri,
      headers: const {'Accept': 'application/atom+xml'},
    );
    if (response.statusCode != 200) return false;

    final entry = RegExp(
      r'<entry\b[\s\S]*?</entry>',
      caseSensitive: false,
    ).firstMatch(response.body)?.group(0);
    if (entry == null) return false;
    final releaseMatch = RegExp(
      r'href="([^" ]+/releases/tag/([^"/]+))"',
      caseSensitive: false,
    ).firstMatch(entry);
    if (releaseMatch == null) return false;

    final tagName = releaseMatch.group(2)!;
    final notesResponse = await _client.get(_rawReleaseNotesUri(tagName));
    final notes = notesResponse.statusCode == 200 ? notesResponse.body : '';
    final updated = RegExp(
      r'<updated>([^<]+)</updated>',
      caseSensitive: false,
    ).firstMatch(entry)?.group(1);
    _applyRelease(
      tagName: tagName,
      releaseUri: Uri.parse(releaseMatch.group(1)!),
      notes: notes,
      publishedAt: DateTime.tryParse(updated ?? ''),
    );
    return true;
  }

  void _applyRelease({
    required String tagName,
    required Uri releaseUri,
    required String notes,
    required DateTime? publishedAt,
  }) {
    latestVersion = tagName;
    latestReleaseUri = releaseUri;
    releaseNotes = notes;
    latestPublishedAt = publishedAt;
  }

  static Uri _rawReleaseNotesUri(String tagName) => Uri.parse(
        'https://raw.githubusercontent.com/benson-singapore/cineo-flutter/'
        '$tagName/docs/update/$tagName.md',
      );

  void _logCheckFailure(Object error) {
    assert(() {
      debugPrint('[Cineo][Update] phase=check_failed '
          'errorType=${error.runtimeType} error=$error');
      return true;
    }());
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  static Uri? _uriFrom(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    final uri = Uri.tryParse(value.trim());
    return uri != null && uri.hasScheme ? uri : null;
  }

  static String _stringFrom(Object? value) => value is String ? value : '';
}

class _ComparableVersion implements Comparable<_ComparableVersion> {
  const _ComparableVersion(this.major, this.minor, this.patch);

  factory _ComparableVersion.parse(String value) {
    final normalized = value.trim().replaceFirst(RegExp(r'^[vV]'), '');
    final publicVersion = normalized.split('+').first.split('-').first;
    final parts = publicVersion.split('.');
    return _ComparableVersion(
      _numberAt(parts, 0),
      _numberAt(parts, 1),
      _numberAt(parts, 2),
    );
  }

  final int major;
  final int minor;
  final int patch;

  @override
  int compareTo(_ComparableVersion other) {
    final majorComparison = major.compareTo(other.major);
    if (majorComparison != 0) return majorComparison;
    final minorComparison = minor.compareTo(other.minor);
    if (minorComparison != 0) return minorComparison;
    return patch.compareTo(other.patch);
  }

  static int _numberAt(List<String> parts, int index) {
    if (index >= parts.length) return 0;
    return int.tryParse(parts[index]) ?? 0;
  }
}

extension on _ComparableVersion {
  bool operator >(_ComparableVersion other) => compareTo(other) > 0;
}
