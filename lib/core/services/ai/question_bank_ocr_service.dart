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
import 'cross_check_answers.dart';
import 'question_text_parser.dart';
import 'settle_scanned_answer.dart';

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
          'printed_answer_letter': Schema.string(
            description:
                'The answer letter exactly as printed on the page (ক, খ, গ, ঘ, '
                'A, B, C, D), or an empty string if the page marks no answer. '
                'Report what you see even when you are unsure which letter it '
                'is; do not resolve it to an index yourself.',
          ),
          'section_title': Schema.string(
            description:
                'The banner or heading this question sits under, e.g. '
                '"ব্যাংক নিয়োগ পরীক্ষা" or "মডেল টেস্ট ০৫". Empty string if '
                'the question sits under no heading.',
          ),
          'source_exam': Schema.string(
            description:
                'The exam the book credits this question to, exactly as '
                'printed in brackets, e.g. "BB Officer (Cash): 16". Empty '
                'string if none is printed.',
          ),
          'printed_number': Schema.string(
            description:
                'The question number exactly as printed, e.g. "১০". Empty '
                'string if the question is unnumbered.',
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

/// The reply wanted from the answer re-check: numbers and letters, nothing else.
final Schema _answersOnlySchema = Schema.object(
  properties: {
    'answers': Schema.array(
      items: Schema.object(
        properties: {
          'printed_number': Schema.string(
            description: 'The question number exactly as printed, e.g. "১০".',
          ),
          'printed_answer_letter': Schema.string(
            description:
                'The answer letter exactly as printed (ক, খ, গ, ঘ, A, B, C, '
                'D). Empty string if this question has no printed answer.',
          ),
          'section_title': Schema.string(
            description:
                'The banner this question sits under, or an empty string. '
                'Needed because one page can hold two question ১৩s.',
          ),
        },
        requiredProperties: ['printed_number', 'printed_answer_letter'],
      ),
    ),
  },
  requiredProperties: ['answers'],
);

/// Asks for the answer column and nothing more.
///
/// It names the letters that get confused, because that is the whole reason
/// this second read exists: two reads of one page disagreed on six answers out
/// of eighteen, every one of them a খ/ঘ/ব or গ/ক mix-up, and both reads were
/// certain.
const String _answersOnlyPrompt = '''
This image is a page from a Bangladeshi exam question bank. Do NOT transcribe
the questions or the options.

Report ONLY the printed answer for each question on the page:
- The question number exactly as printed (printed_number).
- The answer letter exactly as printed (printed_answer_letter) — look for "উ:",
  "উত্তর:", a bolded or ticked option, or an answer table at the bottom, at the
  side, or on a second image if one is given.
- The banner or heading the question sits under (section_title), or an empty
  string. A page can hold two questions with the same number, one from each of
  two tests, and the heading is what tells them apart.

Read the letters with care. ক, খ, গ, ঘ and ব are easily confused in this print.
Report the letter you actually see. Where you cannot tell which letter it is,
return an empty string for that question rather than the likelier of two —
an empty string is useful here and a confident wrong letter is not.

Do not work any answer out yourself. If the page prints no answer for a
question, return an empty string.

Return ONLY valid JSON matching the schema.
''';

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

  /// Roughly how long the instructions are, for the cost estimate.
  ///
  /// A constant rather than the built string's length: the two variants by a
  /// few lines, which is noise beside a page of image tokens, and the estimate
  /// is wanted before the flags are known.
  static const int _estimatePromptChars = 3400;

  /// The instructions sent with the page.
  ///
  /// Two things about it change with the user's settings, so it is built
  /// rather than fixed. [trustPrintedAnswersOnly] decides whether the model
  /// may work out an answer the page does not give, and [withExplanations]
  /// whether it writes an explanation the page does not have. Both default to
  /// the cautious side: these books print their own answers, and those are
  /// usually right, so the model's job is to read them rather than to
  /// second-guess them.
  static String _buildVisionPrompt({
    required bool trustPrintedAnswersOnly,
    required bool withExplanations,
  }) {
    final unprintedAnswer = trustPrintedAnswersOnly
        ? '''     * If NO answer is printed anywhere for a question: set correct_index to -1
       and answer_source to "guess". Do NOT work the answer out, and do NOT
       pick an option. A question that arrives unanswered is wanted here — the
       user fills it in themselves. An invented answer is far worse, because
       once it is saved nothing can tell it from a real one.'''
        : '''     * If NO answer is printed anywhere, solve the question using expert exam
       knowledge and set answer_source to "solved". Set it to "guess" with
       correct_index -1 whenever you are not confident.''';

    final explanationRule = withExplanations
        ? '''     * If an explanation or note (e.g. labeled "ব্যাখ্যা:", "[ব্যাখ্যা]", "নোট:",
       "সমাধান:") is printed with the question, EXTRACT IT EXACTLY.
     * If none is printed, write a concise 1-2 sentence explanation in Bengali.'''
        : '''     * If an explanation or note (e.g. labeled "ব্যাখ্যা:", "[ব্যাখ্যা]", "নোট:",
       "সমাধান:") is printed with the question, EXTRACT IT EXACTLY.
     * If none is printed, return an empty string. Do NOT write one. The user
       asked for the page as it is, and will ask for an explanation on the
       questions where they want one.''';

    return '''
You are an expert OCR and exam question extractor for Bangladeshi competitive exams (BCS Preliminary, Bank, Primary Recruitment, LiveMCQ).
The provided image is a page from a Question Bank (বিগত বছরের প্রশ্ন / প্র্যাকটিস প্রশ্ন ব্যাংক) or model test book.

Your instructions:
1. Extract ALL authentic Multiple Choice Questions (MCQs) visible on the page.
2. Determine the Subject (e.g. "বাংলা ব্যাকরণ", "বাংলাদেশ বিষয়াবলী", "English Language", "সাধারণ বিজ্ঞান", "গণিত ও মানসিক দক্ষতা", "আন্তর্জাতিক বিষয়াবলী", "কম্পিউটার ও তথ্যপ্রযুক্তি", "ভূগোল ও পরিবেশ") and a concise Chapter/Topic Title.
3. For EACH question:
   - Extract the complete question text (keep Bengali question numbers if present, e.g. "১. 'পাপে বিরত হও'—কোন কারকে কোন বিভক্তি?").
   - Extract all 4 distinct options (ক, খ, গ, ঘ or A, B, C, D).
   - The correct answer — READ IT OFF THE PAGE, do not reason it out:
     * These books print the answer. Look for "উ:", "উত্তর:", a bolded or ticked
       option, or an answer table at the bottom, at the side, or on the second
       image when one is provided.
     * Put the letter you read in printed_answer_letter EXACTLY as printed, give
       its 0-based index in correct_index, and set answer_source to "answer_key".
     * THE PRINTED ANSWER STANDS. Do not replace it with your own reasoning, not
       even when you believe the book is wrong. If you think it is wrong, say so
       in the explanation and leave the answer alone.
     * If an answer IS printed but you cannot tell WHICH letter it is — খ, ঘ and
       ব are easily taken for one another in this print — put what you see in
       printed_answer_letter, set correct_index to -1 and answer_source to
       "guess". NEVER pick the likelier of two letters.
__UNPRINTED__
   - Explanation (ব্যাখ্যা):
__EXPLANATION__
   - Set legible to false when the printed text is blurred, cut off, overlapped
     or otherwise not actually readable. A missing answer is NOT illegibility;
     say that with correct_index -1 instead.
4. Sections — one page often holds the end of one model test and the start of
   the next:
   - When a question sits under a banner or heading (e.g. "ব্যাংক নিয়োগ পরীক্ষা",
     "মডেল টেস্ট ০৫"), repeat that heading in section_title for every question
     under it.
   - These books credit each question to an exam in brackets, e.g.
     "[BB Officer (Cash): 16]". Put that in source_exam exactly as printed.
   - Put the question number exactly as printed in printed_number. Where the
     numbering goes back to ১ partway down the page, report it as printed — do
     NOT renumber it to continue from above. That restart is how a reader learns
     a second test begins there.

CRITICAL — do not invent text. If a question or its options cannot be read clearly:
   * Transcribe only what is genuinely visible and set legible to false.
   * Never reconstruct a plausible question, and never borrow an answer, option or explanation from a different question on the page to fill a gap.
   * A question marked legible:false is expected and useful. A clean-looking question that was actually guessed is far worse, because nothing downstream can tell.
5. Clean Unicode:
   - Use native Unicode: '°' (১৮০°), '→', '×', '²', '³', '√'. Never use raw LaTeX syntax like '\$x^2\$'.
6. Return ONLY a valid JSON object matching the requested schema.
'''
        .replaceFirst('__UNPRINTED__', unprintedAnswer)
        .replaceFirst('__EXPLANATION__', explanationRule);
  }

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
        promptChars: _estimatePromptChars,
        image: detail,
        // A page of MCQs with options and explanations is a long reply.
        expectedOutputTokens: 2500,
      ) +
      (pages - 1) * detail.approxTokens;

  /// [onTokens] is called with the running total while the reply streams.
  ///
  /// [onChars] is called with the number of characters received so far.
  ///
  /// This is the figure that actually moves. Measured against the API: usage
  /// metadata does arrive on every chunk, but no chunk arrives at all until
  /// the model stops thinking and starts writing, and the thinking is the
  /// longest part of the wait. Once the writing starts, every chunk carries
  /// text, so this climbs with each one.
  Future<QuestionBankExtractResult> extractQuestionBank({
    required File questionImage,
    File? answerKeyImage,
    String? subjectHint,
    void Function(int tokensSoFar)? onTokens,
    void Function(int charsSoFar)? onChars,

    /// When true the model may not answer a question the page leaves
    /// unanswered, and may never override an answer the page prints. These
    /// books print their own answers and those are usually right, so a model
    /// reasoning over the top of them adds mistakes rather than removing any.
    bool trustPrintedAnswersOnly = true,

    /// When false an explanation is kept only where the page prints one.
    /// Writing one for every question spends output tokens on every question,
    /// and output is the slow half of the wait.
    bool withExplanations = false,
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
      // Bumped with the prompt: it now reads the printed answer rather than
      // reasoning one out, and reports the section it came from.
      promptVersion: 'v2.0',
      model: preferredModel,
      payloadBytes: [
        ...questionBytes,
        ...?answerBytes,
        ...utf8.encode(subjectHint ?? ''),
        // Part of the key, or the same page scanned under different settings
        // would serve whichever answer was cached first.
        ...utf8.encode('trust:$trustPrintedAnswersOnly'),
        ...utf8.encode('explain:$withExplanations'),
      ],
    );

    final cachedRaw = await GeminiResultCache.instance.get(cacheKey);
    if (cachedRaw != null && cachedRaw.isNotEmpty) {
      final cached = _decodeResponse(
        cachedRaw,
        rawRef: 'Page: ${questionImage.path.split('/').last}',
        hasSeparateAnswerKey: answerKeyImage != null,
        trustPrintedAnswersOnly: trustPrintedAnswersOnly,
      );
      if (cached != null) {
        await GeminiUsageTracker.instance.recordCacheHit(
          operation: 'question_bank_ocr',
          model: preferredModel,
        );
        return cached;
      }
    }

    String prompt = _buildVisionPrompt(
      trustPrintedAnswersOnly: trustPrintedAnswersOnly,
      withExplanations: withExplanations,
    );
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
          onChars?.call(buffer.length);
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
          trustPrintedAnswersOnly: trustPrintedAnswersOnly,
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

  /// Reads only the answer letters off the page, for checking the first read.
  ///
  /// Deliberately small. The page has already been transcribed; what is wanted
  /// here is a second opinion on the one thing that was measured to be
  /// unreliable, so the reply is a short list of numbers and letters rather
  /// than the page again. That keeps the second look to a fraction of the
  /// first's cost, which matters because the first is the slow one.
  ///
  /// Returns null when the check could not be made at all — no key, no
  /// network, every model refused. Null means "not checked", which the caller
  /// must not confuse with "checked and found nothing".
  Future<List<PrintedAnswer>?> readPrintedAnswers({
    required File questionImage,
    File? answerKeyImage,
    CaptureDetail detail = CaptureDetail.high,
  }) async {
    final apiKey = await _getStoredApiKey();
    if (apiKey == null || apiKey.isEmpty) return null;

    try {
      final questionBytes = await _prepareImageBytes(
        questionImage,
        detail.dimension,
      );
      final parts = <Part>[
        TextPart(_answersOnlyPrompt),
        DataPart(_detectMimeType(questionImage.path), questionBytes),
      ];
      if (answerKeyImage != null) {
        parts.add(
          DataPart(
            _detectMimeType(answerKeyImage.path),
            await _prepareImageBytes(answerKeyImage, detail.dimension),
          ),
        );
      }

      final model = GenerativeModel(
        model: 'gemini-flash-latest',
        apiKey: apiKey,
        generationConfig: GenerationConfig(
          responseMimeType: 'application/json',
          responseSchema: _answersOnlySchema,
          // Zero, not the 0.1 the first pass uses. A second opinion is only
          // worth having if it is the page's answer rather than a fresh
          // invention, and there is nothing here to be creative about.
          temperature: 0,
        ),
      );

      final response = await model.generateContent([Content.multi(parts)]);
      await GeminiUsageTracker.instance.recordSuccess(
        tokens: response.usageMetadata?.totalTokenCount ?? 0,
        actualInputTokens: response.usageMetadata?.promptTokenCount,
        actualOutputTokens: response.usageMetadata?.candidatesTokenCount,
        actualTotalTokens: response.usageMetadata?.totalTokenCount,
        operation: 'question_bank_answer_recheck',
        model: 'gemini-flash-latest',
      );

      final raw = response.text;
      if (raw == null || raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final list = decoded['answers'];
      if (list is! List) return null;

      return [
        for (final item in list)
          if (item is Map<String, dynamic>) PrintedAnswer.fromJson(item),
      ];
    } catch (e) {
      debugPrint('Answer re-check failed, so nothing was verified: $e');
      return null;
    }
  }

  QuestionBankExtractResult? _decodeResponse(
    String? rawJson, {
    String? rawRef,
    bool hasSeparateAnswerKey = false,
    bool trustPrintedAnswersOnly = false,
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
                (q) => settleScannedAnswer(
                  // Rebuilt with copyWith rather than a fresh QuizQuestion:
                  // writing the fields out by hand here silently dropped
                  // `legible` and `answerSource`, so every flag the model
                  // raised was thrown away one line after it arrived and
                  // nothing downstream ever saw a question marked uncertain.
                  q.copyWith(
                    questionText: BengaliMathSanitizer.sanitize(q.questionText),
                    options: q.options
                        .map((opt) => BengaliMathSanitizer.sanitize(opt))
                        .toList(),
                    explanation: BengaliMathSanitizer.sanitize(q.explanation),
                    subject: raw.subject,
                  ),
                  trustPrintedAnswersOnly: trustPrintedAnswersOnly,
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

  /// Extracts multiple-choice questions from raw text provided by external agents
  /// (such as ChatGPT, Claude, DeepSeek, or web transcriptions).
  ///
  /// First attempts an offline structural parse; if [forceAi] is true or local
  /// parsing yields no questions, sends the text to Gemini with structured output schema.
  Future<QuestionBankExtractResult> extractQuestionsFromText({
    required String rawText,
    String? subjectHint,
    bool forceAi = false,
    void Function(int tokens)? onTokens,
  }) async {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) {
      throw const QuestionBankExtractException(
        'কোনো টেক্সট পাওয়া যায়নি। অনুগ্রহ করে প্রশ্ন সংবলিত টেক্সট পেস্ট করুন।',
      );
    }

    // 1. Try offline local parser first ONLY if not forcing AI AND
    // the input text already contains explicit answers for all questions.
    if (!forceAi) {
      final local = QuestionTextParser.tryParseLocal(
        trimmed,
        subjectHint: subjectHint,
      );
      if (local != null &&
          local.questions.isNotEmpty &&
          QuestionTextParser.hasExplicitAnswers(local)) {
        return local;
      }
    }

    final apiKey = await _getStoredApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      // If no API key, try local parse as best-effort fallback
      final fallback = QuestionTextParser.tryParseLocal(
        trimmed,
        subjectHint: subjectHint,
      );
      if (fallback != null && fallback.questions.isNotEmpty) {
        return fallback;
      }
      throw const QuestionBankExtractException(
        'Gemini API কী বসানো নেই এবং টেক্সটটি সরাসরি পার্স করা যায়নি। সেটিংসে কী দিন অথবা সুনির্দিষ্ট ফরম্যাটে টেক্সট পেস্ট করুন।',
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

    // Check content-hash cache
    final cacheKey = GeminiResultCache.instance.computeKey(
      operation: 'question_text_extract',
      promptVersion: 'v1.0',
      model: preferredModel,
      payloadBytes: [
        ...utf8.encode(trimmed),
        ...utf8.encode(subjectHint ?? ''),
      ],
    );

    final cachedRaw = await GeminiResultCache.instance.get(cacheKey);
    if (cachedRaw != null && cachedRaw.isNotEmpty) {
      final cached = _decodeResponse(
        cachedRaw,
        rawRef: 'Text input (${trimmed.length} chars)',
        hasSeparateAnswerKey: false,
      );
      if (cached != null) {
        await GeminiUsageTracker.instance.recordCacheHit(
          operation: 'question_text_extract',
          model: preferredModel,
        );
        return cached;
      }
    }

    final prompt = '''
You are an expert exam question extractor and question setter for Bangladeshi competitive exams (BCS Preliminary, Bank, Primary Recruitment, LiveMCQ).
The user has provided raw text containing Multiple Choice Questions (MCQs), copied from an external AI agent, website, OCR transcript, or notes.

Instructions:
1. Extract ALL authentic Multiple Choice Questions (MCQs) found in the text.
2. Determine the Subject (e.g. "বাংলা ব্যাকরণ", "বাংলাদেশ বিষয়াবলী", "English Language", "সাধারণ বিজ্ঞান", "গণিত ও মানসিক দক্ষতা", "আন্তর্জাতিক বিষয়াবলী", "কম্পিউটার ও তথ্যপ্রযুক্তি", "ভূগোল ও পরিবেশ") and a concise Chapter/Topic Title.
3. Each question must have exactly 4 distinct options (or 5 if bank exam). Ensure options are cleanly formatted.
4. If an answer key or solution is given in the text, match and indicate the zero-based correct_index (0, 1, 2, or 3) and set answer_source to "answer_key".
   CRITICAL: If NO answer is indicated (the user omitted the answer and explanation), YOU MUST SOLVE THE QUESTION YOURSELF with 100% accuracy, pick the correct option (0, 1, 2, or 3), and set answer_source to "solved". DO NOT default or blindly choose option 0!
5. Provide a clear educational explanation in Bengali for each question explaining why the chosen option is correct.
6. Clean Unicode: Replace LaTeX math like \$x^2\$ or \\to with standard Unicode ('²', '°', '→', '√').

${subjectHint != null && subjectHint.isNotEmpty && subjectHint != 'Auto Detect' ? 'User Subject Hint: "$subjectHint"' : ''}

Raw Input Text:
$trimmed
''';

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
          ),
        );

        final response = await model.generateContent([
          Content.text(prompt),
        ]);

        final text = response.text;
        if (text == null || text.trim().isEmpty) {
          throw const QuestionBankExtractException(
            'মডেল থেকে কোনো উত্তর পাওয়া যায়নি।',
          );
        }

        final spent = response.usageMetadata?.totalTokenCount;
        lastCallTokens = spent;
        if (spent != null && spent > 0) {
          onTokens?.call(spent);
          await GeminiUsageTracker.instance.recordSuccess(
            tokens: spent,
            actualInputTokens: response.usageMetadata?.promptTokenCount,
            actualOutputTokens: response.usageMetadata?.candidatesTokenCount,
            actualTotalTokens: spent,
            operation: 'question_text_extract',
            model: modelName,
          );
        }

        final result = _decodeResponse(
          text,
          rawRef: 'Text Input (${trimmed.length} chars)',
          hasSeparateAnswerKey: false,
        );

        if (result != null && result.questions.isNotEmpty) {
          await GeminiResultCache.instance.put(cacheKey, text);
          return result;
        }

        throw const QuestionBankExtractException(
          'টেক্সট থেকে কোনো প্রশ্ন উদ্ধার করা সম্ভব হয়নি। টেক্সটটিতে কি প্রশ্ন ও অপশন উপস্থিত রয়েছে?',
        );
      } on GenerativeAIException catch (e) {
        lastError = e;
        if (e.message.contains('API key not valid') ||
            e.message.contains('API_KEY_INVALID')) {
          throw const QuestionBankExtractException(
            'সেটিংসের Gemini API কী সঠিক নয়।',
          );
        }
        if (e.message.contains('RESOURCE_EXHAUSTED')) {
          continue; // Try next model
        }
      } catch (e) {
        lastError = e;
      }
    }

    // If Gemini fails, try local parser as final safety net
    final fallback = QuestionTextParser.tryParseLocal(
      trimmed,
      subjectHint: subjectHint,
    );
    if (fallback != null && fallback.questions.isNotEmpty) {
      return fallback;
    }

    throw QuestionBankExtractException(
      'টেক্সট প্রসেস করতে ব্যর্থ হয়েছে: $lastError',
    );
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

Marked Correct Option: ${question.correctIndex} (${(question.correctIndex >= 0 && question.correctIndex < question.options.length) ? question.options[question.correctIndex] : ''})

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
          // A cap only truncates; it never costs anything on its own. At
          // 1024 this verification was cut by the reasoning that precedes
          // the answer, and a reply cut mid-JSON decodes to nothing — so a
          // question came back unverified rather than slowly verified.
        ),
      );

      final response = await model.generateContent([Content.text(prompt)]);
      if (response.candidates.isNotEmpty &&
          response.candidates.first.finishReason == FinishReason.maxTokens) {
        debugPrint('Question verify: reply was cut before it finished');
      }

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
