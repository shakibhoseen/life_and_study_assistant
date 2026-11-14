import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_provider.dart';
import '../../../../core/theme/fluent_tokens.dart';
import '../../../../core/services/ai/routine_parser_service.dart';
import '../../../../core/services/attendance/packly_attendance_service.dart';
import '../../../../core/services/attendance/steadfast_lunch_service.dart';
import '../../../../core/services/background/wifi_monitor_service.dart';
import '../../../../core/services/notification/notification_service.dart';
import '../../../live_mcq/presentation/providers/exam_schedule_provider.dart';
import '../providers/settings_provider.dart';
import '../../../spaced_repetition/presentation/providers/spaced_repetition_provider.dart';

class AutomationTestCard extends ConsumerWidget {
  const AutomationTestCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsNotifierProvider).value;
    final officeSsid = settings?.officeWifiSsid ?? 'Office-WiFi';
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: FluentRadius.cardBorder,
        side: FluentStroke.side(theme.brightness),
      ),
      child: Padding(
        padding: const EdgeInsets.all(FluentSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.developer_mode, color: scheme.primary, size: 20),
                const SizedBox(width: FluentSpacing.s),
                Expanded(
                  child: Text(
                    'Trigger Engine & Automation Lab',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: FluentType.bodyStrong.copyWith(
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: FluentSpacing.xs),
            Text(
              'Test background notifications, Wi-Fi trigger simulation, and notification tray action buttons directly on this device.',
              style: FluentType.caption.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: FluentSpacing.l),
            Wrap(
              spacing: FluentSpacing.s,
              runSpacing: FluentSpacing.s,
              children: [
                _buildChip(
                  context: context,
                  icon: Icons.lunch_dining_rounded,
                  label: '🍱 Ping Lunch Portal',
                  onPressed: () async {
                    final res = await SteadfastLunchService.instance.ping();
                    if (context.mounted) {
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
                _buildChip(
                  context: context,
                  icon: Icons.notifications_active,
                  label: '🍱 Test 5 PM Lunch Reminder',
                  onPressed: () async {
                    await NotificationService.instance.requestPermissions();
                    await NotificationService.instance
                        .showSteadfastLunchReminderNotification(
                          isTomorrowBooked: false,
                          cutoff: '6:00 PM',
                        );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            '🍱 Fired 5:00 PM Lunch Reminder with "Book Tomorrow" button! Check tray.',
                          ),
                        ),
                      );
                    }
                  },
                ),
                _buildChip(
                  context: context,
                  icon: Icons.swap_horiz,
                  label: '🍱 Mock Toggle Tomorrow Lunch',
                  onPressed: () async {
                    final res = await SteadfastLunchService.instance
                        .toggleTomorrowMeal(forceSimulate: true);
                    if (context.mounted) {
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
                _buildChip(
                  context: context,
                  icon: Icons.check_circle_outline,
                  label: '🧪 Mock Check-In (On-Time)',
                  onPressed: () async {
                    final res = await PacklyAttendanceService.instance.checkIn(
                      forceSimulate: true,
                    );
                    await NotificationService.instance
                        .showOfficeCheckInSuccessNotification(
                          time: res.status?.checkInTime ?? '09:05 AM',
                          isLate: false,
                        );
                    await ref
                        .read(settingsNotifierProvider.notifier)
                        .updateCheckInStatus('Punched In');
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: Colors.green.shade800,
                          content: Text('${res.message} (Notification sent)'),
                        ),
                      );
                    }
                  },
                ),
                _buildChip(
                  context: context,
                  icon: Icons.warning_amber_rounded,
                  label: '🧪 Mock Check-In (Late)',
                  onPressed: () async {
                    await PacklyAttendanceService.instance.checkIn(
                      forceSimulate: true,
                    );
                    await NotificationService.instance
                        .showOfficeCheckInSuccessNotification(
                          time: '09:18 AM',
                          isLate: true,
                        );
                    await ref
                        .read(settingsNotifierProvider.notifier)
                        .updateCheckInStatus('Punched In');
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: Colors.orange.shade900,
                          content: const Text(
                            '[TEST MODE] Simulated Check-In at 09:18 AM (LATE > 9:14 AM)',
                          ),
                        ),
                      );
                    }
                  },
                ),
                _buildChip(
                  context: context,
                  icon: Icons.logout,
                  label: '🧪 Mock Check-Out',
                  onPressed: () async {
                    final res = await PacklyAttendanceService.instance.checkOut(
                      forceSimulate: true,
                    );
                    await NotificationService.instance
                        .showOfficeCheckOutSuccessNotification(
                          time: res.status?.checkOutTime ?? '06:05 PM',
                        );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: Colors.teal.shade800,
                          content: Text(
                            '${res.message} (Check notification tray)',
                          ),
                        ),
                      );
                    }
                  },
                ),
                _buildChip(
                  context: context,
                  icon: Icons.alarm,
                  label: '🚨 Test 9:15 AM Late Alarm',
                  onPressed: () async {
                    await NotificationService.instance.requestPermissions();
                    await NotificationService.instance
                        .showLateWarningNotification(minutesRemaining: 4);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            '🚨 Fired 9:15 AM Late Warning Alarm with "Punch In Now" button! Check tray.',
                          ),
                        ),
                      );
                    }
                  },
                ),
                _buildChip(
                  context: context,
                  icon: Icons.alarm_off,
                  label: '🚨 Test 9:15 AM Cutoff Passed',
                  onPressed: () async {
                    await NotificationService.instance.requestPermissions();
                    await NotificationService.instance
                        .showLateWarningNotification(minutesRemaining: 0);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            '🚨 Fired 9:15 AM Cutoff Passed penalty alert! Check tray.',
                          ),
                        ),
                      );
                    }
                  },
                ),
                _buildChip(
                  context: context,
                  icon: Icons.notifications_active,
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
                  context: context,
                  icon: Icons.flash_on,
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
                  context: context,
                  icon: Icons.psychology,
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
                  context: context,
                  icon: Icons.dinner_dining,
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
                  context: context,
                  icon: Icons.exit_to_app,
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
                  context: context,
                  icon: Icons.wifi,
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
                  context: context,
                  icon: Icons.wifi_off,
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
                  context: context,
                  icon: Icons.share,
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

  /// One Fluent chip. These used to carry fifteen different accent colours;
  /// in Fluent the accent marks the thing you act on, so they all share it.
  Widget _buildChip({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ActionChip(
      avatar: Icon(icon, size: 16, color: scheme.primary),
      label: Text(
        label,
        style: FluentType.caption.copyWith(color: scheme.onSurface),
      ),
      backgroundColor: FluentLayer.subtle(scheme.primary, theme.brightness),
      side: BorderSide(
        color: FluentStroke.card(theme.brightness),
        width: FluentStroke.width,
      ),
      shape: RoundedRectangleBorder(borderRadius: FluentRadius.controlBorder),
      onPressed: onPressed,
    );
  }
}
