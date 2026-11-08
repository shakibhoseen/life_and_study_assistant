// Puts a real analysis note through the app's own correction call.
//
// Takes a quiz (as quiz_lab writes it) and a note written the way a person
// would paste one, and runs the prompt QuizBatchCorrectionService uses. The
// point is to find out what the note has to look like for the corrections to
// come out right — whether the shape the app hands out is needed at all, or
// whether plain Bengali does just as well.
//
//   GEMINI_API_KEY=$(tool/read_key_from_phone.sh) \
//     dart run tool/correction_lab.dart quiz.json note.txt
import 'dart:convert';
import 'dart:io';

import 'package:google_generative_ai/google_generative_ai.dart';

final _schema = Schema.array(
  items: Schema.object(
    properties: {
      'question_index': Schema.integer(description: '0-based index'),
      'proposed_correct_index': Schema.integer(nullable: true),
      'is_delete': Schema.boolean(),
      'new_question_text': Schema.string(),
      'new_options': Schema.array(items: Schema.string()),
      'new_explanation': Schema.string(),
      'reason': Schema.string(),
    },
    requiredProperties: [
      'question_index',
      'is_delete',
      'new_question_text',
      'new_options',
      'new_explanation',
      'reason',
    ],
  ),
);

Future<void> main(List<String> args) async {
  final key = Platform.environment['GEMINI_API_KEY'];
  if (key == null || key.isEmpty) {
    stderr.writeln('GEMINI_API_KEY is not set.');
    exit(2);
  }
  if (args.length < 2) {
    stderr.writeln(
      'Usage: dart run tool/correction_lab.dart quiz.json note.txt',
    );
    exit(2);
  }

  final quiz = (jsonDecode(File(args[0]).readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  final note = File(args[1]).readAsStringSync().trim();

  final list = StringBuffer();
  for (var i = 0; i < quiz.length; i++) {
    final q = quiz[i];
    final opts = (q['options'] as List)
        .asMap()
        .entries
        .map((e) => '${e.key}:${e.value}')
        .join(', ');
    list.writeln(
      '$i. "${q['question']}" | options: [$opts] | '
      'current_correct_index: ${q['correct_index']}',
    );
  }

  final prompt =
      '''
You are an expert competitive exam assistant in Bangladesh.
A student took a quiz and asked an external AI (like ChatGPT or Claude) for analysis.
The student has provided the external AI's analysis text below.

Quiz Questions List:
$list

External AI's Analysis Text:
"""
$note
"""

Task:
Extract any question corrections or recommendations mentioned in the external AI's text.
Match each correction to the corresponding question in the quiz list by question number (Bengali or English numeral) or question keywords.
For each correction, identify:
- question_index: integer, 0-based index into the Quiz Questions List above.
    * NUMBERING: the analysis almost always numbers questions from ১/1. The list above is 0-based, so its "প্রশ্ন ৯" is question_index 8. Match on the question text as well, and if you cannot tell which question is meant, leave it out entirely rather than guessing an index.
- proposed_correct_index: integer index into the option list, OR null if the question should be deleted or only its text changes.
- is_delete: boolean (true if the external AI recommended deleting/discarding/excluding this question because it is invalid, obsolete, or flawed).
- new_question_text: the corrected question text when the analysis says the QUESTION ITSELF is wrong, garbled or unreadable. Empty string when the question text is fine.
- new_options: the corrected full option list when the analysis says the OPTIONS are wrong, duplicated or do not contain the answer. Empty array when the options are fine.
    * Only rewrite when the analysis actually supplies or clearly implies the correct wording. Never invent a question or an option to fill a gap — recommend deletion instead.
- new_explanation: the corrected explanation when the analysis says the EXPLANATION is wrong, even if the answer itself is fine. A wrong explanation teaches the wrong thing, so it is worth fixing on its own. Empty string when the explanation is fine.
- reason: concise 1-sentence Bengali reason explaining why this question was corrected or discarded.

Return JSON array ONLY.
If the text says all answers are correct or no fixes are suggested, return: []
''';

  final model = GenerativeModel(
    model: 'gemini-flash-latest',
    apiKey: key,
    generationConfig: GenerationConfig(
      responseMimeType: 'application/json',
      responseSchema: _schema,
      temperature: 0.1,
      maxOutputTokens: 8192,
    ),
  );

  final response = await model.generateContent([Content.text(prompt)]);
  final usage = response.usageMetadata;
  stderr.writeln(
    'in=${usage?.promptTokenCount} out=${usage?.candidatesTokenCount} '
    'finish=${response.candidates.firstOrNull?.finishReason}',
  );
  stdout.writeln(response.text ?? '');
}
