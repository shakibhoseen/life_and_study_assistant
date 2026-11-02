import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../core/services/flashcards/flashcard_service.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/config/notification_constants.dart';

import 'package:flutter/foundation.dart';

import '../../../../core/services/notification/notification_service.dart';
import '../../../../core/services/flashcards/push_queue_depth.dart';

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

  Future<bool> editItem({
    required int id,
    required String title,
    required String keyRule,
  }) {
    return _db.updateSpacedReviewItem(id: id, title: title, keyRule: keyRule);
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

  /// Applies the "মনে থাকবে" taps that arrived while the app was not running.
  ///
  /// The notification action can land in a background isolate, which has no
  /// database of its own, so it only records the id and this drains the list.
  /// Applies what the user answered on a notification while the app was shut.
  ///
  /// Both answers are applied, not just "remembered". The forgot buttons used
  /// to write a key nothing ever read, so the notification dismissed, the user
  /// believed they had graded the card, and its schedule never moved.
  Future<int> applyPendingReviewAdvances() async {
    final prefs = await SharedPreferences.getInstance();
    final advance =
        prefs.getStringList(
          NotificationConstants.prefPendingReviewAdvanceIds,
        ) ??
        const <String>[];
    final reset =
        prefs.getStringList(NotificationConstants.prefPendingReviewResetIds) ??
        const <String>[];
    if (advance.isEmpty && reset.isEmpty) return 0;

    var applied = 0;
    // Reset first: a card answered both ways before the app reopened was
    // forgotten at some point, and that is the answer worth keeping.
    for (final raw in reset) {
      final id = int.tryParse(raw);
      if (id == null) continue;
      try {
        if (await _db.resetSpacedReview(id)) applied++;
      } catch (e) {
        debugPrint('Could not reset review $id: $e');
      }
    }
    for (final raw in advance) {
      final id = int.tryParse(raw);
      if (id == null || reset.contains(raw)) continue;
      try {
        if (await _db.advanceSpacedReview(id)) applied++;
      } catch (e) {
        debugPrint('Could not advance review $id: $e');
      }
    }

    await prefs.remove(NotificationConstants.prefPendingReviewAdvanceIds);
    await prefs.remove(NotificationConstants.prefPendingReviewResetIds);
    debugPrint('Applied $applied pending review answers');
    return applied;
  }

  DateTime? _lastScheduleRefresh;
  bool _refreshInFlight = false;

  /// How close together two refreshes have to be before the second is
  /// pointless. Resume fires more than once on a single return to the app,
  /// and each refresh cancels and re-books twelve notifications.
  static const Duration _refreshCooldown = Duration(seconds: 30);

  /// Rebuilds the queue of scheduled flashcard pushes.
  ///
  /// Called whenever the app opens and whenever the setting changes, because
  /// the queue is finite by design: it holds a day's worth and is topped up
  /// on the next launch.
  Future<void> refreshFlashcardSchedule({bool force = false}) async {
    if (_refreshInFlight) return;
    final last = _lastScheduleRefresh;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < _refreshCooldown) {
      return;
    }
    _refreshInFlight = true;

    try {
      await _refreshFlashcardSchedule();
      _lastScheduleRefresh = DateTime.now();
    } finally {
      _refreshInFlight = false;
    }
  }

  Future<void> _refreshFlashcardSchedule() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled =
        prefs.getBool(NotificationConstants.prefFlashcardPushEnabled) ?? false;

    if (!enabled) {
      await NotificationService.instance.cancelFlashcardSeries();
      debugPrint('Flashcard push: disabled, queue cleared');
      return;
    }

    final minutes =
        prefs.getInt(NotificationConstants.prefFlashcardPushIntervalMinutes) ??
        60;

    final startHour =
        prefs.getInt(NotificationConstants.prefFlashcardPushStartHour) ??
        NotificationConstants.flashcardPushDefaultStartHour;
    final endHour =
        prefs.getInt(NotificationConstants.prefFlashcardPushEndHour) ??
        NotificationConstants.flashcardPushDefaultEndHour;

    // The queue is only rebuilt when the app is opened, so it has to outlast
    // a few days of not opening it. A fixed twelve covered about one day at
    // hourly pushes, after which the pushes simply stopped.
    final depth = flashcardQueueDepth(
      startHour: startHour,
      endHour: endHour,
      intervalMinutes: minutes,
    );

    final cards = await FlashcardService.instance.getFlashcardBatch(
      db: _db,
      count: depth,
    );

    final queued = await NotificationService.instance.scheduleFlashcardSeries(
      cards: cards,
      interval: Duration(minutes: minutes),
      startHour: startHour,
      endHour: endHour,
    );

    // Kept so Settings can say how long the queue lasts: fewer cards than
    // slots means the pushes stop sooner than the user would guess.
    final perDay = flashcardQueueDepth(
      startHour: startHour,
      endHour: endHour,
      intervalMinutes: minutes,
      daysOfCover: 1,
    );
    await prefs.setInt(NotificationConstants.prefFlashcardQueuedCount, queued);
    await prefs.setInt(NotificationConstants.prefFlashcardSlotsPerDay, perDay);
  }

  /// Queues a few cards a minute apart so the feature can be seen working.
  ///
  /// Replaces the real queue, so the next app launch rebuilds the normal one.
  Future<int> scheduleFlashcardTestBurst({int count = 3}) async {
    final cards = await FlashcardService.instance.getFlashcardBatch(
      db: _db,
      count: count,
    );

    await NotificationService.instance.scheduleFlashcardSeries(
      cards: cards,
      interval: const Duration(minutes: 1),
      ignoreQuietHours: true,
    );
    // The burst replaced the real queue, so the next refresh has work to do
    // however recently one ran.
    _lastScheduleRefresh = null;
    return cards.length;
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
