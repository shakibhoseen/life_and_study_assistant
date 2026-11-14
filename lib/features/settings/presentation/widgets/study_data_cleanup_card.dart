import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/data/study_data_cleanup.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../core/theme/fluent_tokens.dart';

/// Tidies study data that has drifted apart, after showing what it will do.
///
/// Nothing runs on its own. A merge cannot be undone, and the rules cannot
/// tell a near-duplicate from two genuinely close topics with certainty, so
/// the counts go up first and the user decides.
class StudyDataCleanupCard extends ConsumerStatefulWidget {
  const StudyDataCleanupCard({super.key});

  @override
  ConsumerState<StudyDataCleanupCard> createState() =>
      _StudyDataCleanupCardState();
}

class _StudyDataCleanupCardState extends ConsumerState<StudyDataCleanupCard> {
  StudyCleanupSummary? _summary;
  bool _busy = false;
  String? _done;

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _done = null;
    });
    final summary = await ref.read(appDatabaseProvider).previewStudyCleanup();
    if (!mounted) return;
    setState(() {
      _summary = summary;
      _busy = false;
    });
  }

  Future<void> _apply() async {
    final summary = _summary;
    if (summary == null) return;
    setState(() => _busy = true);
    final changed = await ref
        .read(appDatabaseProvider)
        .applyStudyCleanup(summary);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _summary = null;
      _done = '$changed টি সারি ঠিক করা হলো';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final summary = _summary;

    // Green here is status: the cleanup finished, or there is nothing to do.
    const successColor = Color(0xFF10B981);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: FluentSpacing.s),
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
                Icon(
                  Icons.cleaning_services_rounded,
                  size: 18,
                  color: scheme.primary,
                ),
                const SizedBox(width: FluentSpacing.s),
                Expanded(
                  child: Text(
                    'ডেটা পরিষ্কার',
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
              'একই বিষয় দুই নামে জমা হলে বা দুর্বল টপিক দুবার লেখা হলে '
              'পরিসংখ্যান ভাগ হয়ে যায়। কী বদলাবে আগে দেখে নিন।',
              style: FluentType.caption.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: FluentSpacing.m),

            if (_done != null)
              Text(
                _done!,
                style: FluentType.caption.copyWith(
                  color: successColor,
                  fontWeight: FontWeight.w600,
                ),
              ),

            if (summary != null) ...[
              if (summary.isEmpty)
                Text(
                  'সব গোছানোই আছে — বদলানোর কিছু পাওয়া যায়নি।',
                  style: FluentType.caption.copyWith(color: successColor),
                )
              else ...[
                _line('একই টপিক দুবার', summary.plan.mergeInto.length),
                _line('পরীক্ষার নাম টপিক হিসেবে', summary.plan.drop.length),
                _line('বিষয়ের নাম ঠিক হবে', summary.plan.renameSubject.length),
                _line(
                  'প্রশ্নের বিষয় বদলাবে',
                  summary.questionSubjectsToRename,
                ),
                _line('কার্ডের বিষয় বদলাবে', summary.cardSubjectsToRename),
                const SizedBox(height: FluentSpacing.m),
                FilledButton.icon(
                  onPressed: _busy ? null : _apply,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: FluentRadius.controlBorder,
                    ),
                  ),
                  icon: const Icon(Icons.check, size: 16),
                  label: Text('পরিষ্কার করুন', style: FluentType.caption),
                ),
              ],
              const SizedBox(height: FluentSpacing.xs),
            ],

            if (summary == null)
              OutlinedButton.icon(
                onPressed: _busy ? null : _check,
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: FluentRadius.controlBorder,
                  ),
                ),
                icon: _busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search, size: 16),
                label: Text('কী বদলাবে দেখুন', style: FluentType.caption),
              ),
          ],
        ),
      ),
    );
  }

  Widget _line(String label, int count) {
    if (count == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: FluentSpacing.xxs),
      child: Text(
        '• $label: $count টি',
        style: FluentType.caption.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}
