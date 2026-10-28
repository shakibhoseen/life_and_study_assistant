import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/services/ai/entity_ref_resolver.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../core/database/tables/weak_topics_table.dart';
import '../../../../core/services/ai/chat_context_resolver.dart';
import '../../../../core/services/ai/gemini_chat_service.dart';
import '../../../../core/services/ai/thread_summarizer_service.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../../core/utils/bengali_math_sanitizer.dart';
import '../../../../core/services/ai/models/parsed_routine_item.dart';
import '../../../../core/services/ai/models/quiz_question.dart';
import '../../../../core/services/ai/quiz_batch_correction_service.dart';
import '../../../../core/services/ai/routine_parser_service.dart';
import '../../domain/models/chat_action.dart';

final chatSessionsStreamProvider = StreamProvider<List<ChatSession>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.watchAllChatSessions();
});

final currentSessionMessagesStreamProvider = StreamProvider<List<ChatMessage>>((
  ref,
) {
  final db = ref.watch(appDatabaseProvider);
  final currentSessionId = ref.watch(
    chatNotifierProvider.select((s) => s.currentSessionId),
  );
  if (currentSessionId == null) {
    return db.watchChatMessages();
  }
  return db.watchChatMessagesForSession(currentSessionId);
});

// Backward-compatible alias
final chatMessagesStreamProvider = currentSessionMessagesStreamProvider;

class ChatState {
  final int? currentSessionId;
  final ChatSession? currentSession;
  final bool isSending;

  /// True once the reply has started arriving. The "typing" bubble is for the
  /// wait before that; after it, the half-written reply is the indicator.
  final bool isStreaming;
  final String? errorMessage;
  final String? currentModelUsed;

  const ChatState({
    this.currentSessionId,
    this.currentSession,
    this.isSending = false,
    this.isStreaming = false,
    this.errorMessage,
    this.currentModelUsed,
  });

  ChatState copyWith({
    int? currentSessionId,
    ChatSession? currentSession,
    bool? isSending,
    bool? isStreaming,
    String? errorMessage,
    String? currentModelUsed,
  }) {
    return ChatState(
      currentSessionId: currentSessionId ?? this.currentSessionId,
      currentSession: currentSession ?? this.currentSession,
      isSending: isSending ?? this.isSending,
      isStreaming: isStreaming ?? this.isStreaming,
      errorMessage: errorMessage,
      currentModelUsed: currentModelUsed ?? this.currentModelUsed,
    );
  }
}

/// How often a streaming reply is flushed to the database.
const Duration _streamWriteInterval = Duration(milliseconds: 150);

class ChatNotifier extends Notifier<ChatState> {
  @override
  ChatState build() {
    Future.microtask(() => _initDefaultSession());
    return const ChatState();
  }

  AppDatabase get _db => ref.read(appDatabaseProvider);

  Future<void> _initDefaultSession() async {
    final session = await _db.getOrCreateDefaultSession();
    if (state.currentSessionId == null) {
      state = state.copyWith(
        currentSessionId: session.id,
        currentSession: session,
      );
    }
  }

  Future<void> switchSession(int sessionId) async {
    final session = await _db.getChatSessionById(sessionId);
    if (session != null) {
      state = state.copyWith(
        currentSessionId: session.id,
        currentSession: session,
        errorMessage: null,
      );
    }
  }

  Future<ChatSession> createNewSession({
    required String title,
    String? subject,
    String? topic,
  }) async {
    final id = await _db.createChatSession(
      title: title,
      subject: subject,
      topic: topic,
    );
    final session = await _db.getChatSessionById(id);
    if (session != null) {
      state = state.copyWith(
        currentSessionId: session.id,
        currentSession: session,
        errorMessage: null,
      );
      return session;
    }
    return _db.getOrCreateDefaultSession();
  }

  Future<ChatSession> openOrCreateTopicSession({
    required String subject,
    required String topic,
    String? initialPrompt,
  }) async {
    final session = await _db.getOrCreateTopicSession(
      subject: subject,
      topic: topic,
    );

    state = state.copyWith(
      currentSessionId: session.id,
      currentSession: session,
      errorMessage: null,
    );

    if (initialPrompt != null && initialPrompt.trim().isNotEmpty) {
      await sendMessage(initialPrompt);
    }

    return session;
  }

