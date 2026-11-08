import 'dart:convert';

import '../../utils/bengali_math_sanitizer.dart';
import 'models/question_bank_extract_result.dart';
import 'models/quiz_question.dart';

/// Local parser for MCQ text copied from external agents (ChatGPT, Claude, etc.),
/// OCR dumps, or question banks.
class QuestionTextParser {
  QuestionTextParser._();

  /// Tries to parse [rawText] into [QuestionBankExtractResult] offline using
  /// JSON parsing or regex-based structural analysis.
  /// Returns `null` if the text could not be reliably parsed into at least 1 MCQ.
  static QuestionBankExtractResult? tryParseLocal(
    String rawText, {
    String? subjectHint,
  }) {
    final text = rawText.trim();
    if (text.isEmpty) return null;

    // 1. Try JSON parsing (direct array or wrapped in an object or markdown block)
    final fromJson = _tryParseJson(text, subjectHint);
    if (fromJson != null && fromJson.questions.isNotEmpty) {
      return fromJson;
    }

    // 2. Try structured regex text parsing
    final fromText = _tryParseStructuredText(text, subjectHint);
    if (fromText != null && fromText.questions.isNotEmpty) {
      return fromText;
    }

    return null;
  }

  /// Parses JSON array `[...]` or object `{"questions": [...]}`
  static QuestionBankExtractResult? _tryParseJson(
    String text,
    String? subjectHint,
  ) {
    try {
      String jsonStr = text;
      // Strip markdown code fences if any
      final fenceMatch = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```').firstMatch(text);
      if (fenceMatch != null) {
        jsonStr = fenceMatch.group(1)?.trim() ?? text;
      }

      final decoded = jsonDecode(jsonStr);
      List<dynamic>? list;
      String? title;
      String? subject = subjectHint;

      if (decoded is List) {
        list = decoded;
      } else if (decoded is Map<String, dynamic>) {
        if (decoded['questions'] is List) {
          list = decoded['questions'] as List<dynamic>;
        }
        title = decoded['title']?.toString();
        if (decoded['subject'] != null) {
          subject = decoded['subject']?.toString();
        }
      }

      if (list != null && list.isNotEmpty) {
        final questions = <QuizQuestion>[];
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            final q = _mapJsonItemToQuestion(item, subject);
            if (q != null) questions.add(q);
          }
        }

        if (questions.isNotEmpty) {
          return QuestionBankExtractResult(
            title: title ?? 'টেক্সট থেকে তৈরি কুইজ (${questions.length} MCQs)',
            subject: subject ?? 'General',
            rawReference: 'Pasted Text (${questions.length} MCQs)',
            questions: questions,
          );
        }
      }
    } catch (_) {
      // Not valid JSON, ignore and try regex
    }
    return null;
  }

  static QuizQuestion? _mapJsonItemToQuestion(
    Map<String, dynamic> item,
    String? subject,
  ) {
    final qText = (item['question'] ?? item['questionText'] ?? item['q'])?.toString().trim();
    if (qText == null || qText.isEmpty) return null;

    final rawOptions = item['options'] ?? item['opts'] ?? item['choices'];
    if (rawOptions is! List) return null;

    final options = <String>[];
    for (final opt in rawOptions) {
      final s = opt?.toString().trim();
      if (s != null && s.isNotEmpty) {
        options.add(BengaliMathSanitizer.sanitize(s));
      }
    }
    if (options.length < 2) return null;

    // Detect correct index
    int correctIndex = 0;
    final rawIndex = item['correct_index'] ?? item['correctIndex'] ?? item['answer_index'];
    if (rawIndex is int && rawIndex >= 0 && rawIndex < options.length) {
      correctIndex = rawIndex;
    } else {
      final rawAns = item['answer'] ?? item['correct'] ?? item['ans'];
      if (rawAns != null) {
        correctIndex = _resolveAnswerOptionIndex(rawAns.toString(), options);
      }
    }

    final explanation = (item['explanation'] ?? item['exp'] ?? item['note'] ?? '')
        .toString()
        .trim();

    return QuizQuestion(
      questionText: BengaliMathSanitizer.sanitize(qText),
      options: options,
      correctIndex: correctIndex,
      explanation: BengaliMathSanitizer.sanitize(explanation),
      subject: subject,
      answerSource: AnswerSource.solved,
      legible: true,
    );
  }

  /// Parses text formatted with question numbers (১., 2., Q1, etc.)
  /// and option markers (ক, খ, গ, ঘ, (ক), A, B, C, D, etc.).
  static QuestionBankExtractResult? _tryParseStructuredText(
    String text,
    String? subjectHint,
  ) {
    // Regex matching the start of a question item:
    // e.g. "১.", "1.", "1)", "১)", "Q1:", "প্রশ্ন ১:", etc.
    final questionHeaderPattern = RegExp(
      r'(?:^|\n+)(?:(?:প্রশ্ন\s*)?([০-৯\d]+)[\.\)\:\-]\s*|(?:Q\s*([০-৯\d]+)[\.\)\:\-]\s*))',
      caseSensitive: false,
    );

    final matches = questionHeaderPattern.allMatches(text).toList();
    final questions = <QuizQuestion>[];

    if (matches.isEmpty) {
      // Single question without number? Check if options exist
      final singleQ = _parseSingleQuestionBlock(text, subjectHint);
      if (singleQ != null) {
        return QuestionBankExtractResult(
          title: 'টেক্সট থেকে তৈরি কুইজ (১ MCQ)',
          subject: subjectHint ?? 'General',
          rawReference: 'Pasted Text (1 MCQ)',
          questions: [singleQ],
        );
      }
      return null;
    }

    for (int i = 0; i < matches.length; i++) {
      final startIndex = matches[i].start;
      final endIndex = (i + 1 < matches.length) ? matches[i + 1].start : text.length;
      final block = text.substring(startIndex, endIndex).trim();

      final parsed = _parseSingleQuestionBlock(block, subjectHint);
      if (parsed != null) {
        questions.add(parsed);
      }
    }

    if (questions.isEmpty) return null;

    return QuestionBankExtractResult(
      title: 'টেক্সট থেকে তৈরি কুইজ (${questions.length} MCQs)',
      subject: subjectHint ?? 'General',
      rawReference: 'Pasted Text (${questions.length} MCQs)',
      questions: questions,
    );
  }

  static QuizQuestion? _parseSingleQuestionBlock(
    String block,
    String? subject,
  ) {
    final lines = block
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    if (lines.isEmpty) return null;

    String? questionText;
    final options = <String>[];
    String? answerLine;
    final explanationLines = <String>[];

    // Option indicators: ক., (ক), ক), A., (A), A)
    final optionRegex = RegExp(
      r'^(?:\(?([কখগঘঙABCDEabcde])[\.\)\:\-]\s*|\(([কখগঘঙABCDEabcde])\)\s*)(.*)$',
    );

    final answerRegex = RegExp(
      r'^(?:(?:সঠিক\s*)?উত্তর|Ans(?:wer)?)\s*[\:\=\-]\s*(.*)$',
      caseSensitive: false,
    );

    final explanationRegex = RegExp(
      r'^(?:ব্যাখ্যা|Explanation|Note)\s*[\:\=\-]\s*(.*)$',
      caseSensitive: false,
    );

    bool readingExplanation = false;

    for (final line in lines) {
      if (explanationRegex.hasMatch(line)) {
        readingExplanation = true;
        final match = explanationRegex.firstMatch(line);
        final content = match?.group(1)?.trim();
        if (content != null && content.isNotEmpty) {
          explanationLines.add(content);
        }
        continue;
      }

      if (readingExplanation) {
        explanationLines.add(line);
        continue;
      }

      if (answerRegex.hasMatch(line)) {
        final match = answerRegex.firstMatch(line);
        answerLine = match?.group(1)?.trim() ?? line;
        continue;
      }

      if (optionRegex.hasMatch(line)) {
        final match = optionRegex.firstMatch(line);
        final letter = (match?.group(1) ?? match?.group(2) ?? '').trim();
        final text = (match?.group(3) ?? '').trim();
        // Standardize Bengali option prefix
        final bengaliLetter = _normalizeOptionPrefix(letter);
        options.add('$bengaliLetter $text');
        continue;
      }

      if (questionText == null) {
        questionText = line;
      } else if (options.isEmpty) {
        // Multi-line question stem
        questionText = '$questionText $line';
      }
    }

    if (questionText == null || options.length < 2) return null;

    int correctIndex = 0;
    if (answerLine != null) {
      correctIndex = _resolveAnswerOptionIndex(answerLine, options);
    }

    final explanation = explanationLines.join(' ').trim();

    return QuizQuestion(
      questionText: BengaliMathSanitizer.sanitize(questionText),
      options: options.map((opt) => BengaliMathSanitizer.sanitize(opt)).toList(),
      correctIndex: correctIndex,
      explanation: BengaliMathSanitizer.sanitize(explanation),
      subject: subject,
      answerSource: answerLine != null ? AnswerSource.answerKey : AnswerSource.solved,
      legible: true,
    );
  }

  static String _normalizeOptionPrefix(String raw) {
    final lower = raw.toLowerCase();
    switch (lower) {
      case 'ক':
      case 'a':
        return 'ক.';
      case 'খ':
      case 'b':
        return 'খ.';
      case 'গ':
      case 'c':
        return 'গ.';
      case 'ঘ':
      case 'd':
        return 'ঘ.';
      case 'ঙ':
      case 'e':
        return 'ঙ.';
      default:
        return '$raw.';
    }
  }

  static int _resolveAnswerOptionIndex(String answerText, List<String> options) {
    final cleaned = answerText.trim();
    if (cleaned.isEmpty) return 0;

    // Check letter match (ক/খ/গ/ঘ or A/B/C/D or 1/2/3/4)
    final firstChar = cleaned.substring(0, 1).toLowerCase();
    switch (firstChar) {
      case 'ক':
      case 'a':
      case '১':
      case '1':
        return 0;
      case 'খ':
      case 'b':
      case '২':
      case '2':
        return options.length > 1 ? 1 : 0;
      case 'গ':
      case 'c':
      case '৩':
      case '3':
        return options.length > 2 ? 2 : 0;
      case 'ঘ':
      case 'd':
      case '৪':
      case '4':
        return options.length > 3 ? 3 : 0;
      case 'ঙ':
      case 'e':
      case '৫':
      case '5':
        return options.length > 4 ? 4 : 0;
    }

    // Try matching substring of option text
    for (int i = 0; i < options.length; i++) {
      final opt = options[i];
      if (opt.contains(cleaned) || cleaned.contains(opt)) {
        return i;
      }
    }

    return 0;
  }
}
