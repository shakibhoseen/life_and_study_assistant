import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/services/ai/gemini_result_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The cache saved real money and could not be seen into or emptied: the keys
/// were hashes, nothing called clear(), and the only way out was to wipe the
/// app's data.
void main() {
  late GeminiResultCache cache;
  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // The replies live in files now, so the tests need somewhere to put them.
    // path_provider needs a platform; this seam is why it is replaceable.
    tempDir = await Directory.systemTemp.createTemp('ai_cache_test');
    cache = GeminiResultCache.instance;
    cache.useDirectory(() async => tempDir);
    cache.clearMemory();
    await cache.clear();
  });

  tearDown(() async {
    cache.useDirectory(null);
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  String keyFor(String operation, String payload) => cache.computeKeyFromString(
    operation: operation,
    promptVersion: 'v1.0',
    model: 'gemini-flash-latest',
    payloadText: payload,
  );

  group('the key says what it is for', () {
    test('the operation survives into the key, readably', () {
      final key = keyFor('question_bank_ocr', 'a page');

      expect(key, startsWith('question_bank_ocr|'));
      expect(GeminiResultCache.operationOf(key), 'question_bank_ocr');
    });

    test('identity still depends on everything it used to', () {
      // Same operation, different payload: a different entry.
      expect(
        keyFor('question_bank_ocr', 'page one'),
        isNot(keyFor('question_bank_ocr', 'page two')),
      );
      // Different operation on the same payload: also a different entry.
      expect(
        keyFor('question_bank_ocr', 'page one'),
        isNot(keyFor('study_sheet_ocr', 'page one')),
      );
      // And the same inputs give the same key every time, or nothing hits.
      expect(
        keyFor('question_bank_ocr', 'page one'),
        keyFor('question_bank_ocr', 'page one'),
      );
    });

    test('a key from before operations were visible reads as unknown', () {
      expect(GeminiResultCache.operationOf('deadbeef'), 'unknown');
    });
  });

  group('looking at what is stored', () {
    test('an entry can be listed, with its label and size', () async {
      final key = keyFor('question_bank_ocr', 'page');
      await cache.put(key, '{"questions":[]}', label: 'page25.jpg · ICT');

      final entries = await cache.list();

      expect(entries.length, 1);
      expect(entries.single.operation, 'question_bank_ocr');
      expect(entries.single.label, 'page25.jpg · ICT');
      expect(entries.single.sizeBytes, greaterThan(0));
    });

    test('the totals add up', () async {
      await cache.put(keyFor('a', '1'), 'one');
      await cache.put(keyFor('b', '2'), 'two');

      final stats = await cache.stats();

      expect(stats.entries, 2);
      expect(stats.isEmpty, isFalse);
      expect(stats.bytes, greaterThan(0));
    });

    test('an empty cache says so rather than failing', () async {
      final stats = await cache.stats();

      expect(stats.entries, 0);
      expect(stats.isEmpty, isTrue);
      expect(await cache.list(), isEmpty);
    });
  });

  group('emptying it', () {
    test('one entry can go without taking the others', () async {
      final doomed = keyFor('a', '1');
      final kept = keyFor('b', '2');
      await cache.put(doomed, 'one');
      await cache.put(kept, 'two');

      await cache.remove(doomed);

      expect(await cache.get(doomed), isNull);
      expect(await cache.get(kept), 'two');
      expect((await cache.list()).length, 1);
    });

    test('clear empties the index as well as the entries', () async {
      await cache.put(keyFor('a', '1'), 'one');
      await cache.clear();

      expect(await cache.list(), isEmpty);
      expect((await cache.stats()).entries, 0);
    });
  });

  group('the index does not grow a tail', () {
    test('an expired entry leaves the index too', () async {
      // It used to be removed from storage and left in the index, so dead keys
      // accumulated and the two-hundred cap counted them — evicting living
      // entries to make room for ones that were not there.
      final key = keyFor('question_bank_ocr', 'old page');
      await cache.put(key, 'stale');
      cache.clearMemory();

      expect(await cache.get(key, ttl: Duration.zero), isNull);
      expect(await cache.list(), isEmpty, reason: 'index pruned as well');
    });

    test('a reply file that vanished under the index is forgotten', () async {
      final key = keyFor('a', '1');
      await cache.put(key, 'one');
      cache.clearMemory();

      // As if the file had been cleared from under it.
      for (final file in tempDir.listSync(recursive: true)) {
        if (file is File) file.deleteSync();
      }

      expect(await cache.get(key), isNull);
      expect(await cache.list(), isEmpty);
    });
  });

  group('the replies are not in the preferences any more', () {
    test('nothing of the cache is stored there at all', () async {
      // A question-bank reply is kilobytes of JSON, and the preferences file is
      // read into memory in full at every launch. Both the replies and the
      // index that lists them now live in the cache folder, so the preferences
      // keep nothing of this.
      final big = 'x' * 20000;
      await cache.put(keyFor('question_bank_ocr', 'page'), big, label: 'p25');

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getKeys().where((k) => k.startsWith('gemini_cache_')),
        isEmpty,
      );
      expect(
        prefs.getKeys().map((k) => prefs.get(k)?.toString() ?? '').join(),
        isNot(contains(big)),
      );
    });

    test('the index is a file in the cache folder', () async {
      await cache.put(keyFor('question_bank_ocr', 'page'), 'reply');

      final names = tempDir
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .toList();

      expect(names, contains('index.json'));
      // And deleting the folder is the whole of deleting the cache.
      await cache.clear();
      expect((await cache.list()), isEmpty);
    });

    test('the reply is readable from its file', () async {
      final key = keyFor('question_bank_ocr', 'page');
      await cache.put(key, '{"questions":[1,2,3]}');
      cache.clearMemory();

      expect(await cache.get(key), '{"questions":[1,2,3]}');
      expect(tempDir.listSync(recursive: true).whereType<File>(), isNotEmpty);
    });

    test('clearing takes the files with it', () async {
      await cache.put(keyFor('a', '1'), 'one');
      await cache.clear();

      final files = (await tempDir.exists())
          ? tempDir.listSync(recursive: true).whereType<File>().toList()
          : <File>[];
      expect(files, isEmpty);
    });

    test('the old preference entries are swept once', () async {
      SharedPreferences.setMockInitialValues({
        'gemini_cache_oldkey1': '{"created":1,"data":"a big old reply"}',
        'gemini_cache_oldkey2': '{"created":1,"data":"another"}',
        'gemini_cache_index': ['oldkey1', 'oldkey2'],
        'office_wifi_ssid': 'ZaviSoft',
      });

      await cache.sweepLegacyEntries();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where((k) => k.startsWith('gemini_cache_')).where(
        (k) => k != 'gemini_cache_legacy_swept',
      ), isEmpty);
      expect(
        prefs.getString('office_wifi_ssid'),
        'ZaviSoft',
        reason: 'it touches nothing else',
      );
    });
  });

  group('asking again on purpose', () {
    test('bypass goes to the model even with an answer in hand', () async {
      final key = keyFor('question_bank_ocr', 'page');
      await cache.put(key, 'the old answer');

      expect(await cache.get(key), 'the old answer');
      expect(
        await cache.get(key, bypass: true),
        isNull,
        reason: 'the caller wants it read again, not handed back',
      );
    });

    test('bypassing does not throw the entry away', () async {
      // The next ordinary read should still hit: bypass is for this one call.
      final key = keyFor('question_bank_ocr', 'page');
      await cache.put(key, 'the old answer');

      await cache.get(key, bypass: true);

      expect(await cache.get(key), 'the old answer');
    });
  });
}
