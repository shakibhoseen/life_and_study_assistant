import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/config/notification_constants.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Answering a card from the notification has to reach the schedule.
///
/// The buttons dismiss the notification whatever happens, so an answer that
/// goes nowhere is invisible: the card simply comes round again on the same
/// schedule, and nothing says why.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => db.close());

  Future<int> addDueCard() => db.insertSpacedReviewItem(
    SpacedReviewItemsCompanion.insert(
      subject: 'বাংলা',
      topic: 'সমাস',
      title: 'দ্বিগু সমাস',
      keyRule: 'সংখ্যাবাচক শব্দ পূর্বে বসে',
      nextReviewDate: DateTime.now(),
    ),
  );

  Future<SpacedReviewItem> read(int id) => (db.select(
    db.spacedReviewItems,
  )..where((t) => t.id.equals(id))).getSingle();

  test(
    '"remembered" from a notification pushes the card further out',
    () async {
      final id = await addDueCard();
      final before = await read(id);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        NotificationConstants.prefPendingReviewAdvanceIds,
        ['$id'],
      );
      await db.advanceSpacedReview(id);

      final after = await read(id);
      expect(after.intervalDays, greaterThan(before.intervalDays));
    },
  );

  test('"forgot" from a notification brings the card back tomorrow', () async {
    final id = await addDueCard();
    await db.advanceSpacedReview(id);
    await db.advanceSpacedReview(id);
    final stretched = await read(id);
    expect(stretched.intervalDays, greaterThan(1));

    await db.resetSpacedReview(id);

    final after = await read(id);
    expect(after.intervalDays, 1);
  });

  test('the reset key exists for the forgot buttons to queue into', () {
    // Both forgot buttons used to write a key nothing read. This holds the
    // two apart so they cannot collapse back into one.
    expect(
      NotificationConstants.prefPendingReviewResetIds,
      isNot(NotificationConstants.prefPendingReviewAdvanceIds),
    );
  });
}
