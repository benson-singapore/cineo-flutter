import 'package:flutter/material.dart';

import 'app_lock_controller.dart';
import 'app_lock_lifecycle.dart';
import 'app_lock_screen.dart';
import 'pin_setup_screen.dart';

class AppLockGate extends StatefulWidget {
  const AppLockGate({
    required this.controller,
    required this.child,
    this.lockedBuilder,
    this.setupBuilder,
    super.key,
  });

  final AppLockController controller;
  final Widget child;
  final WidgetBuilder? lockedBuilder;
  final WidgetBuilder? setupBuilder;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> {
  @override
  void initState() {
    super.initState();
    widget.controller.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return AppLockLifecycle(
      controller: widget.controller,
      child: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, child) {
          if (!widget.controller.initialized) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          if (!widget.controller.hasPin) {
            return widget.setupBuilder?.call(context) ??
                PinSetupScreen(controller: widget.controller);
          }
          if (widget.controller.isLocked) {
            return widget.lockedBuilder?.call(context) ??
                AppLockScreen(controller: widget.controller);
          }
          return child!;
        },
        child: widget.child,
      ),
    );
  }
}
