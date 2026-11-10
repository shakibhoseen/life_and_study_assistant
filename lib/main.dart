import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/services/ai/gemini_ai_service.dart';
import 'core/database/database_provider.dart';
import 'core/services/ai/gemini_result_cache.dart';
import 'core/services/export/auto_backup_service.dart';
import 'core/services/background/wifi_monitor_service.dart';
import 'core/services/background/workmanager_service.dart';
import 'core/services/notification/notification_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
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

  // 1. Initialize Local Notifications & Create Channels
  await NotificationService.instance.init();

  // 2. Schedule Daily 4:00 PM Dinner Confirmation Reminder
  await NotificationService.instance.scheduleDailyDinnerReminder();

  // 3. Start Background Wi-Fi SSID Change Monitor
  await WifiMonitorService.instance.startMonitoring();

  // 4. Initialize Background Watchdog WorkManager
  await WorkmanagerService.instance.init();

  // 5. Initialize Gemini AI Service
  await GeminiAiService.instance.init();

  // 6. Give back the space the old preference-stored AI replies still take.
  // They can never be served again, and they sit in a file Android reads in
  // full at every launch. Not awaited: nothing on screen depends on it.
  unawaited(GeminiResultCache.instance.sweepLegacyEntries());

  // 6. Preload theme mode and dark preset to eliminate startup flicker
  ThemeModeNotifier.initialMode =
      await ThemeModeNotifier.loadInitialThemeMode();
  DarkThemePresetNotifier.initialPreset =
      await DarkThemePresetNotifier.loadInitialPreset();

  runApp(const ProviderScope(child: LifeAndStudyApp()));
}

class LifeAndStudyApp extends ConsumerStatefulWidget {
  const LifeAndStudyApp({super.key});

  @override
  ConsumerState<LifeAndStudyApp> createState() => _LifeAndStudyAppState();
}

class _LifeAndStudyAppState extends ConsumerState<LifeAndStudyApp> {
  @override
  void initState() {
    super.initState();
    // A backup nobody has to remember. At most one a day, written beside the
    // manual ones, and never waited on — the app opens while it happens.
    //
    // Here rather than in main() so it borrows the one database connection
    // the app already has, instead of opening a second one against the same
    // file at the moment everything else is starting.
    // Not tied to the first frame. Measured on a real phone: launched with
    // the screen off, or held behind a permission dialog, no frame is ever
    // produced and a post-frame callback simply never fires — so the backup
    // would quietly not happen on exactly the launches nobody is watching.
    unawaited(AutoBackupService.runIfDue(db: ref.read(appDatabaseProvider)));
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final darkTheme = ref.watch(currentDarkThemeProvider);

    return MaterialApp(
      title: 'Life & Study Assistant',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      home: const HomeShellScreen(),
    );
  }
}
