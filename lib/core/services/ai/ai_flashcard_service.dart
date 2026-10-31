import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/notification_constants.dart';
import '../../database/app_database.dart';
import '../../utils/bengali_math_sanitizer.dart';
import 'ai_media_limits.dart';
import 'gemini_ai_service.dart';
import 'gemini_result_cache.dart';
import 'gemini_usage_tracker.dart';

final _flashcardSchema = Schema.object(
  properties: {
    'subject': Schema.string(
      description: 'Subject name in Bengali (e.g. গণিত, বাংলা ব্যাকরণ, বাংলাদেশ বিষয়াবলী, English)',
    ),
    'topic': Schema.string(
      description: 'Specific topic or chapter name in Bengali (e.g. পরিমিতি ও ক্ষেত্রফল, কারক ও বিভক্তি, সংবিধান)',
    ),
    'cards': Schema.array(
      items: Schema.object(
        properties: {
          'front': Schema.string(
            description: 'Concept, formula name, or question on front of card (e.g. বর্গক্ষেত্রের কর্ণের দৈর্ঘ্য)',
          ),
          'back': Schema.string(
            description: 'The formula, rule, definition, mnemonic or solution on back of card (e.g. d = √2 × a, যেখানে a হলো বাহুর দৈর্ঘ্য। ক্ষেত্রফল = d²/2)',
          ),
          'subject': Schema.string(description: 'Optional subject override'),
          'topic': Schema.string(description: 'Optional topic override'),
          'priority': Schema.enumString(
            enumValues: ['high', 'medium', 'low'],
            description: 'How directly the exam asks this',
          ),
          'why': Schema.string(
            description: 'One short Bengali clause: why memorise this',
          ),
        },
        requiredProperties: ['front', 'back'],
      ),
    ),
  },
  requiredProperties: ['subject', 'topic', 'cards'],
);

/// How directly the exam asks for a card, as judged when it was extracted.
enum CardPriority {
  high,
  medium,
  low;

  static CardPriority parse(String? raw) =>
      switch ((raw ?? '').trim().toLowerCase()) {
        'high' => CardPriority.high,
        'low' => CardPriority.low,
        _ => CardPriority.medium,
      };

  String get label => switch (this) {
    CardPriority.high => 'সরাসরি আসে',
    CardPriority.medium => 'কাজে লাগে',
    CardPriority.low => 'কম আসে',
  };
}

class AiFlashcardItem {
  final String subject;
  final String topic;
  final String front;
  final String back;

  final CardPriority priority;

  /// Why this was judged worth memorising, in the extractor's own words.
  ///
  /// Shown rather than stored: the user is choosing which cards to keep, and
  /// a reason they can read beats a rating they cannot question.
  final String? why;

  bool isSelected;

  AiFlashcardItem({
    required this.subject,
    required this.topic,
    required this.front,
    required this.back,
    this.priority = CardPriority.medium,
    this.why,
    this.isSelected = true,
  });

  AiFlashcardItem copyWith({
    String? subject,
    String? topic,
    String? front,
    String? back,
    bool? isSelected,
  }) {
    return AiFlashcardItem(
      subject: subject ?? this.subject,
      topic: topic ?? this.topic,
      front: front ?? this.front,
      back: back ?? this.back,
      isSelected: isSelected ?? this.isSelected,
    );
  }

  Map<String, dynamic> toJson() => {
    'subject': subject,
    'topic': topic,
    'front': front,
    'back': back,
    'is_selected': isSelected,
  };

