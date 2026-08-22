import 'package:flutter/widgets.dart';

import 'app_lock_controller.dart';

class AppLockLifecycle extends StatefulWidget {
  const AppLockLifecycle({
    required this.controller,
    required this.child,
    super.key,
  });

  final AppLockController controller;
  final Widget child;

  @override
  State<AppLockLifecycle> createState() => _AppLockLifecycleState();
}

class _AppLockLifecycleState extends State<AppLockLifecycle>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      widget.controller.lock();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
