import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
// The storage plugin exposes its test platform through this transitive interface.
// ignore: depend_on_referenced_packages
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cineo_flutter/features/app_lock/app_lock_service.dart';

void main() {
  late Map<String, String> secureData;
  late DateTime now;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secureData = <String, String>{};
    FlutterSecureStoragePlatform.instance =
        TestFlutterSecureStoragePlatform(secureData);
    now = DateTime(2026, 8, 22, 12);
  });

  AppLockService createService() {
    return AppLockService(now: () => now);
  }

  test('defaults to a 30 minute grace period and restores a valid session',
      () async {
    final service = createService();

    expect(await service.getGracePeriod(), AppLockGracePeriod.thirtyMinutes);
    await service.setupPin('123456');
    await service.setEnabled(true);
    expect(service.isLocked, isFalse);

    final restored = createService();
    await restored.restoreSession();
    expect(restored.isLocked, isFalse);

    now = now.add(const Duration(minutes: 30));
    await restored.restoreSession();
    expect(restored.isLocked, isTrue);
  });

  test(
      'keeps a verified session through background until the grace period ends',
      () async {
    final service = createService();
    await service.setupPin('123456');
    await service.setEnabled(true);
    await service.handleBackground();

    final resumed = createService();
    await resumed.handleResume();
    expect(resumed.isLocked, isFalse);

    now = now.add(const Duration(minutes: 30));
    await resumed.handleResume();
    expect(resumed.isLocked, isTrue);
  });

  test('treats the exact grace-period boundary as expired', () async {
    final service = createService();
    await service.setupPin('123456');
    await service.setEnabled(true);

    now = now.add(const Duration(minutes: 30));
    await service.restoreSession();

    expect(service.isLocked, isTrue);
  });

  test('supports all persisted grace period values', () async {
    final service = createService();

    for (final period in AppLockGracePeriod.values) {
      await service.setGracePeriod(period);
      expect(await service.getGracePeriod(), period);
    }
  });

  test('persists a selected grace period across service instances', () async {
    final service = createService();
    await service.setGracePeriod(AppLockGracePeriod.fiveMinutes);

    final restored = createService();
    expect(
      await restored.getGracePeriod(),
      AppLockGracePeriod.fiveMinutes,
    );
  });

  test('setup PIN is treated as verified and immediate clears the session',
      () async {
    final service = createService();
    await service.setupPin('123456');
    await service.setEnabled(true);

    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getInt('cineo.app_lock.session_verified_at_ms'),
      isNotNull,
    );

    await service.setGracePeriod(AppLockGracePeriod.immediate);
    expect(service.isLocked, isTrue);
    expect(
      preferences.getInt('cineo.app_lock.session_verified_at_ms'),
      isNull,
    );
  });

  test('explicit lock clears the persisted verified session', () async {
    final service = createService();
    await service.setupPin('123456');
    await service.setEnabled(true);
    await service.lock();

    expect(service.isLocked, isTrue);
    final restored = createService();
    await restored.restoreSession();
    expect(restored.isLocked, isTrue);
  });

  test('immediate period clears an authenticated session and locks', () async {
    final service = createService();
    await service.setupPin('123456');
    await service.setEnabled(true);
    await service.setGracePeriod(AppLockGracePeriod.immediate);

    expect(service.isLocked, isTrue);

    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getInt('cineo.app_lock.session_verified_at_ms'),
      isNull,
    );
  });

  test('successful verification refreshes session without storing the PIN',
      () async {
    final service = createService();
    await service.setupPin('123456');
    await service.lock();

    final result = await service.verifyPin('123456');

    expect(result.isSuccess, isTrue);
    expect(service.isLocked, isFalse);
    expect(secureData.values, isNot(contains('123456')));
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getInt('cineo.app_lock.session_verified_at_ms'),
      isNotNull,
    );
  });

  test('failed verification keeps the existing lockout behavior', () async {
    final service = createService();
    await service.setupPin('123456');

    final result = await service.verifyPin('000000');

    expect(result.status, PinVerificationStatus.invalidPin);
    expect(result.failedAttempts, 1);
    final locked = await service.verifyPin('123456');
    expect(locked.status, PinVerificationStatus.temporarilyLocked);
  });

  test('keeps a configured PIN disabled until the user enables the app lock',
      () async {
    final service = createService();

    await service.setupPin('123456');
    expect(await service.isEnabled, isFalse);

    final restored = createService();
    await restored.restoreSession();
    expect(restored.isLocked, isFalse);

    await restored.setEnabled(true);
    expect(await restored.isEnabled, isTrue);
  });
}
