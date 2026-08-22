import 'package:flutter/foundation.dart';

import 'app_lock_service.dart';

class AppLockController extends ChangeNotifier {
  AppLockController({AppLockService? service})
      : service = service ?? AppLockService();

  final AppLockService service;
  bool _initialized = false;
  bool _hasPin = false;
  bool _isBusy = false;

  bool get initialized => _initialized;
  bool get hasPin => _hasPin;
  bool get isLocked => service.isLocked;
  bool get isBusy => _isBusy;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _hasPin = await service.hasPin;
    if (_hasPin) {
      await service.lock();
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> refresh() async {
    _hasPin = await service.hasPin;
    notifyListeners();
  }

  Future<void> setupPin(String pin) async {
    await service.setupPin(pin);
    _hasPin = true;
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
    notifyListeners();
  }
}
