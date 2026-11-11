import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/notification_constants.dart';
import '../attendance/packly_attendance_service.dart';
import '../attendance/steadfast_lunch_service.dart';
import '../flashcards/flashcard_service.dart';
import 'notification_service.dart';

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) async {
  await handleNotificationResponse(response);
}

/// Remembers an id until the app can act on it.
///
/// A notification button can arrive in a background isolate, where the
/// database is not open, so the work is queued rather than attempted here.
Future<void> _queueReviewId(
  SharedPreferences prefs,
  String key,
  int reviewId,
) async {
  final pending = prefs.getStringList(key) ?? <String>[];
  final id = '$reviewId';
  if (pending.contains(id)) return;
  pending.add(id);
  await prefs.setStringList(key, pending);
}

Future<void> handleNotificationResponse(NotificationResponse response) async {
  final prefs = await SharedPreferences.getInstance();
  final actionId = response.actionId;
  final todayIso = DateTime.now().toIso8601String().substring(0, 10);

  // A plain tap carries no action id. It used to fall through every branch
  // and do nothing but open the app on whatever screen was last shown.
  if (actionId == null || actionId.isEmpty) {
    final card = FlashcardItem.tryFromPayload(response.payload);
    if (card != null) NotificationService.instance.publishTappedFlashcard(card);
    return;
  }

  if (actionId == NotificationConstants.actionMealYes) {
    await prefs.setString(
      NotificationConstants.prefLastMealResponse,
      'Yes, Count Me In',
    );
    await prefs.setString(
      NotificationConstants.prefLastMealResponseDate,
      todayIso,
    );
  } else if (actionId == NotificationConstants.actionMealNo) {
    await prefs.setString(
      NotificationConstants.prefLastMealResponse,
      'No, Skip',
    );
    await prefs.setString(
      NotificationConstants.prefLastMealResponseDate,
      todayIso,
    );
  } else if (actionId == NotificationConstants.actionLunchToggleTomorrow) {
    await SteadfastLunchService.instance.toggleTomorrowMeal();
  } else if (actionId == NotificationConstants.actionCheckInNow) {
    final result = await PacklyAttendanceService.instance.checkIn();
    if (result.success) {
      final now = DateTime.now();
      final timeStr =
          '${(now.hour % 12 == 0 ? 12 : now.hour % 12).toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} ${now.hour >= 12 ? 'PM' : 'AM'}';
      final isLate = (now.hour > 9) || (now.hour == 9 && now.minute >= 15);
      await NotificationService.instance.showOfficeCheckInSuccessNotification(
        time: timeStr,
        isLate: isLate,
      );
    }
  } else if (actionId == NotificationConstants.actionCheckInDone) {
    await prefs.setString(
      NotificationConstants.prefLastCheckInStatus,
      'Punched In',
    );
    await prefs.setString(NotificationConstants.prefLastCheckInDate, todayIso);
  } else if (actionId == NotificationConstants.actionCheckOutNow) {
    final result = await PacklyAttendanceService.instance.checkOut();
    if (result.success) {
      final now = DateTime.now();
      final timeStr =
          '${(now.hour % 12 == 0 ? 12 : now.hour % 12).toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} ${now.hour >= 12 ? 'PM' : 'AM'}';
      await NotificationService.instance.showOfficeCheckOutSuccessNotification(
        time: timeStr,
      );
      await NotificationService.instance.cancelCheckOutReminder();
      await FlutterForegroundTask.stopService();
    }
  } else if (actionId == NotificationConstants.actionCheckOutDone) {
    await prefs.setString(NotificationConstants.prefLastCheckOutDate, todayIso);
    await NotificationService.instance.cancelCheckOutReminder();
    await FlutterForegroundTask.stopService();
  } else if (actionId == NotificationConstants.actionFlashcardGotIt) {
    await prefs.setString('last_flashcard_reviewed_date', todayIso);

    // "Got it" used to leave only a date behind, so a card the user had
    // actually recalled came round again on the same schedule. Where the card
    // came from the review list, queue it to be advanced; the action can
    // arrive in a background isolate, so the app applies it when it next runs.
    final card = FlashcardItem.tryFromPayload(response.payload);
    if (card?.reviewItemId != null) {
      await _queueReviewId(
        prefs,
        NotificationConstants.prefPendingReviewAdvanceIds,
        card!.reviewItemId!,
      );
    }
  } else if (actionId == NotificationConstants.actionFlashcardForgot) {
    // Forgetting is the signal the schedule needs most, and until now the
    // only way to give it was to open the app and find the card.
    final card = FlashcardItem.tryFromPayload(response.payload);
    if (card?.reviewItemId != null) {
      await _queueReviewId(
        prefs,
        NotificationConstants.prefPendingReviewResetIds,
        card!.reviewItemId!,
      );
    }
  } else if (actionId == NotificationConstants.actionSpacedRemembered) {
    // These two used to write a key nothing ever read: the notification
    // dismissed, the user believed they had graded the card, and its
    // schedule never moved.
    final payloadId = int.tryParse(response.payload ?? '');
    if (payloadId != null) {
      await _queueReviewId(
        prefs,
        NotificationConstants.prefPendingReviewAdvanceIds,
        payloadId,
      );
    }
  } else if (actionId == NotificationConstants.actionSpacedForgot) {
    final payloadId = int.tryParse(response.payload ?? '');
    if (payloadId != null) {
      await _queueReviewId(
        prefs,
        NotificationConstants.prefPendingReviewResetIds,
        payloadId,
      );
    }
  }
}
