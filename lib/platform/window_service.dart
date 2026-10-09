import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class WindowService {
  WindowService._();

  static const MethodChannel _channel = MethodChannel('app.anikku/window');

  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  static Future<void> enterFullscreen() =>
      _channel.invokeMethod<void>('enterFullscreen');

  static Future<void> exitFullscreen() =>
      _channel.invokeMethod<void>('exitFullscreen');
}
