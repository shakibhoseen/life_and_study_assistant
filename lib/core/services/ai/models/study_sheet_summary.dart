class MicroQuizItem {
  final String question;
  final String answer;

  MicroQuizItem({required this.question, required this.answer});

  factory MicroQuizItem.fromJson(Map<String, dynamic> json) {
    return MicroQuizItem(
      question: json['question'] as String? ?? '',
      answer: json['answer'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'question': question, 'answer': answer};
}

class StudySheetSummary {
  final String title;
  final List<String> highYieldPoints; // Exactly 5 concise bullet points
  final List<String> recurringPastQuestions;
  final List<String> mnemonics;
  final List<MicroQuizItem> quickCheck;

  StudySheetSummary({
    required this.title,
    required this.highYieldPoints,
    required this.recurringPastQuestions,
    required this.mnemonics,
    required this.quickCheck,
  });

  factory StudySheetSummary.fromJson(Map<String, dynamic> json) {
    return StudySheetSummary(
      title: json['title'] as String? ?? 'Study Sheet Summary',
      highYieldPoints:
          (json['highYieldPoints'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      recurringPastQuestions:
          (json['recurringPastQuestions'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      mnemonics:
          (json['mnemonics'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      quickCheck:
          (json['quickCheck'] as List<dynamic>?)
              ?.map((e) => MicroQuizItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'highYieldPoints': highYieldPoints,
    'recurringPastQuestions': recurringPastQuestions,
    'mnemonics': mnemonics,
    'quickCheck': quickCheck.map((q) => q.toJson()).toList(),
  };
}
