// Round trip for the batch-correction feature.
//
// Plants known defects in a quiz, writes the kind of correction note an
// external AI produces, asks the real model to turn it into corrections, and
// saves both halves so the Flutter test can apply them to a real database.
// Split in two because `flutter test` blocks outbound HTTP, and the call has
// to be real for this to mean anything.
//
//   GEMINI_API_KEY=$(tool/read_key_from_phone.sh) dart run tool/correction_roundtrip.dart out.json
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

/// Six questions, five broken on purpose and one clean control.
const quiz = [
  {
    'question': 'বাংলাদেশের জাতীয় ফুল কোনটি?',
    'options': ['গোলাপ', 'শাপলা', 'জবা', 'বেলি'],
    'correct_index': 0, // wrong option marked correct
    'explanation': 'গোলাপই জাতীয় ফুল।',
  },
  {
    'question': 'বাংলাদেশের জাতীয় পাখি কোনটি?',
    'options': ['ময়ূর', 'কাক', 'চড়ুই', 'শালিক'],
    'correct_index': 0, // right answer absent from the options
    'explanation': 'জাতীয় পাখি দোয়েল।',
  },
  {
    'question': 'বাংলদেশর জতীয পশু কনটি কপবসয়?',
    'options': ['রয়েল বেঙ্গল টাইগার', 'হাতি', 'হরিণ', 'সিংহ'],
    'correct_index': 0, // garbled question text
    'explanation': 'রয়েল বেঙ্গল টাইগার।',
  },
  {
    'question': 'এক কিলোমিটারে কত মিটার?',
    'options': ['১০০', '১০০০', '১০০০০', '১০'],
    'correct_index': 1,
    'explanation': 'এক কিলোমিটার সমান ১০০ মিটার।', // explanation contradicts
  },
  {
    'question': 'একটি অনুপাত ১০:৬ এর লঘিষ্ঠ রূপ কোনটি?',
    'options': ['৫:৩', '১০:৬', '৩:২', '৪:৩'], // two options, one value
    'correct_index': 0,
    'explanation': 'গ.সা.গু ২ দিয়ে ভাগ করলে ৫:৩।',
  },
  {
    'question': 'বাংলাদেশের রাজধানীর নাম কী?',
    'options': ['ঢাকা', 'চট্টগ্রাম', 'খুলনা', 'রাজশাহী'],
    'correct_index': 0, // control
    'explanation': 'বাংলাদেশের রাজধানী ঢাকা।',
  },
];

const analysis = '''
প্রশ্ন ১: ভুল। বাংলাদেশের জাতীয় ফুল শাপলা, গোলাপ নয়। সঠিক উত্তর হবে খ. শাপলা।

প্রশ্ন ২: সঠিক উত্তর অপশনে নেই। বাংলাদেশের জাতীয় পাখি দোয়েল, কিন্তু অপশনে দোয়েল নেই।
সংশোধিত অপশন: ক. দোয়েল, খ. কাক, গ. চড়ুই, ঘ. শালিক
সঠিক উত্তর: ক. দোয়েল

প্রশ্ন ৩: প্রশ্নের বানান বিকৃত। প্রশ্নটি হওয়া উচিত "বাংলাদেশের জাতীয় পশু কোনটি?"
অপশন ও সঠিক উত্তর ঠিক আছে।

প্রশ্ন ৪: ব্যাখ্যা ভুল। এক কিলোমিটার সমান ১০০০ মিটার, ১০০ নয়। সঠিক উত্তর খ. ১০০০ ঠিকই আছে, শুধু ব্যাখ্যা সংশোধন করতে হবে।

প্রশ্ন ৫: অপশনে সমস্যা। ১০:৬ এবং ৫:৩ একই অনুপাত, তাই দুটি অপশন একই উত্তর বোঝাচ্ছে।
সংশোধিত অপশন: ক. ৫:৩, খ. ২:১, গ. ৩:২, ঘ. ৪:৩
সঠিক উত্তর: ক. ৫:৩

প্রশ্ন ৬: ঠিক আছে, কোনো পরিবর্তন লাগবে না।
''';

String _buildPrompt() {
  final list = StringBuffer();
  for (var i = 0; i < quiz.length; i++) {
    final q = quiz[i];
    final options = (q['options']! as List).cast<String>();
    final opts = [for (var k = 0; k < options.length; k++) '$k:${options[k]}']
        .join(', ');
    list.writeln(
      '$i. "${q['question']}" | options: [$opts] '
      '| current_correct_index: ${q['correct_index']}',
    );
  }

  return '''
You are an expert competitive exam assistant in Bangladesh.
A student took a quiz and asked an external AI for analysis.

Quiz Questions List:
$list

External AI's Analysis Text:
"""
$analysis
"""

Task:
Extract any question corrections mentioned in the external AI's text.
- question_index: integer, 0-based index into the Quiz Questions List above.
    * NUMBERING: the analysis numbers questions from ১/1. The list above is 0-based, so its "প্রশ্ন ৯" is question_index 8. Match on the question text as well, and if you cannot tell which question is meant, leave it out entirely rather than guessing an index.
- proposed_correct_index: integer index into the option list, OR null if the question should be deleted or only its text changes.
- is_delete: boolean, true only if the analysis says to discard the question.
- new_question_text: the corrected question text when the QUESTION ITSELF is wrong. Empty string otherwise.
- new_options: the corrected full option list when the OPTIONS are wrong, duplicated or do not contain the answer. Empty array otherwise.
    * Never invent a question or an option to fill a gap -- recommend deletion instead.
- new_explanation: the corrected explanation when the analysis says the EXPLANATION is wrong, even if the answer is fine. Empty string otherwise.
- reason: concise 1-sentence Bengali reason.

Return JSON array ONLY. If nothing needs fixing, return [].
''';
}

Future<void> main(List<String> args) async {
  final key = Platform.environment['GEMINI_API_KEY'];
  if (key == null || key.isEmpty) {
    stderr.writeln('GEMINI_API_KEY is not set.');
    exit(2);
  }
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/correction_roundtrip.dart <out.json>');
    exit(2);
  }

  final model = GenerativeModel(
    model: 'gemini-flash-latest',
    apiKey: key,
    generationConfig: GenerationConfig(
      responseMimeType: 'application/json',
      responseSchema: _schema,
      temperature: 0.1,
      maxOutputTokens: 4096,
    ),
  );

  final response = await model.generateContent([Content.text(_buildPrompt())]);
  final usage = response.usageMetadata;
  stderr.writeln(
    'in=${usage?.promptTokenCount} out=${usage?.candidatesTokenCount}',
  );

  final corrections = jsonDecode(response.text!) as List;
  File(args.first).writeAsStringSync(
    const JsonEncoder.withIndent('  ')
        .convert({'quiz': quiz, 'corrections': corrections}),
  );
  stderr.writeln('${corrections.length} corrections written to ${args.first}');
}
