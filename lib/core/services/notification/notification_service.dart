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

  /// Removes the first, silent flashcard channel.
  ///
  /// Harmless if it was never created. Without this the user would find two
  /// flashcard entries in Android's notification settings, one of which does
  /// nothing.
  Future<void> _removeLegacyFlashcardChannel() async {
    try {
      final android = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.deleteNotificationChannel(
        channelId: NotificationConstants.flashcardChannelIdLegacy,
      );
    } catch (e) {
      debugPrint('Could not delete the legacy flashcard channel: $e');
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
    await _removeLegacyFlashcardChannel();

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

    // Office Check-In / Check-Out Channel (Heads-up / High Priority)
    const officeChannel = AndroidNotificationChannel(
      NotificationConstants.officeChannelId,
      NotificationConstants.officeChannelName,
      description: NotificationConstants.officeChannelDesc,
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    // Meal / Dinner Reminder Channel
    const mealChannel = AndroidNotificationChannel(
      NotificationConstants.mealChannelId,
      NotificationConstants.mealChannelName,
      description: NotificationConstants.mealChannelDesc,
      importance: Importance.max,
      playSound: true,
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
    await androidImplementation.createNotificationChannel(studyChannel);
    await androidImplementation.createNotificationChannel(flashcardChannel);
    await androidImplementation.createNotificationChannel(spacedChannel);
  }

  /// High-priority heads-up reminder when Office Wi-Fi is detected
  Future<void> showOfficeCheckInReminder({
    String? officeSsid,
    bool ignoreOffDay = false,
  }) async {
    if (!ignoreOffDay) {
      final prefs = await SharedPreferences.getInstance();
      final offDaysStr = prefs.getString(NotificationConstants.prefOffDays);
      final offDays = (offDaysStr == null || offDaysStr.isEmpty)
          ? [DateTime.thursday, DateTime.friday]
          : offDaysStr
                .split(',')
                .map((s) => int.tryParse(s.trim()))
                .whereType<int>()
                .toList();
      if (offDays.contains(DateTime.now().weekday)) {
        debugPrint(
          'Today is an off-day (${DateTime.now().weekday}). Suppressing office check-in reminder.',
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
          NotificationConstants.actionCheckInSnooze,
          '⏰ Remind in 10m',
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
  Future<void> showOfficeCheckOutReminder({bool ignoreOffDay = false}) async {
    if (!ignoreOffDay) {
      final prefs = await SharedPreferences.getInstance();
      final offDaysStr = prefs.getString(NotificationConstants.prefOffDays);
      final offDays = (offDaysStr == null || offDaysStr.isEmpty)
          ? [DateTime.thursday, DateTime.friday]
          : offDaysStr
                .split(',')
                .map((s) => int.tryParse(s.trim()))
                .whereType<int>()
                .toList();
      if (offDays.contains(DateTime.now().weekday)) {
        debugPrint(
          'Today is an off-day (${DateTime.now().weekday}). Suppressing office check-out reminder.',
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
      ),
    );

    await _notificationsPlugin.show(
      id: NotificationConstants.checkOutNotificationId,
      title: '🚪 Leaving Office?',
      body: "Disconnected from office network. Don't forget your biometric check-out punch!",
      notificationDetails: details,
    );
  }

  /// High priority alarm when 9:15 AM late cutoff is approaching
  Future<void> showLateWarningNotification({
    required int minutesRemaining,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      NotificationConstants.officeChannelId,
      NotificationConstants.officeChannelName,
      channelDescription: NotificationConstants.officeChannelDesc,
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          NotificationConstants.actionCheckInNow,
          '⚡ Punch In Now',
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
      NotificationConstants.officeChannelId,
      NotificationConstants.officeChannelName,
      channelDescription: NotificationConstants.officeChannelDesc,
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      fullScreenIntent: true,
      vibrationPattern: vibrationPattern,
      enableVibration: true,
      playSound: true,
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
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
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
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _notificationsPlugin.show(
      id: NotificationConstants.checkOutNotificationId,
      title: '🚪 Office Check-Out Done',
      body: 'Workday completed at $time. Have a relaxing evening!',
      notificationDetails: details,
    );
  }

  /// Schedules daily recurring dinner confirmation notification (Default 4:00 PM)
  /// with actionable notification buttons in tray: [Yes, Count Me In] and [No, Skip]
  Future<void> scheduleDailyDinnerReminder({
    // Was 16 while tz.local was stuck on UTC, which landed at 22:00 in Dhaka.
    // Now that the zone is real, the hour says what it means and the reminder
    // keeps arriving at the time it always did.
    int hour = 22,
    int minute = 0,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
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
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          NotificationConstants.actionMealYes,
          '✓ Yes, Count Me In',
          showsUserInterface: false,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          NotificationConstants.actionMealNo,
          '✗ No, Skip',
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
      ),
    );

    try {
      await _notificationsPlugin.zonedSchedule(
        id: NotificationConstants.mealNotificationId,
        title: '🍽️ Office Dinner Confirmation Cutoff',
        body: 'Daily meal confirmation deadline is approaching! Will you have dinner at the office today?',
        scheduledDate: scheduledDate,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      debugPrint('Daily dinner reminder scheduled for $scheduledDate');
    } catch (e) {
      debugPrint('Error scheduling dinner reminder: $e');
    }
  }

  /// Schedules precise morning alarm triggers between 9:00 AM and 9:15 AM
  /// using Android's ExactAlarmManager so that even if the app was completely killed
  /// and WorkManager is sleeping, the user will be alerted before the strict 9:15 AM late cutoff.
  Future<void> scheduleMorningOfficeWatchdogs() async {
    final now = tz.TZDateTime.now(tz.local);

    final watchdogs = [
      (
        id: NotificationConstants.morningCutoffAlarm900,
        hour: 9,
        minute: 0,
        minLeft: 15,
      ),
      (
        id: NotificationConstants.morningCutoffAlarm906,
        hour: 9,
        minute: 6,
        minLeft: 9,
      ),
      (
        id: NotificationConstants.morningCutoffAlarm912,
        hour: 9,
        minute: 12,
        minLeft: 3,
      ),
    ];

    const androidDetails = AndroidNotificationDetails(
      NotificationConstants.officeChannelId,
      NotificationConstants.officeChannelName,
      channelDescription: NotificationConstants.officeChannelDesc,
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          NotificationConstants.actionCheckInNow,
          '⚡ Punch In Now',
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
      ),
    );

    for (final wd in watchdogs) {
      var scheduledDate = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        wd.hour,
        wd.minute,
      );

      if (scheduledDate.isBefore(now)) {
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
          matchDateTimeComponents: DateTimeComponents.time,
        );
        debugPrint(
          'Morning watchdog [${wd.hour}:${wd.minute.toString().padLeft(2, '0')}] scheduled for $scheduledDate',
        );
      } catch (e) {
        debugPrint('Error scheduling morning watchdog (${wd.id}): $e');
      }
    }
  }

  /// Cancels all scheduled morning watchdogs
  Future<void> cancelMorningOfficeWatchdogs() async {
    await _notificationsPlugin.cancel(
      id: NotificationConstants.morningCutoffAlarm900,
    );
    await _notificationsPlugin.cancel(
      id: NotificationConstants.morningCutoffAlarm906,
    );
    await _notificationsPlugin.cancel(
      id: NotificationConstants.morningCutoffAlarm912,
    );
    debugPrint('Morning office watchdogs cancelled.');
  }

  /// Schedules precise evening alarm triggers around 6:00 PM (5:55 PM, 6:00 PM, 6:05 PM, 6:10 PM, 6:15 PM)
  /// so that if the user leaves office at 6:00 PM, they receive the check-out reminder immediately at departure
  /// rather than waiting for any 15-minute background worker gap when they are already far away!
  Future<void> scheduleEveningOfficeWatchdogs() async {
    final now = tz.TZDateTime.now(tz.local);

    final eveningWatchdogs = [
      (
        id: NotificationConstants.eveningDepartureAlarm555,
        hour: 17,
        minute: 55,
        title: '🏢 5:55 PM: 5 Mins to Office Departure',
        body: 'Office workday ends at 6:00 PM. Get ready to check out on departure!',
      ),
      (
        id: NotificationConstants.eveningDepartureAlarm600,
        hour: 18,
        minute: 0,
        title: '🏁 6:00 PM: Workday Completed! Check Out Now',
        body: '9-Hour duty completed. Leaving office? Tap Check Out Now!',
      ),
      (
        id: NotificationConstants.eveningDepartureAlarm605,
        hour: 18,
        minute: 5,
        title: '🚪 6:05 PM Departure Sentinel: Did you leave office?',
        body: 'Remember to check out before travelling! Tap to submit check-out.',
      ),
      (
        id: NotificationConstants.eveningDepartureAlarm610,
        hour: 18,
        minute: 10,
        title: '⏰ 6:10 PM Check-Out Reminder',
        body: 'Tap to check out or continue working if on Overtime.',
      ),
      (
        id: NotificationConstants.eveningDepartureAlarm615,
        hour: 18,
        minute: 15,
        title: '🚨 6:15 PM Departure Notice',
        body: 'If you left the office, mark attendance now so departure location is saved.',
      ),
      (
        id: NotificationConstants.eveningDepartureAlarm630,
        hour: 18,
        minute: 30,
        title: '🏢 6:30 PM Overtime / Departure Alert',
        body: 'Still working or leaving office? Tap to check out now.',
      ),
      (
        id: NotificationConstants.eveningDepartureAlarm700,
        hour: 19,
        minute: 0,
        title: '🌙 7:00 PM Overtime Notice: Check Out Pending',
        body: 'Office ended at 6:00 PM. Don\'t forget to punch out when leaving!',
      ),
      (
        id: NotificationConstants.eveningDepartureAlarm715,
        hour: 19,
        minute: 15,
        title: '🚨 7:15 PM Urgent: Did you punch Check-Out?',
        body: 'You haven\'t checked out yet today. Tap to punch departure now!',
      ),
      (
        id: NotificationConstants.eveningDepartureAlarm730,
        hour: 19,
        minute: 30,
        title: '🚪 7:30 PM Evening Departure Sentinel',
        body: 'Remember to check out before travelling away from office!',
      ),
      (
        id: NotificationConstants.eveningDepartureAlarm800,
        hour: 20,
        minute: 0,
        title: '🌙 8:00 PM Night Check-Out Alert',
        body: 'Overtime duty completed? Tap to submit your departure punch.',
      ),
    ];

    const androidDetails = AndroidNotificationDetails(
      NotificationConstants.officeChannelId,
      NotificationConstants.officeChannelName,
      channelDescription: NotificationConstants.officeChannelDesc,
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.public,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          NotificationConstants.actionCheckOutNow,
          '⚡ Check Out Now',
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
      ),
    );

    for (final wd in eveningWatchdogs) {
      var scheduledDate = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        wd.hour,
        wd.minute,
      );

      if (scheduledDate.isBefore(now)) {
        scheduledDate = scheduledDate.add(const Duration(days: 1));
      }

      try {
        await _notificationsPlugin.zonedSchedule(
          id: wd.id,
          title: wd.title,
          body: wd.body,
          scheduledDate: scheduledDate,
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
        );
        debugPrint('Evening watchdog [${wd.hour}:${wd.minute}] scheduled for $scheduledDate');
      } catch (e) {
        debugPrint('Error scheduling evening watchdog (${wd.id}): $e');
      }
    }
  }

  /// Cancels all scheduled evening watchdogs
  Future<void> cancelEveningOfficeWatchdogs() async {
    await _notificationsPlugin.cancel(id: NotificationConstants.eveningDepartureAlarm555);
    await _notificationsPlugin.cancel(id: NotificationConstants.eveningDepartureAlarm600);
    await _notificationsPlugin.cancel(id: NotificationConstants.eveningDepartureAlarm605);
    await _notificationsPlugin.cancel(id: NotificationConstants.eveningDepartureAlarm610);
    await _notificationsPlugin.cancel(id: NotificationConstants.eveningDepartureAlarm615);
    await _notificationsPlugin.cancel(id: NotificationConstants.eveningDepartureAlarm630);
    await _notificationsPlugin.cancel(id: NotificationConstants.eveningDepartureAlarm700);
    await _notificationsPlugin.cancel(id: NotificationConstants.eveningDepartureAlarm715);
    await _notificationsPlugin.cancel(id: NotificationConstants.eveningDepartureAlarm730);
    await _notificationsPlugin.cancel(id: NotificationConstants.eveningDepartureAlarm800);
    debugPrint('Evening departure watchdogs cancelled.');
  }

  /// Schedules micro-flashcard study nudges during office break periods (1:15 PM lunch and 4:30 PM tea break)
  /// Non-intrusive (no sound, soft priority) so work is never disturbed while BCS revision continues.
  Future<void> scheduleOfficeDowntimeFlashcards() async {
    final now = tz.TZDateTime.now(tz.local);

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

  /// Instant test/manual trigger for the meal reminder notification
  Future<void> showInstantDinnerReminder() async {
    const androidDetails = AndroidNotificationDetails(
      NotificationConstants.mealChannelId,
      NotificationConstants.mealChannelName,
      channelDescription: NotificationConstants.mealChannelDesc,
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.public,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          NotificationConstants.actionMealYes,
          '✓ Yes, Count Me In',
          showsUserInterface: false,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          NotificationConstants.actionMealNo,
          '✗ No, Skip',
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
      ),
    );

    await _notificationsPlugin.show(
      id: NotificationConstants.mealNotificationId,
      title: '🍽️ Office Dinner Confirmation Cutoff',
      body: 'Daily meal confirmation deadline is approaching! Will you have dinner at the office today?',
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
