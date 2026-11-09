/// Where a question's correct answer came from.
///
/// Worth keeping apart: an answer read off the printed key is evidence, one
/// the model worked out is an opinion, and one it guessed is neither.
enum AnswerSource {
  answerKey,
  solved,
  guess;

  static AnswerSource parse(String? raw) =>
      switch ((raw ?? '').trim().toLowerCase()) {
        'answer_key' => AnswerSource.answerKey,
        'solved' => AnswerSource.solved,
        _ => AnswerSource.guess,
      };

  String get storageKey => switch (this) {
    AnswerSource.answerKey => 'answer_key',
    AnswerSource.solved => 'solved',
    AnswerSource.guess => 'guess',
  };

  String get label => switch (this) {
    AnswerSource.answerKey => 'উত্তরপত্র থেকে',
    AnswerSource.solved => 'AI সমাধান করেছে',
    AnswerSource.guess => 'অনিশ্চিত',
  };

  /// Whether this answer is safe to keep without someone checking it.
  bool get isDependable => this == AnswerSource.answerKey;
}

class QuizQuestion {
  final String questionText;
  final List<String> options;
  final int correctIndex;
  final String explanation;
  final String? subject;

  /// False when the printed text could not actually be read.
  ///
  /// A scan that admits it could not read a line is useful; one that quietly
  /// invents a readable-looking question is not, because nothing downstream
  /// can tell the difference.
  final bool legible;

  final AnswerSource answerSource;

  /// The answer letter as it is printed on the page, before anything is made
  /// of it — "ক", "খ", "B", and so on.
  ///
  /// Kept beside [correctIndex] rather than only resolved into it, because in
  /// Bengali print খ, ঘ and ব are easily taken for one another, and a reader
  /// who can see what the model thought it read can fix a misread in one tap.
  /// Null when the page marked no answer.
  final String? printedAnswerLetter;

  /// The heading this question sits under on the page, when there is one.
  ///
  /// A single page often carries the tail of one model test and the start of
  /// the next, separated by a banner like "ব্যাংক নিয়োগ পরীক্ষা" and by the
  /// numbering going back to ১. Without this they all arrive as one flat set
  /// and the two tests cannot be told apart again.
  final String? sectionTitle;

  /// The exam the book credits this question to, as printed — for example
  /// "BB Officer (Cash): 16". These books tag nearly every question.
  final String? sourceExam;

  /// The question number exactly as printed, which is how a restart at ১
  /// partway down a page becomes visible.
  final String? printedNumber;

  /// What a second read of the page made of the same answer letter.
  ///
  /// Measured on one page: two reads of it disagreed on six answers out of
  /// eighteen, and both reads claimed to have read them straight off the
  /// page. A model that misreads খ as ঘ does not know it has, so nothing it
  /// reports can catch this — only reading twice and comparing can. Null when
  /// the page was read once, or when the second read found no match for this
  /// question.
  final String? secondReadLetter;

  const QuizQuestion({
    required this.questionText,
    required this.options,
    required this.correctIndex,
    required this.explanation,
    this.subject,
    this.legible = true,
    this.answerSource = AnswerSource.solved,
    this.printedAnswerLetter,
    this.sectionTitle,
    this.sourceExam,
    this.printedNumber,
    this.secondReadLetter,
  });

  /// True where this row should not be saved without being looked at.
  bool get needsReview =>
      !legible || answerSource == AnswerSource.guess || correctIndex < 0;

  /// True when a valid option index is marked as the correct answer.
  bool get hasAnswer => correctIndex >= 0 && correctIndex < options.length;

  /// Whether [selected] is the right answer to this question.
  ///
  /// False when there is no answer to be right about, and false for a question
  /// nobody answered. Comparing the two indices directly — which is what every
  /// caller used to do — made a skipped question with no answer key come out
  /// correct, because -1 equals -1. That was harmless only for as long as a
  /// missing answer could not reach the database; it can now, so the rule
  /// lives here rather than in each caller.
  bool isCorrectChoice(int selected) => hasAnswer && selected == correctIndex;

  factory QuizQuestion.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['options'];
    List<String> parsedOptions = [];
    if (rawOptions is List) {
      parsedOptions = rawOptions
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    // Padding a short list with "Option A"/"Option B" used to hide a failed
    // read behind four plausible-looking choices. Keep what was actually
    // there and let the row say it needs looking at.
    final shortOfOptions = parsedOptions.length < 4;
    final options = parsedOptions.length > 4
        ? parsedOptions.take(4).toList()
        : parsedOptions;

    final rawIndex = (json['correct_index'] as num?)?.toInt() ?? -1;
    final indexInRange = rawIndex >= 0 && rawIndex < options.length;

    return QuizQuestion(
      questionText: json['question']?.toString().trim() ?? '',
      options: options,
      // Out of range means no answer, not option ক. It used to fall back to 0,
      // so a page the model could not read an answer off came back marked
      // with the first option — a wrong answer presented as an answer, which
      // is the one outcome worth more than any amount of missing data.
      correctIndex: indexInRange ? rawIndex : -1,
      explanation: json['explanation']?.toString() ?? '',
      subject: json['subject']?.toString(),
      // Legibility is about the printed text, which is why a missing answer
      // no longer counts against it: that is said by [correctIndex] being -1
      // and by [answerSource], and conflating the two hid which was wrong.
      legible:
          json['legible'] != false &&
          !shortOfOptions &&
          (json['question']?.toString().trim().isNotEmpty ?? false),
      answerSource: AnswerSource.parse(json['answer_source']?.toString()),
      printedAnswerLetter: _trimToNull(json['printed_answer_letter']),
      sectionTitle: _trimToNull(json['section_title']),
      sourceExam: _trimToNull(json['source_exam']),
      printedNumber: _trimToNull(json['printed_number']),
      secondReadLetter: _trimToNull(json['second_read_letter']),
    );
  }

  Map<String, dynamic> toJson() => {
    'question': questionText,
    'options': options,
    'correct_index': correctIndex,
    'explanation': explanation,
    'subject': subject,
    'legible': legible,
    'answer_source': answerSource.storageKey,
    'printed_answer_letter': printedAnswerLetter,
    'section_title': sectionTitle,
    'source_exam': sourceExam,
    'printed_number': printedNumber,
    'second_read_letter': secondReadLetter,
  };

  /// An absent, blank or whitespace-only field reads the same as nothing here,
  /// and nothing is easier to check for than three kinds of empty.
  static String? _trimToNull(Object? raw) {
    final text = raw?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  QuizQuestion copyWith({
    String? questionText,
    List<String>? options,
    int? correctIndex,
    String? explanation,
    String? subject,
    bool? legible,
    AnswerSource? answerSource,
    String? printedAnswerLetter,
    String? sectionTitle,
    String? sourceExam,
    String? printedNumber,
    String? secondReadLetter,
  }) {
    return QuizQuestion(
      questionText: questionText ?? this.questionText,
      options: options ?? this.options,
      correctIndex: correctIndex ?? this.correctIndex,
      explanation: explanation ?? this.explanation,
      subject: subject ?? this.subject,
      legible: legible ?? this.legible,
      answerSource: answerSource ?? this.answerSource,
      printedAnswerLetter: printedAnswerLetter ?? this.printedAnswerLetter,
      sectionTitle: sectionTitle ?? this.sectionTitle,
      sourceExam: sourceExam ?? this.sourceExam,
      printedNumber: printedNumber ?? this.printedNumber,
      secondReadLetter: secondReadLetter ?? this.secondReadLetter,
    );
  }
}
