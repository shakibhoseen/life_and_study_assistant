import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Requests, actual tokens, estimated tokens, and cache statistics spent by one kind of call
/// (or one model) today.
class GeminiOperationUsage {
  final int requests;
  final int tokens; // Total tokens (actualTotalTokens + estimatedTokens)
  final int actualInputTokens;
  final int actualOutputTokens;
  final int actualTotalTokens;
  final int estimatedTokens;
  final int cachedTokens;
  final int cacheHits;
  final int failures;

  const GeminiOperationUsage({
    this.requests = 0,
    this.tokens = 0,
    this.actualInputTokens = 0,
    this.actualOutputTokens = 0,
    this.actualTotalTokens = 0,
    this.estimatedTokens = 0,
    this.cachedTokens = 0,
    this.cacheHits = 0,
    this.failures = 0,
  });

  GeminiOperationUsage plus({
    int requests = 0,
    int tokens = 0,
    int actualInputTokens = 0,
    int actualOutputTokens = 0,
    int actualTotalTokens = 0,
    int estimatedTokens = 0,
    int cachedTokens = 0,
    int cacheHits = 0,
    int failures = 0,
  }) => GeminiOperationUsage(
    requests: this.requests + requests,
    tokens: this.tokens + tokens,
    actualInputTokens: this.actualInputTokens + actualInputTokens,
    actualOutputTokens: this.actualOutputTokens + actualOutputTokens,
    actualTotalTokens: this.actualTotalTokens + actualTotalTokens,
    estimatedTokens: this.estimatedTokens + estimatedTokens,
    cachedTokens: this.cachedTokens + cachedTokens,
    cacheHits: this.cacheHits + cacheHits,
    failures: this.failures + failures,
  );

  Map<String, Object?> toJson() => {
    'r': requests,
    't': tokens,
    'ai': actualInputTokens,
    'ao': actualOutputTokens,
    'at': actualTotalTokens,
    'et': estimatedTokens,
    'ct': cachedTokens,
    'ch': cacheHits,
    'f': failures,
  };

  static GeminiOperationUsage fromJson(Object? json) {
    if (json is! Map) return const GeminiOperationUsage();
    return GeminiOperationUsage(
      requests: (json['r'] as num?)?.toInt() ?? 0,
      tokens: (json['t'] as num?)?.toInt() ?? 0,
      actualInputTokens: (json['ai'] as num?)?.toInt() ?? 0,
      actualOutputTokens: (json['ao'] as num?)?.toInt() ?? 0,
      actualTotalTokens: (json['at'] as num?)?.toInt() ?? 0,
      estimatedTokens: (json['et'] as num?)?.toInt() ?? 0,
      cachedTokens: (json['ct'] as num?)?.toInt() ?? 0,
      cacheHits: (json['ch'] as num?)?.toInt() ?? 0,
      failures: (json['f'] as num?)?.toInt() ?? 0,
    );
  }
}

class GeminiUsageStats {
  final int todayRequests;
  final int todayTokens;

  // Granular token accountability
  final int todayActualInputTokens;
  final int todayActualOutputTokens;
  final int todayActualTotalTokens;
  final int todayEstimatedTokens;
  final int todayCachedTokens;
  final int todayCacheHits;
  final int todayFailures;

  /// Daily request budget. Configured by user in settings.
  final int dailyRequestLimit;

  final String lastStatus; // Healthy, QuotaExceeded, Error, Idle
  final DateTime? lastCallTime;

  /// Today's spend broken down by what the call was for ('chat', 'chat+tools',
  /// 'thread_summary', 'study_plan', ...).
  final Map<String, GeminiOperationUsage> byOperation;

  /// Today's spend broken down by model.
  final Map<String, GeminiOperationUsage> byModel;

  const GeminiUsageStats({
    required this.todayRequests,
    required this.todayTokens,
    this.todayActualInputTokens = 0,
    this.todayActualOutputTokens = 0,
    this.todayActualTotalTokens = 0,
    this.todayEstimatedTokens = 0,
    this.todayCachedTokens = 0,
    this.todayCacheHits = 0,
    this.todayFailures = 0,
    this.dailyRequestLimit = GeminiUsageTracker.defaultDailyRequestLimit,
    required this.lastStatus,
    this.lastCallTime,
    this.byOperation = const {},
    this.byModel = const {},
  });

  double get usagePercent => dailyRequestLimit <= 0
      ? 0
      : (todayRequests / dailyRequestLimit).clamp(0.0, 1.0);

  int get remainingRequests =>
      (dailyRequestLimit - todayRequests).clamp(0, dailyRequestLimit);

