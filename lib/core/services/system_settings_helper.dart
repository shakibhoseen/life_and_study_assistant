import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class SystemSettingsHelper {
  static const MethodChannel _channel = MethodChannel(
    'com.example.life_and_study_assistant/system_settings',
  );

  /// Opens the app's Notification Settings (Channel list, custom sounds, badges)
  static Future<void> openNotificationSettings() async {
    try {
      await _channel.invokeMethod('openNotificationSettings');
    } catch (_) {
      await openAppSettings();
    }
  }

  /// Opens Special App Access -> Notification Access (Notification Listener)
  static Future<void> openNotificationListenerSettings() async {
    try {
      await _channel.invokeMethod('openNotificationListenerSettings');
    } catch (_) {
      await openAppSettings();
    }
  }

  /// Opens Battery Optimization Exemption Settings
  static Future<void> openBatteryOptimizationSettings() async {
    try {
      await _channel.invokeMethod('openBatteryOptimizationSettings');
    } catch (_) {
      await openAppSettings();
    }
  }
}
