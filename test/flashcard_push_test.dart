import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/services/flashcards/flashcard_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('Flashcard batch for the scheduled push', () {
    test('asking for nothing returns nothing', () async {
      expect(
        await FlashcardService.instance.getFlashcardBatch(db: db, count: 0),
        isEmpty,
      );
    });

    test('a batch has no repeats', () async {
      final batch = await FlashcardService.instance.getFlashcardBatch(
        db: db,
        count: 8,
      );

      // The same card arriving three times in an afternoon is noise.
      final titles = batch.map((c) => c.title).toSet();
      expect(titles.length, batch.length);
    });

    test('the batch is filled up to the count asked for', () async {
      final batch = await FlashcardService.instance.getFlashcardBatch(
        db: db,
        count: 5,
      );

      expect(batch, hasLength(5));
      expect(batch.every((c) => c.title.isNotEmpty), isTrue);
      expect(batch.every((c) => c.content.isNotEmpty), isTrue);
    });

    test('asking for more than the deck holds does not loop', () async {
      final batch = await FlashcardService.instance.getFlashcardBatch(
        db: db,
        count: 1000,
      );

      final titles = batch.map((c) => c.title).toSet();
      expect(titles.length, batch.length);
      expect(batch.length, lessThan(1000));
    });

    test('due review items are preferred over the curated deck', () async {
      await db
          .into(db.spacedReviewItems)
          .insert(
            SpacedReviewItemsCompanion.insert(
              subject: 'বাংলা ব্যাকরণ',
              topic: 'কারক',
              title: 'কারক চেনার কৌশল',
              keyRule: 'ক্রিয়ার সাথে সম্পর্ক দেখে কারক নির্ণয় করুন।',
              nextReviewDate: DateTime.now().subtract(const Duration(days: 1)),
            ),
          );

      final batch = await FlashcardService.instance.getFlashcardBatch(
        db: db,
        count: 4,
      );

      expect(batch.first.title, 'কারক চেনার কৌশল');
      expect(batch.first.tag, 'SpacedReview');
    });

    test('works without a database at all', () async {
      final batch = await FlashcardService.instance.getFlashcardBatch(count: 3);

      expect(batch, hasLength(3));
    });
  });
}
