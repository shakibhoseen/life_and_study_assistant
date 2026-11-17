/// Splitting a written explanation into prose and figures.
///
/// A triangle, a cube, a circle with a chord — some rules cannot be read at
/// all without seeing the shape, and until now the detail field could only
/// hold words. Rather than a second column and a second paste, a figure
/// lives inside the same text as a fenced block:
///
/// ```text
/// ```svg চিত্র: সমকোণী ত্রিভুজ
/// `<svg viewBox="0 0 100 80">…</svg>`
/// ```
/// ```
///
/// Which means it survives being written by hand, pasted from elsewhere,
/// edited later, and stored in the column that already exists.
library;

/// A piece of a detail: either prose or a drawing.
sealed class DetailSegment {
  const DetailSegment();
}

class ProseSegment extends DetailSegment {
  final String markdown;
  const ProseSegment(this.markdown);
}

class FigureSegment extends DetailSegment {
  final String svg;

  /// What the fence said after `svg`, if anything.
  final String caption;

  const FigureSegment({required this.svg, this.caption = ''});
}

final _fence = RegExp(
  r'^[ \t]*```[ \t]*svg[ \t]*([^\n]*)\n(.*?)^[ \t]*```[ \t]*$',
  multiLine: true,
  dotAll: true,
);

/// Splits [detail] into prose and figures, in the order they appear.
///
/// A fence whose contents do not look like a drawing is left as prose, so a
/// mangled paste shows up as the code it is rather than as an error box or,
/// worse, as nothing at all.
List<DetailSegment> splitDetail(String detail) {
  if (detail.trim().isEmpty) return const [];

  final segments = <DetailSegment>[];
  var cursor = 0;

  void addProse(String text) {
    if (text.trim().isEmpty) return;
    segments.add(ProseSegment(text.trim()));
  }

  for (final match in _fence.allMatches(detail)) {
    final body = match.group(2) ?? '';
    if (!looksLikeSvg(body)) continue;

    addProse(detail.substring(cursor, match.start));
    segments.add(
      FigureSegment(svg: body.trim(), caption: (match.group(1) ?? '').trim()),
    );
    cursor = match.end;
  }

  addProse(detail.substring(cursor));
  return segments;
}

/// Whether a block is worth handing to the SVG renderer.
///
/// Deliberately shallow: it is a gate against prose, a half-pasted fragment
/// or something actively unwanted, not a validator. A structurally odd but
/// genuine drawing should still be tried — the renderer will do better with
/// it than this would.
bool looksLikeSvg(String body) {
  final text = body.trim();
  if (text.isEmpty) return false;

  final lower = text.toLowerCase();
  if (!lower.contains('<svg') || !lower.contains('</svg>')) return false;

  // Nothing that reaches outside the phone, and nothing executable. A figure
  // pasted from an agent should draw and do nothing else.
  if (lower.contains('<script')) return false;
  if (lower.contains('<foreignobject')) return false;
  if (RegExp(r'(href|src)\s*=\s*["' "'" r']?\s*(https?:|//)').hasMatch(lower)) {
    return false;
  }
  return true;
}
