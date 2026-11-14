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

    test('SteadfastServingStatus and SteadfastServingStep parsing & state checks', () {
      final jsonServing = {
        'booked': true,
        'meal': 'Lunch',
        'status': 'upcoming',
        'label': 'Upcoming',
        'message': 'Your meal is on its way to the canteen.',
        'updated_at': '12:25 PM',
        'steps': [
          {'status': 'cooking', 'label': 'Cooking', 'done': true, 'current': false, 'at': null},
          {'status': 'upcoming', 'label': 'Upcoming', 'done': true, 'current': true, 'at': '12:25 PM'},
          {'status': 'received', 'label': 'Received', 'done': false, 'current': false, 'at': null},
          {'status': 'served', 'label': 'Served', 'done': false, 'current': false, 'at': null},
        ],
      };

      final serving = SteadfastServingStatus.fromJson(jsonServing);
      expect(serving.booked, isTrue);
      expect(serving.status, equals('upcoming'));
      expect(serving.isUpcoming, isTrue);
      expect(serving.isReceived, isFalse);
      expect(serving.isServed, isFalse);
      expect(serving.bengaliStatusLabel, contains('রওনা হয়েছে'));
      expect(serving.steps.length, equals(4));

      final jsonReceived = {
        'booked': true,
        'meal': 'Lunch',
        'status': 'received',
        'label': 'Received',
        'message': 'Food car arrived at office.',
        'updated_at': '1:05 PM',
        'steps': [
          {'status': 'cooking', 'label': 'Cooking', 'done': true, 'current': false},
          {'status': 'upcoming', 'label': 'Upcoming', 'done': true, 'current': false},
          {'status': 'received', 'label': 'Received', 'done': true, 'current': true},
          {'status': 'served', 'label': 'Served', 'done': false, 'current': false},
        ],
      };
      final recv = SteadfastServingStatus.fromJson(jsonReceived);
      expect(recv.isReceived, isTrue);
      expect(recv.isServed, isFalse);
      expect(recv.bengaliStatusLabel, contains('অফিসে এসে পৌঁছেছে'));

      final jsonServed = {
        'booked': true,
        'meal': 'Lunch',
        'status': 'served',
        'label': 'Served',
        'message': 'Lunch is ready to eat.',
        'updated_at': '1:18 PM',
        'steps': [
          {'status': 'cooking', 'label': 'Cooking', 'done': true, 'current': false},
          {'status': 'upcoming', 'label': 'Upcoming', 'done': true, 'current': false},
          {'status': 'received', 'label': 'Received', 'done': true, 'current': false},
          {'status': 'served', 'label': 'Served', 'done': true, 'current': true},
        ],
      };
      final srv = SteadfastServingStatus.fromJson(jsonServed);
      expect(srv.isReceived, isTrue);
      expect(srv.isServed, isTrue);
      expect(srv.bengaliStatusLabel, contains('পরিবেশন শুরু'));
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

    test('getServingStatus in simulation mode returns mock status', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(NotificationConstants.prefPacklySimulationMode, true);
      await prefs.setString(NotificationConstants.prefSimulatedServingStatus, 'received');

      final status = await SteadfastLunchService.instance.getServingStatus();
      expect(status, isNotNull);
      expect(status!.status, equals('received'));
      expect(status.isReceived, isTrue);
      expect(status.isServed, isFalse);
    });
  });
}
