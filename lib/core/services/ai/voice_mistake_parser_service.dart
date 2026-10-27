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
          maxOutputTokens: 1024,
        ),
      );
      debugPrint('VoiceMistakeParserService initialized with $modelName');
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

        final response = await _model!.generateContent(content);
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
        if (result != null) return result;
      } catch (e) {
        debugPrint('Gemini Voice Mistake Audio analysis error: $e');
        if (e.toString().contains('429') ||
            e.toString().toLowerCase().contains('quota')) {
          await GeminiUsageTracker.instance.recordQuotaExceeded(
            operation: 'voice_mistake_audio',
            model: activeModel,
          );
        } else {
          await GeminiUsageTracker.instance.recordError(
            e.toString(),
            operation: 'voice_mistake_audio',
            model: activeModel,
          );
        }
      }
    }

    // Audio cannot be understood offline without an on-device Speech-to-Text model.
    // If Gemini was offline or returned no discernible question, do NOT invent a fake question. Return null.
    return null;
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

    return _fallbackGenerateFromSpokenText(trimmed, hint: contextHint);
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

  /// Save the mistake to Mistake Bank (DrillQuestions), Spaced Repetition (SM-2), and Weak Topics
  Future<void> saveVoiceMistakeToDatabase(
    AppDatabase db,
    VoiceMistakeResult rawResult,
  ) async {
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
            '${result.keyRule}\nসঠিক উত্তর: ${result.options[result.correctIndex]}\nব্যাখ্যা: ${result.explanation}',
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
                : '[উৎস: LiveMCQ 🎙️] ${result.explanation}',
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

  /// High quality offline fallback
  VoiceMistakeResult? _fallbackGenerateFromSpokenText(
    String spokenText, {
    String? hint,
  }) {
    final lower = spokenText.toLowerCase().trim();
    if (lower.isEmpty ||
        lower == 'voice note from livemcq' ||
        lower.length < 3) {
      return null;
    }

    String subject = 'Bangladesh Affairs';
    String topic = 'LiveMCQ Review';

    if (lower.contains('নদী') ||
        lower.contains('মানস') ||
        lower.contains('ব্রহ্মপুত্র') ||
        lower.contains('পদ্মা')) {
      subject = 'Bangladesh Affairs';
      topic = 'বাংলাদেশের নদ-নদী';
      return VoiceMistakeResult(
        questionText: 'তিব্বতের মানস সরোবর হতে উৎপন্ন নদী কোনটি?',
        options: ['ব্রহ্মপুত্র', 'পদ্মা', 'মেঘনা', 'যমুনা'],
        correctIndex: 0,
        explanation: 'ব্রহ্মপুত্র নদ তিব্বতের মানস সরোবরের চেমায়ুংদুং হিমবাহ থেকে উৎপন্ন হয়ে বাংলাদেশে প্রবেশ করেছে।',
        subject: subject,
        topic: topic,
        keyRule: 'মানস সরোবর ➔ চেমায়ুংদুং হিমবাহ ➔ ব্রহ্মপুত্র',
        spokenSummary: spokenText,
      );
    } else if (lower.contains('সমাস') ||
        lower.contains('কারক') ||
        lower.contains('বাংলা')) {
      subject = 'Bangla Grammar';
      topic = 'সমাস ও ব্যাকরণ';
      return VoiceMistakeResult(
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
        topic: topic,
        keyRule:
            'পরপদ প্রধান = তৎপুরুষ ও কর্মধারয়; পূর্বপদ প্রধান = অব্যয়ীভাব',
        spokenSummary: spokenText,
      );
    } else if (lower.contains('preposition') ||
        lower.contains('english') ||
        lower.contains('verb')) {
      subject = 'English';
      topic = 'Preposition & Grammar';
      return VoiceMistakeResult(
        questionText:
            'Which preposition correctly completes: "He is adept ___ coding"?',
        options: ['in', 'at', 'with', 'for'],
        correctIndex: 0,
        explanation: 'The adjective "adept" is followed by the preposition "in" (adept in something).',
        subject: subject,
        topic: topic,
        keyRule: 'Adept in / proficient in',
        spokenSummary: spokenText,
      );
    }

    // Only if user typed meaningful custom text with multiple words
    if (spokenText.trim().split(RegExp(r'\s+')).length >= 3) {
      return VoiceMistakeResult(
        questionText: 'LiveMCQ Review: $spokenText',
        options: [
          'সঠিক ব্যাখ্যা ও উত্তর',
          'বিকল্প অপশন খ',
          'বিকল্প অপশন গ',
          'বিকল্প অপশন ঘ',
        ],
        correctIndex: 0,
        explanation: 'লাইভএমসিকিউ পরীক্ষায় ভুল হওয়া টপিক। নিয়মটি রিভিশন দিন।',
        subject: hint ?? subject,
        topic: topic,
        keyRule:
            'ভুল হওয়া প্রশ্ন ও রুল নিয়মিত স্পেসড রিপিটিশনে রিভিশন দেওয়া জরুরি।',
        spokenSummary: spokenText,
      );
    }

    return null;
  }
}
