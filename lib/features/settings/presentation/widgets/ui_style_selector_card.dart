import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/fluent_tokens.dart';
import '../../../../core/theme/ui_style_provider.dart';

/// Lets the user pick how the app's surfaces are rendered, independently of
/// the colour theme: the original flat look, Windows 11 style Mica, or the
/// animated Acrylic treatment.
class UiStyleSelectorCard extends ConsumerWidget {
  const UiStyleSelectorCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(appUiStyleProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    void select(AppUiStyle next) {
      if (next == style) return;
      HapticFeedback.selectionClick();
      ref.read(appUiStyleProvider.notifier).setStyle(next);
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
                Icon(Icons.layers_outlined, size: 18, color: scheme.primary),
                const SizedBox(width: FluentSpacing.s),
                Expanded(
                  child: Text(
                    'Interface Style (সারফেস লুক)',
                    maxLines: 2,
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
              'কালার থিম আলাদা — এটা ঠিক করে সারফেসগুলো কীভাবে আঁকা হবে। পুরনো ফ্ল্যাট লুক চাইলে Classic, '
              'উইন্ডোজ ১১-এর মতো শান্ত টিন্ট চাইলে Mica, আর ঝলমলে ব্লার-গ্লাস চাইলে Acrylic।',
              style: FluentType.caption.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: FluentSpacing.m),

            _StyleOption(
              icon: Icons.crop_square_rounded,
              accent: scheme.primary,
              title: 'Classic (পুরনো লুক)',
              subtitle: 'ফ্ল্যাট ব্যাকগ্রাউন্ড, সলিড কার্ড, কোনো ব্লার বা অ্যানিমেশন নেই — সবচেয়ে হালকা ও ব্যাটারি-সাশ্রয়ী।',
              isSelected: style == AppUiStyle.classic,
              onTap: () => select(AppUiStyle.classic),
            ),
            const SizedBox(height: FluentSpacing.s),
            _StyleOption(
              icon: Icons.gradient_rounded,
              accent: scheme.primary,
              title: 'Fluent Mica (উইন্ডোজ ১১ স্টাইল)',
              subtitle: 'পেছনে একটা স্থির, মৃদু অ্যাকসেন্ট টিন্ট; কার্ড সলিডই থাকে। নড়াচড়া নেই, তাই লেখা সবচেয়ে পরিষ্কার।',
              isSelected: style == AppUiStyle.mica,
              onTap: () => select(AppUiStyle.mica),
            ),
            const SizedBox(height: FluentSpacing.s),
            _StyleOption(
              icon: Icons.blur_on_rounded,
              accent: scheme.primary,
              title: 'Fluent Acrylic (অ্যানিমেটেড গ্লাস)',
              subtitle: 'চলমান গ্রেডিয়েন্ট ব্যাকড্রপ, ভাসমান অর্ব ও ফ্রস্টেড স্বচ্ছ কার্ড — সবচেয়ে প্রিমিয়াম, তবে ভারী।',
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
    final scheme = theme.colorScheme;

    return Material(
      color: isSelected
          ? FluentLayer.subtle(accent, theme.brightness)
          : Colors.transparent,
      borderRadius: FluentRadius.controlBorder,
      child: InkWell(
        borderRadius: FluentRadius.controlBorder,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(FluentSpacing.m),
          decoration: BoxDecoration(
            borderRadius: FluentRadius.controlBorder,
            border: Border.all(
              color: isSelected
                  ? accent.withValues(alpha: 0.55)
                  : FluentStroke.card(theme.brightness),
              width: FluentStroke.width,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Fluent selection bar
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 3,
                height: isSelected ? 30 : 0,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
              SizedBox(width: isSelected ? FluentSpacing.s : FluentSpacing.m),
              Icon(icon, size: 20, color: accent),
              const SizedBox(width: FluentSpacing.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style:
                          (isSelected ? FluentType.bodyStrong : FluentType.body)
                              .copyWith(color: scheme.onSurface),
                    ),
                    const SizedBox(height: FluentSpacing.xxs),
                    Text(
                      subtitle,
                      style: FluentType.caption.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: FluentSpacing.s),
              Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 20,
                color: isSelected
                    ? accent
                    : scheme.onSurface.withValues(alpha: 0.38),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
