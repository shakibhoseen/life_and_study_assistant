import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/notification_constants.dart';
import '../ai/gemini_usage_tracker.dart';
import 'syllabus_service.dart';

class SyllabusDraftException implements Exception {
  final String message;
  const SyllabusDraftException(this.message);
  @override
  String toString() => message;
}

/// Drafting a syllabus for an exam the app does not ship a map for.
///
/// Every track that comes out of here is a draft and is labelled as one. The
/// bundled maps are written by hand precisely because a wrong mark
/// distribution sends someone to study the wrong thing for a month; a model
/// cannot be trusted with that, and the app should not pretend otherwise.
/// What it can do is save an hour of typing for an exam nobody has written a
/// map for, and hand the result straight to the editor.
class SyllabusDraftService {
  SyllabusDraftService._();
  static final SyllabusDraftService instance = SyllabusDraftService._();

  /// Long enough for a full syllabus on a slow connection, bounded so a
  /// stalled request cannot leave the sheet spinning for ever.
  static const Duration _timeout = Duration(seconds: 90);

  /// What a drafted track carries in its note, so the warning travels with
  /// the data rather than living only in the dialog that made it.
  static const String draftNote =
      'AI-এর বানানো খসড়া — মানবণ্টন ও টপিক নিজে মিলিয়ে নিন।';

  /// Asks the model for a syllabus for [examName].
  ///
  /// [trackKey] is left empty: the caller creates the track and owns its key,
  /// because the model has no business naming rows.
  Future<SyllabusTrack> draft(String examName) async {
    final trimmed = examName.trim();
    if (trimmed.isEmpty) {
      throw const SyllabusDraftException('পরীক্ষার নাম লিখুন।');
    }

    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString(NotificationConstants.prefGeminiApiKey);
    if (apiKey == null || apiKey.isEmpty) {
      throw const SyllabusDraftException(
        'Gemini API কী বসানো নেই। সেটিংসে কী দিন, তারপর আবার চেষ্টা করুন।',
      );
    }

    final prompt =
        '''
You are an expert on Bangladeshi public service and teacher recruitment exams.
Produce the syllabus for the preliminary/written objective stage of: "$trimmed"

Rules:
1. List the subjects exactly as that exam's official mark distribution has
   them, with the marks each subject carries.
2. The subject marks MUST add up to the exam's stated total marks.
3. Under each subject list 8-20 topics as they are actually examined, in a
   sensible study order. Topic titles in Bengali, except for English-language
   topics which stay in English.
4. Give each topic a weight of 1, 2 or 3 for how heavily it is examined
   within its subject.
5. Name the distinguishing word FIRST in a topic title. Write
   "মঙ্গলকাব্য (মধ্যযুগ)", never "মধ্যযুগ: মঙ্গলকাব্য".
6. If you are not confident of this exam's real mark distribution, return
   your best standard structure anyway — the user will check it.
7. Return ONLY valid JSON, no markdown fences, no text outside the JSON.

JSON structure:
{
  "trackName": "পরীক্ষার নাম",
  "totalMarks": 100,
  "subjects": [
    {
      "name": "বাংলা",
      "marks": 25,
      "topics": [
        {"title": "কারক ও বিভক্তি", "weight": 3}
      ]
    }
  ]
}
''';

    final savedModel =
        prefs.getString(NotificationConstants.prefGeminiModel) ??
        'gemini-flash-lite-latest';
    final primary =
        const [
          'gemini-flash-lite-latest',
          'gemini-flash-latest',
          'gemini-pro-latest',
        ].contains(savedModel)
        ? savedModel
        : 'gemini-flash-lite-latest';

    final modelsToTry = [
      primary,
      if (primary != 'gemini-flash-latest') 'gemini-flash-latest',
      if (primary != 'gemini-flash-lite-latest') 'gemini-flash-lite-latest',
    ];

    Object? lastError;
    for (final modelName in modelsToTry) {
      try {
        final model = GenerativeModel(
          model: modelName,
          apiKey: apiKey,
          generationConfig: GenerationConfig(
            responseMimeType: 'application/json',
            // Low, because this is a question of fact about a published
            // syllabus, not a request for variety.
            temperature: 0.1,
          ),
        );

        final response = await model
            .generateContent([Content.text(prompt)])
            .timeout(_timeout);

        final raw = response.text?.trim() ?? '';
        if (raw.isEmpty) continue;

        final track = parseDraft(raw, fallbackName: trimmed);
        if (track == null || track.subjects.isEmpty) continue;

        final usage = response.usageMetadata;
        await GeminiUsageTracker.instance.recordSuccess(
          tokens: usage?.totalTokenCount ?? 600,
          actualInputTokens: usage?.promptTokenCount,
          actualOutputTokens: usage?.candidatesTokenCount,
          actualTotalTokens: usage?.totalTokenCount,
          isEstimated: usage?.totalTokenCount == null,
          operation: 'syllabus_draft',
          model: modelName,
        );
        return track;
      } catch (e) {
        debugPrint('SyllabusDraftService error with $modelName: $e');
        lastError = e;
      }
    }

    throw SyllabusDraftException(
      'সিলেবাসের খসড়া তৈরি করা গেল না। '
      '${lastError == null ? 'আবার চেষ্টা করুন।' : 'ইন্টারনেট ও API কী দেখে আবার চেষ্টা করুন।'}',
    );
  }

  /// Turns the model's reply into a track, or null if it is unusable.
  ///
  /// Separate and visible so the parsing can be tested without a network
  /// call — which matters, because this is the layer that has to survive a
  /// model wrapping its JSON in fences or returning a bare array.
  @visibleForTesting
  static SyllabusTrack? parseDraft(String raw, {required String fallbackName}) {
    var text = raw.trim();
    if (text.startsWith('```')) {
      text = text.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '');
      if (text.endsWith('```')) {
        text = text.substring(0, text.length - 3);
      }
      text = text.trim();
    }

    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      return null;
    }

    // A bare array of subjects is a shape models fall into often enough to
    // be worth accepting rather than discarding a whole generation over.
    final map = switch (decoded) {
      Map<String, dynamic> m => m,
      List<dynamic> l => {'subjects': l},
      _ => null,
    };
    if (map == null) return null;

    final name = (map['trackName']?.toString().trim() ?? '');
    final parsed = SyllabusTrack.fromJson({
      ...map,
      'trackKey': '',
      'trackName': name.isEmpty ? fallbackName : name,
      'note': draftNote,
    });

    final usable = parsed.subjects
        .where((s) => s.name.trim().isNotEmpty && s.topics.isNotEmpty)
        .toList();
    if (usable.isEmpty) return null;

    return SyllabusTrack(
      trackKey: '',
      trackName: parsed.trackName,
      totalMarks: parsed.totalMarks,
      note: draftNote,
      subjects: usable,
    );
  }
}
