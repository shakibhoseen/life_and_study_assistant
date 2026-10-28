import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/notification_constants.dart';
import '../../database/app_database.dart';
import 'gemini_result_cache.dart';
import 'ai_media_limits.dart';
import 'gemini_usage_tracker.dart';
import 'models/parsed_routine_item.dart';
import 'models/routine_import_result.dart';

class RoutineParserService {
  /// Ceiling for a routine PDF handed to the model.
  static const int maxPdfBytes = 8 * 1024 * 1024;

  RoutineParserService._();
  static final RoutineParserService instance = RoutineParserService._();

  GenerativeModel? _model;
  String? _modelName;
  String? _cachedApiKey;
  String? get cachedApiKey => _cachedApiKey;
  String? get modelName => _modelName;

  static const String _prompt = '''
Extract all competitive examination / LiveMCQ / BCS schedules from this routine image, PDF or text into a JSON array.
Format each item strictly as:
[
  {
    "date": "YYYY-MM-DD",
    "exam_time": "HH:MM AM/PM",
    "subject": "Name of Subject (e.g., Bangla Grammar, Mathematics, General Science, English)",
    "title": "Exact exam/test title or serial from the routine (e.g., Model Test 03, Daily Exam 12)",
    "topics": ["Topic 1", "Topic 2"],
    "exam_type": "Daily / Weekly / Model Test / Special",
    "track_name": "Program / Batch name from routine title (e.g., 52nd BCS 135-Day, Vocabulary Booster, Friday Mega Model Test, Primary, or General BCS)"
  }
]
Rules:
1. If the year is not mentioned, use the current ongoing year.
2. If time is not mentioned, default to "10:00 PM".
3. Extract EVERY schedule row from EVERY page. One row in the source must become one JSON item; do not combine rows, omit later pages, or return only an example.
4. Preserve a distinct title/test number for exams that share a date or subject, so they remain separate in the app.
5. Extract clean subject and topic names (support both English and Bengali script).
6. Identify the program/track name accurately so multiple concurrent routines can be organized separately.
7. Return ONLY the valid JSON array without markdown code blocks or additional text.
''';

