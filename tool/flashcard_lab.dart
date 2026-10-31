// Runs the app's own flashcard call from a desktop shell.
//
// The model, schema, temperature, token cap and wording are copied from
// AiFlashcardService.generateFromPrompt so that what comes back here is what
// the app would get. Installing a debug APK takes about four minutes; this
// takes two seconds, which is the difference between measuring a prompt and
// guessing at it.
//
//   GEMINI_API_KEY=$(tool/read_key_from_phone.sh) \
//     dart run tool/flashcard_lab.dart prompt.txt
//
// Override the cap to see where it bites:  FLASHCARD_MAX_TOKENS=4096
import 'dart:convert';
import 'dart:io';

import 'package:google_generative_ai/google_generative_ai.dart';

final _flashcardSchema = Schema.object(
  properties: {
    'subject': Schema.string(description: 'Subject name in Bengali'),
    'topic': Schema.string(description: 'Specific topic or chapter name'),
    'cards': Schema.array(
      items: Schema.object(
        properties: {
          'front': Schema.string(description: 'Concept, formula or question'),
          'back': Schema.string(description: 'Formula, rule or mnemonic'),
          'subject': Schema.string(description: 'Optional subject override'),
          'topic': Schema.string(description: 'Optional topic override'),
          'priority': Schema.enumString(
            enumValues: ['high', 'medium', 'low'],
            description: 'How directly the exam asks this',
          ),
          'why': Schema.string(description: 'Why memorise this'),
        },
        requiredProperties: ['front', 'back'],
      ),
    ),
  },
  requiredProperties: ['cards'],
);

Future<void> main(List<String> args) async {
  final key = Platform.environment['GEMINI_API_KEY'];
  if (key == null || key.isEmpty) {
    stderr.writeln('GEMINI_API_KEY is not set. See the header of this file.');
    exit(2);
  }
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/flashcard_lab.dart <prompt-file>');
    exit(2);
  }

  final trimmed = File(args.first).readAsStringSync().trim();
  final cap = int.parse(Platform.environment['FLASHCARD_MAX_TOKENS'] ?? '1024');
  final ask =
      Platform.environment['FLASHCARD_ASK'] ??
      'Generate 3 to 8 high-yield flashcards focused directly on this topic or formula request.';

  final model = GenerativeModel(
    model: 'gemini-flash-latest',
    apiKey: key,
    generationConfig: GenerationConfig(
      responseMimeType: 'application/json',
      responseSchema: _flashcardSchema,
      temperature: 0.2,
      maxOutputTokens: cap,
    ),
  );

  final systemPrompt =
      '''
You are an expert tutor creating study flashcards for competitive exams in Bangladesh (BCS Preliminary, Bank, Primary Recruitment, LiveMCQ).
User prompt: "$trimmed"

Instructions:
1. $ask
2. Front (Title): Short, focused concept, question or formula name.
3. Back (Key Rule): The exact formula, definition, shortcut, mnemonic or explanation in clear Bengali math unicode with practical recall tips.
4. Clean Unicode: Use '°', '×', '²', '³', '√', 'π', '÷', '½'. Never use raw LaTeX dollar signs.
5. Return ONLY a valid JSON object matching the requested schema.
''';

  final response = await model.generateContent([Content.text(systemPrompt)]);

  final usage = response.usageMetadata;
  final finish = response.candidates.isEmpty
      ? null
      : response.candidates.first.finishReason;
  stderr.writeln(
    'cap=$cap  finish=$finish  '
    'in=${usage?.promptTokenCount}  out=${usage?.candidatesTokenCount}',
  );

  final raw = response.text?.trim() ?? '';
  try {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final cards = (decoded['cards'] as List?) ?? const [];
    stderr.writeln('decoded OK: ${cards.length} cards');
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(decoded));
  } catch (e) {
    stderr.writeln('DECODE FAILED ($e) — the app falls back here');
    stdout.writeln(raw);
  }
}
