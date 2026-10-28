import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
// drift also generates a ChatSession (the stored thread), so the SDK's
// chat handle needs a prefix to tell them apart.
import 'package:google_generative_ai/google_generative_ai.dart' as genai;
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/notification_constants.dart';
import '../../database/app_database.dart';
import '../../../features/chat/domain/models/chat_action.dart';
import '../../utils/bengali_math_sanitizer.dart';
import 'chat_context_resolver.dart';
import 'chat_context_tools.dart';
import 'gemini_prompts.dart';
import 'gemini_usage_tracker.dart';

class GeminiChatResponse {
  final String text;
  final List<ChatAction> actions;
  final String modelUsed;

  const GeminiChatResponse({
    required this.text,
    required this.actions,
    required this.modelUsed,
  });
}

class GeminiChatService {
  GeminiChatService._();
  static final GeminiChatService instance = GeminiChatService._();

  /// Number of stored messages replayed to the model.
  ///
  /// Single source of truth: callers fetch exactly this many and the service
  /// does not truncate a second time.
  ///
  /// Tuned against the real threads on device: dropping 14 -> 10 cut replayed
  /// history by 14-30% depending on the thread, and anything older is now
  /// carried by the rolling summary rather than lost. 8 saved more still but
  /// leaves only four exchanges in view, which reads as forgetful.
  static const int maxHistoryMessages = 10;

  /// Caps a single reply. Bengali tokenises far less efficiently than English
  /// (roughly 2-3x the tokens per character), so this sits well above the
  /// English-equivalent budget for a long grammar explanation.
  static const int maxOutputTokens = 2048;

  /// Mentor replies need some warmth, but the API default of 1.0 made
  /// flash-lite wander and pad.
  static const double chatTemperature = 0.7;

  /// The most recent turns are replayed in full; everything older is kept
  /// only as its opening, which in practice is the heading and first points
  /// of a markdown answer -- enough to hold the thread, a fraction of the
  /// tokens.
  static const int verbatimRecentMessages = 4;

  /// Character budget for a model turn that falls outside the verbatim window.
  static const int olderModelTurnCharLimit = 280;

  /// How many times the model may pull context before it has to answer.
  /// Each round is a full extra API round trip, so this is deliberately low.
  static const int maxContextToolRounds = 2;

