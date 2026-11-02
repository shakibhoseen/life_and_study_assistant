import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/widgets/ai_key_missing_notice.dart';

void main() {
  group('looksLikeKeyProblem', () {
    test('recognises the messages the services actually send', () {
      // Copied from the services, so a reworded message that stops matching
      // shows up here rather than as a dead end on the phone.
      const fromServices = [
        'Gemini API কী বসানো নেই। সেটিংসে কী দিন, তারপর আবার চেষ্টা করুন।',
        'Gemini API কী বসানো নেই। সেটিংসে কী দিন, তারপর আবার স্ক্যান করুন।',
        'Gemini API Key সেট করা নেই। রুটিন PDF বিশ্লেষণ করতে Settings এ গিয়ে API Key যোগ করুন।',
      ];
      for (final message in fromServices) {
        expect(
          AiKeyMissingNotice.looksLikeKeyProblem(message),
          isTrue,
          reason: message,
        );
      }
    });

    test('leaves other failures alone', () {
      const others = [
        'Gemini সার্ভার এখন ব্যস্ত (৫০৩)। একটু পরে আবার চেষ্টা করুন।',
        'পাতায় প্রশ্ন অনেক বেশি, পুরোটা পড়া শেষ হয়নি।',
        'প্রশ্ন তৈরি করা গেল না। ইন্টারনেট দেখে আবার চেষ্টা করুন।',
      ];
      for (final message in others) {
        expect(
          AiKeyMissingNotice.looksLikeKeyProblem(message),
          isFalse,
          reason: message,
        );
      }
    });
  });

  testWidgets('offers the way to settings, not just the instruction', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiKeyMissingNotice(message: 'Gemini API কী বসানো নেই।'),
        ),
      ),
    );

    expect(find.text('সেটিংসে যান'), findsOneWidget);
    expect(find.textContaining('API কী'), findsOneWidget);
  });
}
