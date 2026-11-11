import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/config/notification_constants.dart';
import '../../../../core/services/attendance/packly_attendance_service.dart';
import '../../../../core/services/attendance/steadfast_lunch_service.dart';
import '../../../../core/services/background/office_sentinel_service.dart';
import '../../../../core/services/notification/notification_service.dart';
import '../../../dashboard/presentation/providers/office_portal_provider.dart';
import '../widgets/automation_test_card.dart';

class AttendanceTestLabScreen extends ConsumerStatefulWidget {
  const AttendanceTestLabScreen({super.key});

  @override
  ConsumerState<AttendanceTestLabScreen> createState() => _AttendanceTestLabScreenState();
}

class _AttendanceTestLabScreenState extends ConsumerState<AttendanceTestLabScreen> {
  bool _simulationMode = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _simulationMode =
          prefs.getBool(NotificationConstants.prefPacklySimulationMode) ?? false;
    });
  }

  Future<void> _toggleSimulationMode(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(NotificationConstants.prefPacklySimulationMode, val);
    setState(() => _simulationMode = val);
    await ref.read(officeAttendanceProvider.notifier).setSimulationMode(val);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: val ? Colors.amber.shade900 : Colors.teal.shade800,
          content: Text(
            val
                ? '🧪 Safe Simulation Mode ON! এখন আসল সার্ভার নিরাপদ রেখে ডামি টেস্ট করতে পারেন।'
                : '✅ Live Mode ON! ডামি মেমরি মুছে লাইভ সার্ভারের সাথে রিয়েল-টাইম সিঙ্ক হয়েছে।',
          ),
        ),
      );
    }
  }

  Future<void> _clearSimulationData() async {
    setState(() => _isLoading = true);
    await PacklyAttendanceService.instance.clearSimulationData(sanitizeRealKeys: true);
    await ref.read(officeAttendanceProvider.notifier).syncLiveAttendance();
    setState(() {
      _isLoading = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.teal,
          content: Text('🧹 ডামি সিমুলেশন স্টেট সফলভাবে ক্লিয়ার হয়েছে!'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('🧪 Portal & Automation Test Lab'),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Simulation Mode Master Control Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _simulationMode
                  ? (_isDarkTheme(context)
                      ? Colors.amber.withValues(alpha: 0.15)
                      : Colors.amber.shade50)
                  : (_isDarkTheme(context)
                      ? Colors.teal.withValues(alpha: 0.12)
                      : Colors.teal.shade50),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _simulationMode
                    ? Colors.amber.shade600
                    : Colors.teal.shade400,
                width: 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _simulationMode
                            ? Colors.amber.shade900
                            : Colors.teal.shade800,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _simulationMode ? Icons.science : Icons.verified_user,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _simulationMode
                                ? 'Simulation Mode: ACTIVE'
                                : 'Live Mode: ACTIVE',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: _simulationMode
                                  ? (_isDarkTheme(context)
                                      ? Colors.amberAccent
                                      : Colors.amber.shade900)
                                  : (_isDarkTheme(context)
                                      ? Colors.tealAccent
                                      : Colors.teal.shade900),
                            ),
                          ),
                          Text(
                            _simulationMode
                                ? 'Zero server hits. Real credentials safe.'
                                : 'Punches submit to Zavisoft & Steadfast servers.',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _simulationMode,
                      activeThumbColor: Colors.amber,
                      onChanged: _toggleSimulationMode,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _simulationMode
                      ? 'টেস্ট মোড সচল থাকায় সমস্ত পাঞ্চ, ওয়াই-ফাই ট্রিগার ও নোটিফিকেশন সম্পূর্ণ সুরক্ষিত আলাদা মেমরিতে চলবে। সার্ভারে কোনো আসল হাজিরা পাঠানো হবে না।'
                      : 'লাইভ মোড সচল থাকলে প্রতিটি চেক-ইন ও চেক-আউট সরাসরি Zavisoft Packly পোর্টালে সাবমিট হবে।',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                  ),
                  icon: const Icon(Icons.delete_sweep, size: 16),
                  label: const Text('Reset Mock Simulation Data', style: TextStyle(fontSize: 12)),
                  onPressed: _isLoading ? null : _clearSimulationData,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // 2. Mock Attendance Punch Triggers
          _buildSectionCard(
            title: '🏢 Zavisoft Packly Attendance Triggers',
            icon: Icons.badge_outlined,
            isDark: isDark,
            children: [
              const Text(
                'পরীক্ষামূলক ডামি পাঞ্চ দিয়ে অ্যাপের কাউন্টডাউন, ৯-ঘণ্টা ওয়ার্কডে প্রগ্রেস বার ও স্টেট আপডেট টেস্ট করুন:',
                style: TextStyle(fontSize: 11.5),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal.shade700,
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.login, size: 16),
                    label: const Text('Force Mock Check-In'),
                    onPressed: () async {
                      final res = await PacklyAttendanceService.instance.checkIn(forceSimulate: true);
                      await ref.read(officeAttendanceProvider.notifier).syncLiveAttendance();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(res.message)),
                        );
                      }
                    },
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo.shade700,
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.logout, size: 16),
                    label: const Text('Force Mock Check-Out'),
                    onPressed: () async {
                      final res = await PacklyAttendanceService.instance.checkOut(forceSimulate: true);
                      await ref.read(officeAttendanceProvider.notifier).syncLiveAttendance();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(res.message)),
                        );
                      }
                    },
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                    icon: const Icon(Icons.sync, size: 16),
                    label: const Text('Sync Live Status'),
                    onPressed: () async {
                      await ref.read(officeAttendanceProvider.notifier).syncLiveAttendance();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Status refreshed with portal!')),
                        );
                      }
                    },
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                    icon: const Icon(Icons.network_ping, size: 16),
                    label: const Text('Ping Packly Server'),
                    onPressed: () async {
                      final res = await PacklyAttendanceService.instance.ping();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: res.success ? Colors.green.shade800 : Colors.red.shade800,
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
          const SizedBox(height: 18),

          // 3. Urgent Alarms & Departure Distance Test
          _buildSectionCard(
            title: '🚨 Urgent Alarms & Departure Watchdogs',
            icon: Icons.warning_amber_rounded,
            isDark: isDark,
            children: [
              const Text(
                'অফিস থেকে দূরে চলে যাওয়া, লেট পেনাল্টি প্রিভেনশন অ্যালার্ম ও ব্যাকগ্রাউন্ড সেন্টিনেল টেস্ট করুন:',
                style: TextStyle(fontSize: 11.5),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade800,
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.crisis_alert, size: 16),
                    label: const Text('🚨 Test Urgent Distance Alarm'),
                    onPressed: () async {
                      await NotificationService.instance.showUrgentDepartureWarningNotification(
                        distanceMeters: 2400.0,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('🚨 Fired Urgent Distance Siren Alert! Check notification tray.'),
                          ),
                        );
                      }
                    },
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber.shade900,
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.alarm, size: 16),
                    label: const Text('⚡ Test 9:15 AM Late Alarm'),
                    onPressed: () async {
                      await NotificationService.instance.showLateWarningNotification(
                        minutesRemaining: 5,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('⚡ Fired 9:15 AM Late Prevention Alarm! Check tray.'),
                          ),
                        );
                      }
                    },
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                    icon: const Icon(Icons.run_circle_outlined, size: 16),
                    label: const Text('Start Morning Sentinel'),
                    onPressed: () async {
                      await OfficeSentinelService.instance.startMorningSentinel();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('🏢 Morning Sentinel active in foreground!')),
                        );
                      }
                    },
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                    icon: const Icon(Icons.exit_to_app, size: 16),
                    label: const Text('Start Evening Sentinel'),
                    onPressed: () async {
                      await OfficeSentinelService.instance.startEveningSentinel();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('🏢 Evening Departure Sentinel active!')),
                        );
                      }
                    },
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: Colors.redAccent,
                    ),
                    icon: const Icon(Icons.stop_circle_outlined, size: 16),
                    label: const Text('Stop Sentinel Service'),
                    onPressed: () async {
                      await OfficeSentinelService.instance.stopSentinel();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('🛑 Sentinel stopped.')),
                        );
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),

          // 4. Steadfast Lunch Portal Diagnostics
          _buildSectionCard(
            title: '🍱 Steadfast Lunch Portal Triggers',
            icon: Icons.lunch_dining_rounded,
            isDark: isDark,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                    icon: const Icon(Icons.network_ping, size: 16),
                    label: const Text('Ping Lunch Portal'),
                    onPressed: () async {
                      final res = await SteadfastLunchService.instance.ping();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: res.success ? Colors.green.shade800 : Colors.red.shade800,
                            content: Text(res.message),
                          ),
                        );
                      }
                    },
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                    icon: const Icon(Icons.notifications_active, size: 16),
                    label: const Text('Test 5 PM Lunch Reminder'),
                    onPressed: () async {
                      await NotificationService.instance.showSteadfastLunchReminderNotification(
                        isTomorrowBooked: false,
                        cutoff: '6:00 PM',
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('🍱 5 PM Reminder fired with "Book Tomorrow" button!')),
                        );
                      }
                    },
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                    icon: const Icon(Icons.swap_horiz, size: 16),
                    label: const Text('Mock Toggle Tomorrow'),
                    onPressed: () async {
                      final res = await SteadfastLunchService.instance.toggleTomorrowMeal(forceSimulate: true);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(res.message)),
                        );
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),

          // 5. Automation Test Card (Full developer tools)
          const AutomationTestCard(),
        ],
      ),
    );
  }

  bool _isDarkTheme(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required bool isDark,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: isDark ? Colors.tealAccent : Colors.teal.shade800),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          ...children,
        ],
      ),
    );
  }
}
