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
    return PageRouteBuilder<T>(
      opaque: false,
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
