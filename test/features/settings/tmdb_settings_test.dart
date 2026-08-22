import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
// The storage plugin exposes its test platform through this transitive interface.
// ignore: depend_on_referenced_packages
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cineo_flutter/features/settings/tmdb_settings.dart';
import 'package:cineo_flutter/features/settings/tmdb_settings_screen.dart';

void main() {
  late Map<String, String> secureData;

  setUp(() {
    secureData = <String, String>{};
    FlutterSecureStoragePlatform.instance =
        TestFlutterSecureStoragePlatform(secureData);
  });

  test('initializes as not configured when no token is stored', () async {
    final settings = TMDBSettings();

    expect(settings.initialized, isFalse);
    await settings.initialize();

    expect(settings.initialized, isTrue);
    expect(settings.configured, isFalse);
    expect(settings.errorMessage, isNull);
  });

  test('trims and securely persists a token without exposing it as state',
      () async {
    final settings = TMDBSettings();

    await settings.saveToken('  test-token-value  ');

    expect(settings.initialized, isTrue);
    expect(settings.configured, isTrue);
    expect(secureData[TMDBSettings.tokenStorageKey], 'test-token-value');
  });

  test('reads configured state and clears the token', () async {
    secureData[TMDBSettings.tokenStorageKey] = 'stored-token';
    final settings = TMDBSettings();

    await settings.initialize();
    expect(settings.configured, isTrue);

    await settings.clearToken();

    expect(settings.configured, isFalse);
    expect(secureData.containsKey(TMDBSettings.tokenStorageKey), isFalse);
  });

  test('reads the token only for a request without adding it to state',
      () async {
    secureData[TMDBSettings.tokenStorageKey] = ' request-token ';
    final settings = TMDBSettings();

    final token = await settings.readTokenForRequest();

    expect(token, 'request-token');
    expect(settings.configured, isFalse);
    expect(settings.errorMessage, isNull);
  });

  test('rejects a blank token', () async {
    final settings = TMDBSettings();

    await expectLater(
      settings.saveToken(' \n\t '),
      throwsA(isA<ArgumentError>()),
    );

    expect(settings.configured, isFalse);
    expect(settings.errorMessage, '请输入有效的 TMDB API Token');
  });

  testWidgets('clears the input after saving and only shows configured state',
      (tester) async {
    final settings = TMDBSettings();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: TMDBSettingsScreen(settings: settings),
      ),
    );
    await tester.pumpAndSettle();

    const token = 'widget-test-token';
    await tester.enterText(find.byType(TextField), token);
    await tester.tap(find.text('保存配置'));
    await tester.pumpAndSettle();

    expect(settings.configured, isTrue);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    expect(find.text(token), findsNothing);
    expect(find.text('已配置'), findsOneWidget);
  });
}
