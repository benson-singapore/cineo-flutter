import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Keeps navigation native to the active platform without making feature
/// screens depend on a specific app shell.
Route<T> adaptivePageRoute<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  RouteSettings? settings,
  bool fullscreenDialog = false,
  bool opaque = true,
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
  }) : super(
          opaque: false,
          barrierDismissible: false,
        );

  @override
  Widget buildModalBarrier() {
    return const IgnorePointer(
      ignoring: true,
      child: SizedBox.expand(),
    );
  }
}
