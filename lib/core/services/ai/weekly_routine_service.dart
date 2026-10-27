import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/notification_constants.dart';
import '../../../features/weekly_routine/domain/models/weekly_routine.dart';
import 'gemini_usage_tracker.dart';

/// Shape of a weekly routine, enforced by the API rather than asked for in
/// prose. Keys match WeeklyRoutine.fromJson.
final _routineSchema = Schema.object(
  properties: {
    'title': Schema.string(),
    'principle': Schema.string(
      description: 'One sentence on why the week is shaped this way',
    ),
    'windows': Schema.array(
      description: 'The study windows of a working day, in time order',
      items: Schema.object(
        properties: {
          'label': Schema.string(),
          'time': Schema.string(
            description: 'Bengali digits, e.g. ২০:৩০–২১:৩০',
          ),
          'activity': Schema.string(),
          'note': Schema.string(),
        },
        requiredProperties: ['label', 'time', 'activity', 'note'],
      ),
    ),
    'days': Schema.array(
      description: 'Exactly seven days, Saturday through Friday',
      items: Schema.object(
        properties: {
          'day': Schema.string(
            description: 'শনি, রবি, সোম, মঙ্গল, বুধ, বৃহস্পতি, শুক্র',
          ),
          'focus': Schema.string(),
          'note': Schema.string(),
          'is_off_day': Schema.boolean(),
        },
        requiredProperties: ['day', 'focus', 'note', 'is_off_day'],
      ),
    ),
  },
  requiredProperties: ['title', 'principle', 'windows', 'days'],
);

/// Builds and edits the user's weekly study routine.
///
/// The routine is the model's to write, not the app's: the default exists so
/// there is something on screen from the first run, and every change after
/// that comes from the user's own instruction.
class WeeklyRoutineService {
  WeeklyRoutineService._();
  static final WeeklyRoutineService instance = WeeklyRoutineService._();

  static const int maxOutputTokens = 1536;

  Future<String?> _getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(NotificationConstants.prefGeminiApiKey);
  }

  Future<String> _getModel() async {
    final prefs = await SharedPreferences.getInstance();
    final model =
        prefs.getString(NotificationConstants.prefGeminiModel) ??
        'gemini-flash-lite-latest';
    const allowed = [
      'gemini-flash-lite-latest',
      'gemini-flash-latest',
      'gemini-pro-latest',
    ];
    return allowed.contains(model) ? model : 'gemini-flash-lite-latest';
  }

  /// Rewrites [current] according to [command].
  ///
  /// Returns null when nothing could be produced, so the caller keeps what it
  /// already had rather than showing an empty week.
  Future<WeeklyRoutine?> revise({
    required WeeklyRoutine current,
    required String command,
    List<Map<String, dynamic>> weakTopics = const [],
    List<Map<String, dynamic>> upcomingExams = const [],
    String officeHours = '09:00-18:00',
    String offDays = 'বৃহস্পতি, শুক্র',
  }) async {
    final apiKey = await _getApiKey();
    if (apiKey == null || apiKey.isEmpty) return null;

    final modelName = await _getModel();

    final prompt =
        '''
You maintain a weekly study routine for a Bangladeshi software engineer preparing for BCS and government recruitment exams alongside a full-time job.

Their fixed day: office $officeHours, leaves home an hour before, usually home by 19:00 depending on traffic, then food and a shower. Off days: $offDays.

CURRENT ROUTINE:
${jsonEncode(current.toJson())}

THEIR REGISTERED WEAK TOPICS:
${jsonEncode(weakTopics)}

THEIR UPCOMING EXAMS:
${jsonEncode(upcomingExams)}

THE USER ASKS: $command

Apply that change and return the whole routine. Keep what they did not ask you to change. Write in the same Bengali the current routine uses. Stay realistic about the evening: after a full office day only a short window survives, so do not fill it with several subjects.
''';

    try {
      final model = GenerativeModel(
        model: modelName,
        apiKey: apiKey,
        generationConfig: GenerationConfig(
          temperature: 0.4,
          responseMimeType: 'application/json',
          responseSchema: _routineSchema,
          maxOutputTokens: maxOutputTokens,
        ),
      );

      final response = await model.generateContent([Content.text(prompt)]);

      await GeminiUsageTracker.instance.recordSuccess(
        tokens: response.usageMetadata?.totalTokenCount ?? 0,
        actualInputTokens: response.usageMetadata?.promptTokenCount,
        actualOutputTokens: response.usageMetadata?.candidatesTokenCount,
        actualTotalTokens: response.usageMetadata?.totalTokenCount,
        operation: 'weekly_routine',
        model: modelName,
      );

      final text = response.text;
      if (text == null || text.trim().isEmpty) return null;

      final decoded = jsonDecode(text);
      if (decoded is! Map) return null;

      return WeeklyRoutine.fromJson(decoded.cast<String, Object?>())
          .copyWith(updatedAt: DateTime.now(), lastCommand: command);
    } catch (e) {
      debugPrint('Weekly routine revision failed: $e');
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
}
