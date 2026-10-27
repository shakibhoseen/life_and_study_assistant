import 'quiz_question.dart';

class VoiceMistakeResult {
  final String questionText;
  final List<String> options;
  final int correctIndex;
  final String explanation;
  final String subject;
  final String topic;
  final String keyRule;
  final String? spokenSummary;

  const VoiceMistakeResult({
    required this.questionText,
    required this.options,
    required this.correctIndex,
    required this.explanation,
    required this.subject,
    required this.topic,
    required this.keyRule,
    this.spokenSummary,
  });

  factory VoiceMistakeResult.fromJson(
    Map<String, dynamic> json, {
    String? spokenRef,
  }) {
    final rawOptions = json['options'];
    List<String> parsedOptions = [];
    if (rawOptions is List) {
      parsedOptions = rawOptions.map((e) => e.toString().trim()).toList();
    }

    if (parsedOptions.length < 4) {
      parsedOptions = ['অপশন ক', 'অপশন খ', 'অপশন গ', 'অপশন ঘ'];
    }

    return VoiceMistakeResult(
      questionText: json['question']?.toString() ?? 'Recorded Mistake Question',
      options: parsedOptions.take(4).toList(),
      correctIndex: (json['correct_index'] as num?)?.toInt().clamp(0, 3) ?? 0,
      explanation: json['explanation']?.toString() ?? '',
      subject: json['subject']?.toString() ?? 'General BCS',
      topic: json['topic']?.toString() ?? 'LiveMCQ Review',
      keyRule:
          json['key_rule']?.toString() ??
          (json['explanation']?.toString() ?? ''),
      spokenSummary: spokenRef,
    );
  }

  QuizQuestion toQuizQuestion() {
    return QuizQuestion(
      questionText: questionText,
      options: options,
      correctIndex: correctIndex,
      explanation: explanation,
      subject: subject,
    );
  }

  Map<String, dynamic> toJson() => {
    'question': questionText,
    'options': options,
    'correct_index': correctIndex,
    'explanation': explanation,
    'subject': subject,
    'topic': topic,
    'key_rule': keyRule,
    'spoken_summary': spokenSummary,
  };
}
