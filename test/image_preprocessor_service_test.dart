import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:life_and_study_assistant/core/services/media/image_preprocessor_service.dart';
import 'package:life_and_study_assistant/core/services/media/layout/skew_detection_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ImagePreprocessorService & Preprocessing Pipeline Tests', () {
    final sampleFile = File('test/fixtures/sample_text_block.jpg');
    final colLeftFile = File('test/fixtures/col_left_exact.jpg');

    test(
      'TC-PREP-01: Original input image is strictly immutable and preserved',
      () async {
        expect(sampleFile.existsSync(), isTrue);
        final originalBytes = await sampleFile.readAsBytes();

        final processed = await ImagePreprocessorService.instance.processImage(
          inputFile: sampleFile,
          filterMode: ImageFilterMode.enhancedContrast,
        );

        // Verify original file bytes are 100% untouched
        final afterBytes = await sampleFile.readAsBytes();
        expect(afterBytes, equals(originalBytes));

        // Verify processed file is a distinct new file
        expect(processed.path, isNot(equals(sampleFile.path)));
        expect(await processed.exists(), isTrue);
        expect(await processed.length(), greaterThan(0));
      },
    );

    test('TC-PREP-02: Image quality assessment correctly computes dimensions, luminance & contrast', () async {
      final quality = await ImagePreprocessorService.instance
          .assessImageQuality(sampleFile);

      expect(quality.width, equals(1595));
      expect(quality.height, equals(800));
      expect(quality.aspectRatio, closeTo(1.99, 0.05));
      expect(quality.isLowResolution, isFalse);
      expect(quality.isTooDark, isFalse);
      expect(quality.isOverexposed, isFalse);
      expect(quality.isLowContrast, isFalse);
      expect(quality.isAdequateForOcr, isTrue);
      expect(quality.recommendation, contains('উপযুক্ত'));
    });

    test(
      'TC-PREP-03: Quality assessment correctly flags low-resolution images',
      () async {
        // Create a small 200x200 low-resolution image
        final tinyImg = img.Image(width: 200, height: 200);
        img.fill(tinyImg, color: img.ColorRgb8(240, 240, 240));
        final tempFile = File('${Directory.systemTemp.path}/tiny_test.jpg');
        await tempFile.writeAsBytes(img.encodeJpg(tinyImg));

        final quality = await ImagePreprocessorService.instance
            .assessImageQuality(tempFile);
        expect(quality.isLowResolution, isTrue);
        expect(quality.isAdequateForOcr, isFalse);
        expect(quality.recommendation, contains('রেজোলিউশন কম'));

        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      },
    );

    test('TC-PREP-04: Conservative contrast enhancement stretches dynamic range without clipping', () async {
      final processed = await ImagePreprocessorService.instance.processImage(
        inputFile: sampleFile,
        filterMode: ImageFilterMode.enhancedContrast,
      );

      final pBytes = await processed.readAsBytes();
      final pImg = img.decodeImage(pBytes)!;

      // Sample luminance
      int minL = 255;
      int maxL = 0;
      for (int y = 0; y < pImg.height; y += 20) {
        for (int x = 0; x < pImg.width; x += 20) {
          final p = pImg.getPixel(x, y);
          final l = p.r.toInt();
          if (l < minL) minL = l;
          if (l > maxL) maxL = l;
        }
      }

      // Paper background should reach near white (> 240) and ink should reach deep dark (< 50)
      expect(maxL, greaterThanOrEqualTo(240));
      expect(minL, lessThanOrEqualTo(60));
      expect(maxL - minL, greaterThan(180));
    });

    test('TC-PREP-05: High resolution page is preserved up to 4096px without destructive downsampling', () async {
      expect(colLeftFile.existsSync(), isTrue);

      final processed = await ImagePreprocessorService.instance.processImage(
        inputFile: colLeftFile,
        filterMode: ImageFilterMode.enhancedContrast,
        maxDimension: 4096,
      );

      final pBytes = await processed.readAsBytes();
      final pImg = img.decodeImage(pBytes)!;

      // Height should be 4096 (proportionately capped from 4424), NOT destroyed to 1920
      expect(pImg.height, equals(4096));
      expect(pImg.width, closeTo(1432, 5));
    });

    test('TC-PREP-06: Deskew applies white background padding eliminating dark corner wedges', () {
      final testCanvas = img.Image(width: 300, height: 300);
      img.fill(testCanvas, color: img.ColorRgb8(250, 250, 250));

      final deskewed = SkewDetectionService.instance.deskew(testCanvas, 5.0);

      // Check pixel at top-left corner (0, 0) of rotated image
      final cornerPixel = deskewed.getPixel(0, 0);
      // Corner should be white (255, 255, 255), never black (0, 0, 0)
      expect(cornerPixel.r.toInt(), equals(255));
      expect(cornerPixel.g.toInt(), equals(255));
      expect(cornerPixel.b.toInt(), equals(255));
    });

    test('TC-PREP-07: One-stop optimizeForOcr returns complete metadata and valid file', () async {
      final result = await ImagePreprocessorService.instance.optimizeForOcr(
        inputFile: sampleFile,
        filterMode: ImageFilterMode.enhancedContrast,
        autoDeskew: true,
      );

      expect(result.originalFile.path, equals(sampleFile.path));
      expect(await result.processedFile.exists(), isTrue);
      expect(result.originalWidth, equals(1595));
      expect(result.originalHeight, equals(800));
      expect(result.processedWidth, equals(1595));
      expect(result.processedHeight, equals(800));
      expect(result.quality.isAdequateForOcr, isTrue);
      expect(result.appliedFilter, equals(ImageFilterMode.enhancedContrast));
      expect(result.elapsedMs, greaterThan(0));
    });

    test('TC-PREP-08: Dual column splitting preserves aspect ratio and generates two crops', () async {
      final splits = await ImagePreprocessorService.instance.splitTwoColumns(
        sampleFile,
      );
      expect(splits.length, equals(2));
      expect(await splits[0].exists(), isTrue);
      expect(await splits[1].exists(), isTrue);

      final col1 = img.decodeImage(await splits[0].readAsBytes())!;
      final col2 = img.decodeImage(await splits[1].readAsBytes())!;

      // Left column is 52% of 1595 = ~829px; Right column is 52% of 1595 = ~829px
      expect(col1.width, closeTo(829, 5));
      expect(col2.width, closeTo(829, 5));
      expect(col1.height, equals(800));
      expect(col2.height, equals(800));
    });
  });
}
