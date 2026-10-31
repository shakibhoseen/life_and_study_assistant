// Runs the app's own prompts against the real model, from a desktop shell.
//
// The prompt text here is copied verbatim from the services so that what is
// measured is what ships. Each case states what a good reply looks like, and
// the run reports whether it got one -- the point is to find the prompts that
// quietly misbehave without installing a 171 MB APK to discover it.
//
//   GEMINI_API_KEY=$(tool/read_key_from_phone.sh) dart run tool/prompt_audit.dart
//   ... dart run tool/prompt_audit.dart mcq        (one group only)
import 'dart:convert';
import 'dart:io';

import 'package:google_generative_ai/google_generative_ai.dart';

typedef Check = String? Function(Map<String, Object?> json);

class Case {
  final String group;
  final String name;
  final String prompt;
  final Schema? schema;
  final Check check;
  final double temperature;
  final int? maxOutputTokens;

  const Case({
    required this.group,
    required this.name,
    required this.prompt,
    required this.check,
    this.schema,
    this.temperature = 0.1,
    this.maxOutputTokens,
  });
}

// ---------------------------------------------------------------- schemas
final _mcqSolveSchema = Schema.object(
  properties: {
    'chosen_index': Schema.integer(
      description: '0-based option number, or -1 if you cannot settle',
    ),
    'reasoning': Schema.string(description: 'One or two sentences, Bengali'),
    'confidence': Schema.number(description: '0.0 to 1.0'),
    'ambiguity': Schema.enumString(
      enumValues: ['none', 'multiple_correct', 'unclear_question'],
    ),
    'basis': Schema.enumString(
      enumValues: ['computation', 'internal_logic', 'recall'],
    ),
  },
  requiredProperties: [
    'chosen_index',
    'reasoning',
    'confidence',
    'ambiguity',
    'basis',
  ],
);

final _correctionSchema = Schema.array(
  items: Schema.object(
    properties: {
      'question_index': Schema.integer(description: '0-based index'),
      'proposed_correct_index': Schema.integer(nullable: true),
      'is_delete': Schema.boolean(),
      'new_question_text': Schema.string(),
      'new_options': Schema.array(items: Schema.string()),
      'reason': Schema.string(),
    },
    requiredProperties: [
      'question_index',
      'is_delete',
      'new_question_text',
      'new_options',
      'reason',
    ],
  ),
);


final _flashcardSchema = Schema.object(
  properties: {
    'subject': Schema.string(description: 'Subject name in Bengali'),
    'topic': Schema.string(description: 'Specific topic or chapter in Bengali'),
    'cards': Schema.array(
      items: Schema.object(
        properties: {
          'front': Schema.string(description: 'Concept or formula name'),
          'back': Schema.string(description: 'Formula, rule or mnemonic'),
        },
        requiredProperties: ['front', 'back'],
      ),
    ),
  },
  requiredProperties: ['subject', 'topic', 'cards'],
);

String _flashcards(String userPrompt) => '''
You are an expert tutor creating study flashcards for competitive exams in Bangladesh (BCS Preliminary, Bank, Primary Recruitment, LiveMCQ).
User prompt: "$userPrompt"

Instructions:
1. Generate 3 to 8 high-yield flashcards focused directly on this topic or formula request.
2. Front (Title): Short, focused concept, question or formula name.
3. Back (Key Rule): The exact formula, definition, shortcut, mnemonic or explanation in clear Bengali math unicode with practical recall tips.
4. Clean Unicode: Use '\u00b0', '\u00d7', '\u00b2', '\u00b3', '\u221a', '\u03c0', '\u00f7', '\u00bd'. Never use raw LaTeX dollar signs.
5. Return ONLY a valid JSON object matching the requested schema.
''';


/// Reads the mentor instruction out of the source file itself.
///
/// A copy on disk goes stale the moment the prompt changes, and then the
/// audit quietly measures the wrong text — which happened once already.
String _chatInstruction() {
  final src = File(
    'lib/core/services/ai/gemini_prompts.dart',
  ).readAsStringSync();
  const marker = "static const String chatStaticInstruction = '''";
  final start = src.indexOf(marker) + marker.length;
  final end = src.indexOf("''';", start);
  return src.substring(start, end);
}

String _mentor(String userMessage, {String context = ''}) =>
    '${_chatInstruction()}\n$context\n\nUser: $userMessage';


