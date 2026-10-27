import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:life_and_study_assistant/core/services/ai/gemini_usage_tracker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final tracker = GeminiUsageTracker.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Per-Operation Breakdown Tests', () {
    test('records requests and tokens against the operation label', () async {
      await tracker.recordSuccess(
        tokens: 1200,
        operation: 'chat',
        model: 'flash-lite',
      );
      await tracker.recordSuccess(
        tokens: 800,
        operation: 'chat',
        model: 'flash-lite',
      );
      await tracker.recordSuccess(
        tokens: 300,
        operation: 'thread_summary',
        model: 'flash-lite',
      );

      final stats = await tracker.getStats();

      expect(stats.todayRequests, 3);
      expect(stats.todayTokens, 2300);
      expect(stats.byOperation['chat']!.requests, 2);
      expect(stats.byOperation['chat']!.tokens, 2000);
      expect(stats.byOperation['thread_summary']!.tokens, 300);
    });

    test('separates tool-assisted chat from plain chat', () async {
      await tracker.recordSuccess(tokens: 1000, operation: 'chat');
      await tracker.recordSuccess(tokens: 2500, operation: 'chat+tools');

      final stats = await tracker.getStats();

      // The whole point: you can see how often the router had to be rescued.
      expect(stats.byOperation['chat']!.requests, 1);
      expect(stats.byOperation['chat+tools']!.requests, 1);
    });

    test('tracks models separately from operations', () async {
      await tracker.recordSuccess(
        tokens: 500,
        operation: 'chat',
        model: 'gemini-pro-latest',
      );
      await tracker.recordSuccess(
        tokens: 100,
        operation: 'thread_summary',
        model: 'gemini-flash-lite-latest',
      );

      final stats = await tracker.getStats();

      expect(stats.byModel['gemini-pro-latest']!.tokens, 500);
      expect(stats.byModel['gemini-flash-lite-latest']!.tokens, 100);
    });

    test('operationsByCost ranks the heaviest spender first', () async {
      await tracker.recordSuccess(tokens: 100, operation: 'quick_quiz_drill');
      await tracker.recordSuccess(tokens: 5000, operation: 'chat');
      await tracker.recordSuccess(tokens: 900, operation: 'study_plan');

      final stats = await tracker.getStats();

      expect(stats.operationsByCost.first.key, 'chat');
      expect(stats.operationsByCost.last.key, 'quick_quiz_drill');
    });

    test(
      'average tokens per call is the number worth tuning against',
      () async {
        await tracker.recordSuccess(tokens: 1000, operation: 'chat');
        await tracker.recordSuccess(tokens: 2000, operation: 'chat');

        final stats = await tracker.getStats();
        expect(stats.averageTokensPerRequest, 1500);
      },
    );

    test('an empty day reports zero rather than dividing by zero', () async {
      final stats = await tracker.getStats();
      expect(stats.averageTokensPerRequest, 0);
      expect(stats.usagePercent, 0);
    });
  });

  group('Daily Budget Tests', () {
    test('the budget is configurable, not baked in', () async {
      await tracker.setDailyRequestLimit(250);
      for (var i = 0; i < 50; i++) {
        await tracker.recordSuccess(tokens: 10, operation: 'chat');
      }

      final stats = await tracker.getStats();
      expect(stats.dailyRequestLimit, 250);
      expect(stats.remainingRequests, 200);
      expect(stats.usagePercent, closeTo(0.2, 0.001));
    });

    test('usage never reports beyond 100%', () async {
      await tracker.setDailyRequestLimit(2);
      for (var i = 0; i < 5; i++) {
        await tracker.recordSuccess(tokens: 10, operation: 'chat');
      }

      final stats = await tracker.getStats();
      expect(stats.usagePercent, 1.0);
      expect(stats.remainingRequests, 0);
    });
  });

  group('Daily Rollover Tests', () {
    test('a new day clears counters and the breakdown', () async {
      final yesterday = DateTime.now()
          .subtract(const Duration(days: 1))
          .toIso8601String()
          .substring(0, 10);

      SharedPreferences.setMockInitialValues({
        'gemini_last_request_date': yesterday,
        'gemini_daily_requests': 42,
        'gemini_daily_tokens': 99999,
        'gemini_daily_by_operation': jsonEncode({
          'chat': {'r': 42, 't': 99999},
        }),
      });

      final stats = await tracker.getStats();

      expect(stats.todayRequests, 0);
      expect(stats.todayTokens, 0);
      expect(stats.byOperation, isEmpty);
    });

    test('same-day stats survive a read', () async {
      await tracker.recordSuccess(tokens: 700, operation: 'chat');

      await tracker.getStats();
      final stats = await tracker.getStats();

      expect(stats.todayRequests, 1);
      expect(stats.byOperation['chat']!.tokens, 700);
    });
  });

  group('Failure Status Tests', () {
    test('a quota failure is visible and does not wipe the day', () async {
      await tracker.recordSuccess(tokens: 500, operation: 'chat');
      await tracker.recordQuotaExceeded();

      final stats = await tracker.getStats();
      expect(stats.lastStatus, 'QuotaExceeded');
      expect(stats.todayRequests, 1);
    });

    test('an error status is recorded', () async {
      await tracker.recordError('SocketException: failed host lookup');

      final stats = await tracker.getStats();
      expect(stats.lastStatus, 'Error');
    });
  });
}
