import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/notification_constants.dart';
import '../../database/app_database.dart';
import '../../utils/bengali_math_sanitizer.dart';
import 'gemini_prompts.dart';
import 'gemini_result_cache.dart';
import 'models/chat_verification_result.dart';
import 'models/evidence_review.dart';
import 'models/mcq_verification.dart';
import 'gemini_usage_tracker.dart';
import 'models/adaptive_study_plan.dart';
import 'models/study_sheet_summary.dart';
import 'models/study_task.dart';

/// Output shape is set per call rather than on the model, because this one
/// service produces both strict JSON (study plan, sheet summary) and prose
/// (mistake explanations, revision notes). Until now neither was configured,
/// so every call ran at the API default temperature of 1.0 with no output
/// ceiling, and the JSON callers had to beg the model in prose not to wrap
/// their output in markdown fences.
final _studyPlanConfig = GenerationConfig(
  temperature: 0.2,
  responseMimeType: 'application/json',
  responseSchema: studyPlanSchema,
  maxOutputTokens: 2048,
);

final _jsonConfig = GenerationConfig(
  temperature: 0.2,
  responseMimeType: 'application/json',
  maxOutputTokens: 2048,
);

/// Shape of an independent answer to an MCQ.
///
/// Note what is absent: nothing about whether the stored answer was right.
/// The model is not told there is a stored answer, so it has nothing to agree
/// with; it simply answers the question and reports what its answer rests on.
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

final _mcqSolveConfig = GenerationConfig(
  temperature: 0.1,
  responseMimeType: 'application/json',
  responseSchema: _mcqSolveSchema,
  maxOutputTokens: 600,
);

/// Shape for a second look taken with the user's own argument in hand.
///
/// There is no field for "is the stored answer right", because the reviewer is
/// never told what the stored answer is.
final _evidenceReviewSchema = Schema.object(
  properties: {
    'user_reasoning_sound': Schema.boolean(
      description: 'Does the user\'s argument hold up when examined on its own',
    ),
    'reviewer_index': Schema.integer(
      description:
          '0-based option you believe correct, or -1 if you cannot settle',
    ),
    'reasoning': Schema.string(
      description: 'Two or three sentences in Bengali, addressed to the user',
    ),
    'question_flaw': Schema.enumString(
      enumValues: [
        'none',
        'duplicate_options',
        'no_correct_option',
        'unclear_wording',
      ],
    ),
    'suggested_question_text': Schema.string(
      description: 'Rewritten question, or empty string to leave it alone',
    ),
    'suggested_options': Schema.array(
      items: Schema.string(),
      description: 'Replacement options, or an empty array to leave them alone',
    ),
  },
  requiredProperties: [
    'user_reasoning_sound',
    'reviewer_index',
    'reasoning',
    'question_flaw',
    'suggested_question_text',
    'suggested_options',
  ],
);

final _evidenceReviewConfig = GenerationConfig(
  temperature: 0.2,
  responseMimeType: 'application/json',
  responseSchema: _evidenceReviewSchema,
  maxOutputTokens: 900,
);

