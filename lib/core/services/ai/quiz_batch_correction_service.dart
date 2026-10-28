import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/notification_constants.dart';
import '../../database/app_database.dart';
import '../../utils/bengali_math_sanitizer.dart';
import 'gemini_ai_service.dart';
import 'gemini_usage_tracker.dart';
import 'models/quiz_question.dart';

class QuestionCorrectionItem {
  final int questionIndex; // 0-based index
  final String questionSnippet;
  final int? proposedCorrectIndex; // 0, 1, 2, 3 or null if delete
  final String proposedOptionText;
  final String oldOptionText;
  final bool isDelete;

  /// A replacement for the printed question, when the external analysis said
  /// the question text itself was wrong or unreadable.
  final String? newQuestionText;

  /// A replacement option set, for the same reason.
  final List<String>? newOptions;

  final String reason;
  bool isSelected;

  /// Whether this rewrites the question itself rather than only re-pointing
  /// the answer.
  bool get rewritesQuestion => newQuestionText != null || newOptions != null;

  QuestionCorrectionItem({
    required this.questionIndex,
    required this.questionSnippet,
    this.proposedCorrectIndex,
    required this.proposedOptionText,
    required this.oldOptionText,
    this.isDelete = false,
    this.newQuestionText,
    this.newOptions,
    required this.reason,
    this.isSelected = true,
  });

  Map<String, dynamic> toJson() => {
    'question_index': questionIndex,
    'question_snippet': questionSnippet,
    'proposed_correct_index': proposedCorrectIndex,
    'proposed_option_text': proposedOptionText,
    'old_option_text': oldOptionText,
    'is_delete': isDelete,
    'new_question_text': newQuestionText,
    'new_options': newOptions,
    'reason': reason,
  };

  /// Reads one correction, or null when it does not point at a real question.
  ///
  /// An out-of-range index used to fall back to 0, which quietly rewrote the
  /// first question instead of the one the analysis meant — and an external
  /// report that numbers from ১ makes that an easy mistake to trigger.
  static QuestionCorrectionItem? tryFromJson(
    Map<String, dynamic> json,
    List<QuizQuestion> questions,
  ) {
    final idx = (json['question_index'] as num?)?.toInt();
    if (idx == null || idx < 0 || idx >= questions.length) return null;
    final validIdx = idx;
    final q = questions[validIdx];

    final isDel =
        json['is_delete'] == true || json['action'] == 'delete_question';
    final pIdx = (json['proposed_correct_index'] as num?)?.toInt();

    final rawNewOptions = json['new_options'];
    List<String>? newOptions;
    if (rawNewOptions is List && rawNewOptions.length >= 2) {
      final cleaned = rawNewOptions
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (cleaned.length == rawNewOptions.length) newOptions = cleaned;
    }

    final rawNewText = json['new_question_text']?.toString().trim() ?? '';
    final newQuestionText = rawNewText.isEmpty ? null : rawNewText;

    final effectiveOptions = newOptions ?? q.options;

    String oldOpt = '';
    if (q.correctIndex >= 0 && q.correctIndex < q.options.length) {
      oldOpt = q.options[q.correctIndex];
    }

    String propOpt = '';
    if (pIdx != null && pIdx >= 0 && pIdx < effectiveOptions.length) {
      propOpt = effectiveOptions[pIdx];
    } else if (json['proposed_option_text'] != null) {
      propOpt = json['proposed_option_text'].toString();
    }

    return QuestionCorrectionItem(
      questionIndex: validIdx,
      questionSnippet: q.questionText,
      proposedCorrectIndex: pIdx,
      proposedOptionText: propOpt,
      oldOptionText: oldOpt,
      isDelete: isDel,
      newQuestionText: newQuestionText,
      newOptions: newOptions,
      reason: BengaliMathSanitizer.sanitize(
        json['reason']?.toString() ?? 'External AI সংশোধন',
      ),
      isSelected: true,
    );
  }
}

