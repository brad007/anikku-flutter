import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class CastService {
  CastService._();

  static const MethodChannel _channel = MethodChannel('app.anikku/cast');

  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  static Future<void> showAirPlayPicker() =>
      _channel.invokeMethod<void>('showAirPlayPicker');
}
