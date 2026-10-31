import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/services/ai/models/quiz_question.dart';
import 'package:life_and_study_assistant/core/services/ai/quiz_batch_correction_service.dart';

void main() {
  const questions = [
    QuizQuestion(
      questionText: 'বাংলাদেশের সংবিধান কার্যকর হয় কবে?',
      options: [
        'ক. ১৬ ডিসেম্বর ১৯৭২',
        'খ. ৪ নভেম্বর ১৯৭২',
        'গ. ২৬ মার্চ ১৯৭১',
        'ঘ. ১০ এপ্রিল ১৯৭১',
      ],
      correctIndex: 1,
      explanation: '',
      subject: 'বাংলাদেশ বিষয়াবলী',
    ),
    QuizQuestion(
      questionText: '"সূর্য" শব্দের সমার্থক কোনটি?',
      options: ['ক. সুধাকর', 'খ. তপন', 'গ. শশাঙ্ক', 'ঘ. বিধু'],
      correctIndex: 0,
      explanation: '',
      subject: 'বাংলা',
    ),
  ];

  test('a correction pasted as JSON inside a reply costs nothing', () async {
    const pasted = '''
যাচাই করে দেখলাম, একটা উত্তর ভুল আছে:

```json
[
  {
    "question_index": 1,
    "proposed_correct_index": 1,
    "is_delete": false,
    "reason": "তপন সূর্যের সমার্থক; সুধাকর চাঁদের।"
  }
]
```

বাকিগুলো ঠিক আছে।
''';

    final items = await QuizBatchCorrectionService.instance.parseCorrections(
      questions: questions,
      externalAnalysis: pasted,
    );

    expect(items.length, 1);
    expect(items.first.questionIndex, 1);
    expect(items.first.proposedCorrectIndex, 1);
    expect(QuizBatchCorrectionService.instance.lastParseWasFree, isTrue);
  });

  test(
    'a correction aimed at a question that does not exist is dropped',
    () async {
      const pasted = '[{"question_index": 9, "proposed_correct_index": 0}]';

      final items = await QuizBatchCorrectionService.instance.parseCorrections(
        questions: questions,
        externalAnalysis: pasted,
      );

      expect(items, isEmpty);
    },
  );
}
