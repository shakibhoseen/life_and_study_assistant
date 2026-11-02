import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/services/ai/ai_media_limits.dart';

void main() {
  group('estimateRequestTokens', () {
    test('counts the prompt', () {
      // 250 characters at ~2.5 a token.
      expect(estimateRequestTokens(promptChars: 250), 100);
    });

    test('adds the image at its tile cost', () {
      expect(
        estimateRequestTokens(promptChars: 250, image: CaptureDetail.standard),
        100 + CaptureDetail.standard.approxTokens,
      );
    });

    test('a sharper photo costs more', () {
      final standard = estimateRequestTokens(
        promptChars: 100,
        image: CaptureDetail.standard,
      );
      final high = estimateRequestTokens(
        promptChars: 100,
        image: CaptureDetail.high,
      );
      expect(high, greaterThan(standard));
    });

    test('counts the reply when one is expected', () {
      expect(
        estimateRequestTokens(promptChars: 250, expectedOutputTokens: 400),
        500,
      );
    });

    test('lands near a real call', () {
      // Measured on the phone: a cropped study sheet at the standard preset
      // cost 1457 input tokens, with a prompt of roughly 2000 characters.
      final estimate = estimateRequestTokens(
        promptChars: 2000,
        image: CaptureDetail.standard,
      );
      expect(estimate, greaterThan(1000));
      expect(estimate, lessThan(2200));
    });
  });
}
