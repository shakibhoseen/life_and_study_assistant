import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/services/ai/ai_media_limits.dart';

/// Gemini bills an image as 768x768 tiles at 258 tokens each.
int tokensFor(int w, int h) {
  if (w <= 384 && h <= 384) return 258;
  return ((w + 767) ~/ 768) * ((h + 767) ~/ 768) * 258;
}

void main() {
  group('CaptureDetail Tile Boundary Tests', () {
    test('every preset costs what it claims, in both orientations', () {
      for (final d in CaptureDetail.values) {
        // A 4:3 photo reduced to this longest side.
        final long = d.dimension;
        final short = (d.dimension * 3 / 4).round();

        expect(
          tokensFor(long, short),
          d.approxTokens,
          reason: '${d.name} landscape',
        );
        expect(
          tokensFor(short, long),
          d.approxTokens,
          reason: '${d.name} portrait',
        );
      }
    });

    test('presets sit on tile boundaries, so each step actually saves', () {
      final costs = CaptureDetail.values.map((d) => d.approxTokens).toList();

      // Strictly increasing: no two presets may cost the same, which is what
      // would happen with an in-between value like 1600.
      for (var i = 1; i < costs.length; i++) {
        expect(costs[i], greaterThan(costs[i - 1]));
      }
    });

    test('an in-between size would buy nothing over the step above it', () {
      // 1600 is the trap: it looks smaller than 1920 but tiles identically.
      expect(tokensFor(1600, 1200), tokensFor(1920, 1440));
    });

    test('the close-up preset is a single tile', () {
      expect(CaptureDetail.low.approxTokens, 258);
      expect(
        CaptureDetail.high.approxTokens,
        CaptureDetail.low.approxTokens * 4,
      );
    });
  });
}
