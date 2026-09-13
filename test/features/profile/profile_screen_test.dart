import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cineo_flutter/core/theme/cineo_theme.dart';
import 'package:cineo_flutter/features/profile/profile_screen.dart';

void main() {
  testWidgets('shows the cache downloads entry and opens its manager',
      (tester) async {
    var opened = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildCineoTheme(),
        home: ProfileScreen(onOpenDownloads: () => opened = true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('缓存下载'), findsOneWidget);
    expect(find.text('管理已缓存的视频和下载任务'), findsOneWidget);

    await tester.tap(find.text('缓存下载'));
    expect(opened, isTrue);
  });
}
