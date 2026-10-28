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

final _flashcardSchema = Schema.object(
  properties: {
    'subject': Schema.string(
      description:
          'Subject name in Bengali (e.g. গণিত, বাংলা ব্যাকরণ, বাংলাদেশ বিষয়াবলী, English)',
    ),
    'topic': Schema.string(
      description:
          'Specific topic or chapter name in Bengali (e.g. পরিমিতি ও ক্ষেত্রফল, কারক ও বিভক্তি, সংবিধান)',
    ),
    'cards': Schema.array(
      items: Schema.object(
        properties: {
          'front': Schema.string(
            description:
                'Concept, formula name, or question on front of card (e.g. বর্গক্ষেত্রের কর্ণের দৈর্ঘ্য)',
          ),
          'back': Schema.string(
            description:
                'The formula, rule, definition, mnemonic or solution on back of card (e.g. d = √2 × a, যেখানে a হলো বাহুর দৈর্ঘ্য। ক্ষেত্রফল = d²/2)',
          ),
          'subject': Schema.string(description: 'Optional subject override'),
          'topic': Schema.string(description: 'Optional topic override'),
        },
        requiredProperties: ['front', 'back'],
      ),
    ),
  },
  requiredProperties: ['subject', 'topic', 'cards'],
);

class AiFlashcardItem {
  final String subject;
  final String topic;
  final String front;
  final String back;
  bool isSelected;

