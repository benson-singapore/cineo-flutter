import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Keeps navigation native to the active platform without making feature
/// screens depend on a specific app shell.
Route<T> adaptivePageRoute<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  RouteSettings? settings,
  bool fullscreenDialog = false,
  bool opaque = true,
  ValueListenable<bool>? preventPop,
  VoidCallback? onPopPrevented,
}) {
  final platform = Theme.of(context).platform;
  if (platform == TargetPlatform.iOS && opaque) {
    return CupertinoPageRoute<T>(
      builder: builder,
      settings: settings,
      fullscreenDialog: fullscreenDialog,
    );
  }
  if (!opaque) {
    return _TransparentPageRoute<T>(
      pageBuilder: (context, animation, secondaryAnimation) => builder(context),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(opacity: animation, child: child),
      settings: settings,
      preventPop: preventPop,
      onPopPrevented: onPopPrevented,
    );
  }
  return MaterialPageRoute<T>(
    builder: builder,
    settings: settings,
    fullscreenDialog: fullscreenDialog,
  );
}

/// A transparent route whose empty area remains interactive for the route
/// below. ModalRoute normally inserts a full-screen transparent barrier even
/// when [opaque] is false, which makes in-app picture-in-picture windows block
/// taps on the page underneath.
class _TransparentPageRoute<T> extends PageRouteBuilder<T> {
  _TransparentPageRoute({
    required super.pageBuilder,
    required super.transitionsBuilder,
    super.settings,
    this.preventPop,
    this.onPopPrevented,
  }) : super(
          opaque: false,
          barrierDismissible: false,
        );

  final ValueListenable<bool>? preventPop;
  final VoidCallback? onPopPrevented;
  Route<dynamic>? _initialPreviousRoute;
  bool _previousRouteWasRemoved = false;

  @override
  void didChangePrevious(Route<dynamic>? previousRoute) {
    if (_initialPreviousRoute == null) {
      _initialPreviousRoute = previousRoute;
    } else if (!identical(_initialPreviousRoute, previousRoute)) {
      _previousRouteWasRemoved = true;
    }
    super.didChangePrevious(previousRoute);
  }

  @override
  bool didPop(T? result) {
    if (preventPop?.value == true) {
      if (!_previousRouteWasRemoved) onPopPrevented?.call();
      return false;
    }
    return super.didPop(result);
  }

  @override
  Widget buildModalBarrier() {
    return const IgnorePointer(
      ignoring: true,
      child: SizedBox.expand(),
    );
  }
}
