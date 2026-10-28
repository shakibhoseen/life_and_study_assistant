import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/database/database_provider.dart';
import '../../../../core/services/background/wifi_monitor_service.dart';
import '../../../../core/services/export/app_export_service.dart';
import '../../../../core/services/notification/notification_service.dart';
import '../../../../core/theme/theme_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/gemini_usage_monitor_card.dart';

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
  bool _isPinging = false;

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
          style: TextStyle(fontWeight: FontWeight.bold),
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

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // 1. Office Wi-Fi & Schedule Configuration
              _buildSectionHeader(
                'Office Attendance & Schedule',
                Icons.business_rounded,
                Colors.blue.shade700,
              ),
              _buildOfficeWifiSection(settings, currentSsid),
              const SizedBox(height: 18),

              // 2. Dinner Reminder Cutoff Time
              _buildSectionHeader(
                'Office Dinner Cutoff Alert',
                Icons.restaurant_rounded,
                Colors.deepOrange.shade700,
              ),
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white12
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? Colors.deepOrange.withValues(alpha: 0.2)
                                : Colors.deepOrange.shade50,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.access_time_filled,
                            color: Colors.deepOrange,
                            size: 22,
                          ),
                        ),
                        title: const Text(
                          'Daily Cutoff Reminder Time',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          '${settings.dinnerHour.toString().padLeft(2, '0')}:${settings.dinnerMinute.toString().padLeft(2, '0')} (Default 4:00 PM)',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? Colors.white
                                : Colors.black87,
                          ),
                        ),
                        trailing: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                Theme.of(context).brightness == Brightness.dark
                                ? const Color(0xFF1E293B)
                                : Colors.white,
                            foregroundColor: Colors.deepOrange,
                            side: BorderSide(
                              color:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.deepOrange.withValues(alpha: 0.4)
                                  : Colors.deepOrange.shade200,
                            ),
                            elevation: 0,
                          ),
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay(
                                hour: settings.dinnerHour,
                                minute: settings.dinnerMinute,
                              ),
                            );
                            if (picked != null) {
                              ref
                                  .read(settingsNotifierProvider.notifier)
                                  .updateDinnerTime(picked.hour, picked.minute);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Daily dinner reminder rescheduled for ${picked.format(context)}',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                          child: const Text('Change'),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Notification appears with two tray action buttons: [✓ Yes, Count Me In] and [✗ No, Skip].',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white70
                              : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // 3. Gemini AI Configuration (Premium Credential Box)
              _buildSectionHeader(
                'Gemini AI Engine & Credentials',
                Icons.auto_awesome,
                Colors.purple.shade700,
              ),
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white12
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Model Engine Selector Dropdown
                      Text(
                        'AI Engine Model:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white
                              : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xFF1E293B)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? Colors.white12
                                : const Color(0xFFCBD5E1),
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            dropdownColor:
                                Theme.of(context).brightness == Brightness.dark
                                ? const Color(0xFF1E293B)
                                : Colors.white,
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
                      const SizedBox(height: 8),
                      Text(
                        settings.geminiModel == 'gemini-pro-latest'
                            ? '✨ Pro Model active: Providing deepest reasoning (Requires Google Cloud billing enabled on project).'
                            : '⚡ Flash Lite active: 100% free daily quota, ultra-fast response for LiveMCQ routines & AI mentor.',
                        style: TextStyle(
                          fontSize: 11,
                          color: settings.geminiModel == 'gemini-pro-latest'
                              ? (Theme.of(context).brightness == Brightness.dark
                                    ? Colors.purpleAccent
                                    : Colors.deepPurple)
                              : (Theme.of(context).brightness == Brightness.dark
                                    ? Colors.tealAccent
                                    : Colors.teal.shade800),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 16),

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
              const SizedBox(height: 18),

              // Real-time Gemini API Quota & Usage Monitor
              const GeminiUsageMonitorCard(),
              const SizedBox(height: 18),

              // Auto-Weakness Healer & Micro Drills Control
              _buildSectionHeader(
                'Auto-Weakness Healer Engine',
                Icons.healing_rounded,
                const Color(0xFF10B981),
              ),
              _buildWeaknessHealerToggleCard(settings),
              const SizedBox(height: 18),

              // 4. Data Backup & Restore
              _buildBackupRestoreCard(),
              const SizedBox(height: 18),

              // Visual Comfort & Theme Mode
              _buildSectionHeader(
                'Visual Comfort & Display Theme',
                Icons.palette_outlined,
                Colors.indigo.shade700,
              ),
              _buildThemeSelectorCard(),
              const SizedBox(height: 18),

              // 5. Permissions & Reset
              _buildSectionHeader(
                'System & State Control',
                Icons.settings_suggest_rounded,
                Colors.blueGrey.shade700,
              ),
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white12
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.blue.withValues(alpha: 0.2)
                              : Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.notifications_active,
                          color: Colors.blue,
                        ),
                      ),
                      title: const Text(
                        'Request Notification & Location Permissions',
                      ),
                      subtitle: const Text(
                        'Ensure exact alarms, heads-up banner & Wi-Fi SSID access',
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                      onTap: () async {
                        await NotificationService.instance.requestPermissions();
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
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blueGrey.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.restart_alt,
                          color: Colors.blueGrey,
                        ),
                      ),
                      title: const Text(
                        'Reset Today’s Check-In & Dinner Status',
                      ),
                      subtitle: const Text('Allows re-triggering for today'),
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
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.delete_sweep_outlined,
                          color: Colors.orange,
                        ),
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
                                child: const Text(
                                  'Clear',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          await ref.read(appDatabaseProvider).clearAllExams();
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
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.cleaning_services_outlined,
                          color: Colors.redAccent,
                        ),
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
                                child: const Text(
                                  'Clear',
                                  style: TextStyle(color: Colors.red),
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
          );
        },
      ),
    );
  }

  /// Secured Premium Credential Box (Shown when key is saved & active)
  Widget _buildConnectedKeyBox(String apiKey, String modelName) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final maskedKey = apiKey.length > 12
        ? '${apiKey.substring(0, 7)}••••••••••••••••${apiKey.substring(apiKey.length - 4)}'
        : '••••••••••••••••';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF10B981).withValues(alpha: 0.4),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF10B981),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Connected & Active',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: isDark
                          ? const Color(0xFF34D399)
                          : const Color(0xFF047857),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.green.withValues(alpha: 0.2)
                      : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark
                        ? Colors.green.withValues(alpha: 0.4)
                        : Colors.green.shade200,
                  ),
                ),
                child: Text(
                  '✓ Verified',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isDark
                        ? const Color(0xFF6EE7B7)
                        : const Color(0xFF047857),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Masked Credential Box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.shield_outlined,
                  color: Color(0xFF10B981),
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _showRawKey ? apiKey : maskedKey,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: Color(0xFFE2E8F0),
                      fontSize: 12,
                      letterSpacing: 1.2,
                    ),
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
          const SizedBox(height: 8),
          Text(
            '✓ Secured in local device storage. Hidden from plain view.',
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          const SizedBox(height: 12),
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
                  label: Text(_isPinging ? 'Pinging...' : 'Test Ping'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: _isPinging
                      ? null
                      : () => _pingTestApiKey(apiKey, modelName),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Change'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () {
                  _apiKeyController.text = apiKey;
                  setState(() => _isEditingApiKey = true);
                },
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                icon: const Icon(
                  Icons.delete_outline,
                  color: Colors.redAccent,
                  size: 18,
                ),
                tooltip: 'Remove Key',
                style: IconButton.styleFrom(
                  side: BorderSide(
                    color: isDark
                        ? Colors.red.withValues(alpha: 0.4)
                        : Colors.red.shade200,
                  ),
                  visualDensity: VisualDensity.compact,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Enter Gemini API Key',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                ),
              ),
              if (_isEditingApiKey)
                TextButton(
                  onPressed: () {
                    setState(() => _isEditingApiKey = false);
                  },
                  child: const Text('Cancel', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Obtain a free key from Google AI Studio (ai.google.dev). 1,500 free calls/day.',
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          const SizedBox(height: 12),
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
          const SizedBox(height: 12),
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
                backgroundColor: const Color(0xFF1E3A8A),
                foregroundColor: Colors.white,
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
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
      spacing: 6,
      runSpacing: 6,
      children: days.map((d) {
        final val = d['val'] as int;
        final name = d['name'] as String;
        final isSelected = currentOffDays.contains(val);

        return FilterChip(
          label: Text(
            name,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected
                  ? (isDark ? Colors.teal.shade100 : Colors.teal.shade900)
                  : (isDark ? Colors.white : Colors.black87),
            ),
          ),
          selected: isSelected,
          backgroundColor: isDark ? const Color(0xFF1E293B) : null,
          selectedColor: isDark
              ? Colors.teal.withValues(alpha: 0.3)
              : Colors.teal.shade100,
          checkmarkColor: isDark ? Colors.teal.shade200 : Colors.teal.shade900,
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recognized Office Wi-Fi Networks',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: isDark ? Colors.white : const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Connect to ANY of these networks (e.g. Zavisoft or your Mac Hotspot SecretStar / Secreat Star) to trigger biometric check-in. Seamless 15s handoff prevents false check-outs when switching.',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            const SizedBox(height: 12),

            // Warning Banner when Android OS is hiding SSID due to missing Location Permission
            if (isSsidHidden) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF78350F).withValues(alpha: 0.25)
                      : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(12),
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
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Wi-Fi Connected, but Android OS hid network name',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                              color: isDark
                                  ? const Color(0xFFFDE68A)
                                  : const Color(0xFF92400E),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Modern Android (10+) requires Location Permission to read Wi-Fi SSIDs (like ZaviSoft or Secreat Star) for auto attendance check-in & check-out.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark
                            ? const Color(0xFFFEF3C7)
                            : const Color(0xFF78350F),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD97706),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            textStyle: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
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
                        const SizedBox(width: 8),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            foregroundColor: isDark
                                ? const Color(0xFFFDE68A)
                                : const Color(0xFF92400E),
                          ),
                          icon: const Icon(Icons.refresh, size: 14),
                          label: const Text(
                            'Retry',
                            style: TextStyle(fontSize: 11.5),
                          ),
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
              const SizedBox(height: 10),
            ],

            // Real-time Connection Status Card
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                    : (isDark
                          ? const Color(0xFF1E293B)
                          : const Color(0xFFF1F5F9)),
                borderRadius: BorderRadius.circular(10),
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
                      : (isDark ? Colors.white12 : const Color(0xFFCBD5E1)),
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
                  const SizedBox(width: 10),
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
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
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
                          const Text(
                            'Grant location permission above to enable auto check-in',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.deepOrange,
                            ),
                          )
                        else if (currentSsid != null &&
                            (currentSsid.toLowerCase().replaceAll(' ', '') ==
                                    'secretstar' ||
                                currentSsid.toLowerCase().replaceAll(' ', '') ==
                                    'secreatstar'))
                          const Text(
                            '💻 Personal Mac Hotspot (Ultra-fast ethernet mode)',
                            style: TextStyle(fontSize: 11, color: Colors.green),
                          )
                        else if (currentSsid != null &&
                            currentSsid.toLowerCase().contains('zavisoft'))
                          const Text(
                            '🏢 Zavisoft Office Wi-Fi',
                            style: TextStyle(fontSize: 11, color: Colors.teal),
                          )
                        else if (isOfficeConnected)
                          const Text(
                            '🏢 Verified Office Network',
                            style: TextStyle(fontSize: 11, color: Colors.teal),
                          )
                        else if (currentSsid != null && currentSsid.isNotEmpty)
                          Text(
                            'Not yet recognized as office network',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white60 : Colors.black54,
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
                          vertical: 4,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.add, size: 14),
                      label: const Text(
                        'Add This',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
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
            const SizedBox(height: 14),

            // Active Configured Networks Chips
            Text(
              'Active Office SSIDs:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : const Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 6),
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
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isCurrent
                            ? FontWeight.bold
                            : FontWeight.w500,
                        color: isCurrent
                            ? (isDark
                                  ? Colors.greenAccent
                                  : Colors.green.shade900)
                            : (isDark ? Colors.white : const Color(0xFF1E293B)),
                      ),
                      children: [
                        if (isMacHotspot)
                          TextSpan(
                            text: ' (Mac)',
                            style: TextStyle(
                              fontSize: 10,
                              color: isDark ? Colors.white60 : Colors.black54,
                              fontWeight: FontWeight.normal,
                            ),
                          )
                        else if (isZavisoft)
                          TextSpan(
                            text: ' (Main)',
                            style: TextStyle(
                              fontSize: 10,
                              color: isDark ? Colors.white60 : Colors.black54,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                      ],
                    ),
                  ),
                  backgroundColor: isCurrent
                      ? (isDark
                            ? Colors.green.withValues(alpha: 0.2)
                            : const Color(0xFFDCFCE7))
                      : (isDark
                            ? const Color(0xFF1E293B)
                            : const Color(0xFFF8FAFC)),
                  deleteIcon: const Icon(Icons.close, size: 14),
                  onDeleted: configuredList.length > 1
                      ? () {
                          ref
                              .read(settingsNotifierProvider.notifier)
                              .removeOfficeWifiSsid(ssid);
                        }
                      : null,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: isCurrent
                          ? (isDark
                                ? Colors.green.withValues(alpha: 0.5)
                                : const Color(0xFF86EFAC))
                          : (isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),

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
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E3A8A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
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
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                children: [
                  if (!configuredList.any((s) => s.toLowerCase() == 'zavisoft'))
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 14),
                      label: const Text(
                        'Preset: Zavisoft',
                        style: TextStyle(fontSize: 11),
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
                        style: TextStyle(fontSize: 11),
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
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.green.withValues(alpha: 0.15)
                    : const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(8),
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
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'স্মার্ট হ্যান্ডঅফ সক্রিয়: দরজায় "Zavisoft" পেলে চেক-ইন অ্যালার্ট আসবে। এরপর ডেস্কে বসে ম্যাকের "SecretStar" হটস্পটে সুইচ করলে ৪৫ সেকেন্ড গ্রেস পিরিয়ড থাকায় কোনো ভুল চেক-আউট হবে না।',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? const Color(0xFFA7F3D0)
                            : const Color(0xFF166534),
                        height: 1.3,
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
                const SizedBox(width: 8),
                Text(
                  'Weekly Off-Days (No Office Work)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Office Wi-Fi check-in/out and dinner alerts are paused on these days. AI switches to weekend deep study mode.',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            const SizedBox(height: 10),
            _buildWeekdayChips(settings.offDays),
          ],
        ),
      ),
    );
  }

  Widget _buildBackupRestoreCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          'Offline Data Backup & Restore',
          Icons.cloud_sync_rounded,
          Colors.teal.shade700,
        ),
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.teal.withValues(alpha: 0.2)
                          : Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.download_rounded,
                      color: isDark ? Colors.tealAccent : Colors.teal.shade700,
                    ),
                  ),
                  title: const Text(
                    'Export Study Backup (JSON)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: const Text(
                    'Save all Weak Topics, LiveMCQ routines & daily logs',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: () => _handleExportBackup(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.indigo.withValues(alpha: 0.2)
                          : Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.upload_rounded,
                      color: isDark
                          ? Colors.indigoAccent
                          : Colors.indigo.shade700,
                    ),
                  ),
                  title: const Text(
                    'Restore from Backup (JSON)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: const Text(
                    'Restore data from clipboard or backup JSON file',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: () => _handleRestoreBackup(context),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _handleExportBackup(BuildContext context) async {
    try {
      final db = ref.read(appDatabaseProvider);
      final jsonString = await db.exportBackupJson();
      final Map<String, dynamic> parsed =
          jsonDecode(jsonString) as Map<String, dynamic>;

      final topicsCount = (parsed['weak_topics'] as List?)?.length ?? 0;
      final examsCount = (parsed['exam_schedules'] as List?)?.length ?? 0;
      final logsCount = (parsed['daily_energy_logs'] as List?)?.length ?? 0;

      if (!context.mounted) return;
      final isDark = Theme.of(context).brightness == Brightness.dark;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF111827) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.teal.withValues(alpha: 0.2)
                          : Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.cloud_done_rounded,
                      color: isDark ? Colors.tealAccent : Colors.teal.shade700,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Export Study Data Backup',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'Zero-loss offline JSON format',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E293B)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Column(
                  children: [
                    _buildBackupStatRow(
                      'Weak Topics & Syllabus',
                      '$topicsCount items',
                      Icons.playlist_add_check,
                      isDark,
                    ),
                    const Divider(height: 12),
                    _buildBackupStatRow(
                      'LiveMCQ Exam Schedules',
                      '$examsCount exams',
                      Icons.calendar_today_outlined,
                      isDark,
                    ),
                    const Divider(height: 12),
                    _buildBackupStatRow(
                      'Energy & Fatigue Logs',
                      '$logsCount logs',
                      Icons.bolt_outlined,
                      isDark,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Option 1: Save directly to Download folder (Recommended)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.download_rounded, size: 20),
                  label: const Text(
                    'Download ফোল্ডারে সেভ করুন',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final nowStr = DateTime.now().toIso8601String().substring(
                      0,
                      10,
                    );
                    final fileName = 'life_study_backup_$nowStr.json';
                    final result = await AppExportService.saveToDownloads(
                      fileName: fileName,
                      content: jsonString,
                    );
                    if (!context.mounted) return;
                    if (result.success) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: Colors.teal.shade800,
                          duration: const Duration(seconds: 6),
                          content: Text(result.bengaliSummary),
                          action: SnackBarAction(
                            textColor: Colors.tealAccent,
                            label: 'পথ কপি',
                            onPressed: () {
                              if (result.filePath != null) {
                                Clipboard.setData(
                                  ClipboardData(text: result.filePath!),
                                );
                              }
                            },
                          ),
                        ),
                      );
                    } else if (!result.wasCancelled) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: Colors.red.shade800,
                          content: Text(result.bengaliSummary),
                        ),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(height: 10),
              // Option 2 & 3: Save As (Custom Folder) & Copy JSON
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(
                        Icons.create_new_folder_outlined,
                        size: 16,
                      ),
                      label: const Text(
                        'অন্য ফোল্ডার',
                        style: TextStyle(fontSize: 12.5),
                      ),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        final nowStr = DateTime.now()
                            .toIso8601String()
                            .substring(0, 10);
                        final fileName = 'life_study_backup_$nowStr.json';
                        final result = await AppExportService.saveWithPicker(
                          fileName: fileName,
                          content: jsonString,
                          dialogTitle: 'ব্যাকআপ ফাইল সেভ করার ফোল্ডার বেছে নিন',
                        );
                        if (!context.mounted) return;
                        if (result.success) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: Colors.indigo.shade800,
                              duration: const Duration(seconds: 6),
                              content: Text(result.bengaliSummary),
                              action: SnackBarAction(
                                textColor: Colors.indigoAccent,
                                label: 'পথ কপি',
                                onPressed: () {
                                  if (result.filePath != null) {
                                    Clipboard.setData(
                                      ClipboardData(text: result.filePath!),
                                    );
                                  }
                                },
                              ),
                            ),
                          );
                        } else if (!result.wasCancelled) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: Colors.red.shade800,
                              content: Text(result.bengaliSummary),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text(
                        'Copy JSON',
                        style: TextStyle(fontSize: 12.5),
                      ),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: jsonString));
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Backup JSON copied to clipboard! You can paste and save it anywhere.',
                            ),
                            backgroundColor: Colors.teal,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildBackupStatRow(
    String label,
    String value,
    IconData icon, [
    bool isDark = false,
  ]) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: isDark ? Colors.blueGrey.shade200 : Colors.blueGrey,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white70 : const Color(0xFF334155),
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }

  Future<void> _handleRestoreBackup(BuildContext context) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF111827) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.indigo.withValues(alpha: 0.2)
                        : Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.settings_backup_restore_rounded,
                    color: isDark
                        ? Colors.indigoAccent
                        : Colors.indigo.shade700,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Restore from Backup',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'Import without losing existing data',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isDark ? Colors.white12 : Colors.grey.shade200,
                ),
              ),
              leading: CircleAvatar(
                backgroundColor: isDark
                    ? Colors.indigo.withValues(alpha: 0.3)
                    : const Color(0xFFEEF2FF),
                child: Icon(
                  Icons.paste_rounded,
                  color: isDark ? Colors.indigoAccent : Colors.indigo,
                ),
              ),
              title: const Text(
                'Paste JSON from Clipboard',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              subtitle: const Text(
                'Directly read from clipboard',
                style: TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 14),
              onTap: () async {
                Navigator.pop(ctx);
                final clipData = await Clipboard.getData(Clipboard.kTextPlain);
                final text = clipData?.text?.trim() ?? '';
                if (text.isEmpty) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Clipboard is empty. Please copy the backup JSON first.',
                        ),
                        backgroundColor: Colors.orange,
                      ),
                    );
                  }
                  return;
                }
                if (context.mounted) {
                  _executeRestore(context, text);
                }
              },
            ),
            const SizedBox(height: 10),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isDark ? Colors.white12 : Colors.grey.shade200,
                ),
              ),
              leading: CircleAvatar(
                backgroundColor: isDark
                    ? Colors.green.withValues(alpha: 0.25)
                    : const Color(0xFFF0FDF4),
                child: Icon(
                  Icons.file_open_rounded,
                  color: isDark ? Colors.greenAccent : Colors.green,
                ),
              ),
              title: const Text(
                'Pick JSON Backup File',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              subtitle: const Text(
                'Select a .json file from phone storage',
                style: TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 14),
              onTap: () async {
                Navigator.pop(ctx);
                final picked = await FilePicker.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['json'],
                );
                if (picked.isNotEmpty && picked.first.path != null) {
                  final file = File(picked.first.path!);
                  final content = await file.readAsString();
                  if (context.mounted) {
                    _executeRestore(context, content);
                  }
                }
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _executeRestore(BuildContext context, String jsonString) async {
    try {
      final db = ref.read(appDatabaseProvider);
      final result = await db.importBackupJson(jsonString);

      final topicsCount = result['weak_topics'] ?? 0;
      final examsCount = result['exam_schedules'] ?? 0;
      final logsCount = result['daily_energy_logs'] ?? 0;
      final mistakesCount = result['mistakes'] ?? 0;

      if (!context.mounted) return;
      final isDark = Theme.of(context).brightness == Brightness.dark;

      showDialog(
        context: context,
        builder: (dCtx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 28),
              SizedBox(width: 10),
              Text('Restore Complete!'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'আপনার ব্যাকআপ সফলভাবে রিস্টোর হয়েছে:',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              Text('• $topicsCount টি Weak Topics যুক্ত বা আপডেট হয়েছে'),
              Text('• $examsCount টি LiveMCQ পরীক্ষার শিডিউল রিস্টোর হয়েছে'),
              Text('• $logsCount টি Daily Energy Logs সিঙ্ক হয়েছে'),
              if (mistakesCount > 0)
                Text(
                  '• $mistakesCount টি Mistake Notebook প্রশ্ন রিস্টোর হয়েছে',
                ),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo.shade700,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(dCtx),
              child: const Text('ঠিক আছে'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (dCtx) => AlertDialog(
            title: const Text('Restore Failed'),
            content: Text('Invalid backup JSON format:\n$e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dCtx),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    }
  }

  Widget _buildThemeSelectorCard() {
    final currentMode = ref.watch(themeModeProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select Interface Color Scheme',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Midnight OLED Dark reduces eye fatigue after long coding sessions in the office.',
              style: TextStyle(
                fontSize: 11.5,
                color: isDark ? Colors.white60 : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.brightness_auto, size: 20),
              title: const Text(
                'System Default',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              subtitle: const Text(
                'Follows device light / dark schedule',
                style: TextStyle(fontSize: 11),
              ),
              trailing: currentMode == ThemeMode.system
                  ? const Icon(
                      Icons.check_circle,
                      color: Color(0xFF6366F1),
                      size: 20,
                    )
                  : const Icon(
                      Icons.circle_outlined,
                      color: Colors.grey,
                      size: 20,
                    ),
              onTap: () => ref
                  .read(themeModeProvider.notifier)
                  .setThemeMode(ThemeMode.system),
            ),
            const Divider(height: 1),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.light_mode,
                size: 20,
                color: Colors.amber,
              ),
              title: const Text(
                'Clean Light Mode',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              subtitle: const Text(
                'Crisp white slate and deep indigo',
                style: TextStyle(fontSize: 11),
              ),
              trailing: currentMode == ThemeMode.light
                  ? const Icon(
                      Icons.check_circle,
                      color: Color(0xFF6366F1),
                      size: 20,
                    )
                  : const Icon(
                      Icons.circle_outlined,
                      color: Colors.grey,
                      size: 20,
                    ),
              onTap: () => ref
                  .read(themeModeProvider.notifier)
                  .setThemeMode(ThemeMode.light),
            ),
            const Divider(height: 1),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.dark_mode,
                size: 20,
                color: Color(0xFF6366F1),
              ),
              title: const Text(
                'Midnight OLED Dark 🌙',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                'Obsidian black (#090D1A) - zero eye strain & power saving',
                style: TextStyle(fontSize: 11),
              ),
              trailing: currentMode == ThemeMode.dark
                  ? const Icon(
                      Icons.check_circle,
                      color: Color(0xFF6366F1),
                      size: 20,
                    )
                  : const Icon(
                      Icons.circle_outlined,
                      color: Colors.grey,
                      size: 20,
                    ),
              onTap: () => ref
                  .read(themeModeProvider.notifier)
                  .setThemeMode(ThemeMode.dark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeaknessHealerToggleCard(SettingsState settings) {
    final isEnabled = settings.isWeaknessHealingEnabled;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981)
                        .withValues(alpha: isDark ? 0.25 : 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.healing_rounded,
                    color: Color(0xFF10B981),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Daily 3-Min Weakness Micro Drills',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        'অটো-উইকনেস হিলিং ইঞ্জিন ও ড্রিল কন্ট্রোল',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: isEnabled,
                  activeThumbColor: const Color(0xFF10B981),
                  onChanged: (val) {
                    ref
                        .read(settingsNotifierProvider.notifier)
                        .setWeaknessHealingEnabled(val);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          val
                              ? 'অটো-উইকনেস হিলিং সক্রিয় করা হয়েছে 🩺'
                              : 'অটো-উইকনেস হিলিং বন্ধ রাখা হয়েছে ⏸️',
                        ),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              isEnabled
                  ? '✓ সক্রিয়: লাইভ এমসিকিউ বা পরীক্ষায় ভুল হওয়া টপিকগুলোর ওপর ড্যাশবোর্ডে দৈনিক ৩ মিনিটের মাইক্রো-রিভিশন ড্রিল প্রদর্শন করা হবে।'
                  : '⏸️ নিষ্ক্রিয়: দুর্বল টপিকের মাইক্রো-ড্রিল কার্ড ড্যাশবোর্ডে প্রদর্শিত হবে না। যেকোনো সময় পুনরায় চালু করতে পারেন।',
              style: TextStyle(
                fontSize: 11.5,
                color: isEnabled
                    ? (isDark ? Colors.greenAccent : Colors.green.shade800)
                    : (isDark ? Colors.white60 : Colors.grey.shade700),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? 0.25 : 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isDark ? const Color(0xFF93C5FD) : const Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }
}
