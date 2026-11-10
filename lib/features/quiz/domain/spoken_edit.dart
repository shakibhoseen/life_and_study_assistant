/// Reading a correction said the way people actually say it.
///
/// The first version of this understood seven exact phrases. That is fine for
/// a written brief and useless for a person: nobody says "অপশন গ হবে:
/// তঞ্চঙ্গ্যা" twice the same way. They say "গ অপশনটা তঞ্চঙ্গ্যা হবে", or
/// "তিন নম্বরটা তঞ্চঙ্গ্যা", or they tap a chip and dictate only the words.
///
/// So nothing here is matched as a whole phrase. A line is read for what it is
/// *about* — the answer, one option, the question's own wording, the
/// explanation, a doubt, removal — and then for what it should become. Filler
/// around that is thrown away rather than insisted on.
///
/// Two things keep this honest. It writes nothing it was not given: when the
/// new wording is missing or too short to be wording, the line becomes a mark
/// on the question instead of a rewrite. And every edit it reads is shown in a
/// list for the user to tick before anything is saved, so a misread costs a
/// glance rather than a question.
library;

import 'external_audit_brief.dart';

/// What a spoken or typed line is asking for.
enum SpokenEditKind {
  /// Move the answer to another option.
  answer,

  /// Rewrite one option, leaving the others.
  option,

  /// Rewrite the question itself.
  questionText,

  /// Rewrite the explanation, leaving the answer.
  explanation,

  /// Mark the question; change nothing.
  doubt,

  /// Drop the question.
  delete,

  /// Nothing recognisable.
  none,
}

/// One line, read.
class SpokenEdit {
  const SpokenEdit(
    this.kind, {
    this.optionIndex,
    this.payload = '',
    this.status,
  });

  static const SpokenEdit none = SpokenEdit(SpokenEditKind.none);

  final SpokenEditKind kind;

  /// Which option, for [SpokenEditKind.answer] and [SpokenEditKind.option].
  final int? optionIndex;

  /// The new wording, for the rewriting kinds. Never invented: empty when the
  /// line did not carry any.
  final String payload;

  /// Which mark to leave, for [SpokenEditKind.doubt].
  final QuestionAuditStatus? status;
}

/// ক/খ/গ/ঘ, a/b/c/d, ১/2/3/4, or the words for them.
int? optionLetterIndex(String raw) {
  final c = raw.trim().toLowerCase();
  const byLetter = {
    'ক': 0, 'a': 0, '1': 0, '১': 0, 'এক': 0, 'প্রথম': 0,
    'খ': 1, 'b': 1, '2': 1, '২': 1, 'দুই': 1, 'দ্বিতীয়': 1,
    'গ': 2, 'c': 2, '3': 2, '৩': 2, 'তিন': 2, 'তৃতীয়': 2,
    'ঘ': 3, 'd': 3, '4': 3, '৪': 3, 'চার': 3, 'চতুর্থ': 3,
  };
  return byLetter[c];
}

/// A named option: a letter, a digit, or the word for one. The word forms
/// need separators around them, so "চারটি" and "একাধিক" are not options.
final _letterToken = RegExp(
  r'(?:^|[\s"\x27(])([কখগঘ]|[abcd]|[১২৩৪]|এক|দুই|তিন|চার|প্রথম|দ্বিতীয়|'
  r'তৃতীয়|চতুর্থ)(?:[)\s.।,:-]|$)',
  caseSensitive: false,
);

/// Words that carry no meaning of their own once the intent is known —
/// "অপশন গ **তে** তঞ্চঙ্গ্যা **বসাও**" is the same as "অপশন গ তঞ্চঙ্গ্যা".
final _leadingFiller = RegExp(
  r'^(?:হবে|হলো|হইবে|করো|করুন|কর|দাও|দিন|লিখো|লিখুন|লেখো|বসাও|বসান|এভাবে|'
  r'এমন|এরকম|নম্বর|নং|টা|টি|তে|এ|র|এর|should\s*be|will\s*be|is|be)'
  r'(?=\s|[:\-–—]|$)',
  caseSensitive: false,
);

/// Words that only ever mean "and here is what it should be", in any order.
final _becomes = RegExp(
  r'(হবে|হলো|হইবে|হবেন|করো|করুন|কর|দাও|দিন|লিখো|লিখুন|লেখো|বসাও|বসান|'
  r'ঠিক\s*করো|ঠিক\s*করুন|এভাবে|এমন|এরকম|should\s*be|will\s*be|is)',
  caseSensitive: false,
);

String _tidy(String raw) {
  var out = raw.trim();
  // A colon or dash is the most common way people separate the new wording,
  // and whatever comes after the last one is what they meant.
  final cut = out.lastIndexOf(RegExp(r'[:\-–—]'));
  if (cut >= 0 && cut < out.length - 1) out = out.substring(cut + 1);
  // Strip leading filler and separators until neither is left: people put
  // several in a row — "অপশন গ এর ঠিক হবে: …".
  for (var i = 0; i < 8; i++) {
    final before = out;
    out = out.replaceFirst(RegExp(r'^[\s:\-–—,।]+'), '');
    out = out.replaceFirst(_leadingFiller, '');
    out = out.trim();
    if (out == before) break;
  }
  out = out.replaceAll(RegExp(r'[\s,]+$'), '');
  // Trailing "হবে"/"করুন" left over from "… তঞ্চঙ্গ্যা হবে".
  // Trailing filler too: "… তঞ্চঙ্গ্যা হবে", "… তঞ্চঙ্গ্যা বসাও".
  for (var i = 0; i < 4; i++) {
    final before = out;
    out = out
        .replaceFirst(
          RegExp(
            r'\s*(হবে|হলো|হইবে|করো|করুন|কর|দাও|দিন|লিখো|লিখুন|লেখো|বসাও|'
            r'বসান)\s*[।.]?$',
          ),
          '',
        )
        .trim();
    if (out == before) break;
  }
  return out;
}

