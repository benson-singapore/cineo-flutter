import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdultSourceSettings extends ChangeNotifier {
  static const _preferenceKey = 'show_adult_sources';

  bool _initialized = false;
  bool _showAdultSources = false;

  bool get initialized => _initialized;
  bool get showAdultSources => _showAdultSources;

  Future<void> initialize() async {
    if (_initialized) return;
    final preferences = await SharedPreferences.getInstance();
    _showAdultSources = preferences.getBool(_preferenceKey) ?? false;
    _initialized = true;
    notifyListeners();
  }

  Future<void> setShowAdultSources(bool value) async {
    _showAdultSources = value;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_preferenceKey, value);
  }
}
