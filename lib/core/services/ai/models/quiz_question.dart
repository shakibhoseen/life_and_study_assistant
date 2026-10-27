class QuizQuestion {
  final String questionText;
  final List<String> options;
  final int correctIndex;
  final String explanation;
  final String? subject;

  const QuizQuestion({
    required this.questionText,
    required this.options,
    required this.correctIndex,
    required this.explanation,
    this.subject,
  });

  factory QuizQuestion.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['options'];
    List<String> parsedOptions = [];
    if (rawOptions is List) {
      parsedOptions = rawOptions.map((e) => e.toString().trim()).toList();
    }

    return QuizQuestion(
      questionText: json['question']?.toString() ?? 'Sample Question',
      options: parsedOptions.length >= 4
          ? parsedOptions.take(4).toList()
          : ['Option A', 'Option B', 'Option C', 'Option D'],
      correctIndex: (json['correct_index'] as num?)?.toInt() ?? 0,
      explanation: json['explanation']?.toString() ?? '',
      subject: json['subject']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'question': questionText,
    'options': options,
    'correct_index': correctIndex,
    'explanation': explanation,
    'subject': subject,
  };
}