String _prompt(String name) =>
    File('$_promptDir/$name.txt').readAsStringSync();

const _promptDir =
    '/private/tmp/claude-501/-Users-shakib-Documents-work-flutter-app-life-and-study-assistant/683910d2-c4ed-4057-b19d-9e9919a2a859/scratchpad/prompts';

final _chatVerificationSchema = Schema.object(
  properties: {
    'claims_found': Schema.integer(),
    'claims_evaluated': Schema.integer(),
    'extraction_complete': Schema.boolean(),
    'extraction_note': Schema.string(),
    'claims': Schema.array(
      items: Schema.object(
        properties: {
          'text': Schema.string(),
          'kind': Schema.enumString(
            enumValues: ['mathematical', 'logical', 'factual'],
          ),
          'verdict': Schema.enumString(
            enumValues: ['supported', 'likely_incorrect', 'inconclusive'],
          ),
          'reasoning': Schema.string(description: 'One sentence, Bengali'),
          'confidence': Schema.number(description: '0.0 to 1.0'),
        },
        requiredProperties: [
          'text',
          'kind',
          'verdict',
          'reasoning',
          'confidence',
        ],
      ),
    ),
  },
  requiredProperties: [
    'claims_found',
    'claims_evaluated',
    'extraction_complete',
    'extraction_note',
    'claims',
  ],
);

// ------------------------------------------------------------------ cases
String _mcqSolve({
  required String subject,
  required String topic,
  required String question,
  required List<String> options,
}) {
  final numbered = [
    for (var i = 0; i < options.length; i++) '$i. ${options[i]}',
  ].join('\n');
  return '''
Answer this multiple-choice question from a Bangladeshi competitive exam (BCS, Bank, Government Recruitment).

You have NO web access. Work from the question itself and well-established general knowledge.

Subject: $subject
Topic: $topic

Question: $question
Options:
$numbered

BEFORE choosing, compare the options to each other. If any two express the SAME value written differently -- a ratio and its reduced form (10:6 and 5:3), a fraction and a decimal, the same quantity in different units -- then the question has no single answer. Set ambiguity to "multiple_correct" and say which two options collide.

Pick the option you believe is correct and put its number in chosen_index (0-based).

Set basis to:
- "computation" if you reached it by arithmetic or a rule you worked through
- "internal_logic" if the question itself determines the answer
- "recall" if you are remembering the fact. Be honest here; most factual questions are recall.

If more than one option is defensible set ambiguity to "multiple_correct". If the question itself is unclear set it to "unclear_question". In either case still give your best chosen_index, but say why in reasoning.

If you cannot settle on any option, set chosen_index to -1.

Write reasoning in Bengali, one or two sentences. Never cite a source or a URL.
''';
}

