import 'quiz_question.dart';

class QuestionBankExtractResult {
  final String title;
  final String subject;
  final List<QuizQuestion> questions;
  final String? rawReference;
  final bool hasSeparateAnswerKey;

  const QuestionBankExtractResult({
    required this.title,
    required this.subject,
    required this.questions,
    this.rawReference,
    this.hasSeparateAnswerKey = false,
  });

  factory QuestionBankExtractResult.fromJson(
    Map<String, dynamic> json, {
    String? rawRef,
    bool hasSeparateAnswerKey = false,
  }) {
    final rawQuestions = json['questions'];
    List<QuizQuestion> parsedQuestions = [];
    if (rawQuestions is List) {
      parsedQuestions = rawQuestions.map((q) {
        if (q is Map) {
          return QuizQuestion.fromJson(Map<String, dynamic>.from(q));
        }
        return const QuizQuestion(
          questionText: 'Question',
          options: ['A', 'B', 'C', 'D'],
          correctIndex: 0,
          explanation: '',
        );
      }).toList();
    }

    return QuestionBankExtractResult(
      title: json['title']?.toString().trim().isNotEmpty == true
          ? json['title'].toString().trim()
          : 'প্রশ্ন ব্যাংক এক্সাম',
      subject: json['subject']?.toString().trim().isNotEmpty == true
          ? json['subject'].toString().trim()
          : 'সাধারণ জ্ঞান',
      questions: parsedQuestions,
      rawReference: rawRef,
      hasSeparateAnswerKey: hasSeparateAnswerKey,
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'subject': subject,
    'questions': questions.map((q) => q.toJson()).toList(),
    'has_separate_answer_key': hasSeparateAnswerKey,
    if (rawReference != null) 'raw_reference': rawReference,
  };
}
