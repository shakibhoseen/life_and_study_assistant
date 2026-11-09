import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/services/ai/ai_media_limits.dart';
import 'package:life_and_study_assistant/core/services/ai/model_choice.dart';
import 'package:life_and_study_assistant/features/quiz/domain/scan_preferences.dart';

/// The model is the user's choice and a busy server is not a reason to go
/// behind their back about it, and a setting they chose should still be there
/// next time.
void main() {
  group('telling a busy server from a broken request', () {
    test('a 503 and its wording are recognised', () {
      // The exact message the API returns, which is what the app has to match.
      for (final error in [
        'HTTP Error 503: Service Unavailable',
        'This model is currently experiencing high demand.',
        'UNAVAILABLE',
        'The model is overloaded. Please try again later.',
      ]) {
        expect(isServerBusy(error), isTrue, reason: error);
      }
    });

    test('a bad key or an exhausted quota is not a busy server', () {
      // These never fix themselves, so retrying one only makes the user wait
      // longer for the same refusal.
      for (final error in [
        'API key not valid. Please pass a valid API key.',
        'RESOURCE_EXHAUSTED: Quota exceeded',
        'Invalid JSON payload received',
        'FAILED_PRECONDITION',
      ]) {
        expect(isServerBusy(error), isFalse, reason: error);
      }
    });
  });

  group('waiting a busy server out', () {
    test('it gives up after the backoff is spent', () {
      expect(serverBusyBackoff, isNotEmpty);
      expect(
        serverBusyBackoff.fold<int>(0, (a, d) => a + d.inSeconds),
        lessThanOrEqualTo(60),
        reason: 'long enough to ride out a spike, short enough to still look '
            'like working',
      );
    });

    test('each wait is longer than the last', () {
      for (var i = 1; i < serverBusyBackoff.length; i++) {
        expect(
          serverBusyBackoff[i],
          greaterThan(serverBusyBackoff[i - 1]),
          reason: 'step $i',
        );
      }
    });

    test('a request that works is not retried', () async {
      var calls = 0;
      final result = await withServerBusyRetry(() async {
        calls++;
        return 'done';
      });

      expect(result, 'done');
      expect(calls, 1);
    });

    test('something that is not a busy server is thrown straight away', () {
      var calls = 0;
      expect(
        () => withServerBusyRetry(() async {
          calls++;
          throw Exception('API key not valid');
        }),
        throwsA(isA<Exception>()),
      );
      expect(calls, 1);
    });
  });

  group('the scanning settings are remembered', () {
    test('the defaults are the careful ones', () {
      const prefs = ScanPreferences();

      expect(prefs.trustPrintedAnswersOnly, isTrue);
      expect(prefs.crossCheckAnswers, isTrue);
      expect(
        prefs.withExplanations,
        isFalse,
        reason: 'an explanation per question is paid for in output tokens',
      );
      expect(prefs.detail, CaptureDetail.high);
    });

    test('what was stored is read back', () {
      final prefs = ScanPreferences.fromNames(
        trust: false,
        explain: true,
        crossCheck: false,
        detailName: 'full',
      );

      expect(prefs.trustPrintedAnswersOnly, isFalse);
      expect(prefs.withExplanations, isTrue);
      expect(prefs.crossCheckAnswers, isFalse);
      expect(prefs.detail, CaptureDetail.full);
    });

    test('nothing stored means the defaults, not nothing', () {
      expect(ScanPreferences.fromNames(), const ScanPreferences());
    });

    test('a detail name from another build falls back rather than breaking', () {
      // A preset could be renamed or removed; the scanner must still have a
      // setting rather than none.
      expect(
        ScanPreferences.fromNames(detailName: 'ultra').detail,
        CaptureDetail.high,
      );
      expect(
        ScanPreferences.fromNames(detailName: '').detail,
        CaptureDetail.high,
      );
    });

    test('copyWith changes one setting and leaves the rest', () {
      const prefs = ScanPreferences();
      final changed = prefs.copyWith(detail: CaptureDetail.full);

      expect(changed.detail, CaptureDetail.full);
      expect(changed.trustPrintedAnswersOnly, prefs.trustPrintedAnswersOnly);
      expect(changed.crossCheckAnswers, prefs.crossCheckAnswers);
      expect(changed.withExplanations, prefs.withExplanations);
    });
  });
}
