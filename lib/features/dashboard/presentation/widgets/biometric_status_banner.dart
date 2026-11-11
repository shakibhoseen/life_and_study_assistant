import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/config/notification_constants.dart';
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
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            left: 16,
            right: 16,
            top: 20,
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
    final holiday =
        await PacklyAttendanceService.instance.getHolidayForDate(DateTime.now());
    final bannerMode =
        prefs.getString(NotificationConstants.prefOfficeBannerMode) ?? 'contextual';
    final isSim =
        prefs.getBool(NotificationConstants.prefPacklySimulationMode) ?? false;
    final lunchBooked =
        prefs.getBool(NotificationConstants.prefLunchLastKnownTomorrowBooked);

    String? inTime;
    String? outTime;
    bool isLate = false;

    if (isSim) {
      final simDate = prefs.getString(NotificationConstants.prefSimulatedCheckInDate);
      if (simDate == today) {
        inTime = prefs.getString(NotificationConstants.prefSimulatedCheckInTime);
        outTime = prefs.getString(NotificationConstants.prefSimulatedCheckOutTime);
        isLate = prefs.getBool(NotificationConstants.prefSimulatedCheckInIsLate) ?? false;
      }
    } else {
      final lastCheckInDate =
          prefs.getString(NotificationConstants.prefLastCheckInDate);
      if (lastCheckInDate == today) {
        inTime = prefs.getString(NotificationConstants.prefLastCheckInTime);
        final lastOutDate = prefs.getString(NotificationConstants.prefLastCheckOutDate);
        outTime = (lastOutDate == today)
            ? prefs.getString(NotificationConstants.prefLastCheckOutTime)
            : null;
        isLate = prefs.getBool(NotificationConstants.prefLastCheckInIsLate) ?? false;
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
      final isSim = prefs.getBool(NotificationConstants.prefPacklySimulationMode) ?? false;
      final status = await PacklyAttendanceService.instance.getAttendanceStatus();
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
            backgroundColor: result.success ? Colors.green.shade800 : Colors.red.shade800,
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
        title: Row(
          children: [
            Icon(
              isEarly ? Icons.warning_amber_rounded : (isUpdate ? Icons.update : Icons.logout),
              color: isEarly ? Colors.amber : (isUpdate ? Colors.blue : Colors.redAccent),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isEarly
                    ? 'Early Check-Out Alert'
                    : (isUpdate ? 'Update Check-Out (OT)' : 'End Workday & Check Out?'),
                style: const TextStyle(fontSize: 16),
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
                  : (isUpdate ? Colors.indigo : Colors.red.shade700),
              foregroundColor: Colors.white,
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
            backgroundColor: result.success ? Colors.green.shade800 : Colors.red.shade800,
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
        final isPunchedIn = (_liveStatus?.isCheckedIn ?? false) ||
            checkInStatus.toLowerCase().contains('punch');
        final isPunchedOut = _liveStatus?.isCheckedOut ?? (_lastCheckOutTime != null);
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
              final isOfficeHoursWindow = currentMinutes >= (8 * 60 + 45) &&
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
            padding: const EdgeInsets.only(bottom: 16),
            child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  colors: [Colors.purple.shade900, Colors.deepPurple.shade800],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(
                              Icons.celebration_rounded,
                              color: Colors.amberAccent,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _todayHoliday!.name,
                                style: const TextStyle(
                                  color: Colors.amberAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.amberAccent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.amberAccent,
                            width: 0.8,
                          ),
                        ),
                        child: const Text(
                          '🎉 Holiday',
                          style: TextStyle(
                            color: Colors.amberAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'ZaviSoft office is closed today for ${_todayHoliday!.name}! Biometric check-in, check-out, and 9:15 AM late warnings are paused.',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Enjoy your holiday with family and use this free time for focused study.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 11,
                    ),
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
        final dayName = now.weekday == DateTime.thursday
            ? 'Thursday'
            : (now.weekday == DateTime.friday ? 'Friday' : 'Weekend');

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  colors: [Colors.teal.shade900, Colors.indigo.shade900],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(
                              Icons.beach_access,
                              color: Colors.tealAccent,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Weekly Off-Day ($dayName)',
                                style: const TextStyle(
                                  color: Colors.tealAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.tealAccent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          '🌴 Off-Day',
                          style: TextStyle(
                            color: Colors.tealAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No office today! Biometric check-in and 4 PM dinner alerts are paused.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Enjoy guilt-free family time and leverage this day for deeper BCS focus.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          child: Container(
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
            padding: const EdgeInsets.all(16),
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
                                ? Colors.tealAccent
                                : Colors.white70,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isOfficeConnected
                                  ? 'Office Active (ZaviSoft)'
                                  : 'Away from Office',
                              style: TextStyle(
                                color: isOfficeConnected
                                    ? Colors.tealAccent
                                    : Colors.white70,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_isSimulationMode) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: Colors.amberAccent,
                                  width: 0.8,
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.science,
                                    size: 10,
                                    color: Colors.amberAccent,
                                  ),
                                  SizedBox(width: 3),
                                  Text(
                                    'TEST MODE',
                                    style: TextStyle(
                                      color: Colors.amberAccent,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Sync with Packly button
                    InkWell(
                      onTap: _syncLiveAttendance,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_isLoading)
                              const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.tealAccent,
                                ),
                              )
                            else
                              const Icon(
                                Icons.sync,
                                size: 13,
                                color: Colors.tealAccent,
                              ),
                            const SizedBox(width: 4),
                            Text(
                              currentSsid,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Biometric Punch Row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isPunchedIn
                            ? Colors.greenAccent.withValues(alpha: 0.2)
                            : Colors.amberAccent.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isPunchedIn
                            ? (isPunchedOut ? Icons.check_circle : Icons.fingerprint)
                            : Icons.warning_amber_rounded,
                        color: isPunchedIn
                            ? (isPunchedOut ? Colors.blueAccent : Colors.greenAccent)
                            : Colors.amberAccent,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 12),
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
                                  style: TextStyle(
                                    color: isPunchedOut
                                        ? Colors.blueAccent
                                        : (isPunchedIn
                                            ? Colors.greenAccent
                                            : Colors.amberAccent),
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                              if (_isLate && isPunchedIn) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent.withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: Colors.redAccent,
                                      width: 0.8,
                                    ),
                                  ),
                                  child: const Text(
                                    'LATE',
                                    style: TextStyle(
                                      color: Colors.redAccent,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ] else if (isPunchedIn && !_isLate) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.greenAccent.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'ON-TIME',
                                    style: TextStyle(
                                      color: Colors.greenAccent,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _lastCheckInTime != null
                                ? (_lastCheckOutTime != null
                                    ? 'In: $_lastCheckInTime • Out: $_lastCheckOutTime'
                                    : 'In: $_lastCheckInTime (ZaviSoft Portal)')
                                : 'Shift: 9:00 AM – 6:00 PM (Late cutoff 9:15 AM)',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Punch Actions
                    if (!isPunchedIn)
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.tealAccent,
                          foregroundColor: Colors.black87,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          textStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: _isLoading ? null : _handleCheckIn,
                        child: _isLoading
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black87,
                                ),
                              )
                            : const Text('Check In'),
                      )
                    else if (!isPunchedOut)
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent.shade400,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          textStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: _isLoading ? null : _handleCheckOut,
                        child: _isLoading
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Check Out'),
                      )
                    else
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.lightBlueAccent,
                          side: const BorderSide(color: Colors.lightBlueAccent),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                        ),
                        icon: const Icon(Icons.update, size: 12),
                        onPressed: _isLoading ? null : _handleCheckOut,
                        label: const Text(
                          'Update Out (OT)',
                          style: TextStyle(fontSize: 10.5),
                        ),
                      ),
                  ],
                ),
                const Divider(color: Colors.white12, height: 24),

                // Steadfast Lunch Status Row (Tomorrow's Meal & 6 PM Cutoff)
                Row(
                  children: [
                    const Icon(
                      Icons.lunch_dining_rounded,
                      color: Colors.orangeAccent,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tomorrowBooked == true
                                ? 'Tomorrow Lunch: Booked ✓ (Lunch)'
                                : 'Tomorrow Lunch: Not Booked (Off)',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const Text(
                            'Daily Cutoff: 6:00 PM (Steadfast Catering)',
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 10.5,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: tomorrowBooked == true
                            ? Colors.red.withValues(alpha: 0.3)
                            : Colors.tealAccent.withValues(alpha: 0.2),
                        foregroundColor: tomorrowBooked == true
                            ? Colors.redAccent
                            : Colors.tealAccent,
                        side: BorderSide(
                          color: tomorrowBooked == true
                              ? Colors.redAccent
                              : Colors.tealAccent,
                          width: 0.8,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
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
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.tealAccent,
                              ),
                            )
                          : Text(
                              tomorrowBooked == true ? 'Cancel' : 'Book',
                              style: const TextStyle(fontSize: 11),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

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
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.calendar_month_rounded,
                          size: 14,
                          color: Colors.tealAccent,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Open Meal Calendar & Office Portal ➔',
                          style: TextStyle(
                            color: Colors.tealAccent,
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
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
