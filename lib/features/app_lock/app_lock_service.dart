import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PinVerificationStatus {
  success,
  invalidPin,
  temporarilyLocked,
  notConfigured,
}

enum AppLockGracePeriod {
  immediate(0, '立即'),
  fiveMinutes(5, '5 分钟'),
  fifteenMinutes(15, '15 分钟'),
  thirtyMinutes(30, '30 分钟'),
  sixtyMinutes(60, '60 分钟');

  const AppLockGracePeriod(this.minutes, this.label);

  final int minutes;
  final String label;

  static AppLockGracePeriod fromMinutes(int? minutes) {
    return AppLockGracePeriod.values.firstWhere(
      (period) => period.minutes == minutes,
      orElse: () => AppLockGracePeriod.thirtyMinutes,
    );
  }
}

class PinVerificationResult {
  const PinVerificationResult({
    required this.status,
    this.remainingLockout = Duration.zero,
    this.failedAttempts = 0,
  });

  final PinVerificationStatus status;
  final Duration remainingLockout;
  final int failedAttempts;

  bool get isSuccess => status == PinVerificationStatus.success;
}

/// Stores only a salted PBKDF2 verifier. The PIN itself never leaves memory.
class AppLockService {
  AppLockService({
    FlutterSecureStorage? secureStorage,
    SharedPreferences? preferences,
    DateTime Function()? now,
  })  : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _preferencesOverride = preferences,
        _now = now ?? DateTime.now;

  static const _saltKey = 'cineo.app_lock.pin_salt';
  static const _verifierKey = 'cineo.app_lock.pin_verifier';
  static const _failedAttemptsKey = 'cineo.app_lock.failed_attempts';
  static const _lockoutUntilKey = 'cineo.app_lock.lockout_until_ms';
  static const _gracePeriodMinutesKey = 'cineo.app_lock.grace_period_minutes';
  static const _enabledKey = 'cineo.app_lock.enabled';
  static const _sessionVerifiedAtKey = 'cineo.app_lock.session_verified_at_ms';
  static const defaultGracePeriod = AppLockGracePeriod.thirtyMinutes;
  static const _iterations = 120000;
  static const _derivedKeyLength = 32;
  static const _baseLockout = Duration(seconds: 2);
  static const _maxLockout = Duration(minutes: 5);

  final FlutterSecureStorage _secureStorage;
  final SharedPreferences? _preferencesOverride;
  final DateTime Function() _now;
  bool _isLocked = false;

  bool get isLocked => _isLocked;

  Future<SharedPreferences> get _preferences async =>
      _preferencesOverride ?? await SharedPreferences.getInstance();

  Future<bool> get hasPin async {
    final salt = await _secureStorage.read(key: _saltKey);
    final verifier = await _secureStorage.read(key: _verifierKey);
    return salt != null &&
        salt.isNotEmpty &&
        verifier != null &&
        verifier.isNotEmpty;
  }

  Future<bool> get isEnabled async {
    final preferences = await _preferences;
    return preferences.getBool(_enabledKey) ?? false;
  }

  Future<void> setEnabled(bool enabled) async {
    if (enabled && !await hasPin) {
      throw StateError('请先设置应用锁 PIN');
    }
    final preferences = await _preferences;
    await preferences.setBool(_enabledKey, enabled);
    if (!enabled) {
      _isLocked = false;
      return;
    }
    await restoreSession();
  }

  Future<void> lock() async {
    if (await hasPin && await isEnabled) {
      await _clearVerifiedSession();
      _isLocked = true;
    }
  }

  void unlock() {
    _isLocked = false;
  }

  Future<void> setupPin(String pin) async {
    _validatePin(pin);

    final salt = _randomBytes(16);
    final verifier = _deriveKey(utf8.encode(pin), salt);
    await _secureStorage.write(key: _saltKey, value: base64UrlEncode(salt));
    await _secureStorage.write(
      key: _verifierKey,
      value: base64UrlEncode(verifier),
    );
    await _clearLockout();
    await _markSessionVerified();
    _isLocked = false;
  }

  Future<AppLockGracePeriod> getGracePeriod() async {
    final preferences = await _preferences;
    return AppLockGracePeriod.fromMinutes(
      preferences.getInt(_gracePeriodMinutesKey),
    );
  }

  Future<void> setGracePeriod(AppLockGracePeriod period) async {
    final preferences = await _preferences;
    await preferences.setInt(_gracePeriodMinutesKey, period.minutes);
    if (period == AppLockGracePeriod.immediate &&
        await hasPin &&
        await isEnabled) {
      await _clearVerifiedSession();
      _isLocked = true;
    }
  }

  Future<void> restoreSession() async {
    if (!await hasPin || !await isEnabled) {
      _isLocked = false;
      return;
    }
    _isLocked = !await _hasValidVerifiedSession();
  }

  Future<void> handleBackground() async {
    if (!await hasPin || !await isEnabled) return;
    if (await getGracePeriod() == AppLockGracePeriod.immediate) {
      await _clearVerifiedSession();
      _isLocked = true;
    }
  }

  Future<void> handleResume() async {
    await restoreSession();
  }

