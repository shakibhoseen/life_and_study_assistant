import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/data/mistake_kind.dart';
import '../../../../core/theme/fluent_tokens.dart';
import '../../../../core/utils/bengali_math_sanitizer.dart';
import '../providers/mistake_pattern_provider.dart';

String _bn(int value) => BengaliMathSanitizer.toBengaliDigits('$value');

/// What kind of wrong this person goes.
///
/// Every other view in the app answers "where am I weak". This one answers
/// "what do I keep doing", which is a different question with a different
/// remedy: a topic you never learnt and a topic you keep mis-subtracting in
/// look identical in a weak-topic list and need opposite things done about
/// them.
///
/// It is deliberately quiet when it does not know. With four tags any kind
/// looks like half a person, so below a floor it shows the counts and says
/// plainly that it is too early — rather than naming a habit someone might
/// believe.
class MistakePatternCard extends ConsumerWidget {
  const MistakePatternCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(mistakePatternProvider);
    final pattern = async.value;

    if (pattern == null) return const SizedBox.shrink();
    if (pattern.tagged == 0 && pattern.untagged == 0) {
      return const SizedBox.shrink();
    }

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
              Icon(Icons.psychology_outlined, size: 18, color: scheme.primary),
              const SizedBox(width: FluentSpacing.s),
              Text('ভুলের ধরন', style: FluentType.bodyStrong),
            ],
          ),
          const SizedBox(height: FluentSpacing.xs),
          Text(
            pattern.tagged == 0
                ? 'একটা ভুলেও কারণ দেওয়া হয়নি। নিচের যেকোনো প্রশ্নে এক ট্যাপেই দেওয়া যায়।'
                : pattern.isThin
                ? 'এখনো ${_bn(pattern.tagged)}টি ভুলে কারণ দেওয়া — ধরন বলার মতো যথেষ্ট নয়।'
                : _headline(pattern),
            style: FluentType.caption.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (pattern.tagged > 0) ...[
            const SizedBox(height: FluentSpacing.m),
            ...pattern.byKind.map((entry) => _bar(context, pattern, entry)),
            if (!pattern.isThin && pattern.dominant != null) ...[
              const SizedBox(height: FluentSpacing.s),
              Text(
                pattern.dominant!.remedy,
                style: FluentType.caption.copyWith(color: scheme.primary),
              ),
            ],
          ],
          if (pattern.untagged > 0) ...[
            const SizedBox(height: FluentSpacing.s),
            Text(
              '${_bn(pattern.untagged)}টি ভুলে এখনো কারণ দেওয়া হয়নি',
              style: FluentType.caption.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _headline(MistakePattern pattern) {
    final kind = pattern.dominant!;
    final percent = (pattern.dominantShare * 100).round();
    final worst = pattern.worstTopicByKind[kind];
    final where = worst == null ? '' : ' — সবচেয়ে বেশি ${worst.key}-তে';
    return 'আপনার ${_bn(percent)}% ভুল: ${kind.label}$where।';
  }

  Widget _bar(
    BuildContext context,
    MistakePattern pattern,
    MapEntry<MistakeKind, int> entry,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final share = pattern.tagged == 0 ? 0.0 : entry.value / pattern.tagged;

    return Padding(
      padding: const EdgeInsets.only(bottom: FluentSpacing.s),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              entry.key.label,
              style: FluentType.caption,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: share,
                minHeight: 6,
                // The same track colour the coverage bar settled on: a
                // surface tint vanishes against the card in dark mode.
                backgroundColor: scheme.onSurface.withValues(alpha: 0.12),
              ),
            ),
          ),
          const SizedBox(width: FluentSpacing.s),
          Text(_bn(entry.value), style: FluentType.caption),
        ],
      ),
    );
  }
}
