import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/notification_constants.dart';
import '../../database/app_database.dart';
import 'gemini_ai_service.dart';
import 'gemini_result_cache.dart';
import 'ai_media_limits.dart';
import 'gemini_usage_tracker.dart';
import 'models/parsed_routine_item.dart';
import 'models/routine_import_result.dart';

class RoutineParserException implements Exception {
  final String userMessage;
  final String? technicalDetails;
  final String? finishReason;
  final String? rawResponseSnippet;
  final int? promptTokens;
  final int? candidateTokens;
  final int? totalTokens;
  final String? modelName;
  final bool isQuotaOrRateLimit;
  final bool isPayloadTooLarge;

  RoutineParserException({
    required this.userMessage,
    this.technicalDetails,
    this.finishReason,
    this.rawResponseSnippet,
    this.promptTokens,
    this.candidateTokens,
    this.totalTokens,
    this.modelName,
    this.isQuotaOrRateLimit = false,
    this.isPayloadTooLarge = false,
  });

  @override
  String toString() => userMessage;
}

class RoutineParserService {
  /// Ceiling for a routine PDF handed to the model (50MB max for large multi-page scans).
  static const int maxPdfBytes = 50 * 1024 * 1024;

  RoutineParserService._();
  static final RoutineParserService instance = RoutineParserService._();

  GenerativeModel? _model;
  String? _modelName;
  String? _cachedApiKey;
  bool _lastParseWasTruncated = false;

  String? get cachedApiKey => _cachedApiKey;
  String? get modelName => _modelName;
  bool get lastParseWasTruncated => _lastParseWasTruncated;

  static const String _prompt = '''
Extract all competitive examination / BCS / LiveMCQ schedules from this document.
Return a clean JSON structure:
{
  "track_name": "Program / Batch name from routine header (e.g., 52nd BCS 135-Day, 100 Days BCS, General BCS)",
  "exams": [
    {
      "date": "YYYY-MM-DD",
      "exam_time": "10:00 PM",
      "subject": "Subject name",
      "title": "Exam title or serial (e.g., Day 01, Model Test 03)",
      "topics": ["Topic 1", "Topic 2"],
      "exam_type": "Daily"
    }
  ]
}
Alternatively, a direct JSON array of exams [ { "date": ..., ... } ] is also acceptable.
Rules:
1. Extract EVERY schedule row from EVERY page without omitting any row or date.
2. If the year is not mentioned, use the current ongoing year. Default time to "10:00 PM" if absent.
3. Extract accurate subject and topic names (support both English and Bengali script).
4. Do NOT repeat "track_name" inside individual exam objects if using the envelope format above.
5. Return ONLY the valid JSON without markdown formatting or conversational text.
''';

