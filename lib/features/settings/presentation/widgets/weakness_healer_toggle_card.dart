import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/fluent_tokens.dart';
import '../../../../core/widgets/premium_glass_card.dart';
import '../providers/settings_provider.dart';

class WeaknessHealerToggleCard extends ConsumerWidget {
  final SettingsState settings;

  const WeaknessHealerToggleCard({super.key, required this.settings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isEnabled = settings.isWeaknessHealingEnabled;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;

    // Green here carries status meaning: the engine is on.
    const successColor = Color(0xFF10B981);

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
            Row(
              children: [
                PremiumIconBadge(
                  icon: Icons.healing_rounded,
                  size: 38,
                  iconSize: 20,
                  color: scheme.primary,
                ),
                const SizedBox(width: FluentSpacing.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Daily 3-Min Weakness Micro Drills',
                        style: FluentType.bodyStrong.copyWith(
                          color: scheme.onSurface,
                        ),
                      ),
                      Text(
                        'অটো-উইকনেস হিলিং ইঞ্জিন ও ড্রিল কন্ট্রোল',
                        style: FluentType.caption.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: isEnabled,
                  activeThumbColor: scheme.primary,
                  onChanged: (val) {
                    ref
                        .read(settingsNotifierProvider.notifier)
                        .setWeaknessHealingEnabled(val);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          val
                              ? 'অটো-উইকনেস হিলিং সক্রিয় করা হয়েছে 🩺'
                              : 'অটো-উইকনেস হিলিং বন্ধ রাখা হয়েছে ⏸️',
                        ),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: FluentSpacing.s),
            Text(
              isEnabled
                  ? '✓ সক্রিয়: লাইভ এমসিকিউ বা পরীক্ষায় ভুল হওয়া টপিকগুলোর ওপর ড্যাশবোর্ডে দৈনিক ৩ মিনিটের মাইক্রো-রিভিশন ড্রিল প্রদর্শন করা হবে।'
                  : '⏸️ নিষ্ক্রিয়: দুর্বল টপিকের মাইক্রো-ড্রিল কার্ড ড্যাশবোর্ডে প্রদর্শিত হবে না। যেকোনো সময় পুনরায় চালু করতে পারেন।',
              style: FluentType.caption.copyWith(
                color: isEnabled
                    ? successColor
                    : scheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
