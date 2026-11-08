import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/notification_constants.dart';
import '../../database/app_database.dart';
import '../../database/tables/weak_topics_table.dart';
import '../../utils/bengali_math_sanitizer.dart';
import 'gemini_usage_tracker.dart';
import 'models/voice_mistake_result.dart';

/// Why a voice note could not be turned into a question.
///
/// Returning null for everything made a server error look like the user
/// mumbling: the sheet said "কোনো কথা শনাক্ত করা যায়নি" whether the audio
/// was silent or the model was down, so the user re-recorded against a fault
/// that had nothing to do with them.
class VoiceParseException implements Exception {
  final String userMessage;
  final String technicalDetails;
  final bool isTransient;

  const VoiceParseException({
    required this.userMessage,
    required this.technicalDetails,
    this.isTransient = false,
  });

  @override
  String toString() => 'VoiceParseException: $technicalDetails';
}

class VoiceMistakeParserService {
  VoiceMistakeParserService._();
  static final VoiceMistakeParserService instance =
      VoiceMistakeParserService._();

  GenerativeModel? _model;
  String? _modelName;
  String? _cachedApiKey;
  String? get cachedApiKey => _cachedApiKey;
  String? get modelName => _modelName;

  static const String _voicePrompt = '''
You are an expert tutor for BCS (Bangladesh Civil Service) and LiveMCQ exams in Bangladesh.
The student made a mistake in an exam and is looking at the solution on LiveMCQ.
They spoke about the question or mistake in Bengali or Banglish.

Listen to the spoken audio (or read the text) and reconstruct a complete, rigorous Multiple Choice Question (MCQ) so the student can review and master it.

CRITICAL INSTRUCTION FOR SILENCE, NOISE, OR NON-EXAM AUDIO:
If the audio has NO speech, is completely silent, contains only background noise, breathing, static, or unintelligible murmurs with no identifiable exam question, you MUST return STRICTLY:
{
  "no_speech": true,
  "message": "No exam question or speech detected."
}
Do NOT invent, fabricate, or hallucinate a random question if no question was spoken!

If a genuine question or topic was spoken, return STRICTLY a JSON object with this exact structure:
{
  "question": "Complete formal question in Bengali or English (e.g. 'তিব্বতের মানস সরোবর হতে উৎপন্ন নদী কোনটি?')",
  "options": ["Option 1", "Option 2", "Option 3", "Option 4"],
  "correct_index": 0,
  "explanation": "Clear and detailed explanation explaining why this answer is correct and citing the rule/fact.",
  "subject": "Subject name (Bangla Grammar, English Literature, Bangladesh Affairs, International Affairs, Mathematics, General Science, Computer & ICT, Mental Ability)",
  "topic": "Specific topic or chapter name (e.g., বাংলাদেশের নদ-নদী / সমাস / Prepositions)",
  "key_rule": "The tricky rule, formula, exception or mnemonic to remember."
}

Rules:
1. Always provide 4 distinct, realistic competitive examination options.
2. The correct_index must match the correct option (0, 1, 2, or 3).
3. If spoken in Bengali, format the question and options in clean Bengali script.
4. Clean Unicode: Never use raw LaTeX syntax (e.g. Do NOT output '\$180^\\circ\$', '\\to', or '\$x^2\$'). Use native Unicode: '°' (১৮০°), '→', '×', '²', '³', '√'.
5. Return ONLY valid JSON without markdown code fences or conversational text.
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
      _modelName = modelName;
      _model = GenerativeModel(
        model: modelName,
        apiKey: key,
        generationConfig: GenerationConfig(
          responseMimeType: 'application/json',
          temperature: 0.1,
          maxOutputTokens: 8192,
        ),
      );
      debugPrint('VoiceMistakeParserService initialized with $modelName');
    } else {
      // The bubble runs in its own Flutter engine. If plugins are not
      // registered there, SharedPreferences comes back empty and the key is
      // invisible — which looks from the outside exactly like voice input
      // being broken only from the bubble.
      debugPrint(
        'VoiceMistakeParserService: NO API KEY visible in this isolate '
        '(prefs readable: ${prefs.getKeys().isNotEmpty})',
      );
    }
  }

  Future<String?> _getStoredApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(NotificationConstants.prefGeminiApiKey);
  }

  /// Parse spoken audio file (AAC / M4A / MP3 / WAV) directly via Gemini Multimodal Audio.
  /// Returns null if audio is silent, too short, has no speech, or Gemini could not detect an exam question.
  Future<VoiceMistakeResult?> parseMistakeFromAudio(
    File audioFile, {
    String? contextHint,
    int durationSeconds = 0,
  }) async {
    // 1. Audio file verification: if file does not exist or has negligible size, it's silence/empty
    if (!await audioFile.exists()) {
      return null;
    }
    final fileSize = await audioFile.length();
    // AAC header alone is ~500-1000 bytes. A recording < 2500 bytes with < 2 seconds has no speech.
    if (fileSize < 2500 && durationSeconds < 2) {
      debugPrint(
        'Audio file too small ($fileSize bytes, duration ${durationSeconds}s), treating as silence.',
      );
      return null;
    }

    await init();
    final activeModel = _modelName ?? 'gemini-flash-latest';

    if (_model != null) {
      try {
        final audioBytes = await audioFile.readAsBytes();
        final mimeType = _detectAudioMimeType(audioFile.path);

        String prompt = _voicePrompt;
        if (contextHint != null && contextHint.isNotEmpty) {
          prompt += '\nContext hint: $contextHint';
        }

        final content = [
          Content.multi([TextPart(prompt), DataPart(mimeType, audioBytes)]),
        ];

        // One retry, because a 503 here means the server was momentarily
        // busy and the user would otherwise be told to speak again for no
        // reason. Audio calls are slow, so one is enough.
        GenerateContentResponse response;
        try {
          response = await _model!.generateContent(content);
        } catch (e) {
          final lower = e.toString().toLowerCase();
          if (!lower.contains('503') &&
              !lower.contains('unavailable') &&
              !lower.contains('high demand') &&
              !lower.contains('overloaded')) {
            rethrow;
          }
          debugPrint('Voice audio: server busy, retrying once');
          await Future<void>.delayed(const Duration(seconds: 4));
          response = await _model!.generateContent(content);
        }
        await GeminiUsageTracker.instance.recordSuccess(
          tokens: response.usageMetadata?.totalTokenCount ?? 0,
          actualInputTokens: response.usageMetadata?.promptTokenCount,
          actualOutputTokens: response.usageMetadata?.candidatesTokenCount,
          actualTotalTokens: response.usageMetadata?.totalTokenCount,
          operation: 'voice_mistake_audio',
          model: activeModel,
        );

        final result = _decodeResponse(
          response.text,
          spokenRef: 'Voice note: ${audioFile.path.split('/').last}',
        );
        // A clean reply with nothing in it really does mean no question was
        // spoken, which is the one case worth asking the user to repeat.
        return result;
      } catch (e) {
        debugPrint('Gemini Voice Mistake Audio analysis error: $e');
        final text = e.toString();
        final lower = text.toLowerCase();

        if (text.contains('429') || lower.contains('quota')) {
          await GeminiUsageTracker.instance.recordQuotaExceeded(
            operation: 'voice_mistake_audio',
            model: activeModel,
          );
          throw VoiceParseException(
            userMessage: 'আজকের API কোটা শেষ। পরে আবার চেষ্টা করুন।',
            technicalDetails: text,
          );
        }

        await GeminiUsageTracker.instance.recordError(
          text,
          operation: 'voice_mistake_audio',
          model: activeModel,
        );

        // 503 and overload are the server saying "not now", not the audio
        // being unusable. Worth saying so, and worth retrying.
        final transient =
            text.contains('503') ||
            lower.contains('unavailable') ||
            lower.contains('high demand') ||
            lower.contains('overloaded') ||
            lower.contains('connection closed') ||
            lower.contains('timeout');

        throw VoiceParseException(
          userMessage: transient
              ? 'Gemini সার্ভার এই মুহূর্তে ব্যস্ত। আপনার রেকর্ডিং ঠিকই আছে — আবার চেষ্টা করুন।'
              : 'ভয়েস বিশ্লেষণ করা গেল না। ইন্টারনেট বা API key দেখুন।',
          technicalDetails: text,
          isTransient: transient,
        );
      }
    }

    throw const VoiceParseException(
      userMessage: 'Gemini API key সেট করা নেই, তাই ভয়েস বিশ্লেষণ সম্ভব নয়।',
      technicalDetails: 'model was null',
    );
  }

  /// Parse user's typed or transcribed voice text into structured mistake question.
  /// Returns null if text is empty or non-informative.
  Future<VoiceMistakeResult?> parseMistakeFromText(
    String spokenText, {
    String? contextHint,
  }) async {
    final trimmed = spokenText.trim();
    if (trimmed.isEmpty || trimmed.length < 3) {
      return null;
    }

    await init();
    final activeModel = _modelName ?? 'gemini-flash-latest';

    if (_model != null) {
      try {
        String prompt =
            '$_voicePrompt\n\n--- USER SPOKEN TEXT ---\n$trimmed\n-----------------------';
        if (contextHint != null && contextHint.isNotEmpty) {
          prompt += '\nContext hint: $contextHint';
        }

        final response = await _model!.generateContent([Content.text(prompt)]);
        await GeminiUsageTracker.instance.recordSuccess(
          tokens: response.usageMetadata?.totalTokenCount ?? 0,
          actualInputTokens: response.usageMetadata?.promptTokenCount,
          actualOutputTokens: response.usageMetadata?.candidatesTokenCount,
          actualTotalTokens: response.usageMetadata?.totalTokenCount,
          operation: 'voice_mistake_text',
          model: activeModel,
        );

        final result = _decodeResponse(response.text, spokenRef: trimmed);
        if (result != null) return result;
      } catch (e) {
        debugPrint('Gemini Voice Mistake Text analysis error: $e');
        if (e.toString().contains('429') ||
            e.toString().toLowerCase().contains('quota')) {
          await GeminiUsageTracker.instance.recordQuotaExceeded(
            operation: 'voice_mistake_text',
            model: activeModel,
          );
        } else {
          await GeminiUsageTracker.instance.recordError(
            e.toString(),
            operation: 'voice_mistake_text',
            model: activeModel,
          );
        }
      }
    }

    // Nothing is invented from a keyword in what was said. The fallback this
    // replaces answered anything containing "নদী" with a fixed ব্রহ্মপুত্র
    // question, and anything else with a placeholder whose options read
    // "বিকল্প অপশন খ/গ/ঘ". Both were saved to the mistake notebook and
    // drilled as though the user had got them wrong.
    throw const VoiceParseException(
      userMessage:
          'যা বললেন তা থেকে প্রশ্নটা বোঝা গেল না। '
          'একটু গুছিয়ে আবার বলুন, বা টাইপ করে দিন।',
      technicalDetails: 'no model result and no invented fallback',
      isTransient: false,
    );
  }

  VoiceMistakeResult? _decodeResponse(String? rawJson, {String? spokenRef}) {
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
        // Handle explicit silence / no-speech response
        if (decoded['no_speech'] == true ||
            decoded['empty'] == true ||
            decoded['error'] != null) {
          return null;
        }

        // Validate structure
        final questionText = decoded['question']?.toString().trim() ?? '';
        final rawOptions = decoded['options'];
        final optionsList = rawOptions is List ? rawOptions : [];
        if (questionText.isEmpty || optionsList.length < 2) {
          return null;
        }

        return VoiceMistakeResult.fromJson(decoded, spokenRef: spokenRef);
      }
    } catch (e) {
      debugPrint('JSON parsing error in VoiceMistakeParserService: $e');
    }
    return null;
  }

  String _detectAudioMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.mp3')) return 'audio/mp3';
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.aac')) return 'audio/aac';
    return 'audio/m4a';
  }

  String _detectImageMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  /// Parse screenshot or camera image of a LiveMCQ or test paper mistake.
  /// Solves the question on the spot with high accuracy even if official answer
  /// is not yet published on LiveMCQ.
  Future<VoiceMistakeResult?> parseMistakeFromImage(
    File imageFile, {
    String? contextHint,
  }) async {
    if (!await imageFile.exists()) return null;
    final imageBytes = await imageFile.readAsBytes();
    if (imageBytes.isEmpty) return null;

    await init();
    final activeModel = _modelName ?? 'gemini-flash-latest';

    if (_model != null) {
      try {
        final mimeType = _detectImageMimeType(imageFile.path);
        const prompt = '''
You are an expert tutor for BCS (Bangladesh Civil Service) and LiveMCQ exams in Bangladesh.
The student took a screenshot or photo of an exam question from LiveMCQ or a study guide that they got wrong or left unanswered.
Since LiveMCQ does not reveal the correct answer until the next day, you MUST solve the question yourself with 100% academic accuracy!

Task:
1. Extract the question text and all multiple-choice options from the image.
2. If the user's selected wrong answer is visible (marked in red, crossed out, or ticked), note it.
3. Solve the question independently to identify the true correct option index (0, 1, 2, or 3).
4. Provide a clear, educational, authentic Bengali explanation citing authentic rules or textbooks (e.g. বোর্ড ব্যাকরণ, সংবিধান, পিএসসি সিলেবাস).
5. Identify the exact subject (Bangla Grammar, English Literature, Bangladesh Affairs, International Affairs, Mathematics, General Science, Computer & ICT, Mental Ability) and chapter/topic.
6. Provide a 1-sentence punchy takeaway rule (key_rule).

Return STRICTLY a JSON object with this exact structure:
{
  "question": "Full Bengali/English question text",
  "options": ["Option 1", "Option 2", "Option 3", "Option 4"],
  "correct_index": 0,
  "explanation": "Detailed, educational Bengali explanation",
  "subject": "Subject name",
  "topic": "Topic name",
  "key_rule": "Short memorable rule or fact"
}
''';

        final content = [
          Content.multi([
            TextPart(
              contextHint != null && contextHint.isNotEmpty
                  ? '$prompt\nContext: $contextHint'
                  : prompt,
            ),
            DataPart(mimeType, imageBytes),
          ]),
        ];

        GenerateContentResponse response;
        try {
          response = await _model!.generateContent(content);
        } catch (e) {
          final lower = e.toString().toLowerCase();
          if (!lower.contains('503') &&
              !lower.contains('unavailable') &&
              !lower.contains('high demand') &&
              !lower.contains('overloaded')) {
            rethrow;
          }
          await Future<void>.delayed(const Duration(seconds: 3));
          response = await _model!.generateContent(content);
        }

        await GeminiUsageTracker.instance.recordSuccess(
          tokens: response.usageMetadata?.totalTokenCount ?? 0,
          actualInputTokens: response.usageMetadata?.promptTokenCount,
          actualOutputTokens: response.usageMetadata?.candidatesTokenCount,
          actualTotalTokens: response.usageMetadata?.totalTokenCount,
          operation: 'voice_mistake_image',
          model: activeModel,
        );

        final result = _decodeResponse(
          response.text,
          spokenRef: 'Screenshot: ${imageFile.path.split('/').last}',
        );
        return result;
      } catch (e) {
        debugPrint('Gemini Mistake Image analysis error: $e');
        final text = e.toString();
        final lower = text.toLowerCase();

        if (text.contains('429') || lower.contains('quota')) {
          await GeminiUsageTracker.instance.recordQuotaExceeded(
            operation: 'voice_mistake_image',
            model: activeModel,
          );
          throw VoiceParseException(
            userMessage: 'আজকের API কোটা শেষ। পরে আবার চেষ্টা করুন।',
            technicalDetails: text,
          );
        }

        await GeminiUsageTracker.instance.recordError(
          text,
          operation: 'voice_mistake_image',
          model: activeModel,
        );

        final transient =
            lower.contains('503') ||
            lower.contains('unavailable') ||
            lower.contains('overloaded') ||
            lower.contains('high demand');
        throw VoiceParseException(
          userMessage: transient
              ? 'Gemini সার্ভার এই মুহূর্তে ব্যস্ত। আবার চেষ্টা করুন।'
              : 'ছবি থেকে প্রশ্ন বিশ্লেষণ করা গেল না। স্পষ্ট ছবি বা স্ক্রিনশট দিয়ে আবার চেষ্টা করুন।',
          technicalDetails: text,
          isTransient: transient,
        );
      }
    }

    throw const VoiceParseException(
      userMessage: 'Gemini API key সেট করা নেই, তাই ছবি বিশ্লেষণ সম্ভব নয়।',
      technicalDetails: 'model was null',
    );
  }

  /// Save the mistake to Mistake Bank (DrillQuestions), Spaced Repetition (SM-2), and Weak Topics
  Future<void> saveVoiceMistakeToDatabase(
    AppDatabase db,
    VoiceMistakeResult rawResult, {
    String sourceTag = '[উৎস: LiveMCQ 🎙️]',
  }) async {
    final result = VoiceMistakeResult(
      questionText: BengaliMathSanitizer.sanitize(rawResult.questionText),
      options: rawResult.options
          .map((o) => BengaliMathSanitizer.sanitize(o))
          .toList(),
      correctIndex: rawResult.correctIndex,
      explanation: BengaliMathSanitizer.sanitize(rawResult.explanation),
      subject: rawResult.subject,
      topic: rawResult.topic,
      keyRule: BengaliMathSanitizer.sanitize(rawResult.keyRule),
    );

    // 1. Save to Spaced Repetition (Day 1 review interval)
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    await db.insertSpacedReviewItem(
      SpacedReviewItemsCompanion.insert(
        subject: result.subject,
        topic: result.topic,
        title: result.questionText.length > 60
            ? '${result.questionText.substring(0, 60)}...'
            : result.questionText,
        keyRule:
            '${result.keyRule}\nসঠিক উত্তর: ${(result.correctIndex >= 0 && result.correctIndex < result.options.length) ? result.options[result.correctIndex] : "অজানা"}\nব্যাখ্যা: ${result.explanation}',
        nextReviewDate: tomorrow,
      ),
    );

    // 2. Save into Mistake Bank (DrillRecords and DrillQuestions table)
    await db.recordFullDrillSession(
      subject: result.subject,
      topic: result.topic,
      totalQuestions: 1,
      correctCount: 0,
      incorrectCount: 1,
      scorePercentage: 0.0,
      questions: [
        DrillQuestionsCompanion.insert(
          subject: result.subject,
          topic: result.topic,
          questionText: result.questionText,
          optionsJson: jsonEncode(result.options),
          correctIndex: result.correctIndex,
          selectedIndex: (result.correctIndex + 1) % 4,
          isCorrect: false,
          explanation: Value(
            result.explanation.startsWith('[উৎস:')
                ? result.explanation
                : '$sourceTag ${result.explanation}',
          ),
          isMastered: const Value(false),
        ),
      ],
    );

    // 3. Mark as Weak Topic
    await db.insertWeakTopic(
      WeakTopicsCompanion.insert(
        subject: result.subject,
        topicName: result.topic,
        proficiencyLevel: ProficiencyLevel.weak,
      ),
    );
  }
}
