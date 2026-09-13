import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cineo_flutter/core/platform/adaptive_navigation.dart';

void main() {
  testWidgets('transparent routes do not block the page underneath',
      (tester) async {
    var taps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => taps++,
              child: const Text('underlying action'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('underlying action'));
    expect(taps, 1);

    unawaited(
      Navigator.of(tester.element(find.text('underlying action'))).push<void>(
        adaptivePageRoute<void>(
          tester.element(find.text('underlying action')),
          opaque: false,
          builder: (_) => const Stack(
            children: [
              Positioned(
                left: 20,
                top: 20,
                width: 120,
                height: 80,
                child: ColoredBox(color: Colors.red),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('underlying action'));
    expect(taps, 2);
  });
}
