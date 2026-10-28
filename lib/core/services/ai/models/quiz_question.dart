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

  const QuizQuestion({
    required this.questionText,
    required this.options,
    required this.correctIndex,
    required this.explanation,
    this.subject,
    this.legible = true,
    this.answerSource = AnswerSource.solved,
  });

  /// True where this row should not be saved without being looked at.
  bool get needsReview => !legible || answerSource == AnswerSource.guess;

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

    final rawIndex = (json['correct_index'] as num?)?.toInt() ?? 0;
    final indexInRange = rawIndex >= 0 && rawIndex < options.length;

    return QuizQuestion(
      questionText: json['question']?.toString().trim() ?? '',
      options: options,
      correctIndex: indexInRange ? rawIndex : 0,
      explanation: json['explanation']?.toString() ?? '',
      subject: json['subject']?.toString(),
      legible:
          json['legible'] != false &&
          !shortOfOptions &&
          indexInRange &&
          (json['question']?.toString().trim().isNotEmpty ?? false),
      answerSource: AnswerSource.parse(json['answer_source']?.toString()),
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
  };

  QuizQuestion copyWith({
    String? questionText,
    List<String>? options,
    int? correctIndex,
    String? explanation,
    String? subject,
    bool? legible,
    AnswerSource? answerSource,
  }) {
    return QuizQuestion(
      questionText: questionText ?? this.questionText,
      options: options ?? this.options,
      correctIndex: correctIndex ?? this.correctIndex,
      explanation: explanation ?? this.explanation,
      subject: subject ?? this.subject,
      legible: legible ?? this.legible,
      answerSource: answerSource ?? this.answerSource,
    );
  }
}
