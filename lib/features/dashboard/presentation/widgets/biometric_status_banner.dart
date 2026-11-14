import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/config/notification_constants.dart';
import '../../../../core/theme/fluent_tokens.dart';
import '../../../../core/widgets/premium_glass_card.dart';
import '../../../../core/widgets/premium_ui_kit.dart';
import '../../../../core/services/attendance/packly_attendance_service.dart';
import '../../../../core/services/background/wifi_monitor_service.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../providers/office_portal_provider.dart';
import '../screens/office_portal_screen.dart';

class BiometricStatusBanner extends ConsumerStatefulWidget {
  final bool forceVisible;
  const BiometricStatusBanner({super.key, this.forceVisible = false});

  static void showAttendanceSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + FluentSpacing.xl,
            left: FluentSpacing.l,
            right: FluentSpacing.l,
            top: FluentSpacing.xl,
          ),
          child: const BiometricStatusBanner(forceVisible: true),
        ),
      ),
    );
  }

  @override
  ConsumerState<BiometricStatusBanner> createState() =>
      _BiometricStatusBannerState();
}

class _BiometricStatusBannerState extends ConsumerState<BiometricStatusBanner> {
  bool _isLoading = false;
  PacklyAttendanceStatus? _liveStatus;
  PacklyHoliday? _todayHoliday;
  String? _lastCheckInTime;
  String? _lastCheckOutTime;
  bool _isLate = false;
  String _bannerMode = 'contextual';
  bool _isSimulationMode = false;
  bool? _tomorrowLunchBooked;

  @override
  void initState() {
    super.initState();
    _loadSavedStatus();
    _syncLiveAttendance();
  }

  Future<void> _loadSavedStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final holiday = await PacklyAttendanceService.instance.getHolidayForDate(
      DateTime.now(),
    );
    final bannerMode =
        prefs.getString(NotificationConstants.prefOfficeBannerMode) ??
        'contextual';
    final isSim =
        prefs.getBool(NotificationConstants.prefPacklySimulationMode) ?? false;
    final lunchBooked = prefs.getBool(
      NotificationConstants.prefLunchLastKnownTomorrowBooked,
    );

    String? inTime;
    String? outTime;
    bool isLate = false;

    if (isSim) {
      final simDate = prefs.getString(
        NotificationConstants.prefSimulatedCheckInDate,
      );
      if (simDate == today) {
        inTime = prefs.getString(
          NotificationConstants.prefSimulatedCheckInTime,
        );
        outTime = prefs.getString(
          NotificationConstants.prefSimulatedCheckOutTime,
        );
        isLate =
            prefs.getBool(NotificationConstants.prefSimulatedCheckInIsLate) ??
            false;
      }
    } else {
      final lastCheckInDate = prefs.getString(
        NotificationConstants.prefLastCheckInDate,
      );
      if (lastCheckInDate == today) {
        inTime = prefs.getString(NotificationConstants.prefLastCheckInTime);
        final lastOutDate = prefs.getString(
          NotificationConstants.prefLastCheckOutDate,
        );
        outTime = (lastOutDate == today)
            ? prefs.getString(NotificationConstants.prefLastCheckOutTime)
            : null;
        isLate =
            prefs.getBool(NotificationConstants.prefLastCheckInIsLate) ?? false;
      }
    }

