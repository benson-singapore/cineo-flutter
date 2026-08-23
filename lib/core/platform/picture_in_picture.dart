import 'package:flutter/services.dart';

class PictureInPictureRequest {
  const PictureInPictureRequest({
    required this.url,
    required this.title,
    required this.position,
    required this.aspectRatio,
    required this.isPlaying,
  });

  final String url;
  final String title;
  final Duration position;
  final double aspectRatio;
  final bool isPlaying;

  Map<String, Object> toMap() => <String, Object>{
        'url': url,
        'title': title,
        'positionMilliseconds': position.inMilliseconds,
        'aspectRatio': aspectRatio,
        'isPlaying': isPlaying,
      };
}

typedef PictureInPictureActionHandler = Future<void> Function(String action);
typedef PictureInPictureModeHandler = void Function(bool isInPictureInPicture);

class PictureInPictureService {
  const PictureInPictureService();

  static const _channel = MethodChannel('com.benson.cineo/picture_in_picture');

  Future<void> setEventHandlers({
    PictureInPictureActionHandler? onAction,
    PictureInPictureModeHandler? onModeChanged,
  }) async {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'pictureInPictureAction':
          final action = call.arguments as String?;
          if (action != null && onAction != null) await onAction(action);
        case 'pictureInPictureModeChanged':
          final isInPictureInPicture = call.arguments as bool?;
          if (isInPictureInPicture != null && onModeChanged != null) {
            onModeChanged(isInPictureInPicture);
          }
      }
    });
  }

  Future<bool> isAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> enter(PictureInPictureRequest request) async {
    try {
      return await _channel.invokeMethod<bool>('enter', request.toMap()) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> openSystemPlayer(PictureInPictureRequest request) async {
    try {
      return await _channel.invokeMethod<bool>(
            'openSystemPlayer',
            request.toMap(),
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> update(PictureInPictureRequest request) async {
    try {
      await _channel.invokeMethod<void>('update', request.toMap());
    } on PlatformException {
      // The current platform may not expose dynamic PiP controls.
    } on MissingPluginException {
      // PiP is optional on platforms other than Android and iOS.
    }
  }
}
