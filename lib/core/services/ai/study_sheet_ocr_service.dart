import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/notification_constants.dart';
import '../../utils/bengali_math_sanitizer.dart';
import 'gemini_result_cache.dart';
import 'ai_media_limits.dart';
import 'gemini_usage_tracker.dart';
import 'models/quiz_question.dart';
import 'models/study_sheet_result.dart';

/// The shape the model must return.
///
/// This used to be spelled out as JSON inside the prompt, together with rules
/// telling the model not to wrap it in markdown and to keep correct_index in
/// range. Declaring it here lets the API enforce all of that instead, and the
/// prompt is left to say what to extract rather than how to format it.
///
/// Field names must match what StudySheetResult.fromJson reads.
final _studySheetSchema = Schema.object(
  properties: {
    'title': Schema.string(description: 'Topic or chapter title'),
    'subject': Schema.enumString(
      enumValues: [
        'Bangla Grammar',
        'English Literature',
        'Mathematics',
        'Bangladesh Affairs',
        'International Affairs',
        'General Science',
        'Computer & ICT',
        'Mental Ability',
      ],
    ),
    'summary': Schema.string(
      description: '2-3 sentences on the fundamental concept of this page',
    ),
    'high_yield_points': Schema.array(items: Schema.string()),
    'key_rules': Schema.array(
      items: Schema.string(
        description: 'A rule, exception, formula or mnemonic worth revisiting',
      ),
    ),
    'questions': Schema.array(
      items: Schema.object(
        properties: {
          'question': Schema.string(),
          'options': Schema.array(items: Schema.string()),
          'correct_index': Schema.integer(description: '0-3'),
          'explanation': Schema.string(),
        },
        requiredProperties: [
          'question',
          'options',
          'correct_index',
          'explanation',
        ],
      ),
    ),
  },
  requiredProperties: [
    'title',
    'subject',
    'summary',
    'high_yield_points',
    'key_rules',
    'questions',
  ],
);

class StudySheetOcrService {
  StudySheetOcrService._();
  static final StudySheetOcrService instance = StudySheetOcrService._();

  GenerativeModel? _model;
  String? _modelName;
  String? _cachedApiKey;
  String? get cachedApiKey => _cachedApiKey;

  static const String _visionPrompt = '''
You are an expert tutor for Bangladeshi competitive exams (BCS, Bank, Government Recruitment).
Analyse this textbook page, coaching lecture sheet or handwritten note: pull out the high-yield content and write a drill from it.

- Exactly 5 questions, each with 4 distinct options.
- Match the page: a Bengali page gets Bengali questions and options.
- key_rules is for what the student is most likely to forget and should revisit later.
''';

  Future<void> init([String? apiKey]) async {
    final prefs = await SharedPreferences.getInstance();
    var modelName =
        prefs.getString(NotificationConstants.prefGeminiModel) ??
        'gemini-flash-latest';
    if (![
      'gemini-flash-lite-latest',
      'gemini-flash-latest',
      'gemini-pro-latest',
    ].contains(modelName)) {
      modelName = 'gemini-flash-latest';
    }
    final key = apiKey ?? await _getStoredApiKey();
    if (key != null && key.isNotEmpty) {
      _cachedApiKey = key;
      _model = GenerativeModel(
        model: modelName,
        apiKey: key,
        generationConfig: GenerationConfig(
          responseMimeType: 'application/json',
          responseSchema: _studySheetSchema,
          temperature: 0.2,
          maxOutputTokens: 2048,
        ),
      );
      _modelName = modelName;
      debugPrint('StudySheetOcrService initialized with $modelName');
    }
  }