final _cases = <Case>[
  // ---- MCQ independent solve -------------------------------------------
  Case(
    group: 'mcq',
    name: 'spots a duplicated-option question',
    schema: _mcqSolveSchema,
    prompt: _mcqSolve(
      subject: 'Bangladesh Affairs',
      topic: 'জাতীয় প্রতীক',
      question: 'বাংলাদেশের জাতীয় পতাকার দৈর্ঘ্য ও প্রস্থের অনুপাত কত?',
      options: ['৩ : ২', '১০ : ৬', '৫ : ৩', 'অন্যান্য'],
    ),
    check: (j) {
      final amb = j['ambiguity'];
      // 10:6 and 5:3 are one ratio written twice, so this has no single answer.
      if (amb != 'multiple_correct') {
        return 'ambiguity=$amb, expected multiple_correct '
            '(chose ${j['chosen_index']})';
      }
      return null;
    },
  ),
  Case(
    group: 'mcq',
    name: 'answers a clean factual question',
    schema: _mcqSolveSchema,
    prompt: _mcqSolve(
      subject: 'Bangladesh Affairs',
      topic: 'নদী',
      question: 'তিব্বতের মানস সরোবর থেকে উৎপন্ন নদী কোনটি?',
      options: ['ব্রহ্মপুত্র', 'পদ্মা', 'যমুনা', 'মেঘনা'],
    ),
    check: (j) => j['chosen_index'] == 0
        ? null
        : 'chose ${j['chosen_index']}, expected 0 (ব্রহ্মপুত্র)',
  ),
  Case(
    group: 'mcq',
    name: 'calls arithmetic computation, not recall',
    schema: _mcqSolveSchema,
    prompt: _mcqSolve(
      subject: 'গণিত',
      topic: 'অনুপাত',
      question: '১০ : ৬ অনুপাতটিকে লঘিষ্ঠ আকারে প্রকাশ করলে কী হয়?',
      options: ['৩ : ২', '৫ : ৩', '২ : １', '৪ : ৩'],
    ),
    check: (j) {
      if (j['chosen_index'] != 1) {
        return 'chose ${j['chosen_index']}, expected 1 (৫ : ৩)';
      }
      if (j['basis'] != 'computation') {
        return 'basis=${j['basis']}, expected computation';
      }
      return null;
    },
  ),
  Case(
    group: 'mcq',
    name: 'refuses a garbled question instead of inventing',
    schema: _mcqSolveSchema,
    prompt: _mcqSolve(
      subject: 'বাংলা সাহিত্য',
      topic: 'বিলাসী',
      question: 'কপবসয় বতুনা দো পর জেলে ছিল?',
      options: ['ফরিদপুর', 'ঢাকা', 'ব্রাহ্মণ', 'শম্ভুনাথ সেন'],
    ),
    check: (j) {
      final amb = j['ambiguity'];
      final chosen = j['chosen_index'];
      if (amb == 'unclear_question' || chosen == -1) return null;
      return 'answered $chosen with ambiguity=$amb on unreadable text';
    },
  ),

  // ---- flashcard generation --------------------------------------------
  Case(
    group: 'card',
    name: 'turns a plain Bengali request into usable cards',
    schema: _flashcardSchema,
    temperature: 0.3,
    maxOutputTokens: 1200,
    prompt: _flashcards('বর্গক্ষেত্র ও রম্বসের ক্ষেত্রফলের সূত্র মনে রাখার কার্ড দাও'),
    check: (j) {
      final cards = j['cards'] as List?;
      if (cards == null || cards.length < 3) {
        return 'got ${cards?.length ?? 0} cards, expected at least 3';
      }
      for (final c in cards) {
        final m = c as Map;
        if ((m['front'] as String?)?.trim().isEmpty ?? true) {
          return 'a card has an empty front';
        }
        if ((m['back'] as String?)?.trim().isEmpty ?? true) {
          return 'a card has an empty back';
        }
      }
      final backs = cards.map((c) => (c as Map)['back'].toString()).join(' ');
      // LaTeX leaking through is the failure this prompt guards against.
      if (backs.contains(r'\\(') || backs.contains(r'$')) {
        return 'raw LaTeX leaked into a card back';
      }
      return null;
    },
  ),
  Case(
    group: 'card',
    name: 'handles a vague one-word request',
    schema: _flashcardSchema,
    temperature: 0.3,
    maxOutputTokens: 1200,
    prompt: _flashcards('কারক'),
    check: (j) {
      final cards = j['cards'] as List?;
      if (cards == null || cards.isEmpty) return 'no cards for a vague prompt';
      final subject = (j['subject'] ?? '').toString();
      if (subject.isEmpty) return 'no subject detected';
      return null;
    },
  ),
  Case(
    group: 'card',
    name: 'keeps unicode maths out of LaTeX',
    schema: _flashcardSchema,
    temperature: 0.3,
    maxOutputTokens: 1200,
    prompt: _flashcards('ত্রিভুজের ক্ষেত্রফল ও পিথাগোরাসের উপপাদ্য'),
    check: (j) {
      final cards = j['cards'] as List?;
      if (cards == null || cards.isEmpty) return 'no cards';
      final text = cards.map((c) => (c as Map)['back'].toString()).join(' ');
      if (text.contains(r'\\sqrt') || text.contains(r'\\frac')) {
        return 'LaTeX commands in the card back';
      }
      return null;
    },
  ),

  // ---- AI mentor chat ---------------------------------------------------
  Case(
    group: 'chat',
    name: 'answers a tired-after-office request without a lecture',
    temperature: 0.7,
    maxOutputTokens: 700,
    prompt: _mentor(
      'আজকে অফিসে খুব ধকল গেছে, মাথা কাজ করছে না। ১৫ মিনিটে কী পড়তে পারি?',
      context: 'Schedule: regular office workday.\n'
          'Energy: Low. Office fatigue 8/10.',
    ),
    check: (j) {
      final text = j['__text'] as String;
      if (text.length > 1400) {
        return 'replied with ${text.length} chars, that is a lecture';
      }
      if (!RegExp(r'[\u0980-\u09FF]').hasMatch(text)) {
        return 'reply is not in Bengali';
      }
      return null;
    },
  ),
  Case(
    group: 'chat',
    name: 'proposes an exam tag when asked to schedule one',
    temperature: 0.4,
    maxOutputTokens: 700,
    prompt: _mentor(
      '১২ নভেম্বর ২০২৬ তারিখে বাংলা ব্যাকরণের একটা মডেল টেস্ট রুটিনে যোগ করে দাও।',
    ),
    check: (j) {
      final text = j['__text'] as String;
      if (!text.contains('[[ACTION:ADD_EXAM')) {
        return 'no ADD_EXAM tag emitted';
      }
      if (!text.contains('2026-11-12')) {
        return 'tag did not carry the date the user gave';
      }
      return null;
    },
  ),
  Case(
    group: 'chat',
    name: 'does not claim it already saved something',
    temperature: 0.4,
    maxOutputTokens: 700,
    prompt: _mentor('সমাস টপিকটা আমার দুর্বল, যোগ করে রাখো।'),
    check: (j) {
      final text = j['__text'] as String;
      if (!text.contains('[[ACTION:ADD_TOPIC')) return 'no ADD_TOPIC tag';
      // The tag is a proposal the user taps; saying it is done is a lie.
      for (final claim in ['যোগ করে দিয়েছি', 'সেভ করে দিয়েছি', 'যুক্ত করে দিয়েছি']) {
        if (text.contains(claim)) return 'claimed it already saved: "$claim"';
      }
      return null;
    },
  ),
  Case(
    group: 'chat',
    name: 'does not mark a topic weak just for a question',
    temperature: 0.4,
    maxOutputTokens: 700,
    prompt: _mentor('কারক আর বিভক্তির পার্থক্যটা সহজ করে বুঝিয়ে দাও।'),
    check: (j) {
      final text = j['__text'] as String;
      // Offering to save a flashcard of the explanation is useful. Marking
      // the topic WEAK is not: that feeds the weak-topic list and the study
      // plan, and the user only asked what a word means.
      if (text.contains('[[ACTION:ADD_TOPIC')) {
        return 'marked the topic weak just for asking what it means';
      }
      if (text.length < 80) return 'reply too short to be an explanation';
      return null;
    },
  ),

  // ---- chat answer verification ----------------------------------------
  Case(
    group: 'verify',
    name: 'quotes the arithmetic claim so code can check it',
    schema: _chatVerificationSchema,
    maxOutputTokens: 1200,
    prompt: _prompt('chat_verification')
        .replaceAll(r'$contextBlock', '')
        .replaceAll(r'$userQuestion', 'পতাকার অনুপাত কত?')
        .replaceAll(
          r'$aiAnswer',
          'বাংলাদেশের জাতীয় পতাকার অনুপাত ১০:৬, যা লঘিষ্ঠ করলে ৩:২ হয়।',
        ),
    check: (j) {
      final claims = (j['claims'] as List?) ?? const [];
      if (claims.isEmpty) return 'found no claims at all';

      // The model marks this "supported" more often than not — it believes
      // 10:6 reduces to 3:2. ClaimMathChecker overrides that verdict in
      // code, but only for a claim that was actually pulled out and quoted
      // verbatim, so extraction is the part the prompt must get right.
      final quoted = claims.any(
        (c) =>
            (c as Map)['kind'] == 'mathematical' &&
            (c['text'] ?? '').toString().contains('১০:৬'),
      );
      return quoted
          ? null
          : 'did not quote the arithmetic claim, so the local check has '
              'nothing to verify';
    },
  ),
  Case(
    group: 'verify',
    name: 'does not call a recalled fact verified',
    schema: _chatVerificationSchema,
    maxOutputTokens: 1200,
    prompt: _prompt('chat_verification')
        .replaceAll(r'$contextBlock', '')
        .replaceAll(r'$userQuestion', 'মুক্তিযুদ্ধের সেক্টর কয়টি ছিল?')
        .replaceAll(
          r'$aiAnswer',
          'মুক্তিযুদ্ধের সময় বাংলাদেশকে ১১টি সেক্টরে ভাগ করা হয়েছিল।',
        ),
    check: (j) {
      final claims = (j['claims'] as List?) ?? const [];
      if (claims.isEmpty) return 'found no claims';
      for (final c in claims) {
        final m = c as Map;
        // Remembering something is not checking it, however certain it feels.
        if (m['kind'] == 'factual' && m['verdict'] == 'supported') {
          return 'called a factual recall "supported": "${m['text']}"';
        }
      }
      return null;
    },
  ),

  // ---- the user argues back ---------------------------------------------
  Case(
    group: 'evidence',
    name: 'is not told which answer is stored',
    maxOutputTokens: 900,
    prompt:
        'Does the following instruction block ever reveal which option is '
        'currently saved as the correct answer? Reply with exactly YES or NO '
        'and nothing else.\n\n---\n${_prompt('evidence_review')}',
    check: (j) {
      final text = (j['__text'] as String).trim().toUpperCase();
      // The whole design rests on the reviewer not knowing, so this is worth
      // asserting rather than assuming.
      return text.startsWith('NO')
          ? null
          : 'the prompt leaks the stored answer (model said "$text")';
    },
  ),

  // ---- mistake explanation ----------------------------------------------
  Case(
    group: 'explain',
    name: 'keeps the three Bengali headings verbatim',
    temperature: 0.7,
    maxOutputTokens: 900,
    prompt: _prompt('mistake_explain')
        .replaceAll(r'$subject', 'Bangladesh Affairs')
        .replaceAll(r'$topic', 'জাতীয় প্রতীক')
        .replaceAll(r'$questionText', 'পতাকার দৈর্ঘ্য ও প্রস্থের অনুপাত কত?')
        .replaceAll(r"${options.join(', ')}", '৩:২, ১০:৬, ২:১, ৪:৩')
        .replaceAll(r'$userAns', '৩:২')
        .replaceAll(r'$correctAns', '১০:৬')
        .replaceAll(r'${_shorten(explanation, 300)}', '১০:৬ = ৫:৩।'),
    check: (j) {
      final text = j['__text'] as String;
      for (final heading in ['The Trap', 'Memory Hook', 'Related High-Yield']) {
        if (!text.contains(heading)) return 'missing heading: $heading';
      }
      if (text.contains(r'\\(') || text.contains(r'\\frac')) {
        return 'LaTeX leaked into the explanation';
      }
      return null;
    },
  ),

  // ---- batch correction from an external analysis -----------------------
  Case(
    group: 'fix',
    name: 'maps 1-based report numbers onto 0-based rows',
    schema: _correctionSchema,
    maxOutputTokens: 4096,
    prompt: '''
You are an expert competitive exam assistant in Bangladesh.
A student took a quiz and asked an external AI (like ChatGPT or Claude) for analysis.
The student has provided the external AI's analysis text below.

Quiz Questions List:
0. "কল্যাণীর বাবার নাম কী?" | options: [0:শম্ভুনাথ সেন, 1:মৃত্যুঞ্জয়, 2:অনুপম, 3:বিলাসী] | current_correct_index: 0
1. "বায়ান্নর দিনগুলো রচনায় বঙ্গবন্ধু কোন জেলে বন্দী ছিলেন?" | options: [0:ফরিদপুর, 1:ঢাকা, 2:বরিশাল, 3:খুলনা] | current_correct_index: 0
2. "বিলাসী গল্পে মৃত্যুঞ্জয় কোন বংশের ছেলে?" | options: [0:শম্ভুনাথ সেন, 1:ব্রাহ্মণ, 2:কায়স্থ, 3:বৈদ্য] | current_correct_index: 0

External AI's Analysis Text:
"""
প্রশ্ন ৩: ভুল। প্রশ্নে 'বিলাসী' গল্পের মৃত্যুঞ্জয়ের জাত জানতে চাওয়া হয়েছে, কিন্তু উত্তর দেওয়া হয়েছে 'শম্ভুনাথ সেন'। সঠিক উত্তর হবে ব্রাহ্মণ।
প্রশ্ন ১ ও ২ ঠিক আছে।
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
    * Only rewrite when the analysis actually supplies or clearly implies the correct wording. Never invent a question or an option to fill a gap -- recommend deletion instead.
- reason: concise 1-sentence Bengali reason explaining why this question was corrected or discarded.

Return JSON array ONLY.
If the text says all answers are correct or no fixes are suggested, return: []
''',
    check: (j) {
      final items = j['__array'] as List?;
      if (items == null || items.isEmpty) return 'returned no corrections';
      final first = items.first as Map;
      if (first['question_index'] != 2) {
        return 'targeted index ${first['question_index']}, expected 2 '
            '(report said প্রশ্ন ৩)';
      }
      if (first['proposed_correct_index'] != 1) {
        return 'proposed ${first['proposed_correct_index']}, expected 1 '
            '(ব্রাহ্মণ)';
      }
      if (items.length > 1) {
        return 'returned ${items.length} corrections, expected 1';
      }
      return null;
    },
  ),
  Case(
    group: 'fix',
    name: 'does not invent a fix for an unrecoverable question',
    schema: _correctionSchema,
    maxOutputTokens: 4096,
    prompt: '''
You are an expert competitive exam assistant in Bangladesh.
The student has provided an external AI's analysis text below.

Quiz Questions List:
0. "কপবসয় কোন রচনার?" | options: [0:ফরিদপুর, 1:ঢাকা, 2:বরিশাল, 3:খুলনা] | current_correct_index: 0

External AI's Analysis Text:
"""
প্রশ্ন ১: ভুল। 'কপবসয়' কোনো সুস্পষ্ট রচনার নাম নয়, প্রশ্নটি বিকৃত। মূল প্রশ্ন উদ্ধার না করে এর সঠিক উত্তর অনুমান করা ঠিক হবে না।
"""

Task: as above. Only rewrite when the analysis actually supplies or clearly implies the correct wording. Never invent a question or an option to fill a gap -- recommend deletion instead.
Return JSON array ONLY.
''',
    check: (j) {
      final items = j['__array'] as List?;
      if (items == null || items.isEmpty) return null; // leaving it alone is fine
      final first = items.first as Map;
      final rewrote = (first['new_question_text'] as String?)?.isNotEmpty ??
          false;
      if (first['is_delete'] == true) return null;
      if (rewrote) {
        return 'invented a replacement question: '
            '"${first['new_question_text']}"';
      }
      return null;
    },
  ),
];

