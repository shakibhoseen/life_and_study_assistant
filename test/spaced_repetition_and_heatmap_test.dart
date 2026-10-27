import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/database/tables/daily_energy_logs_table.dart';
import 'package:life_and_study_assistant/core/database/tables/weak_topics_table.dart';
import 'package:life_and_study_assistant/core/services/flashcards/flashcard_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('Spaced Repetition (Ebbinghaus Curve) Algorithm Tests', () {
    test(
      'Can insert, advance through SM-2 intervals, and achieve mastery',
      () async {
        final now = DateTime.now();

        final itemId = await db.insertSpacedReviewItem(
          SpacedReviewItemsCompanion.insert(
            subject: 'Bangla Grammar',
            topic: 'কারক ও বিভক্তি',
            title: 'অপাদান কারক চেনার শর্টকাট',
            keyRule: 'উৎপন্ন, বিচ্যুত, ভীত হলে অপাদান (তিলে তৈল হয়)।',
            repetitionLevel: const Value(1),
            intervalDays: const Value(1),
            nextReviewDate: now.subtract(const Duration(minutes: 5)), // Due now
          ),
        );

        expect(itemId, isPositive);

        // Verify it is due for review
        var due = await db.getDueSpacedReviewItems();
        expect(due.length, equals(1));
        expect(due.first.id, equals(itemId));
        expect(due.first.repetitionLevel, equals(1));

        // Advance: Level 1 (1d) -> Level 2 (3d)
        await db.advanceSpacedReview(itemId);
        var all = await db.watchAllSpacedReviewItems().first;
        var item = all.firstWhere((i) => i.id == itemId);
        expect(item.repetitionLevel, equals(2));
        expect(item.intervalDays, equals(3));
        expect(item.isMastered, isFalse);

        // Advance: Level 2 (3d) -> Level 3 (7d)
        await db.advanceSpacedReview(itemId);
        all = await db.watchAllSpacedReviewItems().first;
        item = all.firstWhere((i) => i.id == itemId);
        expect(item.repetitionLevel, equals(3));
        expect(item.intervalDays, equals(7));

        // Advance: Level 3 (7d) -> Level 4 (14d)
        await db.advanceSpacedReview(itemId);
        all = await db.watchAllSpacedReviewItems().first;
        item = all.firstWhere((i) => i.id == itemId);
        expect(item.repetitionLevel, equals(4));
        expect(item.intervalDays, equals(14));

        // Advance: Level 4 (14d) -> Level 5 (30d)
        await db.advanceSpacedReview(itemId);
        all = await db.watchAllSpacedReviewItems().first;
        item = all.firstWhere((i) => i.id == itemId);
        expect(item.repetitionLevel, equals(5));
        expect(item.intervalDays, equals(30));

        // Advance: Level 5 -> Mastered!
        await db.advanceSpacedReview(itemId);
        all = await db.watchAllSpacedReviewItems().first;
        item = all.firstWhere((i) => i.id == itemId);
        expect(item.isMastered, isTrue);

        // Mastered item should not be in due reviews even if nextReviewDate passes
        due = await db.getDueSpacedReviewItems();
        expect(due.any((i) => i.id == itemId), isFalse);
      },
    );

    test(
      'Resetting review drops interval back to 1 day for reinforcement',
      () async {
        final itemId = await db.insertSpacedReviewItem(
          SpacedReviewItemsCompanion.insert(
            subject: 'Mathematics',
            topic: 'লাভ-ক্ষতি',
            title: 'ক্রয়মূল্য সূত্র',
            keyRule: 'ক্রয়মূল্য = (বিক্রয়মূল্য × ১০০) ÷ (১০০ + r)',
            repetitionLevel: const Value(4),
            intervalDays: const Value(14),
            nextReviewDate: DateTime.now(),
          ),
        );

        // User forgot: Reset
        await db.resetSpacedReview(itemId);

        final all = await db.watchAllSpacedReviewItems().first;
        final item = all.firstWhere((i) => i.id == itemId);
        expect(item.repetitionLevel, equals(1));
        expect(item.intervalDays, equals(1));
        expect(item.isMastered, isFalse);
      },
    );
  });

  group('GitHub-Style Study Activity Heatmap & Subject Analytics Tests', () {
    test('getActivityHeatmapData aggregates daily scores, active days, and streak', () async {
      final now = DateTime.now();

      // Day 1: Today - 2 drills + 1 energy log
      await db.insertDrillRecord(
        DrillRecordsCompanion.insert(
          subject: 'Bangla Grammar',
          topic: 'সমাস',
          totalQuestions: 5,
          correctCount: 4,
          incorrectCount: 1,
          scorePercentage: 80.0,
        ),
      );
      await db.insertOrUpdateDailyLog(
        DailyEnergyLogsCompanion.insert(
          date: now,
          energyLevel: EnergyLevel.high,
          officeFatigueScore: const Value(3),
        ),
      );

      // Day 2: Yesterday - 1 drill
      final yesterday = now.subtract(const Duration(days: 1));
      await db.insertDrillRecord(
        DrillRecordsCompanion.insert(
          subject: 'Mathematics',
          topic: 'শতকরা',
          totalQuestions: 5,
          correctCount: 5,
          incorrectCount: 0,
          scorePercentage: 100.0,
          createdAt: Value(yesterday),
        ),
      );

      final heatmap = await db.getActivityHeatmapData(daysBack: 14);

      expect(heatmap['activeDays'], inInclusiveRange(2, 14));
      expect(heatmap['currentStreak'], inInclusiveRange(1, 14));

      final scores = heatmap['scores'] as Map<String, int>;
      final todayKey =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      expect(scores[todayKey], isPositive);
    });

    test(
      'getSubjectStudyDistribution calculates percentage allocation accurately',
      () async {
        await db.insertWeakTopic(
          WeakTopicsCompanion.insert(
            subject: 'Bangla Grammar',
            topicName: 'কারক ও বিভক্তি',
            proficiencyLevel: ProficiencyLevel.weak,
          ),
        );

        await db.insertWeakTopic(
          WeakTopicsCompanion.insert(
            subject: 'Mathematics',
            topicName: 'শতকরা',
            proficiencyLevel: ProficiencyLevel.weak,
          ),
        );

        final dist = await db.getSubjectStudyDistribution();
        expect(dist.isNotEmpty, isTrue);
        expect(dist.every((d) => (d['percentage'] as num) > 0), isTrue);
      },
    );
  });

  group('Flashcard Service Tests', () {
    test(
      'FlashcardService returns curated and subject-filtered flashcards',
      () async {
        final card = await FlashcardService.instance.getFlashcard(
          preferredSubject: 'English',
        );
        expect(card.subject.contains('English'), isTrue);
        expect(card.title.isNotEmpty, isTrue);
        expect(card.content.isNotEmpty, isTrue);
      },
    );
  });
}
