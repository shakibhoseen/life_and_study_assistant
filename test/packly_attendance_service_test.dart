import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/config/notification_constants.dart';
import 'package:life_and_study_assistant/core/services/attendance/packly_attendance_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PacklyAttendanceService Tests', () {
    test('simpleHash djb2 produces valid hex hash', () {
      final hash1 = PacklyAttendanceService.simpleHash('TestString123');
      final hash2 = PacklyAttendanceService.simpleHash('TestString123');
      final hash3 = PacklyAttendanceService.simpleHash('DifferentString');

      expect(hash1, isNotEmpty);
      expect(hash1, equals(hash2));
      expect(hash1, isNot(equals(hash3)));
    });

    test('PacklyAttendanceStatus properties format correctly', () {
      const status = PacklyAttendanceStatus(
        isCheckedIn: true,
        isCheckedOut: false,
        checkInTime: '09:14:20 AM',
        statusText: 'In Progress',
        isLate: false,
      );

      expect(status.isCheckedIn, isTrue);
      expect(status.isCheckedOut, isFalse);
      expect(status.isLate, isFalse);
      expect(status.checkInTime, equals('09:14:20 AM'));
      expect(status.toString(), contains('In Progress'));
    });

    test('PacklyAttendanceStatus late detection', () {
      const lateStatus = PacklyAttendanceStatus(
        isCheckedIn: true,
        isCheckedOut: false,
        checkInTime: '09:19:26 AM',
        statusText: 'In Progress',
        isLate: true,
      );

      expect(lateStatus.isLate, isTrue);
      expect(lateStatus.checkInTime, equals('09:19:26 AM'));
    });

    test('PacklyHoliday date containment test', () {
      final holidaySingle = PacklyHoliday(
        name: 'Victory Day',
        startDate: DateTime(2026, 12, 16),
        endDate: DateTime(2026, 12, 16),
      );

      expect(holidaySingle.containsDate(DateTime(2026, 12, 16)), isTrue);
      expect(holidaySingle.containsDate(DateTime(2026, 12, 15)), isFalse);
      expect(holidaySingle.containsDate(DateTime(2026, 12, 17)), isFalse);

      final holidayRange = PacklyHoliday(
        name: 'Eid ul-Fitr Holiday',
        startDate: DateTime(2026, 3, 19),
        endDate: DateTime(2026, 3, 23),
      );

      expect(holidayRange.containsDate(DateTime(2026, 3, 19)), isTrue);
      expect(holidayRange.containsDate(DateTime(2026, 3, 21)), isTrue);
      expect(holidayRange.containsDate(DateTime(2026, 3, 23)), isTrue);
      expect(holidayRange.containsDate(DateTime(2026, 3, 18)), isFalse);
      expect(holidayRange.containsDate(DateTime(2026, 3, 24)), isFalse);
    });

    test('forceSimulate checkIn and checkOut produces mock success without server hit', () async {
      final checkInResult = await PacklyAttendanceService.instance.checkIn(
        forceSimulate: true,
      );

      expect(checkInResult.success, isTrue);
      expect(checkInResult.message, contains('[TEST MODE]'));
      expect(checkInResult.status?.isCheckedIn, isTrue);
      expect(checkInResult.status?.checkInTime, isNotNull);

      final status = await PacklyAttendanceService.instance.getAttendanceStatus(
        forceSimulate: true,
      );
      expect(status.isCheckedIn, isTrue);
      expect(status.statusText, contains('Test Mode'));

      final checkOutResult = await PacklyAttendanceService.instance.checkOut(
        forceSimulate: true,
      );

      expect(checkOutResult.success, isTrue);
      expect(checkOutResult.message, contains('[TEST MODE]'));
      expect(checkOutResult.status?.isCheckedOut, isTrue);
      expect(checkOutResult.status?.checkOutTime, isNotNull);

      // Verify that simulation mode NEVER contaminated production keys
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(NotificationConstants.prefLastCheckOutDate), isNull);
      expect(prefs.getString(NotificationConstants.prefLastCheckOutTime), isNull);
      expect(prefs.getString(NotificationConstants.prefLastCheckInDate), isNull);

      // Verify simulated keys WERE populated
      expect(prefs.getString(NotificationConstants.prefSimulatedCheckOutDate), isNotNull);
      expect(prefs.getString(NotificationConstants.prefSimulatedCheckOutTime), isNotNull);
      expect(prefs.getString(NotificationConstants.prefSimulatedCheckInDate), isNotNull);

      // Verify clearSimulationData wipes them cleanly
      await PacklyAttendanceService.instance.clearSimulationData();
      expect(prefs.getString(NotificationConstants.prefSimulatedCheckOutDate), isNull);
      expect(prefs.getString(NotificationConstants.prefSimulatedCheckOutTime), isNull);
      expect(prefs.getString(NotificationConstants.prefSimulatedCheckInDate), isNull);
    });

    test('clearSimulationData sanitizes any legacy mock values in real keys', () async {
      SharedPreferences.setMockInitialValues({
        NotificationConstants.prefLastCheckInStatus: 'Punched In (Test Mode)',
        NotificationConstants.prefLastCheckInDate: '2026-11-11',
        NotificationConstants.prefLastCheckOutDate: '2026-11-11',
        NotificationConstants.prefLastCheckOutTime: '06:00 PM',
      });

      await PacklyAttendanceService.instance.clearSimulationData(sanitizeRealKeys: true);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(NotificationConstants.prefLastCheckInStatus), isNull);
      expect(prefs.getString(NotificationConstants.prefLastCheckInDate), isNull);
      expect(prefs.getString(NotificationConstants.prefLastCheckOutDate), isNull);
      expect(prefs.getString(NotificationConstants.prefLastCheckOutTime), isNull);
    });

    test('prefPacklySimulationMode toggle enables safe simulation', () async {
      SharedPreferences.setMockInitialValues({
        NotificationConstants.prefPacklySimulationMode: true,
      });

      final checkInResult = await PacklyAttendanceService.instance.checkIn();
      expect(checkInResult.success, isTrue);
      expect(checkInResult.message, contains('[TEST MODE]'));
      expect(checkInResult.status?.isCheckedIn, isTrue);
    });
  });
}