// ------------------------------------------------------------------ runner
Future<void> main(List<String> args) async {
  final key = Platform.environment['GEMINI_API_KEY'];
  if (key == null || key.isEmpty) {
    stderr.writeln('GEMINI_API_KEY is not set.');
    exit(2);
  }

  final only = args.isEmpty ? null : args.first;
  final cases = only == null
      ? _cases
      : _cases.where((c) => c.group == only).toList();

  var passed = 0;
  var failed = 0;
  var tokens = 0;

  for (final c in cases) {
    final model = GenerativeModel(
      model: Platform.environment['GEMINI_MODEL'] ?? 'gemini-flash-lite-latest',
      apiKey: key,
      generationConfig: GenerationConfig(
        temperature: c.temperature,
        responseMimeType: c.schema == null ? null : 'application/json',
        responseSchema: c.schema,
        maxOutputTokens: c.maxOutputTokens,
      ),
    );

    try {
      final response = await model.generateContent([Content.text(c.prompt)]);
      tokens += response.usageMetadata?.totalTokenCount ?? 0;
      final raw = response.text ?? '';

      late final Map<String, Object?> json;
      if (c.schema == null) {
        json = <String, Object?>{'__text': raw};
      } else {
        final decoded = jsonDecode(raw);
        json = decoded is List
            ? <String, Object?>{'__array': decoded}
            : Map<String, Object?>.from(decoded as Map);
      }

      final problem = c.check(json);
      if (problem == null) {
        passed++;
        stdout.writeln('  PASS  [${c.group}] ${c.name}');
      } else {
        failed++;
        stdout.writeln('  FAIL  [${c.group}] ${c.name}');
        stdout.writeln('        $problem');
      }
    } catch (e) {
      failed++;
      stdout.writeln('  ERROR [${c.group}] ${c.name}');
      stdout.writeln('        $e');
    }
  }

  stdout.writeln('\n$passed passed, $failed failed, $tokens tokens');
  if (failed > 0) exit(1);
}
