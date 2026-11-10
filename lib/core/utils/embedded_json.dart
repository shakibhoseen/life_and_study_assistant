/// Finds JSON inside text that is not only JSON.
///
/// A reply pasted from another assistant almost never arrives bare. It comes
/// wrapped in a sentence before, a fenced block, and an offer to help further
/// after. jsonDecode fails on all of that, and the app then paid a model to
/// re-read text that already held exactly what it needed.
library;

/// Undoes what copying out of a rendered chat window does to JSON.
///
/// A reply copied from ChatGPT's own Markdown view arrives with the block's
/// rendering baked in: every line ends in a backslash continuation, every
/// indent is an `&#x20;` entity, and brackets come escaped. It is still the
/// right answer — it simply will not decode, and the app then either paid a
/// model to re-read it or reported that nothing was found. Neither was true.
///
/// Only the wrapping is undone. Nothing inside the strings is touched beyond
/// the entities, so a Bengali explanation survives exactly as written.
String cleanPastedJson(String text) {
  var out = text;

  // Entities first: the indents are made of them.
  const entities = {
    '&#x20;': ' ',
    '&#32;': ' ',
    '&nbsp;': ' ',
    '&quot;': '"',
    '&#34;': '"',
    '&#39;': "'",
    '&apos;': "'",
    '&lt;': '<',
    '&gt;': '>',
  };
  entities.forEach((from, to) => out = out.replaceAll(from, to));
  // Ampersand last, or it would turn "&amp;#x20;" into a space.
  out = out.replaceAll('&amp;', '&');

  // A backslash at the end of a line is Markdown's hard line break, never
  // part of JSON.
  out = out.replaceAll(RegExp(r'\\+\s*\r?\n'), '\n');

  // Markdown escaping of characters that mean nothing inside JSON.
  out = out.replaceAll(RegExp(r'\\([\[\]_*#])'), r'$1');

  return out;
}

/// The first balanced JSON object or array in [text], or null.
///
/// Scans for a `{` or `[` and walks forward counting depth, so a brace inside
/// a string ("ক. {ক} নয়") does not end the span and an escaped quote does not
/// end the string.
String? extractFirstJson(String text) {
  for (var start = 0; start < text.length; start++) {
    final opener = text[start];
    if (opener != '{' && opener != '[') continue;
    final closer = opener == '{' ? '}' : ']';

    var depth = 0;
    var inString = false;
    var escaped = false;

    for (var i = start; i < text.length; i++) {
      final c = text[i];

      if (escaped) {
        escaped = false;
        continue;
      }
      if (inString) {
        if (c == r'\') {
          escaped = true;
        } else if (c == '"') {
          inString = false;
        }
        continue;
      }
      if (c == '"') {
        inString = true;
      } else if (c == opener) {
        depth++;
      } else if (c == closer) {
        depth--;
        if (depth == 0) return text.substring(start, i + 1);
      }
    }
    // Unbalanced from here; a later opener may still balance.
  }
  return null;
}
