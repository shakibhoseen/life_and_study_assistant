import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/services/flashcards/push_refresh_decision.dart';

void main() {
  final now = DateTime(2026, 11, 2, 18, 30);
  const hourly = Duration(minutes: 60);

  bool decide({
    String fingerprint = 'cards:1,2,3|60|9-22',
    String? lastFingerprint = 'cards:1,2,3|60|9-22',
    Duration builtAgo = const Duration(minutes: 10),
    bool neverBuilt = false,
    bool force = false,
  }) => shouldRebuildPushQueue(
    fingerprint: fingerprint,
    lastFingerprint: lastFingerprint,
    lastBuiltAt: neverBuilt ? null : now.subtract(builtAgo),
    now: now,
    interval: hourly,
    force: force,
  );

  test('opening the app again does not move the next push', () {
    // Rebuilding restarts the first push a full hour from now, so doing it
    // on every open means it never arrives.
    expect(decide(), isFalse);
  });

  test('a changed card set is queued again', () {
    expect(decide(fingerprint: 'cards:1,2,9|60|9-22'), isTrue);
  });

  test('changed settings are queued again', () {
    expect(decide(fingerprint: 'cards:1,2,3|30|9-22'), isTrue);
  });

  test('nothing queued yet means queue it', () {
    expect(decide(lastFingerprint: null), isTrue);
    expect(decide(neverBuilt: true), isTrue);
  });

  test('once a push interval has passed it is rebuilt', () {
    // By now a push has gone out, so nothing is being delayed.
    expect(decide(builtAgo: const Duration(minutes: 61)), isTrue);
  });

  test('the user changing a setting is never made to wait', () {
    expect(decide(force: true), isTrue);
  });
}