  Future<String?> _getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(NotificationConstants.prefGeminiApiKey);
  }

  Future<String> _getSelectedModel() async {
    final prefs = await SharedPreferences.getInstance();
    final model =
        prefs.getString(NotificationConstants.prefGeminiModel) ??
        'gemini-flash-lite-latest';
    if (![
      'gemini-flash-lite-latest',
      'gemini-flash-latest',
      'gemini-pro-latest',
    ].contains(model)) {
      return 'gemini-flash-lite-latest';
    }
    return model;
  }

  /// Sends user message with full context and conversation history to Gemini
  Future<GeminiChatResponse> sendMessage({
    required String userMessage,
    required List<ChatMessage> history,
    String? energyLevel,
    int? fatigueScore,
    List<WeakTopic>? weakTopics,
    List<ExamSchedule>? upcomingExams,
    bool isOffDay = false,
    String? sessionSubject,
    String? sessionTopic,
    String? threadSummary,

    /// Rows the user named by tag, spelled out so the reply can act on them.
    String? referencedItems,
    ChatContextNeeds needs = const ChatContextNeeds(
      energy: true,
      weakTopics: true,
      exams: true,
    ),
    List<WeakTopic>? reserveWeakTopics,
    List<ExamSchedule>? reserveUpcomingExams,

    /// Called with the answer so far as it arrives. When null the reply is
    /// awaited in one piece instead.
    void Function(String partialText)? onPartial,
  }) async {
    final apiKey = await _getApiKey();
    final modelName = await _getSelectedModel();

    if (apiKey == null || apiKey.isEmpty) {
      return _generateLocalFallbackResponse(
        userMessage: userMessage,
        energyLevel: energyLevel,
        fatigueScore: fatigueScore,
        weakTopics: weakTopics,
        upcomingExams: upcomingExams,
        isOffDay: isOffDay,
        referencedItems: referencedItems,
      );
    }

    final weakTopicsMap = _topicsToMaps(weakTopics);
    final examsMap = _examsToMaps(upcomingExams);

    // Everything the mentor *could* have, whether or not it goes in the
    // prompt. Slices left out are offered as callable tools instead, and
    // answered from this without touching the database again.
    final toolData = ChatContextData(
      weakTopics: _topicsToMaps(reserveWeakTopics ?? weakTopics) ?? const [],
      exams: _examsToMaps(reserveUpcomingExams ?? upcomingExams) ?? const [],
      energyLevel: energyLevel,
      fatigueScore: fatigueScore,
      isOffDay: isOffDay,
    );

    final systemPrompt = GeminiPrompts.buildChatSystemInstruction(
      energyLevel: energyLevel,
      fatigueScore: fatigueScore,
      weakTopics: weakTopicsMap,
      upcomingExams: examsMap,
      isOffDay: isOffDay,
      sessionSubject: sessionSubject,
      sessionTopic: sessionTopic,
      threadSummary: threadSummary,
      referencedItems: referencedItems,
      needs: needs,
    );

    try {
      return await _executeChatCall(
        modelName: modelName,
        apiKey: apiKey,
        systemPrompt: systemPrompt,
        history: history,
        userMessage: userMessage,
        needs: needs,
        toolData: toolData,
        onPartial: onPartial,
      );
    } catch (e) {
      // Redact sensitive API keys and query parameters before logging or displaying
      final sanitizedErr = _sanitizeErrorMessage(e.toString());
      debugPrint('Gemini Chat error with $modelName: $sanitizedErr');

      // Auto-fallback from Pro to Flash-Lite if rate limit / quota issue
      if (modelName.contains('pro')) {
        debugPrint('Auto-fallback from Pro to Flash-Lite for Chat...');
        try {
          return await _executeChatCall(
            modelName: 'gemini-flash-lite-latest',
            apiKey: apiKey,
            systemPrompt: systemPrompt,
            history: history,
            userMessage: userMessage,
            needs: needs,
            toolData: toolData,
            onPartial: onPartial,
          );
        } catch (e2) {
          debugPrint(
            'Flash fallback also failed: ${_sanitizeErrorMessage(e2.toString())}',
          );
        }
      }

      // Surface the real failure in the usage monitor. Every other Gemini
      // service already does this; chat alone stayed silently "Healthy"
      // even after a 429.
      if (_isQuotaError(e.toString())) {
        await GeminiUsageTracker.instance.recordQuotaExceeded(
          operation: 'chat',
          model: modelName,
        );
      } else {
        await GeminiUsageTracker.instance.recordError(
          sanitizedErr,
          operation: 'chat',
          model: modelName,
        );
      }

      return _generateLocalFallbackResponse(
        userMessage: userMessage,
        energyLevel: energyLevel,
        fatigueScore: fatigueScore,
        weakTopics: weakTopics,
        upcomingExams: upcomingExams,
        isOffDay: isOffDay,
        referencedItems: referencedItems,
        errorMessage: sanitizedErr,
      );
    }
  }

  static List<Map<String, dynamic>>? _topicsToMaps(List<WeakTopic>? topics) {
    return topics
        ?.map(
          (t) => {
            'subject': t.subject,
            'topic': t.topicName,
            'proficiency': t.proficiencyLevel.name,
          },
        )
        .toList();
  }

  static List<Map<String, dynamic>>? _examsToMaps(List<ExamSchedule>? exams) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    return exams
        ?.map(
          (e) => {
            'title': e.title,
            'track': e.trackName,
            'examDate': e.examDate.toIso8601String().substring(0, 10),
            // "in 3 days" is both shorter and more actionable than a date.
            'daysAway': DateTime(
              e.examDate.year,
              e.examDate.month,
              e.examDate.day,
            ).difference(todayStart).inDays,
            'topics': e.topicsCovered,
          },
        )
        .toList();
  }

  static bool _isQuotaError(String message) {
    final lower = message.toLowerCase();
    return lower.contains('429') ||
        lower.contains('resource_exhausted') ||
        lower.contains('quota') ||
        lower.contains('rate limit');
  }

  Future<GeminiChatResponse> _executeChatCall({
    required String modelName,
    required String apiKey,
    required String systemPrompt,
    required List<ChatMessage> history,
    required String userMessage,
    ChatContextNeeds needs = const ChatContextNeeds(),
    ChatContextData toolData = const ChatContextData(),
    void Function(String partialText)? onPartial,
  }) async {
    // Slices the keyword matcher left out become callable tools, so the model
    // can pull them if it disagrees. When everything is already in the prompt
    // this is null and the request carries no tool overhead.
    final contextTool = ChatContextToolset.declarationsFor(needs, toolData);

    final model = GenerativeModel(
      model: modelName,
      apiKey: apiKey,
      systemInstruction: Content.system(systemPrompt),
      generationConfig: GenerationConfig(
        temperature: chatTemperature,
        maxOutputTokens: maxOutputTokens,
      ),
      tools: contextTool == null ? null : [contextTool],
      toolConfig: contextTool == null
          ? null
          : ToolConfig(
              functionCallingConfig: FunctionCallingConfig(
                mode: FunctionCallingMode.auto,
              ),
            ),
    );

    final (historyContents, carriedOver) = buildHistoryContents(history);
    final outgoingText = carriedOver == null
        ? userMessage
        : '$carriedOver\n\n$userMessage';

    final chat = model.startChat(history: historyContents);

    // One buffer for the whole turn: a tool round may emit a little text
    // before calling, and the answer that follows continues it.
    final answer = StringBuffer();
    var turn = await _runTurn(
      chat,
      Content.text(outgoingText),
      onPartial,
      answer,
    );

    // Every round trip counts towards the day's usage, not just the last one.
    var tokens = turn.tokens;
    var promptTokens = turn.promptTokens;
    var candidateTokens = turn.candidateTokens;
    final pulled = <String>[];

    for (var round = 0; round < maxContextToolRounds; round++) {
      if (turn.functionCalls.isEmpty) break;

      final replies = [
        for (final call in turn.functionCalls)
          FunctionResponse(
            call.name,
            ChatContextToolset.resolve(call, toolData),
          ),
      ];
      pulled.addAll(turn.functionCalls.map((c) => c.name));

      // The SDK's Content.functionResponses incorrectly hardcodes role: 'function'.
      // The Gemini API rejects that role with:
      // "Role 'function' is not supported. Please use a valid role: SYSTEM, USER, MODEL...".
      // In the Gemini REST protocol, client tool responses must use role: 'user'.
      turn = await _runTurn(
        chat,
        buildFunctionResponseContent(replies),
        onPartial,
        answer,
      );
      tokens += turn.tokens;
      promptTokens += turn.promptTokens;
      candidateTokens += turn.candidateTokens;
    }

    if (pulled.isNotEmpty) {
      debugPrint('Chat pulled context on demand: ${pulled.join(', ')}');
    }

    var rawText = answer.isEmpty
        ? 'দুঃখিত, কোনো উত্তর পাওয়া যায়নি। আবার চেষ্টা করুন।'
        : answer.toString();

    final hitOutputCap = turn.hitOutputCap;
    if (hitOutputCap) {
      rawText += '\n\n_(উত্তরটি দীর্ঘ হওয়ায় এখানেই থেমেছে — বাকিটা জানতে "আরও বলো" লিখুন।)_';
    }

    // Real usage reported by the API. If 0 (e.g. offline mock or missing usageMetadata),
    // estimate from text length and mark as isEstimated so it is never mislabeled.
    final bool isEstimated = (tokens == 0);
    if (isEstimated) {
      tokens =
          ((systemPrompt.length + outgoingText.length + rawText.length) / 2.5)
              .round();
    }

    await GeminiUsageTracker.instance.recordSuccess(
      tokens: tokens,
      actualInputTokens: isEstimated ? 0 : promptTokens,
      actualOutputTokens: isEstimated ? 0 : candidateTokens,
      actualTotalTokens: isEstimated ? 0 : tokens,
      isEstimated: isEstimated,
      operation: pulled.isEmpty ? 'chat' : 'chat+tools',
      model: modelName,
    );

    final actions = ChatAction.extractActions(rawText);
    final cleanText = ChatAction.cleanActionTags(rawText);
    final sanitizedText = BengaliMathSanitizer.sanitize(cleanText);

    return GeminiChatResponse(
      text: sanitizedText,
      actions: actions,
      modelUsed: modelName,
    );
  }

  /// Formats function responses for the Gemini API.
  ///
  /// The SDK's [Content.functionResponses] incorrectly hardcodes `role: 'function'`,
  /// which the Gemini backend rejects with:
  /// "Role 'function' is not supported. Please use a valid role: SYSTEM, USER, MODEL...".
  ///
  /// In the Gemini REST API protocol, tool responses must be returned as a client turn
  /// with `role: 'user'`.
  @visibleForTesting
  static Content buildFunctionResponseContent(
    Iterable<FunctionResponse> replies,
  ) {
    return Content('user', replies.toList());
  }

  /// Converts stored messages into a history Gemini will accept.
  ///
  /// The API requires strictly alternating turns that start with `user` and
  /// end with `model`. Consecutive same-role messages are *merged* rather than
  /// dropped: they occur when a send fails after the user message was already
  /// persisted, and dropping them silently lost what the user had written.
  /// A trailing user turn is returned separately so the caller can prepend it
  /// to the outgoing message instead of discarding it.
  @visibleForTesting
  (List<Content>, String?) buildHistoryContents(List<ChatMessage> history) {
    final recent = history.length > maxHistoryMessages
        ? history.sublist(history.length - maxHistoryMessages)
        : history;

    final turns = <({String role, String text})>[];
    for (final m in recent) {
      final role = m.role.trim().toLowerCase();
      // Ensure only Gemini-compatible roles are passed. Map 'assistant' to 'model'.
      // Safely drop any invalid or unsupported roles (such as 'function' or 'tool').
      final normalizedRole = (role == 'model' || role == 'assistant')
          ? 'model'
          : (role == 'user' ? 'user' : null);
      if (normalizedRole == null) continue;
      final text = m.textContent.trim();
      if (text.isEmpty) continue;

      if (turns.isNotEmpty && turns.last.role == normalizedRole) {
        turns[turns.length - 1] = (
          role: normalizedRole,
          text: '${turns.last.text}\n\n$text',
        );
      } else {
        turns.add((role: normalizedRole, text: text));
      }
    }

    while (turns.isNotEmpty && turns.first.role != 'user') {
      turns.removeAt(0);
    }

    final carried = <String>[];
    while (turns.isNotEmpty && turns.last.role != 'model') {
      carried.insert(0, turns.removeLast().text);
    }

    // Older model turns are long markdown answers and dominate the prompt.
    // Keep the newest few verbatim and reduce the rest to their opening.
    final verbatimFrom = turns.length - verbatimRecentMessages;
    final contents = <Content>[];
    for (var i = 0; i < turns.length; i++) {
      final t = turns[i];
      if (t.role == 'user') {
        contents.add(Content.text(t.text));
      } else {
        final text = i < verbatimFrom
            ? _condense(t.text, olderModelTurnCharLimit)
            : t.text;
        contents.add(Content.model([TextPart(text)]));
      }
    }

    return (contents, carried.isEmpty ? null : carried.join('\n\n'));
  }

  /// Runs one exchange with the model, streaming it when [onPartial] is given.
  ///
  /// Text is appended to [answer] either way, so the caller sees the same
  /// result whichever path ran; the only difference is whether the user
  /// watched it arrive.
  Future<_ChatTurn> _runTurn(
    genai.ChatSession chat,
    Content message,
    void Function(String partialText)? onPartial,
    StringBuffer answer,
  ) async {
    if (onPartial == null) {
      final response = await chat.sendMessage(message);
      final text = response.text;
      if (text != null && text.isNotEmpty) answer.write(text);
      return _ChatTurn(
        functionCalls: response.functionCalls.toList(),
        tokens: response.usageMetadata?.totalTokenCount ?? 0,
        promptTokens: response.usageMetadata?.promptTokenCount ?? 0,
        candidateTokens: response.usageMetadata?.candidatesTokenCount ?? 0,
        hitOutputCap: _hitOutputCap(response),
      );
    }

    final calls = <FunctionCall>[];
    var tokens = 0;
    var promptTokens = 0;
    var candidateTokens = 0;
    var hitCap = false;

    await for (final chunk in chat.sendMessageStream(message)) {
      final text = chunk.text;
      if (text != null && text.isNotEmpty) {
        answer.write(text);
        onPartial(answer.toString());
      }
      calls.addAll(chunk.functionCalls);

      // Streaming reports usage cumulatively, so the largest figure seen is
      // the total rather than something to add up.
      final chunkPrompt = chunk.usageMetadata?.promptTokenCount;
      if (chunkPrompt != null && chunkPrompt > promptTokens) {
        promptTokens = chunkPrompt;
      }

      final chunkCandidate = chunk.usageMetadata?.candidatesTokenCount;
      if (chunkCandidate != null && chunkCandidate > candidateTokens) {
        candidateTokens = chunkCandidate;
      }

      final chunkTokens = chunk.usageMetadata?.totalTokenCount;
      if (chunkTokens != null && chunkTokens > tokens) tokens = chunkTokens;

      if (_hitOutputCap(chunk)) hitCap = true;
    }

    return _ChatTurn(
      functionCalls: calls,
      tokens: tokens,
      promptTokens: promptTokens,
      candidateTokens: candidateTokens,
      hitOutputCap: hitCap,
    );
  }

  static bool _hitOutputCap(GenerateContentResponse response) =>
      response.candidates.isNotEmpty &&
      response.candidates.first.finishReason == FinishReason.maxTokens;

  /// Trims an older reply to its opening, on a line boundary where possible.
  static String _condense(String text, int limit) {
    if (text.length <= limit) return text;
    final cut = text.substring(0, limit);
    final lastBreak = cut.lastIndexOf('\n');
    final body = lastBreak > limit ~/ 2 ? cut.substring(0, lastBreak) : cut;
    return '$body\n…(সংক্ষেপিত)';
  }

  /// Redacts API keys and sensitive credentials from error messages before
  /// logging or displaying in user-facing diagnostics.
  @visibleForTesting
  static String sanitizeErrorMessage(String message) {
    return message
        .replaceAll(RegExp(r'AIza[0-9A-Za-z\-_]{35}'), '[REDACTED_API_KEY]')
        .replaceAll(RegExp(r'key=[0-9A-Za-z\-_]+'), 'key=[REDACTED]');
  }

  static String _sanitizeErrorMessage(String message) =>
      sanitizeErrorMessage(message);

  GeminiChatResponse _generateLocalFallbackResponse({
    required String userMessage,
    String? energyLevel,
    int? fatigueScore,
    List<WeakTopic>? weakTopics,
    List<ExamSchedule>? upcomingExams,
    bool isOffDay = false,
    String? referencedItems,
    String? errorMessage,
  }) {
    final lower = userMessage.toLowerCase();
    String responseText;
    final actions = <ChatAction>[];

    if (errorMessage != null) {
      final sanitizedErr = _sanitizeErrorMessage(errorMessage);
      final errLower = sanitizedErr.toLowerCase();
      String diagnosis;

      if (errLower.contains('api_key_invalid') ||
          errLower.contains('api key not valid') ||
          errLower.contains('invalid api key')) {
        diagnosis = '🔑 **API Key অবৈধ বা ভুল।**\nঅনুগ্রহ করে Google AI Studio থেকে নতুন API Key কপি করে Settings এ পেস্ট করুন।';
      } else if (errLower.contains('429') ||
          errLower.contains('resource_exhausted') ||
          errLower.contains('quota')) {
        diagnosis = '⏳ **Quota / Rate Limit শেষ হয়েছে।**\nকিছুক্ষণ পর আবার চেষ্টা করুন বা Settings থেকে অন্য মডেল (Flash / Pro) সিলেক্ট করুন।';
      } else if (errLower.contains('location') ||
          errLower.contains('not supported in your country')) {
        diagnosis = '🌐 **জিও-লোকেশন রেস্ট্রিকশন।**\nGoogle AI Studio আপনার বর্তমান নেটওয়ার্ক আইপি থেকে সাময়িক রেস্ট্রিক্ট করেছে।';
      } else if (errLower.contains('socketexception') ||
          errLower.contains('failed host lookup') ||
          errLower.contains('network is unreachable') ||
          errLower.contains('connection refused') ||
          errLower.contains('handshake')) {
        diagnosis = '📶 **ইন্টারনেট সংযোগ সমস্যা।**\nফোনের ইন্টারনেট বা Wi-Fi চেক করুন।';
      } else {
        diagnosis = '🔍 **কারিগরি কারণ:** $sanitizedErr';
      }

      responseText =
          '''
⚠️ **API সংযোগে সমস্যা হয়েছে**
$diagnosis

---
অফলাইনে আপনার তথ্যের ওপর ভিত্তি করে সাহায্য করছি:
''';
    } else {
      responseText = '''
💡 **Gemini API Key সেট করা নেই (অফলাইন মোড সক্রিয়)**
সম্পূর্ণ AI ফিচারের জন্য Settings এ গিয়ে আপনার Gemini API Key যুক্ত করুন। 
বর্তমানে আপনার লোকাল ডেটাবেসের তথ্যের ওপর ভিত্তি করে উত্তর দেওয়া হলো:
''';
    }

    final fatigue = fatigueScore ?? 5;
    final hasHighFatigue = fatigue >= 7;

    if (isOffDay && !lower.contains('ক্লান্ত')) {
      responseText += '''
* 🌴 আজ আপনার অফ-ডে (বৃহস্পতিবার/শুক্রবার)! কোনো অফিসের চাপ নেই।
* আজকের দিনের জন্য ১-২টি মূল দুর্বল বিষয় (যেমন ব্যাকরণ বা গণিত) গভীরভাবে পড়ার চমৎকার সুযোগ।
* পাশাপাশি পরিবারকে ভালো সময় দিন।
''';
      if (weakTopics != null && weakTopics.isNotEmpty) {
        actions.add(
          ChatAction(
            type: ChatActionType.studyTask,
            title: '৩০ মিনিটের ডিপ ড্রিল: ${weakTopics.first.topicName}',
            subject: weakTopics.first.subject,
            minutes: 30,
          ),
        );
      }
    } else if (lower.contains('ক্লান্ত') ||
        lower.contains('fatigue') ||
        lower.contains('tired') ||
        hasHighFatigue) {
      responseText += '''
* আপনি সারা দিন কোডিং করে অফিস শেষে ক্লান্ত। BCS জার্নিতে সুস্থ থাকাটাই সবচেয়ে বড় স্ট্র্যাটেজি।
* আজ কোনো ভারি টপিক পড়বেন না। শুধু **৫-১০ মিনিট** যেকোনো একটি রিভিশন কার্ড দেখুন।
* বাকি সময়টা পরিবার/স্ত্রীর সাথে আড্ডা দিন এবং তাড়াতাড়ি ঘুমিয়ে পড়ুন।
''';
      actions.add(
        const ChatAction(
          type: ChatActionType.studyTask,
          title: '৫ মিনিটের ফর্মুলা কার্ড রিভিশন',
          subject: 'রিভিউ',
          minutes: 5,
        ),
      );
    } else if (lower.contains('সমাস') || lower.contains('samas')) {
      responseText += '''
### সমাস সহজে মনে রাখার ট্রিকস:
1. **দ্বন্দ্ব:** উভয় পদ প্রধান (মা ও বাবা = মা-বাবা)।
2. **দ্বিগু:** সংখ্যাবাচক শব্দের সমাহার এবং সমাস নিষ্পন্ন পদটি বিশেষ্য (ত্রিফলা, চৌরাস্তা)।
3. **কর্মধারয়:** পরপদ প্রধান, বিশেষণ + বিশেষ্য (নীল যে পদ্ম = নীলপদ্ম)।
4. **তৎপুরুষ:** পূর্বপদের বিভক্তি লোপ পায় (দুঃখকে প্রাপ্ত = দুঃখপ্রাপ্ত)।
5. **বহুব্রীহি:** পূর্বপদ বা পরপদ কোনোটির অর্থ না বুঝিয়ে ভিন্ন অর্থ বোঝায় (দশ আনন যার = দশানন/রাবণ)।
6. **অব্যয়ীভাব:** পূর্বপদের অব্যয়ের অর্থ প্রধান (কূলের সমীপে = উপকূল)।
''';
      actions.add(
        const ChatAction(
          type: ChatActionType.addTopic,
          title: 'Add "সমাস" to Weak Topics',
          subject: 'বাংলা ব্যাকরণ',
          topic: 'সমাস',
          proficiency: 'weak',
        ),
      );
    } else if ((lower.contains('রুটিন') &&
            (lower.contains('বানাও') ||
                lower.contains('তৈরি') ||
                lower.contains('plan') ||
                lower.contains('make') ||
                lower.contains('create') ||
                lower.contains('দাও'))) ||
        (lower.contains('routine') &&
            (lower.contains('make') ||
                lower.contains('create') ||
                lower.contains('build') ||
                lower.contains('banao') ||
                lower.contains('plan')))) {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final startDate = todayStart.add(const Duration(days: 1));

      // 1. Detect requested duration in days (default to 3, or parsed number e.g. "৭ দিন", "7 days")
      int requestedDays = 3;
      final dayMatch = RegExp(r'(\d+|[০-৯]+)\s*(?:দিন|day)')
          .firstMatch(userMessage);
      if (dayMatch != null) {
        final parsed = int.tryParse(
          BengaliMathSanitizer.toEnglishDigits(dayMatch.group(1)!),
        );
        if (parsed != null && parsed >= 1 && parsed <= 30) {
          requestedDays = parsed;
        }
      } else if (lower.contains('সপ্তাহ') || lower.contains('week')) {
        requestedDays = 7;
      }

      // 2. Detect requested daily study hours (e.g. "৩ ঘণ্টা", "3 hours")
      int? dailyHours;
      final hourMatch = RegExp(r'(\d+|[০-৯]+)\s*(?:ঘণ্টা|ঘন্টা|hour)')
          .firstMatch(userMessage);
      if (hourMatch != null) {
        dailyHours = int.tryParse(
          BengaliMathSanitizer.toEnglishDigits(hourMatch.group(1)!),
        );
      }

      // 3. Resolve referenced exam if user mentioned E-{id}
      ExamSchedule? matchedExam;
      final examRefMatch = RegExp(
        r'E-(\d+)',
        caseSensitive: false,
      ).firstMatch(userMessage);
      if (examRefMatch != null) {
        final examId = int.tryParse(examRefMatch.group(1)!);
        if (examId != null && upcomingExams != null) {
          matchedExam = upcomingExams.where((e) => e.id == examId).firstOrNull;
        }
      }
      matchedExam ??= upcomingExams?.firstOrNull;

      String planTitle = 'স্টাডি রুটিন';
      String track = 'AI Study Sprint';
      String subject = 'General BCS';
      List<String> topicPool = [];

      // Extract exam syllabus & metadata from referencedItems if available
      if (referencedItems != null && examRefMatch != null) {
        final refTag = 'E-${examRefMatch.group(1)}';
        if (referencedItems.contains(refTag)) {
          final syllabusMatch = RegExp(r'সিলেবাস:\s*([^\n]+)')
              .firstMatch(referencedItems);
          if (syllabusMatch != null) {
            final rawSyllabus = syllabusMatch.group(1)!.trim();
            topicPool = rawSyllabus
                .split(RegExp(r'[,;\n]'))
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
          }
          final subjectMatch = RegExp(r'বিষয়:\s*([^·\n]+)')
              .firstMatch(referencedItems);
          final titleMatch = RegExp(r'scheduled exam:\s*([^\n]+)')
              .firstMatch(referencedItems);
          final trackMatch = RegExp(r'ট্র্যাক:\s*([^\n·]+)')
              .firstMatch(referencedItems);

          subject =
              subjectMatch?.group(1)?.trim() ??
              matchedExam?.subject ??
              'General BCS';
          track =
              trackMatch?.group(1)?.trim() ??
              matchedExam?.trackName ??
              'AI Study Sprint';
          planTitle =
              titleMatch?.group(1)?.trim() ??
              matchedExam?.title ??
              'স্টাডি রুটিন';
        }
      }

      if (topicPool.isEmpty && matchedExam != null) {
        planTitle = matchedExam.title;
        track = matchedExam.trackName;
        subject = matchedExam.subject;
        topicPool = matchedExam.topicsCovered
            .split(RegExp(r'[,;\n]'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }

      if (topicPool.isEmpty) {
        topicPool = [
          'বাংলা ব্যাকরণ ও সাহিত্য',
          'English Vocabulary & Grammar',
          'বাংলাদেশ বিষয়াবলি',
          'আন্তর্জাতিক বিষয়াবলি',
          'গাণিতিক যুক্তি ও মানসিক দক্ষতা',
          'সাধারণ বিজ্ঞান ও প্রযুক্তি',
        ];
      }

      final items = <Map<String, dynamic>>[];
      final previewLines = <String>[];

      for (var i = 0; i < requestedDays; i++) {
        final dayNum = i + 1;
        final isLastDay = (dayNum == requestedDays);
        final isPenultimateDay =
            (requestedDays >= 5 && dayNum == requestedDays - 1);
        final date = startDate
            .add(Duration(days: i))
            .toIso8601String()
            .substring(0, 10);

        List<String> dayTopics;
        String dayTitle;
        String examType;

        if (isLastDay) {
          dayTopics = ['সম্পূর্ণ সিলেবাস ফাইনাল রিভিশন ও পূর্ণাঙ্গ মক টেস্ট'];
          dayTitle = 'Day $dayNum: ফাইনাল রিভিশন ও মক টেস্ট';
          examType = 'Mock Test';
        } else if (isPenultimateDay) {
          dayTopics = ['গুরুত্বপূর্ণ টপিক রিভিশন ও দুর্বল অংশ সমাধান'];
          dayTitle = 'Day $dayNum: দ্রুত রিভিশন ও প্র্যাকটিস';
          examType = 'Study Session';
        } else {
          final topicIndex = i % topicPool.length;
          dayTopics = [topicPool[topicIndex]];
          dayTitle = 'Day $dayNum: ${dayTopics.first} প্রস্তুতি';
          examType = 'Study Session';
        }

        items.add({
          'date': date,
          'exam_time': '10:00 PM',
          'subject': subject,
          'title': dayTitle,
          'topics': dayTopics,
          'exam_type': examType,
          'track_name': track,
          'resource_summary': 'AI Mentor Plan',
        });

        previewLines.add(
          '* **Day $dayNum:** ${dayTopics.join(", ")} (${examType == "Mock Test" ? "মক টেস্ট" : "স্টাডি সেশন"})',
        );
      }

      final bnDays = BengaliMathSanitizer.toBengaliDigits('$requestedDays');
      final formattedPlanTitle = '$planTitle ($bnDays দিন)';

      final routineJson = jsonEncode({
        'title': formattedPlanTitle,
        'subject': subject,
        'track': track,
        'items': items,
      });

      final hoursNote = dailyHours != null
          ? '\n*(প্রতিদিন ${BengaliMathSanitizer.toBengaliDigits('$dailyHours')} ঘণ্টা পড়ার সময় অনুযায়ী বিন্যস্ত)*'
          : '';

      responseText +=
          '''
📋 **আপনার জন্য $bnDays দিনের স্টাডি রুটিন খসড়া তৈরি করা হয়েছে:**$hoursNote
${previewLines.join('\n')}

নিচের **"রুটিন প্রিভিউ"** বাটনে ট্যাপ করে প্রতিটি দিনের শিডিউল দেখে নিয়ে আপনার মূল রুটিনে যোগ করুন।
''';
      actions.add(
        ChatAction(
          type: ChatActionType.routinePlan,
          title: formattedPlanTitle,
          subject: subject,
          trackName: track,
          routineJson: routineJson,
        ),
      );
    } else if (lower.contains('পরীক্ষা') ||
        lower.contains('exam') ||
        lower.contains('routine')) {
      if (upcomingExams != null && upcomingExams.isNotEmpty) {
        final next = upcomingExams.first;
        responseText +=
            '''
📅 আপনার পরবর্তী পরীক্ষা: **${next.title}** [${next.trackName}] (${next.examDate.toIso8601String().substring(0, 10)})
🎯 টপিকসমূহ: ${next.topicsCovered}

**পরামর্শ:**
* নতুন কোনো বই পড়ার দরকার নেই।
* LiveMCQ অ্যাপে এই টপিকের বিগত বছরের প্রশ্নগুলো সলভ করুন।
''';
      } else {
        responseText += 'বর্তমানে কোনো আসন্ন পরীক্ষার শিডিউল নেই। LiveMCQ থেকে রুটিন PDF শেয়ার বা আপলোড করে নিন!';
      }
    } else {
      responseText += '''
আমি আপনার স্টাডি ও লাইফ পার্টনার।
* আপনার যেকোনো দুর্বল টপিক (যেমন বাংলা ব্যাকরণ, গণিত, বিজ্ঞান) বুঝিয়ে দিতে পারি।
* টপিক আলোচনার পর চাইলে এক ক্লিকে আপনার **Weak Topics** লিস্টে যুক্ত করে নিতে পারবেন।
* আপনার অফিস ক্লান্তি ও এনার্জি অনুযায়ী কাস্টম মাইক্রো-টাস্ক তৈরি করে দেব।

কী বিষয়ে জানতে বা আলোচনা করতে চান বলুন!
''';
    }

    return GeminiChatResponse(
      text: responseText,
      actions: actions,
      modelUsed: 'offline-local',
    );
  }
}

/// The outcome of one exchange, however it was fetched.
class _ChatTurn {
  final List<FunctionCall> functionCalls;
  final int tokens;
  final int promptTokens;
  final int candidateTokens;
  final bool hitOutputCap;

  const _ChatTurn({
    required this.functionCalls,
    required this.tokens,
    this.promptTokens = 0,
    this.candidateTokens = 0,
    required this.hitOutputCap,
  });
}
