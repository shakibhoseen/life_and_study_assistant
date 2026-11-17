import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/data/topic_frequency.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../core/theme/fluent_tokens.dart';
import '../../../../core/utils/bengali_math_sanitizer.dart';

String _bn(int value) => BengaliMathSanitizer.toBengaliDigits('$value');

final topicFrequencyProvider = FutureProvider<List<TopicFrequency>>((
  ref,
) async {
  final db = ref.watch(appDatabaseProvider);
  return db.getTopicFrequency(limit: 6);
});

/// Which topics have actually been asked, and how often.
///
/// Every guide in the country uses the words "high-yield" and almost none of
/// them count anything. Once the source exam is kept with each scanned
/// question it is a count rather than a claim — and it is a count of the
/// user's own papers, which is better than somebody else's list.
///
/// Shows nothing until at least one question carries a source exam, because
/// a thin list here means a thin import rather than a short syllabus, and a
/// near-empty card would read as the opposite.
class TopicFrequencyCard extends ConsumerWidget {
  const TopicFrequencyCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final topics = ref.watch(topicFrequencyProvider).value ?? const [];
    if (topics.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(FluentSpacing.l),
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
              Icon(
                Icons.history_edu_outlined,
                size: 18,
                color: scheme.primary,
              ),
              const SizedBox(width: FluentSpacing.s),
              Text('পরীক্ষায় বারবার এসেছে', style: FluentType.bodyStrong),
            ],
          ),
          const SizedBox(height: FluentSpacing.xs),
          Text(
            'আপনার স্ক্যান করা প্রশ্নপত্র থেকে গোনা',
            style: FluentType.caption.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: FluentSpacing.m),
          ...topics.map(
            (t) => Padding(
              padding: const EdgeInsets.only(bottom: FluentSpacing.s),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.topic, style: FluentType.body),
                        Text(
                          t.exams.join(' · '),
                          style: FluentType.caption.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: FluentSpacing.s),
                  Text(
                    '${_bn(t.exams.length)}টি পরীক্ষায়',
                    style: FluentType.caption.copyWith(color: scheme.primary),
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
