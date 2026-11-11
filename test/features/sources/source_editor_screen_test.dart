import 'package:cineo_flutter/features/sources/source_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('rejects an HTTP URL without a host', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SourceEditorScreen(onSave: (_) async {}),
    ));
    await tester.enterText(find.byType(TextFormField).at(0), 'Source');
    await tester.enterText(find.byType(TextFormField).at(1), 'https://');
    await tester.tap(find.text('保存视频源'));
    await tester.pumpAndSettle();

    expect(find.text('请输入有效的 http 或 https 地址'), findsOneWidget);
  });
}
