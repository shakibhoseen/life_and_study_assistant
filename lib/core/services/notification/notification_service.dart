import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../../config/notification_constants.dart';
import 'notification_action_handler.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  Future<void> init() async {
    if (_isInitialized) return;

    tz.initializeTimeZones();

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
      playSound: false,
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

  /// Schedules daily recurring dinner confirmation notification (Default 4:00 PM)
  /// with actionable notification buttons in tray: [Yes, Count Me In] and [No, Skip]
  Future<void> scheduleDailyDinnerReminder({
    int hour = 16,
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
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
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
          '✓ Remembered (+Interval)',
          showsUserInterface: false,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          NotificationConstants.actionSpacedForgot,
          '✗ Forgot (Reset to 1d)',
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
