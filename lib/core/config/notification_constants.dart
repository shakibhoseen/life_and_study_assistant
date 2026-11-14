class NotificationConstants {
  // Notification Channels
  static const String officeChannelId = 'office_triggers_channel';
  static const String officeChannelName = 'Office Attendance & Wi-Fi Alerts';
  static const String officeChannelDesc =
      'High priority heads-up reminders for biometric check-in and check-out based on Wi-Fi/Geofence.';

  static const String sentinelChannelId = 'office_sentinel_silent_channel_v1';
  static const String sentinelChannelName = 'Office Arrival & Departure Monitor';
  static const String sentinelChannelDesc =
      'Silent ongoing background monitor for office arrival and departure. Zero sound and zero vibration.';

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
  static const int lateWarningNotificationId = 1003;
  static const int checkOutReminderNotificationId = 1004;
  static const int urgentDistanceAlertNotificationId = 1030;
  static const int morningArrivalAlarm850 = 1009;
  static const int morningCutoffAlarm900 = 1010;
  static const int morningCutoffAlarm906 = 1011;
  static const int morningCutoffAlarm912 = 1012;
  static const int eveningDepartureAlarm555 = 1020;
  static const int eveningDepartureAlarm600 = 1021;
  static const int eveningDepartureAlarm605 = 1022;
  static const int eveningDepartureAlarm610 = 1023;
  static const int eveningDepartureAlarm615 = 1024;
  static const int mealNotificationId = 2001;
  static const int lunchReminderNotificationId = 2002;
  static const int lunchReceivedNotificationId = 2003;
  static const int lunchServedNotificationId = 2004;
  static const int lunchTrackingAlarm1230 = 2010;
  static const int lunchServingSentinelServiceId = 258;
  static const int studyPlanNotificationId = 3001;
  static const int flashcardNotificationId = 4001;
  static const int officeDowntimeFlashcardLunch = 4010;
  static const int officeDowntimeFlashcardTea = 4011;

  static const String prefOfficeDowntimeFlashcardEnabled =
      'office_downtime_flashcards_enabled';

  /// Block reserved for the recurring flashcard series.
  ///
  /// Each card in the series needs its own id, so they are numbered from here
  /// upward and cancelled as a block when the schedule is rebuilt.
  static const int flashcardSeriesBaseId = 4100;

  /// Upper bound on how many pushes are queued at once.
  ///
  /// The depth actually used is worked out from the user's window and
  /// interval; this only stops a very short interval filling the queue.
  static const int flashcardSeriesMaxCount = 60;

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

  /// How many pushes the last refresh managed to queue, and how many slots a
  /// day the user's settings give, so Settings can say how long it lasts.
  /// What the queue was last built from, and when, so reopening the app
  /// does not cancel pending pushes and restart them from now.
  static const String prefFlashcardQueueFingerprint =
      'flashcard_queue_fingerprint';
  static const String prefFlashcardQueueBuiltAt = 'flashcard_queue_built_at';

  static const String prefFlashcardQueuedCount = 'flashcard_queued_count';
  static const String prefFlashcardSlotsPerDay = 'flashcard_slots_per_day';

  static const String prefFlashcardPushStartHour = 'flashcard_push_start_hour';
  static const String prefFlashcardPushEndHour = 'flashcard_push_end_hour';
  static const int flashcardPushDefaultStartHour = 9;
  static const int flashcardPushDefaultEndHour = 22;
  static const int spacedReviewNotificationId = 5001;

  // Action IDs for Meal Notification
  static const String actionMealYes = 'meal_action_yes';
  static const String actionMealNo = 'meal_action_no';
  static const String actionLunchToggleTomorrow = 'lunch_action_toggle_tomorrow';
  static const String actionLunchOpen = 'lunch_action_open';

  // Action IDs for Biometric Check-In Notification
  static const String actionCheckInDone = 'checkin_action_done';
  static const String actionCheckInNow = 'checkin_action_now';
  static const String actionCheckInSnooze = 'checkin_action_snooze';

  // Action IDs for Biometric Check-Out Notification
  static const String actionCheckOutDone = 'checkout_action_done';
  static const String actionCheckOutNow = 'checkout_action_now';

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

  // Zavisoft Packly Attendance & Office Geofence Settings
  static const String prefPacklyEmail = 'packly_email';
  static const String prefPacklyPassword = 'packly_password';
  static const String prefAutoCheckInEnabled = 'packly_auto_checkin_enabled';
  static const String prefAutoCheckOutEnabled = 'packly_auto_checkout_enabled';
  static const String prefLateWarningEnabled = 'packly_late_warning_enabled';
  static const String prefOfficeLatitude = 'office_latitude';
  static const String prefOfficeLongitude = 'office_longitude';
  static const String prefOfficeAddress = 'office_address';
  static const String prefOfficeRadiusMeters = 'office_radius_meters';
  static const String prefLastCheckInTime = 'packly_last_checkin_time';
  static const String prefLastCheckOutTime = 'packly_last_checkout_time';
  static const String prefLastCheckInIsLate = 'packly_last_checkin_is_late';
  static const String prefPacklyHolidaysCache = 'packly_holidays_cache';
  static const String prefPacklyHolidaysLastSync = 'packly_holidays_last_sync';
  static const String prefOfficeBannerMode = 'office_banner_display_mode';
  static const String prefPacklySimulationMode = 'packly_simulation_mode';

  // Simulation Mode Keys (Strictly isolated to prevent mock data polluting live attendance)
  static const String prefSimulatedCheckInDate = 'simulated_check_in_date';
  static const String prefSimulatedCheckInTime = 'simulated_check_in_time';
  static const String prefSimulatedCheckInStatus = 'simulated_check_in_status';
  static const String prefSimulatedCheckInIsLate = 'simulated_check_in_is_late';
  static const String prefSimulatedCheckOutDate = 'simulated_check_out_date';
  static const String prefSimulatedCheckOutTime = 'simulated_check_out_time';

  // Steadfast Courier Lunch & Meal Portal Settings
  static const String prefLunchEmail = 'lunch_email';
  static const String prefLunchPassword = 'lunch_password';
  static const String prefLunchAutoReminderEnabled = 'lunch_auto_reminder_enabled';
  static const String prefLunchReminderHour = 'lunch_reminder_hour';
  static const String prefLunchReminderMinute = 'lunch_reminder_minute';
  static const String prefLunchSimulationMode = 'lunch_simulation_mode';
  static const String prefLunchLastKnownTomorrowBooked = 'lunch_tomorrow_booked';
  static const String prefLunchLastKnownTodayBooked = 'lunch_today_booked';
  static const String prefLunchLastSyncTime = 'lunch_last_sync_time';
  static const String prefLunchServingTrackingEnabled = 'lunch_serving_tracking_enabled';
  static const String prefLastNotifiedLunchStatus = 'last_notified_lunch_status';
  static const String prefLastNotifiedLunchStatusDate = 'last_notified_lunch_status_date';
  static const String prefSimulatedServingStatus = 'simulated_serving_status';

  /// Whether a busy or failing model may be swapped for another one.
  ///
  /// The model is the user's choice, made in Settings. Quietly answering with
  /// a different one — usually a cheaper, weaker one — means the quality they
  /// picked is not the quality they get, and nothing on screen says so. Off by
  /// default: a 503 is retried on the chosen model instead.
  static const String prefAllowModelFallback = 'ai_allow_model_fallback';

  /// The scanner's own settings, remembered between scans.
  ///
  /// They used to live only in the modal's state, so every setting the user
  /// chose was forgotten the moment the sheet closed and had to be chosen
  /// again on the next page. A control that does not stick is not control.
  static const String prefScanTrustPrintedAnswers = 'scan_trust_printed';
  static const String prefScanWithExplanations = 'scan_with_explanations';
  static const String prefScanCrossCheck = 'scan_cross_check';
  static const String prefScanDetail = 'scan_capture_detail';
}
