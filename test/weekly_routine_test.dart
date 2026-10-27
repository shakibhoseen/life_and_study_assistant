import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/features/weekly_routine/domain/models/weekly_routine.dart';

void main() {
  group('WeeklyRoutine Default Tests', () {
    test('the default week keeps two off days', () {
      final offDays = WeeklyRoutine.defaultRoutine.days
          .where((d) => d.isOffDay)
          .toList();

      expect(offDays.length, 2);
      expect(offDays.map((d) => d.day), containsAll(['বৃহস্পতি', 'শুক্র']));
    });

    test('the default covers a full seven-day week', () {
      expect(WeeklyRoutine.defaultRoutine.days.length, 7);
    });

    test('the evening window is held to one task', () {
      // The whole point of the shape: two cheap commute windows, one short
      // evening. Three windows, not a wall of study hours.
      expect(WeeklyRoutine.defaultRoutine.windows.length, 3);
    });
  });

  group('WeeklyRoutine Round-Trip Tests', () {
    test('encoding and decoding preserves the week', () {
      final original = WeeklyRoutine.defaultRoutine;
      final restored = WeeklyRoutine.tryDecode(original.encode())!;

      expect(restored.title, original.title);
      expect(restored.principle, original.principle);
      expect(restored.days.length, original.days.length);
      expect(restored.windows.length, original.windows.length);
      expect(restored.days.first.day, original.days.first.day);
      expect(
        restored.days.where((d) => d.isOffDay).length,
        original.days.where((d) => d.isOffDay).length,
      );
    });

    test('a command is remembered with the version it produced', () {
      final revised = WeeklyRoutine.defaultRoutine.copyWith(
        lastCommand: 'রাতের সময়টা ৩০ মিনিট করো',
      );

      final restored = WeeklyRoutine.tryDecode(revised.encode())!;
      expect(restored.lastCommand, 'রাতের সময়টা ৩০ মিনিট করো');
    });
  });

  group('WeeklyRoutine Decoding Failure Tests', () {
    test('unreadable storage falls back rather than throwing', () {
      // The screen must still render; a broken value means "use the default".
      expect(WeeklyRoutine.tryDecode(null), isNull);
      expect(WeeklyRoutine.tryDecode(''), isNull);
      expect(WeeklyRoutine.tryDecode('not json at all'), isNull);
      expect(WeeklyRoutine.tryDecode('[1,2,3]'), isNull);
    });

    test('a partial routine decodes to something usable', () {
      final partial = WeeklyRoutine.tryDecode('{"title":"ছক"}');

      expect(partial, isNotNull);
      expect(partial!.title, 'ছক');
      expect(partial.days, isEmpty);
      expect(partial.windows, isEmpty);
    });
  });
}