  AiFlashcardItem({
    required this.subject,
    required this.topic,
    required this.front,
    required this.back,
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

    return AiFlashcardItem(
      subject: (s != null && s.isNotEmpty) ? s : defaultSubject,
      topic: (t != null && t.isNotEmpty) ? t : defaultTopic,
      front: BengaliMathSanitizer.sanitize(f),
      back: BengaliMathSanitizer.sanitize(b),
      isSelected: json['is_selected'] != false,
    );
  }
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
            maxOutputTokens: 1024,
          ),
        );

        final systemPrompt = '''
You are an expert tutor creating study flashcards for competitive exams in Bangladesh (BCS Preliminary, Bank, Primary Recruitment, LiveMCQ).
User prompt: "$trimmed"
${subjectHint != null && subjectHint.isNotEmpty ? 'Subject context: $subjectHint' : ''}

Instructions:
1. Generate 3 to 8 high-yield flashcards focused directly on this topic or formula request.
2. Front (Title): Short, focused concept, question or formula name (e.g. "বর্গক্ষেত্রের কর্ণের দৈর্ঘ্য", "রম্বসের ক্ষেত্রফল", "ণ-ত্ব বিধানের কমন ফাঁদ", "অনুচ্ছেদ ২৭").
3. Back (Key Rule): The exact formula, definition, shortcut, mnemonic or explanation in clear Bengali math unicode (e.g. "d = √2 × a, যেখানে a = বাহুর দৈর্ঘ্য। ক্ষেত্রফল = a² = d²/2") with practical recall tips.
4. Clean Unicode: Use '°', '×', '²', '³', '√', 'π', '÷', '½'. Never use raw LaTeX dollar signs like '\$x^2\$'.
5. Return ONLY a valid JSON object matching the requested schema.
''';

        final response = await model.generateContent([
          Content.text(systemPrompt),
        ]);
        final rawText = response.text?.trim() ?? '';
        final parsed = _parseJsonFlashcards(rawText, prompt);
        if (parsed.isNotEmpty) return parsed;
      } catch (e) {
        debugPrint('Gemini generateFromPrompt error: $e');
      }
    }

    // Offline rule-based fallback
    return _generateOfflineFallback(trimmed, subjectHint: subjectHint);
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
            maxOutputTokens: 1200,
          ),
        );

        const prompt = '''
You are an expert OCR tutor and formula extractor for Bangladeshi competitive exams (BCS, Bank, Primary, Govt Job).
Analyze this textbook page, lecture sheet, formula table or handwritten note:

Instructions:
1. Extract ALL key formulas, mathematical shortcuts, grammar rules, scientific principles, constitutional articles, or mnemonics visible on the page.
2. For EACH formula/rule:
   - Front: The concept, formula name or question (e.g. "বর্গক্ষেত্রের কর্ণের দৈর্ঘ্য", "পিথাগোরাসের উপপাদ্য", "রম্বসের ক্ষেত্রফল", "ণ-ত্ব বিধানের ব্যতিক্রম").
   - Back: The exact formula, rule statement, condition, example or mnemonic as printed on the page.
3. Clean Bengali Unicode: Use '°', '×', '²', '³', '√', 'π', '÷'. Avoid raw LaTeX syntax.
4. Return ONLY a valid JSON object matching the requested schema.
''';

        final response = await model.generateContent([
          Content.multi([
            TextPart(prompt),
            DataPart(mimeType, imageBytes),
          ]),
        ]);

        final rawText = response.text?.trim() ?? '';
        if (rawText.isNotEmpty) {
          await GeminiResultCache.instance.put(
            cacheKey,
            rawText,
          );
        }

        final parsed = _parseJsonFlashcards(rawText, 'Book Page OCR');
        if (parsed.isNotEmpty) return parsed;
      } catch (e) {
        debugPrint('Gemini extractFromBookImage error: $e');
      }
    }

    return _generateOfflineFallback('বইয়ের পাতা থেকে স্ক্যানকৃত সূত্র', subjectHint: subjectHint);
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

        final prompt = '''
Parse the following unstructured text, formulas, or flashcards into structured flashcards:
"""
$trimmed
"""

Return ONLY a valid JSON object matching the requested schema.
''';

        final response = await model.generateContent([Content.text(prompt)]);
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
        final defaultSubject = decoded['subject']?.toString().trim() ?? 'সাধারণ প্রস্তুতি';
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

  List<AiFlashcardItem> _generateOfflineFallback(
    String query, {
    String? subjectHint,
  }) {
    final qLower = query.toLowerCase();

    if (qLower.contains('বর্গক্ষেত্র') || qLower.contains('square')) {
      return [
        AiFlashcardItem(
          subject: 'গণিত',
          topic: 'পরিমিতি ও জ্যামিতি',
          front: 'বর্গক্ষেত্রের কর্ণের দৈর্ঘ্য (Diagonal)',
          back: 'd = √2 × a (যেখানে a হলো বাহুর দৈর্ঘ্য)।\n• উদাহরণ: বাহু ৪ সেমি হলে কর্ণ = ৪√২ সেমি।',
        ),
        AiFlashcardItem(
          subject: 'গণিত',
          topic: 'পরিমিতি ও জ্যামিতি',
          front: 'বর্গক্ষেত্রের ক্ষেত্রফল (Area)',
          back: 'A = a² = d² ÷ 2\n• বাহু জানা থাকলে: a²\n• কর্ণ d জানা থাকলে: d² ÷ 2 (শর্টকাট!)',
        ),
        AiFlashcardItem(
          subject: 'গণিত',
          topic: 'পরিমিতি ও জ্যামিতি',
          front: 'বর্গক্ষেত্রের পরিসীমা (Perimeter)',
          back: 'P = 4a (চারটি বাহুর সমষ্টি)',
        ),
      ];
    }

    if (qLower.contains('ত্রিভুজ') || qLower.contains('triangle')) {
      return [
        AiFlashcardItem(
          subject: 'গণিত',
          topic: 'জ্যামিতি ও ক্ষেত্রফল',
          front: 'সমকোণী ত্রিভুজের ক্ষেত্রফল',
          back: 'ক্ষেত্রফল = ½ × ভূমি × উচ্চতা\n• পিথাগোরাস সূত্র: অতিভুজ² = ভূমি² + লম্ব²',
        ),
        AiFlashcardItem(
          subject: 'গণিত',
          topic: 'জ্যামিতি ও ক্ষেত্রফল',
          front: 'সমবাহু ত্রিভুজের ক্ষেত্রফল',
          back: 'ক্ষেত্রফল = (√3 ÷ 4) × a²\n• উচ্চতা h = (√3 ÷ 2) × a',
        ),
      ];
    }

    if (qLower.contains('বৃত্ত') || qLower.contains('circle')) {
      return [
        AiFlashcardItem(
          subject: 'গণিত',
          topic: 'বৃত্ত ও পরিধি',
          front: 'বৃত্তের পরিধি ও ক্ষেত্রফল',
          back: '• পরিধি = 2πr\n• ক্ষেত্রফল = πr²\n(r = ব্যাসার্ধ, ব্যাস d = 2r)',
        ),
      ];
    }

    if (qLower.contains('কারক') || qLower.contains('সমাস')) {
      return [
        AiFlashcardItem(
          subject: 'বাংলা ব্যাকরণ',
          topic: 'কারক ও বিভক্তি',
          front: 'অপাদান কারক চেনার শর্টকাট',
          back: 'যা থেকে কোনো কিছু বিচ্যুত, উৎপন্ন, জাত, ভীত, স্খলিত হয়।\n• উদাহরণ: "তিলে তৈল হয়" (উৎপন্ন = অপাদান), "পাপে বিরত হও" (বিচ্যুত = অপাদান)',
        ),
        AiFlashcardItem(
          subject: 'বাংলা ব্যাকরণ',
          topic: 'কারক ও বিভক্তি',
          front: 'অধিকরণ কারক চেনার শর্টকাট',
          back: 'ক্রিয়া সম্পাদনের স্থান, কাল বা বিষয়কে অধিকরণ কারক বলে।\n• উদাহরণ: "তিলে তৈল আছে" (ব্যাপ্তি = অধিকরণ), "প্রভাতে সূর্য ওঠে" (কাল = অধিকরণ)',
        ),
      ];
    }

    return [
      AiFlashcardItem(
        subject: subjectHint ?? 'সাধারণ প্রস্তুতি',
        topic: query,
        front: query,
        back: 'গুরুত্বপূর্ণ সূত্র, সংজ্ঞা বা শর্টকাট নোট সংরক্ষণ করুন। (AI Key সংযুক্ত থাকলে গভীর শর্টকাট জেনারেট হবে)',
      ),
    ];
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
