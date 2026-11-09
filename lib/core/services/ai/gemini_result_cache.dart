import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One thing the cache is holding, as a person could read it.
///
/// The keys are hashes, so a list of them tells nobody anything. The operation
/// and the date are carried alongside so the list can be looked at and judged.
@immutable
class CachedEntry {
  const CachedEntry({
    required this.key,
    required this.operation,
    required this.label,
    required this.createdAt,
    required this.sizeBytes,
  });

  final String key;

  /// What produced it — 'question_bank_ocr', 'study_sheet_ocr', and so on.
  final String operation;

  /// What it was about, where the caller said: a page title, a subject. Empty
  /// for the calls that do not know.
  final String label;

  final DateTime createdAt;

  /// What the stored reply occupies on disk.
  final int sizeBytes;

  Map<String, dynamic> toJson() => {
    'k': key,
    'o': operation,
    'l': label,
    'c': createdAt.millisecondsSinceEpoch,
    's': sizeBytes,
  };

  static CachedEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final key = raw['k']?.toString();
    if (key == null || key.isEmpty) return null;
    return CachedEntry(
      key: key,
      operation: raw['o']?.toString() ?? GeminiResultCache.operationOf(key),
      label: raw['l']?.toString() ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (raw['c'] as num?)?.toInt() ?? 0,
      ),
      sizeBytes: (raw['s'] as num?)?.toInt() ?? 0,
    );
  }
}

/// How much the cache is holding in all.
@immutable
class CacheStats {
  const CacheStats({required this.entries, required this.bytes});

  final int entries;
  final int bytes;

  bool get isEmpty => entries == 0;
}

/// Content-hash-based cache for idempotent Gemini AI operations.
///
/// Prevents redundant token consumption when processing identical documents,
/// study sheets, routine text/images, mistake explanations, or exam
/// cheat-sheets.
///
/// Cache key identity includes:
/// - Operation type (e.g. 'sheet_summary', 'mistake_explain')
/// - Prompt version (e.g. 'v1.0') — changing this invalidates obsolete caches
/// - Model identifier (e.g. 'gemini-flash-lite-latest')
/// - SHA-256 hash of the input payload (text or bytes)
///
/// The operation also survives into the key in plain sight, before the hash,
/// so the stored entries can be listed and understood.
///
/// **Where the replies live.** On disk, one file each, under the app's support
/// directory. They used to sit in SharedPreferences: a question-bank page's
/// reply is several kilobytes of JSON and two hundred of them made a
/// multi-megabyte XML file that Android reads into memory in full at every
/// launch, for a cache almost none of which is wanted on any given run.
/// SharedPreferences now holds only the index — key, operation, label, date
/// and size — which is small, and is also what makes listing the cache cheap.
class GeminiResultCache {
  GeminiResultCache._();
  static final GeminiResultCache instance = GeminiResultCache._();

  /// The index lives in the cache folder beside the replies, not in the
  /// preferences.
  ///
  /// It is small — a couple of hundred entries of key, label, date and size —
  /// but the preferences file is read into memory in full at every launch, and
  /// a cache has no business being in it at all. With the index here too, the
  /// whole cache is one directory: delete it and nothing of it remains, which
  /// is also what makes it easy to reason about.
  static const String _indexFileName = 'index.json';

  /// The prefix the replies themselves used to be stored under, kept only so
  /// the space they took can be given back. See [_sweepLegacyEntries].
  static const String _legacyPrefix = 'gemini_cache_';
  static const String _legacyIndexKey = 'gemini_cache_index';
  static const String _legacySweptKey = 'gemini_cache_legacy_swept';

  static const String _dirName = 'ai_cache';

  // In-memory L1 cache for fast synchronous checks
  final Map<String, ({String data, DateTime createdAt})> _memoryCache = {};

  // Maximum items in memory cache to avoid memory pressure
  static const int maxMemoryEntries = 100;

  /// Maximum entries kept on disk.
  static const int maxStoredEntries = 200;

  /// Default time-to-live: 7 days
  static const Duration defaultTtl = Duration(days: 7);

  /// Where the reply files go. Replaceable so the cache can be tested without
  /// a platform channel.
  Future<Directory> Function()? _directoryOverride;

  Future<Directory>? _resolved;

  /// Set once the directory could not be had. The cache then works from memory
  /// alone, which is the right answer: a cache is an optimisation, and one
  /// that cannot reach its storage should quietly stop optimising rather than
  /// hold up the thing it was meant to speed along.
  bool _noDisk = false;