  Future<void> init([String? apiKey]) async {
    final prefs = await SharedPreferences.getInstance();
    var modelName =
        prefs.getString(NotificationConstants.prefGeminiModel) ??
        'gemini-flash-lite-latest';
    if (![
      'gemini-flash-lite-latest',
      'gemini-flash-latest',
      'gemini-pro-latest',
    ].contains(modelName)) {
      modelName = 'gemini-flash-lite-latest';
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
          // Routine PDFs often contain dozens of rows. The old 4096-token
          // ceiling could cut the JSON array short, which then looked like a
          // single imported routine.
          maxOutputTokens: 8192,
        ),
      );
      debugPrint('RoutineParserService initialized with $modelName');
    }
  }

  Future<String?> _getStoredApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(NotificationConstants.prefGeminiApiKey);
  }

  /// Parse exam schedules from a text-based post (Facebook / LiveMCQ notice)
  Future<List<ParsedRoutineItem>> parseRoutineFromText(String text) async {
    // A routine that is already JSON needs no model: the import prompt asks
    // for exactly this shape, so a saved or shared reply can be read straight
    // back in, at no cost.
    if (_looksLikeRoutineJson(text)) {
      final direct = _decodeResponse(text, rawRef: 'JSON import');
      if (direct.isNotEmpty) {
        debugPrint('Routine JSON read directly: ${direct.length} items');
        return direct;
      }
    }

    await init();

    final activeModel = _modelName ?? 'gemini-flash-lite-latest';
    final cacheKey = GeminiResultCache.instance.computeKeyFromString(
      operation: 'parse_routine_text',
      promptVersion: 'v1.0',
      model: activeModel,
      payloadText: text,
    );

    // 1. Check content-hash cache first (0 tokens)
    final cached = await GeminiResultCache.instance.get(cacheKey);
    if (cached != null && cached.isNotEmpty) {
      final parsed = _decodeResponse(cached, rawRef: text);
      if (parsed.isNotEmpty) {
        await GeminiUsageTracker.instance.recordCacheHit(
          operation: 'parse_routine_text',
          model: activeModel,
        );
        return parsed;
      }
    }

    if (_model != null) {
      try {
        final content = [
          Content.text(
            '$_prompt\n\n--- INPUT CONTENT ---\n$text\n---------------------',
          ),
        ];
        final response = await _model!.generateContent(content);
        await GeminiUsageTracker.instance.recordSuccess(
          tokens: response.usageMetadata?.totalTokenCount ?? 0,
          actualInputTokens: response.usageMetadata?.promptTokenCount,
          actualOutputTokens: response.usageMetadata?.candidatesTokenCount,
          actualTotalTokens: response.usageMetadata?.totalTokenCount,
          operation: 'parse_routine_text',
          model: activeModel,
        );
        final rawText = response.text;
        final parsed = _decodeResponse(rawText, rawRef: text);
        if (parsed.isNotEmpty && rawText != null) {
          await GeminiResultCache.instance.put(cacheKey, rawText);
          return parsed;
        }
      } catch (e) {
        debugPrint(
          'Gemini Text Routine parsing failed: $e. Falling back to local parser.',
        );
        if (e.toString().contains('429') ||
            e.toString().toLowerCase().contains('quota')) {
          await GeminiUsageTracker.instance.recordQuotaExceeded(
            operation: 'parse_routine_text',
            model: activeModel,
          );
        } else {
          await GeminiUsageTracker.instance.recordError(
            e.toString(),
            operation: 'parse_routine_text',
            model: activeModel,
          );
        }
      }
    }

    return _fallbackParseText(text);
  }

  /// Parse exam schedules from an image / screenshot
  Future<List<ParsedRoutineItem>> parseRoutineFromImage(File imageFile) async {
    await init();
    final activeModel = _modelName ?? 'gemini-flash-lite-latest';

    if (_model != null) {
      try {
        final imageBytes = await _prepareImageBytes(imageFile);
        final mimeType = _detectMimeType(imageFile.path);

        final content = [
          Content.multi([TextPart(_prompt), DataPart(mimeType, imageBytes)]),
        ];

        final response = await _model!.generateContent(content);
        await GeminiUsageTracker.instance.recordSuccess(
          tokens: response.usageMetadata?.totalTokenCount ?? 0,
          actualInputTokens: response.usageMetadata?.promptTokenCount,
          actualOutputTokens: response.usageMetadata?.candidatesTokenCount,
          actualTotalTokens: response.usageMetadata?.totalTokenCount,
          operation: 'parse_routine_image',
          model: activeModel,
        );
        final parsed = _decodeResponse(
          response.text,
          rawRef: 'Image: ${imageFile.path.split('/').last}',
        );
        if (parsed.isNotEmpty) return parsed;
      } catch (e) {
        debugPrint(
          'Gemini Image Routine parsing failed: $e. Falling back to local placeholder.',
        );
        if (e.toString().contains('429') ||
            e.toString().toLowerCase().contains('quota')) {
          await GeminiUsageTracker.instance.recordQuotaExceeded(
            operation: 'parse_routine_image',
            model: activeModel,
          );
        } else {
          await GeminiUsageTracker.instance.recordError(
            e.toString(),
            operation: 'parse_routine_image',
            model: activeModel,
          );
        }
      }
    }

    return _fallbackParseImage(imageFile);
  }

  /// Parse exam schedules directly from a PDF routine sheet (LiveMCQ syllabus PDF)
  Future<List<ParsedRoutineItem>> parseRoutineFromPdf(File pdfFile) async {
    await init();
    final activeModel = _modelName ?? 'gemini-flash-lite-latest';

    if (_model != null) {
      try {
        final pdfBytes = await pdfFile.readAsBytes();

        // Gemini bills a PDF by the page (roughly 258 tokens each), and this
        // path has no page count to check against, so size stands in for it.
        // A LiveMCQ routine is a handful of pages; anything near this ceiling
        // is a wrong file, and sending it would quietly cost a day's quota.
        if (pdfBytes.lengthInBytes > maxPdfBytes) {
          debugPrint(
            'Routine PDF rejected: ${(pdfBytes.lengthInBytes / 1048576).toStringAsFixed(1)}MB '
            'exceeds the ${(maxPdfBytes / 1048576).round()}MB limit.',
          );
          return [];
        }

        final content = [
          Content.multi([
            TextPart(_prompt),
            DataPart('application/pdf', pdfBytes),
          ]),
        ];

        final response = await _model!.generateContent(content);
        await GeminiUsageTracker.instance.recordSuccess(
          tokens: response.usageMetadata?.totalTokenCount ?? 0,
          actualInputTokens: response.usageMetadata?.promptTokenCount,
          actualOutputTokens: response.usageMetadata?.candidatesTokenCount,
          actualTotalTokens: response.usageMetadata?.totalTokenCount,
          operation: 'parse_routine_pdf',
          model: activeModel,
        );
        final parsed = _decodeResponse(
          response.text,
          rawRef: 'PDF: ${pdfFile.path.split('/').last}',
        );
        // A routine PDF holds dozens of rows, and whether they all arrived is
        // the whole question with this feature. Say so rather than leaving it
        // to be worked out from the database afterwards.
        final truncated =
            response.candidates.isNotEmpty &&
            response.candidates.first.finishReason == FinishReason.maxTokens;
        debugPrint(
          'PDF routine parse: ${parsed.length} items'
          '${truncated ? " (OUTPUT TRUNCATED -- rows are missing)" : ""}',
        );
        if (parsed.isNotEmpty) return parsed;
        debugPrint('PDF routine parse: nothing usable in the reply');
      } catch (e) {
        debugPrint(
          'Gemini PDF Routine parsing failed: $e. Nothing will be saved.',
        );
        if (e.toString().contains('429') ||
            e.toString().toLowerCase().contains('quota')) {
          await GeminiUsageTracker.instance.recordQuotaExceeded(
            operation: 'parse_routine_pdf',
            model: activeModel,
          );
        } else {
          await GeminiUsageTracker.instance.recordError(
            e.toString(),
            operation: 'parse_routine_pdf',
            model: activeModel,
          );
        }
      }
    }

    // A PDF cannot be read reliably without the vision model. Do not save a
    // made-up placeholder: it was indistinguishable from a real routine and
    // made a multi-row PDF look as if it contained only one exam.
    return [];
  }

  /// Whether this text is already a routine array rather than something to
  /// be read by the model.
  ///
  /// Checked strictly, because [ParsedRoutineItem.fromJson] fills in whatever
  /// is missing: handed an unrelated JSON array it would happily produce
  /// exams dated tomorrow. A real routine row carries a parseable date.
  bool _looksLikeRoutineJson(String text) {
    var cleaned = text.trim();
    if (cleaned.startsWith('```')) {
      cleaned = cleaned
          .replaceFirst(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '')
          .replaceFirst(RegExp(r'\s*```$'), '')
          .trim();
    }
    if (!cleaned.startsWith('[')) return false;

    try {
      final decoded = jsonDecode(cleaned);
      if (decoded is! List || decoded.isEmpty) return false;
      return decoded.every((e) {
        if (e is! Map) return false;
        final date = e['date']?.toString();
        return date != null && DateTime.tryParse(date) != null;
      });
    } catch (_) {
      return false;
    }
  }

  /// Helper to decode JSON response safely
  List<ParsedRoutineItem> _decodeResponse(String? rawJson, {String? rawRef}) {
    if (rawJson == null || rawJson.trim().isEmpty) return [];

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
      if (decoded is List) {
        return decoded
            .map(
              (e) => ParsedRoutineItem.fromJson(
                Map<String, dynamic>.from(e as Map),
                rawRef: rawRef,
              ),
            )
            .toList();
      }
    } catch (e) {
      debugPrint('JSON parsing error in RoutineParserService: $e');
    }
    return [];
  }

  /// Scales an image down to [AiMediaLimits.maxImageDimension] before it is
  /// billed by the model.
  Future<Uint8List> _prepareImageBytes(File file) async {
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
      if (longest > AiMediaLimits.maxImageDimension) {
        processed = decodedImage.width >= decodedImage.height
            ? img.copyResize(
                decodedImage,
                width: AiMediaLimits.maxImageDimension,
              )
            : img.copyResize(
                decodedImage,
                height: AiMediaLimits.maxImageDimension,
              );
      }

      final compressed = img.encodeJpg(
        processed,
        quality: AiMediaLimits.jpegQuality,
      );

      debugPrint(
        'Image prepared: ${decodedImage.width}x${decodedImage.height} '
        '-> ${processed.width}x${processed.height} '
        '(target ${AiMediaLimits.maxImageDimension}, ${(compressed.length / 1024).round()}KB)',
      );
      return Uint8List.fromList(compressed);
    } catch (e) {
      debugPrint('Image compression error: $e, using original bytes');
      return bytes;
    }
  }

  String _detectMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  /// Local rule-based fallback for text routines
  List<ParsedRoutineItem> _fallbackParseText(String text) {
    final List<ParsedRoutineItem> items = [];

    // JSON that got this far is JSON the strict reader rejected. Scraping it
    // as prose turns braces and colons into exams, so leave it alone.
    final head = text.trim();
    if (head.startsWith('[') || head.startsWith('{')) {
      debugPrint('Routine text fallback: input is JSON, not prose; skipping');
      return items;
    }

    final lines = text.split('\n');

    String detectedTrack = 'General BCS';
    final lowerText = text.toLowerCase();
    if (lowerText.contains('52') || lowerText.contains('135')) {
      detectedTrack = '52nd BCS 135-Day';
    } else if (lowerText.contains('vocabulary') ||
        lowerText.contains('শব্দার্থ') ||
        lowerText.contains('booster')) {
      detectedTrack = 'Vocabulary Booster';
    } else if (lowerText.contains('friday') ||
        lowerText.contains('শুক্রবার') ||
        lowerText.contains('mega')) {
      detectedTrack = 'Friday Mega Model Test';
    } else if (lowerText.contains('primary') ||
        lowerText.contains('প্রাইমারি')) {
      detectedTrack = 'Primary Assistant';
    }

    DateTime runningDate = DateTime.now().add(const Duration(days: 1));
    // Without a date read from the text itself, every row below would be
    // scheduled on invented consecutive days.
    var sawDate = false;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // Match simple date pattern (e.g., 28/10, 28-10, 28 Oct, 28 October)
      final dateMatch = RegExp(r'(\d{1,2})[\/\.-](\d{1,2})')
          .firstMatch(trimmed);
      if (dateMatch != null) {
        try {
          final day = int.parse(dateMatch.group(1)!);
          final month = int.parse(dateMatch.group(2)!);
          runningDate = DateTime(DateTime.now().year, month, day);
          sawDate = true;
        } catch (_) {}
      }

      if (!sawDate) continue;

      // Check if line looks like an exam topic
      if (trimmed.contains(':') ||
          trimmed.contains('-') ||
          trimmed.toLowerCase().contains('exam') ||
          trimmed.contains('পরীক্ষা')) {
        items.add(
          ParsedRoutineItem(
            date: runningDate,
            examTime: '10:00 PM',
            subject: 'Competitive Exam Routine',
            topics: [trimmed],
            examType: 'Daily',
            trackName: detectedTrack,
            rawReference: text,
          ),
        );
        runningDate = runningDate.add(const Duration(days: 1));
      }
    }

    // Nothing recognised means nothing recognised. Inventing a row here made
    // a failed import look like a one-exam routine, which is how a broken
    // import went unnoticed for so long.
    if (items.isEmpty) {
      debugPrint('Routine text fallback: no schedule lines recognised');
    }

    return items;
  }

  /// An image cannot be read without the vision model.
  ///
  /// Returns nothing rather than a placeholder, for the same reason the PDF
  /// and text paths do: a made-up row is indistinguishable from a real one.
  List<ParsedRoutineItem> _fallbackParseImage(File imageFile) {
    debugPrint('Routine image parse: no vision model available, nothing saved');
    return const [];
  }

  /// Batch persist parsed items into Drift database with intelligent deduplication
  Future<RoutineImportResult> saveParsedRoutinesToDatabase(
    AppDatabase db,
    List<ParsedRoutineItem> items, {
    String? overrideTrack,
  }) async {
    if (items.isEmpty) {
      return const RoutineImportResult(
        totalParsed: 0,
        insertedCount: 0,
        skippedCount: 0,
      );
    }
    final companions = items
        .map((item) => item.toCompanion(overrideTrack: overrideTrack))
        .toList();
    final result = await db.insertExamSchedulesDeduplicated(companions);
    debugPrint(
      'PDF routine saved: ${result.insertedCount} new, '
      '${result.updatedCount} updated, ${result.skippedCount} duplicate '
      'of ${items.length} parsed',
    );
    return result;
  }
}