  /// Average tokens per request today
  int get averageTokensPerRequest =>
      todayRequests == 0 ? 0 : (todayTokens / todayRequests).round();

  /// Operations ordered by tokens spent, heaviest first.
  List<MapEntry<String, GeminiOperationUsage>> get operationsByCost {
    final entries = byOperation.entries.toList()
      ..sort((a, b) => b.value.tokens.compareTo(a.value.tokens));
    return entries;
  }

  /// Transparent cost estimation based on verified Google AI Studio published rates.
  /// Free tier keys (default) incur $0.00 cost.
  /// Pay-as-you-go calculates based on verified actual tokens per model.
  double computeEstimatedCostUsd({bool isFreeTier = true}) {
    if (isFreeTier) return 0.0;
    double cost = 0.0;
    for (final entry in byModel.entries) {
      final model = entry.key.toLowerCase();
      final usage = entry.value;

      // Published standard rates per 1 Million tokens (AI Studio standard tier)
      double inputRatePerMillion = 0.075;
      double outputRatePerMillion = 0.30;
      if (model.contains('pro')) {
        inputRatePerMillion = 1.25;
        outputRatePerMillion = 5.00;
      }

      cost += (usage.actualInputTokens / 1000000.0) * inputRatePerMillion;
      cost += (usage.actualOutputTokens / 1000000.0) * outputRatePerMillion;
    }
    return cost;
  }
}

class GeminiUsageTracker {
  GeminiUsageTracker._();
  static final GeminiUsageTracker instance = GeminiUsageTracker._();

  static const int defaultDailyRequestLimit = 1000;

  static const String _keyDailyRequests = 'gemini_daily_requests';
  static const String _keyDailyTokens = 'gemini_daily_tokens';
  static const String _keyDailyActualInputTokens =
      'gemini_daily_actual_input_tokens';
  static const String _keyDailyActualOutputTokens =
      'gemini_daily_actual_output_tokens';
  static const String _keyDailyActualTotalTokens =
      'gemini_daily_actual_total_tokens';
  static const String _keyDailyEstimatedTokens =
      'gemini_daily_estimated_tokens';
  static const String _keyDailyCachedTokens = 'gemini_daily_cached_tokens';
  static const String _keyDailyCacheHits = 'gemini_daily_cache_hits';
  static const String _keyDailyFailures = 'gemini_daily_failures';

  static const String _keyLastDate = 'gemini_last_request_date';
  static const String _keyLastTimestamp = 'gemini_last_request_timestamp';
  static const String _keyLastStatus = 'gemini_last_status';
  static const String _keyByOperation = 'gemini_daily_by_operation';
  static const String _keyByModel = 'gemini_daily_by_model';
  static const String _keyDailyLimit = 'gemini_daily_request_limit';

  final StreamController<GeminiUsageStats> _statsController =
      StreamController<GeminiUsageStats>.broadcast();
  Stream<GeminiUsageStats> get statsStream => _statsController.stream;

  static String _todayKey() =>
      DateTime.now().toIso8601String().substring(0, 10);

  /// Clears the day's counters when the date has rolled over.
  Future<void> _rolloverIfNeeded(SharedPreferences prefs) async {
    final today = _todayKey();
    if (prefs.getString(_keyLastDate) == today) return;

    await prefs.setInt(_keyDailyRequests, 0);
    await prefs.setInt(_keyDailyTokens, 0);
    await prefs.setInt(_keyDailyActualInputTokens, 0);
    await prefs.setInt(_keyDailyActualOutputTokens, 0);
    await prefs.setInt(_keyDailyActualTotalTokens, 0);
    await prefs.setInt(_keyDailyEstimatedTokens, 0);
    await prefs.setInt(_keyDailyCachedTokens, 0);
    await prefs.setInt(_keyDailyCacheHits, 0);
    await prefs.setInt(_keyDailyFailures, 0);

    await prefs.remove(_keyByOperation);
    await prefs.remove(_keyByModel);
    await prefs.setString(_keyLastDate, today);
  }

