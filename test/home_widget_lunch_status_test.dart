import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:life_and_study_assistant/core/services/home_widget_service.dart';

/// The home screen widget's refresh button showed the wrong meal status.
///
/// Three things were wrong at once. `getServingStatus()` only returns a value,
/// it writes nothing — so the refresh fetched the live status over the network
/// and dropped it on the floor. What it displayed instead was
/// `last_notified_lunch_status`, which the lunch sentinel writes when it sends
/// a notification, as bookkeeping against notifying twice. And nothing read
/// that key's companion date, so it carried overnight: "Served" at nine the
/// next morning.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const today = '2026-11-15';
  const yesterday = '2026-11-14';

  group('which lunch status the widget shows', () {
    test('what the refresh just fetched wins', () {
      expect(
        HomeWidgetService.resolveLunchStatus(
          fetched: 'cooking',
          notifiedStatus: 'served',
          notifiedDate: today,
          todayIso: today,
        ),
        'cooking',
        reason: 'the live answer is newer than any notification about it',
      );
    });

    test("yesterday's served status does not show up today", () {
      expect(
        HomeWidgetService.resolveLunchStatus(
          fetched: null,
          notifiedStatus: 'served',
          notifiedDate: yesterday,
          todayIso: today,
        ),
        'cooking',
        reason: 'this was the bug: the widget sat on it overnight',
      );
    });

    test("today's notified status is used when the network gave nothing", () {
      expect(
        HomeWidgetService.resolveLunchStatus(
          fetched: null,
          notifiedStatus: 'received',
          notifiedDate: today,
          todayIso: today,
        ),
        'received',
        reason: 'offline, but we did hear about this one today',
      );
    });

    test('a status with no date at all is not trusted for today', () {
      expect(
        HomeWidgetService.resolveLunchStatus(
          fetched: null,
          notifiedStatus: 'served',
          notifiedDate: null,
          todayIso: today,
        ),
        'cooking',
        reason: 'written by a build before the date was recorded',
      );
    });

    test('nothing known at all starts the day where it starts', () {
      expect(
        HomeWidgetService.resolveLunchStatus(
          fetched: null,
          notifiedStatus: null,
          notifiedDate: null,
          todayIso: today,
        ),
        'cooking',
      );
    });

    test('an empty fetched status falls through rather than blanking', () {
      expect(
        HomeWidgetService.resolveLunchStatus(
          fetched: '',
          notifiedStatus: 'served',
          notifiedDate: today,
          todayIso: today,
        ),
        'served',
      );
    });
  });

  group('what updateWidget leaves for the native side', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('a lunch status is stamped with its day', () async {
      await HomeWidgetService.updateWidget(lunchStatus: 'served');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pref_last_notified_lunch_status'), 'served');

      final now = DateTime.now();
      final iso =
          '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
      expect(
        prefs.getString('pref_last_lunch_status_date'),
        iso,
        reason: 'without this the native widget cannot tell stale from fresh',
      );
    });

    test('an explicit date is kept rather than overwritten with now', () async {
      await HomeWidgetService.updateWidget(
        lunchStatus: 'received',
        lunchStatusDate: today,
      );

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pref_last_lunch_status_date'), today);
    });

    test('updating only lunch leaves the attendance keys alone', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.pref_last_check_in_time': '9:05 AM',
        'flutter.pref_last_check_in_date': today,
      });

      // This is how the lunch sentinel calls it: one field, nothing else known.
      await HomeWidgetService.updateWidget(lunchStatus: 'served');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pref_last_check_in_time'), '9:05 AM');
      expect(prefs.getString('pref_last_check_in_date'), today);
    });
  });
}
