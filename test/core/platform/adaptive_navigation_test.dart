import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cineo_flutter/core/platform/adaptive_navigation.dart';

void main() {
  testWidgets('uses Cupertino route transitions on iOS', (tester) async {
    late Route<void> route;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: Builder(
          builder: (context) {
            route = adaptivePageRoute<void>(
              context,
              builder: (_) => const SizedBox(),
            );
            return const SizedBox();
          },
        ),
      ),
    );

    expect(route, isA<CupertinoPageRoute<void>>());
  });

  testWidgets('keeps a Material route on Android', (tester) async {
    late Route<void> route;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Builder(
          builder: (context) {
            route = adaptivePageRoute<void>(
              context,
              builder: (_) => const SizedBox(),
            );
            return const SizedBox();
          },
        ),
      ),
    );

    expect(route, isA<MaterialPageRoute<void>>());
  });
}
