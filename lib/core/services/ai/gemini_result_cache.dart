import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Content-hash-based cache for idempotent Gemini AI operations.
///
/// Prevents redundant token consumption when processing identical documents,
/// study sheets, routine text/images, mistake explanations, or exam cheat-sheets.
///
/// Cache key identity includes:
/// - Operation type (e.g. 'sheet_summary', 'mistake_explain', 'exam_cheat_sheet')
/// - Prompt version (e.g. 'v1.0') - changing this invalidates obsolete caches
/// - Model identifier (e.g. 'gemini-flash-lite-latest')
/// - SHA-256 hash of the input payload (text or bytes)
class GeminiResultCache {
  GeminiResultCache._();
  static final GeminiResultCache instance = GeminiResultCache._();

  static const String _prefPrefix = 'gemini_cache_';
  static const String _prefIndexKey = 'gemini_cache_index';

  // In-memory L1 cache for fast synchronous checks
  final Map<String, ({String data, DateTime createdAt})> _memoryCache = {};

  // Maximum items in memory cache to avoid memory pressure
  static const int maxMemoryEntries = 100;

  /// Default time-to-live: 7 days
  static const Duration defaultTtl = Duration(days: 7);

  /// Computes deterministic SHA-256 cache key
  String computeKey({
    required String operation,
    required String promptVersion,
    required String model,
    required List<int> payloadBytes,
  }) {
    final payloadHash = sha256.convert(payloadBytes).toString();
    final combined = '$operation:$promptVersion:$model:$payloadHash';
    return sha256.convert(utf8.encode(combined)).toString();
  }

  /// Helper to compute key from string payload
  String computeKeyFromString({
    required String operation,
    required String promptVersion,
    required String model,
    required String payloadText,
  }) {
    return computeKey(
      operation: operation,
      promptVersion: promptVersion,
      model: model,
      payloadBytes: utf8.encode(payloadText),
    );
  }

  /// Retrieves a cached response if available and not expired.
  /// Returns null on cache miss or expiration.
  Future<String?> get(String key, {Duration ttl = defaultTtl}) async {
    final now = DateTime.now();

    // 1. Check L1 Memory Cache
    final memHit = _memoryCache[key];
    if (memHit != null) {
      if (now.difference(memHit.createdAt) <= ttl) {
        debugPrint('GeminiResultCache: L1 memory hit for $key');
        return memHit.data;
      } else {
        _memoryCache.remove(key);
      }
    }

    // 2. Check L2 SharedPreferences Persistent Cache
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefPrefix$key');
      if (raw == null || raw.isEmpty) return null;

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;

      final createdMillis = (decoded['created'] as num?)?.toInt() ?? 0;
      final createdAt = DateTime.fromMillisecondsSinceEpoch(createdMillis);
      if (now.difference(createdAt) > ttl) {
        // Expired
        await prefs.remove('$_prefPrefix$key');
        return null;
      }

      final data = decoded['data'] as String?;
      if (data != null) {
        _putInMemory(key, data, createdAt);
        debugPrint('GeminiResultCache: L2 disk hit for $key');
        return data;
      }
    } catch (e) {
      debugPrint('GeminiResultCache read error: $e');
    }

    return null;
  }

  /// Stores a response in both memory and persistent cache.
  Future<void> put(String key, String data) async {
    final now = DateTime.now();
    _putInMemory(key, data, now);

    try {
      final prefs = await SharedPreferences.getInstance();
      final record = jsonEncode({
        'created': now.millisecondsSinceEpoch,
        'data': data,
      });
      await prefs.setString('$_prefPrefix$key', record);

      // Maintain persistent index for bulk invalidation
      final index = prefs.getStringList(_prefIndexKey) ?? [];
      if (!index.contains(key)) {
        index.add(key);
        // Keep index bounded
        if (index.length > 200) {
          final oldestKey = index.removeAt(0);
          await prefs.remove('$_prefPrefix$oldestKey');
        }
        await prefs.setStringList(_prefIndexKey, index);
      }
    } catch (e) {
      debugPrint('GeminiResultCache write error: $e');
    }
  }

  void _putInMemory(String key, String data, DateTime createdAt) {
    if (_memoryCache.length >= maxMemoryEntries) {
      _memoryCache.remove(_memoryCache.keys.first);
    }
    _memoryCache[key] = (data: data, createdAt: createdAt);
  }

  /// Clears all cached items
  Future<void> clear() async {
    _memoryCache.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      final index = prefs.getStringList(_prefIndexKey) ?? [];
      for (final key in index) {
        await prefs.remove('$_prefPrefix$key');
      }
      await prefs.remove(_prefIndexKey);
    } catch (e) {
      debugPrint('GeminiResultCache clear error: $e');
    }
  }

  @visibleForTesting
  int get memoryCacheSize => _memoryCache.length;
}
