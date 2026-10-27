/// Decides which mentor replies are worth offering a check on.
///
/// Most of what the mentor says is not a factual answer: greetings, "ঠিক
/// আছে", a question back, encouragement. Putting a verify action on those
/// trains the user to ignore it, so the action only appears where there is
/// something a check could actually settle.
class ChatVerifiability {
  ChatVerifiability._();

  /// Below this a reply is an acknowledgement, not an answer.
  static const int minAnswerChars = 120;

  /// Words that mark a statement being asserted rather than asked.
  static const List<String> assertionMarkers = [
    'হলো',
    'হল ',
    'হয়',
    'ছিল',
    'অর্থাৎ',
    'মানে',
    'কারণ',
    'সূত্র',
    'অনুপাত',
    'শতকরা',
    'সাল',
    'সালে',
    'তারিখ',
    'নিয়ম',
    'সংজ্ঞা',
    ' is ',
    ' was ',
    ' are ',
    'means',
    'because',
    'ratio',
    'formula',
  ];

  static final _digit = RegExp(r'[0-9০-৯]');

  /// True when [answer] carries something checkable.
  ///
  /// [isStreaming] suppresses the action while the text is still arriving:
  /// half an answer would be checked as if it were the whole one.
  static bool canVerify(String answer, {bool isStreaming = false}) {
    if (isStreaming) return false;

    final text = answer.trim();
    if (text.length < minAnswerChars) return false;

    // A reply that is mostly a question back has nothing to verify.
    if (text.endsWith('?') && text.length < minAnswerChars * 2) return false;

    if (_digit.hasMatch(text)) return true;

    final lower = text.toLowerCase();
    for (final marker in assertionMarkers) {
      if (lower.contains(marker)) return true;
    }
    return false;
  }

  /// The exchange before this one, trimmed to what a verifier needs to read a
  /// follow-up ("আর বলো") correctly.
  static String buildPriorContext({
    String? earlierUser,
    String? earlierAnswer,
    int maxChars = 500,
  }) {
    final parts = <String>[];
    if ((earlierUser ?? '').trim().isNotEmpty) {
      parts.add('USER: ${earlierUser!.trim()}');
    }
    if ((earlierAnswer ?? '').trim().isNotEmpty) {
      parts.add('MENTOR: ${earlierAnswer!.trim()}');
    }
    if (parts.isEmpty) return '';

    final joined = parts.join('\n');
    return joined.length <= maxChars
        ? joined
        : joined.substring(joined.length - maxChars);
  }
}
