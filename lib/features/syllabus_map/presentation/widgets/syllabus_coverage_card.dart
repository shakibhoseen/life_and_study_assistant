import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/data/syllabus_coverage.dart';
import '../../../../core/theme/fluent_tokens.dart';
import '../../../../core/utils/bengali_math_sanitizer.dart';
import '../providers/syllabus_map_provider.dart';
import '../screens/syllabus_map_screen.dart';
import 'coverage_bar.dart';

String _bn(int value) => BengaliMathSanitizer.toBengaliDigits('$value');

/// The dashboard's answer to "কতটা বাকি".
///
/// Shows one track — the one the user last looked at, else the first — with
/// the subject that has the most marks still uncovered, because that is the
/// single most useful sentence the map can produce in four lines.
class SyllabusCoverageCard extends ConsumerWidget {
  const SyllabusCoverageCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(syllabusTracksProvider);
    final rows = tracks.value;
    if (rows == null || rows.isEmpty) return const SizedBox.shrink();

    // The track the user last opened, falling back to the first — and back
    // to the first again if the one they chose has since been deleted.
    final chosen = ref.watch(selectedSyllabusTrackProvider);
    final trackKey = rows.any((t) => t.trackKey == chosen)
        ? chosen!
        : rows.first.trackKey;
    final map = ref.watch(syllabusMapProvider(trackKey));
    final state = map.value;
    if (state == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final tally = state.tally;
    final ordered = subjectsByUncoveredMarks(state.subjects);
    final weakest = ordered.isEmpty ? null : ordered.first;

    return InkWell(
      borderRadius: BorderRadius.circular(FluentRadius.card),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const SyllabusMapScreen()),
      ),
      child: Container(
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
                Icon(Icons.map_outlined, size: 18, color: scheme.primary),
                const SizedBox(width: FluentSpacing.s),
                Expanded(
                  child: Text(state.trackName, style: FluentType.bodyStrong),
                ),
                if (state.proposals.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FluentSpacing.s,
                      vertical: FluentSpacing.xxs,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(FluentRadius.control),
                    ),
                    child: Text(
                      '${_bn(state.proposals.length)}টি প্রশ্ন',
                      style: FluentType.caption.copyWith(
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                const SizedBox(width: FluentSpacing.xs),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
            const SizedBox(height: FluentSpacing.m),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${_bn(tally.donePercent)}%',
                  style: FluentType.title.copyWith(color: scheme.primary),
                ),
                const SizedBox(width: FluentSpacing.s),
                Padding(
                  padding: const EdgeInsets.only(bottom: FluentSpacing.xs),
                  child: CoverageCaption(tally: tally, toBengali: _bn),
                ),
              ],
            ),
            const SizedBox(height: FluentSpacing.s),
            CoverageBar(tally: tally),
            if (weakest != null) ...[
              const SizedBox(height: FluentSpacing.m),
              Text(
                'সবচেয়ে বেশি বাকি: ${weakest.name} '
                '(${_bn((weakest.marks * (1 - tallySubject(weakest).doneFraction)).round())} নম্বর)',
                style: FluentType.caption.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
