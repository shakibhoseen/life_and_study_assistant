import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/services/ai/gemini_ai_service.dart';
import 'core/database/database_provider.dart';
import 'core/services/ai/gemini_result_cache.dart';
import 'core/services/export/auto_backup_service.dart';
import 'core/services/background/lunch_sentinel_service.dart';
import 'core/services/background/office_sentinel_service.dart';
import 'core/services/background/wifi_monitor_service.dart';
import 'core/services/background/workmanager_service.dart';
import 'core/services/home_widget_service.dart';
import 'core/services/study_widget_service.dart';
import 'features/live_mcq/presentation/screens/live_mcq_screen.dart';
import 'features/mistake_notebook/presentation/screens/mistake_notebook_screen.dart';
import 'core/services/notification/notification_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/theme/ui_style_provider.dart';
import 'features/home/presentation/screens/home_shell_screen.dart';
import 'features/live_mcq/presentation/widgets/floating_bubble_overlay.dart';

/// Top-level entry point required by flutter_overlay_window.
/// Must be declared directly in lib/main.dart so Dart VM finds it by name.
@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme.copyWith(
        scaffoldBackgroundColor: Colors.transparent,
      ),
      home: const FloatingBubbleOverlay(),
    ),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load .env configuration if present
  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    debugPrint('.env file not loaded: $e');
  }

  // 1. Initialize Local Notifications & Create Channels
  await NotificationService.instance.init();

  // 2. Schedule Daily 5:00 PM Steadfast Lunch Cutoff Reminder (1 hour before 6:00 PM cutoff)
  await NotificationService.instance.scheduleDailyLunchCutoffReminder();

  // 2.1 Schedule Morning 9:00 AM - 9:15 AM Late Prevention Watchdogs (Exact Alarms)
  await NotificationService.instance.scheduleMorningOfficeWatchdogs();

  // 2.2 Schedule Office Downtime Micro-Study Nudges (1:15 PM Lunch & 4:30 PM Tea Break)
  await NotificationService.instance.scheduleOfficeDowntimeFlashcards();

  // 2.3 Cancel Static Evening Alarms so Overtime work is never interrupted
  await NotificationService.instance.cancelEveningOfficeWatchdogs();

  // 2.4 Schedule Daily 12:25 PM Lunch Serving Sentinel Trigger
  await NotificationService.instance.scheduleDailyLunchTrackingTrigger();
  await LunchSentinelService.instance.init();
  await LunchSentinelService.instance.checkAndTriggerLunchSentinelIfNeeded();

  // 2.5 Schedule Daily LiveMCQ Morning Syllabus Nudge & Evening Score Prompt
  await NotificationService.instance.scheduleLiveMcqDailyNudge();
  await NotificationService.instance.scheduleLiveMcqScorePrompt();

  // 3. Initialize High-Precision Office Sentinel (Active only until Check-In/Out)
  await OfficeSentinelService.instance.init();
  await OfficeSentinelService.instance.checkAndTriggerSentinelIfNeeded();

  // 4. Start Background Wi-Fi SSID Change Monitor
  await WifiMonitorService.instance.startMonitoring();

  // 4. Initialize Background Watchdog WorkManager
  await WorkmanagerService.instance.init();

  // 5. Initialize Gemini AI Service
  await GeminiAiService.instance.init();

  // 6. Give back the space the old preference-stored AI replies still take.
  // They can never be served again, and they sit in a file Android reads in
  // full at every launch. Not awaited: nothing on screen depends on it.
  unawaited(GeminiResultCache.instance.sweepLegacyEntries());

  // 7. Push initial snapshot to native Android Home Screen Widget
  HomeWidgetService.init();
  unawaited(HomeWidgetService.syncCurrentDataToWidget(fetchFromNetwork: false));

  // 8. Preload theme mode and dark preset to eliminate startup flicker
  ThemeModeNotifier.initialMode =
      await ThemeModeNotifier.loadInitialThemeMode();
  DarkThemePresetNotifier.initialPreset =
      await DarkThemePresetNotifier.loadInitialPreset();
  AppUiStyleNotifier.initialStyle = await AppUiStyleNotifier.loadInitialStyle();

  runApp(const ProviderScope(child: LifeAndStudyApp()));
}

class LifeAndStudyApp extends ConsumerStatefulWidget {
  const LifeAndStudyApp({super.key});

  @override
  ConsumerState<LifeAndStudyApp> createState() => _LifeAndStudyAppState();
}

class _LifeAndStudyAppState extends ConsumerState<LifeAndStudyApp>
    with WidgetsBindingObserver {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(AutoBackupService.runIfDue(db: ref.read(appDatabaseProvider)));

    // The study widgets read figures out of this database, so the service is
    // handed the scope's instance rather than opening its own.
    StudyWidgetService.attach(ref.read(appDatabaseProvider));
    StudyWidgetService.pendingRoute.addListener(_openPendingRoute);
  }

  /// Takes a widget tap to the screen it named.
  void _openPendingRoute() {
    final route = StudyWidgetService.pendingRoute.value;
    if (route == null) return;
    StudyWidgetService.pendingRoute.value = null;

    final screen = switch (route) {
      '/mistake_notebook' => const MistakeNotebookScreen(),
      '/live_mcq' => const LiveMcqScreen(),
      // An unknown route is not worth guessing at; the app opens as usual.
      _ => null,
    };
    if (screen == null) return;

    navigatorKey.currentState?.push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }

  @override
  void dispose() {
    StudyWidgetService.pendingRoute.removeListener(_openPendingRoute);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(OfficeSentinelService.instance.checkAndTriggerSentinelIfNeeded());
      // Coming back to the app is also when the study figures are most likely
      // to be stale, and when a widget tap may be waiting to be honoured.
      unawaited(StudyWidgetService.refresh());
      unawaited(StudyWidgetService.consumePendingRoute());
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final darkTheme = ref.watch(currentDarkThemeProvider);

    return MaterialApp(
      title: 'Life & Study Assistant',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      home: const HomeShellScreen(),
    );
  }
}
