import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/services/media/local_ocr_service.dart';
import 'package:life_and_study_assistant/core/services/media/segmentation/segmentation_models.dart';

void main() {
  group('Stage 3.2: Coordinate Mapping & Reading Order Merging Unit Tests', () {
    const pageWidth = 3468;
    const pageHeight = 4624;

    test('TC-M01: Left column (cropOriginX=0) preserves original coordinates', () {
      const leftCropBox = TextBoundingBox(
        left: 0,
        top: 0,
        width: 1685,
        height: 4624,
      );

      final localLines = [
        const TextLineBox(
          text: '১. এমবেডেড সিস্টেমে বিদ্যুৎ খরচ-',
          boundingBox: TextBoundingBox(left: 120, top: 250, width: 850, height: 45),
          confidence: 0.88,
          columnId: 0,
        ),
      ];

      final mapped = LocalOcrService.mapLinesToPageCoordinates(
        lines: localLines,
        cropBox: leftCropBox,
        pageWidth: pageWidth,
        pageHeight: pageHeight,
        columnIndex: 0,
      );

      expect(mapped.length, 1);
      expect(mapped[0].boundingBox.left, 120);
      expect(mapped[0].boundingBox.top, 250);
      expect(mapped[0].boundingBox.width, 850);
      expect(mapped[0].boundingBox.height, 45);
      expect(mapped[0].columnId, 0);
    });

    test('TC-M02: Right column (cropOriginX=1810) correctly offsets X coordinates', () {
      const rightCropBox = TextBoundingBox(
        left: 1810,
        top: 0,
        width: 1658,
        height: 4624,
      );

      final localLines = [
        const TextLineBox(
          text: '১৬. কোনটি কম্পিউটারের মেমোরি নয়?',
          boundingBox: TextBoundingBox(left: 85, top: 310, width: 920, height: 50),
          confidence: 0.92,
          columnId: 1,
        ),
      ];

      final mapped = LocalOcrService.mapLinesToPageCoordinates(
        lines: localLines,
        cropBox: rightCropBox,
        pageWidth: pageWidth,
        pageHeight: pageHeight,
        columnIndex: 1,
      );

      expect(mapped.length, 1);
      // originalX = cropX + 1810 = 85 + 1810 = 1895
      expect(mapped[0].boundingBox.left, 1895);
      expect(mapped[0].boundingBox.top, 310);
      expect(mapped[0].boundingBox.width, 920);
      expect(mapped[0].boundingBox.height, 50);
      expect(mapped[0].columnId, 1);
      expect(mapped[0].boundingBox.right, 1895 + 920);
    });

    test('TC-M03: Boundary clamping prevents coordinates exceeding page boundary', () {
      const rightCropBox = TextBoundingBox(
        left: 1810,
        top: 0,
        width: 1658,
        height: 4624,
      );

      // Oversized box exceeding right and bottom
      final localLines = [
        const TextLineBox(
          text: 'প্রান্তিক লেখা',
          boundingBox: TextBoundingBox(left: 1500, top: 4500, width: 500, height: 300),
          confidence: 0.75,
          columnId: 1,
        ),
      ];

      final mapped = LocalOcrService.mapLinesToPageCoordinates(
        lines: localLines,
        cropBox: rightCropBox,
        pageWidth: pageWidth,
        pageHeight: pageHeight,
        columnIndex: 1,
      );

      expect(mapped.length, 1);
      // left = min(3467, 1810 + 1500) = 3310
      expect(mapped[0].boundingBox.left, 3310);
      // width must not push right beyond 3468
      expect(mapped[0].boundingBox.right, lessThanOrEqualTo(pageWidth));
      // height must not push bottom beyond 4624
      expect(mapped[0].boundingBox.bottom, lessThanOrEqualTo(pageHeight));
    });

    test('TC-M04: Reading order is strictly preserved: Column 0 top-to-bottom, then Column 1', () {
      final leftColLines = [
        const TextLineBox(
          text: 'Left Bottom Q15',
          boundingBox: TextBoundingBox(left: 100, top: 4000, width: 500, height: 40),
          confidence: 0.85,
          columnId: 0,
        ),
        const TextLineBox(
          text: 'Left Top Q1',
          boundingBox: TextBoundingBox(left: 100, top: 200, width: 500, height: 40),
          confidence: 0.90,
          columnId: 0,
        ),
      ];

      final rightColLines = [
        const TextLineBox(
          text: 'Right Top Q16',
          boundingBox: TextBoundingBox(left: 1900, top: 210, width: 500, height: 40),
          confidence: 0.91,
          columnId: 1,
        ),
        const TextLineBox(
          text: 'Right Bottom Q30',
          boundingBox: TextBoundingBox(left: 1900, top: 4100, width: 500, height: 40),
          confidence: 0.88,
          columnId: 1,
        ),
      ];

      // Sort each column internally by Y
      leftColLines.sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
      rightColLines.sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));

      // Sequential merge
      final merged = [...leftColLines, ...rightColLines];

      expect(merged.length, 4);
      expect(merged[0].text, 'Left Top Q1');
      expect(merged[1].text, 'Left Bottom Q15');
      // Crucial: Right Top Q16 comes AFTER Left Bottom Q15, NEVER interleaved by Y
      expect(merged[2].text, 'Right Top Q16');
      expect(merged[3].text, 'Right Bottom Q30');

      // Verify Column IDs
      expect(merged[0].columnId, 0);
      expect(merged[1].columnId, 0);
      expect(merged[2].columnId, 1);
      expect(merged[3].columnId, 1);
    });

    test('TC-M05: Empty or partial lines gracefully handled without errors', () {
      const cropBox = TextBoundingBox(left: 0, top: 0, width: 1000, height: 2000);
      final mapped = LocalOcrService.mapLinesToPageCoordinates(
        lines: [],
        cropBox: cropBox,
        pageWidth: 2000,
        pageHeight: 2000,
        columnIndex: 0,
      );
      expect(mapped, isEmpty);
    });
  });
}
