import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdultSourceSettings extends ChangeNotifier {
  static const _showAdultSourcesKey = 'show_adult_sources';
  static const _hideAdultHistoryKey = 'hide_adult_history';

  bool _initialized = false;
  bool _showAdultSources = false;
  bool _hideAdultHistory = true;

  bool get initialized => _initialized;
  bool get showAdultSources => _showAdultSources;
  bool get hideAdultHistory => _hideAdultHistory;

  Future<void> initialize() async {
    if (_initialized) return;
    final preferences = await SharedPreferences.getInstance();
    _showAdultSources = preferences.getBool(_showAdultSourcesKey) ?? false;
    _hideAdultHistory = preferences.getBool(_hideAdultHistoryKey) ?? true;
    _initialized = true;
    notifyListeners();
  }

  Future<void> setShowAdultSources(bool value) async {
    _showAdultSources = value;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_showAdultSourcesKey, value);
  }

  Future<void> setHideAdultHistory(bool value) async {
    _hideAdultHistory = value;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_hideAdultHistoryKey, value);
  }
}
