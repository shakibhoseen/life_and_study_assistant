import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/notification_constants.dart';
import '../flashcards/flashcard_service.dart';
import 'notification_service.dart';

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) async {
  await handleNotificationResponse(response);
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
  } else if (actionId == NotificationConstants.actionCheckInDone) {
    await prefs.setString(
      NotificationConstants.prefLastCheckInStatus,
      'Punched In',
    );
    await prefs.setString(NotificationConstants.prefLastCheckInDate, todayIso);
  } else if (actionId == NotificationConstants.actionCheckOutDone) {
    await prefs.setString(NotificationConstants.prefLastCheckOutDate, todayIso);
  } else if (actionId == NotificationConstants.actionFlashcardGotIt) {
    await prefs.setString('last_flashcard_reviewed_date', todayIso);

    // "Got it" used to leave only a date behind, so a card the user had
    // actually recalled came round again on the same schedule. Where the card
    // came from the review list, queue it to be advanced; the action can
    // arrive in a background isolate, so the app applies it when it next runs.
    final card = FlashcardItem.tryFromPayload(response.payload);
    if (card?.reviewItemId != null) {
      final pending =
          prefs.getStringList(
            NotificationConstants.prefPendingReviewAdvanceIds,
          ) ??
          <String>[];
      final id = '${card!.reviewItemId}';
      if (!pending.contains(id)) {
        pending.add(id);
        await prefs.setStringList(
          NotificationConstants.prefPendingReviewAdvanceIds,
          pending,
        );
      }
    }
  } else if (actionId == NotificationConstants.actionSpacedRemembered) {
    final payloadId = int.tryParse(response.payload ?? '');
    if (payloadId != null) {
      await prefs.setString('last_spaced_advanced_id', '$payloadId');
    }
  } else if (actionId == NotificationConstants.actionSpacedForgot) {
    final payloadId = int.tryParse(response.payload ?? '');
    if (payloadId != null) {
      await prefs.setString('last_spaced_reset_id', '$payloadId');
    }
  }
}
