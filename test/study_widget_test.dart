import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/services/study_widget_service.dart';

/// The three study home screen widgets render SharedPreferences and nothing
/// else, so what matters is that the right things end up there, in the shape
/// the native side expects.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('counting days to an exam', () {
    test('an exam later tonight is today, not tomorrow', () {
      // 22 hours apart, but the same calendar day is what a reader means.
      final now = DateTime(2026, 11, 15, 1, 0);
      final exam = DateTime(2026, 11, 15, 23, 0);
      expect(StudyWidgetService.daysUntil(exam, now), 0);
    });

    test('an exam tomorrow morning is one day, not zero', () {
      // Only 15 hours apart; counting elapsed hours would call this today.
      final now = DateTime(2026, 11, 15, 18, 0);
      final exam = DateTime(2026, 11, 16, 9, 0);
      expect(StudyWidgetService.daysUntil(exam, now), 1);
    });

    test('a week out counts seven', () {
      expect(
        StudyWidgetService.daysUntil(
          DateTime(2026, 11, 22),
          DateTime(2026, 11, 15),
        ),
        7,
      );
    });

    test('one already past counts negative', () {
      expect(
        StudyWidgetService.daysUntil(
          DateTime(2026, 11, 14),
          DateTime(2026, 11, 15),
        ),
        -1,
      );
    });
  });

  group('how the countdown reads', () {
    test('today and tomorrow are words, not numbers', () {
      expect(StudyWidgetService.countdownLabel(0), 'আজ');
      expect(StudyWidgetService.countdownLabel(1), 'আগামীকাল');
    });

    test('further out is counted, in Bengali numerals', () {
      expect(StudyWidgetService.countdownLabel(3), '৩ দিন বাকি');
      expect(StudyWidgetService.countdownLabel(12), '১২ দিন বাকি');
    });

    test('one that has passed does not read as negative days', () {
      expect(StudyWidgetService.countdownLabel(-2), 'আজ');
    });
  });

  group('the weak topic line', () {
    test('names the first two', () {
      expect(
        StudyWidgetService.weakTopicLine(['সংবিধান', 'ভূগোল', 'ইতিহাস']),
        'দুর্বল: সংবিধান, ভূগোল',
      );
    });

    test('says so plainly when there are none', () {
      expect(
        StudyWidgetService.weakTopicLine([]),
        'কোনো দুর্বল টপিক চিহ্নিত হয়নি',
        reason: 'a bare "দুর্বল:" with nothing after it looks broken',
      );
    });

    test('blank entries do not become empty names', () {
      expect(
        StudyWidgetService.weakTopicLine(['  ', 'সংবিধান']),
        'দুর্বল: সংবিধান',
      );
    });
  });

  group("picking the day's question", () {
    test('it does not move during a day', () {
      final morning = DateTime(2026, 11, 15, 7);
      final evening = DateTime(2026, 11, 15, 22);
      expect(
        StudyWidgetService.questionIndexForDay(9, morning),
        StudyWidgetService.questionIndexForDay(9, evening),
        reason: 'a widget that repainted a new question would be unreadable',
      );
    });

    test('it moves on by itself the next day', () {
      expect(
        StudyWidgetService.questionIndexForDay(9, DateTime(2026, 11, 15)),
        isNot(StudyWidgetService.questionIndexForDay(9, DateTime(2026, 11, 16))),
      );
    });

    test('it always lands inside the bank', () {
      for (var day = 1; day <= 31; day++) {
        final i = StudyWidgetService.questionIndexForDay(
          4,
          DateTime(2026, 1, day),
        );
        expect(i, inInclusiveRange(0, 3));
      }
    });

    test('an empty bank has nothing to pick', () {
      expect(StudyWidgetService.questionIndexForDay(0, DateTime(2026, 11, 15)), -1);
    });
  });

  group('parsing the stored options', () {
    test('a normal row comes back as four', () {
      expect(
        StudyWidgetService.parseOptions('["ক","খ","গ","ঘ"]'),
        ['ক', 'খ', 'গ', 'ঘ'],
      );
    });

    test('a malformed row is empty rather than an exception', () {
      // The native widget would show "Problem loading widget" if this threw
      // during a RemoteViews update.
      expect(StudyWidgetService.parseOptions('not json'), isEmpty);
      expect(StudyWidgetService.parseOptions(''), isEmpty);
    });
  });

  group('what the sync leaves for the widgets', () {
    late AppDatabase db;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase(NativeDatabase.memory());
    });

    // A fresh AppDatabase is not an empty one: it seeds weak topics and a
    // study schedule on creation, so these assert the shape of what is
    // written rather than particular values.
    test('every key the widgets read is filled in', () async {
      await StudyWidgetService.syncStudyData(db);
      final prefs = await SharedPreferences.getInstance();

      // Numbers arrive as display text in Bengali numerals, because the
      // native side renders what it is given rather than formatting it.
      const bengaliDigits = '০১২৩৪৫৬৭৮৯';
      for (final key in [
        StudyWidgetService.keyWrongCount,
        StudyWidgetService.keyDueCount,
        StudyWidgetService.keyAccuracy,
      ]) {
        final value = prefs.getString(key);
        expect(value, isNotNull, reason: '$key must be written');
        expect(
          value!.split('').any(bengaliDigits.contains),
          isTrue,
          reason: '$key should read in Bengali numerals, got "$value"',
        );
      }

      expect(prefs.getString(StudyWidgetService.keyWeakTopics), isNotEmpty);
      expect(prefs.getString(StudyWidgetService.keySyncTime), isNotNull);
      expect(prefs.getString(StudyWidgetService.keyQuestion), isNotNull);
    });

    test('a scheduled exam is described, not just counted', () async {
      await StudyWidgetService.syncStudyData(db);
      final prefs = await SharedPreferences.getInstance();

      // The seed schedule has upcoming exams, so all four keys should be set.
      expect(prefs.getString(StudyWidgetService.keyExamTitle), isNotEmpty);
      expect(prefs.getString(StudyWidgetService.keyExamCountdown), isNotEmpty);
      expect(prefs.getString(StudyWidgetService.keyExamWhen), isNotEmpty);
    });

    test('no scheduled exam clears the keys instead of leaving an old one',
        () async {
      // Clear the seeded schedule so there is genuinely nothing upcoming.
      await db.delete(db.examSchedules).go();

      SharedPreferences.setMockInitialValues({
        'flutter.${StudyWidgetService.keyExamTitle}': 'পুরনো পরীক্ষা',
        'flutter.${StudyWidgetService.keyExamCountdown}': '২ দিন বাকি',
      });

      await StudyWidgetService.syncStudyData(db);
      final prefs = await SharedPreferences.getInstance();

      expect(prefs.getString(StudyWidgetService.keyExamTitle), isNull);
      expect(prefs.getString(StudyWidgetService.keyExamCountdown), isNull);
    });

    test('an empty mistake bank says so rather than showing a blank question',
        () async {
      await StudyWidgetService.syncStudyData(db);
      final prefs = await SharedPreferences.getInstance();

      expect(
        prefs.getString(StudyWidgetService.keyQuestion),
        'ভুলের খাতা খালি — চমৎকার!',
      );
      expect(prefs.getInt(StudyWidgetService.keyCorrectIndex), -1);
    });

    test("a new day hides yesterday's revealed answer again", () async {
      SharedPreferences.setMockInitialValues({
        'flutter.${StudyWidgetService.keyQotdDate}': '2020-01-01',
        'flutter.${StudyWidgetService.keyQotdRevealed}': true,
      });

      await StudyWidgetService.syncStudyData(db);
      final prefs = await SharedPreferences.getInstance();

      expect(prefs.getBool(StudyWidgetService.keyQotdRevealed), isFalse);
      expect(
        prefs.getString(StudyWidgetService.keyQotdDate),
        StudyWidgetService.isoDate(DateTime.now()),
      );
    });
  });
}
