import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/fluent_tokens.dart';
import '../../../../core/utils/bengali_math_sanitizer.dart';
import '../providers/mistake_pattern_provider.dart';

String _bn(int value) => BengaliMathSanitizer.toBengaliDigits('$value');

/// The two things this person keeps swapping.
///
/// Built from wrong answers the app already had: which option was picked,
/// which was right. A weak-topic list says "কারকে দুর্বল" and sends someone
/// to re-read a chapter; this says which two words are actually doing the
/// damage, which is an afternoon's work instead.
///
/// It shows nothing at all until a pair has recurred. One mix-up is a slip,
/// and the claim being made here is "you keep doing this".
class ConfusablePairsCard extends ConsumerWidget {
  const ConfusablePairsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final pairs = ref.watch(confusablePairsProvider).value ?? const [];
    if (pairs.isEmpty) return const SizedBox.shrink();

    final shown = pairs.take(5).toList();

    return Container(
      padding: const EdgeInsets.all(FluentSpacing.l),
      margin: const EdgeInsets.only(bottom: FluentSpacing.m),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(FluentRadius.card),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.swap_horiz, size: 18, color: scheme.primary),
              const SizedBox(width: FluentSpacing.s),
              Text('যে দুটো গুলিয়ে ফেলেন', style: FluentType.bodyStrong),
            ],
          ),
          const SizedBox(height: FluentSpacing.xs),
          Text(
            'ভুল উত্তরগুলো থেকে বের করা — টপিক নয়, ঠিক কোন দুটো।',
            style: FluentType.caption.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: FluentSpacing.m),
          ...shown.map(
            (pair) => Padding(
              padding: const EdgeInsets.only(bottom: FluentSpacing.s),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${pair.first}  ↔  ${pair.second}',
                          style: FluentType.body,
                        ),
                      ),
                      const SizedBox(width: FluentSpacing.s),
                      Text(
                        '${_bn(pair.times)} বার',
                        style: FluentType.caption.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  if (pair.topic.isNotEmpty)
                    Text(
                      pair.topic,
                      style: FluentType.caption.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
