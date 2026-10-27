import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/background/wifi_monitor_service.dart';
import '../../../settings/presentation/providers/settings_provider.dart';

class BiometricStatusBanner extends ConsumerWidget {
  const BiometricStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsNotifierProvider);

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
        final isPunchedIn = checkInStatus.toLowerCase().contains('punch');
        final mealResponse = settingsAsync.value?.lastMealResponse ?? 'Pending';
        final isTodayOff = settingsAsync.value?.isTodayOffDay ?? false;

        if (isTodayOff) {
          final now = DateTime.now();
          final dayName = now.weekday == DateTime.thursday
              ? 'Thursday'
              : (now.weekday == DateTime.friday ? 'Friday' : 'Weekend');

          return Card(
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
          );
        }

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: isOfficeConnected
                    ? [Colors.blue.shade900, Colors.indigo.shade800]
                    : [Colors.grey.shade900, Colors.blueGrey.shade900],
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
                                  ? 'Office Active'
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
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      constraints: const BoxConstraints(maxWidth: 130),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        currentSsid,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
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
                            ? Icons.fingerprint
                            : Icons.warning_amber_rounded,
                        color: isPunchedIn
                            ? Colors.greenAccent
                            : Colors.amberAccent,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Biometric Attendance',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            isPunchedIn ? 'Punched In ✓' : 'Punch Pending',
                            style: TextStyle(
                              color: isPunchedIn
                                  ? Colors.greenAccent
                                  : Colors.amberAccent,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!isPunchedIn)
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.tealAccent,
                          foregroundColor: Colors.black87,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          textStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: () {
                          ref
                              .read(settingsNotifierProvider.notifier)
                              .updateCheckInStatus('Punched In');
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Marked as Punched In!'),
                            ),
                          );
                        },
                        child: const Text('Punch In'),
                      )
                    else
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                        ),
                        onPressed: () {
                          ref
                              .read(settingsNotifierProvider.notifier)
                              .updateCheckInStatus('Pending');
                        },
                        child: const Text(
                          'Reset',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                  ],
                ),
                const Divider(color: Colors.white12, height: 24),
                // Dinner 4 PM Cutoff Row
                Row(
                  children: [
                    const Icon(
                      Icons.dinner_dining,
                      color: Colors.orangeAccent,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Dinner Cutoff (4 PM): $mealResponse',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.tealAccent,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(40, 24),
                      ),
                      onPressed: () {
                        _showMealConfirmDialog(context, ref);
                      },
                      child: const Text(
                        'Change',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showMealConfirmDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Office Dinner Confirmation'),
        content: const Text('Will you have dinner at the office today?'),
        actions: [
          TextButton(
            onPressed: () {
              ref
                  .read(settingsNotifierProvider.notifier)
                  .updateMealResponse('No, Skip');
              Navigator.pop(ctx);
            },
            child: const Text(
              'No, Skip',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              ref
                  .read(settingsNotifierProvider.notifier)
                  .updateMealResponse('Yes, Count Me In');
              Navigator.pop(ctx);
            },
            child: const Text('Yes, Count Me In'),
          ),
        ],
      ),
    );
  }
}
