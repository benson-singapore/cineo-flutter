import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Keeps navigation native to the active platform without making feature
/// screens depend on a specific app shell.
Route<T> adaptivePageRoute<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  RouteSettings? settings,
  bool fullscreenDialog = false,
}) {
  final platform = Theme.of(context).platform;
  if (platform == TargetPlatform.iOS) {
    return CupertinoPageRoute<T>(
      builder: builder,
      settings: settings,
      fullscreenDialog: fullscreenDialog,
    );
  }
  return MaterialPageRoute<T>(
    builder: builder,
    settings: settings,
    fullscreenDialog: fullscreenDialog,
  );
}
