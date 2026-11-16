import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/notification_constants.dart';
import '../ai/gemini_usage_tracker.dart';
import 'reference_service.dart';

class ReferenceImportException implements Exception {
  final String message;
  const ReferenceImportException(this.message);
  @override
  String toString() => message;
}

/// Turning a page of a book into a table you can use.
///
/// This is the answer to "what about everything else in my books". A
/// conversion chart or a formula list is already a table on the page; the
/// work is only getting it off the paper, and the app already does exactly
/// this for question banks.
///
/// What comes back is a draft. The import screen shows it before anything is
/// saved, because a misread digit in a conversion table is worse than no
/// table at all — it is a wrong answer the user will trust.
class ReferenceImportService {
  ReferenceImportService._();
  static final ReferenceImportService instance = ReferenceImportService._();

  static const Duration _timeout = Duration(seconds: 120);

  /// Longest edge of the image sent to the model. Large enough for small
  /// print in a conversion table, small enough not to spend a minute
  /// uploading a phone camera's full frame.
  static const int _maxDimension = 1600;

  /// The whole instruction, ready to hand to a stronger model elsewhere.
  ///
  /// The model this app can afford to call is a cheap one, and reading a
  /// dense conversion table off a photographed page is exactly the job it is
  /// worst at — a misread digit there is a wrong answer the user will go on
  /// to trust. So the app does not insist on being the one to do it: this is
  /// the same prompt it would send, copied out, for whichever model the user
  /// already pays for. What comes back is pasted in and parsed verbatim,
  /// with no second opinion from the weaker model in between.
  static String get externalPrompt =>
      'You are reading a page from a Bangladeshi competitive-exam study '
      'book. Extract the reference table printed on it.\n'
      '$_rules\n'
      'Return the JSON only. I will paste your reply straight into an app.';

  static const String _rules = '''
Rules:
1. Reproduce the table EXACTLY as printed. Do not correct, convert or add
   values of your own. If a figure is unreadable, write it as "?" rather
   than guessing.
2. Keep the printed language. Bengali stays Bengali, English stays English.
3. Use Bengali digits (০-৯) only where the source uses them.
4. Give every row the same number of cells as there are columns.
5. If the page holds several unrelated tables, return the largest one.
6. Return ONLY valid JSON. No markdown fences, no text outside the JSON.

JSON structure:
{
  "title": "দৈর্ঘ্যের একক",
  "category": "পরিমাপ ও একক",
  "subject": "গাণিতিক যুক্তি",
  "note": "",
  "columns": ["একক", "সমান"],
  "rows": [
    {"cells": ["১ মাইল", "১.৬১ কিলোমিটার"], "note": ""}
  ]
}
''';

  /// Reads a table out of a photograph of a page.
  Future<ReferenceSheetData> fromImage(File image) async {
    final bytes = await _prepareImage(image);
    final mime = image.path.toLowerCase().endsWith('.png')
        ? 'image/png'
        : 'image/jpeg';

    return _ask(
      parts: [
        TextPart(
          'You are reading a page from a Bangladeshi competitive-exam study '
          'book. Extract the reference table printed on it.\n$_rules',
        ),
        DataPart(mime, bytes),
      ],
      operation: 'reference_import_image',
    );
  }

