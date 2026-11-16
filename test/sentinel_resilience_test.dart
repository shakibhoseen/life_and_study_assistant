import 'package:flutter_test/flutter_test.dart';

import 'package:life_and_study_assistant/core/services/background/office_sentinel_service.dart';

/// The sentinel polls every five seconds behind a single-entry guard, and used
/// to take a fresh GPS fix on every one of those. Both of those turned out to
/// matter: one hung request could silence it for a morning, and a thousand
/// location fixes a morning is a real cost on a phone in a pocket.
void main() {
  final now = DateTime(2026, 11, 16, 9, 0, 0);

  group('when another location fix is worth taking', () {
    const freshness = Duration(seconds: 45);

    test('the first one always is', () {
      expect(shouldRefreshPosition(null, now, freshness), isTrue);
    });

    test('a fix from five seconds ago is not', () {
      final lastAt = now.subtract(const Duration(seconds: 5));
      expect(
        shouldRefreshPosition(lastAt, now, freshness),
        isFalse,
        reason: 'this is the five-second poll; it must reuse the fix',
      );
    });

    test('one older than the window is', () {
      final lastAt = now.subtract(const Duration(seconds: 50));
      expect(shouldRefreshPosition(lastAt, now, freshness), isTrue);
    });

    test('exactly at the window counts as old', () {
      final lastAt = now.subtract(freshness);
      expect(shouldRefreshPosition(lastAt, now, freshness), isTrue);
    });

    test('a clock that moved backwards does not pin the cache forever', () {
      // The test lab can move the sentinel's clock, and it expires by itself,
      // which moves it back. Without this the cached fix would be newer than
      // "now" and never be replaced.
      final lastAt = now.add(const Duration(hours: 3));
      expect(shouldRefreshPosition(lastAt, now, freshness), isTrue);
    });
  });

  group('when a pass is given up on', () {
    const limit = Duration(minutes: 2);

    test('a pass with no start time is not trusted', () {
      expect(isPassAbandoned(null, now, limit), isTrue);
    });

    test('one that started a moment ago is left alone', () {
      final since = now.subtract(const Duration(seconds: 10));
      expect(
        isPassAbandoned(since, now, limit),
        isFalse,
        reason: 'a pass doing real work must not be run twice',
      );
    });

    test('one stuck past the limit is abandoned', () {
      final since = now.subtract(const Duration(minutes: 5));
      expect(
        isPassAbandoned(since, now, limit),
        isTrue,
        reason: 'otherwise every later tick returns and the morning is lost',
      );
    });

    test('a backwards clock does not make a pass look eternally fresh', () {
      final since = now.add(const Duration(hours: 1));
      expect(isPassAbandoned(since, now, limit), isTrue);
    });
  });
}
