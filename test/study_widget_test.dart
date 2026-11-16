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

  group('option markers already in the text', () {
    test('a Bengali marker is stripped so it is not rendered twice', () {
      // "ক) ক. ২০%" is what the widget showed before this.
      expect(StudyWidgetService.stripOptionMarker('ক. ২০%'), '২০%');
      expect(StudyWidgetService.stripOptionMarker('খ) ২৫%'), '২৫%');
      expect(StudyWidgetService.stripOptionMarker('গ । ৮০%'), '৮০%');
    });

    test('Latin and numeric markers too', () {
      expect(StudyWidgetService.stripOptionMarker('A. Dhaka'), 'Dhaka');
      expect(StudyWidgetService.stripOptionMarker('1) Dhaka'), 'Dhaka');
    });

    test('an option with no marker is left alone', () {
      expect(StudyWidgetService.stripOptionMarker('২০%'), '২০%');
      expect(StudyWidgetService.stripOptionMarker('ঢাকা'), 'ঢাকা');
    });

    test('a marker that is the whole answer is not eaten', () {
      // The answer to "which option is correct" can itself be "ক."
      expect(StudyWidgetService.stripOptionMarker('ক.'), 'ক.');
    });

    test('text that merely starts with a Bengali word survives', () {
      expect(
        StudyWidgetService.stripOptionMarker('কক্সবাজার'),
        'কক্সবাজার',
        reason: 'only a single letter followed by a separator is a marker',
      );
    });
  });

  group('holding the day\'s question still', () {
    test('it does not move while the bank changes under it', () {
      // Drilling renumbers the bank. Picking by index alone would swap the
      // question on the home screen mid-morning.
      final held = StudyWidgetService.dailyQuestionId(
        bankIds: const [11, 12, 13, 14],
        heldId: 12,
        isSameDay: true,
        day: DateTime(2026, 11, 16),
      );
      expect(held, 12);

      final afterOneWasLearnt = StudyWidgetService.dailyQuestionId(
        bankIds: const [11, 12, 14],
        heldId: 12,
        isSameDay: true,
        day: DateTime(2026, 11, 16),
      );
      expect(afterOneWasLearnt, 12, reason: 'still in the bank, still today');
    });

    test('a new day picks again', () {
      final id = StudyWidgetService.dailyQuestionId(
        bankIds: const [11, 12, 13, 14],
        heldId: 12,
        isSameDay: false,
        day: DateTime(2026, 11, 17),
      );
      expect(id, isNot(12));
      expect(const [11, 12, 13, 14], contains(id));
    });

    test('a question that was finally learnt is replaced, not held', () {
      final id = StudyWidgetService.dailyQuestionId(
        bankIds: const [11, 13, 14],
        heldId: 12,
        isSameDay: true,
        day: DateTime(2026, 11, 16),
      );
      expect(id, isNot(12));
      expect(const [11, 13, 14], contains(id));
    });

    test('an empty bank holds nothing', () {
      expect(
        StudyWidgetService.dailyQuestionId(
          bankIds: const [],
          heldId: 12,
          isSameDay: true,
          day: DateTime(2026, 11, 16),
        ),
        isNull,
      );
    });
  });

  group('reading an exam time', () {
    test('12-hour times with and without a space', () {
      expect(StudyWidgetService.minutesOfDay('10:00 PM'), 22 * 60);
      expect(StudyWidgetService.minutesOfDay('9:30AM'), 9 * 60 + 30);
      expect(StudyWidgetService.minutesOfDay('10.15 am'), 10 * 60 + 15);
    });

    test('midnight and noon do not swap', () {
      expect(StudyWidgetService.minutesOfDay('12:00 AM'), 0);
      expect(StudyWidgetService.minutesOfDay('12:00 PM'), 12 * 60);
    });

    test('24-hour times pass through', () {
      expect(StudyWidgetService.minutesOfDay('18:45'), 18 * 60 + 45);
    });

    test('nonsense reads as unknown rather than as midnight', () {
      expect(StudyWidgetService.minutesOfDay('সকালে'), isNull);
      expect(StudyWidgetService.minutesOfDay(null), isNull);
      expect(StudyWidgetService.minutesOfDay('25:00'), isNull);
    });
  });

  group('which exam the countdown names', () {
    ExamSchedule exam({
      required int id,
      required DateTime date,
      required String time,
      String title = 'পরীক্ষা',
    }) {
      return ExamSchedule(
        id: id,
        examDate: date,
        examTime: time,
        subject: 'বাংলা',
        title: title,
        topicsCovered: '',
        examType: 'Self Test',
        trackName: 'Self Test',
        resourceSummary: null,
        rawReference: null,
        completedStatus: false,
        score: null,
        createdAt: DateTime(2026, 1, 1),
      );
    }

    final now = DateTime(2026, 11, 16, 10, 0);

    test('two exams on one day: the earlier one is next', () {
      // The database query orders by date alone, so these come back in
      // whatever order SQLite chose. Only the time tells them apart.
      final picked = StudyWidgetService.pickNextExam([
        exam(id: 2, date: DateTime(2026, 11, 16), time: '10:00 PM', title: 'রাত'),
        exam(id: 1, date: DateTime(2026, 11, 16), time: '11:00 AM', title: 'সকাল'),
      ], now);

      expect(picked?.title, 'সকাল');
    });

    test('an exam that has already gone is not named at all', () {
      // getUpcomingExams falls back to *past* uncompleted exams when nothing
      // is upcoming. Counted as days, one of those is negative, and the
      // countdown would have called it "আজ".
      final picked = StudyWidgetService.pickNextExam([
        exam(id: 1, date: DateTime(2026, 9, 1), time: '10:00 AM'),
      ], now);

      expect(picked, isNull);
    });

    test("today's exam counts as upcoming, even later in the day", () {
      final picked = StudyWidgetService.pickNextExam([
        exam(id: 1, date: DateTime(2026, 11, 16), time: '9:00 AM'),
      ], now);

      expect(picked, isNotNull, reason: 'the day is what the countdown shows');
    });

    test('a nearer day wins over an earlier hour on a later day', () {
      final picked = StudyWidgetService.pickNextExam([
        exam(id: 1, date: DateTime(2026, 11, 20), time: '6:00 AM', title: 'পরে'),
        exam(id: 2, date: DateTime(2026, 11, 17), time: '11:00 PM', title: 'আগে'),
      ], now);

      expect(picked?.title, 'আগে');
    });

    test('an unreadable time sorts after one that can be read', () {
      final picked = StudyWidgetService.pickNextExam([
        exam(id: 1, date: DateTime(2026, 11, 17), time: 'সকালে', title: 'অজানা'),
        exam(id: 2, date: DateTime(2026, 11, 17), time: '9:00 PM', title: 'জানা'),
      ], now);

      expect(
        picked?.title,
        'জানা',
        reason: 'an unknown time should not jump the queue at midnight',
      );
    });

    test('nothing scheduled at all', () {
      expect(StudyWidgetService.pickNextExam([], now), isNull);
    });
  });

  group('the queue the widget answers from', () {
    DrillQuestion q(int id, String text) => DrillQuestion(
          id: id,
          subject: 'বাংলা',
          topic: 'সংবিধান',
          questionText: text,
          optionsJson: '["ক. ২০%","খ. ২৫%","গ. ৮০%","ঘ. ১৫%"]',
          correctIndex: 1,
          selectedIndex: 0,
          isCorrect: false,
          isMastered: false,
          attemptCount: 1,
          wrongCount: 1,
          attemptedAt: DateTime(2026, 11, 16),
          explanation: 'ব্যাখ্যা',
        );

    final bank = [q(1, 'এক'), q(2, 'দুই'), q(3, 'তিন'), q(4, 'চার')];

    test('it starts at the question chosen for the day', () {
      final queue = StudyWidgetService.buildQuestionQueue(
        bank: bank,
        startId: 3,
      );
      expect(queue.first['id'], 3);
      expect(queue.first['q'], 'তিন');
    });

    test('it wraps, so tapping next keeps working past the end', () {
      final queue = StudyWidgetService.buildQuestionQueue(
        bank: bank,
        startId: 3,
      );
      expect(queue.map((e) => e['id']).toList(), [3, 4, 1, 2]);
    });

    test('markers already in the text are not sent twice', () {
      final queue = StudyWidgetService.buildQuestionQueue(
        bank: bank,
        startId: 1,
      );
      expect(queue.first['o'], ['২০%', '২৫%', '৮০%', '১৫%']);
    });

    test('it carries which option is right', () {
      final queue = StudyWidgetService.buildQuestionQueue(
        bank: bank,
        startId: 1,
      );
      expect(queue.first['c'], 1);
    });

    test('it is capped rather than handing over the whole bank', () {
      final big = List.generate(40, (i) => q(i + 1, 'প্রশ্ন $i'));
      final queue = StudyWidgetService.buildQuestionQueue(
        bank: big,
        startId: 1,
      );
      expect(queue.length, StudyWidgetService.questionQueueLength);
    });

    test('a start that is no longer in the bank begins at the top', () {
      final queue = StudyWidgetService.buildQuestionQueue(
        bank: bank,
        startId: 99,
      );
      expect(queue.first['id'], 1);
    });

    test('an empty bank hands over nothing', () {
      expect(
        StudyWidgetService.buildQuestionQueue(bank: const [], startId: 1),
        isEmpty,
      );
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