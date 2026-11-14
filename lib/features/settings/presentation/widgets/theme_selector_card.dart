import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/fluent_tokens.dart';
import '../../../../core/theme/theme_provider.dart';

class ThemeSelectorCard extends ConsumerWidget {
  const ThemeSelectorCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMode = ref.watch(themeModeProvider);
    final activeDarkPreset = ref.watch(darkThemePresetProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    void selectDarkPreset(DarkThemePreset preset) {
      HapticFeedback.selectionClick();
      if (currentMode != ThemeMode.dark) {
        ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.dark);
      }
      ref.read(darkThemePresetProvider.notifier).setPreset(preset);
    }

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
                Icon(Icons.palette_outlined, size: 18, color: scheme.primary),
                const SizedBox(width: FluentSpacing.s),
                Expanded(
                  child: Text(
                    'Select Interface Theme',
                    maxLines: 1,
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
              'চোখের আরাম ও পড়ালেখার পরিবেশ অনুযায়ী আপনার পছন্দের থিম ও কালার স্কিম বেছে নিন।',
              style: FluentType.caption.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: FluentSpacing.m),

            // General Modes (System & Light)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.brightness_auto,
                size: 20,
                color: scheme.onSurface.withValues(alpha: 0.65),
              ),
              title: Text(
                'System Default',
                style: FluentType.bodyStrong.copyWith(color: scheme.onSurface),
              ),
              subtitle: Text(
                'ডিভাইসের ডিফল্ট লাইট/ডার্ক শিডিউল অনুসরণ করে',
                style: FluentType.caption.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
              trailing: Icon(
                currentMode == ThemeMode.system
                    ? Icons.check_circle
                    : Icons.circle_outlined,
                color: currentMode == ThemeMode.system
                    ? scheme.primary
                    : scheme.onSurface.withValues(alpha: 0.38),
                size: 20,
              ),
              onTap: () {
                HapticFeedback.selectionClick();
                ref
                    .read(themeModeProvider.notifier)
                    .setThemeMode(ThemeMode.system);
              },
            ),
            const Divider(height: 1),

            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.light_mode_rounded,
                size: 20,
                color: Color(0xFFF59E0B),
              ),
              title: Text(
                'Clean Light Mode ☀️',
                style: FluentType.bodyStrong.copyWith(color: scheme.onSurface),
              ),
              subtitle: Text(
                'উজ্জ্বল সাদা ও ডিপ ইনডিগো — দিনের বেলায় পড়ার জন্য',
                style: FluentType.caption.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
              trailing: Icon(
                currentMode == ThemeMode.light
                    ? Icons.check_circle
                    : Icons.circle_outlined,
                color: currentMode == ThemeMode.light
                    ? scheme.primary
                    : scheme.onSurface.withValues(alpha: 0.38),
                size: 20,
              ),
              onTap: () {
                HapticFeedback.selectionClick();
                ref
                    .read(themeModeProvider.notifier)
                    .setThemeMode(ThemeMode.light);
              },
            ),

            const SizedBox(height: FluentSpacing.l),
            Row(
              children: [
                Icon(Icons.nightlight_round, size: 16, color: scheme.primary),
                const SizedBox(width: FluentSpacing.s),
                Expanded(
                  child: Text(
                    'ডার্ক ও স্টাডি থিমসমূহ (Aesthetic Dark Palettes)',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: FluentType.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: FluentSpacing.s),

            // 1. Cute Velvet Night
            _buildThemeOption(
              context,
              title: 'Cute Velvet Night 🌸💜 (কউট ডার্ক)',
              subtitle: 'সফট ল্যাভেন্ডার, প্যাস্টেল রোজ ও কোজি ভেলভেট — মিষ্টি ও ফ্রেন্ডলি',
              icon: Icons.auto_awesome,
              iconColor: const Color(0xFFC084FC),
              isSelected:
                  currentMode == ThemeMode.dark &&
                  activeDarkPreset == DarkThemePreset.cuteVelvet,
              onTap: () => selectDarkPreset(DarkThemePreset.cuteVelvet),
            ),
            const Divider(height: 1),

            // 2. Cozy Mocha & Espresso
            _buildThemeOption(
              context,
              title: 'Cozy Mocha & Espresso ☕🤎 (ক্যাফে স্টাডি)',
              subtitle: 'ওয়ার্ম রোস্টেড চকোলেট ও ক্যারামেল — কফি শপ ও লাইব্রেরি বুকিশ ভাইব',
              icon: Icons.coffee_rounded,
              iconColor: const Color(0xFFF59E0B),
              isSelected:
                  currentMode == ThemeMode.dark &&
                  activeDarkPreset == DarkThemePreset.cozyMocha,
              onTap: () => selectDarkPreset(DarkThemePreset.cozyMocha),
            ),
            const Divider(height: 1),

            // 3. Nordic Twilight
            _buildThemeOption(
              context,
              title: 'Nordic Twilight 🌌❄️ (নর্ডিক মিডনাইট)',
              subtitle: 'ডিপ ব্লুবেরি নেভি ও আইস সায়ান — শান্ত ও মার্জিত রাত',
              icon: Icons.nights_stay_rounded,
              iconColor: const Color(0xFF38BDF8),
              isSelected:
                  currentMode == ThemeMode.dark &&
                  activeDarkPreset == DarkThemePreset.nordicTwilight,
              onTap: () => selectDarkPreset(DarkThemePreset.nordicTwilight),
            ),
            const Divider(height: 1),

            // 4. OLED Battery Saver
            _buildThemeOption(
              context,
              title: 'OLED Battery Saver 🔋⚡ (আল্ট্রা ব্ল্যাক)',
              subtitle: 'Obsidian pitch-black (#090D1A) — AMOLED স্ক্রিনে সর্বোচ্চ ব্যাটারি সাশ্রয়ী',
              icon: Icons.battery_saver_rounded,
              iconColor: const Color(0xFF10B981),
              isSelected:
                  currentMode == ThemeMode.dark &&
                  activeDarkPreset == DarkThemePreset.oledBatterySaver,
              onTap: () => selectDarkPreset(DarkThemePreset.oledBatterySaver),
            ),
            const Divider(height: 1),

            // 5. Nature Green
            _buildThemeOption(
              context,
              title: 'Nature Green 🌿🌲 (প্রকৃতি ও ফরেস্ট)',
              subtitle: 'শান্ত বনানী সবুজ ও এমারেল্ড — চোখ জুড়ানো প্রশান্তি ও স্টাডি ফোকাস',
              icon: Icons.forest_rounded,
              iconColor: const Color(0xFF34D399),
              isSelected:
                  currentMode == ThemeMode.dark &&
                  activeDarkPreset == DarkThemePreset.natureGreen,
              onTap: () => selectDarkPreset(DarkThemePreset.natureGreen),
            ),
            const Divider(height: 1),

            // 6. Ice Blue
            _buildThemeOption(
              context,
              title: 'Ice Blue ❄️🧊 (আইসি ব্লু ফ্রস্ট)',
              subtitle: 'ক্রিস্প বরফ নীল ও সায়ান — রিফ্রেশিং, ক্লিন ও আধুনিক প্রিমিয়াম লুক',
              icon: Icons.ac_unit_rounded,
              iconColor: const Color(0xFF60A5FA),
              isSelected:
                  currentMode == ThemeMode.dark &&
                  activeDarkPreset == DarkThemePreset.iceBlue,
              onTap: () => selectDarkPreset(DarkThemePreset.iceBlue),
            ),
            const Divider(height: 1),

            // 7. Premium Gold
            _buildThemeOption(
              context,
              title: 'Premium Gold 👑✨ (লাক্সারি গোল্ড)',
              subtitle: 'অভিজাত গাঢ় অন্ধকার ও উজ্জ্বল স্বর্ণালী আভা — এক্সিকিউটিভ প্রিমিয়াম ফিল',
              icon: Icons.workspace_premium_rounded,
              iconColor: const Color(0xFFFFB800),
              isSelected:
                  currentMode == ThemeMode.dark &&
                  activeDarkPreset == DarkThemePreset.premiumGold,
              onTap: () => selectDarkPreset(DarkThemePreset.premiumGold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeOption(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      // The swatch colour stays: it is a preview of the palette, not decoration.
      leading: Icon(icon, size: 20, color: iconColor),
      title: Text(
        title,
        style: (isSelected ? FluentType.bodyStrong : FluentType.body).copyWith(
          color: scheme.onSurface,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: FluentType.caption.copyWith(
          color: scheme.onSurface.withValues(alpha: 0.65),
        ),
      ),
      trailing: Icon(
        isSelected ? Icons.check_circle : Icons.circle_outlined,
        color: isSelected
            ? scheme.primary
            : scheme.onSurface.withValues(alpha: 0.38),
        size: 20,
      ),
      onTap: onTap,
    );
  }
}
