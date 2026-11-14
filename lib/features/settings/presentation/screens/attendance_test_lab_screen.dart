import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/config/notification_constants.dart';
import '../../../../core/services/attendance/packly_attendance_service.dart';
import '../../../../core/services/attendance/steadfast_lunch_service.dart';
import '../../../../core/services/background/lunch_sentinel_service.dart';
import '../../../../core/services/background/office_sentinel_service.dart';
import '../../../../core/services/notification/notification_service.dart';
import '../../../../core/services/system_settings_helper.dart';
import '../../../../core/theme/fluent_tokens.dart';
import '../../../dashboard/presentation/providers/office_portal_provider.dart';
import '../widgets/automation_test_card.dart';

class AttendanceTestLabScreen extends ConsumerStatefulWidget {
  const AttendanceTestLabScreen({super.key});

  @override
  ConsumerState<AttendanceTestLabScreen> createState() =>
      _AttendanceTestLabScreenState();
}

class _AttendanceTestLabScreenState
    extends ConsumerState<AttendanceTestLabScreen> {
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
          prefs.getBool(NotificationConstants.prefPacklySimulationMode) ??
          false;
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
    await PacklyAttendanceService.instance.clearSimulationData(
      sanitizeRealKeys: true,
    );
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;

    // Status colours: amber warns the app is in simulation, green confirms live.
    const warningColor = Color(0xFFF59E0B);
    const successColor = Color(0xFF10B981);
    final modeColor = _simulationMode ? warningColor : successColor;

    return Scaffold(
      appBar: AppBar(
        title: const Text('🧪 Portal & Automation Test Lab'),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(FluentSpacing.l),
        children: [
          // 1. Simulation Mode Master Control Card
          Container(
            padding: const EdgeInsets.all(FluentSpacing.l),
            decoration: BoxDecoration(
              color: FluentLayer.subtle(modeColor, brightness),
              borderRadius: FluentRadius.cardBorder,
              border: Border.all(
                color: modeColor.withValues(alpha: 0.55),
                width: FluentStroke.width,
              ),
              boxShadow: FluentElevation.card(brightness),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(FluentSpacing.s),
                      decoration: BoxDecoration(
                        color: modeColor,
                        borderRadius: FluentRadius.controlBorder,
                      ),
                      child: Icon(
                        _simulationMode ? Icons.science : Icons.verified_user,
                        // Sits on a saturated fill, so white is correct here.
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: FluentSpacing.m),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _simulationMode
                                ? 'Simulation Mode: ACTIVE'
                                : 'Live Mode: ACTIVE',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FluentType.bodyStrong.copyWith(
                              color: modeColor,
                            ),
                          ),
                          Text(
                            _simulationMode
                                ? 'Zero server hits. Real credentials safe.'
                                : 'Punches submit to Zavisoft & Steadfast servers.',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: FluentType.caption.copyWith(
                              color: scheme.onSurface.withValues(alpha: 0.65),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _simulationMode,
                      activeThumbColor: warningColor,
                      onChanged: _toggleSimulationMode,
                    ),
                  ],
                ),
                const SizedBox(height: FluentSpacing.m),
                Text(
                  _simulationMode
                      ? 'টেস্ট মোড সচল থাকায় সমস্ত পাঞ্চ, ওয়াই-ফাই ট্রিগার ও নোটিফিকেশন সম্পূর্ণ সুরক্ষিত আলাদা মেমরিতে চলবে। সার্ভারে কোনো আসল হাজিরা পাঠানো হবে না।'
                      : 'লাইভ মোড সচল থাকলে প্রতিটি চেক-ইন ও চেক-আউট সরাসরি Zavisoft Packly পোর্টালে সাবমিট হবে।',
                  style: FluentType.caption.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
                const SizedBox(height: FluentSpacing.m),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: scheme.error,
                    side: BorderSide(color: scheme.error),
                    shape: RoundedRectangleBorder(
                      borderRadius: FluentRadius.controlBorder,
                    ),
                  ),
                  icon: const Icon(Icons.delete_sweep, size: 16),
                  label: Text(
                    'Reset Mock Simulation Data',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FluentType.caption,
                  ),
                  onPressed: _isLoading ? null : _clearSimulationData,
                ),
              ],
            ),
          ),
          const SizedBox(height: FluentSpacing.l),

          // 2. Mock Attendance Punch Triggers
          _buildSectionCard(
            title: '🏢 Zavisoft Packly Attendance Triggers',
            icon: Icons.badge_outlined,
            context: context,
            children: [
              Text(
                'পরীক্ষামূলক ডামি পাঞ্চ দিয়ে অ্যাপের কাউন্টডাউন, ৯-ঘণ্টা ওয়ার্কডে প্রগ্রেস বার ও স্টেট আপডেট টেস্ট করুন:',
                style: FluentType.caption,
              ),
              const SizedBox(height: FluentSpacing.m),
              Wrap(
                spacing: FluentSpacing.s,
                runSpacing: FluentSpacing.s,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: FluentRadius.controlBorder,
                      ),
                    ),
                    icon: const Icon(Icons.login, size: 16),
                    label: const Text('Force Mock Check-In'),
                    onPressed: () async {
                      final res = await PacklyAttendanceService.instance
                          .checkIn(forceSimulate: true);
                      await ref
                          .read(officeAttendanceProvider.notifier)
                          .syncLiveAttendance();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(res.message)));
                      }
                    },
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: FluentRadius.controlBorder,
                      ),
                    ),
                    icon: const Icon(Icons.logout, size: 16),
                    label: const Text('Force Mock Check-Out'),
                    onPressed: () async {
                      final res = await PacklyAttendanceService.instance
                          .checkOut(forceSimulate: true);
                      await ref
                          .read(officeAttendanceProvider.notifier)
                          .syncLiveAttendance();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(res.message)));
                      }
                    },
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: FluentRadius.controlBorder,
                      ),
                    ),
                    icon: const Icon(Icons.sync, size: 16),
                    label: const Text('Sync Live Status'),
                    onPressed: () async {
                      await ref
                          .read(officeAttendanceProvider.notifier)
                          .syncLiveAttendance();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Status refreshed with portal!'),
                          ),
                        );
                      }
                    },
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: FluentRadius.controlBorder,
                      ),
                    ),
                    icon: const Icon(Icons.network_ping, size: 16),
                    label: const Text('Ping Packly Server'),
                    onPressed: () async {
                      final res = await PacklyAttendanceService.instance.ping();
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
                ],
              ),
            ],
          ),
          const SizedBox(height: FluentSpacing.l),

          // 3. Urgent Alarms & Departure Distance Test
          _buildSectionCard(
            title: '🚨 Urgent Alarms & Departure Watchdogs',
            icon: Icons.warning_amber_rounded,
            context: context,
            children: [
              Text(
                'অফিস থেকে দূরে চলে যাওয়া, লেট পেনাল্টি প্রিভেনশন অ্যালার্ম ও ব্যাকগ্রাউন্ড সেন্টিনেল টেস্ট করুন:',
                style: FluentType.caption,
              ),
              const SizedBox(height: FluentSpacing.m),
              Wrap(
                spacing: FluentSpacing.s,
                runSpacing: FluentSpacing.s,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: scheme.error,
                      foregroundColor: scheme.onError,
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: FluentRadius.controlBorder,
                      ),
                    ),
                    icon: const Icon(Icons.crisis_alert, size: 16),
                    label: const Text('🚨 Test Urgent Distance Alarm'),
                    onPressed: () async {
                      await NotificationService.instance
                          .showUrgentDepartureWarningNotification(
                            distanceMeters: 2400.0,
                          );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              '🚨 Fired Urgent Distance Siren Alert! Check notification tray.',
                            ),
                          ),
                        );
                      }
                    },
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: warningColor,
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: FluentRadius.controlBorder,
                      ),
                    ),
                    icon: const Icon(Icons.alarm, size: 16),
                    label: const Text('⚡ Test 9:15 AM Late Alarm'),
                    onPressed: () async {
                      await NotificationService.instance
                          .showLateWarningNotification(minutesRemaining: 5);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              '⚡ Fired 9:15 AM Late Prevention Alarm! Check tray.',
                            ),
                          ),
                        );
                      }
                    },
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: FluentRadius.controlBorder,
                      ),
                    ),
                    icon: const Icon(Icons.run_circle_outlined, size: 16),
                    label: const Text('Start Morning Sentinel'),
                    onPressed: () async {
                      await OfficeSentinelService.instance
                          .startMorningSentinel();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              '🏢 Morning Sentinel active in foreground!',
                            ),
                          ),
                        );
                      }
                    },
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: FluentRadius.controlBorder,
                      ),
                    ),
                    icon: const Icon(Icons.exit_to_app, size: 16),
                    label: const Text('Start Evening Sentinel'),
                    onPressed: () async {
                      await OfficeSentinelService.instance
                          .startEveningSentinel();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              '🏢 Evening Departure Sentinel active!',
                            ),
                          ),
                        );
                      }
                    },
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: scheme.error,
                      shape: RoundedRectangleBorder(
                        borderRadius: FluentRadius.controlBorder,
                      ),
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
          const SizedBox(height: FluentSpacing.l),

          // 4. Steadfast Lunch Portal Diagnostics
          _buildSectionCard(
            title: '🍱 Steadfast Lunch Portal Triggers',
            icon: Icons.lunch_dining_rounded,
            context: context,
            children: [
              Wrap(
                spacing: FluentSpacing.s,
                runSpacing: FluentSpacing.s,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: FluentRadius.controlBorder,
                      ),
                    ),
                    icon: const Icon(Icons.network_ping, size: 16),
                    label: const Text('Ping Lunch Portal'),
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
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: FluentRadius.controlBorder,
                      ),
                    ),
                    icon: const Icon(Icons.notifications_active, size: 16),
                    label: const Text('Test 5 PM Lunch Reminder'),
                    onPressed: () async {
                      await NotificationService.instance
                          .showSteadfastLunchReminderNotification(
                            isTomorrowBooked: false,
                            cutoff: '6:00 PM',
                          );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              '🍱 5 PM Reminder fired with "Book Tomorrow" button!',
                            ),
                          ),
                        );
                      }
                    },
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: FluentRadius.controlBorder,
                      ),
                    ),
                    icon: const Icon(Icons.swap_horiz, size: 16),
                    label: const Text('Mock Toggle Tomorrow'),
                    onPressed: () async {
                      final res = await SteadfastLunchService.instance
                          .toggleTomorrowMeal(forceSimulate: true);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(res.message)));
                      }
                    },
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: Colors.teal,
                    ),
                    icon: const Icon(Icons.local_shipping, size: 16),
                    label: const Text('Test: Car Arrived (Received)'),
                    onPressed: () async {
                      await NotificationService.instance.showLunchReceivedNotification(
                        time: '1:05 PM',
                        message: 'খাবার গাড়ি থেকে অফিসে রিসিভ করা হয়েছে। কিছুক্ষণের মধ্যে পরিবেশন শুরু হবে।',
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('📦 Test: Lunch Received alert fired!')),
                        );
                      }
                    },
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: Colors.green,
                    ),
                    icon: const Icon(Icons.restaurant, size: 16),
                    label: const Text('Test: Lunch Served'),
                    onPressed: () async {
                      await NotificationService.instance.showLunchServedNotification(
                        time: '1:18 PM',
                        message: 'ক্যান্টিনে খাবার পরিবেশন শুরু হয়েছে। আপনার লাঞ্চ গ্রহণ করতে পারেন।',
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('🍽️ Test: Lunch Served alert fired!')),
                        );
                      }
                    },
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                    icon: const Icon(Icons.play_circle_outline, size: 16),
                    label: const Text('Live Lunch Status Check'),
                    onPressed: () async {
                      final status = await SteadfastLunchService.instance.getServingStatus();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: Colors.teal.shade800,
                            content: Text(status != null
                                ? '🍱 Live Status: ${status.status} (${status.label})\n${status.message}'
                                : '⚠️ Could not fetch lunch serving status right now.'),
                          ),
                        );
                      }
                    },
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                    icon: const Icon(Icons.radar, size: 16),
                    label: const Text('Start Lunch Sentinel (Foreground)'),
                    onPressed: () async {
                      final started = await LunchSentinelService.instance.startLunchSentinel();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(started
                                ? '🍱 Lunch Sentinel started in background!'
                                : '⚠️ Could not start Lunch Sentinel (Disabled or already served).'),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: FluentSpacing.l),

          // 5. Custom Notification Sounds Studio
          _buildSectionCard(
            title: '🎵 Custom Notification Sounds Studio',
            icon: Icons.volume_up_rounded,
            context: context,
            children: [
              const Text(
                'প্রতিটি নোটিফিকেশন চ্যানেলের জন্য আলাদা কাস্টম সাউন্ড টেস্ট করে শুনুন:',
                style: TextStyle(fontSize: 11.5),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal.shade800,
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.notifications_active, size: 16),
                    label: const Text('🔔 Play Meal Bell (Lunch & Dinner)'),
                    onPressed: () async {
                      await NotificationService.instance.showLunchServedNotification(
                        time: '1:15 PM',
                        message: 'খাবার প্রস্তুত! এই নোটিফিকেশনে মিষ্টি ডাইনিং বেলের শব্দ শোনা যাবে।',
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('🔔 Meal Bell নোটিফিকেশন পাঠানো হয়েছে! সাউন্ড চেক করুন।'),
                          ),
                        );
                      }
                    },
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueGrey.shade800,
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.touch_app, size: 16),
                    label: const Text('🏢 Play Office Chime (Punch In/Out)'),
                    onPressed: () async {
                      await NotificationService.instance.showOfficeCheckInSuccessNotification(
                        time: '8:55 AM',
                        isLate: false,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('🏢 Office Chime নোটিফিকেশন পাঠানো হয়েছে! সাউন্ড চেক করুন।'),
                          ),
                        );
                      }
                    },
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade900,
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.warning, size: 16),
                    label: const Text('🚨 Play Urgent Siren (Cutoff Warning)'),
                    onPressed: () async {
                      await NotificationService.instance.showLateWarningNotification(
                        minutesRemaining: 5,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('🚨 Urgent Siren অ্যালার্ট পাঠানো হয়েছে! সাউন্ড চেক করুন।'),
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

          // 6. Permissions & Notification Access Hub
          _buildSectionCard(
            title: '🔐 Notification & System Access Settings',
            icon: Icons.security,
            context: context,
            children: [
              const Text(
                'অ্যান্ড্রয়েডের নোটিফিকেশন চ্যানেল, সাউন্ড পারমিশন ও ব্যাকগ্রাউন্ড অ্যাক্সেস স্ক্রিন ওপেন করুন:',
                style: TextStyle(fontSize: 11.5),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo.shade800,
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.notifications_active, size: 16),
                    label: const Text('🔔 Notification Channels & Sounds'),
                    onPressed: () async {
                      await SystemSettingsHelper.openNotificationSettings();
                    },
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple.shade800,
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.mark_email_unread, size: 16),
                    label: const Text('📬 Special Notification Access (Listener)'),
                    onPressed: () async {
                      await SystemSettingsHelper.openNotificationListenerSettings();
                    },
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                    icon: const Icon(Icons.battery_charging_full, size: 16),
                    label: const Text('🔋 Battery Optimization Exemption'),
                    onPressed: () async {
                      await SystemSettingsHelper.openBatteryOptimizationSettings();
                    },
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                    icon: const Icon(Icons.settings, size: 16),
                    label: const Text('⚙️ App Details & Permissions'),
                    onPressed: () async {
                      await openAppSettings();
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),

          // 7. Automation Test Card (Full developer tools)
          const AutomationTestCard(),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required BuildContext context,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;

    return Container(
      padding: const EdgeInsets.all(FluentSpacing.l),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? theme.cardColor,
        borderRadius: FluentRadius.cardBorder,
        border: Border.all(
          color: FluentStroke.card(brightness),
          width: FluentStroke.width,
        ),
        boxShadow: FluentElevation.card(brightness),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: FluentSpacing.s),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: FluentType.bodyStrong.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          Divider(
            height: FluentSpacing.xl,
            color: FluentStroke.divider(brightness),
          ),
          ...children,
        ],
      ),
    );
  }
}
