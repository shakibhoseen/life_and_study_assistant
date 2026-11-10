/// What another assistant is asked to send back, and how its verdicts are read.
///
/// The mistake notebook's copy button used to end with one vague line — please
/// check these and tell me if anything is wrong. ChatGPT answered it properly,
/// in prose, keyed on the [Q-…] numbers it had been shown, and almost all of
/// its findings were "this question is ambiguous" or "this needs a source"
/// rather than "the answer is খ". Pasted back into the fix sheet, that produced
/// nothing at all: the reader only understood a changed answer index, and the
/// numbers it looked for were positions in a list, not the printed ids.
///
/// So: the brief below asks for one exact shape keyed on the id that is
/// already printed beside every question, and the verdicts it allows are the
/// ones an honest audit actually reaches, including the ones that change no
/// answer. A reply that only flags is still worth something — it just must not
/// silently rewrite a key.
library;

/// What an audit can conclude about one question.
enum QuestionAuditStatus {
  /// Answer and explanation hold up. Nothing to do.
  verified,

  /// Something is definitely wrong — the key, an option, or the explanation.
  incorrect,

  /// More than one option is defensible, or the wording does not pin an
  /// answer down. The key is left alone and the question is marked.
  ambiguous,

  /// Cannot be settled without checking a real source. Left alone, marked.
  needsSource,

  /// The same question already appears elsewhere in the notebook.
  duplicate;

  static QuestionAuditStatus parse(String? raw) =>
      switch ((raw ?? '').trim().toLowerCase().replaceAll('-', '_')) {
        'incorrect' || 'wrong' => QuestionAuditStatus.incorrect,
        'ambiguous' || 'unclear' => QuestionAuditStatus.ambiguous,
        'needs_source' || 'needssource' || 'unverified' =>
          QuestionAuditStatus.needsSource,
        'duplicate' => QuestionAuditStatus.duplicate,
        _ => QuestionAuditStatus.verified,
      };

  String get wireName => switch (this) {
    QuestionAuditStatus.verified => 'verified',
    QuestionAuditStatus.incorrect => 'incorrect',
    QuestionAuditStatus.ambiguous => 'ambiguous',
    QuestionAuditStatus.needsSource => 'needs_source',
    QuestionAuditStatus.duplicate => 'duplicate',
  };

  /// Whether this verdict forbids moving the answer key.
  ///
  /// Doubt is recorded, never acted on: a reply that says "more than one
  /// option works" or "I would need the book" has not established an answer,
  /// even when it goes on to name one.
  ///
  /// [verified] does not block anything, because a reply that simply gives a
  /// corrected answer without naming a verdict is the ordinary case — most
  /// replies, and every one written before this vocabulary existed.
  bool get blocksAnswerChange => switch (this) {
    QuestionAuditStatus.ambiguous ||
    QuestionAuditStatus.needsSource ||
    QuestionAuditStatus.duplicate => true,
    QuestionAuditStatus.verified || QuestionAuditStatus.incorrect => false,
  };

  /// How the verdict reads on the question afterwards. Null for [verified],
  /// which earns no mark.
  String? get noteLabel => switch (this) {
    QuestionAuditStatus.verified => null,
    QuestionAuditStatus.incorrect => '⚠️ ভুল চিহ্নিত',
    QuestionAuditStatus.ambiguous => '⚠️ একাধিক উত্তর সম্ভব',
    QuestionAuditStatus.needsSource => '⚠️ উৎস যাচাই দরকার',
    QuestionAuditStatus.duplicate => '⚠️ একই প্রশ্ন আরেকবার আছে',
  };
}

/// The note a flagged question carries afterwards, appended to whatever
/// explanation it already had.
String auditNote(QuestionAuditStatus status, String reason) {
  final label = status.noteLabel;
  if (label == null) return '';
  final trimmed = reason.trim();
  return trimmed.isEmpty ? label : '$label: $trimmed';
}

/// The instruction block appended to the copied questions.
///
/// Written at the other assistant, not at this app's own model: it is read by
/// whatever the user pastes into, so it spells the shape out rather than
/// relying on a schema the way an API call can.
const String externalAuditBrief = '''
==============================
নির্দেশনা (এই অংশটুকুও কপি হয়েছে — মুছবেন না)

উপরের প্রতিটি প্রশ্ন, অপশন, চিহ্নিত উত্তর ও ব্যাখ্যা নিরপেক্ষভাবে যাচাই করুন।

উত্তর দেবেন **শুধু একটি JSON array** হিসেবে, আগে-পরে কোনো লেখা ছাড়া। যে প্রশ্নে কোনো সমস্যা নেই, সেটি তালিকায় রাখবেন না।

[
  {
    "question_id": 180,
    "status": "ambiguous",
    "proposed_correct_index": -1,
    "new_question_text": "",
    "new_options": [],
    "new_explanation": "",
    "is_delete": false,
    "reason": "খ ও গ অপশন দুটির অর্থ একই"
  }
]

নিয়ম:

- question_id = প্রশ্নের পাশে বর্গবন্ধনীতে লেখা সংখ্যাটি। "[Q-180]" হলে 180। সিরিয়াল নম্বর নয়।
- status যেকোনো একটি:
  - "incorrect" — উত্তর, অপশন বা ব্যাখ্যায় নিশ্চিত ভুল আছে।
  - "ambiguous" — একাধিক উত্তর গ্রহণযোগ্য, বা প্রশ্নের ভাষা উত্তর নির্দিষ্ট করে না।
  - "needs_source" — নির্ভরযোগ্য উৎস ছাড়া নিশ্চিত হওয়া যাচ্ছে না।
  - "duplicate" — একই প্রশ্ন তালিকায় আরেকবার আছে।
- proposed_correct_index শুধু status "incorrect" হলে এবং আপনি নিশ্চিত হলে দেবেন। ০ = ক, ১ = খ, ২ = গ, ৩ = ঘ। নিশ্চিত না হলে -1 দেবেন।
- "ambiguous", "needs_source" বা "duplicate" হলে উত্তর বদলানো হবে না — শুধু প্রশ্নটিতে একটি সতর্কতা লেখা থাকবে। তাই ওখানে proposed_correct_index সবসময় -1।
- প্রশ্নের ভাষা বা অপশন নিজেই ত্রুটিপূর্ণ হলে new_question_text বা new_options-এ পুরো সংশোধিত রূপটি দেবেন। ঠিক থাকলে ফাঁকা রাখবেন।
- ব্যাখ্যা ভুল হলে new_explanation-এ ঠিক ব্যাখ্যাটি দেবেন — উত্তর ঠিক থাকলেও।
- is_delete শুধু তখনই true, যখন প্রশ্নটি একেবারেই অচল।
- reason এক লাইনে বাংলায়, কেন এই সিদ্ধান্ত।
- অনুমান করে কিছু লিখবেন না। সন্দেহ হলে "needs_source" দেবেন।
- সব ঠিক থাকলে শুধু এটুকু দেবেন: []
''';
