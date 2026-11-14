import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/fluent_tokens.dart';
import '../../../../core/widgets/premium_ui_kit.dart';
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final onSurface = scheme.onSurface;
    final lunchState = ref.watch(lunchProvider);
    final attendanceState = ref.watch(officeAttendanceProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Office Portal (কর্মক্ষেত্র)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FluentType.bodyStrong.copyWith(
                fontSize: 16,
                color: onSurface,
              ),
            ),
            Text(
              'ZaviSoft • Steadfast Catering',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FluentType.caption.copyWith(
                color: onSurface.withValues(alpha: 0.65),
              ),
            ),
          ],
        ),
        actions: [
          if (attendanceState.isSimulationMode)
            const Padding(
              padding: EdgeInsets.symmetric(
                vertical: FluentSpacing.m,
                horizontal: FluentSpacing.xs,
              ),
              child: PremiumTag(
                label: 'TEST MODE',
                icon: Icons.science,
                color: Color(0xFFF59E0B),
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
          indicatorColor: scheme.primary,
          labelColor: onSurface,
          unselectedLabelColor: onSurface.withValues(alpha: 0.6),
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    final onSurface = scheme.onSurface;
    final onSurfaceMuted = onSurface.withValues(alpha: 0.65);
    const amber = Color(0xFFF59E0B);
    const green = Color(0xFF10B981);
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
        padding: const EdgeInsets.all(FluentSpacing.l),
        children: [
          // 1. Cutoff Policy Banner
          Container(
            padding: const EdgeInsets.all(FluentSpacing.m),
            decoration: BoxDecoration(
              color: FluentLayer.subtle(
                isAfterCutoffToday ? scheme.error : amber,
                brightness,
              ),
              borderRadius: FluentRadius.cardBorder,
              border: Border.all(
                color: FluentStroke.card(brightness),
                width: FluentStroke.width,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isAfterCutoffToday ? Icons.lock_clock : Icons.alarm,
                  color: isAfterCutoffToday ? scheme.error : amber,
                  size: 22,
                ),
                const SizedBox(width: FluentSpacing.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isAfterCutoffToday
                            ? 'Cutoff Passed (লক হয়ে গেছে)'
                            : 'Daily Cutoff: 6:00 PM (কাটঅফ সতর্কতা)',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: FluentType.bodyStrong.copyWith(
                          color: isAfterCutoffToday ? scheme.error : amber,
                        ),
                      ),
                      const SizedBox(height: FluentSpacing.xxs),
                      Text(
                        cutoffNotice,
                        style: FluentType.caption.copyWith(color: onSurface),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: FluentSpacing.m),

          // 2. Today & Tomorrow Summary Cards
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(FluentSpacing.m),
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
                      Text(
                        'আজকের লাঞ্চ (Today)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FluentType.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          color: onSurfaceMuted,
                        ),
                      ),
                      const SizedBox(height: FluentSpacing.xs + 2),
                      Row(
                        children: [
                          Icon(
                            state.todayBooked == true
                                ? Icons.check_circle_rounded
                                : Icons.cancel_outlined,
                            color: state.todayBooked == true
                                ? green
                                : onSurfaceMuted,
                            size: 18,
                          ),
                          const SizedBox(width: FluentSpacing.xs + 2),
                          Expanded(
                            child: Text(
                              state.todayBooked == true
                                  ? 'বুক আছে ✓'
                                  : (state.todayBooked == false
                                        ? 'অফ (No Lunch)'
                                        : 'অপেক্ষমাণ'),
                              style: FluentType.bodyStrong.copyWith(
                                color: state.todayBooked == true
                                    ? green
                                    : onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: FluentSpacing.m),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(FluentSpacing.m),
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
                      Text(
                        'আগামীকাল ($tomorrowStr)',
                        style: FluentType.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          color: onSurfaceMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: FluentSpacing.xs + 2),
                      Row(
                        children: [
                          Icon(
                            state.tomorrowBooked == true
                                ? Icons.check_circle_rounded
                                : Icons.cancel_outlined,
                            color: state.tomorrowBooked == true ? green : amber,
                            size: 18,
                          ),
                          const SizedBox(width: FluentSpacing.xs + 2),
                          Expanded(
                            child: Text(
                              state.tomorrowBooked == true
                                  ? 'বুক আছে ✓'
                                  : (state.tomorrowBooked == false
                                        ? 'বুক নেই (Off)'
                                        : 'অপেক্ষমাণ'),
                              style: FluentType.bodyStrong.copyWith(
                                color: state.tomorrowBooked == true
                                    ? green
                                    : (state.tomorrowBooked == false
                                          ? amber
                                          : onSurface),
                              ),
                              maxLines: 1,
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
          const SizedBox(height: FluentSpacing.m),

          // 3. Quick 1-Click Toggle Tomorrow's Lunch Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: state.tomorrowBooked == true
                    ? scheme.error
                    : scheme.primary,
                foregroundColor: state.tomorrowBooked == true
                    ? scheme.onError
                    : scheme.onPrimary,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: FluentSpacing.m),
                shape: RoundedRectangleBorder(
                  borderRadius: FluentRadius.controlBorder,
                ),
              ),
              icon: state.isToggling
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
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
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: FluentType.bodyStrong.copyWith(fontSize: 13),
              ),
              onPressed: state.isToggling
                  ? null
                  : () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final res = await ref
                          .read(lunchProvider.notifier)
                          .toggleTomorrowMeal();
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
          const SizedBox(height: FluentSpacing.xl),

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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    final onSurface = scheme.onSurface;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: FluentRadius.cardBorder,
        side: FluentStroke.side(brightness),
      ),
      child: Padding(
        padding: const EdgeInsets.all(FluentSpacing.l),
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
                      Icon(
                        Icons.calendar_month_rounded,
                        color: scheme.primary,
                        size: 20,
                      ),
                      const SizedBox(width: FluentSpacing.s),
                      Expanded(
                        child: Text(
                          monthLabel,
                          style: FluentType.bodyStrong.copyWith(
                            color: onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: FluentSpacing.s),
                Flexible(
                  child: PremiumTag(
                    label: '$bookedCount Booked',
                    icon: Icons.check,
                    color: const Color(0xFF10B981),
                  ),
                ),
              ],
            ),
            const SizedBox(height: FluentSpacing.xs + 2),
            Text(
              'যেসব দিনে লাঞ্চ চান তা ট্যাপ করে বুক/বাতিল করতে পারেন (৬:০০ টার কাটঅফের পূর্বে)।',
              style: FluentType.caption.copyWith(
                color: onSurface.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: FluentSpacing.m),

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
            Divider(
              height: FluentSpacing.l,
              color: FluentStroke.divider(brightness),
            ),

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
                      Icon(
                        Icons.cloud_off,
                        size: 32,
                        color: onSurface.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: FluentSpacing.s),
                      Text(
                        'No calendar data. Pull down or tap sync.',
                        textAlign: TextAlign.center,
                        style: FluentType.body.copyWith(
                          color: onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                      const SizedBox(height: FluentSpacing.s),
                      TextButton.icon(
                        icon: const Icon(Icons.sync, size: 16),
                        label: const Text('Sync Calendar Now'),
                        onPressed: () {
                          ref
                              .read(lunchProvider.notifier)
                              .syncCalendar(forceRefresh: true);
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    final onSurface = scheme.onSurface;
    const green = Color(0xFF10B981);

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
          : (firstDate.weekday == DateTime.sunday ? 1 : firstDate.weekday + 1);
    }

    final totalSlots = leadingEmptySlots + days.length;
    final rowCount = (totalSlots / 7).ceil();

    final todayStr = DateTime.now().toIso8601String().substring(0, 10);

    return Column(
      children: List.generate(rowCount, (rowIndex) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: FluentSpacing.xxs),
          child: Row(
            children: List.generate(7, (colIndex) {
              final slotIndex = (rowIndex * 7) + colIndex;
              if (slotIndex < leadingEmptySlots || slotIndex >= totalSlots) {
                return const Expanded(child: SizedBox(height: 48));
              }

              final dayIndex = slotIndex - leadingEmptySlots;
              final day = days[dayIndex];
              final isToday = day.date == todayStr;
              final dayNum =
                  DateTime.tryParse(day.date)?.day.toString() ??
                  '${dayIndex + 1}';

              return Expanded(
                child: InkWell(
                  onTap: () => _handleDayTap(day),
                  borderRadius: FluentRadius.controlBorder,
                  child: Container(
                    height: 52,
                    margin: const EdgeInsets.all(FluentSpacing.xxs),
                    decoration: BoxDecoration(
                      color: day.booked
                          ? FluentLayer.subtle(green, brightness)
                          : FluentLayer.subtle(onSurface, brightness),
                      borderRadius: FluentRadius.controlBorder,
                      border: Border.all(
                        color: isToday
                            ? scheme.primary
                            : (day.booked
                                  ? green.withValues(alpha: 0.5)
                                  : FluentStroke.card(brightness)),
                        width: FluentStroke.width,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          dayNum,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: FluentType.caption.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isToday ? scheme.primary : onSurface,
                          ),
                        ),
                        const SizedBox(height: FluentSpacing.xxs),
                        if (day.booked)
                          const Icon(Icons.check_circle, size: 14, color: green)
                        else if (!day.isEditable)
                          Icon(
                            Icons.lock,
                            size: 12,
                            color: onSurface.withValues(alpha: 0.4),
                          )
                        else
                          Icon(
                            Icons.remove,
                            size: 12,
                            color: onSurface.withValues(alpha: 0.3),
                          ),
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
        shape: RoundedRectangleBorder(borderRadius: FluentRadius.cardBorder),
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
              backgroundColor: willBook
                  ? Theme.of(ctx).colorScheme.primary
                  : Theme.of(ctx).colorScheme.error,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: FluentRadius.controlBorder,
              ),
            ),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(ctx);
              final res = await ref
                  .read(lunchProvider.notifier)
                  .toggleDayMeal(date: day.date, book: willBook);
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
            child: Text(willBook ? 'Yes, Book Lunch' : 'Yes, Cancel'),
          ),
        ],
      ),
    );
  }

  ({
    int hours,
    int minutes,
    bool isNineHoursCompleted,
    int remainingMinutes,
    int overtimeMinutes,
  })?
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    final onSurface = scheme.onSurface;
    final onSurfaceMuted = onSurface.withValues(alpha: 0.65);
    const amber = Color(0xFFF59E0B);
    const green = Color(0xFF10B981);
    final status = state.status;
    final isCheckedIn = status?.isCheckedIn ?? (state.lastCheckInTime != null);
    final isCheckedOut =
        status?.isCheckedOut ?? (state.lastCheckOutTime != null);
    final metrics = isCheckedIn
        ? _calculateWorkdayMetrics(state.lastCheckInTime)
        : null;

    final wifiState = ref.watch(settingsNotifierProvider).value;
    final currentSsid = WifiMonitorService.instance.currentSsid;
    final officeSsids =
        wifiState?.officeWifiSsids ?? ['ZaviSoft', 'SecretStar'];
    final isOfficeConnected =
        currentSsid != null && officeSsids.any((s) => currentSsid.contains(s));

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(officeAttendanceProvider.notifier).syncLiveAttendance();
        await _fetchHolidays();
      },
      child: ListView(
        padding: const EdgeInsets.all(FluentSpacing.l),
        children: [
          // 1. Live Attendance Status Card
          Container(
            padding: const EdgeInsets.all(FluentSpacing.l),
            decoration: BoxDecoration(
              borderRadius: FluentRadius.cardBorder,
              color: isOfficeConnected
                  ? FluentLayer.subtle(scheme.primary, brightness)
                  : (theme.cardTheme.color ?? theme.cardColor),
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            isOfficeConnected ? Icons.wifi : Icons.wifi_off,
                            color: isOfficeConnected
                                ? scheme.primary
                                : onSurfaceMuted,
                            size: 18,
                          ),
                          const SizedBox(width: FluentSpacing.s),
                          Expanded(
                            child: Text(
                              isOfficeConnected
                                  ? 'Office Wi-Fi Active ($currentSsid)'
                                  : 'Away from Office Wi-Fi',
                              style: FluentType.bodyStrong.copyWith(
                                color: isOfficeConnected
                                    ? scheme.primary
                                    : onSurfaceMuted,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (state.isSimulationMode) ...[
                      const SizedBox(width: FluentSpacing.s),
                      const Flexible(
                        child: PremiumTag(
                          label: 'TEST MODE',
                          icon: Icons.science,
                          color: amber,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: FluentSpacing.m),

                // Check-In and Check-Out Time Row
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Check-In Time',
                            style: FluentType.caption.copyWith(
                              color: onSurfaceMuted,
                            ),
                          ),
                          const SizedBox(height: FluentSpacing.xs),
                          Text(
                            state.lastCheckInTime ?? 'Not checked in',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FluentType.bodyStrong.copyWith(
                              fontSize: 15,
                              color: state.lastCheckInTime != null
                                  ? (state.isLate ? amber : green)
                                  : onSurface,
                            ),
                          ),
                          if (state.lastCheckInTime != null)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: FluentSpacing.xs,
                              ),
                              child: PremiumTag(
                                label: state.isLate
                                    ? 'LATE (> 9:14 AM)'
                                    : 'ON-TIME ✓',
                                color: state.isLate ? amber : green,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      width: FluentStroke.width,
                      height: 40,
                      color: FluentStroke.divider(brightness),
                    ),
                    const SizedBox(width: FluentSpacing.m),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Check-Out Time',
                            style: FluentType.caption.copyWith(
                              color: onSurfaceMuted,
                            ),
                          ),
                          const SizedBox(height: FluentSpacing.xs),
                          Text(
                            state.lastCheckOutTime ??
                                (isCheckedIn ? 'In Progress' : 'Pending'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FluentType.bodyStrong.copyWith(
                              fontSize: 15,
                              color: state.lastCheckOutTime != null
                                  ? green
                                  : onSurfaceMuted,
                            ),
                          ),
                          if (state.lastCheckOutTime != null)
                            const Padding(
                              padding: EdgeInsets.only(top: FluentSpacing.xs),
                              child: PremiumTag(
                                label: 'COMPLETED ✓',
                                color: green,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                // 9-Hour Workday Progress Indicator
                if (metrics != null) ...[
                  const SizedBox(height: FluentSpacing.m),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FluentSpacing.m,
                      vertical: FluentSpacing.s,
                    ),
                    decoration: BoxDecoration(
                      color: FluentLayer.subtle(onSurface, brightness),
                      borderRadius: FluentRadius.controlBorder,
                      border: Border.all(
                        color: FluentStroke.card(brightness),
                        width: FluentStroke.width,
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
                                    metrics.isNineHoursCompleted
                                        ? Icons.check_circle
                                        : Icons.timer,
                                    size: 14,
                                    color: metrics.isNineHoursCompleted
                                        ? green
                                        : amber,
                                  ),
                                  const SizedBox(width: FluentSpacing.xs + 2),
                                  Expanded(
                                    child: Text(
                                      'Workday: ${metrics.hours}h ${metrics.minutes.toString().padLeft(2, '0')}m / 9h',
                                      style: FluentType.caption.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: onSurface,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: FluentSpacing.s),
                            if (metrics.isNineHoursCompleted)
                              Flexible(
                                child: Text(
                                  metrics.overtimeMinutes > 0
                                      ? 'OT: +${metrics.overtimeMinutes ~/ 60 > 0 ? '${metrics.overtimeMinutes ~/ 60}h ' : ''}${metrics.overtimeMinutes % 60}m 🔥'
                                      : '9h Completed ✓',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.end,
                                  style: FluentType.caption.copyWith(
                                    color: green,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              )
                            else
                              Flexible(
                                child: Text(
                                  '${metrics.remainingMinutes ~/ 60 > 0 ? '${metrics.remainingMinutes ~/ 60}h ' : ''}${metrics.remainingMinutes % 60}m left',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.end,
                                  style: FluentType.caption.copyWith(
                                    color: amber,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: FluentSpacing.s),
                        ClipRRect(
                          borderRadius: FluentRadius.controlBorder,
                          child: LinearProgressIndicator(
                            value:
                                (metrics.hours * 60 + metrics.minutes) / 540.0 >
                                    1.0
                                ? 1.0
                                : (metrics.hours * 60 + metrics.minutes) /
                                      540.0,
                            backgroundColor: FluentLayer.subtle(
                              onSurface,
                              brightness,
                            ),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              metrics.isNineHoursCompleted
                                  ? green
                                  : scheme.primary,
                            ),
                            minHeight: 6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: FluentSpacing.l),

                // Direct Punch Buttons (State-Aware: Supports Multiple Check-Outs & Early Warning)
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isCheckedIn
                              ? FluentLayer.subtle(onSurface, brightness)
                              : scheme.primary,
                          foregroundColor: isCheckedIn
                              ? onSurfaceMuted
                              : scheme.onPrimary,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            vertical: FluentSpacing.s,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: FluentRadius.controlBorder,
                          ),
                        ),
                        icon: state.isLoading
                            ? const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                isCheckedIn ? Icons.check_circle : Icons.login,
                                size: 16,
                              ),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            isCheckedIn ? 'Checked In ✓' : 'Check In Now',
                            style: FluentType.caption,
                          ),
                        ),
                        onPressed: (state.isLoading || isCheckedIn)
                            ? null
                            : () async {
                                final messenger = ScaffoldMessenger.of(context);
                                final res = await ref
                                    .read(officeAttendanceProvider.notifier)
                                    .checkIn();
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
                    const SizedBox(width: FluentSpacing.s),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: !isCheckedIn
                              ? FluentLayer.subtle(onSurface, brightness)
                              : (isCheckedOut ? scheme.primary : scheme.error),
                          foregroundColor: !isCheckedIn
                              ? onSurfaceMuted
                              : Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            vertical: FluentSpacing.s,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: FluentRadius.controlBorder,
                          ),
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
                                : (isCheckedOut
                                      ? 'Update Out'
                                      : 'Check Out Now'),
                            style: FluentType.caption,
                          ),
                        ),
                        onPressed: (state.isLoading || !isCheckedIn)
                            ? null
                            : () async {
                                final now = DateTime.now();
                                final isEarly =
                                    (metrics != null &&
                                        !metrics.isNineHoursCompleted) ||
                                    now.hour < 18;

                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: FluentRadius.cardBorder,
                                    ),
                                    title: Row(
                                      children: [
                                        Icon(
                                          isEarly
                                              ? Icons.warning_amber_rounded
                                              : (isCheckedOut
                                                    ? Icons.update
                                                    : Icons.logout),
                                          color: isEarly
                                              ? amber
                                              : (isCheckedOut
                                                    ? scheme.primary
                                                    : scheme.error),
                                        ),
                                        const SizedBox(width: FluentSpacing.s),
                                        Expanded(
                                          child: Text(
                                            isEarly
                                                ? 'Early Check-Out Alert'
                                                : (isCheckedOut
                                                      ? 'Update Check-Out (OT)'
                                                      : 'Confirm Check-Out?'),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: FluentType.subtitle.copyWith(
                                              fontSize: 15,
                                            ),
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
                                      style: FluentType.body,
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text('Cancel'),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: isEarly
                                              ? amber
                                              : (isCheckedOut
                                                    ? scheme.primary
                                                    : scheme.error),
                                          foregroundColor: Colors.white,
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                FluentRadius.controlBorder,
                                          ),
                                        ),
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: Text(
                                          isEarly
                                              ? 'Proceed Early Out'
                                              : (isCheckedOut
                                                    ? 'Update Check-Out'
                                                    : 'Yes, Check Out'),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  if (!mounted) return;
                                  final messenger = ScaffoldMessenger.of(
                                    context,
                                  );
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
          const SizedBox(height: FluentSpacing.m),

          // 2. Strict 9:15 AM Policy Card
          Container(
            padding: const EdgeInsets.all(FluentSpacing.m),
            decoration: BoxDecoration(
              color: FluentLayer.subtle(amber, brightness),
              borderRadius: FluentRadius.cardBorder,
              border: Border.all(
                color: FluentStroke.card(brightness),
                width: FluentStroke.width,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded, color: amber, size: 20),
                const SizedBox(width: FluentSpacing.s),
                Expanded(
                  child: Text(
                    'অফিস নিয়ম: ৯:১৪ AM পর্যন্ত অন-টাইম, ৯:১৫ AM বাজলেই LATE। মাসে ৩ দিন লেট হলে ১ দিনের বেতন কর্তন ও শোকজ কার্যকর হয়।',
                    style: FluentType.caption.copyWith(color: onSurface),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: FluentSpacing.m),

          // 3. Holidays List
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: FluentRadius.cardBorder,
              side: FluentStroke.side(brightness),
            ),
            child: Padding(
              padding: const EdgeInsets.all(FluentSpacing.l),
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
                              Icons.celebration,
                              color: scheme.primary,
                              size: 18,
                            ),
                            const SizedBox(width: FluentSpacing.s),
                            Flexible(
                              child: Text(
                                'Official Company Holidays',
                                style: FluentType.bodyStrong.copyWith(
                                  color: onSurface,
                                ),
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
                  const SizedBox(height: FluentSpacing.s),
                  if (_holidays.isEmpty)
                    Text(
                      'ছুটির তালিকা লোড হচ্ছে...',
                      style: FluentType.caption.copyWith(color: onSurfaceMuted),
                    )
                  else
                    ..._holidays.take(6).map((h) {
                      final isUpcoming = h.endDate.isAfter(DateTime.now());
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: FluentSpacing.xs,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(
                              isUpcoming
                                  ? Icons.event_available
                                  : Icons.event_busy,
                              size: 16,
                              color: isUpcoming
                                  ? scheme.primary
                                  : onSurfaceMuted,
                            ),
                            const SizedBox(width: FluentSpacing.s),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    h.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: FluentType.body.copyWith(
                                      fontWeight: isUpcoming
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      color: onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: FluentSpacing.xxs),
                                  Text(
                                    h.formattedWithWeekday,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: FluentType.caption.copyWith(
                                      color: isUpcoming
                                          ? scheme.primary
                                          : onSurfaceMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: FluentSpacing.s),
                            Flexible(
                              child: PremiumTag(
                                label: isUpcoming ? 'আসন্ন' : 'সমাপ্ত',
                                color: isUpcoming
                                    ? scheme.primary
                                    : onSurfaceMuted,
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
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: FluentType.caption.copyWith(
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface
                .withValues(alpha: isWeekend ? 0.8 : 0.6),
          ),
        ),
      ),
    );
  }
}
