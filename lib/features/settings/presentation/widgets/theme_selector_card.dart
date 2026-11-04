import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/theme_provider.dart';

class ThemeSelectorCard extends ConsumerWidget {
  const ThemeSelectorCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMode = ref.watch(themeModeProvider);
    final activeDarkPreset = ref.watch(darkThemePresetProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    void selectDarkPreset(DarkThemePreset preset) {
      HapticFeedback.selectionClick();
      if (currentMode != ThemeMode.dark) {
        ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.dark);
      }
      ref.read(darkThemePresetProvider.notifier).setPreset(preset);
    }

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.palette_outlined, size: 18, color: Color(0xFF6366F1)),
                SizedBox(width: 8),
                Text(
                  'Select Interface Theme',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'চোখের আরাম ও পড়ালেখার পরিবেশ অনুযায়ী আপনার পছন্দের থিম ও কালার স্কিম বেছে নিন।',
              style: TextStyle(
                fontSize: 11.5,
                color: isDark ? Colors.white60 : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 12),

            // General Modes (System & Light)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.brightness_auto, size: 20),
              title: const Text(
                'System Default',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              subtitle: const Text(
                'ডিভাইসের ডিফল্ট লাইট/ডার্ক শিডিউল অনুসরণ করে',
                style: TextStyle(fontSize: 11),
              ),
              trailing: currentMode == ThemeMode.system
                  ? const Icon(
                      Icons.check_circle,
                      color: Color(0xFF6366F1),
                      size: 20,
                    )
                  : const Icon(
                      Icons.circle_outlined,
                      color: Colors.grey,
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
                color: Colors.amber,
              ),
              title: const Text(
                'Clean Light Mode ☀️',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              subtitle: const Text(
                'উজ্জ্বল সাদা ও ডিপ ইনডিগো — দিনের বেলায় পড়ার জন্য',
                style: TextStyle(fontSize: 11),
              ),
              trailing: currentMode == ThemeMode.light
                  ? const Icon(
                      Icons.check_circle,
                      color: Color(0xFF6366F1),
                      size: 20,
                    )
                  : const Icon(
                      Icons.circle_outlined,
                      color: Colors.grey,
                      size: 20,
                    ),
              onTap: () {
                HapticFeedback.selectionClick();
                ref
                    .read(themeModeProvider.notifier)
                    .setThemeMode(ThemeMode.light);
              },
            ),

            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(
                  Icons.nightlight_round,
                  size: 15,
                  color: Color(0xFFA78BFA),
                ),
                const SizedBox(width: 6),
                Text(
                  'ডার্ক ও স্টাডি থিমসমূহ (Aesthetic Dark Palettes)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // 1. Cute Velvet Night
            _buildThemeOption(
              context,
              title: 'Cute Velvet Night 🌸💜 (কউট ডার্ক)',
              subtitle: 'সফট ল্যাভেন্ডার, প্যাস্টেল রোজ ও কোজি ভেলভেট — মিষ্টি ও ফ্রেন্ডলি',
              icon: Icons.auto_awesome,
              iconColor: const Color(0xFFC084FC),
              isSelected: currentMode == ThemeMode.dark &&
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
              isSelected: currentMode == ThemeMode.dark &&
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
              isSelected: currentMode == ThemeMode.dark &&
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
              isSelected: currentMode == ThemeMode.dark &&
                  activeDarkPreset == DarkThemePreset.oledBatterySaver,
              onTap: () => selectDarkPreset(DarkThemePreset.oledBatterySaver),
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
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 20, color: iconColor),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 10.5),
      ),
      trailing: isSelected
          ? Icon(
              Icons.check_circle,
              color: iconColor,
              size: 20,
            )
          : const Icon(
              Icons.circle_outlined,
              color: Colors.grey,
              size: 20,
            ),
      onTap: onTap,
    );
  }
}