    if (mounted) {
      setState(() {
        _bannerMode = bannerMode;
        _isSimulationMode = isSim;
        _todayHoliday = holiday;
        _tomorrowLunchBooked = lunchBooked;
        _lastCheckInTime = inTime;
        _lastCheckOutTime = outTime;
        _isLate = isLate;
      });
    }
  }

  Future<void> _syncLiveAttendance() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final isSim =
          prefs.getBool(NotificationConstants.prefPacklySimulationMode) ??
          false;
      final status = await PacklyAttendanceService.instance
          .getAttendanceStatus();
      if (mounted) {
        setState(() {
          _isSimulationMode = isSim;
          _liveStatus = status;
          if (status.checkInTime != null) {
            _lastCheckInTime = status.checkInTime;
            _isLate = status.isLate;
          }
          _lastCheckOutTime = status.checkOutTime;
          _isLoading = false;
        });
        if (status.isCheckedIn) {
          ref
              .read(settingsNotifierProvider.notifier)
              .updateCheckInStatus('Punched In');
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleCheckIn() async {
    setState(() => _isLoading = true);
    try {
      final result = await PacklyAttendanceService.instance.checkIn();
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (result.status != null) {
            _liveStatus = result.status;
            _lastCheckInTime = result.status!.checkInTime;
            _isLate = result.status!.isLate;
          }
        });
        ref
            .read(settingsNotifierProvider.notifier)
            .updateCheckInStatus('Punched In');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: result.success
                ? Colors.green.shade800
                : Colors.red.shade800,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Check-In error: $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    }
  }

  Future<void> _handleCheckOut() async {
    final now = DateTime.now();
    final isEarly = now.hour < 18;
    final isUpdate = _lastCheckOutTime != null;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: FluentRadius.cardBorder),
        title: Row(
          children: [
            Icon(
              isEarly
                  ? Icons.warning_amber_rounded
                  : (isUpdate ? Icons.update : Icons.logout),
              color: isEarly
                  ? const Color(0xFFF59E0B)
                  : (isUpdate
                        ? Theme.of(ctx).colorScheme.primary
                        : Theme.of(ctx).colorScheme.error),
            ),
            const SizedBox(width: FluentSpacing.s),
            Expanded(
              child: Text(
                isEarly
                    ? 'Early Check-Out Alert'
                    : (isUpdate
                          ? 'Update Check-Out (OT)'
                          : 'End Workday & Check Out?'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: FluentType.subtitle.copyWith(fontSize: 16),
              ),
            ),
          ],
        ),
        content: Text(
          isEarly
              ? 'অফিস সময় সন্ধ্যা ৬:০০ টা পর্যন্ত (মোট ৯ ঘণ্টা)। আপনি নির্ধারিত সময়ের পূর্বে বের হচ্ছেন। ম্যানেজমেন্টের অনুমোদন নিয়ে থাকলে "Proceed Early Out" চাপুন।'
              : (isUpdate
                    ? 'আপনার পূর্বের চেক-আউট ছিল: $_lastCheckOutTime। এখন নতুন পাঞ্চ দিলে সিস্টেমে আপনার সর্বশেষ সময় রেকর্ড হবে এবং ওভারটাইম গণনা হবে। আপডেট করতে চান?'
                    : 'Are you sure you want to punch check-out on Zavisoft Packly? This will record your departure location and end today’s attendance.'),
          style: FluentType.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isEarly
                  ? const Color(0xFFF59E0B)
                  : (isUpdate
                        ? Theme.of(ctx).colorScheme.primary
                        : Theme.of(ctx).colorScheme.error),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: FluentRadius.controlBorder,
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              isEarly
                  ? 'Proceed Early Out'
                  : (isUpdate ? 'Update Check-Out' : 'Yes, Check Out Now'),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      final result = await PacklyAttendanceService.instance.checkOut();
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (result.status != null) {
            _liveStatus = result.status;
            _lastCheckOutTime = result.status!.checkOutTime;
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: result.success
                ? Colors.green.shade800
                : Colors.red.shade800,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Check-Out error: $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsNotifierProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    final onSurface = scheme.onSurface;
    final onSurfaceMuted = onSurface.withValues(alpha: 0.65);
    final surface = theme.cardTheme.color ?? theme.cardColor;
    final lunchState = ref.watch(lunchProvider);
    final tomorrowBooked = lunchState.tomorrowBooked ?? _tomorrowLunchBooked;

    return StreamBuilder<OfficeConnectionState>(
      stream: WifiMonitorService.instance.officeStateStream,
      initialData: WifiMonitorService.instance.currentState,
      builder: (context, snapshot) {
        final state = snapshot.data ?? OfficeConnectionState.unknown;
        final isOfficeConnected = state == OfficeConnectionState.connected;
        final currentSsid =
            WifiMonitorService.instance.currentSsid ?? 'Not connected';

        final checkInStatus =
            settingsAsync.value?.lastCheckInStatus ?? 'Pending';
        final isPunchedIn =
            (_liveStatus?.isCheckedIn ?? false) ||
            checkInStatus.toLowerCase().contains('punch');
        final isPunchedOut =
            _liveStatus?.isCheckedOut ?? (_lastCheckOutTime != null);
        final isTodayOff = settingsAsync.value?.isTodayOffDay ?? false;

        // Contextual Display Logic (Keeps Study Dashboard Clean & Distraction-Free)
        if (!widget.forceVisible) {
          if (_bannerMode == 'hidden') {
            return const SizedBox.shrink();
          }
          if (_bannerMode == 'contextual') {
            // If connected to Office Wi-Fi, show
            if (!isOfficeConnected) {
              // If today is a holiday or weekly off-day, hide from study dashboard
              if (_todayHoliday != null || isTodayOff) {
                return const SizedBox.shrink();
              }
              // If outside office window (before 8:45 AM or after 6:30 PM), hide from study dashboard
              final now = DateTime.now();
              final currentMinutes = now.hour * 60 + now.minute;
              final isOfficeHoursWindow =
                  currentMinutes >= (8 * 60 + 45) &&
                  currentMinutes <= (18 * 60 + 30);
              if (!isOfficeHoursWindow) {
                return const SizedBox.shrink();
              }
            }
          }
        }

        // 1. Official Holiday Banner (from Zavisoft Packly Calendar)
        if (_todayHoliday != null) {
          return Padding(
            padding: const EdgeInsets.only(bottom: FluentSpacing.l),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: FluentRadius.cardBorder,
                side: FluentStroke.side(brightness),
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: FluentRadius.cardBorder,
                  color: FluentLayer.subtle(scheme.primary, brightness),
                ),
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
                                Icons.celebration_rounded,
                                color: scheme.primary,
                                size: 20,
                              ),
                              const SizedBox(width: FluentSpacing.s),
                              Expanded(
                                child: Text(
                                  _todayHoliday!.name,
                                  style: FluentType.bodyStrong.copyWith(
                                    color: onSurface,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: FluentSpacing.s),
                        Flexible(
                          child: PremiumTag(
                            label: '🎉 Holiday',
                            color: scheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: FluentSpacing.m),
                    Text(
                      'আজ ${_todayHoliday!.formattedWithWeekday} উপলক্ষে ZaviSoft অফিস বন্ধ! ${_todayHoliday!.name} এর জন্য বায়োমেট্রিক চেক-ইন ও কাটঅফ অ্যালার্ট স্থগিত রয়েছে।',
                      style: FluentType.body.copyWith(color: onSurface),
                    ),
                    const SizedBox(height: FluentSpacing.xs + 2),
                    Text(
                      'Enjoy your holiday with family and use this free time for focused study.',
                      style: FluentType.caption.copyWith(color: onSurfaceMuted),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // 2. Weekly Off-Day Banner (e.g. Thursday & Friday)
        if (isTodayOff) {
          final now = DateTime.now();
          final dayNameEn = now.weekday == DateTime.thursday
              ? 'Thursday'
              : (now.weekday == DateTime.friday ? 'Friday' : 'Weekend');
          final dayNameBn = PacklyHoliday.weekdayNameBn(now.weekday);

          return Padding(
            padding: const EdgeInsets.only(bottom: FluentSpacing.l),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: FluentRadius.cardBorder,
                side: FluentStroke.side(brightness),
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: FluentRadius.cardBorder,
                  color: FluentLayer.subtle(scheme.primary, brightness),
                ),
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
                                Icons.beach_access,
                                color: scheme.primary,
                                size: 20,
                              ),
                              const SizedBox(width: FluentSpacing.s),
                              Expanded(
                                child: Text(
                                  'Weekly Off-Day ($dayNameEn - $dayNameBn)',
                                  style: FluentType.bodyStrong.copyWith(
                                    color: onSurface,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: FluentSpacing.s),
                        Flexible(
                          child: PremiumTag(
                            label: '🌴 Off-Day',
                            color: scheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: FluentSpacing.m),
                    Text(
                      'No office today! Biometric check-in and 4 PM dinner alerts are paused.',
                      style: FluentType.body.copyWith(color: onSurface),
                    ),
                    const SizedBox(height: FluentSpacing.xs + 2),
                    Text(
                      'Enjoy guilt-free family time and leverage this day for deeper BCS focus.',
                      style: FluentType.caption.copyWith(color: onSurfaceMuted),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: FluentSpacing.l),
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: FluentRadius.cardBorder,
              side: FluentStroke.side(brightness),
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: FluentRadius.cardBorder,
                color: isOfficeConnected
                    ? FluentLayer.subtle(scheme.primary, brightness)
                    : surface,
              ),
              padding: const EdgeInsets.all(FluentSpacing.l),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Row: Wi-Fi status + Packly Sync Button
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
                                    ? 'Office Active (ZaviSoft)'
                                    : 'Away from Office',
                                style: FluentType.bodyStrong.copyWith(
                                  color: isOfficeConnected
                                      ? scheme.primary
                                      : onSurfaceMuted,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (_isSimulationMode) ...[
                              const SizedBox(width: FluentSpacing.xs + 2),
                              const Flexible(
                                child: PremiumTag(
                                  label: 'TEST MODE',
                                  icon: Icons.science,
                                  color: Color(0xFFF59E0B),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: FluentSpacing.xs + 2),
                      // Sync with Packly button
                      InkWell(
                        onTap: _syncLiveAttendance,
                        borderRadius: FluentRadius.controlBorder,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: FluentSpacing.s,
                            vertical: FluentSpacing.xs,
                          ),
                          decoration: BoxDecoration(
                            color: FluentLayer.subtle(onSurface, brightness),
                            borderRadius: FluentRadius.controlBorder,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_isLoading)
                                SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: scheme.primary,
                                  ),
                                )
                              else
                                Icon(
                                  Icons.sync,
                                  size: 13,
                                  color: scheme.primary,
                                ),
                              const SizedBox(width: FluentSpacing.xs),
                              Flexible(
                                child: Text(
                                  currentSsid,
                                  style: FluentType.caption.copyWith(
                                    color: onSurface,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: FluentSpacing.m),

                  // Biometric Punch Row
                  Row(
                    children: [
                      PremiumIconBadge(
                        icon: isPunchedIn
                            ? (isPunchedOut
                                  ? Icons.check_circle
                                  : Icons.fingerprint)
                            : Icons.warning_amber_rounded,
                        size: 44,
                        iconSize: 24,
                        color: isPunchedIn
                            ? (isPunchedOut
                                  ? scheme.primary
                                  : const Color(0xFF10B981))
                            : const Color(0xFFF59E0B),
                      ),
                      const SizedBox(width: FluentSpacing.m),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    isPunchedOut
                                        ? 'Workday Ended'
                                        : (isPunchedIn
                                              ? 'Punched In ✓'
                                              : 'Punch Pending'),
                                    style: FluentType.bodyStrong.copyWith(
                                      color: isPunchedOut
                                          ? scheme.primary
                                          : (isPunchedIn
                                                ? const Color(0xFF10B981)
                                                : const Color(0xFFF59E0B)),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                                if (_isLate && isPunchedIn) ...[
                                  const SizedBox(width: FluentSpacing.xs + 2),
                                  Flexible(
                                    child: PremiumTag(
                                      label: 'LATE',
                                      color: scheme.error,
                                    ),
                                  ),
                                ] else if (isPunchedIn && !_isLate) ...[
                                  const SizedBox(width: FluentSpacing.xs + 2),
                                  const Flexible(
                                    child: PremiumTag(
                                      label: 'ON-TIME',
                                      color: Color(0xFF10B981),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: FluentSpacing.xxs),
                            Text(
                              _lastCheckInTime != null
                                  ? (_lastCheckOutTime != null
                                        ? 'In: $_lastCheckInTime • Out: $_lastCheckOutTime'
                                        : 'In: $_lastCheckInTime (ZaviSoft Portal)')
                                  : 'Shift: 9:00 AM – 6:00 PM (Late cutoff 9:15 AM)',
                              style: FluentType.caption.copyWith(
                                color: onSurfaceMuted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: FluentSpacing.s),

                      // Punch Actions
                      if (!isPunchedIn)
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: scheme.primary,
                            foregroundColor: scheme.onPrimary,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: FluentRadius.controlBorder,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: FluentSpacing.m,
                              vertical: FluentSpacing.s,
                            ),
                            textStyle: FluentType.caption.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onPressed: _isLoading ? null : _handleCheckIn,
                          child: _isLoading
                              ? SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: scheme.onPrimary,
                                  ),
                                )
                              : const Text('Check In'),
                        )
                      else if (!isPunchedOut)
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: scheme.error,
                            foregroundColor: scheme.onError,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: FluentRadius.controlBorder,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: FluentSpacing.m,
                              vertical: FluentSpacing.s,
                            ),
                            textStyle: FluentType.caption.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onPressed: _isLoading ? null : _handleCheckOut,
                          child: _isLoading
                              ? SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: scheme.onError,
                                  ),
                                )
                              : const Text('Check Out'),
                        )
                      else
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: scheme.primary,
                            side: BorderSide(
                              color: FluentStroke.card(brightness),
                              width: FluentStroke.width,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: FluentRadius.controlBorder,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: FluentSpacing.s,
                              vertical: FluentSpacing.xs + 2,
                            ),
                          ),
                          icon: const Icon(Icons.update, size: 12),
                          onPressed: _isLoading ? null : _handleCheckOut,
                          label: Text(
                            'Update Out (OT)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FluentType.caption,
                          ),
                        ),
                    ],
                  ),
                  Divider(
                    color: FluentStroke.divider(brightness),
                    height: FluentSpacing.xxl,
                  ),

                  // Steadfast Lunch Status Row (Tomorrow's Meal & 6 PM Cutoff)
                  Row(
                    children: [
                      Icon(
                        Icons.lunch_dining_rounded,
                        color: scheme.primary,
                        size: 20,
                      ),
                      const SizedBox(width: FluentSpacing.s),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tomorrowBooked == true
                                  ? 'Tomorrow Lunch: Booked ✓ (Lunch)'
                                  : 'Tomorrow Lunch: Not Booked (Off)',
                              style: FluentType.body.copyWith(
                                fontWeight: FontWeight.w600,
                                color: onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'Daily Cutoff: 6:00 PM (Steadfast Catering)',
                              style: FluentType.caption.copyWith(
                                color: onSurfaceMuted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: FluentSpacing.s),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: FluentLayer.subtle(
                            tomorrowBooked == true
                                ? scheme.error
                                : scheme.primary,
                            brightness,
                          ),
                          foregroundColor: tomorrowBooked == true
                              ? scheme.error
                              : scheme.primary,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: FluentRadius.controlBorder,
                          ),
                          side: BorderSide(
                            color: FluentStroke.card(brightness),
                            width: FluentStroke.width,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: FluentSpacing.s,
                            vertical: FluentSpacing.xs,
                          ),
                          minimumSize: const Size(40, 26),
                        ),
                        onPressed: lunchState.isToggling
                            ? null
                            : () async {
                                final res = await ref
                                    .read(lunchProvider.notifier)
                                    .toggleTomorrowMeal();
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
                        child: lunchState.isToggling
                            ? SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: scheme.primary,
                                ),
                              )
                            : Text(
                                tomorrowBooked == true ? 'Cancel' : 'Book',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: FluentType.caption,
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: FluentSpacing.m),

                  // Link to Full Office Portal & Interactive Calendar
                  InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const OfficePortalScreen(),
                        ),
                      );
                    },
                    borderRadius: FluentRadius.controlBorder,
                    child: Container(
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
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.calendar_month_rounded,
                            size: 14,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: FluentSpacing.xs + 2),
                          Flexible(
                            child: Text(
                              'Open Meal Calendar & Office Portal ➔',
                              style: FluentType.caption.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
