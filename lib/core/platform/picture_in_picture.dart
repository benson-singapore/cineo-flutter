import 'package:flutter/services.dart';

class PictureInPictureRequest {
  const PictureInPictureRequest({
    required this.url,
    required this.title,
    required this.position,
  });

  final String url;
  final String title;
  final Duration position;

  Map<String, Object> toMap() => <String, Object>{
        'url': url,
        'title': title,
        'positionMilliseconds': position.inMilliseconds,
      };
}

class PictureInPictureService {
  const PictureInPictureService();

  static const _channel = MethodChannel('com.benson.cineo/picture_in_picture');

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
}
