// Runs the app's own quiz generation from a desktop shell.
//
// Model list, temperature, token cap and wording are copied from
// QuizGeneratorService.generateQuiz, so what comes back here is what the app
// would get. See tool/flashcard_lab.dart for why this exists.
//
//   GEMINI_API_KEY=$(tool/read_key_from_phone.sh) \
//     dart run tool/quiz_lab.dart "<subject>" "<topic>" [count]
import 'dart:convert';
import 'dart:io';

import 'package:google_generative_ai/google_generative_ai.dart';

Future<void> main(List<String> args) async {
  final key = Platform.environment['GEMINI_API_KEY'];
  if (key == null || key.isEmpty) {
    stderr.writeln('GEMINI_API_KEY is not set.');
    exit(2);
  }
  if (args.length < 2) {
    stderr.writeln('Usage: dart run tool/quiz_lab.dart <subject> <topic> [n]');
    exit(2);
  }

  final subject = args[0];
  final topic = args[1];
  final count = args.length > 2 ? int.parse(args[2]) : 5;
  final cap = int.parse(Platform.environment['QUIZ_MAX_TOKENS'] ?? '2048');
  final modelName =
      Platform.environment['QUIZ_MODEL'] ?? 'gemini-flash-lite-latest';

  final prompt =
      '''
You are an expert BCS Preliminary Exam and LiveMCQ question setter.
Generate exactly $count high-yield, authentic Multiple Choice Questions (MCQs) in Bengali for:
- Subject: $subject
- Topic: $topic

Formatting Rules:
1. Each question must have exactly 4 plausible options.
2. Indicate the zero-based index of the correct option (0, 1, 2, or 3).
3. Provide a clear, educational 1-2 sentence explanation in Bengali.
4. Clean Unicode: Never use raw LaTeX syntax. Use native Unicode: '°', '→', '×', '²', '³', '√'.
5. Return ONLY a valid JSON array of objects. Do not include markdown code fences or text outside JSON.

JSON Structure:
[
  {
    "question": "নিচের কোনটি ...?",
    "options": ["ক. অপশন ১", "খ. অপশন ২", "গ. অপশন ৩", "ঘ. অপশন ৪"],
    "correct_index": 1,
    "explanation": "সঠিক উত্তর খ কারণ..."
  }
]
''';

  final model = GenerativeModel(
    model: modelName,
    apiKey: key,
    generationConfig: GenerationConfig(
      responseMimeType: 'application/json',
      temperature: 0.2,
      maxOutputTokens: cap,
    ),
  );

  final response = await model.generateContent([Content.text(prompt)]);
  final usage = response.usageMetadata;
  final finish = response.candidates.isEmpty
      ? null
      : response.candidates.first.finishReason;
  stderr.writeln(
    'model=$modelName cap=$cap asked=$count finish=$finish '
    'in=${usage?.promptTokenCount} out=${usage?.candidatesTokenCount}',
  );

  final raw = response.text?.trim() ?? '';
  try {
    final decoded = jsonDecode(raw) as List;
    stderr.writeln('decoded OK: ${decoded.length} questions');
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(decoded));
  } catch (e) {
    stderr.writeln('DECODE FAILED ($e) — the app falls back here');
    stdout.writeln(raw);
  }
}