/// Claim-level shape for a chat answer.
///
/// The counts are part of the contract, not decoration: without them a model
/// can check one easy sentence and leave the reply looking verified.
final _chatVerificationSchema = Schema.object(
  properties: {
    'claims_found': Schema.integer(
      description: 'How many independently checkable claims the answer makes',
    ),
    'claims_evaluated': Schema.integer(
      description: 'How many you actually judged',
    ),
    'extraction_complete': Schema.boolean(
      description: 'False if you could not cover every claim',
    ),
    'extraction_note': Schema.string(
      description: 'Why coverage is incomplete, when it is',
    ),
    'claims': Schema.array(
      items: Schema.object(
        properties: {
          'text': Schema.string(
            description: 'The claim quoted from the answer, not paraphrased',
          ),
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
    'claims',
  ],
);

final _chatVerificationConfig = GenerationConfig(
  temperature: 0.1,
  responseMimeType: 'application/json',
  responseSchema: _chatVerificationSchema,
  maxOutputTokens: 1400,
);

final _proseConfig = GenerationConfig(temperature: 0.6, maxOutputTokens: 1536);

class GeminiAiService {
  /// Trims a context value so one long syllabus string cannot dominate the
  /// prompt.
  static String _shorten(String? value, int max) {
    final v = value?.trim() ?? '';
    return v.length <= max ? v : '${v.substring(0, max)}…';
  }

  GeminiAiService._();
  static final GeminiAiService instance = GeminiAiService._();

  GenerativeModel? _model;
  String? _cachedApiKey;
  String _selectedModel = 'gemini-flash-lite-latest';
  String get selectedModel => _selectedModel;

  static const List<String> supportedModels = [
    'gemini-flash-lite-latest',
    'gemini-flash-latest',
    'gemini-pro-latest',
  ];

  Future<void> init([String? apiKey]) async {
    final prefs = await SharedPreferences.getInstance();
    var model =
        prefs.getString(NotificationConstants.prefGeminiModel) ??
        'gemini-flash-lite-latest';
    if (!supportedModels.contains(model)) {
      model = 'gemini-flash-lite-latest';
      await prefs.setString(NotificationConstants.prefGeminiModel, model);
    }
    _selectedModel = model;

    final key = apiKey ?? await _getStoredApiKey();
    if (key != null && key.isNotEmpty) {
      _cachedApiKey = key;
      _model = GenerativeModel(
        model: _selectedModel,
        apiKey: key,
        systemInstruction: Content.system(GeminiPrompts.systemInstruction),
      );
      debugPrint('GeminiAiService initialized with model $_selectedModel');
    } else {
      _cachedApiKey = null;
      _model = null;
      debugPrint('GeminiAiService cleared (offline mode)');
    }
  }

  Future<void> setModel(String modelName) async {
    _selectedModel = modelName;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(NotificationConstants.prefGeminiModel, modelName);
    if (_cachedApiKey != null) {
      _model = GenerativeModel(
        model: modelName,
        apiKey: _cachedApiKey!,
        systemInstruction: Content.system(GeminiPrompts.systemInstruction),
      );
      debugPrint('Switched AI model to $modelName');
    }
  }

  Future<String?> _getStoredApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(NotificationConstants.prefGeminiApiKey);
  }

  Future<void> saveApiKey(String apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      NotificationConstants.prefGeminiApiKey,
      apiKey.trim(),
    );
    await init(apiKey.trim());
  }

  bool get hasApiKey => _cachedApiKey != null && _cachedApiKey!.isNotEmpty;
  String? get apiKey => _cachedApiKey;

  /// Generates structured daily adaptive study plan
  Future<AdaptiveStudyPlan> generateAdaptivePlan({
    required String energyLevel,
    required int fatigueScore,
    required List<WeakTopic> weakTopics,
    required List<ExamSchedule> upcomingExams,
    bool isOffDay = false,
  }) async {
    await init();

    if (_model == null) {
      debugPrint(
        'No Gemini API key configured. Using intelligent rule-based local planner.',
      );
      return _generateLocalAdaptivePlan(
        energyLevel: energyLevel,
        fatigueScore: fatigueScore,
        weakTopics: weakTopics,
        upcomingExams: upcomingExams,
        isOffDay: isOffDay,
      );
    }

    final weakTopicsMap = weakTopics
        .map(
          (t) => {
            'subject': t.subject,
            'topic': t.topicName,
            'proficiency': t.proficiencyLevel.name,
            if ((t.notes ?? '').isNotEmpty) 'notes': _shorten(t.notes, 100),
          },
        )
        .toList();

    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final examsMap = upcomingExams
        .map(
          (e) => {
            'title': e.title,
            'track': e.trackName,
            'examDate': e.examDate.toIso8601String().substring(0, 10),
            'daysAway': DateTime(
              e.examDate.year,
              e.examDate.month,
              e.examDate.day,
            ).difference(todayStart).inDays,
            'topics': _shorten(e.topicsCovered, 120),
          },
        )
        .toList();

    final promptText = GeminiPrompts.buildStudyPlanPrompt(
      energyLevel: energyLevel,
      fatigueScore: fatigueScore,
      weakTopics: weakTopicsMap,
      upcomingExams: examsMap,
      isOffDay: isOffDay,
    );

    try {
      final response = await _model!.generateContent([
        Content.text(promptText),
      ], generationConfig: _studyPlanConfig);

      await GeminiUsageTracker.instance.recordSuccess(
        tokens: response.usageMetadata?.totalTokenCount ?? 0,
        actualInputTokens: response.usageMetadata?.promptTokenCount,
        actualOutputTokens: response.usageMetadata?.candidatesTokenCount,
        actualTotalTokens: response.usageMetadata?.totalTokenCount,
        operation: 'study_plan',
        model: _selectedModel,
      );

      final rawText = response.text;
      if (rawText != null && rawText.isNotEmpty) {
        final cleanJson = _extractCleanJson(rawText);
        final decoded = jsonDecode(cleanJson) as Map<String, dynamic>;
        return AdaptiveStudyPlan.fromJson(decoded);
      }
    } catch (e) {
      debugPrint('Gemini ($_selectedModel) call failed: $e.');

      // Auto-fallback to gemini-flash-lite-latest if primary model is rate-limited or fails
      if (_selectedModel != 'gemini-flash-lite-latest' &&
          _cachedApiKey != null) {
        try {
          debugPrint(
            'Auto-falling back from $_selectedModel to gemini-flash-lite-latest...',
          );
          final flashModel = GenerativeModel(
            model: 'gemini-flash-lite-latest',
            apiKey: _cachedApiKey!,
            systemInstruction: Content.system(GeminiPrompts.systemInstruction),
          );
          final fallbackResponse = await flashModel.generateContent([
            Content.text(promptText),
          ], generationConfig: _studyPlanConfig);
          await GeminiUsageTracker.instance.recordSuccess(
            tokens: fallbackResponse.usageMetadata?.totalTokenCount ?? 0,
            actualInputTokens: fallbackResponse.usageMetadata?.promptTokenCount,
            actualOutputTokens:
                fallbackResponse.usageMetadata?.candidatesTokenCount,
            actualTotalTokens: fallbackResponse.usageMetadata?.totalTokenCount,
            operation: 'study_plan',
            model: 'gemini-flash-lite-latest',
          );
          final rawText = fallbackResponse.text;
          if (rawText != null && rawText.isNotEmpty) {
            final cleanJson = _extractCleanJson(rawText);
            final decoded = jsonDecode(cleanJson) as Map<String, dynamic>;
            return AdaptiveStudyPlan.fromJson(decoded);
          }
        } catch (fallbackErr) {
          debugPrint('Flash fallback also failed: $fallbackErr');
        }
      }

      if (e.toString().contains('429') ||
          e.toString().toLowerCase().contains('quota')) {
        await GeminiUsageTracker.instance.recordQuotaExceeded(
          operation: 'study_plan',
          model: _selectedModel,
        );
      } else {
        await GeminiUsageTracker.instance.recordError(
          e.toString(),
          operation: 'study_plan',
          model: _selectedModel,
        );
      }
    }

    return _generateLocalAdaptivePlan(
      energyLevel: energyLevel,
      fatigueScore: fatigueScore,
      weakTopics: weakTopics,
      upcomingExams: upcomingExams,
    );
  }

  /// PDF & Resource Summarizer: returns 5 concise bullet points and recurring past questions.
  /// Uses content-hash caching to avoid redundant token costs when reviewing the same sheet.
  Future<StudySheetSummary> summarizeStudySheet({
    required String content,
    String? subject,
  }) async {
    await init();

    final cacheKey = GeminiResultCache.instance.computeKeyFromString(
      operation: 'sheet_summary',
      promptVersion: 'v2.0',
      model: _selectedModel,
      payloadText: '${subject ?? ""}:$content',
    );

    // 1. Check content-hash cache first (0 tokens)
    final cachedData = await GeminiResultCache.instance.get(cacheKey);
    if (cachedData != null) {
      try {
        final decoded = jsonDecode(cachedData) as Map<String, dynamic>;
        await GeminiUsageTracker.instance.recordCacheHit(
          operation: 'sheet_summary',
          model: _selectedModel,
        );
        return StudySheetSummary.fromJson(decoded);
      } catch (_) {}
    }

    if (_model != null) {
      try {
        final promptText = GeminiPrompts.buildStudySheetSummaryPrompt(
          rawContent: content,
          subject: subject,
        );

        final response = await _model!.generateContent([
          Content.text(promptText),
        ], generationConfig: _jsonConfig);

        await GeminiUsageTracker.instance.recordSuccess(
          tokens: response.usageMetadata?.totalTokenCount ?? 0,
          actualInputTokens: response.usageMetadata?.promptTokenCount,
          actualOutputTokens: response.usageMetadata?.candidatesTokenCount,
          actualTotalTokens: response.usageMetadata?.totalTokenCount,
          operation: 'sheet_summary',
          model: _selectedModel,
        );

        final rawText = response.text;
        if (rawText != null && rawText.isNotEmpty) {
          final cleanJson = _extractCleanJson(rawText);
          final decoded = jsonDecode(cleanJson) as Map<String, dynamic>;
          // Cache the successful summary for future instant zero-cost retrieval
          await GeminiResultCache.instance.put(cacheKey, cleanJson);
          return StudySheetSummary.fromJson(decoded);
        }
      } catch (e) {
        debugPrint(
          'Gemini summarization failed: $e. Falling back to local summary.',
        );
        if (e.toString().contains('429') ||
            e.toString().toLowerCase().contains('quota')) {
          await GeminiUsageTracker.instance.recordQuotaExceeded(
            operation: 'sheet_summary',
            model: _selectedModel,
          );
        } else {
          await GeminiUsageTracker.instance.recordError(
            e.toString(),
            operation: 'sheet_summary',
            model: _selectedModel,
          );
        }
      }
    }

    return _generateLocalSummary(content: content, subject: subject);
  }

  /// Deep Mistake Explainer: Generates a 3-section Bengali explanation (Trap, Memory Hook, High-Yield Fact).
  /// Uses content-hash caching so repeated clicks on the same mistake explanation cost 0 tokens.
  /// Checks a mentor reply claim by claim.
  ///
  /// A chat answer is prose carrying several assertions, so one verdict over
  /// the whole thing would let a single wrong line hide behind everything
  /// else that is right. Each claim is quoted and judged separately, and the
  /// counts travel with the result so partial coverage is visible.
  ///
  /// [priorContext] carries the exchange before this one, because a reply to
  /// "আর বলো" cannot be read on its own.
  ///
  /// Returns null when nothing usable came back. Nothing here edits the
  /// message being checked.
  Future<ChatVerificationResult?> verifyChatAnswer({
    required String userQuestion,
    required String aiAnswer,
    String priorContext = '',
  }) async {
    await init();

    // Everything that shapes the judgement is in the key, so a follow-up read
    // under different context cannot reuse an earlier verdict.
    final payload = '$priorContext||$userQuestion||$aiAnswer';
    final cacheKey = GeminiResultCache.instance.computeKeyFromString(
      operation: 'chat_verification',
      promptVersion: 'v1.0',
      model: _selectedModel,
      payloadText: payload,
    );

    final cached = await GeminiResultCache.instance.get(cacheKey);
    if (cached != null && cached.isNotEmpty) {
      final decoded = _decodeChatVerification(cached);
      if (decoded != null) {
        await GeminiUsageTracker.instance.recordCacheHit(
          operation: 'chat_verification',
          model: _selectedModel,
        );
        return decoded;
      }
    }

    if (_model == null) return null;

    final contextBlock = priorContext.trim().isEmpty
        ? ''
        : 'Earlier in the conversation:\n$priorContext\n\n';

    final prompt =
        '''
You are checking one answer a study mentor gave a BCS candidate in Bangladesh.

You have NO web access and NO way to look anything up. Judge from the text itself plus well-established general knowledge, and say when that is not enough.

$contextBlock The candidate asked: $userQuestion

The mentor answered:
$aiAnswer

Pull out the claims in that answer which can be checked independently. Group related sentences into one claim rather than splitting every line; aim for the few that carry the answer, at most six. Quote each one as written.

For each claim set kind to:
- "mathematical" for arithmetic, ratios, percentages, units
- "logical" for internal consistency, where the answer contradicts itself
- "factual" for anything about the world that would need a source

Then a verdict:
- "supported": you can show it holds from the text or from arithmetic
- "likely_incorrect": you can point to the specific error
- "inconclusive": settling it needs a source you cannot consult. Use this for nearly every "factual" claim, because recall is not verification.

Set claims_found to how many checkable claims the answer makes, and claims_evaluated to how many you judged. If you could not cover them all, set extraction_complete false and say why in extraction_note. Do not quietly check only the easy ones.

Write every reasoning in Bengali, one sentence. Never cite a source or a URL.
''';

    try {
      final response = await _model!.generateContent([
        Content.text(prompt),
      ], generationConfig: _chatVerificationConfig);

      await GeminiUsageTracker.instance.recordSuccess(
        tokens: response.usageMetadata?.totalTokenCount ?? 0,
        actualInputTokens: response.usageMetadata?.promptTokenCount,
        actualOutputTokens: response.usageMetadata?.candidatesTokenCount,
        actualTotalTokens: response.usageMetadata?.totalTokenCount,
        operation: 'chat_verification',
        model: _selectedModel,
      );

      final raw = response.text;
      if (raw == null || raw.trim().isEmpty) return null;

      final result = _decodeChatVerification(raw);
      if (result != null) {
        await GeminiResultCache.instance.put(cacheKey, raw);
      }
      return result;
    } catch (e) {
      debugPrint('Chat verification failed: $e');
      final lower = e.toString().toLowerCase();
      if (lower.contains('429') ||
          lower.contains('resource_exhausted') ||
          lower.contains('quota')) {
        await GeminiUsageTracker.instance.recordQuotaExceeded();
      } else {
        await GeminiUsageTracker.instance.recordError(e.toString());
      }
      return null;
    }
  }

  /// Parses a claim-level reply, returning null for anything malformed.
  @visibleForTesting
  static ChatVerificationResult? decodeChatVerification(String raw) =>
      _decodeChatVerification(raw);

  static ChatVerificationResult? _decodeChatVerification(String raw) {
    try {
      var cleaned = raw.trim();
      if (cleaned.startsWith('```')) {
        cleaned = cleaned.replaceFirst(RegExp(r'^```[a-zA-Z]*'), '').trim();
        if (cleaned.endsWith('```')) {
          cleaned = cleaned.substring(0, cleaned.length - 3).trim();
        }
      }
      final decoded = jsonDecode(cleaned);
      if (decoded is! Map) return null;
      return ChatVerificationResult.tryFromJson(
        decoded.cast<String, Object?>(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Rechecks a stored MCQ by answering it again from scratch.
  ///
  /// The verifier is given the question and the options and nothing else: not
  /// the saved answer, and not the explanation, which names the answer in
  /// prose. Showing it either would turn the check into agreement with a
  /// claim it had already been handed. It answers the question, and the app
  /// compares afterwards.
  ///
  /// The stored explanation is still examined, but locally and
  /// deterministically, so a self-contradicting one is caught without
  /// leaking the answer into the prompt.
  ///
  /// Returns null when nothing usable came back. Nothing here writes to the
  /// question; accepting a correction is a separate, explicit step.
  Future<McqVerification?> verifyAnswer({
    required String subject,
    required String topic,
    required String questionText,
    required List<String> options,
    required int correctIndex,
    required int selectedIndex,
    required String explanation,
    bool userDecided = false,
  }) async {
    await init();
    if (options.isEmpty) return null;

    // Only what the verifier actually sees goes in the key. The saved answer
    // is not part of the request, so including it would miss the cache for no
    // reason; the comparison against it is redone locally every time.
    final payload = '$subject|$topic|$questionText|${options.join("~")}';
    final cacheKey = GeminiResultCache.instance.computeKeyFromString(
      operation: 'mcq_independent_solve',
      promptVersion: 'v1.0',
      model: _selectedModel,
      payloadText: payload,
    );

    IndependentSolve? solve;

    final cached = await GeminiResultCache.instance.get(cacheKey);
    if (cached != null && cached.isNotEmpty) {
      solve = _decodeSolve(cached);
      if (solve != null) {
        await GeminiUsageTracker.instance.recordCacheHit(
          operation: 'mcq_independent_solve',
          model: _selectedModel,
        );
      }
    }

    if (solve == null) {
      if (_model == null) return null;

      final numbered = [
        for (var i = 0; i < options.length; i++) '$i. ${options[i]}',
      ].join('\n');

      final prompt =
          '''
Answer this multiple-choice question from a Bangladeshi competitive exam (BCS, Bank, Government Recruitment).

You have NO web access. Work from the question itself and well-established general knowledge.

Subject: $subject
Topic: $topic

Question: $questionText
Options:
$numbered

Pick the option you believe is correct and put its number in chosen_index (0-based).

Set basis to:
- "computation" if you reached it by arithmetic or a rule you worked through
- "internal_logic" if the question itself determines the answer
- "recall" if you are remembering the fact. Be honest here; most factual questions are recall.

If more than one option is defensible set ambiguity to "multiple_correct". If the question itself is unclear set it to "unclear_question". In either case still give your best chosen_index, but say why in reasoning.

If you cannot settle on any option, set chosen_index to -1.

Write reasoning in Bengali, one or two sentences. Never cite a source or a URL.
''';

      try {
        final response = await _model!.generateContent([
          Content.text(prompt),
        ], generationConfig: _mcqSolveConfig);

        await GeminiUsageTracker.instance.recordSuccess(
          tokens: response.usageMetadata?.totalTokenCount ?? 0,
          actualInputTokens: response.usageMetadata?.promptTokenCount,
          actualOutputTokens: response.usageMetadata?.candidatesTokenCount,
          actualTotalTokens: response.usageMetadata?.totalTokenCount,
          operation: 'mcq_independent_solve',
          model: _selectedModel,
        );

        final raw = response.text;
        if (raw == null || raw.trim().isEmpty) return null;

        solve = _decodeSolve(raw);
        if (solve == null) return null;
        await GeminiResultCache.instance.put(cacheKey, raw);
      } catch (e) {
        debugPrint('MCQ independent solve failed: $e');
        final lower = e.toString().toLowerCase();
        if (lower.contains('429') ||
            lower.contains('resource_exhausted') ||
            lower.contains('quota')) {
          await GeminiUsageTracker.instance.recordQuotaExceeded();
        } else {
          await GeminiUsageTracker.instance.recordError(e.toString());
        }
        return null;
      }
    }

    return McqVerification.decide(
      solve: solve,
      storedIndex: correctIndex,
      storedExplanation: explanation,
      optionCount: options.length,
      userDecided: userDecided,
    );
  }

  /// Takes a second look at a stored question using the user's own argument.
  ///
  /// Unlike [verifyAnswer] this does show the model the stored answer, because
  /// the user is asking it to judge that answer rather than to produce one
  /// independently. The result is a suggestion either way: nothing is written
  /// without the user accepting it.
  Future<EvidenceReview?> reviewWithUserEvidence({
    required String subject,
    required String topic,
    required String questionText,
    required List<String> options,
    required int correctIndex,
    required String explanation,
    required String userEvidence,
  }) async {
    await init();
    if (options.isEmpty) return null;
    final evidence = userEvidence.trim();
    if (evidence.isEmpty) return null;
    if (_model == null) return null;

    // The saved answer is not in the request, so it is not in the key either.
    final payload = '$questionText|${options.join("~")}|$evidence';
    final cacheKey = GeminiResultCache.instance.computeKeyFromString(
      operation: 'mcq_evidence_review',
      promptVersion: 'v1.0',
      model: _selectedModel,
      payloadText: payload,
    );

    Map<String, Object?>? decoded;

    final cached = await GeminiResultCache.instance.get(cacheKey);
    if (cached != null && cached.isNotEmpty) {
      decoded = _decodeJsonObject(cached);
      if (decoded != null) {
        await GeminiUsageTracker.instance.recordCacheHit(
          operation: 'mcq_evidence_review',
          model: _selectedModel,
        );
      }
    }

    if (decoded == null) {
      final numbered = [
        for (var i = 0; i < options.length; i++) '$i. ${options[i]}',
      ].join('\n');

      final prompt =
          '''
A user is challenging the saved answer to a multiple-choice question from a Bangladeshi competitive exam. Work out the answer yourself and judge their argument.

You have NO web access. Work from the question, the options and the user's reasoning.

You are NOT being told which option is currently saved, and you must not guess at it. Answer the question on its own merits.

Subject: $subject
Topic: $topic

Question: $questionText
Options:
$numbered

The user says:
$evidence

Set reviewer_index to the option YOU believe is correct, or -1 if you cannot settle on one.

Set user_reasoning_sound to true only if the user's argument holds up when you examine it yourself. A confident user can still be wrong; say so in reasoning when they are.

Then look at the question itself and set question_flaw:
- "duplicate_options" if two options express the SAME value (for example 10:6 and 5:3 are one ratio written twice)
- "no_correct_option" if the right answer is not among the options
- "unclear_wording" if the question admits more than one reading
- "none" otherwise

Only when the question itself is broken, put a fixed version in suggested_question_text and a fixed set in suggested_options. Otherwise return an empty string and an empty array. Keep the same number of options where you can, and keep them in Bengali.

Write reasoning in Bengali, two or three sentences, speaking to the user. Never cite a source or a URL.
''';

      try {
        final response = await _model!.generateContent([
          Content.text(prompt),
        ], generationConfig: _evidenceReviewConfig);

        await GeminiUsageTracker.instance.recordSuccess(
          tokens: response.usageMetadata?.totalTokenCount ?? 0,
          actualInputTokens: response.usageMetadata?.promptTokenCount,
          actualOutputTokens: response.usageMetadata?.candidatesTokenCount,
          actualTotalTokens: response.usageMetadata?.totalTokenCount,
          operation: 'mcq_evidence_review',
          model: _selectedModel,
        );

        final raw = response.text;
        if (raw == null || raw.trim().isEmpty) return null;

        decoded = _decodeJsonObject(raw);
        if (decoded == null) return null;
        await GeminiResultCache.instance.put(cacheKey, raw);
      } catch (e) {
        debugPrint('MCQ evidence review failed: $e');
        final lower = e.toString().toLowerCase();
        if (lower.contains('429') ||
            lower.contains('resource_exhausted') ||
            lower.contains('quota')) {
          await GeminiUsageTracker.instance.recordQuotaExceeded();
        } else {
          await GeminiUsageTracker.instance.recordError(e.toString());
        }
        return null;
      }
    }

    final opinion = EvidenceOpinion.tryFromJson(
      decoded,
      optionCount: options.length,
    );
    if (opinion == null) return null;

    return EvidenceReview.decide(
      opinion: opinion,
      storedIndex: correctIndex,
      userEvidence: evidence,
    );
  }

  /// Parses a review reply, returning null for anything malformed.
  @visibleForTesting
  static EvidenceReview? decodeEvidenceReview(
    String raw, {
    required String userEvidence,
    required int optionCount,
    required int storedIndex,
  }) {
    final json = _decodeJsonObject(raw);
    if (json == null) return null;
    final opinion = EvidenceOpinion.tryFromJson(json, optionCount: optionCount);
    if (opinion == null) return null;
    return EvidenceReview.decide(
      opinion: opinion,
      storedIndex: storedIndex,
      userEvidence: userEvidence,
    );
  }

  /// Turns a spoken question into text for the chat box.
  ///
  /// Deliberately transcription only. Sending the audio straight to the
  /// mentor would answer in one call, but then the thread would hold no
  /// record of what was actually said, and a misheard Bengali word would be
  /// answered rather than corrected. The user sees the text first.
  Future<String?> transcribeVoice(File audioFile) async {
    await init();
    if (_model == null) return null;
    if (!await audioFile.exists()) return null;

    // An AAC header alone runs to roughly a kilobyte, so anything this small
    // carries no speech and is not worth a call.
    final size = await audioFile.length();
    if (size < 2500) {
      debugPrint('Voice transcribe: $size bytes, treating as silence');
      return null;
    }

    try {
      final bytes = await audioFile.readAsBytes();
      final response = await _model!.generateContent([
        Content.multi([
          TextPart(
            'Transcribe this audio exactly as spoken. It is a Bangladeshi '
            'student asking their study mentor something, usually in Bengali '
            'and often mixing in English words; keep those words as they were '
            'said. Return the transcription alone, with no quotes, no '
            'translation and no commentary. Return an empty string if there '
            'is no speech.',
          ),
          DataPart(_audioMimeType(audioFile.path), bytes),
        ]),
      ], generationConfig: _proseConfig);

      await GeminiUsageTracker.instance.recordSuccess(
        tokens: response.usageMetadata?.totalTokenCount ?? 0,
        actualInputTokens: response.usageMetadata?.promptTokenCount,
        actualOutputTokens: response.usageMetadata?.candidatesTokenCount,
        actualTotalTokens: response.usageMetadata?.totalTokenCount,
        operation: 'voice_transcribe',
        model: _selectedModel,
      );

      final text = response.text?.trim();
      debugPrint(
        'Voice transcribe: ${text?.length ?? 0} chars from $size bytes',
      );
      return (text == null || text.isEmpty) ? null : text;
    } catch (e) {
      debugPrint('Voice transcribe failed: $e');
      final lower = e.toString().toLowerCase();
      if (lower.contains('429') ||
          lower.contains('resource_exhausted') ||
          lower.contains('quota')) {
        await GeminiUsageTracker.instance.recordQuotaExceeded();
      } else {
        await GeminiUsageTracker.instance.recordError(e.toString());
      }
      return null;
    }
  }

  static String _audioMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.m4a') || lower.endsWith('.aac')) return 'audio/mp4';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.ogg')) return 'audio/ogg';
    return 'audio/mp4';
  }

  /// Parses an independent solve, returning null for anything malformed.
  @visibleForTesting
  static IndependentSolve? decodeSolve(String raw) => _decodeSolve(raw);

  static IndependentSolve? _decodeSolve(String raw) {
    final json = _decodeJsonObject(raw);
    if (json == null) return null;
    return IndependentSolve.tryFromJson(json);
  }

  /// Reads a JSON object out of a model reply, tolerating markdown fences.
  static Map<String, Object?>? _decodeJsonObject(String raw) {
    try {
      var cleaned = raw.trim();
      if (cleaned.startsWith('```')) {
        cleaned = cleaned.replaceFirst(RegExp(r'^```[a-zA-Z]*'), '').trim();
        if (cleaned.endsWith('```')) {
          cleaned = cleaned.substring(0, cleaned.length - 3).trim();
        }
      }
      final decoded = jsonDecode(cleaned);
      if (decoded is! Map) return null;
      return decoded.cast<String, Object?>();
    } catch (_) {
      return null;
    }
  }

  Future<String> explainMistake({
    required String subject,
    required String topic,
    required String questionText,
    required List<String> options,
    required String userAns,
    required String correctAns,
    required String explanation,
  }) async {
    await init();

    final payload =
        '$subject|$topic|$questionText|${options.join(",")}|$userAns|$correctAns|$explanation';
    final cacheKey = GeminiResultCache.instance.computeKeyFromString(
      operation: 'mistake_explain',
      promptVersion: 'v2.1',
      model: _selectedModel,
      payloadText: payload,
    );

    // 1. Check cache first
    final cached = await GeminiResultCache.instance.get(cacheKey);
    if (cached != null && cached.isNotEmpty) {
      await GeminiUsageTracker.instance.recordCacheHit(
        operation: 'mistake_explain',
        model: _selectedModel,
      );
      return cached;
    }

    if (_model == null) {
      return _generateLocalMistakeExplanation(
        userAns: userAns,
        correctAns: correctAns,
        topic: topic,
        explanation: explanation,
      );
    }

    try {
      final prompt =
          '''
You are a mentor for BCS and government job exams in Bangladesh. A candidate got this wrong.

Subject: $subject
Topic: $topic
Question: $questionText
Options: ${options.join(', ')}
They chose: $userAns
Correct: $correctAns
Existing explanation: ${_shorten(explanation, 300)}

IMPORTANT VALIDITY & REDUNDANCY CHECK:
First, inspect if the question stem itself is factually flawed, has no correct options, is ambiguous, or is completely obsolete/redundant for BCS/PSC syllabus (e.g. outdated one-time GK from years ago or syllabus-irrelevant questions).
- If the question is FLAWED, OUTDATED, or REDUNDANT:
  Begin your response with an alert box:
  ⚠️ **সতর্কতা: প্রশ্নটি ত্রুটিপূর্ণ বা অপ্রাসঙ্গিক (Flawed / Redundant Question)**
  [Explain why this question is invalid or unnecessary for BCS, and explicitly advise the candidate to delete/exclude or correct it instead of memorizing it.]
- Then (or if question is valid), reply in Bengali under these three headings:

১. 🎯 **ভুল হওয়ার মূল কারণ ও ফাঁদ (The Trap):**
২. 💡 **মনে রাখার শর্টকাট / নেমোনিক ট্রিক (Memory Hook):**
৩. 📌 **বিসিএস ও চাকরির পরীক্ষায় সম্পর্কিত তথ্য (Related High-Yield Fact):**

Under them, in order: why candidates fall for this one; a hook that makes it stick for good; what else PSC tends to ask from this rule or topic.

Use Unicode symbols (°, →, ×, ², ³), no LaTeX, no stray markdown. Friendly, crisp, under 250 words.
''';

      final response = await _model!.generateContent([
        Content.text(prompt),
      ], generationConfig: _proseConfig);
      await GeminiUsageTracker.instance.recordSuccess(
        tokens: response.usageMetadata?.totalTokenCount ?? 0,
        actualInputTokens: response.usageMetadata?.promptTokenCount,
        actualOutputTokens: response.usageMetadata?.candidatesTokenCount,
        actualTotalTokens: response.usageMetadata?.totalTokenCount,
        operation: 'mistake_explain',
        model: _selectedModel,
      );

      final rawText = response.text ?? 'ব্যাখ্যা প্রস্তুত করা যায়নি।';
      final cleanText = BengaliMathSanitizer.sanitize(rawText);

      // Save to cache
      await GeminiResultCache.instance.put(cacheKey, cleanText);
      return cleanText;
    } catch (e) {
      debugPrint('Mistake explanation failed: $e');
      if (e.toString().contains('429') ||
          e.toString().toLowerCase().contains('quota')) {
        await GeminiUsageTracker.instance.recordQuotaExceeded(
          operation: 'mistake_explain',
          model: _selectedModel,
        );
      } else {
        await GeminiUsageTracker.instance.recordError(
          e.toString(),
          operation: 'mistake_explain',
          model: _selectedModel,
        );
      }
      return _generateLocalMistakeExplanation(
        userAns: userAns,
        correctAns: correctAns,
        topic: topic,
        explanation: explanation,
      );
    }
  }

  /// Exam Quick Revision Cheat-Sheet (4-bullet points).
  /// Uses content-hash caching so repeated openings cost 0 tokens.
  Future<String> getExamQuickRevision({
    required String subject,
    required String title,
    required String topicsCovered,
    String? examTime,
    String? trackName,
  }) async {
    await init();

    final payload = '$subject|$title|$topicsCovered';
    final cacheKey = GeminiResultCache.instance.computeKeyFromString(
      operation: 'exam_cheat_sheet',
      promptVersion: 'v2.0',
      model: _selectedModel,
      payloadText: payload,
    );

    // 1. Check cache
    final cached = await GeminiResultCache.instance.get(cacheKey);
    if (cached != null && cached.isNotEmpty) {
      await GeminiUsageTracker.instance.recordCacheHit(
        operation: 'exam_cheat_sheet',
        model: _selectedModel,
      );
      return cached;
    }

    if (_model == null) {
      return _generateLocalExamRevision(
        title: title,
        topicsCovered: topicsCovered,
        examTime: examTime,
        trackName: trackName,
      );
    }

    try {
      final prompt =
          '''
You are a competitive exam tutor for BCS and LiveMCQ exams in Bangladesh.
Provide a quick, high-yield, 4-bullet point revision cheat-sheet for:
Subject: $subject
Title: $title
Topics: $topicsCovered

Keep it crisp, actionable, in Bengali with English terminology where appropriate.
Use clean Unicode (e.g. °, →, ×, ², ³). No LaTeX symbols.
''';

      final response = await _model!.generateContent([
        Content.text(prompt),
      ], generationConfig: _proseConfig);
      await GeminiUsageTracker.instance.recordSuccess(
        tokens: response.usageMetadata?.totalTokenCount ?? 0,
        actualInputTokens: response.usageMetadata?.promptTokenCount,
        actualOutputTokens: response.usageMetadata?.candidatesTokenCount,
        actualTotalTokens: response.usageMetadata?.totalTokenCount,
        operation: 'exam_cheat_sheet',
        model: _selectedModel,
      );

      final raw = response.text ?? 'Summary generated.';
      final cleaned = BengaliMathSanitizer.sanitize(raw);

      await GeminiResultCache.instance.put(cacheKey, cleaned);
      return cleaned;
    } catch (e) {
      debugPrint('Exam quick revision failed: $e');
      if (e.toString().contains('429') ||
          e.toString().toLowerCase().contains('quota')) {
        await GeminiUsageTracker.instance.recordQuotaExceeded(
          operation: 'exam_cheat_sheet',
          model: _selectedModel,
        );
      } else {
        await GeminiUsageTracker.instance.recordError(
          e.toString(),
          operation: 'exam_cheat_sheet',
          model: _selectedModel,
        );
      }
      return _generateLocalExamRevision(
        title: title,
        topicsCovered: topicsCovered,
        examTime: examTime,
        trackName: trackName,
      );
    }
  }

  String _generateLocalMistakeExplanation({
    required String userAns,
    required String correctAns,
    required String topic,
    required String explanation,
  }) {
    return '''
১. 🎯 **ভুল হওয়ার কারণ ও ফাঁদ:**
"$userAns" অপশনটি প্রায়ই বিভ্রান্তিকর হিসেবে দেওয়া থাকে। পরীক্ষার্থীরা তাড়াহুড়োয় মূল নিয়ম মিস করে এটি দাগিয়ে ফেলেন।

২. 💡 **সঠিক নিয়ম ও শর্টকাট:**
সঠিক উত্তর হলো **"$correctAns"**।
${explanation.isNotEmpty ? explanation : 'এই নিয়মটি ভালোভাবে আয়ত্ত করুন যাতে পরবর্তীতে অনুরূপ প্রশ্নে দ্রুত সঠিক সিদ্ধান্তে আসা যায়।'}

৩. 📌 **পরীক্ষার জন্য গুরুত্বপূর্ণ টিপ:**
"$topic" টপিক থেকে বিগত বছরের বিসিএস ও পিএসসির পরীক্ষায় নিয়মিত ১-২টি প্রশ্ন আসে। পরীক্ষার আগে এই রুলটি একবার রিভিশন দিয়ে যাবেন।
''';
  }

  String _generateLocalExamRevision({
    required String title,
    required String topicsCovered,
    String? examTime,
    String? trackName,
  }) {
    return '💡 **$title** Quick Revision:\n\n'
        '• **Topics**: $topicsCovered\n'
        '• **Exam Time**: ${examTime ?? '10:00 PM'}${trackName != null ? ' ($trackName)' : ''}\n'
        '• **High-Yield Strategy**: Review key definitions, formulas, and past BCS/LiveMCQ question patterns.\n'
        '• **Pro Tip**: Use the floating bubble during solution review to record any mistakes into your Mistake Notebook!';
  }

  String _extractCleanJson(String input) {
    var cleaned = input.trim();
    if (cleaned.startsWith('```json')) {
      cleaned = cleaned.substring(7);
    } else if (cleaned.startsWith('```')) {
      cleaned = cleaned.substring(3);
    }
    if (cleaned.endsWith('```')) {
      cleaned = cleaned.substring(0, cleaned.length - 3);
    }
    return cleaned.trim();
  }

  /// Intelligent deterministic rule-based local generator
  AdaptiveStudyPlan _generateLocalAdaptivePlan({
    required String energyLevel,
    required int fatigueScore,
    required List<WeakTopic> weakTopics,
    required List<ExamSchedule> upcomingExams,
    bool isOffDay = false,
  }) {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final isLowEnergy = energyLevel.toLowerCase() == 'low' || fatigueScore >= 7;
    final isMediumEnergy =
        energyLevel.toLowerCase() == 'medium' && fatigueScore < 7;

    // Pick top weak topic
    final primaryTopic = weakTopics.isNotEmpty ? weakTopics.first : null;

    final secondaryTopic = weakTopics.length > 1 ? weakTopics[1] : null;

    if (isOffDay) {
      return AdaptiveStudyPlan(
        date: today,
        energyLevel: 'Weekend/Off-Day',
        fatigueScore: 0,
        motivationalQuote: 'আজ আপনার ছুটির দিন! কোনো অফিস তাড়াহুড়া নেই। আজকের দিনটি BCS প্রস্তুতিতে এগিয়ে যাওয়ার সেরা এক্সিলারেটর।',
        summary: 'আজকের ডেডিকেটেড প্ল্যান: দুর্বল টপিক রিভিশন ও ১টি মডেল টেস্ট প্র্যাকটিস, সাথে সুন্দর ফ্যামিলি টাইম।',
        recommendedStudyMinutes: 75,
        recommendedFamilyMinutes: 180,
        familyAndWellbeingAdvice: 'ছুটির দিনে পরিবার ও জীবনসঙ্গীকে পর্যাপ্ত সময় দেওয়া রিচার্জ হওয়ার মূল চাবিকাঠি। বিকেলে মন খুলে আড্ডা দিন।',
        burnoutWarning: null,
        tasks: [
          StudyTask(
            id: 'task_${DateTime.now().millisecondsSinceEpoch}_1',
            title: primaryTopic != null
                ? 'ডিপ রিভিশন ও নোটস: ${primaryTopic.topicName}'
                : 'দুর্বল বিষয়ের মূল ধারণা ও নোট রিভিশন',
            subject: primaryTopic?.subject ?? 'Bangla Grammar',
            estimatedMinutes: 30,
            taskType: 'deep_study',
            actionablePrompt:
                '${primaryTopic?.topicName ?? 'বাংলা ব্যাকরণ'} টপিকটির গুরুত্বপূর্ণ নিয়ম, ব্যতিক্রম ও বিগত বছরের প্রশ্ন ভালো করে পড়ুন।',
          ),
          StudyTask(
            id: 'task_${DateTime.now().millisecondsSinceEpoch}_2',
            title: upcomingExams.isNotEmpty
                ? 'LiveMCQ স্পেশাল ড্রিল: ${upcomingExams.first.title}'
                : 'LiveMCQ ফুল ৫০ মার্কস মডেল টেস্ট',
            subject: upcomingExams.isNotEmpty
                ? upcomingExams.first.topicsCovered
                : 'General BCS',
            estimatedMinutes: 30,
            taskType: 'mock_test',
            actionablePrompt: 'পরীক্ষার মতো শান্ত পরিবেশে একটি সম্পূর্ণ টেস্ট দিন এবং ভুলগুলো চিহ্নিত করুন।',
          ),
          if (secondaryTopic != null)
            StudyTask(
              id: 'task_${DateTime.now().millisecondsSinceEpoch}_3',
              title: 'কুইক ফর্মুলা রিভিশন: ${secondaryTopic.topicName}',
              subject: secondaryTopic.subject,
              estimatedMinutes: 15,
              taskType: 'quick_review',
              actionablePrompt: 'শর্টকাট নোট বা ফর্মুলা কার্ডে চোখ বুলিয়ে নিন।',
            ),
        ],
      );
    }

    if (isLowEnergy) {
      return AdaptiveStudyPlan(
        date: today,
        energyLevel: 'Low',
        fatigueScore: fatigueScore,
        motivationalQuote: 'আজকের সারাদিনের কোডিংয়ের পর আপনার মস্তিষ্কের বিশ্রাম দরকার। মাত্র ১০ মিনিটের মাইক্রো-কমিটমেন্টই যথেষ্ট!',
        summary: 'আজ ভারী পড়া একেবারেই বাদ দিন। মাত্র ১০ মিনিট একটি দুর্বল বিষয়ে চোখ বুলিয়ে বাকি সন্ধ্যা পরিবারকে দিন।',
        recommendedStudyMinutes: 10,
        recommendedFamilyMinutes: 90,
        familyAndWellbeingAdvice: 'অফিসের স্ক্রিনটাইমের পর বিশ্রাম নিন। জীবনসঙ্গী ও পরিবারের সাথে গল্প করুন, চা খান এবং তাড়াতাড়ি ঘুমানোর প্রস্তুতি নিন।',
        burnoutWarning: fatigueScore >= 8
            ? 'হাই ফ্যাটিগ লেভেল ডিটেক্টেড! আজ কোনোভাবেই ১ ঘণ্টার বেশি জাগবেন না।'
            : null,
        tasks: [
          StudyTask(
            id: 'task_${DateTime.now().millisecondsSinceEpoch}_1',
            title: primaryTopic != null
                ? '১০টি বিগত বছরের MCQ: ${primaryTopic.topicName}'
                : '১০টি লাইভএমসিকিউ বিগত বছরের প্রশ্ন সমাধান',
            subject: primaryTopic?.subject ?? 'Bangla Grammar',
            estimatedMinutes: 10,
            taskType: 'micro_mcq',
            actionablePrompt:
                'LiveMCQ অ্যাপে গিয়ে ${primaryTopic?.topicName ?? 'কারক ও বিভক্তি'} থেকে যেকোনো ১০টি প্রশ্ন দ্রুত দাগান। কোনো ব্যাখ্যা মুখস্থের চাপ নেবেন না।',
          ),
        ],
      );
    } else if (isMediumEnergy) {
      return AdaptiveStudyPlan(
        date: today,
        energyLevel: 'Medium',
        fatigueScore: fatigueScore,
        motivationalQuote: 'ধারাবাহিকতাই আসল চাবিকাঠি। ৩০ মিনিটের ব্যালান্সড রিভিশন আপনাকে এগিয়ে রাখবে।',
        summary: 'পরবর্তী LiveMCQ পরীক্ষার একটি দুর্বল টপিক রিভিশন এবং ১৫টি প্র্যাকটিস প্রশ্ন।',
        recommendedStudyMinutes: 25,
        recommendedFamilyMinutes: 60,
        familyAndWellbeingAdvice: 'পড়ার পর অন্তত ১ ঘণ্টা পরিবারের সাথে কোয়ালিটি টাইম কাটান। মোবাইল দূরে রাখুন।',
        tasks: [
          StudyTask(
            id: 'task_${DateTime.now().millisecondsSinceEpoch}_1',
            title: primaryTopic != null
                ? 'রুলস রিকল: ${primaryTopic.topicName}'
                : 'রুলস রিকল: সমাস ও সন্ধি',
            subject: primaryTopic?.subject ?? 'Bangla Grammar',
            estimatedMinutes: 10,
            taskType: 'quick_rule',
            actionablePrompt:
                '১০ মিনিট নোট শিট থেকে মূল নিয়মগুলো একবার চোখ বুলিয়ে নিন।',
          ),
          StudyTask(
            id: 'task_${DateTime.now().millisecondsSinceEpoch}_2',
            title: secondaryTopic != null
                ? '১৫টি প্র্যাকটিস MCQ: ${secondaryTopic.topicName}'
                : '১৫টি গণিত শর্টকাট প্র্যাকটিস',
            subject: secondaryTopic?.subject ?? 'Mathematics',
            estimatedMinutes: 15,
            taskType: 'micro_mcq',
            actionablePrompt: 'LiveMCQ-এ গিয়ে নির্ধারিত টপিকের বিগত ১০ বছরের প্রশ্নগুলো টেস্ট মোডে দিন।',
          ),
        ],
      );
    } else {
      return AdaptiveStudyPlan(
        date: today,
        energyLevel: 'High',
        fatigueScore: fatigueScore,
        motivationalQuote: 'আজ এনার্জি লেভেল চমৎকার! কঠিন দুর্বল বিষয়গুলো শেষ করার সেরা সুযোগ।',
        summary: 'আসন্ন LiveMCQ পরীক্ষার জন্য ৪৫ মিনিটের ইন-ডেপথ দুর্বল টপিক প্র্যাকটিস ও স্পিড ড্রিল।',
        recommendedStudyMinutes: 45,
        recommendedFamilyMinutes: 45,
        familyAndWellbeingAdvice: 'পড়া শেষে পরিবারকে জানিয়ে দিন আপনার আজকের লক্ষ্য পূরণ হয়েছে। একসাথে রাতের খাবার উপভোগ করুন।',
        tasks: [
          StudyTask(
            id: 'task_${DateTime.now().millisecondsSinceEpoch}_1',
            title: primaryTopic != null
                ? 'ডিপ ড্রিল: ${primaryTopic.topicName}'
                : 'ডিপ ড্রিল: কারক ও বিভক্তি',
            subject: primaryTopic?.subject ?? 'Bangla Grammar',
            estimatedMinutes: 20,
            taskType: 'concept_review',
            actionablePrompt: 'কনফিউজিং উদাহরণগুলো আলাদা খাতায় টুকে রাখুন এবং ৩টি ব্যতিক্রম নোট করুন।',
          ),
          StudyTask(
            id: 'task_${DateTime.now().millisecondsSinceEpoch}_2',
            title: secondaryTopic != null
                ? '২৫টি লাইভ স্পিড টেস্ট: ${secondaryTopic.topicName}'
                : '২৫টি ম্যাথ স্পিড টেস্ট',
            subject: secondaryTopic?.subject ?? 'Mathematics',
            estimatedMinutes: 25,
            taskType: 'micro_mcq',
            actionablePrompt:
                'টাইমার দিয়ে ২৫টি প্রশ্ন ২০ মিনিটে সমাধানের স্পিড টেস্ট দিন।',
          ),
        ],
      );
    }
  }

  StudySheetSummary _generateLocalSummary({
    required String content,
    String? subject,
  }) {
    return StudySheetSummary(
      title: subject != null
          ? '$subject High-Yield Summary'
          : 'LiveMCQ Topic High-Yield Card',
      highYieldPoints: [
        'বিগত ৫টি BCS প্রিলিমিনারিতে এই টপিক থেকে প্রতি বছর অন্তত ২-৩ নম্বর এসেছে।',
        'ব্যতিক্রমী নিয়ম এবং অপশনে কনফিউজিং ডিস্ট্রাক্টরের দিকে বিশেষ খেয়াল রাখুন।',
        'শর্টকাট মেথড ব্যবহার করে প্রশ্নের প্যাটার্ন ৫০ সেকেন্ডের মধ্যে শনাক্ত করুন।',
        'সরাসরি মুখস্থ করার চেয়ে উদাহরণের পার্থক্য তুলনা করে মনে রাখা সহজ।',
        'ভুল হওয়া প্রশ্নগুলো LiveMCQ ফেভারিট লিস্টে সেভ করে রাখুন।',
      ],
      recurringPastQuestions: [
        'বিগত ৩৬তম এবং ৪০তম বিসিএস প্রিলির রিপিটেড ট্র্যাপ প্রশ্ন।',
        'অপশনে কাছাকাছি দুটি সঠিক মনে হওয়া উত্তরের মধ্যে সুনির্দিষ্ট পার্থক্য।',
      ],
      mnemonics: [
        'শর্ট টেকনিক: বাক্যে ক্রিয়াপদের সাথে প্রশ্ন করে দ্রুত বিভক্তি ও কারক নির্ণয়।',
      ],
      quickCheck: [
        MicroQuizItem(
          question: 'এই বিষয়ের সবচেয়ে সাধারণ ব্যতিক্রমী নিয়ম কোনটি?',
          answer: 'সংস্কৃত তদ্ধিত ও কৃৎ প্রত্যয়ের বিশেষ রূপান্তর।',
        ),
        MicroQuizItem(
          question: 'পরীক্ষায় সবচেয়ে বেশি ভুল হওয়া প্রশ্ন কাঠামো কোনটি?',
          answer: 'নেতিবাচক প্রশ্ন ("কোনটি নয়" জাতীয় প্রশ্ন)।',
        ),
      ],
    );
  }
}
