import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/theme_provider.dart';

class ThemeSelectorCard extends ConsumerWidget {
  const ThemeSelectorCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMode = ref.watch(themeModeProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
            const Text(
              'Select Interface Color Scheme',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Midnight OLED Dark reduces eye fatigue after long coding sessions in the office.',
              style: TextStyle(
                fontSize: 11.5,
                color: isDark ? Colors.white60 : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.brightness_auto, size: 20),
              title: const Text(
                'System Default',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              subtitle: const Text(
                'Follows device light / dark schedule',
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
              onTap: () => ref
                  .read(themeModeProvider.notifier)
                  .setThemeMode(ThemeMode.system),
            ),
            const Divider(height: 1),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.light_mode,
                size: 20,
                color: Colors.amber,
              ),
              title: const Text(
                'Clean Light Mode',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              subtitle: const Text(
                'Crisp white slate and deep indigo',
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
              onTap: () => ref
                  .read(themeModeProvider.notifier)
                  .setThemeMode(ThemeMode.light),
            ),
            const Divider(height: 1),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.dark_mode,
                size: 20,
                color: Color(0xFF6366F1),
              ),
              title: const Text(
                'Midnight OLED Dark 🌙',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                'Obsidian black (#090D1A) - zero eye strain & power saving',
                style: TextStyle(fontSize: 11),
              ),
              trailing: currentMode == ThemeMode.dark
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
              onTap: () => ref
                  .read(themeModeProvider.notifier)
                  .setThemeMode(ThemeMode.dark),
            ),
          ],
        ),
      ),
    );
  }
}
