import 'package:flutter/services.dart';

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

  Future<bool> enter({double aspectRatio = 16 / 9}) async {
    try {
      return await _channel.invokeMethod<bool>('enter', {
            'aspectRatio': aspectRatio,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