  static Map<String, GeminiOperationUsage> _readBreakdown(
    SharedPreferences prefs,
    String key,
  ) {
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return decoded.map(
        (k, v) => MapEntry(k.toString(), GeminiOperationUsage.fromJson(v)),
      );
    } catch (_) {
      return const {};
    }
  }

  static Future<void> _writeBreakdown(
    SharedPreferences prefs,
    String key,
    Map<String, GeminiOperationUsage> value,
  ) async {
    await prefs.setString(
      key,
      jsonEncode(value.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  Future<GeminiUsageStats> getStats() async {
    final prefs = await SharedPreferences.getInstance();
    await _rolloverIfNeeded(prefs);
    return _buildStats(prefs);
  }

  GeminiUsageStats _buildStats(
    SharedPreferences prefs, {
    String? statusOverride,
  }) {
    final timestampMillis = prefs.getInt(_keyLastTimestamp);
    return GeminiUsageStats(
      todayRequests: prefs.getInt(_keyDailyRequests) ?? 0,
      todayTokens: prefs.getInt(_keyDailyTokens) ?? 0,
      todayActualInputTokens: prefs.getInt(_keyDailyActualInputTokens) ?? 0,
      todayActualOutputTokens: prefs.getInt(_keyDailyActualOutputTokens) ?? 0,
      todayActualTotalTokens: prefs.getInt(_keyDailyActualTotalTokens) ?? 0,
      todayEstimatedTokens: prefs.getInt(_keyDailyEstimatedTokens) ?? 0,
      todayCachedTokens: prefs.getInt(_keyDailyCachedTokens) ?? 0,
      todayCacheHits: prefs.getInt(_keyDailyCacheHits) ?? 0,
      todayFailures: prefs.getInt(_keyDailyFailures) ?? 0,
      dailyRequestLimit:
          prefs.getInt(_keyDailyLimit) ?? defaultDailyRequestLimit,
      lastStatus:
          statusOverride ?? prefs.getString(_keyLastStatus) ?? 'Healthy',
      lastCallTime: timestampMillis != null
          ? DateTime.fromMillisecondsSinceEpoch(timestampMillis)
          : null,
      byOperation: _readBreakdown(prefs, _keyByOperation),
      byModel: _readBreakdown(prefs, _keyByModel),
    );
  }

  /// Sets the daily request budget shown in the usage monitor.
  Future<void> setDailyRequestLimit(int limit) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyDailyLimit, limit.clamp(1, 1000000));
    _statsController.add(_buildStats(prefs));
  }

  /// Records one successful API call with precise token accounting.
  ///
  /// Distinguishes actual tokens reported by the SDK UsageMetadata from
  /// estimated tokens. Never labels estimated tokens as actual.
  Future<void> recordSuccess({
    int tokens = 0,
    int? actualInputTokens,
    int? actualOutputTokens,
    int? actualTotalTokens,
    int? cachedTokens,
    bool isEstimated = false,
    String operation = 'general',
    String? model,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await _rolloverIfNeeded(prefs);

    final inputTokens = actualInputTokens ?? 0;
    final outputTokens = actualOutputTokens ?? 0;
    final bool hasActual = actualTotalTokens != null && actualTotalTokens > 0;
    final int resolvedActualTotal = hasActual ? actualTotalTokens : 0;
    final int resolvedEstimated = (isEstimated || !hasActual) ? tokens : 0;
    final int totalTokensToAdd = (resolvedActualTotal > 0)
        ? resolvedActualTotal
        : (tokens > 0 ? tokens : resolvedEstimated);

    final requests = (prefs.getInt(_keyDailyRequests) ?? 0) + 1;
    final totalTokens = (prefs.getInt(_keyDailyTokens) ?? 0) + totalTokensToAdd;
    final currentInput =
        (prefs.getInt(_keyDailyActualInputTokens) ?? 0) + inputTokens;
    final currentOutput =
        (prefs.getInt(_keyDailyActualOutputTokens) ?? 0) + outputTokens;
    final currentActualTotal =
        (prefs.getInt(_keyDailyActualTotalTokens) ?? 0) + resolvedActualTotal;
    final currentEstimated =
        (prefs.getInt(_keyDailyEstimatedTokens) ?? 0) + resolvedEstimated;
    final currentCachedTokens =
        (prefs.getInt(_keyDailyCachedTokens) ?? 0) + (cachedTokens ?? 0);

    await prefs.setInt(_keyDailyRequests, requests);
    await prefs.setInt(_keyDailyTokens, totalTokens);
    await prefs.setInt(_keyDailyActualInputTokens, currentInput);
    await prefs.setInt(_keyDailyActualOutputTokens, currentOutput);
    await prefs.setInt(_keyDailyActualTotalTokens, currentActualTotal);
    await prefs.setInt(_keyDailyEstimatedTokens, currentEstimated);
    await prefs.setInt(_keyDailyCachedTokens, currentCachedTokens);
    await prefs.setString(_keyLastStatus, 'Healthy');
    await prefs.setInt(
      _keyLastTimestamp,
      DateTime.now().millisecondsSinceEpoch,
    );

    final byOperation = Map<String, GeminiOperationUsage>.from(
      _readBreakdown(prefs, _keyByOperation),
    );
    byOperation[operation] =
        (byOperation[operation] ?? const GeminiOperationUsage()).plus(
          requests: 1,
          tokens: totalTokensToAdd,
          actualInputTokens: inputTokens,
          actualOutputTokens: outputTokens,
          actualTotalTokens: resolvedActualTotal,
          estimatedTokens: resolvedEstimated,
          cachedTokens: cachedTokens ?? 0,
        );
    await _writeBreakdown(prefs, _keyByOperation, byOperation);

    if (model != null && model.isNotEmpty) {
      final byModel = Map<String, GeminiOperationUsage>.from(
        _readBreakdown(prefs, _keyByModel),
      );
      byModel[model] = (byModel[model] ?? const GeminiOperationUsage()).plus(
        requests: 1,
        tokens: totalTokensToAdd,
        actualInputTokens: inputTokens,
        actualOutputTokens: outputTokens,
        actualTotalTokens: resolvedActualTotal,
        estimatedTokens: resolvedEstimated,
        cachedTokens: cachedTokens ?? 0,
      );
      await _writeBreakdown(prefs, _keyByModel, byModel);
    }

    _statsController.add(_buildStats(prefs));
    debugPrint(
      'Gemini usage: $operation #$requests today, +$totalTokensToAdd tokens '
      '(actual: $resolvedActualTotal, est: $resolvedEstimated, total: $totalTokens)',
    );
  }

  /// Records a cache hit where no network call was made.
  Future<void> recordCacheHit({
    String operation = 'general',
    String? model,
    int savedTokens = 0,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await _rolloverIfNeeded(prefs);

    final currentHits = (prefs.getInt(_keyDailyCacheHits) ?? 0) + 1;
    await prefs.setInt(_keyDailyCacheHits, currentHits);

    final byOperation = Map<String, GeminiOperationUsage>.from(
      _readBreakdown(prefs, _keyByOperation),
    );
    byOperation[operation] =
        (byOperation[operation] ?? const GeminiOperationUsage()).plus(
          cacheHits: 1,
        );
    await _writeBreakdown(prefs, _keyByOperation, byOperation);

    if (model != null && model.isNotEmpty) {
      final byModel = Map<String, GeminiOperationUsage>.from(
        _readBreakdown(prefs, _keyByModel),
      );
      byModel[model] = (byModel[model] ?? const GeminiOperationUsage()).plus(
        cacheHits: 1,
      );
      await _writeBreakdown(prefs, _keyByModel, byModel);
    }

    _statsController.add(_buildStats(prefs));
    debugPrint('Gemini cache hit: $operation (hit #$currentHits today)');
  }

  /// Records a call failure or error.
  Future<void> recordFailure({
    String operation = 'general',
    String? model,
    String? error,
    bool isQuota = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await _rolloverIfNeeded(prefs);

    final currentFailures = (prefs.getInt(_keyDailyFailures) ?? 0) + 1;
    await prefs.setInt(_keyDailyFailures, currentFailures);
    await prefs.setString(_keyLastStatus, isQuota ? 'QuotaExceeded' : 'Error');
    await prefs.setInt(
      _keyLastTimestamp,
      DateTime.now().millisecondsSinceEpoch,
    );

    final byOperation = Map<String, GeminiOperationUsage>.from(
      _readBreakdown(prefs, _keyByOperation),
    );
    byOperation[operation] =
        (byOperation[operation] ?? const GeminiOperationUsage()).plus(
          failures: 1,
        );
    await _writeBreakdown(prefs, _keyByOperation, byOperation);

    if (model != null && model.isNotEmpty) {
      final byModel = Map<String, GeminiOperationUsage>.from(
        _readBreakdown(prefs, _keyByModel),
      );
      byModel[model] = (byModel[model] ?? const GeminiOperationUsage()).plus(
        failures: 1,
      );
      await _writeBreakdown(prefs, _keyByModel, byModel);
    }

    _statsController.add(_buildStats(prefs));
    debugPrint('Gemini failure recorded for $operation: $error');
  }

  Future<void> recordQuotaExceeded({
    String operation = 'general',
    String? model,
  }) async {
    await recordFailure(
      operation: operation,
      model: model,
      error: 'Quota exceeded',
      isQuota: true,
    );
  }

  Future<void> recordError(
    String error, {
    String operation = 'general',
    String? model,
  }) async {
    await recordFailure(
      operation: operation,
      model: model,
      error: error,
      isQuota: false,
    );
  }
}