  /// Reads a table out of text the user pasted or typed.
  ///
  /// JSON in this app's own shape is taken as it stands. That is the whole
  /// point of [externalPrompt]: the user has already had a better model read
  /// the page, and sending its answer through a weaker one to be "parsed"
  /// would only give that model a chance to change the numbers.
  Future<ReferenceSheetData> fromText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw const ReferenceImportException('কিছু লেখা দিন।');
    }

    final direct = parseSheet(trimmed);
    if (direct != null) return direct;

    return _ask(
      parts: [
        TextPart(
          'Turn the following notes from a Bangladeshi competitive-exam study '
          'book into a reference table.\n$_rules\n\nText:\n$trimmed',
        ),
      ],
      operation: 'reference_import_text',
    );
  }

  Future<ReferenceSheetData> _ask({
    required List<Part> parts,
    required String operation,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString(NotificationConstants.prefGeminiApiKey);
    if (apiKey == null || apiKey.isEmpty) {
      throw const ReferenceImportException(
        'Gemini API কী বসানো নেই। সেটিংসে কী দিন, তারপর আবার চেষ্টা করুন।',
      );
    }

    // Reading a table off a page is a vision job the lite model is poor at,
    // so this starts a tier up from the app's default and falls back rather
    // than down.
    const models = ['gemini-flash-latest', 'gemini-flash-lite-latest'];

    Object? lastError;
    for (final modelName in models) {
      try {
        final model = GenerativeModel(
          model: modelName,
          apiKey: apiKey,
          generationConfig: GenerationConfig(
            responseMimeType: 'application/json',
            // Transcription, not composition.
            temperature: 0.0,
          ),
        );

        final response = await model
            .generateContent([Content.multi(parts)])
            .timeout(_timeout);

        final sheet = parseSheet(response.text ?? '');
        if (sheet == null) continue;

        final usage = response.usageMetadata;
        await GeminiUsageTracker.instance.recordSuccess(
          tokens: usage?.totalTokenCount ?? 800,
          actualInputTokens: usage?.promptTokenCount,
          actualOutputTokens: usage?.candidatesTokenCount,
          actualTotalTokens: usage?.totalTokenCount,
          isEstimated: usage?.totalTokenCount == null,
          operation: operation,
          model: modelName,
        );
        return sheet;
      } catch (e) {
        debugPrint('ReferenceImportService error with $modelName: $e');
        lastError = e;
      }
    }

    throw ReferenceImportException(
      lastError == null
          ? 'এই ছবি বা লেখা থেকে টেবিল পাওয়া গেল না। পরিষ্কার ছবি দিয়ে আবার চেষ্টা করুন।'
          : 'টেবিল তৈরি করা গেল না। ইন্টারনেট ও API কী দেখে আবার চেষ্টা করুন।',
    );
  }

  /// Turns the model's reply into a sheet, or null if it is unusable.
  ///
  /// Visible for testing because this is where a reply has to survive
  /// markdown fences, a missing title, and — the one that matters — rows
  /// whose cell count does not match the columns. A ragged row is padded or
  /// trimmed rather than dropped: a line read off the page with one cell
  /// missing is still most of a line, and the user is about to review it.
  @visibleForTesting
  static ReferenceSheetData? parseSheet(String raw) {
    var text = raw.trim();
    if (text.startsWith('```')) {
      text = text.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '');
      if (text.endsWith('```')) text = text.substring(0, text.length - 3);
      text = text.trim();
    }
    if (text.isEmpty) return null;

    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;

    final map = decoded.cast<String, dynamic>();
    final columns = ((map['columns'] as List?) ?? const [])
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (columns.length < 2) return null;

    final rows = <ReferenceRowData>[];
    for (final entry in ((map['rows'] as List?) ?? const []).whereType<Map>()) {
      final row = entry.cast<String, dynamic>();
      final cells = ((row['cells'] as List?) ?? const [])
          .map((e) => e.toString().trim())
          .toList();
      if (cells.every((c) => c.isEmpty)) continue;

      final sized = List<String>.generate(
        columns.length,
        (i) => i < cells.length ? cells[i] : '',
      );
      rows.add(
        ReferenceRowData(
          cells: sized,
          note: row['note']?.toString().trim() ?? '',
        ),
      );
    }
    if (rows.isEmpty) return null;

    final title = map['title']?.toString().trim() ?? '';
    return ReferenceSheetData(
      sheetKey: '',
      title: title.isEmpty ? 'নামহীন টেবিল' : title,
      category: map['category']?.toString().trim().isNotEmpty == true
          ? map['category'].toString().trim()
          : 'আমার টেবিল',
      subject: map['subject']?.toString().trim() ?? '',
      note: map['note']?.toString().trim() ?? '',
      columns: columns,
      rows: rows,
    );
  }

  Future<Uint8List> _prepareImage(File file) async {
    final bytes = await file.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const ReferenceImportException('ছবিটি পড়া গেল না।');
    }
    if (decoded.width <= _maxDimension && decoded.height <= _maxDimension) {
      return bytes;
    }
    final resized = decoded.width >= decoded.height
        ? img.copyResize(decoded, width: _maxDimension)
        : img.copyResize(decoded, height: _maxDimension);
    return Uint8List.fromList(img.encodeJpg(resized, quality: 88));
  }
}
