class NotificationConstants {
  // Notification Channels
  static const String officeChannelId = 'office_triggers_channel';
  static const String officeChannelName = 'Office Attendance & Wi-Fi Alerts';
  static const String officeChannelDesc =
      'High priority heads-up reminders for biometric check-in and check-out based on Wi-Fi/Geofence.';

  static const String mealChannelId = 'meal_reminders_channel';
  static const String mealChannelName = 'Office Meal / Dinner Cutoff';
  static const String mealChannelDesc =
      'Daily scheduled cutoff reminders with action buttons to confirm dinner.';

  static const String studyChannelId = 'study_nudges_channel';
  static const String studyChannelName = 'AI Study Nudges & Micro-Commitments';
  static const String studyChannelDesc =
      'Adaptive study reminders tailored to your daily energy levels and LiveMCQ schedule.';

  /// Version suffix because an Android channel is immutable once created.
  ///
  /// The first version was registered silent, for glancing at while coding,
  /// and no code change can give an existing channel a sound — only a new
  /// channel id can. The old one is deleted on startup so it does not linger
  /// in the system notification settings.
  static const String flashcardChannelId = 'office_flashcards_channel_v2';
  static const String flashcardChannelIdLegacy = 'office_flashcards_channel';
  static const String flashcardChannelName = 'Office Micro-Flashcards & Vocab';
  static const String flashcardChannelDesc =
      'Timed flashcard and vocabulary nudges for revision.';

  static const String spacedReviewChannelId = 'spaced_repetition_channel';
  static const String spacedReviewChannelName = 'Ebbinghaus Spaced Repetition';
  static const String spacedReviewChannelDesc =
      'Timely memory refreshers for difficult rules before the forgetting curve drops.';

  // Notification IDs
  static const int checkInNotificationId = 1001;
  static const int checkOutNotificationId = 1002;
  static const int mealNotificationId = 2001;
  static const int studyPlanNotificationId = 3001;
  static const int flashcardNotificationId = 4001;

  /// Block reserved for the recurring flashcard series.
  ///
  /// Each card in the series needs its own id, so they are numbered from here
  /// upward and cancelled as a block when the schedule is rebuilt.
  static const int flashcardSeriesBaseId = 4100;
  static const int flashcardSeriesMaxCount = 12;

  /// Settings keys for the recurring push.
  static const String prefFlashcardPushEnabled = 'flashcard_push_enabled';
  static const String prefFlashcardPushIntervalMinutes =
      'flashcard_push_interval_minutes';

  /// The window the user allows cards to arrive in, as hours of the day.
  /// Review items the user marked as recalled from a notification, waiting
  /// for the app to run and advance them.
  static const String prefPendingReviewAdvanceIds =
      'pending_review_advance_ids';

  /// Cards the user said they had forgotten, from a notification button.
  ///
  /// Kept beside the advance list rather than applied on the spot: the button
  /// can arrive in a background isolate where the database is not open, so
  /// the id waits here until the app next runs.
  static const String prefPendingReviewResetIds = 'pending_review_reset_ids';

  static const String prefFlashcardPushStartHour = 'flashcard_push_start_hour';
  static const String prefFlashcardPushEndHour = 'flashcard_push_end_hour';
  static const int flashcardPushDefaultStartHour = 9;
  static const int flashcardPushDefaultEndHour = 22;
  static const int spacedReviewNotificationId = 5001;

  // Action IDs for Meal Notification
  static const String actionMealYes = 'meal_action_yes';
  static const String actionMealNo = 'meal_action_no';

  // Action IDs for Biometric Check-In Notification
  static const String actionCheckInDone = 'checkin_action_done';
  static const String actionCheckInSnooze = 'checkin_action_snooze';

  // Action IDs for Biometric Check-Out Notification
  static const String actionCheckOutDone = 'checkout_action_done';

  // Action IDs for Flashcards & Spaced Repetition
  static const String actionFlashcardGotIt = 'flashcard_action_got_it';
  static const String actionFlashcardForgot = 'flashcard_action_forgot';
  static const String actionSpacedRemembered = 'spaced_action_remembered';
  static const String actionSpacedForgot = 'spaced_action_forgot';

  // SharedPreferences Keys for quick state access
  static const String prefLastCheckInDate = 'last_checkin_date';
  static const String prefLastCheckInStatus = 'last_checkin_status';
  static const String prefLastCheckOutDate = 'last_checkout_date';
  static const String prefLastMealResponse = 'last_meal_response';
  static const String prefLastMealResponseDate = 'last_meal_response_date';
  static const String prefOfficeWifiSsid = 'office_wifi_ssid';
  static const String prefGeminiApiKey = 'gemini_api_key';
  static const String prefGeminiModel = 'gemini_selected_model';
  static const String prefDinnerHour = 'dinner_hour';
  static const String prefDinnerMinute = 'dinner_minute';
  static const String prefOffDays =
      'weekly_off_days'; // Comma-separated weekdays (e.g. "4,5" for Thu, Fri)
  static const String prefWeaknessHealingEnabled = 'weakness_healing_enabled';
}
