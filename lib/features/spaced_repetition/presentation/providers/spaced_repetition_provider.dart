import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../core/services/flashcards/flashcard_service.dart';
import '../../../../core/services/notification/notification_service.dart';

final allSpacedReviewsStreamProvider = StreamProvider<List<SpacedReviewItem>>((
  ref,
) {
  final db = ref.watch(appDatabaseProvider);
  return db.watchAllSpacedReviewItems();
});

final dueSpacedReviewsStreamProvider = StreamProvider<List<SpacedReviewItem>>((
  ref,
) {
  final db = ref.watch(appDatabaseProvider);
  return db.watchDueSpacedReviewItems();
});

class SpacedRepetitionNotifier extends Notifier<void> {
  @override
  void build() {}

  AppDatabase get _db => ref.read(appDatabaseProvider);

  Future<bool> advanceReview(int id) async {
    return _db.advanceSpacedReview(id);
  }

  Future<bool> resetReview(int id) async {
    return _db.resetSpacedReview(id);
  }

  Future<int> addRule({
    required String subject,
    required String topic,
    required String title,
    required String keyRule,
    int initialIntervalDays = 1,
  }) async {
    final now = DateTime.now();
    return _db.insertSpacedReviewItem(
      SpacedReviewItemsCompanion.insert(
        subject: subject,
        topic: topic,
        title: title,
        keyRule: keyRule,
        repetitionLevel: const Value(1),
        intervalDays: Value(initialIntervalDays),
        nextReviewDate: now.add(Duration(days: initialIntervalDays)),
      ),
    );
  }

  Future<int> deleteRule(int id) async {
    return _db.deleteSpacedReviewItem(id);
  }

  /// Sends a 5-second quick office flashcard notification immediately
  Future<void> triggerOfficeFlashcardNotification({
    String? preferredSubject,
  }) async {
    final card = await FlashcardService.instance.getFlashcard(
      db: _db,
      preferredSubject: preferredSubject,
    );

    await NotificationService.instance.showOfficeMicroFlashcard(
      subject: card.subject,
      title: card.title,
      content: card.content,
      mnemonic: card.mnemonic,
    );
  }

  /// Sends a push reminder for the top due spaced review item
  Future<bool> triggerDueReviewNotification() async {
    final due = await _db.getDueSpacedReviewItems();
    if (due.isEmpty) return false;

    final item = due.first;
    await NotificationService.instance.showSpacedReviewNotification(
      itemId: item.id,
      subject: item.subject,
      topic: item.topic,
      title: item.title,
      keyRule: item.keyRule,
      intervalDays: item.intervalDays,
    );
    return true;
  }
}

final spacedRepetitionNotifierProvider =
    NotifierProvider<SpacedRepetitionNotifier, void>(() {
      return SpacedRepetitionNotifier();
    });
