import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_provider.dart';
import '../../../../core/services/ai/routine_parser_service.dart';
import '../../../../core/services/background/wifi_monitor_service.dart';
import '../../../../core/services/notification/notification_service.dart';
import '../../../live_mcq/presentation/providers/exam_schedule_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../spaced_repetition/presentation/providers/spaced_repetition_provider.dart';

class AutomationTestCard extends ConsumerWidget {
  const AutomationTestCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsNotifierProvider).value;
    final officeSsid = settings?.officeWifiSsid ?? 'Office-WiFi';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.developer_mode,
                  color: isDark ? Colors.blueGrey.shade200 : Colors.blueGrey,
                  size: 22,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Trigger Engine & Automation Lab',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Test background notifications, Wi-Fi trigger simulation, and notification tray action buttons directly on this device.',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildChip(
                  isDark: isDark,
                  icon: Icons.notifications_active,
                  color: Colors.indigo,
                  label: 'Test Check-In Alert',
                  onPressed: () async {
                    await NotificationService.instance.requestPermissions();
                    await NotificationService.instance
                        .showOfficeCheckInReminder(
                          officeSsid: officeSsid,
                          ignoreOffDay: true,
                        );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Fired Check-In heads-up notification! Check tray.',
                          ),
                        ),
                      );
                    }
                  },
                ),
                _buildChip(
                  isDark: isDark,
                  icon: Icons.flash_on,
                  color: Colors.amber,
                  label: 'Test 5s Office Flashcard',
                  onPressed: () async {
                    await NotificationService.instance.requestPermissions();
                    await ref
                        .read(spacedRepetitionNotifierProvider.notifier)
                        .triggerOfficeFlashcardNotification();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            '⚡ Fired 5-second Flashcard! Check notification tray.',
                          ),
                        ),
                      );
                    }
                  },
                ),
                _buildChip(
                  isDark: isDark,
                  icon: Icons.psychology,
                  color: Colors.purple,
                  label: 'Test Spaced Review Alert',
                  onPressed: () async {
                    await NotificationService.instance.requestPermissions();
                    final sent = await ref
                        .read(spacedRepetitionNotifierProvider.notifier)
                        .triggerDueReviewNotification();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            sent
                                ? '🧠 Fired Spaced Repetition notification! Check tray.'
                                : 'No due items right now. Add a rule or wait for scheduled interval.',
                          ),
                        ),
                      );
                    }
                  },
                ),
                _buildChip(
                  isDark: isDark,
                  icon: Icons.dinner_dining,
                  color: Colors.deepOrange,
                  label: 'Test 4 PM Dinner Tray',
                  onPressed: () async {
                    await NotificationService.instance.requestPermissions();
                    await NotificationService.instance
                        .showInstantDinnerReminder();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Fired Dinner Cutoff notification with Yes/No buttons!',
                          ),
                        ),
                      );
                    }
                  },
                ),
                _buildChip(
                  isDark: isDark,
                  icon: Icons.exit_to_app,
                  color: Colors.purple,
                  label: 'Test Check-Out Alert',
                  onPressed: () async {
                    await NotificationService.instance.requestPermissions();
                    await NotificationService.instance
                        .showOfficeCheckOutReminder(ignoreOffDay: true);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Fired Check-Out reminder notification!',
                          ),
                        ),
                      );
                    }
                  },
                ),
                _buildChip(
                  isDark: isDark,
                  icon: Icons.wifi,
                  color: Colors.teal,
                  label: 'Simulate Office Wi-Fi',
                  onPressed: () async {
                    await WifiMonitorService.instance
                        .simulateOfficeWifiConnection(testSsid: officeSsid);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Simulated connected to "$officeSsid"'),
                        ),
                      );
                    }
                  },
                ),
                _buildChip(
                  isDark: isDark,
                  icon: Icons.wifi_off,
                  color: Colors.redAccent,
                  label: 'Simulate Wi-Fi Disconnect',
                  onPressed: () async {
                    await WifiMonitorService.instance
                        .simulateOfficeWifiDisconnection();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Simulated office Wi-Fi disconnection'),
                        ),
                      );
                    }
                  },
                ),
                _buildChip(
                  isDark: isDark,
                  icon: Icons.share,
                  color: Colors.deepPurple,
                  label: 'Simulate Shared Routine',
                  onPressed: () async {
                    const samplePost =
                        'LiveMCQ 47th BCS Final Crash Routine:\n'
                        '2026-10-29 | 10:00 PM | Bangla Grammar: কারক ও সমাস | Daily Exam\n'
                        '2026-10-30 | 10:00 PM | Math: লাভ-ক্ষতি ও সুদকষা | Daily Exam\n'
                        '2026-11-01 | 09:00 PM | General Science: চুম্বক ও স্থির তড়িৎ | Model Test';
                    final items = await RoutineParserService.instance
                        .parseRoutineFromText(samplePost);
                    final db = ref.read(appDatabaseProvider);
                    final result = await RoutineParserService.instance
                        .saveParsedRoutinesToDatabase(db, items);
                    ref.invalidate(upcomingExamsStreamProvider);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: result.allDuplicates
                              ? Colors.amber.shade900
                              : Colors.green.shade800,
                          content: Text(result.toBengaliMessage()),
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
    );
  }

  Widget _buildChip({
    required bool isDark,
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onPressed,
  }) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: isDark ? color : color),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: isDark ? Colors.white : Colors.black87,
        ),
      ),
      backgroundColor: isDark
          ? color.withValues(alpha: 0.18)
          : color.withValues(alpha: 0.1),
      side: BorderSide(
        color: isDark
            ? color.withValues(alpha: 0.3)
            : color.withValues(alpha: 0.2),
      ),
      onPressed: onPressed,
    );
  }
}
