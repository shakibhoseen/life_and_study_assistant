import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/notification_constants.dart';

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) async {
  await handleNotificationResponse(response);
}

Future<void> handleNotificationResponse(NotificationResponse response) async {
  final prefs = await SharedPreferences.getInstance();
  final actionId = response.actionId;
  final todayIso = DateTime.now().toIso8601String().substring(0, 10);

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
