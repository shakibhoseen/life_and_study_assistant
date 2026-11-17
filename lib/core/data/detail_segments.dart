/// Splitting a written explanation into prose and figures.
///
/// A triangle, a cube, a circle with a chord — some rules cannot be read at
/// all without seeing the shape, and until now the detail field could only
/// hold words. Rather than a second column and a second paste, a figure
/// lives inside the same text — either fenced, or written straight in:
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

/// A fenced block, or a drawing written straight into the text.
///
/// Both, because an agent asked for a fenced block will often just write
/// the `<svg>` — which is what happened the first time this was used, and
/// the figure came out as a wall of code. Relying on a model to wrap its
/// answer correctly is relying on the one thing it is least careful about.
///
/// The fenced form is listed first, so a fence containing a drawing is
/// consumed whole rather than matched twice.
final _figure = RegExp(
  r'^[ \t]*```[ \t]*svg[ \t]*([^\n]*)\n(.*?)^[ \t]*```[ \t]*$'
  r'|'
  r'(<svg[\s>][\s\S]*?</svg\s*>)',
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

  for (final match in _figure.allMatches(detail)) {
    // Group 2 is a fenced body, group 3 a drawing written straight in.
    final fenced = match.group(2);
    final body = fenced ?? match.group(3) ?? '';
    if (!looksLikeSvg(body)) continue;

    addProse(detail.substring(cursor, match.start));
    segments.add(
      FigureSegment(
        svg: body.trim(),
        // Only a fence can carry a caption. A bare drawing usually has a
        // heading above it already, which stays where it is as prose.
        caption: fenced == null ? '' : (match.group(1) ?? '').trim(),
      ),
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
