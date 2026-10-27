import 'quiz_question.dart';

class StudySheetResult {
  final String title;
  final String subject;
  final String summary;
  final List<String> highYieldPoints;
  final List<String> keyRules;
  final List<QuizQuestion> questions;
  final String? rawReference;

  const StudySheetResult({
    required this.title,
    required this.subject,
    required this.summary,
    required this.highYieldPoints,
    required this.keyRules,
    required this.questions,
    this.rawReference,
  });

  factory StudySheetResult.fromJson(
    Map<String, dynamic> json, {
    String? rawRef,
  }) {
    final rawPoints = json['high_yield_points'];
    List<String> parsedPoints = [];
    if (rawPoints is List) {
      parsedPoints = rawPoints
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }

    final rawRules = json['key_rules'];
    List<String> parsedRules = [];
    if (rawRules is List) {
      parsedRules = rawRules
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }

    final rawQuestions = json['questions'];
    List<QuizQuestion> parsedQuestions = [];
    if (rawQuestions is List) {
      parsedQuestions = rawQuestions.map((q) {
        if (q is Map) {
          return QuizQuestion.fromJson(Map<String, dynamic>.from(q));
        }
        return const QuizQuestion(
          questionText: 'Sample Drill Question',
          options: ['Option A', 'Option B', 'Option C', 'Option D'],
          correctIndex: 0,
          explanation: '',
        );
      }).toList();
    }

    return StudySheetResult(
      title: json['title']?.toString() ?? 'Study Page Analysis',
      subject: json['subject']?.toString() ?? 'General BCS',
      summary: json['summary']?.toString() ?? 'Important examination concepts extracted from the uploaded study material.',
      highYieldPoints: parsedPoints,
      keyRules: parsedRules,
      questions: parsedQuestions,
      rawReference: rawRef,
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'subject': subject,
    'summary': summary,
    'high_yield_points': highYieldPoints,
    'key_rules': keyRules,
    'questions': questions.map((q) => q.toJson()).toList(),
    'raw_reference': rawReference,
  };
}
