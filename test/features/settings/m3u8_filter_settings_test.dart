import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cineo_flutter/features/settings/m3u8_filter_settings.dart';

const _template =
    'https://filter.example.test/proxy?rule=auto_full&url=$m3u8FilterUrlPlaceholder';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('validates and encodes the M3U8 URL in a filter template', () {
    const source = 'https://video.example.test/main.m3u8?token=a&part=1';

    expect(isValidM3u8FilterTemplate(_template), isTrue);
    expect(
      buildM3u8FilterUrl(_template, source),
      'https://filter.example.test/proxy?rule=auto_full&url='
      'https%3A%2F%2Fvideo.example.test%2Fmain.m3u8%3Ftoken%3Da%26part%3D1',
    );
    expect(isValidM3u8FilterTemplate('https://filter.example.test/proxy'),
        isFalse);
  });

  test('persists configs and keeps at most one config enabled', () async {
    final settings = M3u8FilterSettings();
    await settings.initialize();

    final first = await settings.addConfig(
      name: '第一个过滤器',
      template: _template,
      enabled: true,
    );
    final second = await settings.addConfig(
      name: '第二个过滤器',
      template: _template,
      enabled: true,
    );

    expect(settings.activeConfig?.id, second.id);
    expect(settings.configs.where((config) => config.enabled), hasLength(1));
    expect(
        settings.configs.firstWhere((config) => config.id == first.id).enabled,
        isFalse);

    final reloaded = M3u8FilterSettings();
    await reloaded.initialize();
    expect(reloaded.activeConfig?.id, second.id);

    await reloaded.setEnabled(second.id, false);
    expect(reloaded.activeConfig, isNull);
  });

  test('rejects blank names and templates without the placeholder', () async {
    final settings = M3u8FilterSettings();
    await settings.initialize();

    await expectLater(
      settings.addConfig(name: ' ', template: _template),
      throwsA(isA<ArgumentError>()),
    );
    await expectLater(
      settings.addConfig(
        name: '无效配置',
        template: 'https://filter.example.test/proxy',
      ),
      throwsA(isA<ArgumentError>()),
    );
  });
}