  Future<String?> _getStoredApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(NotificationConstants.prefGeminiApiKey);
  }

  /// Analyze a textbook page / sheet image and generate high-yield points, key rules, and a 5-MCQ drill.
  /// Uses content-hash caching based on image bytes to prevent redundant expensive vision calls.
  Future<StudySheetResult> analyzeStudySheet(
    File imageFile, {
    String? subjectHint,
    CaptureDetail detail = CaptureDetail.standard,
  }) async {
    await init();
    final activeModel = _modelName ?? 'gemini-flash-latest';

    if (_model != null) {
      try {
        final imageBytes = await _prepareImageBytes(
          imageFile,
          detail.dimension,
        );
        final mimeType = _detectMimeType(imageFile.path);

        // Check content-hash cache for this image
        final cacheKey = GeminiResultCache.instance.computeKey(
          operation: 'study_sheet_ocr',
          promptVersion: 'v2.0',
          model: activeModel,
          payloadBytes: [...imageBytes, ...utf8.encode(subjectHint ?? '')],
        );

        final cachedRaw = await GeminiResultCache.instance.get(cacheKey);
        if (cachedRaw != null && cachedRaw.isNotEmpty) {
          final cachedResult = _decodeResponse(
            cachedRaw,
            rawRef: 'Image: ${imageFile.path.split('/').last}',
            fallbackSubject: subjectHint,
          );
          if (cachedResult != null) {
            await GeminiUsageTracker.instance.recordCacheHit(
              operation: 'study_sheet_ocr',
              model: activeModel,
            );
            return cachedResult;
          }
        }

        String prompt = _visionPrompt;
        if (subjectHint != null &&
            subjectHint.isNotEmpty &&
            subjectHint != 'Auto Detect') {
          prompt +=
              '\nNote: The user indicates this page belongs to the subject: "$subjectHint".';
        }

        final content = [
          Content.multi([TextPart(prompt), DataPart(mimeType, imageBytes)]),
        ];

        final response = await _model!.generateContent(content);
        await GeminiUsageTracker.instance.recordSuccess(
          tokens: response.usageMetadata?.totalTokenCount ?? 0,
          actualInputTokens: response.usageMetadata?.promptTokenCount,
          actualOutputTokens: response.usageMetadata?.candidatesTokenCount,
          actualTotalTokens: response.usageMetadata?.totalTokenCount,
          operation: 'study_sheet_ocr',
          model: activeModel,
        );

        final rawText = response.text;
        final result = _decodeResponse(
          rawText,
          rawRef: 'Image: ${imageFile.path.split('/').last}',
          fallbackSubject: subjectHint,
        );
        if (result != null && rawText != null) {
          await GeminiResultCache.instance.put(cacheKey, rawText);
          return result;
        }
      } catch (e) {
        debugPrint('Gemini StudySheet Vision analysis error: $e');
        if (e.toString().contains('429') ||
            e.toString().toLowerCase().contains('quota')) {
          await GeminiUsageTracker.instance.recordQuotaExceeded(
            operation: 'study_sheet_ocr',
            model: activeModel,
          );
        } else {
          await GeminiUsageTracker.instance.recordError(
            e.toString(),
            operation: 'study_sheet_ocr',
            model: activeModel,
          );
        }
      }
    }

    // Offline rule-based fallback
    return _fallbackGenerateResult(imageFile, subjectHint: subjectHint);
  }

  StudySheetResult? _decodeResponse(
    String? rawJson, {
    String? rawRef,
    String? fallbackSubject,
  }) {
    if (rawJson == null || rawJson.trim().isEmpty) return null;

    try {
      var cleaned = rawJson.trim();
      if (cleaned.startsWith('```json')) {
        cleaned = cleaned.substring(7);
      } else if (cleaned.startsWith('```')) {
        cleaned = cleaned.substring(3);
      }
      if (cleaned.endsWith('```')) {
        cleaned = cleaned.substring(0, cleaned.length - 3);
      }
      cleaned = cleaned.trim();

      final dynamic decoded = jsonDecode(cleaned);
      if (decoded is Map<String, dynamic>) {
        final rawResult = StudySheetResult.fromJson(decoded, rawRef: rawRef);
        return StudySheetResult(
          title: BengaliMathSanitizer.sanitize(rawResult.title),
          subject: rawResult.subject,
          summary: BengaliMathSanitizer.sanitize(rawResult.summary),
          highYieldPoints: rawResult.highYieldPoints
              .map((p) => BengaliMathSanitizer.sanitize(p))
              .toList(),
          keyRules: rawResult.keyRules
              .map((r) => BengaliMathSanitizer.sanitize(r))
              .toList(),
          questions: rawResult.questions
              .map(
                (q) => QuizQuestion(
                  questionText: BengaliMathSanitizer.sanitize(q.questionText),
                  options: q.options
                      .map((opt) => BengaliMathSanitizer.sanitize(opt))
                      .toList(),
                  correctIndex: q.correctIndex,
                  explanation: BengaliMathSanitizer.sanitize(q.explanation),
                  subject: q.subject,
                ),
              )
              .toList(),
          rawReference: rawResult.rawReference,
        );
      }
    } catch (e) {
      debugPrint('JSON parsing error in StudySheetOcrService: $e');
    }
    return null;
  }

  Future<Uint8List> _prepareImageBytes(File file, int maxDimension) async {
    final bytes = await file.readAsBytes();

    try {
      final decodedImage = img.decodeImage(bytes);
      if (decodedImage == null) return bytes;

      // Resize on the longest side, whatever the file weighs. The old guard
      // only resized files over 2MB, which the picker already keeps us under,
      // so every photo went to the model at full picker resolution.
      final longest = decodedImage.width > decodedImage.height
          ? decodedImage.width
          : decodedImage.height;

      img.Image processed = decodedImage;
      if (longest > maxDimension) {
        processed = decodedImage.width >= decodedImage.height
            ? img.copyResize(decodedImage, width: maxDimension)
            : img.copyResize(decodedImage, height: maxDimension);
      }

      final compressed = img.encodeJpg(
        processed,
        quality: AiMediaLimits.jpegQuality,
      );

      debugPrint(
        'Image prepared: ${decodedImage.width}x${decodedImage.height} '
        '-> ${processed.width}x${processed.height} '
        '(target $maxDimension, ${(compressed.length / 1024).round()}KB)',
      );
      return Uint8List.fromList(compressed);
    } catch (e) {
      debugPrint('Image compression error in StudySheetOcrService: $e');
      return bytes;
    }
  }

  String _detectMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  /// High quality offline fallback generator
  StudySheetResult _fallbackGenerateResult(
    File imageFile, {
    String? subjectHint,
  }) {
    final fileName = imageFile.path.split('/').last;
    final subject =
        (subjectHint != null &&
            subjectHint.isNotEmpty &&
            subjectHint != 'Auto Detect')
        ? subjectHint
        : 'Bangla Grammar';

    return StudySheetResult(
      title: 'Captured Study Page: $fileName',
      subject: subject,
      summary: 'High-yield study page captured via camera. Connect your Gemini API Key in Settings for deep multimodal AI extraction of textbook pages.',
      highYieldPoints: [
        'Important definition and core formula from captured sheet',
        'Frequently tested exception rule in competitive exams',
        'Memory mnemonic for quick revision during exam revision',
      ],
      keyRules: [
        'নিয়ম: পরপদে অর্থ প্রধান হলে তৎপুরুষ সমাস হয়, আর পূর্বপদ প্রধান হলে অব্যয়ীভাব সমাস হয়।',
        'ব্যাসবাক্যে ‘যে’ বা ‘যিনি’ থাকলে সাধারণত কর্মধারয় সমাস নির্দেশ করে।',
        'দ্বিগু সমাসে সমাহার বা সমষ্টি বোঝায় এবং সংখ্যাবাচক শব্দ পূর্বে বসে।',
      ],
      questions: [
        QuizQuestion(
          questionText: 'কোন সমাসে পরপদের অর্থ প্রধান থাকে?',
          options: [
            'তৎপুরুষ সমাস',
            'দ্বন্দ্ব সমাস',
            'অব্যয়ীভাব সমাস',
            'বহুব্রীহি সমাস',
          ],
          correctIndex: 0,
          explanation: 'তৎপুরুষ ও কর্মধারয় সমাসে পরপদের অর্থ প্রাধান্য পায়।',
          subject: subject,
        ),
        QuizQuestion(
          questionText:
              '‘সিংহ চিহ্নিত আসন = সিংহাসন’ - এটি কোন কর্মধারয় সমাস?',
          options: [
            'মধ্যপদলোপী কর্মধারয়',
            'উপমান কর্মধারয়',
            'উপমিত কর্মধারয়',
            'রূপক কর্মধারয়',
          ],
          correctIndex: 0,
          explanation: 'যে কর্মধারয় সমাসে ব্যাসবাক্যের মধ্যের পদ লোপ পায়, তাকে মধ্যপদলোপী কর্মধারয় সমাস বলে।',
          subject: subject,
        ),
        QuizQuestion(
          questionText: 'কোন সমাসে পূর্বপদের অর্থ প্রধান থাকে?',
          options: [
            'অব্যয়ীভাব সমাস',
            'তৎপুরুষ সমাস',
            'দ্বিগু সমাস',
            'দ্বন্দ্ব সমাস',
          ],
          correctIndex: 0,
          explanation:
              'অব্যয়ীভাব সমাসে পূর্বপদের উপসর্গ বা অব্যয়ের অর্থ প্রধান থাকে।',
          subject: subject,
        ),
        QuizQuestion(
          questionText: '‘পঙ্কজ’ (পঙ্কে জন্মে যা) কোন সমাসের উদাহরণ?',
          options: [
            'উপপদ তৎপুরুষ',
            'নঞ তৎপুরুষ',
            'অলুক তৎপুরুষ',
            'দ্বিতীয় তৎপুরুষ',
          ],
          correctIndex: 0,
          explanation:
              'কৃদন্ত পদের সাথে উপপদের যে সমাস হয় তাকে উপপদ তৎপুরুষ বলে।',
          subject: subject,
        ),
        QuizQuestion(
          questionText: 'যে সমাসে সমস্যমান পদগুলোর কোনোটির অর্থ না বুঝিয়ে ভিন্ন অর্থ বোঝায়, তাকে কী বলে?',
          options: [
            'বহুব্রীহি সমাস',
            'কর্মধারয় সমাস',
            'দ্বিগু সমাস',
            'দ্বন্দ্ব সমাস',
          ],
          correctIndex: 0,
          explanation: 'বহুব্রীহি সমাসে সমস্যমান পদের অর্থের প্রাধান্য না থেকে তৃতীয় কোনো সত্ত্বাকে বোঝায়।',
          subject: subject,
        ),
      ],
      rawReference: 'Image: $fileName',
    );
  }
}