  /// Points the cache at a directory of the caller's choosing, and forgets
  /// whatever it had worked out about the last one.
  @visibleForTesting
  void useDirectory(Future<Directory> Function()? override) {
    _directoryOverride = override;
    _resolved = null;
    _noDisk = false;
  }

  /// Keeps everything in memory and touches no files.
  ///
  /// **Any widget test that reaches this cache has to call this.** Asking the
  /// platform where the files go leaves a future that never completes when
  /// nothing is there to answer, and real file I/O awaited in a widget test's
  /// body does not complete either — so the test hangs rather than fails.
  ///
  /// A timeout was tried here instead and was worse: it leaves a pending timer
  /// behind, which the test framework rightly complains about, and it put an
  /// arbitrary five-second limit into production code to work around tests. On
  /// a device the platform always answers. So the rule lives in the tests, and
  /// a test that seeds and reads within one run is served by memory anyway.
  @visibleForTesting
  void useMemoryOnly() {
    _directoryOverride = null;
    _resolved = null;
    _noDisk = true;
  }

  Future<Directory> _resolveDirectory() async {
    final base = _directoryOverride != null
        ? await _directoryOverride!()
        : await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/$_dirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// The cache directory, or null when there is not going to be one.
  Future<Directory?> _dir() async {
    if (_noDisk) return null;
    try {
      _resolved ??= _resolveDirectory();
      return await _resolved!;
    } catch (e) {
      _noDisk = true;
      _resolved = null;
      debugPrint('GeminiResultCache: no storage, memory only ($e)');
      return null;
    }
  }

  /// A key as a file name. The operation is snake_case and the rest is hex, so
  /// only the separator needs replacing.
  String _fileName(String key) => '${key.replaceAll('|', '_')}.json';

  Future<File?> _fileFor(String key) async {
    final dir = await _dir();
    if (dir == null) return null;
    return File('${dir.path}/${_fileName(key)}');
  }

  Future<File?> _indexFile() async {
    final dir = await _dir();
    if (dir == null) return null;
    return File('${dir.path}/$_indexFileName');
  }

  /// Computes a deterministic cache key.
  String computeKey({
    required String operation,
    required String promptVersion,
    required String model,
    required List<int> payloadBytes,
  }) {
    final payloadHash = sha256.convert(payloadBytes).toString();
    final combined = '$operation:$promptVersion:$model:$payloadHash';
    return '$operation|${sha256.convert(utf8.encode(combined))}';
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

  /// The operation a key belongs to, or 'unknown' for one written before keys
  /// carried it.
  static String operationOf(String key) {
    final cut = key.indexOf('|');
    return cut <= 0 ? 'unknown' : key.substring(0, cut);
  }

  /// Retrieves a cached response if available and not expired.
  ///
  /// [bypass] asks for the model instead, whatever is stored. The caller wants
  /// this page read again — usually because the last answer was wrong — and
  /// handing back the same answer is the one thing that cannot help.
  Future<String?> get(
    String key, {
    Duration ttl = defaultTtl,
    bool bypass = false,
  }) async {
    if (bypass) {
      debugPrint('GeminiResultCache: bypassed for $key');
      return null;
    }

    final now = DateTime.now();

    final memHit = _memoryCache[key];
    if (memHit != null) {
      if (now.difference(memHit.createdAt) <= ttl) {
        debugPrint('GeminiResultCache: L1 memory hit for $key');
        return memHit.data;
      }
      _memoryCache.remove(key);
    }

    try {
      final index = await _readIndex();
      final entry = index[key];
      if (entry == null) return null;

      if (now.difference(entry.createdAt) > ttl) {
        // Expired. Taken off the index as well as off the disk — leaving the
        // key behind let dead entries fill the index, and the cap below then
        // counted them and evicted living ones in their place.
        await remove(key);
        return null;
      }

      final file = await _fileFor(key);
      if (file == null || !await file.exists()) {
        // The index said it was there and it is not.
        await remove(key);
        return null;
      }

      final data = await file.readAsString();
      _putInMemory(key, data, entry.createdAt);
      debugPrint('GeminiResultCache: disk hit for $key');
      return data;
    } catch (e) {
      debugPrint('GeminiResultCache read error: $e');
      return null;
    }
  }

  /// Stores a response on disk and in memory.
  ///
  /// [label] is what the entry was about, in words — a page title, a subject.
  /// It is shown when the cache is listed, and is the difference between a
  /// list somebody can act on and a column of hashes.
  Future<void> put(String key, String data, {String label = ''}) async {
    final now = DateTime.now();
    _putInMemory(key, data, now);

    try {
      final file = await _fileFor(key);
      if (file == null) return; // Held in memory for this run and no further.
      await file.writeAsString(data, flush: true);

      final index = await _readIndex();
      index[key] = CachedEntry(
        key: key,
        operation: operationOf(key),
        label: label,
        createdAt: now,
        sizeBytes: data.length,
      );

      // Oldest first out, which the dates decide rather than insertion order.
      if (index.length > maxStoredEntries) {
        final byAge = index.values.toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        for (final stale in byAge.take(index.length - maxStoredEntries)) {
          index.remove(stale.key);
          await _deleteFile(stale.key);
        }
      }

      await _writeIndex(index);
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

  /// Everything the cache is holding, newest first.
  ///
  /// Read straight from the index, so listing no longer means opening every
  /// stored reply to find out how big it is.
  Future<List<CachedEntry>> list({Duration ttl = defaultTtl}) async {
    try {
      final index = await _readIndex();
      final now = DateTime.now();
      final expired = index.values
          .where((e) => now.difference(e.createdAt) > ttl)
          .toList();

      if (expired.isNotEmpty) {
        for (final entry in expired) {
          index.remove(entry.key);
          await _deleteFile(entry.key);
        }
        await _writeIndex(index);
      }

      return index.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (e) {
      debugPrint('GeminiResultCache list error: $e');
      return const [];
    }
  }

  /// How many entries there are and what they weigh.
  Future<CacheStats> stats() async {
    final entries = await list();
    return CacheStats(
      entries: entries.length,
      bytes: entries.fold<int>(0, (sum, e) => sum + e.sizeBytes),
    );
  }

  /// Drops one entry, so a single wrong answer can be thrown away without
  /// losing everything else that was paid for.
  Future<void> remove(String key) async {
    _memoryCache.remove(key);
    try {
      await _deleteFile(key);
      final index = await _readIndex();
      if (index.remove(key) != null) await _writeIndex(index);
    } catch (e) {
      debugPrint('GeminiResultCache remove error: $e');
    }
  }

  /// Clears all cached items
  Future<void> clear() async {
    _memoryCache.clear();
    try {
      final dir = await _dir();
      if (dir != null && await dir.exists()) {
        await dir.delete(recursive: true);
      }
      // The resolved path is remembered, and it has just been deleted, so the
      // next write would aim at a directory that is no longer there. Letting
      // it be worked out again recreates it. The index went with the folder.
      _resolved = null;
    } catch (e) {
      debugPrint('GeminiResultCache clear error: $e');
    }
  }

  /// Gives back the space the old preference-stored replies are still taking.
  ///
  /// Those entries can never be served again — the key format changed with the
  /// move to files — so they are pure weight in a file Android reads in full
  /// at every launch. Run once; the flag is a preference of a few bytes, which
  /// is the one thing preferences are for.
  Future<void> sweepLegacyEntries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_legacySweptKey) ?? false) return;

      var removed = 0;
      for (final key in prefs.getKeys().toList()) {
        if (key.startsWith(_legacyPrefix) && key != _legacySweptKey) {
          await prefs.remove(key);
          removed++;
        }
      }
      await prefs.remove(_legacyIndexKey);
      await prefs.setBool(_legacySweptKey, true);
      if (removed > 0) {
        debugPrint('GeminiResultCache: swept $removed old preference entries');
      }
    } catch (e) {
      debugPrint('GeminiResultCache sweep error: $e');
    }
  }

  Future<void> _deleteFile(String key) async {
    try {
      final file = await _fileFor(key);
      if (file != null && await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('GeminiResultCache file delete error: $e');
    }
  }

  Future<Map<String, CachedEntry>> _readIndex() async {
    final file = await _indexFile();
    if (file == null || !await file.exists()) return {};
    final raw = await file.readAsString();
    if (raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return {};
      final out = <String, CachedEntry>{};
      for (final item in decoded) {
        final entry = CachedEntry.fromJson(item);
        if (entry != null) out[entry.key] = entry;
      }
      return out;
    } catch (e) {
      debugPrint('GeminiResultCache index parse error: $e');
      return {};
    }
  }

  Future<void> _writeIndex(Map<String, CachedEntry> index) async {
    final file = await _indexFile();
    if (file == null) return;
    if (index.isEmpty) {
      if (await file.exists()) await file.delete();
      return;
    }
    await file.writeAsString(
      jsonEncode(index.values.map((e) => e.toJson()).toList()),
      flush: true,
    );
  }

  @visibleForTesting
  int get memoryCacheSize => _memoryCache.length;

  @visibleForTesting
  void clearMemory() => _memoryCache.clear();
}
