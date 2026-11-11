import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/config/notification_constants.dart';
import 'package:life_and_study_assistant/core/services/attendance/steadfast_lunch_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SteadfastLunchService Model Tests', () {
    test('SteadfastDayMeal parsing and isEditable logic', () {
      final jsonEditable = {
        'date': '2026-11-14',
        'state': 'editable',
        'after_cutoff': false,
        'booked': true,
        'meal': 'Lunch',
        'holiday': null,
      };

      final day = SteadfastDayMeal.fromJson(jsonEditable);
      expect(day.date, equals('2026-11-14'));
      expect(day.booked, isTrue);
      expect(day.meal, equals('Lunch'));
      expect(day.isEditable, isTrue);

      final jsonPast = {
        'date': '2026-11-10',
        'state': 'past',
        'after_cutoff': false,
        'booked': true,
        'meal': 'Lunch',
        'holiday': null,
      };
      final pastDay = SteadfastDayMeal.fromJson(jsonPast);
      expect(pastDay.isEditable, isFalse);

      final jsonCutoff = {
        'date': '2026-11-11',
        'state': 'editable',
        'after_cutoff': true,
        'booked': false,
        'meal': null,
        'holiday': null,
      };
      final cutoffDay = SteadfastDayMeal.fromJson(jsonCutoff);
      expect(cutoffDay.isEditable, isFalse);
    });

    test('SteadfastMealCalendar parsing and findDay', () {
      final calJson = {
        'month': '2026-11',
        'label': 'November 2026',
        'cutoff': '6:00 PM',
        'eligible': true,
        'booked': 12,
        'days': [
          {
            'date': '2026-11-11',
            'state': 'past',
            'after_cutoff': false,
            'booked': true,
            'meal': 'Lunch',
            'holiday': null,
          },
          {
            'date': '2026-11-12',
            'state': 'editable',
            'after_cutoff': false,
            'booked': false,
            'meal': null,
            'holiday': null,
          },
        ],
      };

      final cal = SteadfastMealCalendar.fromJson(calJson);
      expect(cal.month, equals('2026-11'));
      expect(cal.cutoff, equals('6:00 PM'));
      expect(cal.eligible, isTrue);
      expect(cal.bookedCount, equals(12));
      expect(cal.days.length, equals(2));

      final d1 = cal.findDay('2026-11-11');
      expect(d1, isNotNull);
      expect(d1!.booked, isTrue);

      final d2 = cal.findDay('2026-11-12');
      expect(d2, isNotNull);
      expect(d2!.booked, isFalse);

      final dNonExistent = cal.findDay('2026-12-01');
      expect(dNonExistent, isNull);
    });
  });

  group('SteadfastLunchService Simulation Tests', () {
    test('Ping in simulation mode returns success and employee info', () async {
      SharedPreferences.setMockInitialValues({
        NotificationConstants.prefPacklySimulationMode: true,
      });

      final pingRes = await SteadfastLunchService.instance.ping();
      expect(pingRes.success, isTrue);
      expect(pingRes.message, contains('[TEST MODE]'));
      expect(pingRes.userName, contains('Shakib Hossen'));
      expect(pingRes.cutoffTime, equals('6:00 PM'));
    });

    test('toggleTomorrowMeal in simulation mode books and unbooks without server hit', () async {
      final res1 = await SteadfastLunchService.instance.toggleTomorrowMeal(
        forceSimulate: true,
      );
      expect(res1.success, isTrue);
      expect(res1.message, contains('[TEST MODE]'));
      expect(res1.isBooked, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getBool(NotificationConstants.prefLunchLastKnownTomorrowBooked),
        isTrue,
      );

      final res2 = await SteadfastLunchService.instance.toggleMealDate(
        date: res1.targetDate,
        book: false,
        forceSimulate: true,
      );
      expect(res2.success, isTrue);
      expect(res2.isBooked, isFalse);
    });
  });
}
