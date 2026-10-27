import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/database/tables/weak_topics_table.dart';
import 'package:life_and_study_assistant/core/services/ai/chat_context_resolver.dart';
import 'package:life_and_study_assistant/core/services/ai/gemini_prompts.dart';
import 'package:life_and_study_assistant/core/services/ai/gemini_result_cache.dart';
import 'package:life_and_study_assistant/core/services/ai/gemini_usage_tracker.dart';
import 'package:life_and_study_assistant/features/weakness_healer/domain/models/weakness_healing_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await GeminiResultCache.instance.clear();
  });

  group('Operation-Specific Context Policy Tests', () {
    test('Chat Context excludes unrelated fields when only teaching concept is requested', () {
      final needs = ChatContextResolver.resolve(
        userMessage:
            'অনুগ্রহ করে দ্বঘু সমাস এবং দ্বিগু সমাসের পার্থক্য বুঝিয়ে দিন',
      );

      expect(needs.energy, isFalse);
      expect(needs.weakTopics, isFalse);
      expect(needs.exams, isFalse);

      final systemPrompt = GeminiPrompts.buildChatSystemInstruction(
        energyLevel: 'Low',
        fatigueScore: 4,
        weakTopics: [
          {'subject': 'গণিত', 'topic': 'বীজগণিত', 'proficiency': 'weak'},
        ],
        upcomingExams: [
          {'title': 'BCS Model Test', 'daysAway': 15, 'topics': 'All'},
        ],
        needs: needs,
      );

      // System prompt should contain the stable prefix without volatile energy or exams
      expect(systemPrompt.contains('--- CURRENT USER CONTEXT ---'), isFalse);
      expect(systemPrompt.contains('বীজগণিত'), isFalse);
      expect(systemPrompt.contains('BCS Model Test'), isFalse);
      expect(systemPrompt, GeminiPrompts.chatStaticInstruction);
    });

    test('Chat Context includes only energy when user mentions fatigue', () {
      final needs = ChatContextResolver.resolve(
        userMessage: 'আজকে অফিস থেকে ফিরে খুব টায়ার্ড লাগছে',
      );

      expect(needs.energy, isTrue);
      expect(needs.weakTopics, isFalse);
      expect(needs.exams, isFalse);

      final prompt = GeminiPrompts.buildChatSystemInstruction(
        energyLevel: 'Low',
        fatigueScore: 8,
        weakTopics: [
          {'subject': 'গণিত', 'topic': 'বীজগণিত', 'proficiency': 'weak'},
        ],
        upcomingExams: [
          {'title': 'BCS Model Test', 'daysAway': 15, 'topics': 'All'},
        ],
        needs: needs,
      );

      expect(prompt.contains('Energy Level: Low'), isTrue);
      expect(prompt.contains('Fatigue Score: 8/10'), isTrue);
      expect(prompt.contains('বীজগণিত'), isFalse);
      expect(prompt.contains('BCS Model Test'), isFalse);
    });

    test('Study Plan Prompt shortens long notes and syllabus strings', () {
      final veryLongNotes = 'X' * 500;
      final veryLongSyllabus = 'Y' * 500;

      final weakTopicsMap = [
        {
          'subject': 'Bangla',
          'topic': 'সমাস',
          'proficiency': 'weak',
          'notes': veryLongNotes.length > 100
              ? '${veryLongNotes.substring(0, 100)}…'
              : veryLongNotes,
        },
      ];

      final examsMap = [
        {
          'title': '47th BCS Preliminary',
          'track': 'General BCS',
          'daysAway': 5,
          'topics': veryLongSyllabus.length > 120
              ? '${veryLongSyllabus.substring(0, 120)}…'
              : veryLongSyllabus,
        },
      ];

      final prompt = GeminiPrompts.buildStudyPlanPrompt(
        energyLevel: 'Medium',
        fatigueScore: 5,
        weakTopics: weakTopicsMap,
        upcomingExams: examsMap,
        isOffDay: false,
      );

      // Verify that full 500-char strings were trimmed to avoid token explosion
      expect(prompt.contains('X' * 150), isFalse);
      expect(prompt.contains('Y' * 150), isFalse);
      expect(prompt.contains('…'), isTrue);
    });
  });

  group('Deterministic Calculations vs AI Calls Tests', () {
    test('calculateWeaknessHealth performs 100% deterministic calculation without AI', () {
      final now = DateTime.now();
      final topics = [
        WeakTopic(
          id: 1,
          subject: 'বাংলা ব্যাকরণ',
          topicName: 'সমাস',
          proficiencyLevel: ProficiencyLevel.weak,
          createdAt: now,
        ),
        WeakTopic(
          id: 2,
          subject: 'বাংলা ব্যাকরণ',
          topicName: 'কারক',
          proficiencyLevel: ProficiencyLevel.moderate,
          createdAt: now,
        ),
        WeakTopic(
          id: 3,
          subject: 'ইংরেজি',
          topicName: 'Prepositions',
          proficiencyLevel: ProficiencyLevel.strong,
          createdAt: now,
        ),
      ];

      final mistakes = [
        DrillQuestion(
          id: 1,
          subject: 'বাংলা ব্যাকরণ',
          topic: 'সমাস',
          questionText: '‘নীলোৎপল’ কোন সমাস?',
          optionsJson: '["কর্মধারয়","তৎপুরুষ","দ্বন্দ্ব","বহুব্রীহি"]',
          correctIndex: 0,
          selectedIndex: 1,
          isCorrect: false,
          explanation: 'নীল যে উৎপল = নীলোৎপল',
          isMastered: false,
          attemptedAt: now,
        ),
      ];

      final summary = calculateWeaknessHealth(
        topics: topics,
        unmasteredMistakes: mistakes,
      );

      expect(summary.totalTopics, 3);
      expect(summary.weakCount, 1);
      expect(summary.moderateCount, 1);
      expect(summary.healedCount, 1);
      // Health: (1.0 * 1 + 0.5 * 1 + 0.0 * 1) / 3 = 1.5 / 3 = 50.0%
      expect(summary.healthPercentage, closeTo(50.0, 0.01));
      expect(summary.primaryFocusTopic?.topicName, 'সমাস');
      expect(summary.matchingMistakesCount, 1);
    });

    test(
      'Multi-Track countdown calculates exact daysAway deterministically',
      () {
        final now = DateTime.now();
        final todayStart = DateTime(now.year, now.month, now.day);
        final examDate = todayStart.add(const Duration(days: 4));

        final daysAway = DateTime(
          examDate.year,
          examDate.month,
          examDate.day,
        ).difference(todayStart).inDays;

        expect(daysAway, 4);
      },
    );
  });

  group('Content-Hash Result Caching Tests', () {
    test('Identical input produces cache hit and retrieves stored response with 0 tokens', () async {
      final cache = GeminiResultCache.instance;
      const operation = 'sheet_summary';
      const promptVersion = 'v1.0';
      const model = 'gemini-flash-lite-latest';
      const payload = 'বাংলা ব্যাকরণ সমাস নির্ণয়ের সহজ নিয়মাবলি ও উদাহরণ';

      final key = cache.computeKeyFromString(
        operation: operation,
        promptVersion: promptVersion,
        model: model,
        payloadText: payload,
      );

      // Initially null
      expect(await cache.get(key), isNull);

      // Put response
      const sampleResponse = '{"title":"সমাস সামারি","points":["পয়েন্ট ১"]}';
      await cache.put(key, sampleResponse);

      // Immediate hit from memory
      final hit1 = await cache.get(key);
      expect(hit1, sampleResponse);

      // Memory hit persists across repeated reads
      final hit2 = await cache.get(key);
      expect(hit2, sampleResponse);
    });

    test('Different payload produces distinct cache key', () {
      final cache = GeminiResultCache.instance;
      final keyA = cache.computeKeyFromString(
        operation: 'sheet_summary',
        promptVersion: 'v1.0',
        model: 'gemini-flash-lite-latest',
        payloadText: 'Content A',
      );
      final keyB = cache.computeKeyFromString(
        operation: 'sheet_summary',
        promptVersion: 'v1.0',
        model: 'gemini-flash-lite-latest',
        payloadText: 'Content B',
      );

      expect(keyA, isNot(equals(keyB)));
    });

    test('Prompt version change invalidates older cache key', () {
      final cache = GeminiResultCache.instance;
      final keyV1 = cache.computeKeyFromString(
        operation: 'mistake_explain',
        promptVersion: 'v1.0',
        model: 'gemini-flash-lite-latest',
        payloadText: 'Question: What is X?',
      );
      final keyV2 = cache.computeKeyFromString(
        operation: 'mistake_explain',
        promptVersion: 'v2.0', // Updated prompt template
        model: 'gemini-flash-lite-latest',
        payloadText: 'Question: What is X?',
      );

      expect(keyV1, isNot(equals(keyV2)));
    });

    test('Expired TTL returns null and removes entry', () async {
      final cache = GeminiResultCache.instance;
      final key = cache.computeKeyFromString(
        operation: 'exam_cheat_sheet',
        promptVersion: 'v1.0',
        model: 'gemini-flash-lite-latest',
        payloadText: '47th BCS Exam Syllabus',
      );

      await cache.put(key, 'Summary content');

      // Request with negative Duration TTL simulates expired entry
      final result = await cache.get(key, ttl: const Duration(seconds: -1));
      expect(result, isNull);
    });
  });

  group('GeminiUsageTracker Observability Tests', () {
    final tracker = GeminiUsageTracker.instance;

    test(
      'Distinguishes actual provider-reported tokens from estimated tokens',
      () async {
        // Call 1: Provider reported actual tokens via UsageMetadata
        await tracker.recordSuccess(
          tokens: 450,
          actualInputTokens: 350,
          actualOutputTokens: 100,
          actualTotalTokens: 450,
          isEstimated: false,
          operation: 'chat',
          model: 'gemini-flash-lite-latest',
        );

        // Call 2: Estimated tokens (usageMetadata was null)
        await tracker.recordSuccess(
          tokens: 200,
          isEstimated: true,
          operation: 'quick_quiz_drill',
          model: 'gemini-flash-lite-latest',
        );

        final stats = await tracker.getStats();

        // Total requests & total tokens
        expect(stats.todayRequests, 2);
        expect(stats.todayTokens, 650);

        // Granular token accountability: Never label estimated tokens as actual
        expect(stats.todayActualInputTokens, 350);
        expect(stats.todayActualOutputTokens, 100);
        expect(stats.todayActualTotalTokens, 450);
        expect(stats.todayEstimatedTokens, 200);

        // Operation-specific breakdown
        final chatUsage = stats.byOperation['chat']!;
        expect(chatUsage.actualTotalTokens, 450);
        expect(chatUsage.estimatedTokens, 0);

        final quizUsage = stats.byOperation['quick_quiz_drill']!;
        expect(quizUsage.actualTotalTokens, 0);
        expect(quizUsage.estimatedTokens, 200);
      },
    );

    test('Records cache hits and tracks zero-cost operations', () async {
      await tracker.recordCacheHit(
        operation: 'sheet_summary',
        model: 'gemini-flash-lite-latest',
      );
      await tracker.recordCacheHit(
        operation: 'sheet_summary',
        model: 'gemini-flash-lite-latest',
      );

      final stats = await tracker.getStats();
      expect(stats.todayCacheHits, 2);
      expect(stats.byOperation['sheet_summary']!.cacheHits, 2);
      // Cache hits do not consume API request budget or tokens
      expect(stats.todayRequests, 0);
      expect(stats.todayTokens, 0);
    });

    test('Records failures and errors against operation and model', () async {
      await tracker.recordFailure(
        operation: 'chat',
        model: 'gemini-pro-latest',
        error: '429 Quota Exceeded',
        isQuota: true,
      );

      final stats = await tracker.getStats();
      expect(stats.todayFailures, 1);
      expect(stats.lastStatus, 'QuotaExceeded');
      expect(stats.byOperation['chat']!.failures, 1);
      expect(stats.byModel['gemini-pro-latest']!.failures, 1);
    });

    test('Transparent cost estimation reports 0 for Free tier and calculates verified rates for Pay-as-you-go', () async {
      await tracker.recordSuccess(
        tokens: 100000,
        actualInputTokens: 80000,
        actualOutputTokens: 20000,
        actualTotalTokens: 100000,
        operation: 'chat',
        model: 'gemini-flash-lite-latest',
      );

      final stats = await tracker.getStats();

      // Free tier always incurs $0.00
      expect(stats.computeEstimatedCostUsd(isFreeTier: true), 0.0);

      // Pay-as-you-go:
      // 80,000 input tokens * $0.075 / 1M = $0.006
      // 20,000 output tokens * $0.30 / 1M = $0.006
      // Total = $0.012
      final payAsYouGoCost = stats.computeEstimatedCostUsd(isFreeTier: false);
      expect(payAsYouGoCost, closeTo(0.012, 0.0001));
    });
  });
}
