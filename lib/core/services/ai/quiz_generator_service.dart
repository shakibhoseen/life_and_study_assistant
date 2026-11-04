import 'dart:convert';
import 'dart:math' as math;

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
    void Function(int tokens)? onTokens,
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

    // Respect the user's selected Gemini model from Settings.
    // Defaults to 'gemini-flash-lite-latest' (Fastest & 100% Free - Recommended).
    final savedModel =
        prefs.getString(NotificationConstants.prefGeminiModel) ??
        'gemini-flash-lite-latest';
    final primaryModel = [
      'gemini-flash-lite-latest',
      'gemini-flash-latest',
      'gemini-pro-latest',
    ].contains(savedModel)
        ? savedModel
        : 'gemini-flash-lite-latest';

    final modelsToTry = [
      primaryModel,
      if (primaryModel != 'gemini-flash-lite-latest')
        'gemini-flash-lite-latest',
      if (primaryModel != 'gemini-flash-latest')
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
          ),
        );

        final buffer = StringBuffer();
        int promptTokens = 0;
        int outputTokens = 0;
        int totalTokens = 0;
        int lastReportedTokens = 0;

        await for (final chunk in model.generateContentStream([
          Content.text(prompt),
        ])) {
          final text = chunk.text ?? '';
          buffer.write(text);

          final usage = chunk.usageMetadata;
          if (usage != null) {
            promptTokens = math.max(promptTokens, usage.promptTokenCount ?? 0);
            outputTokens = math.max(
              outputTokens,
              usage.candidatesTokenCount ?? 0,
            );
            totalTokens = math.max(totalTokens, usage.totalTokenCount ?? 0);
          }

          if (totalTokens > lastReportedTokens) {
            lastReportedTokens = totalTokens;
          } else {
            // Live approximation as chunks flow in:
            // ~120 prompt tokens + approx output characters / 3.5
            final approxOut = (buffer.length / 3.5).round();
            final approxTotal =
                (promptTokens > 0 ? promptTokens : 120) + approxOut;
            if (approxTotal > lastReportedTokens) {
              lastReportedTokens = approxTotal;
            }
          }
          onTokens?.call(lastReportedTokens);
        }

        final rawText = buffer.toString().trim();

        if (rawText.isNotEmpty) {
          final questions = _parseQuestions(rawText);
          if (questions.isNotEmpty) {
            final hasMetadata = totalTokens > 0;
            await GeminiUsageTracker.instance.recordSuccess(
              tokens: totalTokens > 0 ? totalTokens : (questions.length * 80),
              actualInputTokens: promptTokens > 0 ? promptTokens : null,
              actualOutputTokens: outputTokens > 0 ? outputTokens : null,
              actualTotalTokens: totalTokens > 0 ? totalTokens : null,
              isEstimated: !hasMetadata,
              operation: 'quick_quiz_drill',
              model: modelName,
            );
            return questions;
          }
        }
      } catch (e) {
        debugPrint('QuizGeneratorService error with $modelName: $e');
        lastError = e;
      }
    }

    debugPrint('Quiz generation failed for "$topic": $lastError');
    throw QuizGenerationException(_diagnoseError(lastError));
  }

  List<QuizQuestion> _parseQuestions(String rawText) {
    final cleanJson = _extractCleanJson(rawText);
    try {
      final decoded = jsonDecode(cleanJson);
      if (decoded is List) {
        return _mapJsonListToQuestions(decoded);
      }
    } catch (_) {
      // If direct jsonDecode failed (e.g. slight formatting anomaly),
      // scan and recover all individual complete question objects.
      final recovered = _recoverIndividualQuestions(cleanJson);
      if (recovered.isNotEmpty) return recovered;
    }
    return [];
  }

  List<QuizQuestion> _mapJsonListToQuestions(List<dynamic> list) {
    return list.map((e) {
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
  }

  List<QuizQuestion> _recoverIndividualQuestions(String text) {
    final questions = <QuizQuestion>[];
    final regex = RegExp(
      r'\{[^{}]*"question"[^{}]*"options"[^{}]*\}',
      dotAll: true,
    );
    for (final match in regex.allMatches(text)) {
      try {
        final decoded = jsonDecode(match.group(0)!);
        if (decoded is Map<String, dynamic>) {
          final q = QuizQuestion.fromJson(decoded);
          questions.add(
            QuizQuestion(
              questionText: BengaliMathSanitizer.sanitize(q.questionText),
              options: q.options
                  .map((opt) => BengaliMathSanitizer.sanitize(opt))
                  .toList(),
              correctIndex: q.correctIndex,
              explanation: BengaliMathSanitizer.sanitize(q.explanation),
              subject: q.subject,
            ),
          );
        }
      } catch (_) {}
    }
    return questions;
  }

  String _diagnoseError(Object? error) {
    if (error == null) {
      return 'প্রশ্ন তৈরি করা গেল না। ইন্টারনেট সংযোগ দেখে আবার চেষ্টা করুন।';
    }
    final str = error.toString().toLowerCase();
    if (str.contains('503') ||
        str.contains('overloaded') ||
        str.contains('unavailable')) {
      return 'Gemini সার্ভার বর্তমানে ব্যস্ত (503)। কয়েক সেকেন্ড পর আবার চেষ্টা করুন।';
    }
    if (str.contains('429') ||
        str.contains('resourceexhausted') ||
        str.contains('quota')) {
      return 'Gemini API ফ্রি রিকোয়েস্ট সীমা সাময়িকভাবে পূর্ণ (429)। এক মিনিট পর আবার চেষ্টা করুন।';
    }
    if (str.contains('socketexception') ||
        str.contains('network is unreachable') ||
        str.contains('failed host lookup') ||
        str.contains('clientexception')) {
      return 'ইন্টারনেট সংযোগ পাওয়া যায়নি। ফোনের Wi-Fi বা মোবাইল ডেটা চেক করুন।';
    }
    if (str.contains('api_key_invalid') ||
        str.contains('api key not valid')) {
      return 'Gemini API কী সঠিক নয়। সেটিংসে গিয়ে নতুন কী দিন।';
    }
    return 'প্রশ্ন তৈরি করা সম্ভব হয়নি (${error.runtimeType})। আবার চেষ্টা করুন।';
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
