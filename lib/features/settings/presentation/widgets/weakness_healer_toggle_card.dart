import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_provider.dart';

class WeaknessHealerToggleCard extends ConsumerWidget {
  final SettingsState settings;

  const WeaknessHealerToggleCard({super.key, required this.settings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
}
