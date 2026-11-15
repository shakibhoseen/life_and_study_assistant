import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:life_and_study_assistant/core/services/background/workmanager_service.dart';
import 'package:life_and_study_assistant/core/services/home_widget_service.dart';

/// The widgets are meant to keep themselves current without anyone pressing
/// refresh: lunch comes from the sentinel, attendance from a punch, and the
/// date-driven study figures from one background job a day.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('mirroring attendance for the widget', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('a check-in is written where the widget looks first', () async {
      await HomeWidgetService.mirrorAttendance(
        checkInDate: '2026-11-15',
        checkInTime: '08:54 AM',
        isLate: false,
      );

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pref_last_check_in_date'), '2026-11-15');
      expect(prefs.getString('pref_last_check_in_time'), '08:54 AM');
      expect(prefs.getBool('pref_last_check_in_is_late'), isFalse);
      expect(prefs.getString('widget_last_sync_time'), isNotNull);
    });

    test('a cleared check-out is cleared in the mirror too', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.pref_last_check_out_date': '2026-11-14',
        'flutter.pref_last_check_out_time': '06:10 PM',
      });

      // The portal says the check-out is still pending. The widget reads the
      // mirror in preference to the source keys, so leaving it would keep
      // yesterday's "Checked Out" on screen.
      await HomeWidgetService.mirrorAttendance(
        checkInDate: '2026-11-15',
        checkInTime: '08:54 AM',
        isLate: false,
      );

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pref_last_check_out_date'), isNull);
      expect(prefs.getString('pref_last_check_out_time'), isNull);
    });

    test('nothing punched at all clears every attendance key', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.pref_last_check_in_date': '2026-11-14',
        'flutter.pref_last_check_in_time': '09:01 AM',
        'flutter.pref_last_check_in_is_late': true,
      });

      await HomeWidgetService.mirrorAttendance();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pref_last_check_in_date'), isNull);
      expect(prefs.getString('pref_last_check_in_time'), isNull);
      expect(prefs.getBool('pref_last_check_in_is_late'), isNull);
    });

    test('an empty string is an absence, not a value', () async {
      await HomeWidgetService.mirrorAttendance(checkInDate: '', checkInTime: '');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pref_last_check_in_date'), isNull);
    });
  });

  group('when the daily study refresh lands', () {
    test('before 5 AM it waits until this morning', () {
      final delay = WorkmanagerService.delayUntilNextDailyRefresh(
        DateTime(2026, 11, 15, 2, 30),
      );
      expect(delay, const Duration(hours: 2, minutes: 30));
    });

    test('after 5 AM it crosses midnight rather than going negative', () {
      final delay = WorkmanagerService.delayUntilNextDailyRefresh(
        DateTime(2026, 11, 15, 22, 0),
      );
      expect(delay, const Duration(hours: 7));
      expect(delay.isNegative, isFalse);
    });

    test('at exactly 5 AM it means tomorrow, not right now', () {
      final delay = WorkmanagerService.delayUntilNextDailyRefresh(
        DateTime(2026, 11, 15, 5, 0),
      );
      expect(
        delay,
        const Duration(hours: 24),
        reason: 'zero would re-run the job that has just finished',
      );
    });

    test('it is never more than a day away', () {
      for (var hour = 0; hour < 24; hour++) {
        final delay = WorkmanagerService.delayUntilNextDailyRefresh(
          DateTime(2026, 11, 15, hour, 7),
        );
        expect(delay.inHours, lessThanOrEqualTo(24));
        expect(delay.isNegative, isFalse);
      }
    });
  });
}
