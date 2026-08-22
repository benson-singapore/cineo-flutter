import 'package:flutter/foundation.dart';

import 'app_lock_service.dart';

class AppLockController extends ChangeNotifier {
  AppLockController({AppLockService? service})
      : service = service ?? AppLockService();

  final AppLockService service;
  bool _initialized = false;
  bool _hasPin = false;
  bool _enabled = false;
  bool _isBusy = false;
  AppLockGracePeriod _gracePeriod = AppLockService.defaultGracePeriod;

  bool get initialized => _initialized;
  bool get hasPin => _hasPin;
  bool get enabled => _enabled;
  bool get isLocked => service.isLocked;
  bool get isBusy => _isBusy;
  AppLockGracePeriod get gracePeriod => _gracePeriod;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _hasPin = await service.hasPin;
    _enabled = await service.isEnabled;
    _gracePeriod = await service.getGracePeriod();
    await service.restoreSession();
    _initialized = true;
    notifyListeners();
  }

  Future<void> refresh() async {
    _hasPin = await service.hasPin;
    _enabled = await service.isEnabled;
    _gracePeriod = await service.getGracePeriod();
    notifyListeners();
  }

  Future<void> setGracePeriod(AppLockGracePeriod period) async {
    await service.setGracePeriod(period);
    _gracePeriod = period;
    notifyListeners();
  }

  Future<void> setupPin(String pin) async {
    await service.setupPin(pin);
    _hasPin = true;
    notifyListeners();
  }

  Future<void> setEnabled(bool enabled) async {
    await service.setEnabled(enabled);
    _enabled = await service.isEnabled;
    notifyListeners();
  }

  Future<PinVerificationResult> verifyPin(String pin) async {
    _isBusy = true;
    notifyListeners();
    try {
      final result = await service.verifyPin(pin);
      if (result.isSuccess) {
        notifyListeners();
      }
      return result;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> lock() async {
    await service.lock();
    notifyListeners();
  }

  void unlock() {
    service.unlock();
    notifyListeners();
  }

  Future<void> clearPin() async {
    await service.clearPin();
    _hasPin = false;
    _enabled = false;
    notifyListeners();
  }

  Future<void> handleBackground() async {
    await service.handleBackground();
    notifyListeners();
  }

  Future<void> handleResume() async {
    await service.handleResume();
    notifyListeners();
  }
}