  factory AiFlashcardItem.fromJson(
    Map<String, dynamic> json, {
    String defaultSubject = 'গণিত ও সাধারণ জ্ঞান',
    String defaultTopic = 'গুরুত্বপূর্ণ সূত্র ও নিয়ম',
  }) {
    final s = json['subject']?.toString().trim();
    final t = json['topic']?.toString().trim();
    final f =
        json['front']?.toString().trim() ??
        json['title']?.toString().trim() ??
        json['question']?.toString().trim() ??
        '';
    final b =
        json['back']?.toString().trim() ??
        json['rule']?.toString().trim() ??
        json['key_rule']?.toString().trim() ??
        json['formula']?.toString().trim() ??
        json['content']?.toString().trim() ??
        json['answer']?.toString().trim() ??
        '';

    final reason = json['why']?.toString().trim();

    return AiFlashcardItem(
      subject: (s != null && s.isNotEmpty) ? s : defaultSubject,
      topic: (t != null && t.isNotEmpty) ? t : defaultTopic,
      front: BengaliMathSanitizer.sanitize(f),
      back: BengaliMathSanitizer.sanitize(b),
      priority: CardPriority.parse(json['priority']?.toString()),
      why: (reason == null || reason.isEmpty) ? null : reason,
      // The extractor is asked to put the ones that matter first, so the
      // low-priority tail starts unticked rather than being saved by default.
      isSelected:
          json['is_selected'] != false &&
          CardPriority.parse(json['priority']?.toString()) != CardPriority.low,
    );
  }
}

/// A generation run that produced nothing usable.
///
/// Flashcards used to fall back to a canned deck keyed off a word in the
/// prompt, and to a single card whose front was the prompt itself when no
/// word matched. Asking for fifteen cards on the heart produced one card
/// headed with the whole request, which looks like an answer and is not one.
class FlashcardGenerationException implements Exception {
  /// Shown to the user as it is.
  final String userMessage;

  const FlashcardGenerationException(this.userMessage);

  @override
  String toString() => 'FlashcardGenerationException: $userMessage';
}

class AiFlashcardService {
  AiFlashcardService._();
  static final AiFlashcardService instance = AiFlashcardService._();

  Future<String?> _getApiKey() async {
    try {
      final cached = GeminiAiService.instance.apiKey;
      if (cached != null && cached.isNotEmpty) return cached;
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(NotificationConstants.prefGeminiApiKey);
    } catch (_) {
      return null;
    }
  }

  /// Generates structured flashcards based on a user prompt or topic query.
  Future<List<AiFlashcardItem>> generateFromPrompt(
    String prompt, {
    String? subjectHint,
  }) async {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty) return const [];

    final apiKey = await _getApiKey();
    if (apiKey != null && apiKey.isNotEmpty) {
      try {
        final model = GenerativeModel(
          model: 'gemini-flash-latest',
          apiKey: apiKey,
          generationConfig: GenerationConfig(
            responseMimeType: 'application/json',
            responseSchema: _flashcardSchema,
            temperature: 0.2,
            // Measured against a real request for ১৫টি Bengali cards on the
            // heart: at 1024 the reply was cut after one unfinished card,
            // and the budget went mostly on reasoning before any of it was
            // written. Bengali costs about 1.5 characters a token, and a
            // card with a mnemonic runs long, so the room has to be real.
            maxOutputTokens: 8192,
          ),
        );

        final systemPrompt =
            '''
You are an expert tutor creating study flashcards for competitive exams in Bangladesh (BCS Preliminary, Bank, Primary Recruitment, LiveMCQ).
User prompt: "$trimmed"
${subjectHint != null && subjectHint.isNotEmpty ? 'Subject context: $subjectHint' : ''}

Instructions:
1. Make as many flashcards as the user asked for. When they name a number, produce exactly that many; when they do not, produce 3 to 8. Follow any rules they set about content, wording or coverage.
2. Front (Title): Short, focused concept, question or formula name (e.g. "বর্গক্ষেত্রের কর্ণের দৈর্ঘ্য", "রম্বসের ক্ষেত্রফল", "ণ-ত্ব বিধানের কমন ফাঁদ", "অনুচ্ছেদ ২৭").
3. Back (Key Rule): The exact formula, definition, shortcut, mnemonic or explanation in clear Bengali math unicode (e.g. "d = √2 × a, যেখানে a = বাহুর দৈর্ঘ্য। ক্ষেত্রফল = a² = d²/2") with practical recall tips.
4. Clean Unicode: Use '°', '×', '²', '³', '√', 'π', '÷', '½'. Never use raw LaTeX dollar signs like '\$x^2\$'.
5. Return ONLY a valid JSON object matching the requested schema.
''';

        final response = await model.generateContent([
          Content.text(systemPrompt),
        ]);

        // These calls used to spend tokens without recording any, so none of
        // the flashcard work appeared in the daily total.
        await GeminiUsageTracker.instance.recordSuccess(
          tokens: response.usageMetadata?.totalTokenCount ?? 0,
          actualInputTokens: response.usageMetadata?.promptTokenCount,
          actualOutputTokens: response.usageMetadata?.candidatesTokenCount,
          actualTotalTokens: response.usageMetadata?.totalTokenCount,
          operation: 'flashcard_generate',
          model: 'gemini-flash-latest',
        );
        if (response.candidates.isNotEmpty &&
            response.candidates.first.finishReason == FinishReason.maxTokens) {
          throw const FlashcardGenerationException(
            'কার্ডগুলো লেখা শেষ হওয়ার আগেই জায়গা ফুরিয়েছে। '
            'কম কার্ড চান, বা বিষয়টা ভাগ করে নিন।',
          );
        }

        final rawText = response.text?.trim() ?? '';
        final parsed = _parseJsonFlashcards(rawText, prompt);
        if (parsed.isNotEmpty) return parsed;
        throw const FlashcardGenerationException(
          'এই প্রম্পট থেকে কোনো কার্ড তৈরি হয়নি। একটু অন্যভাবে লিখে দেখুন।',
        );
      } on FlashcardGenerationException {
        rethrow;
      } catch (e) {
        debugPrint('Gemini generateFromPrompt error: $e');
        throw const FlashcardGenerationException(
          'কার্ড তৈরি করা গেল না। ইন্টারনেট দেখে আবার চেষ্টা করুন।',
        );
      }
    }

