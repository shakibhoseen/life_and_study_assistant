import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/services/flashcards/push_queue_depth.dart';

void main() {
  group('flashcardQueueDepth', () {
    test('an hourly push through a working day covers three days', () {
      // 9am to 10pm is thirteen slots a day.
      expect(
        flashcardQueueDepth(startHour: 9, endHour: 22, intervalMinutes: 60),
        39,
      );
    });

    test('a shorter interval queues more, not the same twelve', () {
      final hourly = flashcardQueueDepth(
        startHour: 9,
        endHour: 22,
        intervalMinutes: 60,
      );
      final halfHourly = flashcardQueueDepth(
        startHour: 9,
        endHour: 22,
        intervalMinutes: 30,
      );
      expect(halfHourly, greaterThan(hourly));
    });

    test('a long interval queues fewer', () {
      expect(
        flashcardQueueDepth(startHour: 9, endHour: 22, intervalMinutes: 240),
        9,
      );
    });

    test('the cap holds a very short interval in check', () {
      expect(
        flashcardQueueDepth(startHour: 0, endHour: 24, intervalMinutes: 5),
        60,
      );
    });

    test('a window that makes no sense still queues something', () {
      // Nonsense settings should not turn the feature off silently.
      expect(
        flashcardQueueDepth(startHour: 22, endHour: 9, intervalMinutes: 60),
        1,
      );
      expect(
        flashcardQueueDepth(startHour: 9, endHour: 22, intervalMinutes: 0),
        1,
      );
    });

    test('an interval longer than the window still queues one a day', () {
      expect(
        flashcardQueueDepth(
          startHour: 9,
          endHour: 10,
          intervalMinutes: 120,
          daysOfCover: 3,
        ),
        1,
      );
    });
  });
}
