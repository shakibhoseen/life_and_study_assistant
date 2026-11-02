import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/notification_constants.dart';
import '../../utils/bengali_math_sanitizer.dart';
import 'ai_media_limits.dart';
import 'gemini_result_cache.dart';
import 'gemini_usage_tracker.dart';
import 'models/quiz_question.dart';
import 'models/question_bank_extract_result.dart';

final _questionBankSchema = Schema.object(
  properties: {
    'title': Schema.string(
      description: 'Concise topic or chapter title of this question bank page',
    ),
    'subject': Schema.string(
      description: 'Subject of these questions in Bengali (e.g. বাংলা ব্যাকরণ, বাংলাদেশ বিষয়াবলী, English Language)',
    ),
    'questions': Schema.array(
      items: Schema.object(
        properties: {
          'question': Schema.string(
            description: 'Full question text with question number if printed',
          ),
          'options': Schema.array(
            items: Schema.string(),
            description: 'List of exactly 4 distinct options',
          ),
          'correct_index': Schema.integer(
            description: '0-based index (0, 1, 2, or 3) of the correct option',
          ),
          'explanation': Schema.string(
            description: 'Printed explanation or note from the book page if present below the question, otherwise a concise educational explanation in Bengali',
          ),
          'legible': Schema.boolean(
            description:
                'false if the printed text was blurred, cut off or otherwise '
                'not actually readable in the image',
          ),
          'answer_source': Schema.enumString(
            enumValues: ['answer_key', 'solved', 'guess'],
            description:
                'answer_key if read off the page, solved if you worked it out '
                'with confidence, guess if you are not sure',
          ),
        },
        requiredProperties: [
          'question',
          'options',
          'correct_index',
          'explanation',
          'legible',
          'answer_source',
        ],
      ),
    ),
  },
  requiredProperties: ['title', 'subject', 'questions'],
);

/// A scan that did not produce the user's page.
///
/// It replaces a fallback deck of three hard-coded questions about সূর্য,
/// কারক and মুজিবনগর that used to be returned whenever the scan failed. They
/// arrived titled with the user's own filename and were indistinguishable
/// from a real read, so a failed scan looked like a page of questions the
/// book did not contain.
class QuestionBankExtractException implements Exception {
  /// Shown to the user as it is.
  final String userMessage;

  /// For the log, not the screen.
  final String? technicalDetails;

  const QuestionBankExtractException(this.userMessage, {this.technicalDetails});

  @override
  String toString() =>
      'QuestionBankExtractException: $userMessage'
      '${technicalDetails == null ? '' : ' ($technicalDetails)'}';
}

class QuestionBankOcrService {
  QuestionBankOcrService._();
  static final QuestionBankOcrService instance = QuestionBankOcrService._();

  static const String _visionPrompt = '''
You are an expert OCR and exam question extractor for Bangladeshi competitive exams (BCS Preliminary, Bank, Primary Recruitment, LiveMCQ).
The provided image is a page from a Question Bank (বিগত বছরের প্রশ্ন / প্র্যাকটিস প্রশ্ন ব্যাংক) or model test book.

Your instructions:
1. Extract ALL authentic Multiple Choice Questions (MCQs) visible on the page.
2. Determine the Subject (e.g. "বাংলা ব্যাকরণ", "বাংলাদেশ বিষয়াবলী", "English Language", "সাধারণ বিজ্ঞান", "গণিত ও মানসিক দক্ষতা", "আন্তর্জাতিক বিষয়াবলী", "কম্পিউটার ও তথ্যপ্রযুক্তি", "ভূগোল ও পরিবেশ") and a concise Chapter/Topic Title.
3. For EACH question:
   - Extract the complete question text (keep Bengali question numbers if present, e.g. "১. 'পাপে বিরত হও'—কোন কারকে কোন বিভক্তি?").
   - Extract all 4 distinct options (ক, খ, গ, ঘ or A, B, C, D).
   - Determine the correct answer index (0 for ক/A, 1 for খ/B, 2 for গ/C, 3 for ঘ/D).
     * First, look for answer markings on the page, bolded options, tick marks, or the answer table/key at the bottom/side of the page (or on the second image if provided).
     * If no answer key is visible, solve the question using expert BCS exam knowledge, and set answer_source to "solved". Set it to "guess" when you are not confident.
   - Explanation (ব্যাখ্যা):
     * If an explanation or note (e.g. labeled "ব্যাখ্যা:", "[ব্যাখ্যা]", "নোট:", "সমাধান:") is printed right below or next to the question/options on the book page, EXTRACT THAT PRINTED EXPLANATION EXACTLY. Do not discard or skip it.
     * If NO printed explanation is present on the page, generate a concise 1-2 sentence educational explanation in Bengali explaining why the correct answer is right.
   - Set legible to false when the printed text is blurred, cut off, overlapped or otherwise not actually readable.

CRITICAL — do not invent text. If a question or its options cannot be read clearly:
   * Transcribe only what is genuinely visible and set legible to false.
   * Never reconstruct a plausible question, and never borrow an answer, option or explanation from a different question on the page to fill a gap.
   * A question marked legible:false is expected and useful. A clean-looking question that was actually guessed is far worse, because nothing downstream can tell.
4. Clean Unicode:
   - Use native Unicode: '°' (১৮০°), '→', '×', '²', '³', '√'. Never use raw LaTeX syntax like '\$x^2\$'.
5. Return ONLY a valid JSON object matching the requested schema.
''';

