import 'package:flutter/material.dart';

import '../../../../core/data/syllabus_coverage.dart';
import '../../../../core/theme/fluent_tokens.dart';

/// A two-segment progress bar: finished solid, being-read faint.
///
/// The segments are drawn in that order and the faint one is clamped to
/// what is left, so the two can never add up to more than the track — which
/// is the only way a bar can tell a lie the numbers beside it do not.
class CoverageBar extends StatelessWidget {
  final CoverageTally tally;
  final double height;

  const CoverageBar({super.key, required this.tally, this.height = 8});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final done = tally.doneFraction.clamp(0.0, 1.0);
    final reading = tally.readingFraction.clamp(0.0, 1.0 - done);

    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return Stack(
              children: [
                // Not surfaceContainerHighest: on the dark theme it sits
                // within a shade of the card it is drawn on, so an empty bar
                // vanished entirely and 0% looked like a rendering failure.
                // An alpha over onSurface keeps the track visible against
                // whatever surface it lands on, in either theme.
                Container(color: scheme.onSurface.withValues(alpha: 0.12)),
                Positioned(
                  left: width * done,
                  child: Container(
                    width: width * reading,
                    height: height,
                    color: scheme.primary.withValues(alpha: 0.3),
                  ),
                ),
                Container(width: width * done, color: scheme.primary),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// "৪৫% · ৯০/২০০ নম্বর" — the figure and what it is a figure of.
///
/// The marks are shown next to the percentage on purpose: a percentage on its
/// own invites being read as readiness, where "৯০ of ২০০ marks" says plainly
/// that this counts syllabus covered, not marks expected.
class CoverageCaption extends StatelessWidget {
  final CoverageTally tally;
  final String Function(int) toBengali;

  const CoverageCaption({
    super.key,
    required this.tally,
    required this.toBengali,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final parts = <String>[
      '${toBengali(tally.donePercent)}%',
      if (tally.marksTotal > 0)
        '${toBengali(tally.marksCovered.round())}/'
            '${toBengali(tally.marksTotal)} নম্বর',
      if (tally.readingTopics > 0)
        '${toBengali(tally.readingTopics)}টি পড়ছেন',
    ];

    return Text(
      parts.join(' · '),
      style: FluentType.caption.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}