/// Reads one line. [line] has already had any "প্রশ্ন ৩ এর" target stripped
/// off the front by the caller, because which question is a separate question
/// from what to do to it.
SpokenEdit readSpokenEdit(String line) {
  final text = line.trim();
  if (text.isEmpty) return SpokenEdit.none;
  final lower = text.toLowerCase();

  // Removal first: it is unambiguous, and nothing it might also look like
  // matters once someone has said to drop the question.
  if (RegExp(
    r'(বাদ\s*দা|বাদ\s*দি|বাতিল|মুছ|ডিলিট|delete|remove|discard)',
    caseSensitive: false,
  ).hasMatch(lower)) {
    return const SpokenEdit(SpokenEditKind.delete);
  }

  final letter = _letterToken.firstMatch(text);
  final letterIndex = letter == null ? null : optionLetterIndex(letter.group(1)!);
  final hasBecomes = _becomes.hasMatch(lower);

  bool mentions(String word) => lower.contains(word);

  // "অপশন গ হবে তঞ্চঙ্গ্যা", "গ অপশনটা তঞ্চঙ্গ্যা", "অপশন গ-তে তঞ্চঙ্গ্যা বসাও".
  final doubt = spokenDoubt(lower);

  if (mentions('অপশন') || mentions('option')) {
    if (letterIndex != null && doubt == null) {
      final payload = _tidy(
        text
            .replaceFirst(RegExp(r'(অপশন(গুলো|টা|টি)?|option)', caseSensitive: false), ' ')
            .replaceFirst(letter!.group(0)!, ' '),
      );
      if (payload.isNotEmpty) {
        return SpokenEdit(
          SpokenEditKind.option,
          optionIndex: letterIndex,
          payload: payload,
        );
      }
    }
    // "অপশন গ ঠিক নয়" — an option named with nothing to put in it, or named
    // inside a complaint, is a complaint rather than a replacement.
    if (letterIndex != null || doubt != null) {
      return SpokenEdit(
        SpokenEditKind.doubt,
        status: doubt ?? QuestionAuditStatus.ambiguous,
      );
    }
  }

  if (mentions('ব্যাখ্যা') || mentions('explanation')) {
    final payload = _tidy(
      text.replaceFirst(
        RegExp(r'(ব্যাখ্যা(টা|টি)?|explanation)', caseSensitive: false),
        ' ',
      ),
    );
    if (payload.length >= 4 && doubt == null) {
      return SpokenEdit(SpokenEditKind.explanation, payload: payload);
    }
    return SpokenEdit(
      SpokenEditKind.doubt,
      status: doubt ?? QuestionAuditStatus.ambiguous,
    );
  }

  if (mentions('প্রশ্ন') || mentions('question')) {
    final payload = _tidy(
      text.replaceFirst(
        RegExp(r'(প্রশ্ন(টা|টি)?|question)', caseSensitive: false),
        ' ',
      ),
    );
    // Wording, not a word: "প্রশ্নটা ভুল" is a complaint with one word left
    // after the stripping, and a dictated question is at least a couple.
    if (hasBecomes && doubt == null && payload.split(RegExp(r'\s+')).length >= 2) {
      return SpokenEdit(SpokenEditKind.questionText, payload: payload);
    }
  }

  // "উত্তর গ", "গ হবে", or just "গ" — and also "এই প্রশ্নটা ঠিক নেই, গ হবে",
  // which raises a doubt and then settles it. A complaint that names the
  // answer is a correction; only one that names none is a mark.
  if (letterIndex != null &&
      (mentions('উত্তর') || mentions('সঠিক') || mentions('answer') ||
          hasBecomes ||
          text.trim().length <= 3)) {
    return SpokenEdit(SpokenEditKind.answer, optionIndex: letterIndex);
  }

  if (doubt != null) return SpokenEdit(SpokenEditKind.doubt, status: doubt);

  return SpokenEdit.none;
}

/// The chips shown above the box: tap one, then say only the words.
///
/// Speaking freely works, but a tag removes the guessing altogether, and it is
/// the difference between the app hoping it understood and knowing it did.
const List<(String, String)> spokenEditChips = [
  ('সঠিক উত্তর', 'উত্তর হবে '),
  ('অপশন ঠিক করুন', 'অপশন ক হবে: '),
  ('প্রশ্নের লেখা', 'প্রশ্ন হবে: '),
  ('ব্যাখ্যা', 'ব্যাখ্যা হবে: '),
  ('সন্দেহ আছে', 'এই প্রশ্নে ভুল আছে'),
  ('উৎস দেখতে হবে', 'বই দেখে নিতে হবে'),
];