  Future<PinVerificationResult> verifyPin(String pin) async {
    final configured = await hasPin;
    if (!configured) {
      return const PinVerificationResult(
        status: PinVerificationStatus.notConfigured,
      );
    }

    final remaining = await _remainingLockout();
    if (remaining > Duration.zero) {
      return PinVerificationResult(
        status: PinVerificationStatus.temporarilyLocked,
        remainingLockout: remaining,
        failedAttempts: await _failedAttempts(),
      );
    }

    if (!_isValidPin(pin)) {
      return _recordFailure();
    }

    final encodedSalt = await _secureStorage.read(key: _saltKey);
    final encodedVerifier = await _secureStorage.read(key: _verifierKey);
    if (encodedSalt == null || encodedVerifier == null) {
      return const PinVerificationResult(
        status: PinVerificationStatus.notConfigured,
      );
    }

    final salt = base64Url.decode(encodedSalt);
    final expected = base64Url.decode(encodedVerifier);
    final actual = _deriveKey(utf8.encode(pin), salt);
    if (_constantTimeEquals(actual, expected)) {
      await _clearLockout();
      await _markSessionVerified();
      _isLocked = false;
      return const PinVerificationResult(status: PinVerificationStatus.success);
    }

    return _recordFailure();
  }

  Future<void> clearPin() async {
    await _secureStorage.delete(key: _saltKey);
    await _secureStorage.delete(key: _verifierKey);
    await _clearLockout();
    await _clearVerifiedSession();
    final preferences = await _preferences;
    await preferences.setBool(_enabledKey, false);
    _isLocked = false;
  }

  Future<PinVerificationResult> _recordFailure() async {
    final attempts = await _failedAttempts() + 1;
    final exponent = min(attempts - 1, 8);
    final requestedSeconds = _baseLockout.inSeconds * (1 << exponent);
    final lockout = Duration(
      seconds: min(requestedSeconds, _maxLockout.inSeconds),
    );
    final preferences = await _preferences;
    await preferences.setInt(_failedAttemptsKey, attempts);
    await preferences.setInt(
      _lockoutUntilKey,
      _now().add(lockout).millisecondsSinceEpoch,
    );
    return PinVerificationResult(
      status: PinVerificationStatus.invalidPin,
      remainingLockout: lockout,
      failedAttempts: attempts,
    );
  }

  Future<int> _failedAttempts() async {
    final preferences = await _preferences;
    return preferences.getInt(_failedAttemptsKey) ?? 0;
  }

  Future<Duration> _remainingLockout() async {
    final preferences = await _preferences;
    final until = preferences.getInt(_lockoutUntilKey);
    if (until == null) {
      return Duration.zero;
    }
    final remaining =
        Duration(milliseconds: until - _now().millisecondsSinceEpoch);
    if (remaining <= Duration.zero) {
      await _clearLockout();
      return Duration.zero;
    }
    return remaining;
  }

  Future<void> _clearLockout() async {
    final preferences = await _preferences;
    await preferences.remove(_failedAttemptsKey);
    await preferences.remove(_lockoutUntilKey);
  }

  Future<void> _markSessionVerified() async {
    final period = await getGracePeriod();
    final preferences = await _preferences;
    if (period == AppLockGracePeriod.immediate) {
      await preferences.remove(_sessionVerifiedAtKey);
      return;
    }
    await preferences.setInt(
        _sessionVerifiedAtKey, _now().millisecondsSinceEpoch);
  }

  Future<void> _clearVerifiedSession() async {
    final preferences = await _preferences;
    await preferences.remove(_sessionVerifiedAtKey);
  }

  Future<bool> _hasValidVerifiedSession() async {
    final preferences = await _preferences;
    final verifiedAt = preferences.getInt(_sessionVerifiedAtKey);
    if (verifiedAt == null) {
      return false;
    }

    final period = await getGracePeriod();
    final expiresAt =
        verifiedAt + period.minutes * Duration.millisecondsPerMinute;
    if (_now().millisecondsSinceEpoch < expiresAt) {
      return true;
    }
    await _clearVerifiedSession();
    return false;
  }

  static void _validatePin(String pin) {
    if (!_isValidPin(pin)) {
      throw ArgumentError.value(pin, 'pin', 'PIN 必须是 6 位数字');
    }
  }

  static bool _isValidPin(String pin) => RegExp(r'^\d{6}$').hasMatch(pin);

  static List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  static List<int> _deriveKey(List<int> password, List<int> salt) {
    final hmac = Hmac(sha256, password);
    final output = Uint8List(_derivedKeyLength);
    var outputOffset = 0;
    var block = 1;
    while (outputOffset < _derivedKeyLength) {
      final blockBytes = <int>[
        ...salt,
        (block >> 24) & 0xff,
        (block >> 16) & 0xff,
        (block >> 8) & 0xff,
        block & 0xff
      ];
      var u = hmac.convert(blockBytes).bytes;
      final t = Uint8List.fromList(u);
      for (var iteration = 1; iteration < _iterations; iteration++) {
        u = hmac.convert(u).bytes;
        for (var index = 0; index < t.length; index++) {
          t[index] ^= u[index];
        }
      }
      final copyLength = min(t.length, _derivedKeyLength - outputOffset);
      output.setRange(outputOffset, outputOffset + copyLength, t);
      outputOffset += copyLength;
      block++;
    }
    return output;
  }

  static bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) {
      return false;
    }
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }
}