  /// Ready-to-use prompt for External AIs (ChatGPT, Claude, Gemini Web, DeepSeek).
  ///
  /// Users can paste this prompt alongside their routine PDF, image, or text in
  /// ChatGPT or Claude, and paste the resulting JSON straight into the app.
  static const String externalAiRoutinePrompt = '''
Please extract all examination / LiveMCQ / BCS schedules from my attached routine (PDF, image, or text) into a compact JSON format.

Format the output strictly as:
{
  "track_name": "Program or Batch name (e.g. 52nd BCS 135-Day, 100 Days BCS, General BCS)",
  "exams": [
    {
      "date": "YYYY-MM-DD",
      "exam_time": "10:00 PM",
      "subject": "Name of Subject (e.g. Bangla, English, Mathematics, General Science)",
      "title": "Exact exam title or serial (e.g. Day 01, Model Test 03)",
      "topics": ["Topic 1", "Topic 2"],
      "exam_type": "Daily"
    }
  ]
}

Rules:
1. Extract EVERY schedule row from EVERY page without omitting any dates.
2. If time is not mentioned, use "10:00 PM". If year is omitted, use the current year (2026).
3. Do not repeat track_name inside the individual exam objects.
4. Output strictly valid JSON code block only without extra conversational prose.
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
    final key = apiKey ??
        await _getStoredApiKey() ??
        GeminiAiService.instance.apiKey;
    if (key != null && key.isNotEmpty) {
      _cachedApiKey = key;
      _modelName = modelName;
      _model = GenerativeModel(
        model: modelName,
        apiKey: key,
        generationConfig: GenerationConfig(
          responseMimeType: 'application/json',
          temperature: 0.1,
          // No token cap: let the model generate freely without artificial cutoff
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
    _lastParseWasTruncated = false;
    await init();
    final activeModel = _modelName ?? 'gemini-flash-lite-latest';

    if (_model == null || _cachedApiKey == null || _cachedApiKey!.isEmpty) {
      throw RoutineParserException(
        userMessage:
            'Gemini API Key সেট করা নেই। রুটিন PDF বিশ্লেষণ করতে Settings এ গিয়ে API Key যোগ করুন।',
        modelName: activeModel,
      );
    }

    final pdfBytes = await pdfFile.readAsBytes();

    if (pdfBytes.lengthInBytes > maxPdfBytes) {
      throw RoutineParserException(
        userMessage:
            'PDF ফাইলটি অনেক বড় (${(pdfBytes.lengthInBytes / 1048576).toStringAsFixed(1)}MB)। সর্বোচ্চ ৫০MB পর্যন্ত ফাইল দেওয়া যাবে।',
        technicalDetails: 'File size: ${pdfBytes.lengthInBytes} bytes',
        modelName: activeModel,
        isPayloadTooLarge: true,
      );
    }

    try {
      final content = [
        Content.multi([
          TextPart(_prompt),
          DataPart('application/pdf', pdfBytes),
        ]),
      ];

      // Dedicated unconstrained model for routine PDF parsing: no artificial token limit!
      final pdfModel = GenerativeModel(
        model: activeModel,
        apiKey: _cachedApiKey!,
        generationConfig: GenerationConfig(
          responseMimeType: 'application/json',
          temperature: 0.1,
          // Completely unconstrained tokens: no maxOutputTokens limitation
        ),
      );

      final response = await pdfModel.generateContent(content);
      final candidate = response.candidates.isNotEmpty
          ? response.candidates.first
          : null;
      final finishReason = candidate?.finishReason;
      final usage = response.usageMetadata;
      final rawText = response.text;

      await GeminiUsageTracker.instance.recordSuccess(
        tokens: usage?.totalTokenCount ?? 0,
        actualInputTokens: usage?.promptTokenCount,
        actualOutputTokens: usage?.candidatesTokenCount,
        actualTotalTokens: usage?.totalTokenCount,
        operation: 'parse_routine_pdf',
        model: activeModel,
      );

      final parsed = _decodeResponse(
        rawText,
        rawRef: 'PDF: ${pdfFile.path.split('/').last}',
      );

      _lastParseWasTruncated = finishReason == FinishReason.maxTokens;

      debugPrint(
        'PDF routine parse: ${parsed.length} items'
        '${_lastParseWasTruncated ? " (OUTPUT TRUNCATED BY TOKEN LIMIT -- recovered ${parsed.length} complete rows)" : ""}',
      );

      if (parsed.isNotEmpty) return parsed;

      debugPrint(
        'PDF routine parse: nothing usable in reply. Raw length: ${rawText?.length ?? 0}, FinishReason: ${finishReason?.name}',
      );

      // If empty or null response from model
      if (rawText == null || rawText.trim().isEmpty) {
        String msg =
            'Gemini AI কোনো তথ্য প্রদান করেনি (Empty candidate response)।';
        if (finishReason == FinishReason.safety) {
          msg = 'Gemini-র Safety Filters দ্বারা রেসপন্স ব্লক হয়েছে।';
        } else if (finishReason == FinishReason.maxTokens) {
          msg = 'Gemini টোকেন সীমার কারণে উত্তর প্রদান বন্ধ করেছে।';
        } else if (finishReason != null) {
          msg =
              'Gemini AI উত্তর প্রদান সম্পন্ন করতে পারেনি (FinishReason: ${finishReason.name})।';
        }
        throw RoutineParserException(
          userMessage: msg,
          technicalDetails:
              'Candidates: ${response.candidates.length}, FinishReason: ${finishReason?.name ?? "none"}',
          finishReason: finishReason?.name,
          promptTokens: usage?.promptTokenCount,
          candidateTokens: usage?.candidatesTokenCount,
          totalTokens: usage?.totalTokenCount,
          modelName: activeModel,
        );
      }

      // If text received but 0 parsed
      throw RoutineParserException(
        userMessage:
            'রুটিন PDF থেকে কোনো পরীক্ষার তথ্য সনাক্ত করা যায়নি। ফাইলটি স্পষ্ট কিনা যাচাই করুন।',
        technicalDetails:
            'Response received (${rawText.length} chars, ${usage?.candidatesTokenCount ?? 0} output tokens), but JSON parsing produced 0 items.',
        rawResponseSnippet: rawText.length > 500
            ? '${rawText.substring(0, 500)}...'
            : rawText,
        finishReason: finishReason?.name,
        promptTokens: usage?.promptTokenCount,
        candidateTokens: usage?.candidatesTokenCount,
        totalTokens: usage?.totalTokenCount,
        modelName: activeModel,
      );
    } catch (e) {
      debugPrint('Gemini PDF Routine parsing failed: $e');
      if (e is RoutineParserException) {
        rethrow;
      }
      final errStr = e.toString();
      if (errStr.contains('429') || errStr.toLowerCase().contains('quota')) {
        await GeminiUsageTracker.instance.recordQuotaExceeded(
          operation: 'parse_routine_pdf',
          model: activeModel,
        );
        throw RoutineParserException(
          userMessage:
              'Gemini API ফ্রি কোটা সাময়িকভাবে শেষ বা রেট লিমিট হয়েছে (429 Quota Exceeded)। কিছুক্ষণ পর আবার চেষ্টা করুন।',
          technicalDetails: errStr,
          modelName: activeModel,
          isQuotaOrRateLimit: true,
        );
      } else if (errStr.contains('413') ||
          errStr.toLowerCase().contains('too large') ||
          errStr.contains('Request payload size')) {
        throw RoutineParserException(
          userMessage:
              'PDF ফাইলটির সাইজ (${(pdfBytes.lengthInBytes / 1048576).toStringAsFixed(1)}MB) Gemini API সীমা অতিক্রম করেছে।',
          technicalDetails: errStr,
          modelName: activeModel,
          isPayloadTooLarge: true,
        );
      } else {
        await GeminiUsageTracker.instance.recordError(
          errStr,
          operation: 'parse_routine_pdf',
          model: activeModel,
        );
        throw RoutineParserException(
          userMessage:
              'Gemini AI রুটিন বিশ্লেষণে সমস্যা হয়েছে: ${errStr.replaceFirst("Exception: ", "")}',
          technicalDetails: errStr,
          modelName: activeModel,
        );
      }
    }
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
    if (!cleaned.startsWith('[') && !cleaned.startsWith('{')) return false;

    try {
      final decoded = jsonDecode(cleaned);
      if (decoded is List) {
        if (decoded.isEmpty) return false;
        return decoded.every((e) {
          if (e is! Map) return false;
          final date = e['date']?.toString();
          return date != null && DateTime.tryParse(date) != null;
        });
      } else if (decoded is Map) {
        final list =
            decoded['exams'] ?? decoded['schedules'] ?? decoded['items'];
        if (list is List && list.isNotEmpty) {
          return list.every((e) {
            if (e is! Map) return false;
            final date = e['date']?.toString();
            return date != null && DateTime.tryParse(date) != null;
          });
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Testing bridge for decoding response and token truncation recovery
  @visibleForTesting
  List<ParsedRoutineItem> decodeResponseForTesting(
    String? rawJson, {
    String? rawRef,
  }) =>
      _decodeResponse(rawJson, rawRef: rawRef);

  /// Helper to decode JSON response safely with token truncation recovery
  List<ParsedRoutineItem> _decodeResponse(String? rawJson, {String? rawRef}) {
    if (rawJson == null || rawJson.trim().isEmpty) return [];

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

    // 1. Fast path: Standard complete JSON
    try {
      final dynamic decoded = jsonDecode(cleaned);
      final items = _extractItemsFromDecoded(decoded, rawRef: rawRef);
      if (items.isNotEmpty) return items;
    } catch (e) {
      debugPrint(
        'Standard JSON parse failed, attempting token truncation recovery: $e',
      );
    }

    // 2. Truncation Recovery: If hit max tokens and JSON was cut off mid-stream
    try {
      final repaired = _tryRepairTruncatedJson(cleaned);
      if (repaired != null) {
        final dynamic decoded = jsonDecode(repaired);
        final items = _extractItemsFromDecoded(decoded, rawRef: rawRef);
        if (items.isNotEmpty) {
          debugPrint(
            'Successfully recovered ${items.length} items from token-truncated JSON!',
          );
          return items;
        }
      }
    } catch (e) {
      debugPrint('Truncated repair attempt failed: $e');
    }

    // 3. Robust Scanner: Extract individual complete {...} objects
    try {
      final items = _extractIndividualObjects(cleaned, rawRef: rawRef);
      if (items.isNotEmpty) {
        debugPrint(
          'Recovered ${items.length} items via individual object scanner!',
        );
        return items;
      }
    } catch (e) {
      debugPrint('Individual object extraction failed: $e');
    }

    return [];
  }

  List<ParsedRoutineItem> _extractItemsFromDecoded(
    dynamic decoded, {
    String? rawRef,
  }) {
    if (decoded is List) {
      return decoded
          .whereType<Map>()
          .map(
            (e) => ParsedRoutineItem.fromJson(
              Map<String, dynamic>.from(e),
              rawRef: rawRef,
            ),
          )
          .where(_isValidRoutineItem)
          .toList();
    } else if (decoded is Map) {
      final defaultTrack = decoded['track_name']?.toString() ??
          decoded['program_name']?.toString() ??
          decoded['batch_name']?.toString() ??
          decoded['routine_title']?.toString();

      final list = decoded['exams'] ??
          decoded['schedules'] ??
          decoded['items'] ??
          decoded['routine'] ??
          decoded['data'];

      if (list is List) {
        return list
            .whereType<Map>()
            .map(
              (e) => ParsedRoutineItem.fromJson(
                Map<String, dynamic>.from(e),
                rawRef: rawRef,
                defaultTrack: defaultTrack,
              ),
            )
            .where(_isValidRoutineItem)
            .toList();
      }
    }
    return [];
  }

  bool _isValidRoutineItem(ParsedRoutineItem item) {
    return item.subject.trim().isNotEmpty ||
        (item.title != null && item.title!.trim().isNotEmpty);
  }

  String? _tryRepairTruncatedJson(String text) {
    var s = text.trim();
    if (s.isEmpty) return null;

    if (s.endsWith('```')) {
      s = s.substring(0, s.length - 3).trim();
    }

    final lastBraceIndex = s.lastIndexOf('}');
    if (lastBraceIndex == -1) return null;

    final truncated = s.substring(0, lastBraceIndex + 1).trim();

    if (truncated.startsWith('[')) {
      return '$truncated]';
    }

    if (truncated.startsWith('{')) {
      int openBrackets = 0;
      int openBraces = 0;
      bool inString = false;
      bool escaped = false;

      for (int i = 0; i < truncated.length; i++) {
        final c = truncated[i];
        if (escaped) {
          escaped = false;
          continue;
        }
        if (c == '\\') {
          escaped = true;
          continue;
        }
        if (c == '"') {
          inString = !inString;
          continue;
        }
        if (!inString) {
          if (c == '[') openBrackets++;
          if (c == ']') openBrackets--;
          if (c == '{') openBraces++;
          if (c == '}') openBraces--;
        }
      }

      final buf = StringBuffer(truncated);
      while (openBrackets > 0) {
        buf.write(']');
        openBrackets--;
      }
      while (openBraces > 0) {
        buf.write('}');
        openBraces--;
      }
      return buf.toString();
    }

    return null;
  }

  List<ParsedRoutineItem> _extractIndividualObjects(
    String text, {
    String? rawRef,
  }) {
    final List<ParsedRoutineItem> results = [];

    String? detectedTrack;
    final trackMatch = RegExp(
      r'"(?:track_name|program_name|batch_name)"\s*:\s*"([^"]+)"',
    ).firstMatch(text);
    if (trackMatch != null) {
      detectedTrack = trackMatch.group(1);
    }

    final List<int> starts = [];
    bool inString = false;
    bool escaped = false;

    for (int i = 0; i < text.length; i++) {
      final c = text[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (c == '\\') {
        escaped = true;
        continue;
      }
      if (c == '"') {
        inString = !inString;
        continue;
      }
      if (!inString) {
        if (c == '{') {
          starts.add(i);
        } else if (c == '}') {
          if (starts.isNotEmpty) {
            final startIdx = starts.removeLast();
            final candidate = text.substring(startIdx, i + 1);
            try {
              final decoded = jsonDecode(candidate);
              if (decoded is Map &&
                  (decoded.containsKey('date') ||
                      decoded.containsKey('subject') ||
                      decoded.containsKey('title'))) {
                final item = ParsedRoutineItem.fromJson(
                  Map<String, dynamic>.from(decoded),
                  rawRef: rawRef,
                  defaultTrack: detectedTrack,
                );
                if (_isValidRoutineItem(item)) {
                  results.add(item);
                }
              }
            } catch (_) {}
          }
        }
      }
    }

    return results;
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