  Future<void> renameSession(int sessionId, String newTitle) async {
    await _db.updateChatSessionTitle(sessionId, newTitle);
    if (state.currentSessionId == sessionId) {
      final updated = await _db.getChatSessionById(sessionId);
      if (updated != null) {
        state = state.copyWith(currentSession: updated);
      }
    }
  }

  Future<void> deleteSession(int sessionId) async {
    await _db.deleteChatSession(sessionId);
    if (state.currentSessionId == sessionId) {
      final defaultSession = await _db.getOrCreateDefaultSession();
      state = state.copyWith(
        currentSessionId: defaultSession.id,
        currentSession: defaultSession,
      );
    }
  }

  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.isSending) return;

    // Ensure we have an active session
    int sessionId = state.currentSessionId ?? 1;
    if (state.currentSessionId == null) {
      final defaultSession = await _db.getOrCreateDefaultSession();
      sessionId = defaultSession.id;
      state = state.copyWith(
        currentSessionId: sessionId,
        currentSession: defaultSession,
      );
    }

    state = state.copyWith(
      isSending: true,
      isStreaming: false,
      errorMessage: null,
    );

    int? placeholderId;

    try {
      // 1. Fetch PRIOR history for THIS specific session
      final history = await _db.getRecentChatMessagesForSession(
        sessionId,
        limit: GeminiChatService.maxHistoryMessages,
      );

      // 2. Save user message with sessionId
      await _db.insertChatMessage(
        ChatMessagesCompanion.insert(
          sessionId: Value(sessionId),
          role: 'user',
          textContent: trimmed,
        ),
      );

      // 3. Fetch context from DB: today's energy log, weak topics, upcoming exams
      final now = DateTime.now();
      final todayLog = await _db.watchTodayLog(now).first;
      // Capped on purpose: the full lists grow unbounded (a bulk-imported
      // routine alone can hold hundreds of future exams) and were previously
      // resent in full with every single message.
      final candidateTopics = await _db.getContextWeakTopics();
      final candidateExams = await _db.getContextUpcomingExams();
      final settings = await ref.read(settingsNotifierProvider.future);

      // 4. Work out which of those slices this particular message needs.
      // Reading them from the local database is free; putting them in the
      // prompt is not, so a plain teaching question carries none of it.
      final nextExamDays = candidateExams.isEmpty
          ? null
          : DateTime(
              candidateExams.first.examDate.year,
              candidateExams.first.examDate.month,
              candidateExams.first.examDate.day,
            ).difference(DateTime(now.year, now.month, now.day)).inDays;

      final needs = ChatContextResolver.resolve(
        userMessage: trimmed,
        sessionSubject: state.currentSession?.subject,
        sessionTopic: state.currentSession?.topic,
        knownSubjects: candidateTopics.map((t) => t.subject).toSet().toList(),
        fatigueScore: todayLog?.officeFatigueScore,
        daysToNextExam: nextExamDays,
        isFirstMessageInSession: history.isEmpty,
      );

      final weakTopics = _narrowBySubject(candidateTopics, needs.subjectFilter);

      // 5. Wider pools for the slices the matcher left out. These never enter
      // the prompt; they only answer a function call if the model decides it
      // needs context after all. Fetching is local and free, so the only cost
      // is paid when the model actually asks.
      final reserveTopics = needs.weakTopics
          ? null
          : await _db.getContextWeakTopics(limit: 25);
      final reserveExams = needs.exams
          ? null
          : await _db.getContextUpcomingExams(limit: 15, withinDays: 120);

      // 6. Reserve the reply's row up front so the half-written answer has
      // somewhere to live. The message stream is watched, so every write to
      // this row shows up on screen immediately.
      placeholderId = await _db.insertChatMessage(
        ChatMessagesCompanion.insert(
          sessionId: Value(sessionId),
          role: 'model',
          textContent: '',
        ),
      );

      var lastWriteAt = DateTime.fromMillisecondsSinceEpoch(0);

      // 7. Send to Gemini Chat Service with session topic metadata
      final response = await GeminiChatService.instance.sendMessage(
        userMessage: trimmed,
        history: history,
        energyLevel: todayLog?.energyLevel.name,
        fatigueScore: todayLog?.officeFatigueScore,
        weakTopics: weakTopics,
        upcomingExams: candidateExams,
        isOffDay: settings.isTodayOffDay,
        sessionSubject: state.currentSession?.subject,
        sessionTopic: state.currentSession?.topic,
        threadSummary: state.currentSession?.summary,
        // Only reads rows the message actually named, so an ordinary question
        // adds nothing to the prompt.
        referencedItems: await EntityRefResolver.describe(_db, text),
        needs: needs,
        reserveWeakTopics: reserveTopics,
        reserveUpcomingExams: reserveExams,
        onPartial: (partial) {
          final rowId = placeholderId!;
          // Throttled: the model emits chunks far faster than a phone wants
          // to rebuild a markdown list.
          final now = DateTime.now();
          if (now.difference(lastWriteAt) < _streamWriteInterval) return;
          lastWriteAt = now;

          if (!state.isStreaming) {
            state = state.copyWith(isStreaming: true);
          }
          unawaited(_db.updateChatMessageText(rowId, _presentPartial(partial)));
        },
      );

      // 8. Replace the placeholder with the finished, sanitised reply.
      final actionJson = ChatAction.encodeList(response.actions);

      await _db.finalizeChatMessage(
        placeholderId,
        text: response.text,
        suggestedAction: actionJson,
      );

      // Touch session updated time
      await _db.touchChatSession(sessionId);

      state = state.copyWith(
        isSending: false,
        isStreaming: false,
        currentModelUsed: response.modelUsed,
      );

      // Fold anything that just dropped out of the replay window into the
      // thread's standing summary. Deliberately not awaited: the reply is
      // already on screen and this must never delay it or fail it.
      unawaited(_refreshThreadSummary(sessionId));
    } catch (e) {
      // Never leave an empty bubble behind if the send fell over.
      if (placeholderId != null) {
        await _db.deleteChatMessage(placeholderId);
      }
      state = state.copyWith(
        isSending: false,
        isStreaming: false,
        errorMessage: 'Failed to send message: $e',
      );
    }
  }

  /// Cleans a half-written reply for display.
  ///
  /// Action tags are stripped from the first bracket onwards, so a tag being
  /// typed out never flashes on screen as raw text.
  static String _presentPartial(String partial) {
    final tagStart = partial.indexOf('[[');
    final body = tagStart >= 0 ? partial.substring(0, tagStart) : partial;
    return BengaliMathSanitizer.sanitize(body);
  }

  /// Rebuilds the session's running summary when enough messages have fallen
  /// out of the replayed history window.
  ///
  /// Everything newer than [GeminiChatService.maxHistoryMessages] is still
  /// replayed verbatim, so only the older remainder is ever summarised, and
  /// only once it has grown by [ThreadSummarizerService.refreshEveryMessages]
  /// since the last update — one cheap call per several exchanges, not one
  /// per message.
  Future<void> _refreshThreadSummary(int sessionId) async {
    try {
      final session = await _db.getChatSessionById(sessionId);
      if (session == null) return;

      final all = await _db.getAllChatMessagesForSession(sessionId);
      if (all.length <= GeminiChatService.maxHistoryMessages) return;

      final foldable = all.sublist(
        0,
        all.length - GeminiChatService.maxHistoryMessages,
      );
      if (foldable.isEmpty) return;

      final alreadyCovered = session.summarizedUpToId ?? 0;
      final pending = foldable
          .where((m) => m.id > alreadyCovered)
          .toList(growable: false);
      if (pending.length < ThreadSummarizerService.refreshEveryMessages) return;

      final summary = await ThreadSummarizerService.instance.summarize(
        messages: pending,
        previousSummary: session.summary,
        subject: session.subject,
        topic: session.topic,
      );
      if (summary == null || summary.trim().isEmpty) return;

      await _db.updateChatSessionSummary(
        sessionId,
        summary: summary,
        upToId: foldable.last.id,
      );

      // Keep the in-memory session in step so the next message carries it.
      if (state.currentSessionId == sessionId) {
        final updated = await _db.getChatSessionById(sessionId);
        if (updated != null) {
          state = state.copyWith(currentSession: updated);
        }
      }
    } catch (e) {
      // Best effort only — a failed summary must never surface to the user.
      debugPrint('Thread summary refresh skipped: $e');
    }
  }

  /// Narrows weak topics to one subject when the message or thread named one.
  ///
  /// Falls back to the unfiltered list when the subject matches nothing, so a
  /// thread about a subject with no registered topics still gets context.
  static List<WeakTopic> _narrowBySubject(
    List<WeakTopic> topics,
    String? subject,
  ) {
    if (subject == null || subject.trim().isEmpty) return topics;
    final target = subject.trim().toLowerCase();
    final filtered = topics
        .where((t) => t.subject.trim().toLowerCase() == target)
        .toList();
    return filtered.isEmpty ? topics : filtered;
  }

  /// Executes an interactive action suggested by Gemini (e.g. Add to Weak Topics, Routine Plan)
  Future<bool> executeAction({
    required ChatAction action,
    required ChatMessage message,
    List<ParsedRoutineItem>? approvedItems,
  }) async {
    if (action.isExecuted) return false;
    try {
      if (action.type == ChatActionType.addTopic) {
        ProficiencyLevel prof = ProficiencyLevel.weak;
        if (action.proficiency == 'moderate') prof = ProficiencyLevel.moderate;
        if (action.proficiency == 'strong') prof = ProficiencyLevel.strong;

        await _db.insertWeakTopic(
          WeakTopicsCompanion.insert(
            subject: action.subject,
            topicName: action.topic ?? action.title,
            proficiencyLevel: prof,
            notes: Value(
              'Added via AI Mentor Chat on ${DateTime.now().toIso8601String().substring(0, 10)}',
            ),
          ),
        );
      }

      if (action.type == ChatActionType.addExam) {
        final date = DateTime.tryParse(action.examDate ?? '');
        if (date == null) return false;

        final track = action.effectiveTrackName;

        // Goes through the same deduplicated insert as a PDF import, so an
        // exam the routine already holds is not added twice.
        await _db.insertExamSchedulesDeduplicated([
          ExamSchedulesCompanion.insert(
            examDate: date,
            examTime: Value(action.examTime ?? '10:00 PM'),
            subject: Value(action.subject),
            title: action.title,
            topicsCovered: (action.topic == null || action.topic!.isEmpty)
                ? 'General Syllabus'
                : action.topic!,
            trackName: Value(track),
            resourceSummary: const Value('AI Mentor'),
            rawReference: const Value('ai_mentor'),
          ),
        ]);
      }

      if (action.type == ChatActionType.routinePlan) {
        final itemsToSave = approvedItems ?? action.routineItems;
        if (itemsToSave.isEmpty) return false;

        final result = await RoutineParserService.instance
            .saveParsedRoutinesToDatabase(
              _db,
              itemsToSave,
              overrideTrack: action.trackName,
            );
        if (result.insertedCount == 0 &&
            result.updatedCount == 0 &&
            result.skippedCount == 0) {
          return false;
        }
      }

      if (action.type == ChatActionType.fixExam) {
        if (action.examId == null || action.correctionsJson == null) {
          return false;
        }
        try {
          final decoded = jsonDecode(action.correctionsJson!);
          if (decoded is List) {
            final exam = await (_db.select(
              _db.examSchedules,
            )..where((t) => t.id.equals(action.examId!))).getSingleOrNull();
            if (exam == null || exam.resourceSummary == null) return false;

            final qDecoded = jsonDecode(exam.resourceSummary!);
            if (qDecoded is List) {
              final questions = qDecoded
                  .map((e) => QuizQuestion.fromJson(e as Map<String, dynamic>))
                  .toList();
              final corrections = decoded
                  .whereType<Map<String, dynamic>>()
                  .map((m) => QuestionCorrectionItem.tryFromJson(m, questions))
                  .nonNulls
                  .toList();

              final ok = await QuizBatchCorrectionService.instance
                  .applyCorrectionsToExam(
                    _db,
                    examId: action.examId!,
                    corrections: corrections,
                  );
              if (!ok) return false;
            }
          }
        } catch (e) {
          debugPrint('Error executing fixExam action: $e');
          return false;
        }
      }

      final existingActions = ChatAction.decodeList(message.suggestedAction);
      final updatedActions = existingActions.map((a) {
        if (a.title == action.title &&
            a.subject == action.subject &&
            a.type == action.type) {
          return a.copyWith(isExecuted: true);
        }
        return a;
      }).toList();

      await (_db.update(
        _db.chatMessages,
      )..where((t) => t.id.equals(message.id))).write(
        ChatMessagesCompanion(
          suggestedAction: Value(ChatAction.encodeList(updatedActions)),
        ),
      );

      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> clearCurrentSession() async {
    if (state.currentSessionId != null) {
      await _db.clearSessionMessages(state.currentSessionId!);
    }
  }

  Future<void> clearHistory() async {
    await clearCurrentSession();
  }
}

final chatNotifierProvider = NotifierProvider<ChatNotifier, ChatState>(() {
  return ChatNotifier();
});
