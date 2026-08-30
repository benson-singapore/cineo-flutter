import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/download_models.dart';

typedef DownloadPreferencesProvider = Future<SharedPreferences> Function();

class DownloadSettingsStore {
  DownloadSettingsStore({DownloadPreferencesProvider? preferencesProvider})
      : _preferencesProvider =
            preferencesProvider ?? SharedPreferences.getInstance;

  static const storageKey = 'cineo_download_settings';
  final DownloadPreferencesProvider _preferencesProvider;

  Future<DownloadSettings> load() async {
    final preferences = await _preferencesProvider();
    final encoded = preferences.getString(storageKey);
    if (encoded == null) return const DownloadSettings();
    try {
      final decoded = jsonDecode(encoded);
      return decoded is Map
          ? DownloadSettings.fromJson(Map<String, dynamic>.from(decoded))
          : const DownloadSettings();
    } on FormatException {
      return const DownloadSettings();
    }
  }

  Future<DownloadSettings> save(DownloadSettings settings) async {
    final preferences = await _preferencesProvider();
    final normalized = settings.normalized();
    await preferences.setString(storageKey, jsonEncode(normalized.toJson()));
    return normalized;
  }
}
