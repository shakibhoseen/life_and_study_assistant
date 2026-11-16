import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:life_and_study_assistant/core/services/background/sentinel_clock.dart';
import 'package:life_and_study_assistant/core/services/background/sentinel_log.dart';

/// Auto check-in happens with the phone in a pocket, so when it does not
/// happen there is nothing left to look at: logcat needs someone attached and
/// rolls over within hours. These two exist so a quiet morning can be read
/// afterwards, and so the time-of-day rules can be tried without being at the
/// office at nine.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the sentinel diary', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('newest first, because the question is what just happened', () async {
      await SentinelLog.write('first');
      await SentinelLog.write('second');

      final entries = await SentinelLog.read();
      expect(entries.first, contains('second'));
      expect(entries.last, contains('first'));
    });

    test('every line is stamped with when it happened', () async {
      final prefs = await SharedPreferences.getInstance();
      await SentinelLog.writeAt(
        prefs,
        'office wifi matched',
        DateTime(2026, 11, 16, 9, 7, 4),
      );

      expect((await SentinelLog.read()).single, '16/11 09:07:04  office wifi matched');
    });

    test('it stops growing, rather than bloating the preferences file',
        () async {
      for (var i = 0; i < SentinelLog.maxEntries + 40; i++) {
        await SentinelLog.write('entry $i');
      }

      final entries = await SentinelLog.read();
      expect(entries.length, SentinelLog.maxEntries);
      // The oldest are the ones dropped.
      expect(entries.first, contains('entry ${SentinelLog.maxEntries + 39}'));
    });

    test('clearing empties it', () async {
      await SentinelLog.write('something');
      await SentinelLog.clear();
      expect(await SentinelLog.read(), isEmpty);
    });
  });

  group('the pretend clock', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('with nothing set, it is simply now', () async {
      final prefs = await SharedPreferences.getInstance();
      final real = DateTime(2026, 11, 16, 14, 30);
      expect(SentinelClock.now(prefs, realNow: real), real);
      expect(SentinelClock.isOverridden(prefs, realNow: real), isFalse);
    });

    test('a pretend morning is reported instead of the real hour', () async {
      final setAt = DateTime(2026, 11, 16, 14, 0);
      SharedPreferences.setMockInitialValues({
        'flutter.${SentinelClock.prefFakeNow}':
            DateTime(2026, 11, 16, 8, 45).toIso8601String(),
        'flutter.${SentinelClock.prefFakeNowSetAt}': setAt.toIso8601String(),
      });
      final prefs = await SharedPreferences.getInstance();

      expect(SentinelClock.now(prefs, realNow: setAt).hour, 8);
      expect(SentinelClock.now(prefs, realNow: setAt).minute, 45);
    });

    test('it runs, so a window can be watched opening and closing', () async {
      final setAt = DateTime(2026, 11, 16, 14, 0);
      SharedPreferences.setMockInitialValues({
        'flutter.${SentinelClock.prefFakeNow}':
            DateTime(2026, 11, 16, 8, 45).toIso8601String(),
        'flutter.${SentinelClock.prefFakeNowSetAt}': setAt.toIso8601String(),
      });
      final prefs = await SharedPreferences.getInstance();

      // Ten real minutes later the pretend clock has also moved ten.
      final later = SentinelClock.now(
        prefs,
        realNow: setAt.add(const Duration(minutes: 10)),
      );
      expect(later.hour, 8);
      expect(later.minute, 55);
    });

    test('it expires, so a forgotten override cannot break a real morning',
        () async {
      final setAt = DateTime(2026, 11, 16, 14, 0);
      SharedPreferences.setMockInitialValues({
        'flutter.${SentinelClock.prefFakeNow}':
            DateTime(2026, 11, 16, 8, 45).toIso8601String(),
        'flutter.${SentinelClock.prefFakeNowSetAt}': setAt.toIso8601String(),
      });
      final prefs = await SharedPreferences.getInstance();

      // The next morning, with the override still sitting in preferences.
      final tomorrow = DateTime(2026, 11, 17, 9, 5);
      expect(
        SentinelClock.now(prefs, realNow: tomorrow),
        tomorrow,
        reason: 'this is the clock an attendance decision is made on',
      );
      expect(SentinelClock.isOverridden(prefs, realNow: tomorrow), isFalse);
    });

    test('a device clock that moved backwards is not trusted', () async {
      final setAt = DateTime(2026, 11, 16, 14, 0);
      SharedPreferences.setMockInitialValues({
        'flutter.${SentinelClock.prefFakeNow}':
            DateTime(2026, 11, 16, 8, 45).toIso8601String(),
        'flutter.${SentinelClock.prefFakeNowSetAt}': setAt.toIso8601String(),
      });
      final prefs = await SharedPreferences.getInstance();

      final earlier = setAt.subtract(const Duration(hours: 1));
      expect(SentinelClock.now(prefs, realNow: earlier), earlier);
    });

    test('a corrupt value falls back to the real time', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.${SentinelClock.prefFakeNow}': 'not a date',
        'flutter.${SentinelClock.prefFakeNowSetAt}': 'also not a date',
      });
      final prefs = await SharedPreferences.getInstance();

      final real = DateTime(2026, 11, 16, 14, 30);
      expect(SentinelClock.now(prefs, realNow: real), real);
    });

    test('clearing it brings back the real time', () async {
      await SentinelClock.pretendItIs(DateTime(2026, 11, 16, 8, 45));
      await SentinelClock.clear();

      final prefs = await SharedPreferences.getInstance();
      final real = DateTime(2026, 11, 16, 14, 30);
      expect(SentinelClock.now(prefs, realNow: real), real);
    });
  });
}
