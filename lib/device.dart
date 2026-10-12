import 'package:flutter/services.dart';
import 'store.dart';

class WalkingDevice {
  static const sandboxEnabled = bool.fromEnvironment('LANGKAH_SANDBOX');
  // Compile-time test entry only. Production builds cannot enable these inputs.
  static JsonMap Function()? sandboxLocation;
  static Stream<int>? sandboxSteps;
  static const _methods = MethodChannel('langkah/device');
  static const _events = EventChannel('langkah/steps');
  static Future<void> requestActivity() async {
    if (!sandboxEnabled) await _methods.invokeMethod('requestActivity');
  }

  static Future<void> openUrl(String url) async =>
      await _methods.invokeMethod('openUrl', {'url': url});
  static Future<void> keepAwake(bool enabled) async {
    if (!sandboxEnabled) {
      await _methods.invokeMethod('keepAwake', {'enabled': enabled});
    }
  }

  static Future<JsonMap> location() async => sandboxEnabled
      ? sandboxLocation!()
      : JsonMap.from(await _methods.invokeMapMethod('location') ?? {});
  static Stream<int> get steps => sandboxEnabled
      ? sandboxSteps!
      : _events.receiveBroadcastStream().map((v) => (v as num).toInt());
}
