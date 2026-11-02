import 'dart:convert';
import 'dart:math' as math;
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

/// A study sheet that could not be read.
///
/// It replaces a fallback that answered every failure with the same page: a
/// title made from the user's filename, three English placeholder points,
/// and সমাস rules and MCQs that had nothing to do with the photo. A page on
/// any subject came back as Bengali grammar, and it read like a successful
/// scan, so there was no way to tell the model had never seen it.
class StudySheetReadException implements Exception {
  /// Shown to the user as it is.
  final String userMessage;

  const StudySheetReadException(this.userMessage);

  @override
  String toString() => 'StudySheetReadException: $userMessage';
}

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
  /// What the last call actually cost, once the model has reported it.
  ///
  /// Null until a call returns. During the wait only an estimate exists,
  /// because a non-streaming call says nothing about its cost until it is
  /// finished.
  int? lastCallTokens;

  /// A rough cost for a call that has not been made yet, so a wait can show
  /// what it is spending rather than only that it is spending.
  int estimateTokensFor(CaptureDetail detail) => estimateRequestTokens(
    promptChars: _visionPrompt.length,
    image: detail,
    // Measured on a real page: 3199 tokens in all, of which about 1200 were
    // the prompt and image. The rest is the reply plus the reasoning that
    // precedes it, and the reasoning is the larger part — a streamed run
    // showed roughly a thousand tokens spent before the first word.
    expectedOutputTokens: 2000,
  );

  /// [onTokens] is called with the running total while the reply streams.
  ///
  /// Measured against the API: a streaming call reports usage on every chunk,
  /// and the total climbs as the reply is written. It stands still for the
  /// first stretch, because the model reasons before it writes anything —
  /// about a hundred seconds in one measured run, with roughly a thousand
  /// tokens already spent by the time the first words appeared. So the figure
  /// is real rather than guessed, and when it starts moving the user is
  /// watching the reply being written.
  Future<StudySheetResult> analyzeStudySheet(
    File imageFile, {
    String? subjectHint,
    CaptureDetail detail = CaptureDetail.standard,
    void Function(int tokensSoFar)? onTokens,
  }) async {
    await init();
    final activeModel = _modelName ?? 'gemini-flash-latest';
    Object? lastError;
    lastCallTokens = null;

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

        final buffer = StringBuffer();
        int promptTokens = 0;
        int outputTokens = 0;
        int totalTokens = 0;

        await for (final chunk in _model!.generateContentStream(content)) {
          buffer.write(chunk.text ?? '');
          final usage = chunk.usageMetadata;
          // Each chunk reports the running totals, not its own share, so the
          // highest seen is the figure to keep.
          promptTokens = math.max(promptTokens, usage?.promptTokenCount ?? 0);
          outputTokens = math.max(
            outputTokens,
            usage?.candidatesTokenCount ?? 0,
          );
          final chunkTotal = usage?.totalTokenCount ?? 0;
          if (chunkTotal > totalTokens) {
            totalTokens = chunkTotal;
            onTokens?.call(totalTokens);
          }
        }

        lastCallTokens = totalTokens > 0 ? totalTokens : null;
        await GeminiUsageTracker.instance.recordSuccess(
          tokens: totalTokens,
          actualInputTokens: promptTokens > 0 ? promptTokens : null,
          actualOutputTokens: outputTokens > 0 ? outputTokens : null,
          actualTotalTokens: totalTokens > 0 ? totalTokens : null,
          operation: 'study_sheet_ocr',
          model: activeModel,
        );

        final rawText = buffer.toString();
        final result = _decodeResponse(
          rawText,
          rawRef: 'Image: ${imageFile.path.split('/').last}',
          fallbackSubject: subjectHint,
        );
        if (result != null && rawText.isNotEmpty) {
          await GeminiResultCache.instance.put(cacheKey, rawText);
          return result;
        }
      } catch (e) {
        debugPrint('Gemini StudySheet Vision analysis error: $e');
        lastError = e;
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

    final reason = lastError?.toString() ?? '';
    if (reason.contains('503') || reason.contains('UNAVAILABLE')) {
      throw const StudySheetReadException(
        'Gemini সার্ভার এখন ব্যস্ত (৫০৩)। একটু পরে আবার চেষ্টা করুন — '
        'ছবিটা এখানেই আছে।',
      );
    }
    if (reason.contains('429') || reason.toLowerCase().contains('quota')) {
      throw const StudySheetReadException(
        'আজকের কোটা শেষ। কাল আবার চেষ্টা করুন।',
      );
    }
    throw const StudySheetReadException(
      'পাতাটা পড়া গেল না। ইন্টারনেট দেখে আবার চেষ্টা করুন — '
      'ছবিটা এখানেই আছে।',
    );
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
}
