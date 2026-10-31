/// Finds JSON inside text that is not only JSON.
///
/// A reply pasted from another assistant almost never arrives bare. It comes
/// wrapped in a sentence before, a fenced block, and an offer to help further
/// after. jsonDecode fails on all of that, and the app then paid a model to
/// re-read text that already held exactly what it needed.
library;

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
