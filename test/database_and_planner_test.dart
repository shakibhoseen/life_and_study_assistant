import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/database/tables/daily_energy_logs_table.dart';
import 'package:life_and_study_assistant/core/database/tables/weak_topics_table.dart';
import 'package:life_and_study_assistant/core/services/ai/gemini_ai_service.dart';
import 'package:life_and_study_assistant/core/services/background/wifi_monitor_service.dart';
import 'package:life_and_study_assistant/features/live_mcq/data/repositories/exam_schedule_repository_impl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // In-memory sqlite database for fast, isolated testing
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('Drift Local Database Tests', () {
    test('Can insert and retrieve weak topics', () async {
      final id = await db.insertWeakTopic(
        WeakTopicsCompanion.insert(
          subject: 'Bangla Grammar',
          topicName: 'কারক ও বিভক্তি',
          proficiencyLevel: ProficiencyLevel.weak,
          notes: const Value('Accusative case confusion'),
        ),
      );

      expect(id, isPositive);

      final topics = await db.getAllWeakTopics();
      expect(topics.any((t) => t.topicName == 'কারক ও বিভক্তি'), isTrue);

      final inserted = topics.firstWhere((t) => t.id == id);
      expect(inserted.subject, equals('Bangla Grammar'));
      expect(inserted.proficiencyLevel, equals(ProficiencyLevel.weak));
    });

    test('Can update topic proficiency level', () async {
      final id = await db.insertWeakTopic(
        WeakTopicsCompanion.insert(
          subject: 'Mathematics',
          topicName: 'শতকরা ও লাভ-ক্ষতি',
          proficiencyLevel: ProficiencyLevel.weak,
        ),
      );

      final existing = (await db.getAllWeakTopics()).firstWhere(
        (t) => t.id == id,
      );
      final updated = await db.updateWeakTopic(
        existing.copyWith(proficiencyLevel: ProficiencyLevel.strong),
      );

      expect(updated, isTrue);

      final afterUpdate = (await db.getAllWeakTopics()).firstWhere(
        (t) => t.id == id,
      );
      expect(afterUpdate.proficiencyLevel, equals(ProficiencyLevel.strong));
    });

    test('Can insert and fetch upcoming LiveMCQ exams (prioritizing future exams over past dates)', () async {
      final pastDate = DateTime.now().subtract(const Duration(days: 30));
      final futureDate = DateTime.now().add(const Duration(days: 3));

      // Insert an old exam from a month ago
      await db.insertExamSchedule(
        ExamSchedulesCompanion.insert(
          examDate: pastDate,
          title: 'Old LiveMCQ Past Exam',
          topicsCovered: 'Ancient History',
        ),
      );

      // Insert an upcoming exam
      await db.insertExamSchedule(
        ExamSchedulesCompanion.insert(
          examDate: futureDate,
          title: 'LiveMCQ 47th BCS Model Test 12',
          topicsCovered: 'General Science & Optics',
          resourceSummary: const Value('High yield 20 marks'),
        ),
      );

      final upcoming = await db.getUpcomingExams();
      expect(upcoming.length, greaterThanOrEqualTo(1));
      // Future exam must be in upcoming, and past exam must NOT be in upcoming
      expect(upcoming.any((e) => e.title.contains('Model Test 12')), isTrue);
      expect(upcoming.any((e) => e.title == 'Old LiveMCQ Past Exam'), isFalse);
    });

    test(
      'Can mark exam as completed with score and revert to incomplete',
      () async {
        final repo = ExamScheduleRepositoryImpl(db);
        final id = await repo.addExam(
          examDate: DateTime.now().add(const Duration(days: 4)),
          title: 'Score Tracking Test',
          topicsCovered: 'Algebra',
        );

        final success = await repo.markExamCompleted(id, score: 87.5);
        expect(success, isTrue);

        final completedExam = (await db.select(db.examSchedules).get())
            .firstWhere((e) => e.id == id);
        expect(completedExam.completedStatus, isTrue);
        expect(completedExam.score, equals(87.5));

        final unmarkSuccess = await repo.markExamIncomplete(id);
        expect(unmarkSuccess, isTrue);

        final revertedExam = (await db.select(db.examSchedules).get())
            .firstWhere((e) => e.id == id);
        expect(revertedExam.completedStatus, isFalse);
        expect(revertedExam.score, isNull);
      },
    );

    test('Can insert, filter by track, and fetch distinct tracks', () async {
      final date1 = DateTime.now().add(const Duration(days: 1));
      final date2 = DateTime.now().add(const Duration(days: 2));

      await db.insertExamSchedule(
        ExamSchedulesCompanion.insert(
          examDate: date1,
          title: 'Daily Vocab Drill 01',
          topicsCovered: 'Synonyms',
          trackName: const Value('Vocabulary Booster'),
        ),
      );

      await db.insertExamSchedule(
        ExamSchedulesCompanion.insert(
          examDate: date2,
          title: '135-Day Exam 10',
          topicsCovered: 'Bangla Grammar',
          trackName: const Value('52nd BCS 135-Day'),
        ),
      );

      final vocabExams = await db.watchExamsByTrack('Vocabulary Booster').first;
      expect(vocabExams.any((e) => e.title == 'Daily Vocab Drill 01'), isTrue);
      expect(vocabExams.any((e) => e.trackName == '52nd BCS 135-Day'), isFalse);

      final distinctTracks = await db.watchAllDistinctTracks().first;
      expect(distinctTracks, contains('Vocabulary Booster'));
      expect(distinctTracks, contains('52nd BCS 135-Day'));
    });

    test('Deduplication: Inserting the same routine/PDF exams twice detects duplicates and skips them', () async {
      final examDate = DateTime(2026, 11, 15);
      final companions = [
        ExamSchedulesCompanion.insert(
          examDate: examDate,
          title: 'Day 20: International Affairs',
          topicsCovered: 'League of Nations & UN',
          trackName: const Value('52nd BCS 135-Day'),
        ),
        ExamSchedulesCompanion.insert(
          examDate: examDate.add(const Duration(days: 2)),
          title: 'Day 21: ICT & Computer',
          topicsCovered: 'Computer Architecture',
          trackName: const Value('52nd BCS 135-Day'),
        ),
      ];

      // First insertion (new exams)
      final result1 = await db.insertExamSchedulesDeduplicated(companions);
      expect(result1.totalParsed, equals(2));
      expect(result1.insertedCount, equals(2));
      expect(result1.skippedCount, equals(0));
      expect(result1.allDuplicates, isFalse);
      expect(result1.isAllNew, isTrue);

      // Second insertion of identical exams (accidentally uploaded same routine twice)
      final result2 = await db.insertExamSchedulesDeduplicated(companions);
      expect(result2.totalParsed, equals(2));
      expect(result2.insertedCount, equals(0));
      expect(result2.skippedCount, equals(2));
      expect(result2.allDuplicates, isTrue);
      expect(
        result2.toBengaliMessage(),
        contains('ইতোমধ্যে আপনার তালিকায় যুক্ত রয়েছে'),
      );

      // Total count in DB should still be exactly 2, not 4
      final exams = await (db.select(
        db.examSchedules,
      )..where((t) => t.trackName.equals('52nd BCS 135-Day'))).get();
      expect(
        exams
            .where(
              (e) => e.title.contains('Day 20') || e.title.contains('Day 21'),
            )
            .length,
        equals(2),
      );
    });

    test(
      'Deduplication keeps distinct same-subject exams on the same day',
      () async {
        final date = DateTime(2026, 11, 15);
        final result = await db.insertExamSchedulesDeduplicated([
          ExamSchedulesCompanion.insert(
            title: 'Bangla Daily Exam 01',
            examDate: date,
            topicsCovered: 'কারক ও বিভক্তি',
            subject: const Value('Bangla'),
            trackName: const Value('52nd BCS'),
          ),
          ExamSchedulesCompanion.insert(
            title: 'Bangla Daily Exam 02',
            examDate: date,
            topicsCovered: 'সমাস ও সন্ধি',
            subject: const Value('Bangla'),
            trackName: const Value('52nd BCS'),
          ),
        ]);

        expect(result.insertedCount, 2);
        final saved = await db.select(db.examSchedules).get();
        expect(saved.where((e) => e.examDate == date).length, 2);
      },
    );

    test(
      'Deduplication keeps two sittings of the same exam at different times',
      () async {
        // The hard case: the routine gives no distinct title, so both rows
        // generate the same one, and both cover the same syllabus line. Only
        // the hour tells them apart.
        final date = DateTime(2026, 11, 2);
        ExamSchedulesCompanion sitting(String time) =>
            ExamSchedulesCompanion.insert(
              title: 'Bangla Grammar Daily Exam',
              examDate: date,
              examTime: Value(time),
              topicsCovered: 'General Syllabus',
              subject: const Value('Bangla Grammar'),
              examType: const Value('Daily'),
              trackName: const Value('52nd BCS'),
            );

        final result = await db.insertExamSchedulesDeduplicated([
          sitting('10:00 AM'),
          sitting('10:00 PM'),
        ]);

        expect(result.insertedCount, 2);
        final saved = await (db.select(
          db.examSchedules,
        )..where((t) => t.trackName.equals('52nd BCS'))).get();
        expect(saved.where((e) => e.examDate == date).length, 2);
      },
    );

    test(
      'Deduplication still skips a genuine re-import of the same sitting',
      () async {
        final date = DateTime(2026, 11, 3);
        ExamSchedulesCompanion sitting() => ExamSchedulesCompanion.insert(
          title: 'Bangla Grammar Daily Exam',
          examDate: date,
          examTime: const Value('10:00 PM'),
          topicsCovered: 'General Syllabus',
          subject: const Value('Bangla Grammar'),
          examType: const Value('Daily'),
          trackName: const Value('52nd BCS'),
        );

        await db.insertExamSchedulesDeduplicated([sitting()]);
        final again = await db.insertExamSchedulesDeduplicated([sitting()]);

        expect(again.insertedCount, 0);
        expect(again.skippedCount, 1);
      },
    );

    test('Deduplication: Preserves completedStatus and score when re-importing updated routines', () async {
      final date = DateTime(2026, 11, 20);
      final id = await db.insertExamSchedule(
        ExamSchedulesCompanion.insert(
          examDate: date,
          title: 'Day 25: Bangla Literature',
          topicsCovered: 'Modern Era',
          trackName: const Value('52nd BCS 135-Day'),
        ),
      );

      // User marks this exam completed with score
      final exam = (await db.select(db.examSchedules).get()).firstWhere(
        (e) => e.id == id,
      );
      await db.updateExamSchedule(
        exam.copyWith(completedStatus: true, score: const Value(18.5)),
      );

      // Now user re-imports PDF with richer topics
      final updateCompanion = [
        ExamSchedulesCompanion.insert(
          examDate: date,
          title: 'Day 25: Bangla Literature',
          topicsCovered:
              'Modern Era: Rabindranath, Nazrul & Jibanananda Das (Expanded)',
          trackName: const Value('52nd BCS 135-Day'),
        ),
      ];

      final result = await db.insertExamSchedulesDeduplicated(updateCompanion);
      expect(result.updatedCount, equals(1));
      expect(result.insertedCount, equals(0));

      final updatedExam = (await db.select(db.examSchedules).get()).firstWhere(
        (e) => e.id == id,
      );
      expect(updatedExam.completedStatus, isTrue);
      expect(updatedExam.score, equals(18.5));
      expect(updatedExam.topicsCovered, contains('Expanded'));
    });

    test('Can log daily post-work energy and retrieve today’s log', () async {
      final now = DateTime.now();
      await db.insertOrUpdateDailyLog(
        DailyEnergyLogsCompanion.insert(
          date: now,
          energyLevel: EnergyLevel.low,
          officeFatigueScore: const Value(9),
          notes: const Value('Long debug session at work, drained.'),
        ),
      );

      final todayLog = await db.getTodayLog(now);
      expect(todayLog, isNotNull);
      expect(todayLog!.energyLevel, equals(EnergyLevel.low));
      expect(todayLog.officeFatigueScore, equals(9));
      expect(todayLog.notes, contains('Long debug session'));
    });

    test(
      'Can store and retrieve app settings (Office Wi-Fi, Dinner hour)',
      () async {
        await db.setSetting('office_wifi_ssid', 'Google-Office-5G');
        final ssid = await db.getSetting('office_wifi_ssid');
        expect(ssid, equals('Google-Office-5G'));
      },
    );
  });

  group('Adaptive AI Planner Logic Tests', () {
    test(
      'Low energy / high fatigue generates micro-commitment <= 15 mins',
      () async {
        final weakTopic = WeakTopic(
          id: 1,
          subject: 'Bangla Grammar',
          topicName: 'কারক ও বিভক্তি',
          proficiencyLevel: ProficiencyLevel.weak,
          createdAt: DateTime.now(),
        );

        final plan = await GeminiAiService.instance.generateAdaptivePlan(
          energyLevel: 'Low',
          fatigueScore: 8,
          weakTopics: [weakTopic],
          upcomingExams: [],
        );

        expect(plan.energyLevel, equals('Low'));
        expect(plan.recommendedStudyMinutes, lessThanOrEqualTo(15));
        expect(plan.recommendedFamilyMinutes, greaterThanOrEqualTo(60));
        expect(plan.tasks.length, equals(1));
        expect(plan.tasks.first.estimatedMinutes, lessThanOrEqualTo(15));
        expect(plan.burnoutWarning, isNotNull);
      },
    );

    test(
      'High energy generates expanded drill with higher study minutes',
      () async {
        final weakTopic = WeakTopic(
          id: 1,
          subject: 'Mathematics',
          topicName: 'শতকরা ও লাভ-ক্ষতি',
          proficiencyLevel: ProficiencyLevel.weak,
          createdAt: DateTime.now(),
        );

        final plan = await GeminiAiService.instance.generateAdaptivePlan(
          energyLevel: 'High',
          fatigueScore: 2,
          weakTopics: [weakTopic],
          upcomingExams: [],
        );

        expect(plan.energyLevel, equals('High'));
        expect(plan.recommendedStudyMinutes, greaterThanOrEqualTo(30));
      },
    );

    test(
      'Off-day (Thursday/Friday) generates deep-study and mock test routine',
      () async {
        final weakTopic = WeakTopic(
          id: 1,
          subject: 'Bangla Grammar',
          topicName: 'সমাস ও প্রত্যয়',
          proficiencyLevel: ProficiencyLevel.weak,
          createdAt: DateTime.now(),
        );

        final plan = await GeminiAiService.instance.generateAdaptivePlan(
          energyLevel: 'Moderate',
          fatigueScore: 4,
          weakTopics: [weakTopic],
          upcomingExams: [],
          isOffDay: true,
        );

        expect(plan.energyLevel, equals('Weekend/Off-Day'));
        expect(plan.recommendedStudyMinutes, greaterThanOrEqualTo(60));
        expect(plan.tasks.any((t) => t.taskType == 'mock_test'), isTrue);
      },
    );

    test(
      'WifiMonitorService correctly identifies Thursday and Friday as off-days',
      () {
        final thursday = DateTime(2026, 10, 29); // 2026-10-29 is Thursday
        final friday = DateTime(2026, 10, 30); // 2026-10-30 is Friday
        final saturday = DateTime(2026, 10, 31); // 2026-10-31 is Saturday
        final sunday = DateTime(2026, 11, 1); // 2026-11-01 is Sunday

        expect(WifiMonitorService.isOffDay(thursday), isTrue);
        expect(WifiMonitorService.isOffDay(friday), isTrue);
        expect(WifiMonitorService.isOffDay(saturday), isFalse);
        expect(WifiMonitorService.isOffDay(sunday), isFalse);
      },
    );
  });
}
