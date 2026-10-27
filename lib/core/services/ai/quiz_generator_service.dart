import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/notification_constants.dart';
import '../../utils/bengali_math_sanitizer.dart';
import 'gemini_usage_tracker.dart';
import 'models/quiz_question.dart';

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
      debugPrint(
        'No API Key for QuizGeneratorService, using offline fallback.',
      );
      return _generateOfflineFallbackQuiz(
        topic: topic,
        subject: subject,
        count: count,
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
      }
    }

    return _generateOfflineFallbackQuiz(
      topic: topic,
      subject: subject,
      count: count,
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

  List<QuizQuestion> _generateOfflineFallbackQuiz({
    required String topic,
    required String subject,
    int count = 5,
  }) {
    final lower = topic.toLowerCase();
    if (lower.contains('কারক') || lower.contains('বিভক্তি')) {
      return const [
        QuizQuestion(
          questionText: '‘পাপে বিরত হও’ — ‘পাপে’ কোন কারকে কোন বিভক্তি?',
          options: [
            'ক. কর্মে ৭মী',
            'খ. অপাদানে ৭মী',
            'খ. করণে ৭মী',
            'ঘ. অধিকরণে ৭মী',
          ],
          correctIndex: 1,
          explanation: 'যা থেকে কিছু চ্যুত, চলিত, ভীত বা নিবৃত্ত/বিরত হয়, তাকে অপাদান কারক বলে। ‘পাপে’ অপাদানে ৭মী।',
          subject: 'বাংলা ব্যাকরণ',
        ),
        QuizQuestion(
          questionText: '‘ঘোড়াকে চাবুক মার’ — ‘চাবুক’ কোন কারক?',
          options: [
            'ক. কর্ম কারক',
            'খ. করণ কারক',
            'গ. অপাদান কারক',
            'ঘ. ভাবাধিকরণ',
          ],
          correctIndex: 1,
          explanation: 'ক্রিয়া সম্পাদনের যন্ত্র, সহায়ক বা উপায়কে করণ কারক বলে। চাবুক দ্বারা মারা হচ্ছে, তাই করণ কারক।',
          subject: 'বাংলা ব্যাকরণ',
        ),
        QuizQuestion(
          questionText: '‘তিলে তৈল হয়’ — এখানে ‘তিলে’ কোন কারক?',
          options: [
            'ক. অধিকরণ কারক',
            'খ. অপাদান কারক',
            'গ. করণ কারক',
            'ঘ. কর্ম কারক',
          ],
          correctIndex: 1,
          explanation: 'তিল থেকে তেল উৎপন্ন বা জাত হয়, তাই এটি অপাদান কারক (তিলে তৈল আছে হলে অধিকরণ হতো)।',
          subject: 'বাংলা ব্যাকরণ',
        ),
        QuizQuestion(
          questionText:
              '‘সূর্যোদয়ে অন্ধকার দূরীভূত হয়’ — ‘সূর্যোদয়ে’ কোন কারক?',
          options: [
            'ক. কালাধিকরণ',
            'খ. আধারাধিকরণ',
            'গ. ভাবাধিকরণ',
            'ঘ. বৈষয়িক অধিকরণ',
          ],
          correctIndex: 2,
          explanation: 'একটি ক্রিয়ার প্রকাশে অন্য ক্রিয়া সম্পন্ন হলে তাকে ভাবাধিকরণ (বা ভাবে সপ্তমী) বলে।',
          subject: 'বাংলা ব্যাকরণ',
        ),
        QuizQuestion(
          questionText: '‘রাজায় রাজায় যুদ্ধ, উলুখাগড়ার প্রাণান্ত’ — ‘রাজায় রাজায়’ কোন ধরণের কর্তা?',
          options: [
            'ক. প্রযোজক কর্তা',
            'খ. ব্যতিহার কর্তা',
            'গ. মুখ্য কর্তা',
            'ঘ. কর্মবাচ্যের কর্তা',
          ],
          correctIndex: 1,
          explanation: 'দুটো কর্তা যখন একই সাথে পরস্পরের বিরুদ্ধে কাজ করে, তখন তাকে ব্যতিহার কর্তা বলে।',
          subject: 'বাংলা ব্যাকরণ',
        ),
      ];
    } else if (lower.contains('সমাস')) {
      return const [
        QuizQuestion(
          questionText: '‘জায় ও পতি’ = ‘দম্পতি’ — এটি কোন সমাসের উদাহরণ?',
          options: [
            'ক. বহুব্রীহি',
            'খ. দ্বন্দ্ব',
            'গ. কর্মধারয়',
            'ঘ. তৎপুরুষ',
          ],
          correctIndex: 1,
          explanation: 'যে সমাসে উভয় পদের অর্থের প্রাধান্য বজায় থাকে, তাকে দ্বন্দ্ব সমাস বলে।',
          subject: 'বাংলা ব্যাকরণ',
        ),
        QuizQuestion(
          questionText: '‘নীল যে অম্বর’ = ‘নীলাম্বর’ — এটি কোন সমাস?',
          options: [
            'ক. মধ্যপদলোপী কর্মধারয়',
            'খ. সাধারণ কর্মধারয়',
            'গ. বহুব্রীহি',
            'ঘ. দ্বিগু',
          ],
          correctIndex: 1,
          explanation: 'বিশেষ্য ও বিশেষণের সমন্বয়ে যে সমাস হয় এবং পরপদের অর্থ প্রধান থাকে, তা কর্মধারয় সমাস।',
          subject: 'বাংলা ব্যাকরণ',
        ),
        QuizQuestion(
          questionText: '‘উপকণ্ঠ’ শব্দটির সঠিক ব্যাসবাক্য কোনটি?',
          options: [
            'ক. কণ্ঠের সদৃশ',
            'খ. কণ্ঠের সমীপে',
            'গ. কণ্ঠকে অতিক্রম না করে',
            'ঘ. কণ্ঠের পশ্চাৎ',
          ],
          correctIndex: 1,
          explanation:
              '‘উপকণ্ঠ’ অব্যয়ীভাব সমাস, যার ব্যাসবাক্য হলো ‘কণ্ঠের সমীপে’।',
          subject: 'বাংলা ব্যাকরণ',
        ),
      ];
    }

    // Generic high-yield fallback questions
    return List.generate(count, (index) {
      return QuizQuestion(
        questionText:
            '[$subject - $topic] সংক্রান্ত প্রস্তুতিমূলক প্রশ্ন #${index + 1}: বিগত বিসিএস পরীক্ষায় নিচের কোন তথ্যটি প্রায়ই আসে?',
        options: [
          'ক. মূল সংজ্ঞা ও প্রাথমিক বৈশিষ্ট্য',
          'খ. ব্যতিক্রমী সূত্র ও প্রয়োগ (High-Yield)',
          'গ. ইতিহাস ও সূচনা পর্ব',
          'ঘ. অপ্রচলিত তাত্ত্বিক বিশ্লেষণ',
        ],
        correctIndex: 1,
        explanation: 'বিসিএস ও লাইভএমসিকিউ পরীক্ষায় সাধারণ তথ্যের চেয়ে ব্যতিক্রমী নিয়ম ও সাম্প্রতিক প্রয়োগ থেকে সর্বোচ্চ প্রশ্ন আসে।',
        subject: subject,
      );
    });
  }
}
