import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
// The storage plugin exposes its test platform through this transitive API.
// ignore: depend_on_referenced_packages
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cineo_flutter/features/app_lock/app_lock_controller.dart';
import 'package:cineo_flutter/features/app_lock/app_lock_gate.dart';
import 'package:cineo_flutter/features/app_lock/app_lock_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStoragePlatform.instance =
        TestFlutterSecureStoragePlatform(<String, String>{});
  });

  testWidgets('shows the app directly when no PIN has been configured',
      (tester) async {
    final controller = AppLockController(service: AppLockService());
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: AppLockGate(
          controller: controller,
          child: const Scaffold(body: Text('Cineo 首页')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cineo 首页'), findsOneWidget);
    expect(find.text('设置应用锁'), findsNothing);
  });
}