    throw const FlashcardGenerationException(
      'Gemini API কী বসানো নেই। সেটিংসে কী দিন, তারপর আবার চেষ্টা করুন।',
    );
  }

  /// Extracts formulas and rules from an image of a textbook page or lecture sheet.
  Future<List<AiFlashcardItem>> extractFromBookImage(
    File imageFile, {
    String? subjectHint,
    CaptureDetail detail = CaptureDetail.high,
  }) async {
    final apiKey = await _getApiKey();
    if (apiKey != null && apiKey.isNotEmpty) {
      try {
        final imageBytes = await _prepareImageBytes(
          imageFile,
          detail.dimension,
        );
        final mimeType = _detectMimeType(imageFile.path);

        // Check content-hash cache
        final cacheKey = GeminiResultCache.instance.computeKey(
          operation: 'flashcard_image_ocr',
          promptVersion: 'v1.0',
          model: 'gemini-flash-latest',
          payloadBytes: imageBytes,
        );

        final cached = await GeminiResultCache.instance.get(cacheKey);
        if (cached != null) {
          final parsed = _parseJsonFlashcards(cached, 'Book OCR');
          if (parsed.isNotEmpty) return parsed;
        }

        final model = GenerativeModel(
          model: 'gemini-flash-latest',
          apiKey: apiKey,
          generationConfig: GenerationConfig(
            responseMimeType: 'application/json',
            responseSchema: _flashcardSchema,
            temperature: 0.1,
            // A dense page can carry a dozen cards, and reasoning is drawn
            // from this budget before any of them is written; 1200 cut the
            // reply mid-card.
            maxOutputTokens: 4096,
          ),
        );

        const prompt = '''
You are an expert tutor for Bangladeshi competitive exams (BCS, Bank, Primary, Govt Job), deciding what on this page is worth memorising.

The image is a textbook page, lecture sheet, formula table or handwritten note.

JUDGE, do not transcribe. A page holds far more text than is worth carrying in someone's head, and a card for every line buries the ones that matter.

Make a card ONLY for:
- a formula, equation or constant;
- a rule, law or definition stated precisely;
- a classification or list the exam asks directly (সমাসের প্রকার, কারকের প্রশ্নসূত্র);
- a fixed fact: a year, an article number, a named first/largest/longest;
- a shortcut or trap the page itself points out.

Do NOT make a card for:
- narrative or explanatory prose, worked examples, or practice questions;
- anything you cannot read clearly off the page;
- something you already made a card for on this page.

For EACH card:
- front: the concept, formula name, or the question it answers.
- back: the formula, rule or fact as the page states it, with its conditions.
- priority: "high" if the exam asks it directly and it is easy to forget, "medium" if it supports those, "low" if worth knowing but rarely asked.
- why: one short Bengali clause saying why it is worth memorising.

Put the highest priority first. Five well-chosen cards beat twenty. If the page holds nothing worth memorising, return an empty cards array rather than filling it.

Clean Bengali Unicode: use '°', '×', '²', '³', '√', 'π', '÷'. Never raw LaTeX.
Return ONLY a valid JSON object matching the requested schema.
''';

        final response = await model.generateContent([
          Content.multi([TextPart(prompt), DataPart(mimeType, imageBytes)]),
        ]);

        // These calls used to spend tokens without recording any, so none of
        // the flashcard work appeared in the daily total.
        await GeminiUsageTracker.instance.recordSuccess(
          tokens: response.usageMetadata?.totalTokenCount ?? 0,
          actualInputTokens: response.usageMetadata?.promptTokenCount,
          actualOutputTokens: response.usageMetadata?.candidatesTokenCount,
          actualTotalTokens: response.usageMetadata?.totalTokenCount,
          operation: 'flashcard_image_ocr',
          model: 'gemini-flash-latest',
        );

        if (response.candidates.isNotEmpty &&
            response.candidates.first.finishReason == FinishReason.maxTokens) {
          throw const FlashcardGenerationException(
            'পাতায় মনে রাখার মতো জিনিস অনেক, পুরোটা লেখা শেষ হয়নি। '
            'অর্ধেক পাতা করে তুলুন।',
          );
        }

        final rawText = response.text?.trim() ?? '';
        if (rawText.isNotEmpty) {
          await GeminiResultCache.instance.put(cacheKey, rawText);
        }

        final parsed = _parseJsonFlashcards(rawText, 'Book Page OCR');
        if (parsed.isNotEmpty) return parsed;
      } on FlashcardGenerationException {
        rethrow;
      } catch (e) {
        debugPrint('Gemini extractFromBookImage error: $e');
      }
    }

    // Nothing was read off the page, so there is nothing to offer. The old
    // fallback returned a placeholder card titled "বইয়ের পাতা থেকে স্ক্যানকৃত
    // সূত্র", which looked exactly like a card the page itself had produced.
    debugPrint('Book page flashcards: nothing extracted, saving nothing');
    return const [];
  }

  /// Parses flashcards pasted from external AI (Claude/ChatGPT) or custom structured text.
  Future<List<AiFlashcardItem>> parseFromExternalText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const [];

    // 1. Try direct JSON parsing
    var clean = trimmed;
    if (clean.startsWith('```json')) clean = clean.substring(7);
    if (clean.startsWith('```')) clean = clean.substring(3);
    if (clean.endsWith('```')) clean = clean.substring(0, clean.length - 3);
    clean = clean.trim();

    try {
      final decoded = jsonDecode(clean);
      if (decoded is Map<String, dynamic>) {
        final parsed = _parseJsonFlashcards(clean, 'External AI');
        if (parsed.isNotEmpty) return parsed;
      } else if (decoded is List) {
        final items = <AiFlashcardItem>[];
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            items.add(AiFlashcardItem.fromJson(item));
          }
        }
        if (items.isNotEmpty) return items;
      }
    } catch (_) {}

    // 2. Try Gemini structured parsing if API key is available
    final apiKey = await _getApiKey();
    if (apiKey != null && apiKey.isNotEmpty) {
      try {
        final model = GenerativeModel(
          model: 'gemini-flash-latest',
          apiKey: apiKey,
          generationConfig: GenerationConfig(
            responseMimeType: 'application/json',
            responseSchema: _flashcardSchema,
            temperature: 0.1,
            maxOutputTokens: 1024,
          ),
        );

        final prompt =
            '''
Parse the following unstructured text, formulas, or flashcards into structured flashcards:
"""
$trimmed
"""

Return ONLY a valid JSON object matching the requested schema.
''';

        final response = await model.generateContent([Content.text(prompt)]);

        // These calls used to spend tokens without recording any, so none of
        // the flashcard work appeared in the daily total.
        await GeminiUsageTracker.instance.recordSuccess(
          tokens: response.usageMetadata?.totalTokenCount ?? 0,
          actualInputTokens: response.usageMetadata?.promptTokenCount,
          actualOutputTokens: response.usageMetadata?.candidatesTokenCount,
          actualTotalTokens: response.usageMetadata?.totalTokenCount,
          operation: 'flashcard_external_text',
          model: 'gemini-flash-latest',
        );
        final rawText = response.text?.trim() ?? '';
        final parsed = _parseJsonFlashcards(rawText, 'External AI');
        if (parsed.isNotEmpty) return parsed;
      } catch (e) {
        debugPrint('Gemini parseFromExternalText error: $e');
      }
    }

    // 3. Fallback regex line-by-line parsing
    return _parseTextWithRegex(trimmed);
  }

  /// Saves selected flashcards directly to the database SpacedReviewItems table.
  Future<int> saveToSpacedRepetition(
    AppDatabase db,
    List<AiFlashcardItem> items, {
    int initialIntervalDays = 1,
  }) async {
    final selected = items.where((c) => c.isSelected).toList();
    if (selected.isEmpty) return 0;

    final now = DateTime.now();
    final companions = selected.map((item) {
      return SpacedReviewItemsCompanion.insert(
        subject: item.subject,
        topic: item.topic,
        title: item.front,
        keyRule: item.back,
        repetitionLevel: const Value(1),
        intervalDays: Value(initialIntervalDays),
        nextReviewDate: now.add(Duration(days: initialIntervalDays)),
      );
    }).toList();

    return db.insertSpacedReviewItemsBatch(companions);
  }

  List<AiFlashcardItem> _parseJsonFlashcards(String jsonString, String query) {
    try {
      var clean = jsonString.trim();
      if (clean.startsWith('```json')) clean = clean.substring(7);
      if (clean.startsWith('```')) clean = clean.substring(3);
      if (clean.endsWith('```')) clean = clean.substring(0, clean.length - 3);
      clean = clean.trim();

      final decoded = jsonDecode(clean);
      if (decoded is Map<String, dynamic>) {
        final defaultSubject =
            decoded['subject']?.toString().trim() ?? 'সাধারণ প্রস্তুতি';
        final defaultTopic = decoded['topic']?.toString().trim() ?? query;
        final cardsList = decoded['cards'];

        if (cardsList is List) {
          final result = <AiFlashcardItem>[];
          for (final c in cardsList) {
            if (c is Map<String, dynamic>) {
              result.add(
                AiFlashcardItem.fromJson(
                  c,
                  defaultSubject: defaultSubject,
                  defaultTopic: defaultTopic,
                ),
              );
            }
          }
          return result;
        }
      }
    } catch (e) {
      debugPrint('Error parsing flashcards JSON: $e');
    }
    return const [];
  }

  List<AiFlashcardItem> _parseTextWithRegex(String text) {
    final items = <AiFlashcardItem>[];
    final lines = text.split('\n');

    // Matches lines like: "১. বর্গক্ষেত্রের কর্ণ: d = √2a" or "Front - Back" or "Concept: Formula"
    final linePattern = RegExp(
      r'^(?:[•\-*\d]+\.?\s*)?(.*?)\s*(?:[:=—–\-]|->|—>)\s*(.+)$',
    );

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      final match = linePattern.firstMatch(line);
      if (match != null) {
        final front = match.group(1)?.trim() ?? '';
        final back = match.group(2)?.trim() ?? '';

        if (front.isNotEmpty && back.isNotEmpty && front.length < 120) {
          items.add(
            AiFlashcardItem(
              subject: 'গণিত ও প্রস্তুতি',
              topic: 'সংগৃহীত সূত্র',
              front: BengaliMathSanitizer.sanitize(front),
              back: BengaliMathSanitizer.sanitize(back),
            ),
          );
        }
      }
    }

    if (items.isEmpty && text.trim().isNotEmpty) {
      items.add(
        AiFlashcardItem(
          subject: 'সাধারণ প্রস্তুতি',
          topic: 'কাস্টম নোট',
          front: BengaliMathSanitizer.sanitize(text.split('\n').first.trim()),
          back: BengaliMathSanitizer.sanitize(text.trim()),
        ),
      );
    }

    return items;
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
      debugPrint('Image compression error in AiFlashcardService: $e');
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
