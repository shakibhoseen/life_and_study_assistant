import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../../config/notification_constants.dart';
import '../background/wifi_monitor_service.dart';
import '../flashcards/flashcard_service.dart';
import 'notification_action_handler.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// Cards whose notification the user tapped.
  ///
  /// The tap arrives in a plugin callback with no access to the widget tree,
  /// so it is published here and the shell listens, the same way shared files
  /// are handled.
  final StreamController<FlashcardItem> _tappedFlashcards =
      StreamController<FlashcardItem>.broadcast();
  Stream<FlashcardItem> get tappedFlashcards => _tappedFlashcards.stream;

  void publishTappedFlashcard(FlashcardItem card) {
    _tappedFlashcards.add(card);
  }

  /// The card from a notification that launched the app from cold.
  ///
  /// A tap that starts the process arrives before anything is listening, so
  /// it is read back once the shell is up instead of being lost.
  Future<FlashcardItem?> takeLaunchFlashcard() async {
    final details = await _notificationsPlugin
        .getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    final response = details!.notificationResponse;
    if (response?.actionId != null) return null;
    return FlashcardItem.tryFromPayload(response?.payload);
  }

  /// Removes previous versions of channels whose sound or settings changed.
  ///
  /// In Android 8+, notification channels are immutable once created.
  /// Any channel setting update (like custom sounds) requires a new channel ID,
  /// and old unused channels should be removed so users don't see duplicates in settings.
  Future<void> _removeLegacyChannels() async {
    try {
      final android = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android == null) return;
      await android.deleteNotificationChannel(
        channelId: NotificationConstants.flashcardChannelIdLegacy,
      );
      await android.deleteNotificationChannel(
        channelId: NotificationConstants.officeChannelIdLegacy,
      );
      await android.deleteNotificationChannel(
        channelId: NotificationConstants.officeChannelIdLegacyV2,
      );
      await android.deleteNotificationChannel(
        channelId: NotificationConstants.mealChannelIdLegacy,
      );
      await android.deleteNotificationChannel(
        channelId: NotificationConstants.urgentChannelIdLegacy,
      );
    } catch (e) {
      debugPrint('Could not delete legacy channels: $e');
    }
  }

  /// Points `tz.local` at the device's own zone.
  ///
  /// The timezone package starts on UTC and stays there unless told
  /// otherwise, so every scheduled notification was being placed on UTC
  /// wall-clock hours. In Dhaka that is a six hour shift: a "9am to 10pm"
  /// quiet window actually ran 3pm to 4am, which is how flashcards came to be
  /// queued for midnight.
  ///
  /// Resolved by matching the device's current UTC offset rather than by
  /// adding a plugin for it. Any zone sharing the offset keeps the same wall
  /// clock, which is all scheduling needs.
  void _configureLocalTimeZone() {
    final offset = DateTime.now().timeZoneOffset;
    final now = DateTime.now().toUtc();

    bool matches(String name) {
      try {
        return tz.TZDateTime.from(now, tz.getLocation(name)).timeZoneOffset ==
            offset;
      } catch (_) {
        return false;
      }
    }

    // Preferred first, so the common case lands on the right name and keeps
    // the right daylight-saving rules.
    for (final name in const [
      'Asia/Dhaka',
      'Asia/Kolkata',
      'Asia/Karachi',
      'Asia/Dubai',
    ]) {
      if (matches(name)) {
        tz.setLocalLocation(tz.getLocation(name));
        debugPrint('Notification timezone: $name');
        return;
      }
    }

    for (final name in tz.timeZoneDatabase.locations.keys) {
      if (matches(name)) {
        tz.setLocalLocation(tz.getLocation(name));
        debugPrint('Notification timezone: $name (matched by offset)');
        return;
      }
    }

    debugPrint('Notification timezone: no match, staying on UTC');
  }

  Future<void> init() async {
    if (_isInitialized) return;

    tz.initializeTimeZones();
    _configureLocalTimeZone();
    await _removeLegacyChannels();

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notificationsPlugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        debugPrint('Notification clicked: ${response.actionId}');
        await handleNotificationResponse(response);
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    await _createNotificationChannels();
    await requestPermissions();

    _isInitialized = true;
  }

  Future<void> requestPermissions() async {
    if (Platform.isAndroid) {
      final androidImplementation = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      await androidImplementation?.requestNotificationsPermission();
      await androidImplementation?.requestExactAlarmsPermission();
    }

    try {
      final notifStatus = await Permission.notification.status;
      if (!notifStatus.isGranted) {
        await Permission.notification.request();
      }
      final locStatus = await Permission.location.status;
      if (!locStatus.isGranted) {
        await Permission.location.request();
      }
    } catch (e) {
      debugPrint('Error requesting permissions via permission_handler: $e');
    }
  }

  Future<void> _createNotificationChannels() async {
    final androidImplementation = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (androidImplementation == null) return;

    // Office Check-In / Check-Out Channel (Heads-up / High Priority with corporate chime)
    const officeChannel = AndroidNotificationChannel(
      NotificationConstants.officeChannelId,
      NotificationConstants.officeChannelName,
      description: NotificationConstants.officeChannelDesc,
      importance: Importance.max,
      playSound: true,
      sound: RawResourceAndroidNotificationSound(NotificationConstants.soundOfficeChime),
      enableVibration: true,
    );

    // Meal / Lunch Status Channel (Dining bell chime)
    const mealChannel = AndroidNotificationChannel(
      NotificationConstants.mealChannelId,
      NotificationConstants.mealChannelName,
      description: NotificationConstants.mealChannelDesc,
      importance: Importance.max,
      playSound: true,
      sound: RawResourceAndroidNotificationSound(NotificationConstants.soundMealBell),
      enableVibration: true,
    );

    // Urgent Attendance & Cutoff Sirens Channel (High priority dual-pulse siren)
    const urgentChannel = AndroidNotificationChannel(
      NotificationConstants.urgentChannelId,
      NotificationConstants.urgentChannelName,
      description: NotificationConstants.urgentChannelDesc,
      importance: Importance.max,
      playSound: true,
      sound: RawResourceAndroidNotificationSound(NotificationConstants.soundUrgentSiren),
      enableVibration: true,
    );

    // Study Nudges Channel
    const studyChannel = AndroidNotificationChannel(
      NotificationConstants.studyChannelId,
      NotificationConstants.studyChannelName,
      description: NotificationConstants.studyChannelDesc,
      importance: Importance.defaultImportance,
      playSound: true,
    );

    // Office Flashcards Channel (Non-intrusive, no aggressive sound while coding)
    const flashcardChannel = AndroidNotificationChannel(
      NotificationConstants.flashcardChannelId,
      NotificationConstants.flashcardChannelName,
      description: NotificationConstants.flashcardChannelDesc,
      importance: Importance.defaultImportance,
      playSound: true,
      enableVibration: true,
    );

    // Spaced Repetition (Forgetting Curve) Channel
    const spacedChannel = AndroidNotificationChannel(
      NotificationConstants.spacedReviewChannelId,
      NotificationConstants.spacedReviewChannelName,
      description: NotificationConstants.spacedReviewChannelDesc,
      importance: Importance.high,
      playSound: true,
    );

    await androidImplementation.createNotificationChannel(officeChannel);
    await androidImplementation.createNotificationChannel(mealChannel);
    await androidImplementation.createNotificationChannel(urgentChannel);
    await androidImplementation.createNotificationChannel(studyChannel);
    await androidImplementation.createNotificationChannel(flashcardChannel);
    await androidImplementation.createNotificationChannel(spacedChannel);

    // Completely silent channel for ongoing Foreground Sentinel (Zero vibration, zero sound)
    const sentinelChannel = AndroidNotificationChannel(
      NotificationConstants.sentinelChannelId,
      NotificationConstants.sentinelChannelName,
      description: NotificationConstants.sentinelChannelDesc,
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
      showBadge: false,
    );
    await androidImplementation.createNotificationChannel(sentinelChannel);
  }

  /// High-priority heads-up reminder when Office Wi-Fi is detected
  Future<void> showOfficeCheckInReminder({
    String? officeSsid,
    bool ignoreOffDay = false,
  }) async {
    if (!ignoreOffDay) {
      if (await WifiMonitorService.instance.isOfficeClosedToday()) {
        debugPrint(
          'Office is closed today (Off-day, Holiday, or Leave). Suppressing office check-in reminder.',
        );
        return;
      }
    }

    const androidDetails = AndroidNotificationDetails(
      NotificationConstants.officeChannelId,
      NotificationConstants.officeChannelName,
      channelDescription: NotificationConstants.officeChannelDesc,
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.public,
      ticker: 'Office Wi-Fi Connected!',
      playSound: true,
      sound: RawResourceAndroidNotificationSound(NotificationConstants.soundOfficeChime),
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          NotificationConstants.actionCheckInNow,
          '⚡ Punch In Now',
          showsUserInterface: false,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          NotificationConstants.actionCheckInDone,
          '✓ Punched In',
          showsUserInterface: false,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          NotificationConstants.actionMarkLeaveToday,
          '🌴 আজ ছুটিতে (Leave)',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'office_chime.wav',
      ),
    );

    final ssidText = (officeSsid != null && officeSsid.isNotEmpty)
        ? ' connected ($officeSsid)'
        : ' connected';

    await _notificationsPlugin.show(
      id: NotificationConstants.checkInNotificationId,
      title: '🏢 Office Wi-Fi Connected!',
      body:
          'Office network$ssidText. Have you punched your biometric check-in?',
      notificationDetails: details,
    );
  }

  /// Prompt notification when Office Wi-Fi disconnects
  Future<void> showOfficeCheckOutReminder({
    bool ignoreOffDay = false,
    bool isEarly = false,
  }) async {
    if (!ignoreOffDay) {
      if (await WifiMonitorService.instance.isOfficeClosedToday()) {
        debugPrint(
          'Office is closed today (Off-day, Holiday, or Leave). Suppressing office check-out reminder.',
        );
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final today = now.toIso8601String().substring(0, 10);
      final lastCheckInDate =
          prefs.getString(NotificationConstants.prefLastCheckInDate);
      final lastCheckInStatus =
          prefs.getString(NotificationConstants.prefLastCheckInStatus);
      final isPunchedInToday = lastCheckInDate == today &&
          (lastCheckInStatus == 'Punched' || lastCheckInStatus == 'Punched In');
      if (!isPunchedInToday) {
        debugPrint(
          'User was not punched in today ($today). Suppressing office check-out reminder.',
        );
        return;
      }
    }

    const androidDetails = AndroidNotificationDetails(
      NotificationConstants.officeChannelId,
      NotificationConstants.officeChannelName,
      channelDescription: NotificationConstants.officeChannelDesc,
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.public,
      playSound: true,
      sound: RawResourceAndroidNotificationSound(NotificationConstants.soundOfficeChime),
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          NotificationConstants.actionCheckOutNow,
          '🚪 Punch Out Now',
          showsUserInterface: false,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          NotificationConstants.actionCheckOutDone,
          '✓ Punched Out',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'office_chime.wav',
      ),
    );

    final title = isEarly
        ? '⚠️ Early Departure Alert (Before 6:00 PM)'
        : '🚪 Leaving Office?';
    final body = isEarly
        ? 'অফিস সময় সন্ধ্যা ৬:০০ টা পর্যন্ত (৯ ঘণ্টা)। নির্ধারিত সময়ের পূর্বে বের হলে ম্যানেজমেন্টের অনুমতি সাপেক্ষে ট্যাপ করে চেক-আউট দিন।'
        : "Disconnected from office network. Don't forget your biometric check-out punch!";

    await _notificationsPlugin.show(
      id: NotificationConstants.checkOutNotificationId,
      title: title,
      body: body,
      notificationDetails: details,
    );
  }

  /// High priority alarm when 9:15 AM late cutoff is approaching
  Future<void> showLateWarningNotification({
    required int minutesRemaining,
  }) async {
    if (await WifiMonitorService.instance.isOfficeClosedToday()) {
      debugPrint(
        'Office is closed today (Off-day, Holiday, or Leave). Suppressing late warning.',
      );
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      NotificationConstants.urgentChannelId,
      NotificationConstants.urgentChannelName,
      channelDescription: NotificationConstants.urgentChannelDesc,
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      playSound: true,
      sound: RawResourceAndroidNotificationSound(NotificationConstants.soundUrgentSiren),
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          NotificationConstants.actionCheckInNow,
          '⚡ Punch In Now',
          showsUserInterface: false,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          NotificationConstants.actionMarkLeaveToday,
          '🌴 আজ ছুটিতে (Leave)',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'urgent_siren.wav',
      ),
    );

    final title = minutesRemaining > 0
        ? '🚨 9:15 AM Late Warning ($minutesRemaining min left!)'
        : '🚨 9:15 AM Cutoff Passed - Mark Attendance Now!';
    final body = minutesRemaining > 0
        ? 'Office late penalty starts at 9:15 AM! You have not punched yet. Connect to Wi-Fi and punch now.'
        : 'It is 9:15 AM or later. Late deduction policy applies. Punch immediately!';

    await _notificationsPlugin.show(
      id: NotificationConstants.lateWarningNotificationId,
      title: title,
      body: body,
      notificationDetails: details,
    );
  }

  /// High priority urgent alert when leaving office without checking out and moving far away
  Future<void> showUrgentDepartureWarningNotification({
    required double distanceMeters,
  }) async {
    final km = (distanceMeters / 1000).toStringAsFixed(1);
    final vibrationPattern = Int64List.fromList([0, 500, 200, 500, 200, 1000]);

    final androidDetails = AndroidNotificationDetails(
      NotificationConstants.urgentChannelId,
      NotificationConstants.urgentChannelName,
      channelDescription: NotificationConstants.urgentChannelDesc,
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      fullScreenIntent: true,
      vibrationPattern: vibrationPattern,
      enableVibration: true,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound(NotificationConstants.soundUrgentSiren),
      actions: const <AndroidNotificationAction>[
        AndroidNotificationAction(
          NotificationConstants.actionCheckOutNow,
          '⚡ এখনই চেক-আউট পাঞ্চ দিন',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'urgent_siren.wav',
      ),
    );

    await _notificationsPlugin.show(
      id: NotificationConstants.urgentDistanceAlertNotificationId,
      title: '🚨 জরুরি অ্যালার্ট: আপনি অফিস ছেড়ে দূরে যাচ্ছেন!',
      body: 'আপনি অফিস থেকে প্রায় $km কিমি দূরে! কিন্তু চেক-আউট পাঞ্চ দেননি। এখনই চেক-আউট পাঞ্চ করতে ট্যাপ করুন।',
      notificationDetails: details,
    );
  }

  /// Cancels checkout reminders and distance alerts
  Future<void> cancelCheckOutReminder() async {
    await _notificationsPlugin.cancel(id: NotificationConstants.checkOutNotificationId);
    await _notificationsPlugin.cancel(id: NotificationConstants.checkOutReminderNotificationId);
    await _notificationsPlugin.cancel(id: NotificationConstants.urgentDistanceAlertNotificationId);
  }

  /// Success confirmation after Check-In
  Future<void> showOfficeCheckInSuccessNotification({
    required String time,
    required bool isLate,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      NotificationConstants.officeChannelId,
      NotificationConstants.officeChannelName,
      channelDescription: NotificationConstants.officeChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.status,
      visibility: NotificationVisibility.public,
      playSound: true,
      sound: RawResourceAndroidNotificationSound(NotificationConstants.soundOfficeChime),
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'office_chime.wav',
      ),
    );

    await _notificationsPlugin.show(
      id: NotificationConstants.checkInNotificationId,
      title: isLate ? '⚠️ Office Check-In (LATE)' : '✅ Office Check-In Successful',
      body: isLate
          ? 'Recorded at $time (After 9:14 AM late cutoff).'
          : 'Recorded at $time (On-Time ✓). Have a productive day at ZaviSoft!',
      notificationDetails: details,
    );
  }

  /// Success confirmation after Check-Out
  Future<void> showOfficeCheckOutSuccessNotification({
    required String time,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      NotificationConstants.officeChannelId,
      NotificationConstants.officeChannelName,
      channelDescription: NotificationConstants.officeChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.status,
      visibility: NotificationVisibility.public,
      playSound: true,
      sound: RawResourceAndroidNotificationSound(NotificationConstants.soundOfficeChime),
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'office_chime.wav',
      ),
    );

    await _notificationsPlugin.show(
      id: NotificationConstants.checkOutNotificationId,
      title: '🚪 Office Check-Out Done',
      body: 'Workday completed at $time. Have a relaxing evening!',
      notificationDetails: details,
    );
  }

  /// Schedules daily recurring Steadfast Lunch Cutoff reminder (Default 5:00 PM, 1 hour before 6:00 PM cutoff).
  /// Replaces the legacy 10:00 PM dinner reminder that was logically invalid.
  Future<void> scheduleDailyLunchCutoffReminder({
    int hour = 17,
    int minute = 0,
  }) async {
    // Cancel the legacy 10:00 PM dinner notification permanently
    await _notificationsPlugin.cancel(id: NotificationConstants.mealNotificationId);

    final prefs = await SharedPreferences.getInstance();
    final isEnabled =
        prefs.getBool(NotificationConstants.prefLunchAutoReminderEnabled) ?? true;
    if (!isEnabled) {
      await cancelDailyLunchCutoffReminder();
      return;
    }

    final tz.TZDateTime now;
    try {
      now = tz.TZDateTime.now(tz.local);
    } catch (_) {
      debugPrint('Timezone not initialized for watchdogs. Skipping schedule.');
      return;
    }
    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    // If time has already passed today, schedule for tomorrow
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    const androidDetails = AndroidNotificationDetails(
      NotificationConstants.mealChannelId,
      NotificationConstants.mealChannelName,
      channelDescription: NotificationConstants.mealChannelDesc,
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.public,
      playSound: true,
      sound: RawResourceAndroidNotificationSound(NotificationConstants.soundMealBell),
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          NotificationConstants.actionLunchToggleTomorrow,
          '⚡ Toggle Tomorrow Lunch',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'meal_bell.wav',
      ),
    );

    try {
      await _notificationsPlugin.zonedSchedule(
        id: NotificationConstants.lunchReminderNotificationId,
        title: '🍱 Steadfast Lunch Cutoff Reminder (Cutoff 6:00 PM)',
        body: 'আগামীকালের লাঞ্চ বুকিং বা বাতিলের সময় সন্ধ্যা ৬:০০ টায় শেষ হবে। পরিবর্তন করতে এখনই ট্যাপ করুন!',
        scheduledDate: scheduledDate,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      debugPrint('Daily lunch cutoff reminder scheduled for $scheduledDate');
    } catch (e) {
      debugPrint('Error scheduling lunch cutoff reminder: $e');
    }
  }

  /// Cancels daily lunch cutoff reminder
  Future<void> cancelDailyLunchCutoffReminder() async {
    await _notificationsPlugin.cancel(id: NotificationConstants.mealNotificationId);
    await _notificationsPlugin.cancel(id: NotificationConstants.lunchReminderNotificationId);
    debugPrint('Daily lunch cutoff reminder cancelled.');
  }

  /// Legacy alias forwarding to [scheduleDailyLunchCutoffReminder]
  Future<void> scheduleDailyDinnerReminder({
    int hour = 17,
    int minute = 0,
  }) async {
    // If caller passed 22 (the old flawed 10 PM), override to 17 (5 PM, 1h before 6 PM cutoff)
    final targetHour = (hour == 22) ? 17 : hour;
    await scheduleDailyLunchCutoffReminder(hour: targetHour, minute: minute);
  }

  /// Schedules precise morning alarm triggers before 9:15 AM late cutoff
  /// using Android's ExactAlarmManager so that even if the app was completely killed
  /// and WorkManager is sleeping, the user will be alerted before the strict 9:15 AM late cutoff.
  Future<void> scheduleMorningOfficeWatchdogs() async {
    // Cancel old alarms first to prevent duplicates
    await cancelMorningOfficeWatchdogs();

    final prefs = await SharedPreferences.getInstance();
    final isEnabled =
        prefs.getBool(NotificationConstants.prefLateWarningEnabled) ?? true;
    if (!isEnabled) {
      debugPrint('Morning watchdogs disabled in settings. Skipping.');
      return;
    }

    final tz.TZDateTime now;
    try {
      now = tz.TZDateTime.now(tz.local);
    } catch (_) {
      debugPrint('Timezone not initialized for watchdogs. Skipping schedule.');
      return;
    }
    final today = now.toIso8601String().substring(0, 10);
    final lastCheckInDate =
        prefs.getString(NotificationConstants.prefLastCheckInDate);
    final lastCheckInStatus =
        prefs.getString(NotificationConstants.prefLastCheckInStatus);
    final alreadyPunchedInToday =
        (lastCheckInDate == today && lastCheckInStatus == 'Punched In');

    // Streamlined: 2 clear alerts instead of 4 spammy sirens
    final watchdogs = [
      (
        id: NotificationConstants.morningArrivalAlarm850,
        hour: 8,
        minute: 50,
        minLeft: 25,
      ),
      (
        id: NotificationConstants.morningCutoffAlarm906,
        hour: 9,
        minute: 8,
        minLeft: 7,
      ),
    ];

    const androidDetails = AndroidNotificationDetails(
      NotificationConstants.urgentChannelId,
      NotificationConstants.urgentChannelName,
      channelDescription: NotificationConstants.urgentChannelDesc,
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      playSound: true,
      sound: RawResourceAndroidNotificationSound(NotificationConstants.soundUrgentSiren),
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          NotificationConstants.actionCheckInNow,
          '⚡ Punch In Now',
          showsUserInterface: false,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          NotificationConstants.actionMarkLeaveToday,
          '🌴 আজ ছুটিতে (Leave)',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'urgent_siren.wav',
      ),
    );

    final isClosedToday =
        await WifiMonitorService.instance.isOfficeClosedToday(now);

    for (final wd in watchdogs) {
      var scheduledDate = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        wd.hour,
        wd.minute,
      );

      // If time has already passed today, user already punched in today,
      // or office is closed today (weekly off-day, holiday, or user leave):
      if (scheduledDate.isBefore(now) || alreadyPunchedInToday || isClosedToday) {
        scheduledDate = scheduledDate.add(const Duration(days: 1));
      }

      // Advance past any weekly off-days, official company holidays, or user leaves
      while (await WifiMonitorService.instance.isOfficeClosedToday(scheduledDate)) {
        scheduledDate = scheduledDate.add(const Duration(days: 1));
      }

      try {
        await _notificationsPlugin.zonedSchedule(
          id: wd.id,
          title: '🚨 9:15 AM Late Prevention (${wd.minLeft}m Left!)',
          body:
              'Office late penalty starts at 9:15 AM! Connect to Wi-Fi and tap Punch In Now.',
          scheduledDate: scheduledDate,
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
        debugPrint(
          'Morning watchdog [${wd.hour}:${wd.minute.toString().padLeft(2, '0')}] scheduled for next working day: $scheduledDate',
        );
      } catch (e) {
        debugPrint('Error scheduling morning watchdog (${wd.id}): $e');
      }
    }
  }

  /// Cancels all scheduled morning watchdogs.
  ///
  /// Best effort on purpose. This is called straight after a successful
  /// check-in, and a punch that reached Packly must not be reported as
  /// failed because a notification could not be withdrawn afterwards. The
  /// worst case of swallowing it is a watchdog firing once for a user who
  /// has already checked in; the worst case of letting it through is the
  /// user believing they are not checked in when they are.
  Future<void> cancelMorningOfficeWatchdogs() async {
    const ids = [
      NotificationConstants.morningArrivalAlarm850,
      NotificationConstants.morningCutoffAlarm900,
      NotificationConstants.morningCutoffAlarm906,
      NotificationConstants.morningCutoffAlarm912,
    ];
    for (final id in ids) {
      try {
        await _notificationsPlugin.cancel(id: id);
      } catch (e) {
        debugPrint('Could not cancel morning watchdog $id: $e');
      }
    }
    debugPrint('Morning office watchdogs cancelled.');
  }

  /// Cancels static evening watchdogs so overtime is fully respected.
  /// Check-out and departure alerts are now 100% event-driven by Wi-Fi disconnection.
  Future<void> scheduleEveningOfficeWatchdogs() async {
    await cancelEveningOfficeWatchdogs();
    debugPrint('Evening static office watchdogs disabled to protect overtime.');
  }

  /// Cancels all scheduled evening watchdogs
  Future<void> cancelEveningOfficeWatchdogs() async {
    await _notificationsPlugin.cancel(id: NotificationConstants.eveningDepartureAlarm555);
    await _notificationsPlugin.cancel(id: NotificationConstants.eveningDepartureAlarm600);
    await _notificationsPlugin.cancel(id: NotificationConstants.eveningDepartureAlarm605);
    await _notificationsPlugin.cancel(id: NotificationConstants.eveningDepartureAlarm610);
    await _notificationsPlugin.cancel(id: NotificationConstants.eveningDepartureAlarm615);
    debugPrint('Evening departure watchdogs cancelled.');
  }

  /// Schedules daily 12:25 PM lunch status sentinel trigger
  Future<void> scheduleDailyLunchTrackingTrigger() async {
    final tz.TZDateTime now;
    try {
      now = tz.TZDateTime.now(tz.local);
    } catch (_) {
      debugPrint('Timezone not initialized for watchdogs. Skipping schedule.');
      return;
    }
    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      12,
      25,
    );

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    const androidDetails = AndroidNotificationDetails(
      NotificationConstants.sentinelChannelId,
      NotificationConstants.sentinelChannelName,
      channelDescription: NotificationConstants.sentinelChannelDesc,
      importance: Importance.low,
      priority: Priority.low,
      playSound: false,
      enableVibration: false,
      channelShowBadge: false,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: false,
        presentBadge: false,
        presentSound: false,
      ),
    );

    try {
      await _notificationsPlugin.zonedSchedule(
        id: NotificationConstants.lunchTrackingAlarm1230,
        title: '🍱 Steadfast Lunch Tracker Active',
        body: 'Checking meal dispatch progress...',
        scheduledDate: scheduledDate,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      debugPrint('Daily lunch tracking trigger scheduled for $scheduledDate');
    } catch (e) {
      debugPrint('Error scheduling daily lunch tracking trigger: $e');
    }
  }

  /// Cancels scheduled daily lunch tracking trigger
  Future<void> cancelDailyLunchTrackingTrigger() async {
    await _notificationsPlugin.cancel(id: NotificationConstants.lunchTrackingAlarm1230);
    debugPrint('Daily lunch tracking trigger cancelled.');
  }

  /// Schedules micro-flashcard study nudges during office break periods (1:15 PM lunch and 4:30 PM tea break)
  /// Non-intrusive (no sound, soft priority) so work is never disturbed while BCS revision continues.
  Future<void> scheduleOfficeDowntimeFlashcards() async {
    final prefs = await SharedPreferences.getInstance();
    final isEnabled =
        prefs.getBool(NotificationConstants.prefOfficeDowntimeFlashcardEnabled) ?? false;
    if (!isEnabled) {
      await cancelOfficeDowntimeFlashcards();
      return;
    }

    final tz.TZDateTime now;
    try {
      now = tz.TZDateTime.now(tz.local);
    } catch (_) {
      debugPrint('Timezone not initialized for watchdogs. Skipping schedule.');
      return;
    }

    final breaks = [
      (
        id: NotificationConstants.officeDowntimeFlashcardLunch,
        hour: 13,
        minute: 15,
        title: '☕ Lunch Downtime Revision',
        body: 'লাঞ্চ বিরতিতে ১ মিনিটের কুইক রিভিশন: বিসিএস ফ্ল্যাশকার্ড দেখে নিন!',
      ),
      (
        id: NotificationConstants.officeDowntimeFlashcardTea,
        hour: 16,
        minute: 30,
        title: '🫖 Tea Break Micro-Study',
        body: 'বিকালের বিরতিতে বিসিএস সাধারণ জ্ঞান বা ভোকাবুলারির ১টি কুইক রুল রিফ্রেশ করুন!',
      ),
    ];

    const androidDetails = AndroidNotificationDetails(
      NotificationConstants.flashcardChannelId,
      NotificationConstants.flashcardChannelName,
      channelDescription: NotificationConstants.flashcardChannelDesc,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      playSound: false,
      enableVibration: false,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: false,
      ),
    );

    for (final b in breaks) {
      var scheduledDate = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        b.hour,
        b.minute,
      );

      if (scheduledDate.isBefore(now)) {
        scheduledDate = scheduledDate.add(const Duration(days: 1));
      }

      try {
        await _notificationsPlugin.zonedSchedule(
          id: b.id,
          title: b.title,
          body: b.body,
          scheduledDate: scheduledDate,
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
        );
        debugPrint('Office downtime flashcard scheduled for ${b.hour}:${b.minute}');
      } catch (e) {
        debugPrint('Error scheduling office downtime flashcard: $e');
      }
    }
  }

  /// Cancels scheduled office downtime flashcard nudges
  Future<void> cancelOfficeDowntimeFlashcards() async {
    await _notificationsPlugin.cancel(
      id: NotificationConstants.officeDowntimeFlashcardLunch,
    );
    await _notificationsPlugin.cancel(
      id: NotificationConstants.officeDowntimeFlashcardTea,
    );
  }

  /// Schedules daily morning exam & syllabus reminder (Default 8:30 AM)
  Future<void> scheduleLiveMcqDailyNudge({
    int hour = 8,
    int minute = 30,
  }) async {
    final tz.TZDateTime now;
    try {
      now = tz.TZDateTime.now(tz.local);
    } catch (_) {
      debugPrint('Timezone not initialized for watchdogs. Skipping schedule.');
      return;
    }
    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    const androidDetails = AndroidNotificationDetails(
      NotificationConstants.studyChannelId,
      NotificationConstants.studyChannelName,
      channelDescription: NotificationConstants.studyChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    try {
      await _notificationsPlugin.zonedSchedule(
        id: NotificationConstants.liveMcqExamReminderId,
        title: '☀️ আজকের লাইভ পরীক্ষা ও সিলেবাস লক্ষ্য',
        body: 'আজকের পরীক্ষার সিলেবাস রিভিশন ও স্টাডি টার্গেট সেট করুন!',
        scheduledDate: scheduledDate,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      debugPrint('Daily LiveMCQ morning nudge scheduled for $scheduledDate');
    } catch (e) {
      debugPrint('Error scheduling LiveMCQ morning nudge: $e');
    }
  }

  /// Schedules daily evening accountability check-in (Default 10:00 PM)
  Future<void> scheduleLiveMcqScorePrompt({
    int hour = 22,
    int minute = 0,
  }) async {
    final tz.TZDateTime now;
    try {
      now = tz.TZDateTime.now(tz.local);
    } catch (_) {
      debugPrint('Timezone not initialized for watchdogs. Skipping schedule.');
      return;
    }
    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    const androidDetails = AndroidNotificationDetails(
      NotificationConstants.studyChannelId,
      NotificationConstants.studyChannelName,
      channelDescription: NotificationConstants.studyChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    try {
      await _notificationsPlugin.zonedSchedule(
        id: NotificationConstants.liveMcqScoreCheckinId,
        title: '🎯 লাইভ পরীক্ষা সম্পন্ন করেছেন?',
        body: 'আজকের পরীক্ষার স্কোর কত এলো? অ্যাপে লিখে আপনার প্রগ্রেস ট্র্যাক করুন!',
        scheduledDate: scheduledDate,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      debugPrint('Daily LiveMCQ score check-in scheduled for $scheduledDate');
    } catch (e) {
      debugPrint('Error scheduling LiveMCQ score check-in: $e');
    }
  }

  /// Instant test/manual trigger for the lunch cutoff reminder notification
  Future<void> showInstantDinnerReminder() async {
    final prefs = await SharedPreferences.getInstance();
    final isBooked =
        prefs.getBool(NotificationConstants.prefLunchLastKnownTomorrowBooked) ?? false;
    await showSteadfastLunchReminderNotification(
      isTomorrowBooked: isBooked,
      cutoff: '6:00 PM',
    );
  }

  /// Instant result notification after user toggles lunch from notification action
  Future<void> showSteadfastLunchResultNotification({
    required bool isBooked,
  }) async {
    final title = isBooked
        ? '✅ Steadfast Lunch: Tomorrow is Booked!'
        : '❌ Steadfast Lunch: Tomorrow Cancelled';
    final body = isBooked
        ? 'আগামীকালের লাঞ্চ সফলভাবে বুক করা হয়েছে (Cutoff 6:00 PM)।'
        : 'আগামীকালের লাঞ্চ সফলভাবে বাতিল করা হয়েছে।';

    const androidDetails = AndroidNotificationDetails(
      NotificationConstants.mealChannelId,
      NotificationConstants.mealChannelName,
      channelDescription: NotificationConstants.mealChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.status,
      visibility: NotificationVisibility.public,
      playSound: true,
      sound: RawResourceAndroidNotificationSound(NotificationConstants.soundMealBell),
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'meal_bell.wav',
      ),
    );

    await _notificationsPlugin.show(
      id: NotificationConstants.lunchReminderNotificationId,
      title: title,
      body: body,
      notificationDetails: details,
    );
  }

  /// Steadfast Courier Lunch Cutoff reminder (e.g. at 5:00 PM, 1 hour before 6:00 PM cutoff)
  Future<void> showSteadfastLunchReminderNotification({
    required bool isTomorrowBooked,
    String cutoff = '6:00 PM',
  }) async {
    final androidDetails = AndroidNotificationDetails(
      NotificationConstants.mealChannelId,
      NotificationConstants.mealChannelName,
      channelDescription: NotificationConstants.mealChannelDesc,
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.public,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound(NotificationConstants.soundMealBell),
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          NotificationConstants.actionLunchToggleTomorrow,
          isTomorrowBooked ? '❌ Cancel Tomorrow Lunch' : '⚡ Book Tomorrow Lunch',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'meal_bell.wav',
      ),
    );

    final title = isTomorrowBooked
        ? '🍱 Steadfast Lunch: Tomorrow is Booked (Cutoff $cutoff)'
        : '⚠️ Steadfast Lunch: Tomorrow is NOT Booked! (Cutoff $cutoff)';
    final body = isTomorrowBooked
        ? 'আগামীকালের লাঞ্চ বুক করা আছে। পরিবর্তন করতে চাইলে আজ সন্ধ্যা $cutoff-এর আগেই পরিবর্তন করতে হবে।'
        : 'আগামীকালের লাঞ্চ এখনো বুক করেননি! আগামীকাল অফিসে লাঞ্চ পেতে চাইলে আজ সন্ধ্যা $cutoff-এর আগে বুক করুন।';

    await _notificationsPlugin.show(
      id: NotificationConstants.lunchReminderNotificationId,
      title: title,
      body: body,
      notificationDetails: details,
    );
  }

  /// High-priority notification when the lunch car arrives at the office / canteen
  Future<void> showLunchReceivedNotification({
    String? time,
    String? message,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      NotificationConstants.mealChannelId,
      NotificationConstants.mealChannelName,
      channelDescription: NotificationConstants.mealChannelDesc,
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.public,
      enableVibration: true,
      playSound: true,
      sound: RawResourceAndroidNotificationSound(NotificationConstants.soundMealBell),
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'meal_bell.wav',
      ),
    );

    final timeSuffix = time != null && time.isNotEmpty ? ' ($time)' : '';
    await _notificationsPlugin.show(
      id: NotificationConstants.lunchReceivedNotificationId,
      title: '📦 লাঞ্চের গাড়ি অফিসে পৌঁছেছে!$timeSuffix',
      body: message != null && message.isNotEmpty
          ? message
          : 'খাবার ক্যান্টিনে রিসিভ করা হয়েছে। কিছুক্ষণের মধ্যেই পরিবেশন শুরু হবে।',
      notificationDetails: details,
    );
  }

  /// High-priority notification when lunch is served and ready in cafeteria
  Future<void> showLunchServedNotification({
    String? time,
    String? message,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      NotificationConstants.mealChannelId,
      NotificationConstants.mealChannelName,
      channelDescription: NotificationConstants.mealChannelDesc,
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.public,
      enableVibration: true,
      playSound: true,
      sound: RawResourceAndroidNotificationSound(NotificationConstants.soundMealBell),
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'meal_bell.wav',
      ),
    );

    final timeSuffix = time != null && time.isNotEmpty ? ' ($time)' : '';
    await _notificationsPlugin.show(
      id: NotificationConstants.lunchServedNotificationId,
      title: '🍽️ লাঞ্চ পরিবেশন শুরু হয়েছে!$timeSuffix',
      body: message != null && message.isNotEmpty
          ? message
          : 'ক্যান্টিনে খাবার পরিবেশন শুরু হয়েছে। আপনার লাঞ্চ গ্রহণ করতে পারেন।',
      notificationDetails: details,
    );
  }

  /// Show study nudge notification
  Future<void> showStudyNudgeNotification({
    required String title,
    required String body,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      NotificationConstants.studyChannelId,
      NotificationConstants.studyChannelName,
      channelDescription: NotificationConstants.studyChannelDesc,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );

    await _notificationsPlugin.show(
      id: NotificationConstants.studyPlanNotificationId,
      title: title,
      body: body,
      notificationDetails: details,
    );
  }

  /// Non-intrusive 5-second flashcard notification for coding breaks
  /// Lays out the next few flashcards as timed notifications.
  ///
  /// Scheduled ahead with their content already chosen, rather than woken by
  /// a background task: Android gives a periodic worker no better than a
  /// fifteen-minute floor and may defer it for far longer, and a worker would
  /// have to reach the database from another isolate to find a card. Queuing
  /// real cards in advance keeps the timing exact and the content real; the
  /// app refills the queue whenever it is opened.
  ///
  /// Quiet hours are honoured, because a vocabulary card at 3am teaches
  /// nothing and costs trust.
  /// Returns how many pushes were actually queued.
  ///
  /// Fewer than asked for means the deck ran out, which is worth saying:
  /// the queue is only rebuilt when the app is opened, so a short one is how
  /// long the pushes will last.
  Future<int> scheduleFlashcardSeries({
    required List<FlashcardItem> cards,
    required Duration interval,
    int startHour = 9,
    int endHour = 22,

    /// For trying the feature out: skips the quiet window so a card arrives
    /// now rather than tomorrow morning.
    bool ignoreQuietHours = false,
  }) async {
    await cancelFlashcardSeries();
    if (cards.isEmpty || interval.inMinutes < 1) return 0;

    final androidDetails = AndroidNotificationDetails(
      NotificationConstants.flashcardChannelId,
      NotificationConstants.flashcardChannelName,
      channelDescription: NotificationConstants.flashcardChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          NotificationConstants.actionFlashcardGotIt,
          '✓ মনে আছে',
          showsUserInterface: false,
          cancelNotification: true,
        ),
        // Forgetting is the signal the schedule needs most, and offering only
        // "got it" meant the honest answer cost a trip into the app.
        AndroidNotificationAction(
          NotificationConstants.actionFlashcardForgot,
          '✗ মনে নেই',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(presentAlert: true),
    );

    var when = tz.TZDateTime.now(tz.local).add(interval);
    var scheduled = 0;

    for (final card in cards) {
      if (scheduled >= NotificationConstants.flashcardSeriesMaxCount) break;

      // Walk forward out of the quiet window rather than dropping the card.
      var guard = 0;
      while (!ignoreQuietHours &&
          (when.hour < startHour || when.hour >= endHour) &&
          guard < 48) {
        when = when.add(const Duration(hours: 1));
        guard++;
      }

      final body = (card.mnemonic != null && card.mnemonic!.isNotEmpty)
          ? '${card.content}\n💡 ${card.mnemonic}'
          : card.content;

      try {
        await _notificationsPlugin.zonedSchedule(
          id: NotificationConstants.flashcardSeriesBaseId + scheduled,
          title: '🧠 ${card.subject}: ${card.title}',
          body: body,
          scheduledDate: when,
          notificationDetails: details,
          payload: jsonEncode(card.toPayload()),
          // Inexact alarms are cheap on battery and fine an hour apart, but
          // the OS may hold them for many minutes -- useless for a short
          // interval where the whole point is seeing it arrive.
          androidScheduleMode: interval.inMinutes < 15
              ? AndroidScheduleMode.exactAllowWhileIdle
              : AndroidScheduleMode.inexactAllowWhileIdle,
        );
        scheduled++;
      } catch (e) {
        debugPrint('Error scheduling flashcard at $when: $e');
      }

      when = when.add(interval);
    }

    debugPrint(
      'Flashcard series: $scheduled queued, every ${interval.inMinutes} min, '
      '${ignoreQuietHours ? "quiet hours ignored" : "${startHour}h-${endHour}h"}',
    );
    return scheduled;
  }

  /// Clears the whole queued series.
  Future<void> cancelFlashcardSeries() async {
    for (var i = 0; i < NotificationConstants.flashcardSeriesMaxCount; i++) {
      await _notificationsPlugin.cancel(
        id: NotificationConstants.flashcardSeriesBaseId + i,
      );
    }
  }

  Future<void> showOfficeMicroFlashcard({
    required String subject,
    required String title,
    required String content,
    String? mnemonic,
  }) async {
    final bodyText = mnemonic != null && mnemonic.isNotEmpty
        ? '$content\n💡 Shortcut: $mnemonic'
        : content;

    final androidDetails = AndroidNotificationDetails(
      NotificationConstants.flashcardChannelId,
      NotificationConstants.flashcardChannelName,
      channelDescription: NotificationConstants.flashcardChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      styleInformation: BigTextStyleInformation(
        bodyText,
        htmlFormatBigText: false,
        contentTitle: '⚡ 5s Flashcard: [$subject] $title',
        summaryText: subject,
      ),
      actions: const <AndroidNotificationAction>[
        AndroidNotificationAction(
          NotificationConstants.actionFlashcardGotIt,
          '✓ Got It (মনে আছে)',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentSound: false,
      ),
    );

    await _notificationsPlugin.show(
      id: NotificationConstants.flashcardNotificationId,
      title: '⚡ 5s Flashcard: [$subject] $title',
      body: content,
      notificationDetails: details,
    );
  }

  /// Spaced Repetition (Ebbinghaus Forgetting Curve) timely reminder
  Future<void> showSpacedReviewNotification({
    required int itemId,
    required String subject,
    required String topic,
    required String title,
    required String keyRule,
    required int intervalDays,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      NotificationConstants.spacedReviewChannelId,
      NotificationConstants.spacedReviewChannelName,
      channelDescription: NotificationConstants.spacedReviewChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(
        keyRule,
        contentTitle: '🧠 Spaced Review (Day $intervalDays): [$subject]',
        summaryText: topic,
      ),
      actions: const <AndroidNotificationAction>[
        AndroidNotificationAction(
          NotificationConstants.actionSpacedRemembered,
          '✓ মনে আছে',
          showsUserInterface: false,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          NotificationConstants.actionSpacedForgot,
          '✗ মনে নেই',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
      ),
    );

    await _notificationsPlugin.show(
      id: NotificationConstants.spacedReviewNotificationId,
      title: '🧠 Spaced Review (Day $intervalDays): [$subject]',
      body: '$title — $keyRule',
      notificationDetails: details,
      payload: '$itemId',
    );
  }

  Future<void> cancelNotification(int id) async {
    await _notificationsPlugin.cancel(id: id);
  }
}