/// Shape of a batch of corrections read out of an external analysis.
///
/// Taught as a schema rather than as prose in the prompt, because a reply
/// that drifts from the shape decodes to nothing and reads downstream as
/// "no corrections found".
final _correctionSchema = Schema.array(
  items: Schema.object(
    properties: {
      'question_index': Schema.integer(
        description: '0-based index into the quiz list given above',
      ),
      'proposed_correct_index': Schema.integer(
        description: 'New correct option index, or -1 to leave the answer',
        nullable: true,
      ),
      'is_delete': Schema.boolean(
        description: 'True if this question should be dropped entirely',
      ),
      'new_question_text': Schema.string(
        description: 'Corrected question text, or empty string to keep it',
      ),
      'new_options': Schema.array(
        items: Schema.string(),
        description: 'Corrected full option list, or empty array to keep them',
      ),
      'reason': Schema.string(description: 'One short Bengali sentence'),
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

class QuizBatchCorrectionService {
  QuizBatchCorrectionService._();
  static final QuizBatchCorrectionService instance =
      QuizBatchCorrectionService._();

  Future<String?> _getApiKey() async {
    try {
      final cached = GeminiAiService.instance.apiKey;
      if (cached != null && cached.isNotEmpty) return cached;
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(NotificationConstants.prefGeminiApiKey);
    } catch (_) {
      return null;
    }
  }

  /// Parses external AI feedback/analysis into structured question corrections.
  Future<List<QuestionCorrectionItem>> parseCorrections({
    required List<QuizQuestion> questions,
    required String externalAnalysis,
  }) async {
    if (questions.isEmpty || externalAnalysis.trim().isEmpty) return const [];

    final apiKey = await _getApiKey();
    if (apiKey != null && apiKey.isNotEmpty) {
      try {
        final result = await _parseWithGemini(
          apiKey: apiKey,
          questions: questions,
          externalAnalysis: externalAnalysis,
        );
        debugPrint(
          'Batch correction: ${result.length} corrections parsed from '
          '${questions.length} questions',
        );
        if (result.isNotEmpty) return result;
      } catch (e) {
        debugPrint('Gemini batch correction parsing error: $e');
        final lower = e.toString().toLowerCase();
        if (lower.contains('429') ||
            lower.contains('resource_exhausted') ||
            lower.contains('quota')) {
          await GeminiUsageTracker.instance.recordQuotaExceeded(
            operation: 'quiz_batch_correction',
            model: 'gemini-flash-latest',
          );
        } else {
          await GeminiUsageTracker.instance.recordError(
            e.toString(),
            operation: 'quiz_batch_correction',
            model: 'gemini-flash-latest',
          );
        }
      }
    }

    // Offline / Regex fallback
    final offline = _parseOffline(questions, externalAnalysis);
    debugPrint(
      'Batch correction: fell back to offline parsing, '
      '${offline.length} corrections',
    );
    return offline;
  }

  Future<List<QuestionCorrectionItem>> _parseWithGemini({
    required String apiKey,
    required List<QuizQuestion> questions,
    required String externalAnalysis,
  }) async {
    final questionsListBuffer = StringBuffer();
    for (int i = 0; i < questions.length; i++) {
      final q = questions[i];
      final opts = q.options
          .asMap()
          .entries
          .map((e) => '${e.key}:${e.value}')
          .join(', ');
      questionsListBuffer.writeln(
        '$i. "${q.questionText}" | options: [$opts] | current_correct_index: ${q.correctIndex}',
      );
    }

    final prompt =
        '''
You are an expert competitive exam assistant in Bangladesh.
A student took a quiz and asked an external AI (like ChatGPT or Claude) for analysis.
The student has provided the external AI's analysis text below.

Quiz Questions List:
$questionsListBuffer

External AI's Analysis Text:
"""
$externalAnalysis
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
- reason: concise 1-sentence Bengali reason explaining why this question was corrected or discarded.

Return JSON array ONLY:
[
  {
    "question_index": 0,
    "proposed_correct_index": 1,
    "is_delete": false,
    "new_question_text": "",
    "new_options": [],
    "reason": "..."
  }
]
If the text says all answers are correct or no fixes are suggested, return: []
''';

    final model = GenerativeModel(
      model: 'gemini-flash-latest',
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        responseSchema: _correctionSchema,
        temperature: 0.1,
        // A page of Bengali corrections runs well past 1024, and a cut-off
        // array decodes to nothing, which looked like "it got them all wrong".
        maxOutputTokens: 4096,
      ),
    );

    final response = await model.generateContent([Content.text(prompt)]);

    // This call used to spend tokens without recording any, so its cost never
    // showed up in the daily total or in the log.
    await GeminiUsageTracker.instance.recordSuccess(
      tokens: response.usageMetadata?.totalTokenCount ?? 0,
      actualInputTokens: response.usageMetadata?.promptTokenCount,
      actualOutputTokens: response.usageMetadata?.candidatesTokenCount,
      actualTotalTokens: response.usageMetadata?.totalTokenCount,
      operation: 'quiz_batch_correction',
      model: 'gemini-flash-latest',
    );

    final truncated =
        response.candidates.isNotEmpty &&
        response.candidates.first.finishReason == FinishReason.maxTokens;
    if (truncated) {
      debugPrint(
        'Batch correction: OUTPUT TRUNCATED — some corrections are missing',
      );
    }

    final raw = response.text?.trim() ?? '';
    if (raw.isEmpty) {
      debugPrint('Batch correction: empty reply');
      return const [];
    }

    var clean = raw;
    if (clean.startsWith('```json')) clean = clean.substring(7);
    if (clean.startsWith('```')) clean = clean.substring(3);
    if (clean.endsWith('```')) clean = clean.substring(0, clean.length - 3);

    final decoded = jsonDecode(clean.trim());
    if (decoded is List) {
      final items = <QuestionCorrectionItem>[];
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          final parsed = QuestionCorrectionItem.tryFromJson(item, questions);
          // A correction that points at no real question is dropped, not
          // redirected onto another one.
          if (parsed != null) items.add(parsed);
        }
      }
      return items;
    }
    return const [];
  }

  /// Rule-based regex parser fallback for offline use.
  List<QuestionCorrectionItem> _parseOffline(
    List<QuizQuestion> questions,
    String text,
  ) {
    final items = <QuestionCorrectionItem>[];
    final lines = text.split('\n');

    // Maps Bengali/English option letters to 0..3
    int? optionCharToIndex(String char) {
      final c = char.trim().toLowerCase();
      if (c == 'ক' || c == 'a' || c == '১' || c == '1' || c == '0') return 0;
      if (c == 'খ' || c == 'b' || c == '২' || c == '2') return 1;
      if (c == 'গ' || c == 'c' || c == '৩' || c == '3') return 2;
      if (c == 'ঘ' || c == 'd' || c == '৪' || c == '4') return 3;
      return null;
    }

    final directPattern = RegExp(
      r'^(?:প্রশ্ন|q|question)?\s*([০-৯\d]+)[.:\s\-)–—]+\s*([কখগঘabcd])(?:\s*[-–—:]\s*(.*)|\s+.*)?$',
      caseSensitive: false,
    );
    final qPattern = RegExp(
      r'(?:প্রশ্ন|q|question)?\s*([০-৯\d]+)[.:\s\-)–—]+.*?(?:সঠিক|উত্তর|correct|\bহবে\b|\bis\b).*?([কখগঘabcd])',
      caseSensitive: false,
    );
    final delPattern = RegExp(
      r'(?:প্রশ্ন|q|question)?\s*([০-৯\d]+)[.:\s\-)–—]+.*?(?:বাদ|বাতিল|ভুল প্রশ্ন|delete|remove|invalid|outdated)',
      caseSensitive: false,
    );

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final delMatch = delPattern.firstMatch(line);
      if (delMatch != null) {
        final qNumStr = delMatch.group(1)!;
        final qNum =
            int.tryParse(BengaliMathSanitizer.toEnglishDigits(qNumStr)) ?? 0;
        final qIdx = qNum - 1;
        if (qIdx >= 0 && qIdx < questions.length) {
          items.add(
            QuestionCorrectionItem(
              questionIndex: qIdx,
              questionSnippet: questions[qIdx].questionText,
              proposedCorrectIndex: null,
              proposedOptionText: '',
              oldOptionText:
                  questions[qIdx].options[questions[qIdx].correctIndex],
              isDelete: true,
              reason: 'External AI প্রশ্নটি বাদ দেওয়ার পরামর্শ দিয়েছে',
            ),
          );
          continue;
        }
      }

      var match = directPattern.firstMatch(line);
      String? reason;
      if (match != null) {
        reason = match.group(3)?.trim();
      } else {
        match = qPattern.firstMatch(line);
      }

      if (match != null) {
        final qNumStr = match.group(1)!;
        final optChar = match.group(2)!;
        final qNum =
            int.tryParse(BengaliMathSanitizer.toEnglishDigits(qNumStr)) ?? 0;
        final qIdx = qNum - 1;
        final optIdx = optionCharToIndex(optChar);

        if (qIdx >= 0 &&
            qIdx < questions.length &&
            optIdx != null &&
            optIdx < questions[qIdx].options.length) {
          if (optIdx != questions[qIdx].correctIndex) {
            items.add(
              QuestionCorrectionItem(
                questionIndex: qIdx,
                questionSnippet: questions[qIdx].questionText,
                proposedCorrectIndex: optIdx,
                proposedOptionText: questions[qIdx].options[optIdx],
                oldOptionText:
                    questions[qIdx].options[questions[qIdx].correctIndex],
                isDelete: false,
                reason: reason != null && reason.isNotEmpty
                    ? reason
                    : 'External AI উত্তর পরিবর্তন করার পরামর্শ দিয়েছে',
              ),
            );
          }
        }
      }
    }

    return items;
  }

  /// Applies selected corrections to an in-memory list of questions.
  List<QuizQuestion> applyCorrectionsToQuestions({
    required List<QuizQuestion> questions,
    required List<QuestionCorrectionItem> corrections,
  }) {
    final updatedList = List<QuizQuestion>.from(questions);
    final deleteIndices = <int>{};

    for (final item in corrections) {
      if (!item.isSelected) continue;
      if (item.questionIndex < 0 || item.questionIndex >= updatedList.length) {
        continue;
      }

      if (item.isDelete) {
        deleteIndices.add(item.questionIndex);
        continue;
      }

      final oldQ = updatedList[item.questionIndex];

      // The analysis may fix the question itself, not just where the answer
      // points -- a garbled question cannot be repaired by moving its tick.
      final options = item.newOptions ?? oldQ.options;
      final proposed = item.proposedCorrectIndex;
      final correctIndex =
          (proposed != null && proposed >= 0 && proposed < options.length)
          ? proposed
          : (oldQ.correctIndex < options.length ? oldQ.correctIndex : 0);

      if (item.newOptions == null &&
          item.newQuestionText == null &&
          proposed == null) {
        continue;
      }

      updatedList[item.questionIndex] = oldQ.copyWith(
        questionText: item.newQuestionText ?? oldQ.questionText,
        options: options,
        correctIndex: correctIndex,
        // A row the analysis rewrote is readable again by definition, and
        // its answer now rests on that analysis rather than on a guess.
        legible: item.rewritesQuestion ? true : oldQ.legible,
        answerSource: proposed != null || item.rewritesQuestion
            ? AnswerSource.solved
            : oldQ.answerSource,
        explanation: item.reason.isNotEmpty
            ? '${oldQ.explanation.isNotEmpty ? "${oldQ.explanation} • " : ""}${item.reason}'
            : oldQ.explanation,
      );
    }

    // Remove deleted questions from back to front to preserve indices
    final sortedDel = deleteIndices.toList()..sort((a, b) => b.compareTo(a));
    for (final idx in sortedDel) {
      if (idx >= 0 && idx < updatedList.length) {
        updatedList.removeAt(idx);
      }
    }

    return updatedList;
  }

  /// Applies corrections directly to a database exam schedule row by ID.
  Future<bool> applyCorrectionsToExam(
    AppDatabase db, {
    required int examId,
    required List<QuestionCorrectionItem> corrections,
  }) async {
    try {
      final exam = await (db.select(
        db.examSchedules,
      )..where((t) => t.id.equals(examId))).getSingleOrNull();
      if (exam == null || exam.resourceSummary == null) return false;

      final summary = exam.resourceSummary!.trim();
      if (!summary.startsWith('[')) return false;

      final decoded = jsonDecode(summary);
      if (decoded is! List) return false;

      final questions = decoded
          .map((e) => QuizQuestion.fromJson(e as Map<String, dynamic>))
          .toList();

      final updatedQuestions = applyCorrectionsToQuestions(
        questions: questions,
        corrections: corrections,
      );

      final newSummary = jsonEncode(
        updatedQuestions.map((q) => q.toJson()).toList(),
      );

      await (db.update(db.examSchedules)..where((t) => t.id.equals(examId)))
          .write(ExamSchedulesCompanion(resourceSummary: Value(newSummary)));

      // Synchronize changes to any matching DrillQuestions (Mistake Notebook)
      for (final item in corrections) {
        if (!item.isSelected) continue;
        if (item.questionIndex < 0 || item.questionIndex >= questions.length) {
          continue;
        }
        final q = questions[item.questionIndex];

        final matchingRows = await (db.select(
          db.drillQuestions,
        )..where((t) => t.questionText.equals(q.questionText))).get();

        for (final row in matchingRows) {
          if (item.isDelete) {
            await (db.delete(
              db.drillQuestions,
            )..where((t) => t.id.equals(row.id))).go();
          } else if (item.proposedCorrectIndex != null) {
            await db.acceptAnswerCorrection(
              row.id,
              correctedIndex: item.proposedCorrectIndex!,
              correctedExplanation: item.reason.isNotEmpty
                  ? '${row.explanation.isNotEmpty ? "${row.explanation} • " : ""}${item.reason}'
                  : row.explanation,
            );
          }
        }
      }

      return true;
    } catch (e) {
      debugPrint('Error applying batch corrections to exam #$examId: $e');
      return false;
    }
  }

  /// Applies corrections directly to a list of Mistake Notebook questions (DrillQuestion).
  Future<bool> applyCorrectionsToMistakeQuestions(
    AppDatabase db, {
    required List<DrillQuestion> drillQuestions,
    required List<QuestionCorrectionItem> corrections,
  }) async {
    try {
      for (final item in corrections) {
        if (!item.isSelected) continue;
        if (item.questionIndex < 0 ||
            item.questionIndex >= drillQuestions.length) {
          continue;
        }
        final dq = drillQuestions[item.questionIndex];

        if (item.isDelete) {
          await (db.delete(
            db.drillQuestions,
          )..where((t) => t.id.equals(dq.id))).go();
        } else if (item.proposedCorrectIndex != null) {
          await db.acceptAnswerCorrection(
            dq.id,
            correctedIndex: item.proposedCorrectIndex!,
            correctedExplanation: item.reason.isNotEmpty
                ? '${dq.explanation.isNotEmpty ? "${dq.explanation} • " : ""}${item.reason}'
                : dq.explanation,
          );
        }
      }
      return true;
    } catch (e) {
      debugPrint('Error applying batch corrections to mistake questions: $e');
      return false;
    }
  }
}
