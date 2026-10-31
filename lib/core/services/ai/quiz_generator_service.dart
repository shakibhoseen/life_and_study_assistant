import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/notification_constants.dart';
import '../../utils/bengali_math_sanitizer.dart';
import 'gemini_usage_tracker.dart';
import 'models/quiz_question.dart';

/// A drill that could not be built.
///
/// It replaces a fallback that invented questions. For a topic it recognised
/// the fallback served a canned MCQ; for anything else it generated placeholder
/// questions — "[বিষয় - টপিক] সংক্রান্ত প্রস্তুতিমূলক প্রশ্ন #১" with options
/// like "মূল সংজ্ঞা ও প্রাথমিক বৈশিষ্ট্য" and a correct answer chosen at
/// random. Those were scored, written to the drill record, and a wrong answer
/// landed in the mistake notebook, so a failed call quietly taught nothing and
/// corrupted the record of what the user is weak at.
class QuizGenerationException implements Exception {
  /// Shown to the user as it is.
  final String userMessage;

  const QuizGenerationException(this.userMessage);

  @override
  String toString() => 'QuizGenerationException: $userMessage';
}

class QuizGeneratorService {
  QuizGeneratorService._();
  static final QuizGeneratorService instance = QuizGeneratorService._();

  Future<List<QuizQuestion>> generateQuiz({
    required String topic,
    required String subject,
    int count = 5,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString(NotificationConstants.prefGeminiApiKey);

    if (apiKey == null || apiKey.isEmpty) {
      throw const QuizGenerationException(
        'Gemini API কী বসানো নেই। সেটিংসে কী দিন, তারপর আবার চেষ্টা করুন।',
      );
    }

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
4. Clean Unicode: Never use raw LaTeX syntax (e.g. Do NOT write '\$180^\\circ\$', '\\to', or '\$x^2\$'). Use native Unicode: '°' (১৮০°), '→', '×', '²', '³', '√'.
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

    final modelsToTry = [
      'gemini-flash-lite-latest',
      'gemini-3.5-flash-lite',
      'gemini-flash-latest',
    ];

    Object? lastError;
    for (final modelName in modelsToTry) {
      try {
        final model = GenerativeModel(
          model: modelName,
          apiKey: apiKey,
          generationConfig: GenerationConfig(
            responseMimeType: 'application/json',
            temperature: 0.2,
            maxOutputTokens: 2048,
          ),
        );

        final response = await model.generateContent([Content.text(prompt)]);
        final rawText = response.text?.trim() ?? '';

        if (rawText.isNotEmpty) {
          final cleanJson = _extractCleanJson(rawText);
          final decoded = jsonDecode(cleanJson);
          if (decoded is List) {
            final questions = decoded.map((e) {
              final q = QuizQuestion.fromJson(e as Map<String, dynamic>);
              return QuizQuestion(
                questionText: BengaliMathSanitizer.sanitize(q.questionText),
                options: q.options
                    .map((opt) => BengaliMathSanitizer.sanitize(opt))
                    .toList(),
                correctIndex: q.correctIndex,
                explanation: BengaliMathSanitizer.sanitize(q.explanation),
                subject: q.subject,
              );
            }).toList();
            if (questions.isNotEmpty) {
              final hasMetadata =
                  response.usageMetadata?.totalTokenCount != null;
              await GeminiUsageTracker.instance.recordSuccess(
                tokens:
                    response.usageMetadata?.totalTokenCount ??
                    (questions.length * 80),
                actualInputTokens: response.usageMetadata?.promptTokenCount,
                actualOutputTokens:
                    response.usageMetadata?.candidatesTokenCount,
                actualTotalTokens: response.usageMetadata?.totalTokenCount,
                isEstimated: !hasMetadata,
                operation: 'quick_quiz_drill',
                model: modelName,
              );
              return questions;
            }
          }
        }
      } catch (e) {
        debugPrint('QuizGeneratorService error with $modelName: $e');
        lastError = e;
      }
    }

    debugPrint('Quiz generation failed for "$topic": $lastError');
    throw const QuizGenerationException(
      'প্রশ্ন তৈরি করা গেল না। ইন্টারনেট দেখে আবার চেষ্টা করুন।',
    );
  }

  String _extractCleanJson(String raw) {
    var text = raw.trim();
    if (text.startsWith('```json')) {
      text = text.substring(7);
    } else if (text.startsWith('```')) {
      text = text.substring(3);
    }
    if (text.endsWith('```')) {
      text = text.substring(0, text.length - 3);
    }
    return text.trim();
  }
}
