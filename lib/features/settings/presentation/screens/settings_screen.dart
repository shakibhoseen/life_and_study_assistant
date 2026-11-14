import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/config/notification_constants.dart';

import '../../../spaced_repetition/presentation/providers/spaced_repetition_provider.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/database/database_provider.dart';
import '../../../../core/services/attendance/packly_attendance_service.dart';
import '../../../../core/services/background/wifi_monitor_service.dart';
import '../../../../core/services/background/workmanager_service.dart';
import '../../../../core/services/notification/notification_service.dart';

import 'package:geolocator/geolocator.dart';
import 'package:life_and_study_assistant/features/dashboard/presentation/providers/office_portal_provider.dart';
import 'package:life_and_study_assistant/features/dashboard/presentation/screens/office_portal_screen.dart';

import '../widgets/backup_restore_card.dart';
import '../widgets/theme_selector_card.dart';
import '../widgets/ui_style_selector_card.dart';
import '../widgets/weakness_healer_toggle_card.dart';

import 'package:life_and_study_assistant/features/live_mcq/presentation/providers/exam_schedule_provider.dart';

import '../providers/settings_provider.dart';
import '../widgets/gemini_usage_monitor_card.dart';
import '../widgets/ai_cache_card.dart';
import '../widgets/study_data_cleanup_card.dart';
import '../../../../core/theme/fluent_tokens.dart';
import '../../../../core/widgets/animated_premium_background.dart';
import '../../../../core/widgets/premium_glass_card.dart';
import '../../../../core/widgets/premium_ui_kit.dart';
import 'attendance_test_lab_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final TextEditingController _ssidController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _customSsidController = TextEditingController();
  StreamSubscription<OfficeConnectionState>? _wifiStateSubscription;
  bool _isInitialized = false;
  bool _isValidatingKey = false;
  bool _isEditingApiKey = false;
  bool _showRawKey = false;
  bool _flashcardPushEnabled = false;
  int _flashcardPushMinutes = 60;
  int _flashcardQueuedCount = 0;
  int _flashcardSlotsPerDay = 0;
  int _flashcardStartHour = NotificationConstants.flashcardPushDefaultStartHour;
  int _flashcardEndHour = NotificationConstants.flashcardPushDefaultEndHour;
  bool _isPinging = false;
  bool _autoCheckInEnabled = true;
  bool _autoCheckOutEnabled = true;
  bool _lateWarningEnabled = true;
  bool _isBatteryOptIgnored = false;
  bool _simulationMode = false;
  bool _officeDowntimeStudyEnabled = true;
  String _officeAddress = 'ZaviSoft Office, Dhaka';
  String _bannerDisplayMode = 'contextual';

  // Packly Attendance Credentials & Ping
  String _packlyEmail = 'shakibhossen100@gmail.com';
  bool _isPacklyPinging = false;

  // Steadfast Lunch Credentials & Live State
  String _lunchEmail = 'shakibhossen100@gmail.com';
  bool? _lunchTodayBooked;
  bool? _lunchTomorrowBooked;
  bool _lunchAutoReminderEnabled = true;

  @override
  void initState() {
    super.initState();
    _wifiStateSubscription = WifiMonitorService.instance.officeStateStream
        .listen((_) {
          if (mounted) setState(() {});
        });
    // Immediately check status on screen load
    WifiMonitorService.instance.checkCurrentWifiStatus().then((_) {
      if (mounted) setState(() {});
    });
    _loadFlashcardPushPrefs();
    _loadPacklySettings();
  }

  Future<void> _loadPacklySettings() async {
    final prefs = await SharedPreferences.getInstance();
    final isIgnored = await Permission.ignoreBatteryOptimizations.isGranted;
    if (!mounted) return;
    setState(() {
      _packlyEmail =
          prefs.getString(NotificationConstants.prefPacklyEmail) ??
          'shakibhossen100@gmail.com';
      _lunchEmail =
          prefs.getString(NotificationConstants.prefLunchEmail) ??
          'shakibhossen100@gmail.com';
      _lunchAutoReminderEnabled =
          prefs.getBool(NotificationConstants.prefLunchAutoReminderEnabled) ??
          true;
      _lunchTodayBooked = prefs.getBool(
        NotificationConstants.prefLunchLastKnownTodayBooked,
      );
      _lunchTomorrowBooked = prefs.getBool(
        NotificationConstants.prefLunchLastKnownTomorrowBooked,
      );
      _autoCheckInEnabled =
          prefs.getBool(NotificationConstants.prefAutoCheckInEnabled) ?? true;
      _autoCheckOutEnabled =
          prefs.getBool(NotificationConstants.prefAutoCheckOutEnabled) ?? true;
      _lateWarningEnabled =
          prefs.getBool(NotificationConstants.prefLateWarningEnabled) ?? true;
      _simulationMode =
          prefs.getBool(NotificationConstants.prefPacklySimulationMode) ??
          false;
      _officeDowntimeStudyEnabled =
          prefs.getBool(
            NotificationConstants.prefOfficeDowntimeFlashcardEnabled,
          ) ??
          true;
      _officeAddress =
          prefs.getString(NotificationConstants.prefOfficeAddress) ??
          'ZaviSoft Office, Dhaka';
      _bannerDisplayMode =
          prefs.getString(NotificationConstants.prefOfficeBannerMode) ??
          'contextual';
      _isBatteryOptIgnored = isIgnored;
    });
  }

  Future<void> _loadFlashcardPushPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _flashcardPushEnabled =
          prefs.getBool(NotificationConstants.prefFlashcardPushEnabled) ??
          false;
      _flashcardQueuedCount =
          prefs.getInt(NotificationConstants.prefFlashcardQueuedCount) ?? 0;
      _flashcardSlotsPerDay =
          prefs.getInt(NotificationConstants.prefFlashcardSlotsPerDay) ?? 0;
      _flashcardPushMinutes =
          prefs.getInt(
            NotificationConstants.prefFlashcardPushIntervalMinutes,
          ) ??
          60;
      _flashcardStartHour =
          prefs.getInt(NotificationConstants.prefFlashcardPushStartHour) ??
          NotificationConstants.flashcardPushDefaultStartHour;
      _flashcardEndHour =
          prefs.getInt(NotificationConstants.prefFlashcardPushEndHour) ??
          NotificationConstants.flashcardPushDefaultEndHour;
    });
  }

  @override
  void dispose() {
    _wifiStateSubscription?.cancel();
    _ssidController.dispose();
    _apiKeyController.dispose();
    _customSsidController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsNotifierProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Automation & Settings',
          style: FluentType.bodyStrong,
        ),
      ),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
        data: (settings) {
          if (!_isInitialized) {
            _ssidController.text = settings.officeWifiSsid;
            _apiKeyController.text = settings.geminiApiKey;
            _isInitialized = true;
          }

          final currentSsid = WifiMonitorService.instance.currentSsid;
          final hasKey = settings.geminiApiKey.isNotEmpty;

          return Stack(
            children: [
              const Positioned.fill(
                child: AnimatedGradientBackground(child: SizedBox.expand()),
              ),
              const FloatingOrb(top: -30, right: -50, size: 280, opacity: 0.14),
              const FloatingOrb(
                bottom: 100,
                left: -60,
                size: 240,
                opacity: 0.11,
              ),
              ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: FluentSpacing.m,
                ),
                children: [
                  // 1. Office Wi-Fi & Schedule Configuration
                  _buildSectionHeader(
                    'Office Attendance & Schedule',
                    Icons.business_rounded,
                  ),
                  _buildOfficeWifiSection(settings, currentSsid),
                  const SizedBox(height: FluentSpacing.xl),

                  // 2. Zavisoft Packly Attendance Portal
                  _buildSectionHeader(
                    'Zavisoft Packly Attendance Portal',
                    Icons.fingerprint_rounded,
                  ),
                  _buildPacklyAutomationSection(),
                  const SizedBox(height: FluentSpacing.xl),

                  // 3. Steadfast Office Lunch / Meal Portal
                  _buildSectionHeader(
                    'Steadfast Office Lunch / Meal Portal',
                    Icons.lunch_dining_rounded,
                  ),
                  _buildSteadfastLunchSection(),
                  const SizedBox(height: FluentSpacing.xl),

                  // 3. Gemini AI Configuration (Premium Credential Box)
                  _buildSectionHeader(
                    'Gemini AI Engine & Credentials',
                    Icons.auto_awesome,
                  ),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: FluentRadius.cardBorder,
                      side: FluentStroke.side(Theme.of(context).brightness),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(FluentSpacing.l),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Model Engine Selector Dropdown
                          Text(
                            'AI Engine Model:',
                            style: FluentType.bodyStrong.copyWith(
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: FluentSpacing.s),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: FluentSpacing.m,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.onSurface
                                  .withValues(alpha: 0.04),
                              borderRadius: FluentRadius.controlBorder,
                              border: Border.all(
                                color: FluentStroke.card(
                                  Theme.of(context).brightness,
                                ),
                                width: FluentStroke.width,
                              ),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                isExpanded: true,
                                borderRadius: FluentRadius.cardBorder,
                                style: FluentType.body.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface,
                                ),
                                dropdownColor: Theme.of(context)
                                    .colorScheme
                                    .surface,
                                value:
                                    ([
                                      'gemini-flash-lite-latest',
                                      'gemini-flash-latest',
                                      'gemini-pro-latest',
                                    ].contains(settings.geminiModel))
                                    ? settings.geminiModel
                                    : 'gemini-flash-lite-latest',
                                items: const [
                                  DropdownMenuItem(
                                    value: 'gemini-flash-lite-latest',
                                    child: Text(
                                      '⚡ Gemini Flash Lite (Fastest & 100% Free - Recommended)',
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'gemini-flash-latest',
                                    child: Text(
                                      '🚀 Gemini Flash Latest (High Intelligence)',
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'gemini-pro-latest',
                                    child: Text(
                                      '🧠 Gemini Pro Latest (Requires Google Cloud Billing)',
                                    ),
                                  ),
                                ],
                                onChanged: (newModel) {
                                  if (newModel != null) {
                                    ref
                                        .read(settingsNotifierProvider.notifier)
                                        .updateGeminiModel(newModel);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Switched AI engine to $newModel',
                                        ),
                                      ),
                                    );
                                  }
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: FluentSpacing.s),
                          Text(
                            settings.geminiModel == 'gemini-pro-latest'
                                ? '✨ Pro Model active: Providing deepest reasoning (Requires Google Cloud billing enabled on project).'
                                : '⚡ Flash Lite active: 100% free daily quota, ultra-fast response for LiveMCQ routines & AI mentor.',
                            style: FluentType.caption.copyWith(
                              color: Theme.of(context).colorScheme.onSurface
                                  .withValues(alpha: 0.65),
                            ),
                          ),
                          const SizedBox(height: FluentSpacing.m),

                          // Whether the chosen model may be swapped out. Here
                          // rather than buried in a scanner, because it is about
                          // the model chosen just above it.
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'ব্যস্ত থাকলে অন্য মডেল ব্যবহার করুক',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: FluentType.bodyStrong.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: FluentSpacing.xxs),
                                    Text(
                                      settings.allowModelFallback
                                          ? 'সার্ভার ব্যস্ত হলে দুর্বল মডেলে উত্তর আসতে পারে — '
                                                'স্ক্রিনে তা বলা থাকবে না'
                                          : 'আপনার বাছাই করা মডেলই ব্যবহার হবে — '
                                                'ব্যস্ত থাকলে অপেক্ষা করে আবার চেষ্টা করবে',
                                      style: FluentType.caption.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.65),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: FluentSpacing.s),
                              Switch(
                                value: settings.allowModelFallback,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                onChanged: (v) => ref
                                    .read(settingsNotifierProvider.notifier)
                                    .setAllowModelFallback(v),
                              ),
                            ],
                          ),
                          const SizedBox(height: FluentSpacing.l),

                          // API Key Presentation: Either Secured Connected Box OR Input Box
                          if (hasKey && !_isEditingApiKey)
                            _buildConnectedKeyBox(
                              settings.geminiApiKey,
                              settings.geminiModel,
                            )
                          else
                            _buildApiKeyInputBox(settings),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: FluentSpacing.xl),

                  // Real-time Gemini API Quota & Usage Monitor
                  const GeminiUsageMonitorCard(),
                  const SizedBox(height: FluentSpacing.xl),

                  // What the result cache is holding, and the means to empty it.
                  const AiCacheCard(),
                  const SizedBox(height: FluentSpacing.xl),

                  // Auto-Weakness Healer & Micro Drills Control
                  _buildSectionHeader(
                    'Auto-Weakness Healer Engine',
                    Icons.healing_rounded,
                  ),
                  WeaknessHealerToggleCard(settings: settings),
                  const SizedBox(height: FluentSpacing.xl),

                  _buildSectionHeader('ফ্ল্যাশকার্ড পুশ', Icons.style_outlined),
                  _buildFlashcardPushCard(),
                  const SizedBox(height: FluentSpacing.xl),

                  // 4. Data Backup & Restore
                  const BackupRestoreCard(),
                  const StudyDataCleanupCard(),
                  const SizedBox(height: FluentSpacing.xl),

                  // Visual Comfort & Theme Mode
                  _buildSectionHeader(
                    'Visual Comfort & Display Theme',
                    Icons.palette_outlined,
                  ),
                  const ThemeSelectorCard(),
                  const SizedBox(height: FluentSpacing.s),
                  const UiStyleSelectorCard(),
                  const SizedBox(height: FluentSpacing.xl),

                  // 5. Permissions & Reset
                  _buildSectionHeader(
                    'System & State Control',
                    Icons.settings_suggest_rounded,
                  ),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: FluentRadius.cardBorder,
                      side: FluentStroke.side(Theme.of(context).brightness),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          leading: PremiumIconBadge(
                            icon: Icons.notifications_active,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          title: const Text(
                            'Request Notification & Location Permissions',
                          ),
                          subtitle: const Text(
                            'Ensure exact alarms, heads-up banner & Wi-Fi SSID access',
                          ),
                          trailing: const Icon(
                            Icons.arrow_forward_ios,
                            size: 14,
                          ),
                          onTap: () async {
                            await NotificationService.instance
                                .requestPermissions();
                            final granted = await WifiMonitorService.instance
                                .requestWifiLocationPermissions();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    granted
                                        ? 'Notification & Location permissions active!'
                                        : 'Please allow Location permission to detect Wi-Fi names.',
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: PremiumIconBadge(
                            icon: Icons.restart_alt,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          title: const Text(
                            'Reset Today’s Check-In & Dinner Status',
                          ),
                          subtitle: const Text(
                            'Allows re-triggering for today',
                          ),
                          onTap: () async {
                            await ref
                                .read(settingsNotifierProvider.notifier)
                                .updateCheckInStatus('Pending');
                            await ref
                                .read(settingsNotifierProvider.notifier)
                                .updateMealResponse('Pending');
                            await WifiMonitorService.instance
                                .checkCurrentWifiStatus();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Today’s status reset to Pending. Connect to Wi-Fi to test!',
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: PremiumIconBadge(
                            icon: Icons.delete_sweep_outlined,
                            color: const Color(0xFFF59E0B),
                          ),
                          title: const Text('Clear All Exam Schedules'),
                          subtitle: const Text(
                            'Wipe sample or old routines to start fresh',
                          ),
                          onTap: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Clear All Exam Schedules?'),
                                content: const Text(
                                  'This will delete all saved LiveMCQ exam routines. You can then upload or import your own routine PDF/image.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: Text(
                                      'Clear',
                                      style: FluentType.body.copyWith(
                                        color: Colors.red,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true) {
                              await ref
                                  .read(appDatabaseProvider)
                                  .clearAllExams();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('All exam routines cleared.'),
                                  ),
                                );
                              }
                            }
                          },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: PremiumIconBadge(
                            icon: Icons.folder_delete_outlined,
                            color: const Color(0xFFF59E0B),
                          ),
                          title: const Text('Delete Specific Program Track'),
                          subtitle: const Text(
                            'Remove all exams of a single track/tag without affecting others',
                          ),
                          onTap: () => _showDeleteTrackDialog(context),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: PremiumIconBadge(
                            icon: Icons.cleaning_services_outlined,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          title: const Text('Clear All Weak Topics'),
                          subtitle: const Text('Remove all weak point entries'),
                          onTap: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Clear All Weak Topics?'),
                                content: const Text(
                                  'This will delete all weak topic entries from the database.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: Text(
                                      'Clear',
                                      style: FluentType.body.copyWith(
                                        color: Colors.red,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true) {
                              await ref
                                  .read(appDatabaseProvider)
                                  .clearAllWeakTopics();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('All weak topics cleared.'),
                                  ),
                                );
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  /// Secured Premium Credential Box (Shown when key is saved & active)
  Widget _buildConnectedKeyBox(String apiKey, String modelName) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    // Green here is status: the key is connected and verified.
    const successColor = Color(0xFF10B981);
    final maskedKey = apiKey.length > 12
        ? '${apiKey.substring(0, 7)}••••••••••••••••${apiKey.substring(apiKey.length - 4)}'
        : '••••••••••••••••';

    return Container(
      padding: const EdgeInsets.all(FluentSpacing.l),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? theme.cardColor,
        borderRadius: FluentRadius.cardBorder,
        border: Border.all(
          color: successColor.withValues(alpha: 0.4),
          width: FluentStroke.width,
        ),
        boxShadow: FluentElevation.card(brightness),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: FluentSpacing.s),
                    Flexible(
                      child: Text(
                        'Connected & Active',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FluentType.bodyStrong.copyWith(
                          color: successColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: FluentSpacing.s),
              const PremiumTag(label: '✓ Verified', color: successColor),
            ],
          ),
          const SizedBox(height: FluentSpacing.m),
          // Masked Credential Box
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: FluentSpacing.m,
              vertical: FluentSpacing.s,
            ),
            decoration: BoxDecoration(
              // A deliberately dark plate: the key reads as a secured value.
              color: const Color(0xFF0F172A),
              borderRadius: FluentRadius.controlBorder,
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.shield_outlined,
                  color: successColor,
                  size: 18,
                ),
                const SizedBox(width: FluentSpacing.m),
                Expanded(
                  child: Text(
                    _showRawKey ? apiKey : maskedKey,
                    // Sits on the dark secured plate above.
                    style: FluentType.caption.copyWith(
                      fontFamily: 'monospace',
                      color: const Color(0xFFE2E8F0),
                      letterSpacing: 1.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Icon(
                    _showRawKey ? Icons.visibility_off : Icons.visibility,
                    color: Colors.white70,
                    size: 18,
                  ),
                  tooltip: _showRawKey ? 'Mask Key' : 'Reveal Key',
                  onPressed: () {
                    setState(() => _showRawKey = !_showRawKey);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: FluentSpacing.s),
          Text(
            '✓ Secured in local device storage. Hidden from plain view.',
            style: FluentType.caption.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: FluentSpacing.m),
          // Action Buttons: Ping Test, Change, and Remove
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: _isPinging
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.speed, size: 16),
                  label: Text(
                    _isPinging ? 'Pinging...' : 'Test Ping',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FluentType.caption,
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: FluentSpacing.s,
                    ),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: FluentRadius.controlBorder,
                    ),
                  ),
                  onPressed: _isPinging
                      ? null
                      : () => _pingTestApiKey(apiKey, modelName),
                ),
              ),
              const SizedBox(width: FluentSpacing.s),
              OutlinedButton.icon(
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: Text('Change', style: FluentType.caption),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FluentSpacing.m,
                    vertical: FluentSpacing.s,
                  ),
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(
                    borderRadius: FluentRadius.controlBorder,
                  ),
                ),
                onPressed: () {
                  _apiKeyController.text = apiKey;
                  setState(() => _isEditingApiKey = true);
                },
              ),
              const SizedBox(width: FluentSpacing.s),
              IconButton.outlined(
                icon: Icon(Icons.delete_outline, color: scheme.error, size: 18),
                tooltip: 'Remove Key',
                style: IconButton.styleFrom(
                  side: BorderSide(
                    color: scheme.error.withValues(alpha: 0.4),
                    width: FluentStroke.width,
                  ),
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(
                    borderRadius: FluentRadius.controlBorder,
                  ),
                ),
                onPressed: () => _confirmRemoveApiKey(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Input Credential Box (Shown when no key is set or user clicked Change)
  Widget _buildApiKeyInputBox(SettingsState settings) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(FluentSpacing.l),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? theme.cardColor,
        borderRadius: FluentRadius.cardBorder,
        border: Border.all(
          color: FluentStroke.card(theme.brightness),
          width: FluentStroke.width,
        ),
        boxShadow: FluentElevation.card(theme.brightness),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'Enter Gemini API Key',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FluentType.bodyStrong.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
              ),
              if (_isEditingApiKey)
                TextButton(
                  onPressed: () {
                    setState(() => _isEditingApiKey = false);
                  },
                  child: Text('Cancel', style: FluentType.caption),
                ),
            ],
          ),
          const SizedBox(height: FluentSpacing.xs),
          Text(
            'Obtain a free key from Google AI Studio (ai.google.dev). 1,500 free calls/day.',
            style: FluentType.caption.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: FluentSpacing.m),
          TextField(
            controller: _apiKeyController,
            obscureText: !_showRawKey,
            decoration: InputDecoration(
              labelText: 'Google AI Gemini API Key',
              hintText: 'AIzaSy...',
              isDense: true,
              prefixIcon: const Icon(Icons.vpn_key_rounded, size: 18),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      _showRawKey ? Icons.visibility_off : Icons.visibility,
                      size: 18,
                    ),
                    onPressed: () => setState(() => _showRawKey = !_showRawKey),
                  ),
                  IconButton(
                    icon: const Icon(Icons.content_paste, size: 18),
                    tooltip: 'Paste from clipboard',
                    onPressed: () async {
                      final data = await Clipboard.getData(
                        Clipboard.kTextPlain,
                      );
                      if (data?.text != null && data!.text!.isNotEmpty) {
                        _apiKeyController.text = data.text!.trim();
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: FluentSpacing.m),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: _isValidatingKey
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.lock_outline, size: 16),
              label: Text(
                _isValidatingKey
                    ? 'Testing Connection...'
                    : 'Save & Secure Key',
              ),
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: FluentSpacing.m),
                shape: RoundedRectangleBorder(
                  borderRadius: FluentRadius.controlBorder,
                ),
              ),
              onPressed: _isValidatingKey
                  ? null
                  : () => _saveAndValidateKey(settings.geminiModel),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveAndValidateKey(String modelName) async {
    final key = _apiKeyController.text.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an API Key first.')),
      );
      return;
    }

    setState(() => _isValidatingKey = true);

    try {
      // 1. Save locally
      await ref.read(settingsNotifierProvider.notifier).updateGeminiApiKey(key);

      // 2. Perform live ping test with auto-model fallback
      final candidates = [
        modelName,
        'gemini-flash-lite-latest',
        'gemini-3.5-flash-lite',
        'gemini-flash-latest',
      ];

      GenerateContentResponse? successResponse;
      String workingModel = modelName;
      Object? lastError;

      for (final candidate in candidates) {
        try {
          final testModel = GenerativeModel(model: candidate, apiKey: key);
          final response = await testModel.generateContent([
            Content.text('ping'),
          ]);
          successResponse = response;
          workingModel = candidate;
          break;
        } catch (e) {
          lastError = e;
          final errStr = e.toString().toLowerCase();
          if (errStr.contains('api_key_invalid') ||
              errStr.contains('api key not valid') ||
              errStr.contains('socketexception') ||
              errStr.contains('failed host lookup')) {
            rethrow;
          }
        }
      }

      if (successResponse == null) {
        throw lastError ??
            Exception('Could not connect to Gemini with any supported model.');
      }

      // If the originally selected model was deprecated/unavailable, auto-switch to working model
      if (workingModel != modelName) {
        await ref
            .read(settingsNotifierProvider.notifier)
            .updateGeminiModel(workingModel);
      }

      if (mounted) {
        setState(() {
          _isValidatingKey = false;
          _isEditingApiKey = false;
          _showRawKey = false;
        });

        final fallbackNotice = (workingModel != modelName)
            ? '\n\n💡 দ্রষ্টব্য: "$modelName" মডেলটি গুগল ডিসকন্টিনিউ করায় স্বয়ংক্রিয়ভাবে অ্যাক্টিভ মডেল "$workingModel"-এ সেট করা হয়েছে।'
            : '';

        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(
              Icons.check_circle,
              color: Color(0xFF10B981),
              size: 48,
            ),
            title: const Text('API Key Validated!'),
            content: Text(
              '✓ Successfully connected to Google Gemini API!\n\nEngine: $workingModel\nStatus: Active & Ready (200 OK)\nSample Reply: "${successResponse?.text?.trim() ?? "OK"}"$fallbackNotice',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Awesome'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isValidatingKey = false);
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(
              Icons.error_outline,
              color: Colors.redAccent,
              size: 48,
            ),
            title: const Text('Validation Failed'),
            content: Text(
              'Could not connect to Gemini with this key.\n\nError Message:\n$e\n\nPlease check:\n1. The key was copied completely from Google AI Studio.\n2. Your device is connected to the internet.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _pingTestApiKey(String apiKey, String modelName) async {
    setState(() => _isPinging = true);
    final stopwatch = Stopwatch()..start();

    try {
      final candidates = [
        modelName,
        'gemini-flash-lite-latest',
        'gemini-3.5-flash-lite',
        'gemini-flash-latest',
      ];

      GenerateContentResponse? successResponse;
      String workingModel = modelName;
      Object? lastError;

      for (final candidate in candidates) {
        try {
          final model = GenerativeModel(model: candidate, apiKey: apiKey);
          final response = await model.generateContent([Content.text('ping')]);
          successResponse = response;
          workingModel = candidate;
          break;
        } catch (e) {
          lastError = e;
          final errStr = e.toString().toLowerCase();
          if (errStr.contains('api_key_invalid') ||
              errStr.contains('api key not valid') ||
              errStr.contains('socketexception')) {
            rethrow;
          }
        }
      }

      stopwatch.stop();

      if (successResponse == null) {
        throw lastError ?? Exception('Ping failed');
      }

      if (workingModel != modelName) {
        await ref
            .read(settingsNotifierProvider.notifier)
            .updateGeminiModel(workingModel);
      }

      if (mounted) {
        setState(() => _isPinging = false);
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(
              Icons.check_circle,
              color: Color(0xFF10B981),
              size: 48,
            ),
            title: const Text('Connection Healthy!'),
            content: Text(
              '✓ Successfully reached Google Gemini API.\n\nLatency: ${stopwatch.elapsedMilliseconds} ms\nModel: $workingModel\nStatus: 200 OK\nSample Reply: "${successResponse?.text?.trim() ?? "OK"}"',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Done'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isPinging = false);
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(
              Icons.error_outline,
              color: Colors.redAccent,
              size: 48,
            ),
            title: const Text('Ping Failed'),
            content: Text('Error testing connection:\n\n$e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _confirmRemoveApiKey(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect Gemini API Key?'),
        content: const Text(
          'This will remove your API key from this device. The app will revert to intelligent offline rule-based mode.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Remove',
              style: FluentType.body.copyWith(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _apiKeyController.clear();
      await ref.read(settingsNotifierProvider.notifier).updateGeminiApiKey('');
      setState(() {
        _isEditingApiKey = false;
        _showRawKey = false;
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gemini API Key removed. Offline mode active.'),
          ),
        );
      }
    }
  }

  Widget _buildWeekdayChips(List<int> currentOffDays) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const days = [
      {'name': 'Sat', 'val': DateTime.saturday},
      {'name': 'Sun', 'val': DateTime.sunday},
      {'name': 'Mon', 'val': DateTime.monday},
      {'name': 'Tue', 'val': DateTime.tuesday},
      {'name': 'Wed', 'val': DateTime.wednesday},
      {'name': 'Thu', 'val': DateTime.thursday},
      {'name': 'Fri', 'val': DateTime.friday},
    ];

    return Wrap(
      spacing: FluentSpacing.s,
      runSpacing: FluentSpacing.s,
      children: days.map((d) {
        final val = d['val'] as int;
        final name = d['name'] as String;
        final isSelected = currentOffDays.contains(val);

        return FilterChip(
          label: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FluentType.caption.copyWith(
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              color: isSelected ? scheme.primary : scheme.onSurface,
            ),
          ),
          selected: isSelected,
          shape: RoundedRectangleBorder(
            borderRadius: FluentRadius.controlBorder,
            side: FluentStroke.side(theme.brightness),
          ),
          backgroundColor: theme.cardTheme.color ?? theme.cardColor,
          selectedColor: FluentLayer.subtle(scheme.primary, theme.brightness),
          checkmarkColor: scheme.primary,
          onSelected: (bool selected) {
            final updated = List<int>.from(currentOffDays);
            if (selected) {
              if (!updated.contains(val)) updated.add(val);
            } else {
              updated.remove(val);
            }
            ref.read(settingsNotifierProvider.notifier).updateOffDays(updated);
          },
        );
      }).toList(),
    );
  }

  Widget _buildOfficeWifiSection(SettingsState settings, String? currentSsid) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final configuredList = settings.officeWifiSsids;
    final isOfficeConnected = WifiMonitorService.isOfficeNetwork(
      currentSsid,
      settings.officeWifiSsid,
    );
    final isSsidHidden = WifiMonitorService.instance.isSsidHiddenByAndroid;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: FluentRadius.cardBorder,
        side: FluentStroke.side(Theme.of(context).brightness),
      ),
      child: Padding(
        padding: const EdgeInsets.all(FluentSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recognized Office Wi-Fi Networks',
              style: FluentType.bodyStrong.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: FluentSpacing.xs),
            Text(
              'Connect to ANY of these networks (e.g. Zavisoft or your Mac Hotspot SecretStar / Secreat Star) to trigger biometric check-in. Seamless 15s handoff prevents false check-outs when switching.',
              style: FluentType.caption.copyWith(
                color: Theme.of(context).colorScheme.onSurface
                    .withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: FluentSpacing.m),

            // Warning Banner when Android OS is hiding SSID due to missing Location Permission
            if (isSsidHidden) ...[
              Container(
                padding: const EdgeInsets.all(FluentSpacing.m),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF78350F).withValues(alpha: 0.25)
                      : const Color(0xFFFEF3C7),
                  borderRadius: FluentRadius.cardBorder,
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFFD97706).withValues(alpha: 0.4)
                        : const Color(0xFFFDE68A),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.location_off_rounded,
                          color: Color(0xFFD97706),
                          size: 20,
                        ),
                        const SizedBox(width: FluentSpacing.s),
                        Expanded(
                          child: Text(
                            'Wi-Fi Connected, but Android OS hid network name',
                            style: FluentType.caption.copyWith(
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? const Color(0xFFFDE68A)
                                  : const Color(0xFF92400E),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: FluentSpacing.xs),
                    Text(
                      'Modern Android (10+) requires Location Permission to read Wi-Fi SSIDs (like ZaviSoft or Secreat Star) for auto attendance check-in & check-out.',
                      style: FluentType.caption.copyWith(
                        color: isDark
                            ? const Color(0xFFFEF3C7)
                            : const Color(0xFF78350F),
                      ),
                    ),
                    const SizedBox(height: FluentSpacing.s),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD97706),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: FluentSpacing.s,
                            ),
                            textStyle: FluentType.caption.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          icon: const Icon(Icons.security, size: 14),
                          label: const Text('Grant Location Permission'),
                          onPressed: () async {
                            final granted = await WifiMonitorService.instance
                                .requestWifiLocationPermissions();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    granted
                                        ? 'Permission granted! Scanning Wi-Fi name...'
                                        : 'Please allow Location permission in App Settings.',
                                  ),
                                  action: !granted
                                      ? SnackBarAction(
                                          label: 'Settings',
                                          onPressed: openAppSettings,
                                        )
                                      : null,
                                ),
                              );
                            }
                            if (mounted) setState(() {});
                          },
                        ),
                        const SizedBox(width: FluentSpacing.s),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: FluentSpacing.s,
                            ),
                            foregroundColor: isDark
                                ? const Color(0xFFFDE68A)
                                : const Color(0xFF92400E),
                          ),
                          icon: const Icon(Icons.refresh, size: 14),
                          label: const Text('Retry', style: FluentType.caption),
                          onPressed: () async {
                            await WifiMonitorService.instance
                                .checkCurrentWifiStatus();
                            if (mounted) setState(() {});
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: FluentSpacing.s),
            ],

            // Real-time Connection Status Card
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: FluentSpacing.m,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: isOfficeConnected
                    ? (isDark
                          ? Colors.green.withValues(alpha: 0.15)
                          : const Color(0xFFECFDF5))
                    : (currentSsid != null && currentSsid.isNotEmpty)
                    ? (isDark
                          ? Colors.amber.withValues(alpha: 0.15)
                          : const Color(0xFFFFFBEB))
                    : isSsidHidden
                    ? (isDark
                          ? Colors.orange.withValues(alpha: 0.15)
                          : const Color(0xFFFFF7ED))
                    : Theme.of(context).colorScheme.onSurface,
                borderRadius: FluentRadius.cardBorder,
                border: Border.all(
                  color: isOfficeConnected
                      ? (isDark
                            ? Colors.green.withValues(alpha: 0.4)
                            : const Color(0xFFA7F3D0))
                      : (currentSsid != null && currentSsid.isNotEmpty)
                      ? (isDark
                            ? Colors.amber.withValues(alpha: 0.4)
                            : const Color(0xFFFDE68A))
                      : isSsidHidden
                      ? (isDark
                            ? Colors.orange.withValues(alpha: 0.4)
                            : const Color(0xFFFED7AA))
                      : Theme.of(context).colorScheme.onSurface
                            .withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isOfficeConnected
                        ? Icons.check_circle_rounded
                        : (currentSsid != null && currentSsid.isNotEmpty)
                        ? Icons.wifi_find_rounded
                        : isSsidHidden
                        ? Icons.wifi_password_rounded
                        : Icons.wifi_off_rounded,
                    size: 20,
                    color: isOfficeConnected
                        ? (isDark ? Colors.greenAccent : Colors.green.shade700)
                        : (currentSsid != null && currentSsid.isNotEmpty)
                        ? (isDark ? Colors.amberAccent : Colors.amber.shade800)
                        : isSsidHidden
                        ? (isDark
                              ? Colors.orangeAccent
                              : Colors.orange.shade800)
                        : (isDark ? Colors.blueGrey.shade200 : Colors.blueGrey),
                  ),
                  const SizedBox(width: FluentSpacing.s),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isOfficeConnected
                              ? '🟢 Connected: $currentSsid (Office)'
                              : (currentSsid != null && currentSsid.isNotEmpty)
                              ? '📶 Connected: $currentSsid'
                              : isSsidHidden
                              ? '⚠️ Wi-Fi Connected (SSID Hidden)'
                              : '⚪ Wi-Fi Disconnected / Mobile Data',
                          style: FluentType.caption.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isOfficeConnected
                                ? (isDark
                                      ? Colors.greenAccent
                                      : Colors.green.shade900)
                                : (currentSsid != null &&
                                      currentSsid.isNotEmpty)
                                ? (isDark
                                      ? Colors.amberAccent
                                      : Colors.amber.shade900)
                                : isSsidHidden
                                ? (isDark
                                      ? Colors.orangeAccent
                                      : Colors.orange.shade900)
                                : (isDark
                                      ? Colors.white70
                                      : Colors.blueGrey.shade800),
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        if (isSsidHidden)
                          Text(
                            'Grant location permission above to enable auto check-in',
                            style: FluentType.caption.copyWith(
                              color: Colors.deepOrange,
                            ),
                          )
                        else if (currentSsid != null &&
                            (currentSsid.toLowerCase().replaceAll(' ', '') ==
                                    'secretstar' ||
                                currentSsid.toLowerCase().replaceAll(' ', '') ==
                                    'secreatstar'))
                          Text(
                            '💻 Personal Mac Hotspot (Ultra-fast ethernet mode)',
                            style: FluentType.caption.copyWith(
                              color: Colors.green,
                            ),
                          )
                        else if (currentSsid != null &&
                            currentSsid.toLowerCase().contains('zavisoft'))
                          Text(
                            '🏢 Zavisoft Office Wi-Fi',
                            style: FluentType.caption.copyWith(
                              color: Colors.teal,
                            ),
                          )
                        else if (isOfficeConnected)
                          Text(
                            '🏢 Verified Office Network',
                            style: FluentType.caption.copyWith(
                              color: Colors.teal,
                            ),
                          )
                        else if (currentSsid != null && currentSsid.isNotEmpty)
                          Text(
                            'Not yet recognized as office network',
                            style: FluentType.caption.copyWith(
                              color: Theme.of(context).colorScheme.onSurface
                                  .withValues(alpha: 0.65),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (!isOfficeConnected &&
                      currentSsid != null &&
                      currentSsid.isNotEmpty)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: FluentSpacing.xs,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.add, size: 14),
                      label: Text(
                        'Add This',
                        style: FluentType.caption.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: () {
                        ref
                            .read(settingsNotifierProvider.notifier)
                            .addOfficeWifiSsid(currentSsid);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Added "$currentSsid" to office networks!',
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: FluentSpacing.m),

            // Active Configured Networks Chips
            Text(
              'Active Office SSIDs:',
              style: FluentType.caption.copyWith(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface
                    .withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: FluentSpacing.xs),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: configuredList.map((ssid) {
                final cleanSsid = ssid.toLowerCase().replaceAll(' ', '');
                final cleanCurrent = currentSsid?.toLowerCase().replaceAll(
                  ' ',
                  '',
                );
                final isCurrent =
                    cleanCurrent != null && (cleanCurrent == cleanSsid);
                final isMacHotspot =
                    cleanSsid == 'secretstar' || cleanSsid == 'secreatstar';
                final isZavisoft = cleanSsid.contains('zavisoft');

                return Chip(
                  avatar: CircleAvatar(
                    backgroundColor: isCurrent
                        ? (isDark
                              ? Colors.green.withValues(alpha: 0.3)
                              : Colors.green.shade100)
                        : (isDark
                              ? Colors.indigo.withValues(alpha: 0.3)
                              : Colors.indigo.shade50),
                    child: Icon(
                      isMacHotspot
                          ? Icons.laptop_mac
                          : (isZavisoft ? Icons.business : Icons.wifi),
                      size: 14,
                      color: isCurrent
                          ? (isDark
                                ? Colors.greenAccent
                                : Colors.green.shade800)
                          : (isDark
                                ? Colors.indigoAccent
                                : Colors.indigo.shade700),
                    ),
                  ),
                  label: Text.rich(
                    TextSpan(
                      text: ssid,
                      style: FluentType.caption.copyWith(
                        fontWeight: isCurrent
                            ? FontWeight.bold
                            : FontWeight.w500,
                        color: isCurrent
                            ? (isDark
                                  ? Colors.greenAccent
                                  : Colors.green.shade900)
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                      children: [
                        if (isMacHotspot)
                          TextSpan(
                            text: ' (Mac)',
                            style: FluentType.caption.copyWith(
                              color: Theme.of(context).colorScheme.onSurface
                                  .withValues(alpha: 0.65),
                            ),
                          )
                        else if (isZavisoft)
                          TextSpan(
                            text: ' (Main)',
                            style: FluentType.caption.copyWith(
                              color: Theme.of(context).colorScheme.onSurface
                                  .withValues(alpha: 0.65),
                            ),
                          ),
                      ],
                    ),
                  ),
                  backgroundColor: isCurrent
                      ? (isDark
                            ? Colors.green.withValues(alpha: 0.2)
                            : const Color(0xFFDCFCE7))
                      : Theme.of(context).colorScheme.onSurface
                            .withValues(alpha: 0.04),
                  deleteIcon: const Icon(Icons.close, size: 14),
                  onDeleted: configuredList.length > 1
                      ? () {
                          ref
                              .read(settingsNotifierProvider.notifier)
                              .removeOfficeWifiSsid(ssid);
                        }
                      : null,
                  shape: RoundedRectangleBorder(
                    borderRadius: FluentRadius.controlBorder,
                    side: BorderSide(
                      color: isCurrent
                          ? (isDark
                                ? Colors.green.withValues(alpha: 0.5)
                                : const Color(0xFF86EFAC))
                          : Theme.of(context).colorScheme.onSurface
                                .withValues(alpha: 0.12),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: FluentSpacing.m),

            // Add Custom or Presets
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customSsidController,
                    decoration: const InputDecoration(
                      hintText: 'Add another Wi-Fi (e.g. Zavisoft-5G)',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: FluentSpacing.s,
                      ),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: FluentSpacing.s),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E3A8A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: FluentSpacing.s,
                    ),
                  ),
                  onPressed: () {
                    final text = _customSsidController.text.trim();
                    if (text.isNotEmpty) {
                      ref
                          .read(settingsNotifierProvider.notifier)
                          .addOfficeWifiSsid(text);
                      _customSsidController.clear();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Added "$text" to office networks!'),
                        ),
                      );
                    }
                  },
                  child: const Text('Add'),
                ),
              ],
            ),

            // Quick Preset Action Chips if not yet added
            if (!configuredList.any((s) => s.toLowerCase() == 'zavisoft') ||
                !configuredList.any(
                  (s) => s.toLowerCase() == 'secretstar',
                )) ...[
              const SizedBox(height: FluentSpacing.s),
              Wrap(
                spacing: 6,
                children: [
                  if (!configuredList.any((s) => s.toLowerCase() == 'zavisoft'))
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 14),
                      label: const Text(
                        'Preset: Zavisoft',
                        style: FluentType.caption,
                      ),
                      onPressed: () {
                        ref
                            .read(settingsNotifierProvider.notifier)
                            .addOfficeWifiSsid('Zavisoft');
                      },
                    ),
                  if (!configuredList.any(
                    (s) => s.toLowerCase() == 'secretstar',
                  ))
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 14),
                      label: const Text(
                        'Preset: SecretStar (Mac Hotspot)',
                        style: FluentType.caption,
                      ),
                      onPressed: () {
                        ref
                            .read(settingsNotifierProvider.notifier)
                            .addOfficeWifiSsid('SecretStar');
                      },
                    ),
                ],
              ),
            ],

            // Seamless Handoff Banner Note
            const SizedBox(height: FluentSpacing.m),
            Container(
              padding: const EdgeInsets.all(FluentSpacing.s),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.green.withValues(alpha: 0.15)
                    : const Color(0xFFF0FDF4),
                borderRadius: FluentRadius.controlBorder,
                border: Border.all(
                  color: isDark
                      ? Colors.green.withValues(alpha: 0.3)
                      : const Color(0xFFBBF7D0),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.bolt, color: Colors.green, size: 18),
                  const SizedBox(width: FluentSpacing.s),
                  Expanded(
                    child: Text(
                      'স্মার্ট হ্যান্ডঅফ সক্রিয়: দরজায় "Zavisoft" পেলে চেক-ইন অ্যালার্ট আসবে। এরপর ডেস্কে বসে ম্যাকের "SecretStar" হটস্পটে সুইচ করলে ৪৫ সেকেন্ড গ্রেস পিরিয়ড থাকায় কোনো ভুল চেক-আউট হবে না।',
                      style: FluentType.caption.copyWith(
                        color: isDark
                            ? const Color(0xFFA7F3D0)
                            : const Color(0xFF166534),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 28),
            Row(
              children: [
                const Icon(Icons.beach_access, size: 18, color: Colors.teal),
                const SizedBox(width: FluentSpacing.s),
                Expanded(
                  child: Text(
                    'Weekly Off-Days (No Office Work)',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: FluentType.bodyStrong.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: FluentSpacing.xs),
            Text(
              'Office Wi-Fi check-in/out and dinner alerts are paused on these days. AI switches to weekend deep study mode.',
              style: FluentType.caption.copyWith(
                color: Theme.of(context).colorScheme.onSurface
                    .withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: FluentSpacing.s),
            _buildWeekdayChips(settings.offDays),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditCredentialsDialog({
    required String title,
    required String initialEmail,
    required String prefEmailKey,
    required String prefPasswordKey,
    required VoidCallback onSaved,
  }) async {
    final emailCtrl = TextEditingController(text: initialEmail);
    final passCtrl = TextEditingController();
    bool obscure = true;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text(title, style: FluentType.bodyStrong),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(
                  labelText: 'Email Address',
                  prefixIcon: Icon(Icons.email_outlined, size: 20),
                  isDense: true,
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: FluentSpacing.m),
              TextField(
                controller: passCtrl,
                obscureText: obscure,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscure ? Icons.visibility : Icons.visibility_off,
                      size: 18,
                    ),
                    onPressed: () => setDlgState(() => obscure = !obscure),
                  ),
                  isDense: true,
                  hintText: 'Enter new password if changed',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                if (emailCtrl.text.trim().isNotEmpty) {
                  await prefs.setString(prefEmailKey, emailCtrl.text.trim());
                }
                if (passCtrl.text.isNotEmpty) {
                  await prefs.setString(prefPasswordKey, passCtrl.text);
                }
                if (ctx.mounted) Navigator.pop(ctx);
                onSaved();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPacklyAutomationSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: FluentRadius.cardBorder,
        side: FluentStroke.side(Theme.of(context).brightness),
      ),
      child: Padding(
        padding: const EdgeInsets.all(FluentSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Portal Account Info & Edit / Ping Row
            Container(
              padding: const EdgeInsets.all(FluentSpacing.m),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : const Color(0xFFF0FDFA),
                borderRadius: FluentRadius.cardBorder,
                border: Border.all(
                  color: isDark ? Colors.white12 : const Color(0xFFCCFBF1),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(FluentSpacing.s),
                        decoration: BoxDecoration(
                          color: Colors.teal.withValues(alpha: 0.15),
                          borderRadius: FluentRadius.controlBorder,
                        ),
                        child: const Icon(
                          Icons.domain,
                          color: Colors.teal,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: FluentSpacing.s),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'ZaviSoft Packly Attendance Portal',
                              style: FluentType.bodyStrong,
                            ),
                            Text(
                              '$_packlyEmail • Shift: 9:00 AM – 6:00 PM',
                              style: FluentType.caption.copyWith(
                                color: Theme.of(context).colorScheme.onSurface
                                    .withValues(alpha: 0.65),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: FluentSpacing.s),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    alignment: WrapAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: FluentSpacing.xs,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.edit, size: 14),
                        label: const Text(
                          'Edit Credentials',
                          style: FluentType.caption,
                        ),
                        onPressed: () {
                          _showEditCredentialsDialog(
                            title: 'Edit Packly Attendance Credentials',
                            initialEmail: _packlyEmail,
                            prefEmailKey: NotificationConstants.prefPacklyEmail,
                            prefPasswordKey:
                                NotificationConstants.prefPacklyPassword,
                            onSaved: () {
                              _loadPacklySettings();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Packly credentials saved!'),
                                  ),
                                );
                              }
                            },
                          );
                        },
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: FluentSpacing.xs,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: _isPacklyPinging
                            ? const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.sync, size: 14),
                        label: Text(
                          _isPacklyPinging ? 'Pinging...' : 'Ping / Test Login',
                          style: FluentType.caption,
                        ),
                        onPressed: _isPacklyPinging
                            ? null
                            : () async {
                                setState(() => _isPacklyPinging = true);
                                final res = await PacklyAttendanceService
                                    .instance
                                    .ping();
                                if (mounted) {
                                  setState(() => _isPacklyPinging = false);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      backgroundColor: res.success
                                          ? Colors.teal.shade800
                                          : Colors.red.shade800,
                                      content: Text(res.message),
                                    ),
                                  );
                                }
                              },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: FluentSpacing.m),

            // Strict Policy & Grace Period Notice
            Container(
              padding: const EdgeInsets.all(FluentSpacing.s),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.amber.withValues(alpha: 0.12)
                    : const Color(0xFFFFFBEB),
                borderRadius: FluentRadius.cardBorder,
                border: Border.all(
                  color: isDark
                      ? Colors.amber.withValues(alpha: 0.3)
                      : const Color(0xFFFDE68A),
                ),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: Colors.amber, size: 18),
                  SizedBox(width: FluentSpacing.s),
                  Expanded(
                    child: Text(
                      'অফিস নিয়ম: ৯:১৪ AM পর্যন্ত অন-টাইম, ৯:১৫ AM বাজলেই LATE হিসেবে গণ্য হবে। ৩ দিন লেট হলে ১ দিনের বেতন/ছুটি কর্তন ও শোকজ নোটিশ কার্যকর হয়।',
                      style: FluentType.caption,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: FluentSpacing.m),

            // Navigation Card to dedicated Diagnostics & Simulation Test Lab
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: FluentRadius.cardBorder,
                side: BorderSide(
                  color: _simulationMode
                      ? Colors.amber.withValues(alpha: 0.5)
                      : Theme.of(context).colorScheme.onSurface
                            .withValues(alpha: 0.2),
                  width: _simulationMode ? 1.5 : 1,
                ),
              ),
              color: _simulationMode
                  ? (isDark
                        ? Colors.amber.withValues(alpha: 0.1)
                        : const Color(0xFFFFFBEB))
                  : (isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : const Color(0xFFF8FAFC)),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: FluentSpacing.xs,
                ),
                leading: Container(
                  padding: const EdgeInsets.all(FluentSpacing.s),
                  decoration: BoxDecoration(
                    color: _simulationMode
                        ? Colors.amber.withValues(alpha: 0.25)
                        : Theme.of(context).colorScheme.onSurface
                              .withValues(alpha: 0.12),
                    borderRadius: FluentRadius.controlBorder,
                  ),
                  child: Icon(
                    Icons.science_rounded,
                    color: _simulationMode ? Colors.amber : Colors.blueGrey,
                    size: 22,
                  ),
                ),
                title: Row(
                  children: [
                    const Flexible(
                      child: Text(
                        'Portal & Automation Test Lab',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FluentType.bodyStrong,
                      ),
                    ),
                    if (_simulationMode) ...[
                      const SizedBox(width: FluentSpacing.s),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: FluentSpacing.xxs,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade900,
                          borderRadius: FluentRadius.controlBorder,
                        ),
                        child: Text(
                          'TEST MODE ON',
                          style: FluentType.caption.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                subtitle: Text(
                  _simulationMode
                      ? '🧪 টেস্ট মোড সচল! ডামি টেস্ট ল্যাব থেকে নোটিফিকেশন, পিং ও ফলস পাঞ্চ পরিচালনা করুন।'
                      : 'ডামি টেস্ট মোড, নোটিফিকেশন অ্যালার্ম, পিং ডায়াগনস্টিকস ও অটোমেশন ল্যাব স্ক্রিন খুলুন।',
                  style: FluentType.caption,
                ),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (ctx) => const AttendanceTestLabScreen(),
                    ),
                  );
                  _loadPacklySettings();
                },
              ),
            ),
            const SizedBox(height: FluentSpacing.m),

            // Switch 1: Auto Check-In on Office Wi-Fi
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Auto Check-In (Office Wi-Fi)',
                style: FluentType.bodyStrong,
              ),
              subtitle: const Text(
                'অফিস ওয়াই-ফাইতে ("Zavisoft" / "SecretStar") কানেক্ট হওয়া মাত্রই সকাল ৯:০০ টার আগে স্বয়ংক্রিয়ভাবে জিপিএস ও অনুমোদিত আইপি দিয়ে চেক-ইন সাবমিট হবে।',
                style: FluentType.caption,
              ),
              value: _autoCheckInEnabled,
              onChanged: (val) async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool(
                  NotificationConstants.prefAutoCheckInEnabled,
                  val,
                );
                setState(() => _autoCheckInEnabled = val);
                await WorkmanagerService.instance.syncWatchdogWithPrefs();
              },
            ),
            const Divider(height: 20),

            // Switch 2: 9:15 AM Late Prevention Warning
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                '9:15 AM Late Prevention Alarm',
                style: FluentType.bodyStrong,
              ),
              subtitle: const Text(
                'সকাল ৮:৫০ ও ৯:১০ এ আপনি পাঞ্চ না করে থাকলে অ্যালার্মধর্মী হাই-প্রায়োরিটি নোটিফিকেশন পাঠাবে, যাতে কোনোভাবেই ৯:১৫ এর লেট পেনাল্টি না পড়ে।',
                style: FluentType.caption,
              ),
              value: _lateWarningEnabled,
              onChanged: (val) async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool(
                  NotificationConstants.prefLateWarningEnabled,
                  val,
                );
                setState(() => _lateWarningEnabled = val);
                if (val) {
                  await NotificationService.instance
                      .scheduleMorningOfficeWatchdogs();
                } else {
                  await NotificationService.instance
                      .cancelMorningOfficeWatchdogs();
                }
                await WorkmanagerService.instance.syncWatchdogWithPrefs();
              },
            ),
            const Divider(height: 20),

            // Switch 3: Auto Check-Out after 6:00 PM
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Smart Check-Out (After 6:00 PM)',
                style: FluentType.bodyStrong,
              ),
              subtitle: const Text(
                'সন্ধ্যা ৬:০০ টার পর অফিস ছেড়ে বের হলে (ওয়াই-ফাই বিচ্ছিন্ন হলে) অটো চেক-আউট সাবমিট করবে। সময়ের আগে ভুলবশত কোনো চেক-আউট হবে না।',
                style: FluentType.caption,
              ),
              value: _autoCheckOutEnabled,
              onChanged: (val) async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool(
                  NotificationConstants.prefAutoCheckOutEnabled,
                  val,
                );
                setState(() => _autoCheckOutEnabled = val);
                if (val) {
                  await NotificationService.instance
                      .scheduleEveningOfficeWatchdogs();
                } else {
                  await NotificationService.instance
                      .cancelEveningOfficeWatchdogs();
                }
                await WorkmanagerService.instance.syncWatchdogWithPrefs();
              },
            ),
            const Divider(height: 20),

            // Switch 4: Office Downtime BCS Micro-Nudges (1:15 PM & 4:30 PM)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Office Downtime Micro-Study Nudges',
                style: FluentType.bodyStrong,
              ),
              subtitle: const Text(
                'অফিসের লাঞ্চ বিরতি (১:১৫ PM) ও বিকালের চা পানের সময়ে (৪:৩০ PM) ১ মিনিটের হালকা বিসিএস রিভিশন পুশ দেবে (শব্দহীন ও কাজের ক্ষতি না করে)।',
                style: FluentType.caption,
              ),
              value: _officeDowntimeStudyEnabled,
              onChanged: (val) async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool(
                  NotificationConstants.prefOfficeDowntimeFlashcardEnabled,
                  val,
                );
                setState(() => _officeDowntimeStudyEnabled = val);
                if (val) {
                  await NotificationService.instance
                      .scheduleOfficeDowntimeFlashcards();
                } else {
                  await NotificationService.instance
                      .cancelOfficeDowntimeFlashcards();
                }
              },
            ),
            const Divider(height: 20),

            // Study Dashboard Display Mode (User can choose to keep dashboard clean for studies)
            const Text(
              'Study Dashboard Display Mode',
              style: FluentType.bodyStrong,
            ),
            const SizedBox(height: FluentSpacing.xs),
            Text(
              'আপনার ড্যাশবোর্ড যেন সম্পূর্ণ পড়াশোনার জন্য শান্ত ও নিরবচ্ছিন্ন থাকে, সেজন্য অফিস ব্যানার কখন দেখাবে তা নির্বাচন করুন:',
              style: FluentType.caption.copyWith(
                color: Theme.of(context).colorScheme.onSurface
                    .withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: FluentSpacing.s),
            Container(
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : const Color(0xFFF8FAFC),
                borderRadius: FluentRadius.cardBorder,
                border: Border.all(
                  color: Theme.of(context).colorScheme.onSurface
                      .withValues(alpha: 0.12),
                ),
              ),
              child: Column(
                children: [
                  _buildDisplayModeOption(
                    value: 'contextual',
                    title: 'শুধুমাত্র অফিসে বা অফিস টাইমে দেখাও',
                    subtitle: 'পড়াশোনার সময় (সন্ধ্যা, রাত বা ছুটির দিন) ড্যাশবোর্ড ক্লিন থাকবে। কুইক অ্যাকশন পিল থেকে যেকোনো সময় খোলা যাবে। (Recommended)',
                    isDark: isDark,
                  ),
                  const Divider(height: 1),
                  _buildDisplayModeOption(
                    value: 'always',
                    title: 'সবসময় ড্যাশবোর্ডে দেখাও',
                    subtitle: 'পড়াশোনা বা অন্য সব অবস্থাতেই ড্যাশবোর্ডের উপরে ব্যানার দৃশ্যমান থাকবে।',
                    isDark: isDark,
                  ),
                  const Divider(height: 1),
                  _buildDisplayModeOption(
                    value: 'hidden',
                    title: 'ড্যাশবোর্ড থেকে হাইড রাখো (শুধু কুইক অ্যাকশনে)',
                    subtitle: 'ড্যাশবোর্ড ১০০% পড়াশোনার জন্য সংরক্ষিত থাকবে। অফিস দেখতে Quick Action পিল ট্যাপ করুন।',
                    isDark: isDark,
                  ),
                ],
              ),
            ),
            const Divider(height: 20),

            // Kill Mode / Battery Optimization
            Container(
              padding: const EdgeInsets.all(FluentSpacing.m),
              decoration: BoxDecoration(
                color: _isBatteryOptIgnored
                    ? (isDark
                          ? Colors.green.withValues(alpha: 0.15)
                          : const Color(0xFFECFDF5))
                    : (isDark
                          ? Colors.red.withValues(alpha: 0.15)
                          : const Color(0xFFFEF2F2)),
                borderRadius: FluentRadius.cardBorder,
                border: Border.all(
                  color: _isBatteryOptIgnored
                      ? (isDark
                            ? Colors.green.withValues(alpha: 0.3)
                            : const Color(0xFFA7F3D0))
                      : (isDark
                            ? Colors.red.withValues(alpha: 0.3)
                            : const Color(0xFFFECACA)),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _isBatteryOptIgnored
                            ? Icons.shield_rounded
                            : Icons.battery_alert_rounded,
                        color: _isBatteryOptIgnored
                            ? Colors.green
                            : Colors.redAccent,
                        size: 20,
                      ),
                      const SizedBox(width: FluentSpacing.s),
                      Expanded(
                        child: Text(
                          _isBatteryOptIgnored
                              ? 'কিল মোড সুরক্ষা সক্রিয় (OS Always Runs App)'
                              : 'কিল মোড সমাধান: ব্যাটারি অপ্টিমাইজেশন বন্ধ করুন',
                          style: FluentType.caption.copyWith(
                            fontWeight: FontWeight.w600,
                            color: _isBatteryOptIgnored
                                ? (isDark
                                      ? Colors.greenAccent
                                      : Colors.green.shade800)
                                : (isDark
                                      ? Colors.redAccent
                                      : Colors.red.shade800),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: FluentSpacing.xs),
                  Text(
                    _isBatteryOptIgnored
                        ? 'অ্যাপ সোয়াইপ করে বন্ধ রাখলেও অ্যান্ড্রয়েড ওএস ব্যাকগ্রাউন্ডে ওয়াই-ফাই ডিটেকশন ও চেক-ইন অ্যালার্ট সচল রাখবে।'
                        : 'অ্যান্ড্রয়েড ওএস যাতে অ্যাপ ব্যাকগ্রাউন্ডে বন্ধ (Kill) না করে এবং সঠিক সময়ে চেক-ইন ও নোটিফিকেশন পাঠাতে পারে, সেজন্য এটি সক্রিয় করুন।',
                    style: FluentType.caption.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  if (!_isBatteryOptIgnored) ...[
                    const SizedBox(height: FluentSpacing.s),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: FluentSpacing.s,
                        ),
                      ),
                      icon: const Icon(Icons.bolt, size: 14),
                      label: const Text(
                        'Allow Always in Background',
                        style: FluentType.caption,
                      ),
                      onPressed: () async {
                        final granted = await WifiMonitorService.instance
                            .requestIgnoreBatteryOptimization();
                        if (mounted) {
                          setState(() => _isBatteryOptIgnored = granted);
                        }
                      },
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: FluentSpacing.m),

            // Office Location Geofence row
            Row(
              children: [
                const Icon(
                  Icons.location_on,
                  color: Colors.blueAccent,
                  size: 18,
                ),
                const SizedBox(width: FluentSpacing.s),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Office GPS Location Geofence',
                        style: FluentType.caption.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        _officeAddress,
                        style: FluentType.caption.copyWith(
                          color: Theme.of(context).colorScheme.onSurface
                              .withValues(alpha: 0.65),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: FluentSpacing.xs,
                    ),
                  ),
                  icon: const Icon(Icons.my_location, size: 14),
                  label: const Text('Calibrate', style: FluentType.caption),
                  onPressed: () async {
                    try {
                      final pos = await Geolocator.getCurrentPosition(
                        locationSettings: const LocationSettings(
                          accuracy: LocationAccuracy.high,
                          timeLimit: Duration(seconds: 10),
                        ),
                      );
                      final addr = await PacklyAttendanceService.instance
                          .reverseGeocode(pos.latitude, pos.longitude);
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setDouble(
                        NotificationConstants.prefOfficeLatitude,
                        pos.latitude,
                      );
                      await prefs.setDouble(
                        NotificationConstants.prefOfficeLongitude,
                        pos.longitude,
                      );
                      await prefs.setString(
                        NotificationConstants.prefOfficeAddress,
                        addr,
                      );
                      if (mounted) {
                        setState(() => _officeAddress = addr);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Office location updated: $addr'),
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Location error: $e')),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSteadfastLunchSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lunchState = ref.watch(lunchProvider);
    final tomorrowBooked = lunchState.tomorrowBooked ?? _lunchTomorrowBooked;
    final todayBooked = lunchState.todayBooked ?? _lunchTodayBooked;

    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final tomorrowStr = '${tomorrow.day}/${tomorrow.month}/${tomorrow.year}';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: FluentRadius.cardBorder,
        side: FluentStroke.side(Theme.of(context).brightness),
      ),
      child: Padding(
        padding: const EdgeInsets.all(FluentSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Account Info & Edit / Ping Row
            Container(
              padding: const EdgeInsets.all(FluentSpacing.m),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : const Color(0xFFFFF7ED),
                borderRadius: FluentRadius.cardBorder,
                border: Border.all(
                  color: isDark ? Colors.white12 : const Color(0xFFFFEDD5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(FluentSpacing.s),
                        decoration: BoxDecoration(
                          color: Colors.deepOrange.withValues(alpha: 0.15),
                          borderRadius: FluentRadius.controlBorder,
                        ),
                        child: const Icon(
                          Icons.lunch_dining_rounded,
                          color: Colors.deepOrange,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: FluentSpacing.s),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Steadfast Courier Lunch Portal',
                              style: FluentType.bodyStrong,
                            ),
                            Text(
                              '$_lunchEmail • Cutoff: Daily 6:00 PM',
                              style: FluentType.caption.copyWith(
                                color: Theme.of(context).colorScheme.onSurface
                                    .withValues(alpha: 0.65),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: FluentSpacing.s),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    alignment: WrapAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: FluentSpacing.xs,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.edit, size: 14),
                        label: const Text(
                          'Edit Credentials',
                          style: FluentType.caption,
                        ),
                        onPressed: () {
                          _showEditCredentialsDialog(
                            title: 'Edit Lunch Portal Credentials',
                            initialEmail: _lunchEmail,
                            prefEmailKey: NotificationConstants.prefLunchEmail,
                            prefPasswordKey:
                                NotificationConstants.prefLunchPassword,
                            onSaved: () {
                              _loadPacklySettings();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Lunch credentials saved!'),
                                  ),
                                );
                              }
                            },
                          );
                        },
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepOrange.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: FluentSpacing.xs,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: lunchState.isLoading
                            ? const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.sync, size: 14),
                        label: Text(
                          lunchState.isLoading
                              ? 'Checking...'
                              : 'Ping / Check Status',
                          style: FluentType.caption,
                        ),
                        onPressed: lunchState.isLoading
                            ? null
                            : () async {
                                final res = await ref
                                    .read(lunchProvider.notifier)
                                    .ping();
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      backgroundColor: res.success
                                          ? Colors.green.shade800
                                          : Colors.red.shade800,
                                      content: Text(res.message),
                                    ),
                                  );
                                }
                              },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: FluentSpacing.m),

            // Strict Cutoff Rule Notice
            Container(
              padding: const EdgeInsets.all(FluentSpacing.s),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.orange.withValues(alpha: 0.12)
                    : const Color(0xFFFFF7ED),
                borderRadius: FluentRadius.cardBorder,
                border: Border.all(
                  color: isDark
                      ? Colors.orange.withValues(alpha: 0.3)
                      : const Color(0xFFFED7AA),
                ),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: Colors.deepOrange, size: 18),
                  SizedBox(width: FluentSpacing.s),
                  Expanded(
                    child: Text(
                      'লাঞ্চ নিয়ম: আগামীকালের লাঞ্চ পেতে হলে আজ সন্ধ্যা ৬:০০ টার মধ্যে বুক করতে হবে। ৬:০০ টা বেজে গেলে ক্যালেন্ডার স্বয়ংক্রিয়ভাবে লক হয়ে যায় এবং আর বুকিং সম্ভব হয় না।',
                      style: FluentType.caption,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: FluentSpacing.m),

            // Live Meal Status Tiles (Today & Tomorrow)
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(FluentSpacing.m),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.04)
                          : const Color(0xFFF8FAFC),
                      borderRadius: FluentRadius.cardBorder,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.onSurface
                            .withValues(alpha: 0.12),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'আজকের লাঞ্চ (Today)',
                          style: FluentType.caption.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: FluentSpacing.xs),
                        Row(
                          children: [
                            Icon(
                              todayBooked == true
                                  ? Icons.check_circle
                                  : Icons.cancel_outlined,
                              size: 16,
                              color: todayBooked == true
                                  ? Colors.green
                                  : Colors.grey,
                            ),
                            const SizedBox(width: FluentSpacing.xs),
                            Expanded(
                              child: Text(
                                todayBooked == true
                                    ? 'বুক করা আছে ✓'
                                    : (todayBooked == false
                                          ? 'বুক নেই (Off)'
                                          : 'সিঙ্ক করুন'),
                                style: FluentType.caption.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: todayBooked == true
                                      ? Colors.green
                                      : Theme.of(context).colorScheme.onSurface,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: FluentSpacing.s),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(FluentSpacing.m),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.04)
                          : const Color(0xFFF8FAFC),
                      borderRadius: FluentRadius.cardBorder,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.onSurface
                            .withValues(alpha: 0.12),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'আগামীকাল ($tomorrowStr)',
                          style: FluentType.caption.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        const SizedBox(height: FluentSpacing.xs),
                        Row(
                          children: [
                            Icon(
                              tomorrowBooked == true
                                  ? Icons.check_circle
                                  : Icons.cancel_outlined,
                              size: 16,
                              color: tomorrowBooked == true
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                            const SizedBox(width: FluentSpacing.xs),
                            Expanded(
                              child: Text(
                                tomorrowBooked == true
                                    ? 'বুক করা আছে ✓'
                                    : (tomorrowBooked == false
                                          ? 'বুক নেই (Off)'
                                          : 'সিঙ্ক করুন'),
                                style: FluentType.caption.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: tomorrowBooked == true
                                      ? Colors.green
                                      : (tomorrowBooked == false
                                            ? Colors.orange
                                            : Theme.of(context)
                                                  .colorScheme
                                                  .onSurface),
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: FluentSpacing.m),

            // Toggle Tomorrow's Lunch Quick Action Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: tomorrowBooked == true
                      ? Colors.redAccent.shade700
                      : Colors.teal.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    vertical: FluentSpacing.s,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: FluentRadius.cardBorder,
                  ),
                ),
                icon: lunchState.isToggling
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        tomorrowBooked == true
                            ? Icons.cancel
                            : Icons.check_circle,
                        size: 16,
                      ),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    lunchState.isToggling
                        ? 'Updating Server...'
                        : (tomorrowBooked == true
                              ? 'Cancel Tomorrow\'s Lunch (লাঞ্চ বাতিল করুন)'
                              : 'Book Tomorrow\'s Lunch (আগামীকালের লাঞ্চ বুক করুন)'),
                    style: FluentType.caption.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                onPressed: lunchState.isToggling
                    ? null
                    : () async {
                        final res = await ref
                            .read(lunchProvider.notifier)
                            .toggleTomorrowMeal();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: res.success
                                  ? Colors.green.shade800
                                  : Colors.red.shade800,
                              content: Text(res.message),
                            ),
                          );
                        }
                      },
              ),
            ),
            const SizedBox(height: FluentSpacing.s),

            // Button to Open Full Interactive Calendar & Office Portal
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.onSurface
                        .withValues(alpha: 0.5),
                  ),
                  padding: const EdgeInsets.symmetric(
                    vertical: FluentSpacing.s,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: FluentRadius.cardBorder,
                  ),
                ),
                icon: const Icon(
                  Icons.calendar_month_rounded,
                  size: 16,
                  color: Colors.deepOrange,
                ),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Open Meal Calendar & Office Portal ➔',
                    style: FluentType.caption.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const OfficePortalScreen(),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 24),

            // 5:00 PM Auto Reminder Switch
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                '5:00 PM Daily Lunch Cutoff Alarm',
                style: FluentType.bodyStrong,
              ),
              subtitle: const Text(
                'প্রতিদিন বিকেল ৫:০০ টায় (৬:০০ টার কাটঅফের ১ ঘণ্টা আগে) আগামীকালের লাঞ্চ বুক করা না থাকলে নোটিফিকেশন পাঠাবে এবং নোটিফিকেশনে বুক করার বাটন দেবে।',
                style: FluentType.caption,
              ),
              value: _lunchAutoReminderEnabled,
              onChanged: (val) async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool(
                  NotificationConstants.prefLunchAutoReminderEnabled,
                  val,
                );
                setState(() => _lunchAutoReminderEnabled = val);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDisplayModeOption({
    required String value,
    required String title,
    required String subtitle,
    required bool isDark,
  }) {
    final isSelected = _bannerDisplayMode == value;
    return InkWell(
      onTap: () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          NotificationConstants.prefOfficeBannerMode,
          value,
        );
        setState(() => _bannerDisplayMode = value);
      },
      borderRadius: FluentRadius.controlBorder,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: FluentSpacing.m,
          vertical: 10,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected
                  ? Colors.teal
                  : Theme.of(context).colorScheme.onSurface
                        .withValues(alpha: 0.5),
              size: 18,
            ),
            const SizedBox(width: FluentSpacing.s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: FluentType.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? (isDark ? Colors.tealAccent : Colors.teal.shade800)
                          : null,
                    ),
                  ),
                  const SizedBox(height: FluentSpacing.xxs),
                  Text(
                    subtitle,
                    style: FluentType.caption.copyWith(
                      color: Theme.of(context).colorScheme.onSurface
                          .withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlashcardPushCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    const options = <int, String>{
      30: 'প্রতি ৩০ মিনিটে',
      60: 'প্রতি ঘণ্টায়',
      120: 'প্রতি ২ ঘণ্টায়',
      180: 'প্রতি ৩ ঘণ্টায়',
    };

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: FluentRadius.cardBorder,
        side: BorderSide(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _flashcardPushEnabled,
              title: const Text(
                'নিয়ম করে ফ্ল্যাশকার্ড পাঠাও',
                style: FluentType.bodyStrong,
              ),
              subtitle: Text(
                'রিভিশনের সময় হয়ে আসা কার্ড আগে যায়, তারপর বাছাই করা ডেক। '
                'নিচের সময়সীমার বাইরে কিছু পাঠানো হয় না।',
                style: FluentType.caption.copyWith(
                  color: Theme.of(context).colorScheme.onSurface
                      .withValues(alpha: 0.65),
                ),
              ),
              onChanged: (v) async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool(
                  NotificationConstants.prefFlashcardPushEnabled,
                  v,
                );
                if (!mounted) return;
                setState(() => _flashcardPushEnabled = v);
                await ref
                    .read(spacedRepetitionNotifierProvider.notifier)
                    .refreshFlashcardSchedule(force: true);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      v ? 'ফ্ল্যাশকার্ড পুশ চালু হলো' : 'ফ্ল্যাশকার্ড পুশ বন্ধ',
                    ),
                  ),
                );
              },
            ),
            if (_flashcardPushEnabled) ...[
              // The queue is only rebuilt when the app is opened, so how deep
              // it is decides how long the pushes last. Leaving that invisible
              // is what made the feature look broken after a quiet weekend.
              if (_flashcardQueuedCount > 0 && _flashcardSlotsPerDay > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 2),
                  child: Text(
                    '$_flashcardQueuedCount টি কার্ড সাজানো আছে — '
                    'অ্যাপ না খুললেও প্রায় '
                    '${(_flashcardQueuedCount / _flashcardSlotsPerDay).toStringAsFixed(1)} '
                    'দিন চলবে',
                    style: FluentType.caption.copyWith(
                      color: _flashcardQueuedCount < _flashcardSlotsPerDay
                          ? Colors.orange.shade800
                          : Colors.green.shade700,
                    ),
                  ),
                ),
              const SizedBox(height: FluentSpacing.xs),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: options.entries.map((e) {
                  final selected = _flashcardPushMinutes == e.key;
                  return ChoiceChip(
                    label: Text(e.value, style: FluentType.caption),
                    selected: selected,
                    onSelected: (_) async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setInt(
                        NotificationConstants.prefFlashcardPushIntervalMinutes,
                        e.key,
                      );
                      if (!mounted) return;
                      setState(() => _flashcardPushMinutes = e.key);
                      await ref
                          .read(spacedRepetitionNotifierProvider.notifier)
                          .refreshFlashcardSchedule(force: true);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: FluentSpacing.m),
              Text(
                'কখন থেকে কখন পর্যন্ত পাঠানো হবে',
                style: FluentType.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: FluentSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: _buildHourPicker(
                      label: 'শুরু',
                      hour: _flashcardStartHour,
                      isDark: isDark,
                      onPicked: (h) => _saveFlashcardWindow(startHour: h),
                    ),
                  ),
                  const SizedBox(width: FluentSpacing.s),
                  Expanded(
                    child: _buildHourPicker(
                      label: 'শেষ',
                      hour: _flashcardEndHour,
                      isDark: isDark,
                      onPicked: (h) => _saveFlashcardWindow(endHour: h),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: FluentSpacing.s),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final n = await ref
                        .read(spacedRepetitionNotifierProvider.notifier)
                        .scheduleFlashcardTestBurst();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          n == 0
                              ? 'কোনো কার্ড পাওয়া গেল না'
                              : '$n টি কার্ড ১ মিনিট পরপর আসবে। '
                                    'অ্যাপ বন্ধ করলেও আসবে।',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.play_circle_outline, size: 17),
                  label: const Text(
                    '১ মিনিট পরপর পাঠিয়ে দেখুন',
                    style: FluentType.caption,
                  ),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
              const SizedBox(height: FluentSpacing.s),
              Text(
                // Said plainly, because a queue that runs out looks like a
                // broken feature otherwise.
                'পরীক্ষাটি সময়সীমা মানে না, আর চলতি তালিকার জায়গা নেয় — '
                'অ্যাপ আবার খুললে স্বাভাবিক তালিকা ফিরে আসে।\n'
                'একবারে ${NotificationConstants.flashcardSeriesMaxCount}টি কার্ড সময় ধরে সাজানো থাকে; '
                'অ্যাপ খুললেই তালিকাটি আবার ভরে যায়।',
                style: FluentType.caption.copyWith(
                  color: Theme.of(context).colorScheme.onSurface
                      .withValues(alpha: 0.65),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHourPicker({
    required String label,
    required int hour,
    required bool isDark,
    required ValueChanged<int> onPicked,
  }) {
    return OutlinedButton(
      onPressed: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(hour: hour, minute: 0),
          helpText: '$label সময় বেছে নিন',
        );
        if (picked != null) onPicked(picked.hour);
      },
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: FluentSpacing.m),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: FluentType.caption.copyWith(
              color: Theme.of(context).colorScheme.onSurface
                  .withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 0),
          Text(
            TimeOfDay(hour: hour, minute: 0).format(context),
            style: FluentType.bodyStrong,
          ),
        ],
      ),
    );
  }

  /// Saves one edge of the window, refusing a pair that leaves no room.
  Future<void> _saveFlashcardWindow({int? startHour, int? endHour}) async {
    final start = startHour ?? _flashcardStartHour;
    final end = endHour ?? _flashcardEndHour;

    if (end <= start) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('শেষ সময় শুরুর পরে হতে হবে')),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(NotificationConstants.prefFlashcardPushStartHour, start);
    await prefs.setInt(NotificationConstants.prefFlashcardPushEndHour, end);

    if (!mounted) return;
    setState(() {
      _flashcardStartHour = start;
      _flashcardEndHour = end;
    });
    await ref
        .read(spacedRepetitionNotifierProvider.notifier)
        .refreshFlashcardSchedule(force: true);
  }

  /// Every section used to carry its own accent colour. In Fluent the accent
  /// marks the thing you act on, so they all share one now.
  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FluentSpacing.s),
      child: PremiumSectionHeader(icon: icon, label: title),
    );
  }

  Future<void> _showDeleteTrackDialog(BuildContext context) async {
    final db = ref.read(appDatabaseProvider);
    final exams = await db.select(db.examSchedules).get();
    final trackCounts = <String, int>{};
    for (final e in exams) {
      if (e.trackName.isNotEmpty) {
        trackCounts[e.trackName] = (trackCounts[e.trackName] ?? 0) + 1;
      }
    }

    if (!context.mounted) return;

    if (trackCounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No exam tracks found in database.')),
      );
      return;
    }

    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(FluentRadius.large),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: FluentSpacing.l),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: FluentSpacing.xl),
                child: Text(
                  'Select Program Track to Delete',
                  style: FluentType.subtitle.copyWith(fontSize: 16),
                ),
              ),
              const SizedBox(height: FluentSpacing.s),
              ...trackCounts.entries.map((entry) {
                return ListTile(
                  leading: const Icon(Icons.bookmark, color: Colors.indigo),
                  title: Text(entry.key, style: FluentType.bodyStrong),
                  subtitle: Text('${entry.value} exams scheduled'),
                  trailing: const Icon(Icons.delete_outline, color: Colors.red),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (dCtx) => AlertDialog(
                        title: Text('Delete "${entry.key}"?'),
                        content: Text(
                          'Are you sure you want to delete all ${entry.value} exams in "${entry.key}"? Other tracks will remain safe.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dCtx, false),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => Navigator.pop(dCtx, true),
                            child: const Text('Delete Track'),
                          ),
                        ],
                      ),
                    );

                    if (confirmed == true && context.mounted) {
                      await db.deleteExamsByTrack(entry.key);
                      ref.invalidate(distinctTracksStreamProvider);
                      ref.invalidate(upcomingExamsStreamProvider);
                      ref.invalidate(allExamsStreamProvider);
                      ref.invalidate(filteredExamsStreamProvider);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: Colors.red.shade800,
                            content: Text(
                              'Deleted all ${entry.value} exams of "${entry.key}".',
                            ),
                          ),
                        );
                      }
                    }
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
