import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cineo_flutter/core/theme/cineo_theme.dart';
import 'package:cineo_flutter/features/update/app_update_screen.dart';
import 'package:cineo_flutter/features/update/app_update_service.dart';

void main() {
  testWidgets('collapses long Markdown release notes without overflow',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(428, 900));
    final service = AppUpdateService()
      ..currentVersion = '1.0.4'
      ..latestVersion = 'v1.0.4'
      ..releaseNotes = '''# Cineo v1.0.4 更新说明

## 版本信息

- 版本号：`v1.0.4`
- 内部构建号：`4`
- 更新时间：`2026-08-22 18:43:50 (Asia/Singapore)`
- 版本类型：功能更新

## 更新内容

- 优化播放体验
- 优化设置页面
- 修复若干已知问题

## 其他说明

${List<String>.generate(20, (index) => '- 详细更新项目 $index').join('\n')}''';

    await tester.pumpWidget(
      MaterialApp(
        theme: buildCineoTheme(),
        home: AppUpdateScreen(updateService: service),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('查看全部'), findsOneWidget);
    expect(find.byType(MarkdownBody), findsNothing);

    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('查看全部'),
      300,
      scrollable: scrollable,
    );
    await tester.tap(find.text('查看全部'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('收起'), findsOneWidget);
    expect(find.byType(MarkdownBody), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
    service.dispose();
  });
}
