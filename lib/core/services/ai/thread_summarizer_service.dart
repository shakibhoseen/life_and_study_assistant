import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/notification_constants.dart';
import '../../database/app_database.dart';
import 'gemini_usage_tracker.dart';

/// Keeps a running summary of a chat thread.
///
/// The mentor replays a fixed window of recent messages, so without this a
/// long thread silently forgets everything older — while the system prompt
/// still tells it to "build on the conversation so far". This folds whatever
/// drops out of that window into a short standing summary that travels with
/// every later request.
///
/// It is housekeeping, not the user's reply: it always runs on the cheapest
/// model, never blocks a response, and returns null rather than failing the
/// conversation when something goes wrong.
class ThreadSummarizerService {
  ThreadSummarizerService._();
  static final ThreadSummarizerService instance = ThreadSummarizerService._();

  /// Housekeeping always runs on the cheap model, whatever the user picked
  /// for the conversation itself.
  static const String summaryModel = 'gemini-flash-lite-latest';

  /// Don't re-summarise on every message; wait until this many have dropped
  /// out of the replay window since the last update.
  static const int refreshEveryMessages = 6;

  /// Keeps the summary from growing into a second transcript.
  static const int maxSummaryChars = 800;

  /// How much of each folded message is shown to the summariser. Older
  /// replies are long markdown; their opening carries the substance.
  static const int perMessageCharLimit = 600;

  Future<String?> _getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(NotificationConstants.prefGeminiApiKey);
  }

  /// Folds [messages] into [previousSummary] and returns the updated summary,
  /// or null if it could not be produced.
  Future<String?> summarize({
    required List<ChatMessage> messages,
    String? previousSummary,
    String? subject,
    String? topic,
  }) async {
    if (messages.isEmpty) return previousSummary;

    final apiKey = await _getApiKey();
    if (apiKey == null || apiKey.isEmpty) return previousSummary;

    final transcript = StringBuffer();
    for (final m in messages) {
      final who = m.role == 'user' ? 'USER' : 'MENTOR';
      final text = m.textContent.trim();
      final shown = text.length > perMessageCharLimit
          ? '${text.substring(0, perMessageCharLimit)}…'
          : text;
      transcript.writeln('$who: $shown');
    }

    final threadLine = (subject != null && subject.isNotEmpty)
        ? 'This thread is dedicated to "$subject"${topic != null && topic.isNotEmpty ? ' / "$topic"' : ''}.\n'
        : '';

    final previousBlock =
        (previousSummary != null && previousSummary.trim().isNotEmpty)
        ? 'EXISTING SUMMARY (update it, do not start over):\n$previousSummary\n\n'
        : '';

    final prompt =
        '''
You maintain a running memory note for a BCS study-mentoring conversation.
$threadLine
$previousBlock
NEW MESSAGES TO FOLD IN:
${transcript.toString()}

Rewrite the memory note so a mentor reading only this note could continue the
conversation without seeing the messages. Capture:
- which topics were explained and the key rules or tricks that were settled on
- what the user got wrong, found confusing, or asked to revisit
- any decisions, commitments or tasks agreed
Drop greetings, encouragement and anything already obvious.

Write it as terse bullet points in the same Bengali/English mix the
conversation uses. Hard limit: $maxSummaryChars characters. Output only the
note, no preamble.
''';

    try {
      final model = GenerativeModel(
        model: summaryModel,
        apiKey: apiKey,
        generationConfig: GenerationConfig(
          temperature: 0.2,
          maxOutputTokens: 500,
        ),
      );

      final response = await model.generateContent([Content.text(prompt)]);

      await GeminiUsageTracker.instance.recordSuccess(
        tokens: response.usageMetadata?.totalTokenCount ?? 0,
        actualInputTokens: response.usageMetadata?.promptTokenCount,
        actualOutputTokens: response.usageMetadata?.candidatesTokenCount,
        actualTotalTokens: response.usageMetadata?.totalTokenCount,
        operation: 'thread_summary',
        model: summaryModel,
      );

      final text = response.text?.trim();
      if (text == null || text.isEmpty) return previousSummary;

      return text.length > maxSummaryChars
          ? '${text.substring(0, maxSummaryChars)}…'
          : text;
    } catch (e) {
      debugPrint('Thread summary failed: $e');
      final lower = e.toString().toLowerCase();
      if (lower.contains('429') ||
          lower.contains('resource_exhausted') ||
          lower.contains('quota')) {
        await GeminiUsageTracker.instance.recordQuotaExceeded(
          operation: 'thread_summary',
          model: summaryModel,
        );
      } else {
        await GeminiUsageTracker.instance.recordError(
          e.toString(),
          operation: 'thread_summary',
          model: summaryModel,
        );
      }
      // Summarising is best-effort; the conversation carries on regardless.
      return previousSummary;
    }
  }
}
