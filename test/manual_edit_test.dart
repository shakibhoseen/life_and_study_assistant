import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('editing a flashcard by hand', () {
    Future<int> addCard() => db.insertSpacedReviewItem(
      SpacedReviewItemsCompanion.insert(
        subject: 'সাধারণ বিজ্ঞান',
        topic: 'রক্তসংবহন',
        title: 'হৃদপিণ্ডে কয়টি প্রকোষ্ঠ?',
        keyRule: '৩টি',
        nextReviewDate: DateTime.now(),
      ),
    );

    test('a wrong fact can be corrected without losing the card', () async {
      final id = await addCard();

      final changed = await db.updateSpacedReviewItem(
        id: id,
        keyRule: '৪টি — ২ অলিন্দ, ২ নিলয়',
      );

      expect(changed, isTrue);
      final card = await (db.select(
        db.spacedReviewItems,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(card.keyRule, '৪টি — ২ অলিন্দ, ২ নিলয়');
      // The front is untouched when only the back was edited.
      expect(card.title, 'হৃদপিণ্ডে কয়টি প্রকোষ্ঠ?');
    });

    test('the schedule survives an edit', () async {
      final id = await addCard();
      await db.advanceSpacedReview(id);
      final before = await (db.select(
        db.spacedReviewItems,
      )..where((t) => t.id.equals(id))).getSingle();

      await db.updateSpacedReviewItem(id: id, title: 'নতুন প্রশ্ন');

      final after = await (db.select(
        db.spacedReviewItems,
      )..where((t) => t.id.equals(id))).getSingle();
      // Rewording a card is not the same as having forgotten it.
      expect(after.intervalDays, before.intervalDays);
      expect(after.nextReviewDate, before.nextReviewDate);
    });

    test('surrounding spaces are trimmed off', () async {
      final id = await addCard();
      await db.updateSpacedReviewItem(id: id, title: '  ফাঁকা সহ  ');

      final card = await (db.select(
        db.spacedReviewItems,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(card.title, 'ফাঁকা সহ');
    });

    test('editing a card that is gone changes nothing', () async {
      expect(await db.updateSpacedReviewItem(id: 9999, title: 'x'), isFalse);
    });
  });
}