  Future<String?> _getStoredApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(NotificationConstants.prefGeminiApiKey);
  }

  /// Extracts MCQs from a question page and an optional answer key page.
  /// What the last extraction actually cost, once the model reported it.
  int? lastCallTokens;

  /// A rough cost for an extraction not yet made, so the wait can show what
  /// it is spending. [pages] counts the answer key as a second image.
  int estimateTokensFor(CaptureDetail detail, {int pages = 1}) =>
      estimateRequestTokens(
        promptChars: _visionPrompt.length,
        image: detail,
        // A page of MCQs with options and explanations is a long reply.
        expectedOutputTokens: 2500,
      ) +
      (pages - 1) * detail.approxTokens;

  /// [onTokens] is called with the running total while the reply streams.
  Future<QuestionBankExtractResult> extractQuestionBank({
    required File questionImage,
    File? answerKeyImage,
    String? subjectHint,
    void Function(int tokensSoFar)? onTokens,
    // A question bank page is a full page of small Bengali print, which is
    // what the high preset is for. At 1024 the conjuncts and matras blur and
    // the model starts filling the gaps with invented text.
    CaptureDetail detail = CaptureDetail.high,
  }) async {
    final apiKey = await _getStoredApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw const QuestionBankExtractException(
        'Gemini API কী বসানো নেই। সেটিংসে কী দিন, তারপর আবার স্ক্যান করুন।',
      );
    }

    final prefs = await SharedPreferences.getInstance();
    var preferredModel =
        prefs.getString(NotificationConstants.prefGeminiModel) ??
        'gemini-flash-latest';
    if (![
      'gemini-flash-lite-latest',
      'gemini-flash-latest',
      'gemini-pro-latest',
      'gemini-3.5-flash-lite',
    ].contains(preferredModel)) {
      preferredModel = 'gemini-flash-latest';
    }

    final modelsToTry = [
      preferredModel,
      if (preferredModel != 'gemini-flash-latest') 'gemini-flash-latest',
      'gemini-flash-lite-latest',
    ];

    final questionBytes = await _prepareImageBytes(
      questionImage,
      detail.dimension,
    );
    final questionMime = _detectMimeType(questionImage.path);

    Uint8List? answerBytes;
    String? answerMime;
    if (answerKeyImage != null) {
      answerBytes = await _prepareImageBytes(answerKeyImage, detail.dimension);
      answerMime = _detectMimeType(answerKeyImage.path);
    }

    // Check content-hash cache
    final cacheKey = GeminiResultCache.instance.computeKey(
      operation: 'question_bank_ocr',
      promptVersion: 'v1.0',
      model: preferredModel,
      payloadBytes: [
        ...questionBytes,
        ...?answerBytes,
        ...utf8.encode(subjectHint ?? ''),
      ],
    );

    final cachedRaw = await GeminiResultCache.instance.get(cacheKey);
    if (cachedRaw != null && cachedRaw.isNotEmpty) {
      final cached = _decodeResponse(
        cachedRaw,
        rawRef: 'Page: ${questionImage.path.split('/').last}',
        hasSeparateAnswerKey: answerKeyImage != null,
      );
      if (cached != null) {
        await GeminiUsageTracker.instance.recordCacheHit(
          operation: 'question_bank_ocr',
          model: preferredModel,
        );
        return cached;
      }
    }

    String prompt = _visionPrompt;
    if (subjectHint != null &&
        subjectHint.isNotEmpty &&
        subjectHint != 'Auto Detect') {
      prompt += '\nNote: The user specifies the subject is: "$subjectHint".';
    }
    if (answerKeyImage != null) {
      prompt += '\nNote: Two images are provided. Image 1 has the questions. Image 2 contains the answer key/solutions. Match the question numbers to verify correct answers.';
    }

    final contentParts = <Part>[
      TextPart(prompt),
      DataPart(questionMime, questionBytes),
      if (answerBytes != null && answerMime != null)
        DataPart(answerMime, answerBytes),
    ];

    Object? lastError;
    lastCallTokens = null;
    for (final modelName in modelsToTry) {
      try {
        final model = GenerativeModel(
          model: modelName,
          apiKey: apiKey,
          generationConfig: GenerationConfig(
            responseMimeType: 'application/json',
            responseSchema: _questionBankSchema,
            temperature: 0.1,
            // Roughly 200 tokens per Bengali MCQ with options and an
            // explanation, so 4096 cut a full page short.
            maxOutputTokens: 8192,
          ),
        );

        final buffer = StringBuffer();
        int promptTokens = 0;
        int outputTokens = 0;
        int totalTokens = 0;
        var wasCut = false;

        await for (final chunk in model.generateContentStream([
          Content.multi(contentParts),
        ])) {
          buffer.write(chunk.text ?? '');
          final usage = chunk.usageMetadata;
          // Each chunk carries the running totals, not its own share.
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
          if (chunk.candidates.isNotEmpty &&
              chunk.candidates.first.finishReason == FinishReason.maxTokens) {
            wasCut = true;
          }
        }

        lastCallTokens = totalTokens > 0 ? totalTokens : null;
        await GeminiUsageTracker.instance.recordSuccess(
          tokens: totalTokens,
          actualInputTokens: promptTokens > 0 ? promptTokens : null,
          actualOutputTokens: outputTokens > 0 ? outputTokens : null,
          actualTotalTokens: totalTokens > 0 ? totalTokens : null,
          operation: 'question_bank_ocr',
          model: modelName,
        );

        if (wasCut) {
          // The reply was cut mid-JSON, so it decodes to nothing. Trying the
          // next model only repeats the same cut on the same crowded page.
          throw const QuestionBankExtractException(
            'পাতায় প্রশ্ন অনেক বেশি, পুরোটা পড়া শেষ হয়নি। '
            'অর্ধেক পাতা করে তুলুন।',
          );
        }

        final rawText = buffer.toString();
        final result = _decodeResponse(
          rawText,
          rawRef: 'Page: ${questionImage.path.split('/').last}',
          hasSeparateAnswerKey: answerKeyImage != null,
        );
        if (result != null && rawText.isNotEmpty) {
          await GeminiResultCache.instance.put(cacheKey, rawText);
          return result;
        }
      } on QuestionBankExtractException {
        rethrow;
      } catch (e) {
        debugPrint('QuestionBankOcrService model $modelName failed: $e');
        lastError = e;
      }
    }

    throw QuestionBankExtractException(
      'পাতাটা পড়া গেল না। ইন্টারনেট দেখে আবার চেষ্টা করুন, '
      'অথবা আলো ভালো রেখে আরেকবার ছবি তুলুন।',
      technicalDetails: lastError?.toString(),
    );
  }

  QuestionBankExtractResult? _decodeResponse(
    String? rawJson, {
    String? rawRef,
    bool hasSeparateAnswerKey = false,
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
        final raw = QuestionBankExtractResult.fromJson(
          decoded,
          rawRef: rawRef,
          hasSeparateAnswerKey: hasSeparateAnswerKey,
        );

        return QuestionBankExtractResult(
          title: BengaliMathSanitizer.sanitize(raw.title),
          subject: BengaliMathSanitizer.sanitize(raw.subject),
          rawReference: raw.rawReference,
          hasSeparateAnswerKey: raw.hasSeparateAnswerKey,
          questions: raw.questions
              .map(
                (q) => QuizQuestion(
                  questionText: BengaliMathSanitizer.sanitize(q.questionText),
                  options: q.options
                      .map((opt) => BengaliMathSanitizer.sanitize(opt))
                      .toList(),
                  correctIndex: q.correctIndex,
                  explanation: BengaliMathSanitizer.sanitize(q.explanation),
                  subject: raw.subject,
                ),
              )
              .toList(),
        );
      }
    } catch (e) {
      debugPrint('JSON decode error in QuestionBankOcrService: $e');
    }
    return null;
  }

  Future<Uint8List> _prepareImageBytes(File file, int maxDimension) async {
    final bytes = await file.readAsBytes();
    try {
      final decodedImage = img.decodeImage(bytes);
      if (decodedImage == null) return bytes;

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
      return Uint8List.fromList(compressed);
    } catch (e) {
      debugPrint('Image compression error in QuestionBankOcrService: $e');
      return bytes;
    }
  }

  String _detectMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  /// Independently verifies if a question and its marked answer are factually correct.
  /// Detects potential errors, typos or disagreements in question bank / test paper keys.
  Future<QuestionVerificationResult?> verifyQuestion({
    required QuizQuestion question,
    required String subject,
  }) async {
    final apiKey = await _getStoredApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      return QuestionVerificationResult(
        isCorrect: true,
        trueCorrectIndex: question.correctIndex,
        isAmbiguous: false,
        explanation: 'লোকাল চেকার: উত্তরটি সংরক্ষিত আছে (API Key সংযুক্ত থাকলে গভীর ফ্যাক্ট-চেক হবে)।',
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final modelName =
        prefs.getString(NotificationConstants.prefGeminiModel) ??
        'gemini-flash-latest';

    final prompt =
        '''
You are an expert BCS Prelims and Bangladesh competitive exam question verifier.
Check if this question and marked answer are 100% accurate, valid, and relevant.

Subject: $subject
Question: ${question.questionText}
Options:
${question.options.asMap().entries.map((e) => '${e.key}. ${e.value}').join('\n')}

Marked Correct Option: ${question.correctIndex} (${question.options.length > question.correctIndex ? question.options[question.correctIndex] : ''})

Task:
1. Is the question stem itself factually flawed, erroneous, or has NO correct answer at all among the options? (is_flawed: true/false)
2. Is the question completely irrelevant, obsolete (e.g. outdated one-time GK from years ago), or redundant for BCS/PSC syllabus? (is_irrelevant: true/false)
3. Solve the question independently. Which option (0, 1, 2, or 3) is actually correct?
4. Does the marked answer agree with the true correct answer? (is_correct: true/false)
5. Is the question ambiguous or debatable? (is_ambiguous: true/false)
6. Explain in 1-2 concise Bengali sentences. If flawed or irrelevant, state whether it should be deleted or corrected.

Return JSON ONLY:
{
  "is_correct": true,
  "true_correct_index": 0,
  "is_ambiguous": false,
  "is_flawed": false,
  "is_irrelevant": false,
  "explanation": "..."
}
''';

    try {
      final model = GenerativeModel(
        model: modelName,
        apiKey: apiKey,
        generationConfig: GenerationConfig(
          responseMimeType: 'application/json',
          temperature: 0.1,
          maxOutputTokens: 1024,
        ),
      );

      final response = await model.generateContent([Content.text(prompt)]);

      // Per-question verification is a real call too; it was the only one in
      // this service not being counted.
      await GeminiUsageTracker.instance.recordSuccess(
        tokens: response.usageMetadata?.totalTokenCount ?? 0,
        actualInputTokens: response.usageMetadata?.promptTokenCount,
        actualOutputTokens: response.usageMetadata?.candidatesTokenCount,
        actualTotalTokens: response.usageMetadata?.totalTokenCount,
        operation: 'question_verify',
        model: modelName,
      );
      final raw = response.text?.trim() ?? '';
      if (raw.isNotEmpty) {
        var clean = raw;
        if (clean.startsWith('```json')) clean = clean.substring(7);
        if (clean.startsWith('```')) clean = clean.substring(3);
        if (clean.endsWith('```')) clean = clean.substring(0, clean.length - 3);
        final decoded = jsonDecode(clean.trim());
        if (decoded is Map<String, dynamic>) {
          return QuestionVerificationResult(
            isCorrect: decoded['is_correct'] == true,
            trueCorrectIndex:
                (decoded['true_correct_index'] as num?)?.toInt() ??
                question.correctIndex,
            isAmbiguous: decoded['is_ambiguous'] == true,
            explanation: BengaliMathSanitizer.sanitize(
              decoded['explanation']?.toString() ?? '',
            ),
            isFlawed: decoded['is_flawed'] == true,
            isIrrelevant: decoded['is_irrelevant'] == true,
          );
        }
      }
    } catch (e) {
      debugPrint('Error in verifyQuestion: $e');
    }
    return null;
  }
}

class QuestionVerificationResult {
  final bool isCorrect;
  final int trueCorrectIndex;
  final bool isAmbiguous;
  final String explanation;
  final bool isFlawed;
  final bool isIrrelevant;

  const QuestionVerificationResult({
    required this.isCorrect,
    required this.trueCorrectIndex,
    required this.isAmbiguous,
    required this.explanation,
    this.isFlawed = false,
    this.isIrrelevant = false,
  });

  Map<String, dynamic> toJson() => {
    'is_correct': isCorrect,
    'true_correct_index': trueCorrectIndex,
    'is_ambiguous': isAmbiguous,
    'explanation': explanation,
    'is_flawed': isFlawed,
    'is_irrelevant': isIrrelevant,
  };
}
