import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/services/ai/gemini_ai_service.dart';
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

  runApp(const ProviderScope(child: LifeAndStudyApp()));
}

class LifeAndStudyApp extends ConsumerWidget {
  const LifeAndStudyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'Life & Study Assistant',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: const HomeShellScreen(),
    );
  }
}
