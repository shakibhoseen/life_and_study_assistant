import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/ui_style_provider.dart';

/// Lets the user pick how the app's surfaces are rendered, independently of
/// the colour theme: the original flat look, Windows 11 style Mica, or the
/// animated Acrylic treatment.
class UiStyleSelectorCard extends ConsumerWidget {
  const UiStyleSelectorCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(appUiStyleProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    void select(AppUiStyle next) {
      if (next == style) return;
      HapticFeedback.selectionClick();
      ref.read(appUiStyleProvider.notifier).setStyle(next);
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
                Icon(
                  Icons.layers_outlined,
                  size: 18,
                  color: Color(0xFF0078D4),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Interface Style (সারফেস লুক)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'কালার থিম আলাদা — এটা ঠিক করে সারফেসগুলো কীভাবে আঁকা হবে। পুরনো ফ্ল্যাট লুক চাইলে Classic, '
              'উইন্ডোজ ১১-এর মতো শান্ত টিন্ট চাইলে Mica, আর ঝলমলে ব্লার-গ্লাস চাইলে Acrylic।',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: isDark ? Colors.white60 : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 12),

            _StyleOption(
              icon: Icons.crop_square_rounded,
              accent: const Color(0xFF64748B),
              title: 'Classic (পুরনো লুক)',
              subtitle:
                  'ফ্ল্যাট ব্যাকগ্রাউন্ড, সলিড কার্ড, কোনো ব্লার বা অ্যানিমেশন নেই — সবচেয়ে হালকা ও ব্যাটারি-সাশ্রয়ী।',
              isSelected: style == AppUiStyle.classic,
              onTap: () => select(AppUiStyle.classic),
            ),
            const SizedBox(height: 8),
            _StyleOption(
              icon: Icons.gradient_rounded,
              accent: const Color(0xFF0078D4),
              title: 'Fluent Mica (উইন্ডোজ ১১ স্টাইল)',
              subtitle:
                  'পেছনে একটা স্থির, মৃদু অ্যাকসেন্ট টিন্ট; কার্ড সলিডই থাকে। নড়াচড়া নেই, তাই লেখা সবচেয়ে পরিষ্কার।',
              isSelected: style == AppUiStyle.mica,
              onTap: () => select(AppUiStyle.mica),
            ),
            const SizedBox(height: 8),
            _StyleOption(
              icon: Icons.blur_on_rounded,
              accent: const Color(0xFF8B5CF6),
              title: 'Fluent Acrylic (অ্যানিমেটেড গ্লাস)',
              subtitle:
                  'চলমান গ্রেডিয়েন্ট ব্যাকড্রপ, ভাসমান অর্ব ও ফ্রস্টেড স্বচ্ছ কার্ড — সবচেয়ে প্রিমিয়াম, তবে ভারী।',
              isSelected: style == AppUiStyle.acrylic,
              onTap: () => select(AppUiStyle.acrylic),
            ),
          ],
        ),
      ),
    );
  }
}

/// A Fluent-flavoured selectable row: the selected one carries a short
/// rounded accent bar on its leading edge, the way Windows 11 marks the
/// active item in a navigation list.
class _StyleOption extends StatelessWidget {
  const _StyleOption({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: isSelected
          ? accent.withValues(alpha: isDark ? 0.18 : 0.10)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? accent.withValues(alpha: 0.55)
                  : (isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
              width: isSelected ? 1.4 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Fluent selection bar
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 3.5,
                height: isSelected ? 30 : 0,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              SizedBox(width: isSelected ? 10 : 13.5),
              Icon(icon, size: 20, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.4,
                        color: isDark ? Colors.white60 : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 19,
                color: isSelected ? accent : Colors.grey,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
