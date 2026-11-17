import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/data/detail_segments.dart';
import '../../../../core/theme/fluent_tokens.dart';
import '../../../../core/utils/bengali_math_sanitizer.dart';

/// A written explanation, with its figures drawn.
///
/// Prose and drawings are interleaved in one text field, so this walks the
/// segments in order rather than putting all the pictures at the end.
class DetailBody extends StatelessWidget {
  final String detail;

  const DetailBody({super.key, required this.detail});

  @override
  Widget build(BuildContext context) {
    final segments = splitDetail(detail);
    if (segments.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final segment in segments)
          Padding(
            padding: const EdgeInsets.only(bottom: FluentSpacing.m),
            child: switch (segment) {
              ProseSegment(:final markdown) => MarkdownBody(
                // The same sanitiser the AI explanations use: a derivation
                // arrives full of LaTeX whatever the prompt asked for.
                data: BengaliMathSanitizer.sanitize(markdown),
                selectable: true,
                styleSheet: MarkdownStyleSheet.fromTheme(
                  Theme.of(context),
                ).copyWith(p: FluentType.body),
              ),
              FigureSegment(:final svg, :final caption) => _Figure(
                svg: svg,
                caption: caption,
              ),
            },
          ),
      ],
    );
  }
}

/// One drawing, on a page-coloured panel.
///
/// Always light, never themed. A figure arrives drawn in black on an assumed
/// white page — that is what every model produces and what every textbook
/// looks like — and recolouring arbitrary SVG to suit a dark theme is a
/// losing game: strokes, fills, text and markers would all need rules, and
/// getting one wrong makes a diagram silently misleading. A white panel is
/// honest and always legible.
class _Figure extends StatelessWidget {
  final String svg;
  final String caption;

  const _Figure({required this.svg, required this.caption});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(FluentSpacing.m),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(FluentRadius.card),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: ConstrainedBox(
            // A viewBox with no width scales to whatever it is given, so a
            // ceiling keeps one figure from filling the whole sheet.
            constraints: const BoxConstraints(maxHeight: 260),
            child: SvgPicture.string(
              svg,
              fit: BoxFit.contain,
              // Shown while it parses, and left in place if it never does —
              // better than an error box over half the explanation.
              placeholderBuilder: (_) => const SizedBox(height: 80),
            ),
          ),
        ),
        if (caption.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: FluentSpacing.xs),
            child: Text(
              caption,
              style: FluentType.caption.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}
