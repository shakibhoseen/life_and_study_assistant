import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/attendance/packly_attendance_service.dart';
import '../../../../core/services/attendance/steadfast_lunch_service.dart';
import '../../../../core/services/background/wifi_monitor_service.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../settings/presentation/screens/settings_screen.dart';
import '../providers/office_portal_provider.dart';

class OfficePortalScreen extends ConsumerStatefulWidget {
  const OfficePortalScreen({super.key});

  @override
  ConsumerState<OfficePortalScreen> createState() => _OfficePortalScreenState();
}

class _OfficePortalScreenState extends ConsumerState<OfficePortalScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<PacklyHoliday> _holidays = [];
  bool _isLoadingHolidays = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // Initial sync
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(lunchProvider.notifier).syncCalendar();
      ref.read(officeAttendanceProvider.notifier).syncLiveAttendance();
      _fetchHolidays();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchHolidays() async {
    setState(() => _isLoadingHolidays = true);
    try {
      final list = await PacklyAttendanceService.instance.fetchHolidays();
      if (mounted) {
        setState(() {
          _holidays = list;
          _isLoadingHolidays = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingHolidays = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lunchState = ref.watch(lunchProvider);
    final attendanceState = ref.watch(officeAttendanceProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Office Portal (কর্মক্ষেত্র)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              'ZaviSoft • Steadfast Catering',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
          ],
        ),
        actions: [
          if (attendanceState.isSimulationMode)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.amber, width: 0.8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.science, size: 12, color: Colors.amber),
                  SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      'TEST MODE',
                      style: TextStyle(
                        color: Colors.amber,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          IconButton(
            tooltip: 'Sync All',
            icon: lunchState.isLoading || attendanceState.isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            onPressed: () {
              ref.read(lunchProvider.notifier).syncCalendar(forceRefresh: true);
              ref.read(officeAttendanceProvider.notifier).syncLiveAttendance();
              _fetchHolidays();
            },
          ),
          IconButton(
            tooltip: 'Office Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.deepOrange,
          labelColor: isDark ? Colors.white : Colors.black87,
          unselectedLabelColor: isDark ? Colors.white54 : Colors.black45,
          tabs: const [
            Tab(
              icon: Icon(Icons.lunch_dining_rounded, size: 18),
              text: 'Lunch & Meal Calendar',
            ),
            Tab(
              icon: Icon(Icons.fingerprint_rounded, size: 18),
              text: 'Attendance (Packly)',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildLunchTab(lunchState, isDark),
          _buildAttendanceTab(attendanceState, isDark),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 1: STEADFAST LUNCH & MEAL CALENDAR
  // ==========================================
  Widget _buildLunchTab(LunchState state, bool isDark) {
    final now = DateTime.now();
    final tomorrow = now.add(const Duration(days: 1));
    final tomorrowStr = '${tomorrow.day}/${tomorrow.month}/${tomorrow.year}';
    final cal = state.calendar;

    // Cutoff status calculation (Daily 6:00 PM)
    final isAfterCutoffToday = now.hour >= 18;
    final cutoffNotice = isAfterCutoffToday
        ? '⚠️ আজকের সন্ধ্যা ৬:০০ টার কাটঅফ পার হয়ে গেছে। আগামীকাল ($tomorrowStr)-এর মিল আর পরিবর্তনযোগ্য নয়।'
        : '⏳ আজ সন্ধ্যা ৬:০০ টার মধ্যে আগামীকাল ($tomorrowStr)-এর লাঞ্চ বুক বা বাতিল করতে হবে।';

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(lunchProvider.notifier).syncCalendar(forceRefresh: true);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Cutoff Policy Banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isAfterCutoffToday
                  ? (isDark
                      ? Colors.red.withValues(alpha: 0.15)
                      : const Color(0xFFFEF2F2))
                  : (isDark
                      ? Colors.orange.withValues(alpha: 0.15)
                      : const Color(0xFFFFF7ED)),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isAfterCutoffToday
                    ? (isDark ? Colors.redAccent.withValues(alpha: 0.3) : const Color(0xFFFECACA))
                    : (isDark ? Colors.orange.withValues(alpha: 0.3) : const Color(0xFFFED7AA)),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isAfterCutoffToday ? Icons.lock_clock : Icons.alarm,
                  color: isAfterCutoffToday ? Colors.redAccent : Colors.deepOrange,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isAfterCutoffToday
                            ? 'Cutoff Passed (লক হয়ে গেছে)'
                            : 'Daily Cutoff: 6:00 PM (কাটঅফ সতর্কতা)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                          color: isAfterCutoffToday ? Colors.redAccent : Colors.deepOrange,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        cutoffNotice,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.35,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 2. Today & Tomorrow Summary Cards
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1E293B)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'আজকের লাঞ্চ (Today)',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            state.todayBooked == true
                                ? Icons.check_circle_rounded
                                : Icons.cancel_outlined,
                            color: state.todayBooked == true ? Colors.green : Colors.grey,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              state.todayBooked == true
                                  ? 'বুক আছে ✓'
                                  : (state.todayBooked == false ? 'অফ (No Lunch)' : 'অপেক্ষমাণ'),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: state.todayBooked == true
                                    ? Colors.green
                                    : (isDark ? Colors.white70 : Colors.black87),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1E293B)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'আগামীকাল ($tomorrowStr)',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            state.tomorrowBooked == true
                                ? Icons.check_circle_rounded
                                : Icons.cancel_outlined,
                            color: state.tomorrowBooked == true ? Colors.green : Colors.orange,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              state.tomorrowBooked == true
                                  ? 'বুক আছে ✓'
                                  : (state.tomorrowBooked == false ? 'বুক নেই (Off)' : 'অপেক্ষমাণ'),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: state.tomorrowBooked == true
                                    ? Colors.green
                                    : (state.tomorrowBooked == false
                                        ? Colors.orange
                                        : (isDark ? Colors.white70 : Colors.black87)),
                              ),
                              overflow: TextOverflow.ellipsis,
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
          const SizedBox(height: 12),

          // 3. Quick 1-Click Toggle Tomorrow's Lunch Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: state.tomorrowBooked == true
                    ? Colors.redAccent.shade700
                    : Colors.teal.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: state.isToggling
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Icon(
                      state.tomorrowBooked == true
                          ? Icons.cancel
                          : Icons.check_circle_outline,
                      size: 18,
                    ),
              label: Text(
                state.isToggling
                    ? 'সার্ভারে আপডেট হচ্ছে...'
                    : (state.tomorrowBooked == true
                        ? 'Cancel Tomorrow\'s Lunch (আগামীকালের লাঞ্চ বাতিল করুন)'
                        : 'Book Tomorrow\'s Lunch (আগামীকালের লাঞ্চ বুক করুন)'),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              onPressed: state.isToggling
                  ? null
                  : () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final res = await ref.read(lunchProvider.notifier).toggleTomorrowMeal();
                      if (mounted) {
                        messenger.showSnackBar(
                          SnackBar(
                            backgroundColor:
                                res.success ? Colors.green.shade800 : Colors.red.shade800,
                            content: Text(res.message),
                          ),
                        );
                      }
                    },
            ),
          ),
          const SizedBox(height: 18),

          // 4. Monthly Interactive Calendar
          _buildMonthlyCalendarCard(state, cal, isDark),
        ],
      ),
    );
  }

  Widget _buildMonthlyCalendarCard(
    LunchState state,
    SteadfastMealCalendar? cal,
    bool isDark,
  ) {
    final monthLabel = cal?.label ?? 'Current Month';
    final bookedCount = cal?.bookedCount ?? 0;
    final days = cal?.days ?? [];

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Calendar Header with month & stats
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month_rounded, color: Colors.deepOrange, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          monthLabel,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green, width: 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check, size: 12, color: Colors.green),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '$bookedCount Booked',
                          style: const TextStyle(
                            color: Colors.green,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'যেসব দিনে লাঞ্চ চান তা ট্যাপ করে বুক/বাতিল করতে পারেন (৬:০০ টার কাটঅফের পূর্বে)।',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
            const SizedBox(height: 14),

            // Weekday Headers (Bangladesh work-week: Sat -> Fri)
            Row(
              children: const [
                _WeekdayHeader('Sat'),
                _WeekdayHeader('Sun'),
                _WeekdayHeader('Mon'),
                _WeekdayHeader('Tue'),
                _WeekdayHeader('Wed'),
                _WeekdayHeader('Thu', isWeekend: true),
                _WeekdayHeader('Fri', isWeekend: true),
              ],
            ),
            const Divider(height: 16),

            if (state.isLoading && days.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 36),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (days.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Column(
                    children: [
                      const Icon(Icons.cloud_off, size: 32, color: Colors.grey),
                      const SizedBox(height: 8),
                      const Text('No calendar data. Pull down or tap sync.'),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        icon: const Icon(Icons.sync, size: 16),
                        label: const Text('Sync Calendar Now'),
                        onPressed: () {
                          ref.read(lunchProvider.notifier).syncCalendar(forceRefresh: true);
                        },
                      ),
                    ],
                  ),
                ),
              )
            else
              _buildCalendarDaysGrid(days, isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarDaysGrid(List<SteadfastDayMeal> days, bool isDark) {
    if (days.isEmpty) return const SizedBox.shrink();

    // Work out weekday offset for the 1st of month:
    // In DateTime: 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat, 7=Sun
    // Our grid starts with Saturday = index 0:
    // Sat=0, Sun=1, Mon=2, Tue=3, Wed=4, Thu=5, Fri=6
    final firstDateStr = days.first.date;
    final firstDate = DateTime.tryParse(firstDateStr);
    int leadingEmptySlots = 0;
    if (firstDate != null) {
      leadingEmptySlots = (firstDate.weekday == DateTime.saturday)
          ? 0
          : (firstDate.weekday == DateTime.sunday
              ? 1
              : firstDate.weekday + 1);
    }

    final totalSlots = leadingEmptySlots + days.length;
    final rowCount = (totalSlots / 7).ceil();

    final todayStr = DateTime.now().toIso8601String().substring(0, 10);

    return Column(
      children: List.generate(rowCount, (rowIndex) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: List.generate(7, (colIndex) {
              final slotIndex = (rowIndex * 7) + colIndex;
              if (slotIndex < leadingEmptySlots || slotIndex >= totalSlots) {
                return const Expanded(child: SizedBox(height: 48));
              }

              final dayIndex = slotIndex - leadingEmptySlots;
              final day = days[dayIndex];
              final isToday = day.date == todayStr;
              final dayNum = DateTime.tryParse(day.date)?.day.toString() ?? '${dayIndex + 1}';

              return Expanded(
                child: InkWell(
                  onTap: () => _handleDayTap(day),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    height: 52,
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: day.booked
                          ? (isDark
                              ? Colors.green.withValues(alpha: 0.25)
                              : const Color(0xFFDCFCE7))
                          : (isDark
                              ? Colors.white.withValues(alpha: 0.04)
                              : const Color(0xFFF8FAFC)),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isToday
                            ? Colors.deepOrange
                            : (day.booked
                                ? Colors.green.withValues(alpha: 0.5)
                                : (isDark ? Colors.white12 : const Color(0xFFE2E8F0))),
                        width: isToday ? 1.8 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          dayNum,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: isToday ? FontWeight.bold : FontWeight.w600,
                            color: isToday
                                ? Colors.deepOrange
                                : (isDark ? Colors.white : Colors.black87),
                          ),
                        ),
                        const SizedBox(height: 2),
                        if (day.booked)
                          const Icon(Icons.check_circle, size: 14, color: Colors.green)
                        else if (!day.isEditable)
                          const Icon(Icons.lock, size: 12, color: Colors.grey)
                        else
                          const Icon(Icons.remove, size: 12, color: Colors.black26),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      }),
    );
  }

  String _dateWithWeekday(String dateStr) {
    final dt = DateTime.tryParse(dateStr);
    if (dt == null) return dateStr;
    final wBn = PacklyHoliday.weekdayNameBn(dt.weekday);
    return '$dateStr ($wBn)';
  }

  void _handleDayTap(SteadfastDayMeal day) {
    final formattedDate = _dateWithWeekday(day.date);
    if (!day.isEditable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(
            day.afterCutoff
                ? 'Locked: $formattedDate এর ৬:০০ PM কাটঅফ পার হয়ে গেছে।'
                : 'Locked: $formattedDate অতীত বা ছুটির দিন হওয়ায় পরিবর্তনযোগ্য নয়।',
          ),
        ),
      );
      return;
    }

    final willBook = !day.booked;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(willBook ? 'Book Lunch?' : 'Cancel Lunch?'),
        content: Text(
          willBook
              ? '$formattedDate তারিখের জন্য কি লাঞ্চ বুক করতে চান?'
              : '$formattedDate তারিখের লাঞ্চ কি বাতিল করতে চান?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: willBook ? Colors.teal.shade700 : Colors.redAccent.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(ctx);
              final res = await ref.read(lunchProvider.notifier).toggleDayMeal(
                    date: day.date,
                    book: willBook,
                  );
              if (mounted) {
                messenger.showSnackBar(
                  SnackBar(
                    backgroundColor:
                        res.success ? Colors.green.shade800 : Colors.red.shade800,
                    content: Text(res.message),
                  ),
                );
              }
            },
            child: Text(willBook ? 'Yes, Book Lunch' : 'Yes, Cancel'),
          ),
        ],
      ),
    );
  }

  ({int hours, int minutes, bool isNineHoursCompleted, int remainingMinutes, int overtimeMinutes})?
      _calculateWorkdayMetrics(String? checkInTime) {
    if (checkInTime == null || checkInTime.isEmpty) return null;
    try {
      final clean = checkInTime.trim().toUpperCase();
      final parts = clean.split(' ');
      if (parts.isEmpty) return null;
      final timeParts = parts[0].split(':');
      if (timeParts.length < 2) return null;

      int hour = int.parse(timeParts[0]);
      int minute = int.parse(timeParts[1]);
      final isPm = parts.length > 1 && parts[1] == 'PM';
      final isAm = parts.length > 1 && parts[1] == 'AM';

      if (isPm && hour < 12) hour += 12;
      if (isAm && hour == 12) hour = 0;

      final now = DateTime.now();
      final checkInDt = DateTime(now.year, now.month, now.day, hour, minute);

      if (now.isBefore(checkInDt)) return null;

      final totalMinutes = now.difference(checkInDt).inMinutes;
      final workedHours = totalMinutes ~/ 60;
      final workedMins = totalMinutes % 60;

      // Standard workday: 9 hours = 540 minutes
      const targetMinutes = 9 * 60;
      final isCompleted = totalMinutes >= targetMinutes;
      final remaining = isCompleted ? 0 : (targetMinutes - totalMinutes);
      final overtime = isCompleted ? (totalMinutes - targetMinutes) : 0;

      return (
        hours: workedHours,
        minutes: workedMins,
        isNineHoursCompleted: isCompleted,
        remainingMinutes: remaining,
        overtimeMinutes: overtime,
      );
    } catch (_) {
      return null;
    }
  }

  // ==========================================
  // TAB 2: PACKLY ATTENDANCE
  // ==========================================
  Widget _buildAttendanceTab(AttendanceState state, bool isDark) {
    final status = state.status;
    final isCheckedIn = status?.isCheckedIn ?? (state.lastCheckInTime != null);
    final isCheckedOut = status?.isCheckedOut ?? (state.lastCheckOutTime != null);
    final metrics = isCheckedIn ? _calculateWorkdayMetrics(state.lastCheckInTime) : null;

    final wifiState = ref.watch(settingsNotifierProvider).value;
    final currentSsid = WifiMonitorService.instance.currentSsid;
    final officeSsids = wifiState?.officeWifiSsids ?? ['ZaviSoft', 'SecretStar'];
    final isOfficeConnected =
        currentSsid != null && officeSsids.any((s) => currentSsid.contains(s));

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(officeAttendanceProvider.notifier).syncLiveAttendance();
        await _fetchHolidays();
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Live Attendance Status Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: isOfficeConnected
                    ? [const Color(0xFF0F172A), const Color(0xFF1E293B)]
                    : [const Color(0xFF1E1E2E), const Color(0xFF181825)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
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
                          Icon(
                            isOfficeConnected ? Icons.wifi : Icons.wifi_off,
                            color: isOfficeConnected ? Colors.tealAccent : Colors.white70,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isOfficeConnected
                                  ? 'Office Wi-Fi Active ($currentSsid)'
                                  : 'Away from Office Wi-Fi',
                              style: TextStyle(
                                color: isOfficeConnected ? Colors.tealAccent : Colors.white70,
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (state.isSimulationMode) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.amberAccent, width: 0.8),
                        ),
                        child: const Text(
                          'TEST MODE',
                          style: TextStyle(
                            color: Colors.amberAccent,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),

                // Check-In and Check-Out Time Row
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Check-In Time',
                            style: TextStyle(color: Colors.white60, fontSize: 11),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            state.lastCheckInTime ?? 'Not checked in',
                            style: TextStyle(
                              color: state.lastCheckInTime != null
                                  ? (state.isLate ? Colors.amberAccent : Colors.tealAccent)
                                  : Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (state.lastCheckInTime != null)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: state.isLate
                                    ? Colors.amber.withValues(alpha: 0.2)
                                    : Colors.green.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                state.isLate ? 'LATE (> 9:14 AM)' : 'ON-TIME ✓',
                                style: TextStyle(
                                  color: state.isLate ? Colors.amberAccent : Colors.greenAccent,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Container(width: 1, height: 40, color: Colors.white12),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Check-Out Time',
                            style: TextStyle(color: Colors.white60, fontSize: 11),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            state.lastCheckOutTime ?? (isCheckedIn ? 'In Progress' : 'Pending'),
                            style: TextStyle(
                              color: state.lastCheckOutTime != null
                                  ? Colors.greenAccent
                                  : Colors.white70,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (state.lastCheckOutTime != null)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'COMPLETED ✓',
                                style: TextStyle(
                                  color: Colors.greenAccent,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                // 9-Hour Workday Progress Indicator
                if (metrics != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: metrics.isNineHoursCompleted
                            ? Colors.greenAccent.withValues(alpha: 0.3)
                            : (DateTime.now().hour < 18
                                ? Colors.amber.withValues(alpha: 0.3)
                                : Colors.white12),
                      ),
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
                                  Icon(
                                    metrics.isNineHoursCompleted ? Icons.check_circle : Icons.timer,
                                    size: 14,
                                    color: metrics.isNineHoursCompleted ? Colors.greenAccent : Colors.amberAccent,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Workday: ${metrics.hours}h ${metrics.minutes.toString().padLeft(2, '0')}m / 9h',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (metrics.isNineHoursCompleted)
                              Text(
                                metrics.overtimeMinutes > 0
                                    ? 'OT: +${metrics.overtimeMinutes ~/ 60 > 0 ? '${metrics.overtimeMinutes ~/ 60}h ' : ''}${metrics.overtimeMinutes % 60}m 🔥'
                                    : '9h Completed ✓',
                                style: const TextStyle(
                                  color: Colors.greenAccent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            else
                              Text(
                                '${metrics.remainingMinutes ~/ 60 > 0 ? '${metrics.remainingMinutes ~/ 60}h ' : ''}${metrics.remainingMinutes % 60}m left',
                                style: const TextStyle(color: Colors.amberAccent, fontSize: 11),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (metrics.hours * 60 + metrics.minutes) / 540.0 > 1.0
                                ? 1.0
                                : (metrics.hours * 60 + metrics.minutes) / 540.0,
                            backgroundColor: Colors.white12,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              metrics.isNineHoursCompleted ? Colors.greenAccent : Colors.tealAccent,
                            ),
                            minHeight: 6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                // Direct Punch Buttons (State-Aware: Supports Multiple Check-Outs & Early Warning)
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isCheckedIn ? Colors.grey.shade800 : Colors.teal.shade600,
                          foregroundColor: isCheckedIn ? Colors.white54 : Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: state.isLoading
                            ? const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Icon(isCheckedIn ? Icons.check_circle : Icons.login, size: 16),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            isCheckedIn ? 'Checked In ✓' : 'Check In Now',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        onPressed: (state.isLoading || isCheckedIn)
                            ? null
                            : () async {
                                final messenger = ScaffoldMessenger.of(context);
                                final res =
                                    await ref.read(officeAttendanceProvider.notifier).checkIn();
                                if (mounted) {
                                  messenger.showSnackBar(
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
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: !isCheckedIn
                              ? Colors.grey.shade800
                              : (isCheckedOut ? Colors.indigo.shade600 : Colors.redAccent.shade700),
                          foregroundColor: !isCheckedIn ? Colors.white54 : Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: Icon(
                          isCheckedOut ? Icons.update : Icons.logout,
                          size: 16,
                        ),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            !isCheckedIn
                                ? 'Pending In'
                                : (isCheckedOut ? 'Update Out' : 'Check Out Now'),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        onPressed: (state.isLoading || !isCheckedIn)
                            ? null
                            : () async {
                                final now = DateTime.now();
                                final isEarly = (metrics != null && !metrics.isNineHoursCompleted) || now.hour < 18;

                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: Row(
                                      children: [
                                        Icon(
                                          isEarly
                                              ? Icons.warning_amber_rounded
                                              : (isCheckedOut ? Icons.update : Icons.logout),
                                          color: isEarly
                                              ? Colors.amber
                                              : (isCheckedOut ? Colors.blue : Colors.redAccent),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            isEarly
                                                ? 'Early Check-Out Alert'
                                                : (isCheckedOut ? 'Update Check-Out (OT)' : 'Confirm Check-Out?'),
                                            style: const TextStyle(fontSize: 15),
                                          ),
                                        ),
                                      ],
                                    ),
                                    content: Text(
                                      isEarly
                                          ? 'অফিসের নির্ধারিত সময় সকাল ৯:০০ টা থেকে সন্ধ্যা ৬:০০ টা (মোট ৯ ঘণ্টা)।\n\n'
                                            'আপনি এখন পর্যন্ত কাজ করেছেন: ${metrics?.hours ?? 0} ঘণ্টা ${metrics?.minutes ?? 0} মিনিট '
                                            '(৯ ঘণ্টা পূর্ণ হতে আরও ${metrics?.remainingMinutes ?? 0} মিনিট বাকি)।\n\n'
                                            'ম্যানেজমেন্টের অনুমোদন নিয়ে থাকলে "Proceed Early Out" চাপুন।'
                                          : (isCheckedOut
                                              ? 'আপনার পূর্ববর্তী চেক-আউট ছিল: ${state.lastCheckOutTime}।\n\n'
                                                'এখন নতুন পাঞ্চ দিলে সিস্টেমে আপনার সর্বশেষ সময় রেকর্ড হবে এবং ওভারটাইম গণনা হবে।\n\n'
                                                'সর্বশেষ চেক-আউট আপডেট করতে চান?'
                                              : 'আজকের কাজের সময় সম্পন্ন হয়েছে (মোট সময়: ${metrics?.hours ?? 9} ঘণ্টা ${metrics?.minutes ?? 0} মিনিট)।\n\n'
                                                'চেক-আউট সাবমিট করতে চান?'),
                                      style: const TextStyle(fontSize: 13, height: 1.4),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx, false),
                                        child: const Text('Cancel'),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: isEarly
                                              ? Colors.amber.shade800
                                              : (isCheckedOut ? Colors.indigo : Colors.redAccent),
                                          foregroundColor: Colors.white,
                                        ),
                                        onPressed: () => Navigator.pop(ctx, true),
                                        child: Text(
                                          isEarly
                                              ? 'Proceed Early Out'
                                              : (isCheckedOut ? 'Update Check-Out' : 'Yes, Check Out'),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  if (!mounted) return;
                                  final messenger = ScaffoldMessenger.of(context);
                                  final res = await ref
                                      .read(officeAttendanceProvider.notifier)
                                      .checkOut();
                                  if (mounted) {
                                    messenger.showSnackBar(
                                      SnackBar(
                                        backgroundColor: res.success
                                            ? Colors.green.shade800
                                            : Colors.red.shade800,
                                        content: Text(res.message),
                                      ),
                                    );
                                  }
                                }
                              },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 2. Strict 9:15 AM Policy Card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Colors.amber.withValues(alpha: 0.12) : const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? Colors.amber.withValues(alpha: 0.3) : const Color(0xFFFDE68A),
              ),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'অফিস নিয়ম: ৯:১৪ AM পর্যন্ত অন-টাইম, ৯:১৫ AM বাজলেই LATE। মাসে ৩ দিন লেট হলে ১ দিনের বেতন কর্তন ও শোকজ কার্যকর হয়।',
                    style: TextStyle(fontSize: 11.5, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 3. Holidays List
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Row(
                          children: [
                            Icon(Icons.celebration, color: Colors.teal, size: 18),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Official Company Holidays',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_isLoadingHolidays)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_holidays.isEmpty)
                    const Text(
                      'ছুটির তালিকা লোড হচ্ছে...',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    )
                  else
                    ..._holidays.take(6).map((h) {
                      final isUpcoming = h.endDate.isAfter(DateTime.now());
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(
                              isUpcoming ? Icons.event_available : Icons.event_busy,
                              size: 16,
                              color: isUpcoming ? Colors.teal : Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    h.name,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: isUpcoming ? FontWeight.w600 : FontWeight.normal,
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    h.formattedWithWeekday,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isUpcoming ? Colors.teal.shade700 : Colors.grey.shade600,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isUpcoming
                                    ? Colors.teal.withValues(alpha: 0.12)
                                    : Colors.grey.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                isUpcoming ? 'আসন্ন' : 'সমাপ্ত',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isUpcoming ? Colors.teal : Colors.grey,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  final String label;
  final bool isWeekend;
  const _WeekdayHeader(this.label, {this.isWeekend = false});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isWeekend ? Colors.redAccent : Colors.grey,
          ),
        ),
      ),
    );
  }
}
