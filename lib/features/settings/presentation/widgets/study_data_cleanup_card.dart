import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/data/study_data_cleanup.dart';
import '../../../../core/database/database_provider.dart';

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final summary = _summary;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cleaning_services_rounded, size: 18),
                const SizedBox(width: 8),
                const Text(
                  'ডেটা পরিষ্কার',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'একই বিষয় দুই নামে জমা হলে বা দুর্বল টপিক দুবার লেখা হলে '
              'পরিসংখ্যান ভাগ হয়ে যায়। কী বদলাবে আগে দেখে নিন।',
              style: TextStyle(
                fontSize: 11.5,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
            const SizedBox(height: 10),

            if (_done != null)
              Text(
                _done!,
                style: TextStyle(
                  fontSize: 12.5,
                  color: Colors.green.shade700,
                  fontWeight: FontWeight.bold,
                ),
              ),

            if (summary != null) ...[
              if (summary.isEmpty)
                Text(
                  'সব গোছানোই আছে — বদলানোর কিছু পাওয়া যায়নি।',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.green.shade700,
                  ),
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
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _busy ? null : _apply,
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text(
                    'পরিষ্কার করুন',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
              const SizedBox(height: 4),
            ],

            if (summary == null)
              OutlinedButton.icon(
                onPressed: _busy ? null : _check,
                icon: _busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search, size: 16),
                label: const Text(
                  'কী বদলাবে দেখুন',
                  style: TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _line(String label, int count) {
    if (count == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text('• $label: $count টি', style: const TextStyle(fontSize: 12)),
    );
  }
}
