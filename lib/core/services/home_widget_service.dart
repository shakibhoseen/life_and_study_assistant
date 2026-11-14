import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeWidgetService {
  static const MethodChannel _channel = MethodChannel(
    'com.example.life_and_study_assistant/system_settings',
  );

  /// Synchronizes current office & lunch data to native home screen widget
  static Future<void> updateWidget({
    String? checkInTime,
    String? checkInDate,
    bool? isLate,
    String? checkOutTime,
    String? checkOutDate,
    String? lunchStatus,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final timeStr =
          '${(now.hour % 12 == 0 ? 12 : now.hour % 12).toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} ${now.hour >= 12 ? 'PM' : 'AM'}';

      await prefs.setString('widget_last_sync_time', timeStr);

      if (checkInTime != null) {
        await prefs.setString('pref_last_check_in_time', checkInTime);
      }
      if (checkInDate != null) {
        await prefs.setString('pref_last_check_in_date', checkInDate);
      }
      if (isLate != null) {
        await prefs.setBool('pref_last_check_in_is_late', isLate);
      }
      if (checkOutTime != null) {
        await prefs.setString('pref_last_check_out_time', checkOutTime);
      }
      if (checkOutDate != null) {
        await prefs.setString('pref_last_check_out_date', checkOutDate);
      }
      if (lunchStatus != null) {
        await prefs.setString('pref_last_notified_lunch_status', lunchStatus);
      }

      await _channel.invokeMethod('updateWidget');
      debugPrint('HomeWidget: updated widget data successfully ($timeStr)');
    } catch (e) {
      debugPrint('HomeWidget: could not update widget: $e');
    }
  }
}
