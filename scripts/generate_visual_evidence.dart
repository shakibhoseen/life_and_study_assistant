// ignore_for_file: avoid_print
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:life_and_study_assistant/core/services/media/image_preprocessor_service.dart';
import 'package:life_and_study_assistant/core/services/media/layout/skew_detection_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Generate Visual Comparison Evidence', () async {
  print('============================================================');
  print('📸 [VISUAL EVIDENCE] Generating Side-by-Side Preprocessing Proof');
  print('============================================================');

  final outDir = Directory('test_results/visual_comparison');
  if (!outDir.existsSync()) {
    outDir.createSync(recursive: true);
  }

  final fixtures = <String, String>{
    'sample_text_block': 'test/fixtures/sample_text_block.jpg',
    'col_left_exact': 'test/fixtures/col_left_exact.jpg',
    'mcq_book_page': 'test/fixtures/mcq_book_page.jpg',
  };

  for (final entry in fixtures.entries) {
    final name = entry.key;
    final path = entry.value;
    final file = File(path);

    if (!file.existsSync()) {
      print('⚠️ Fixture not found: $path');
      continue;
    }

    print('\n▶ Processing fixture: $name ($path)');
    final originalBytes = await file.readAsBytes();
    final decoded = img.decodeImage(originalBytes)!;
    final upright = img.bakeOrientation(decoded);

    // 1. Original (baked upright)
    final origFile = File('${outDir.path}/${name}_01_original.jpg');
    await origFile.writeAsBytes(img.encodeJpg(upright, quality: 95));

    // 2. Grayscale
    final gray = img.grayscale(upright);
    final grayFile = File('${outDir.path}/${name}_02_grayscale.jpg');
    await grayFile.writeAsBytes(img.encodeJpg(gray, quality: 95));

    // 3. Contrast-enhanced (Conservative Auto-Stretch)
    final enhanced = await ImagePreprocessorService.instance.processImage(
      inputFile: file,
      filterMode: ImageFilterMode.enhancedContrast,
    );
    final enhFile = File('${outDir.path}/${name}_03_contrast_enhanced.jpg');
    await enhFile.writeAsBytes(await enhanced.readAsBytes());

    // 4. Deskewed
    final skewAngle = SkewDetectionService.instance.detectSkewAngle(upright);
    final deskewed = SkewDetectionService.instance.deskew(upright, skewAngle);
    final deskewFile = File('${outDir.path}/${name}_04_deskewed.jpg');
    await deskewFile.writeAsBytes(img.encodeJpg(deskewed, quality: 95));

    // 5. Final OCR input (One-stop optimizeForOcr)
    final optResult = await ImagePreprocessorService.instance.optimizeForOcr(
      inputFile: file,
      filterMode: ImageFilterMode.enhancedContrast,
      autoDeskew: true,
    );
    final finalFile = File('${outDir.path}/${name}_05_final_ocr_input.jpg');
    await finalFile.writeAsBytes(await optResult.processedFile.readAsBytes());

    // Analyze contrast expansion
    final enhImg = img.decodeImage(await enhFile.readAsBytes())!;
    int minL = 255;
    int maxL = 0;
    for (int y = 0; y < enhImg.height; y += 15) {
      for (int x = 0; x < enhImg.width; x += 15) {
        final p = enhImg.getPixel(x, y);
        final l = p.r.toInt();
        if (l < minL) minL = l;
        if (l > maxL) maxL = l;
      }
    }

    print('   Dimensions: ${upright.width}x${upright.height} -> ${enhImg.width}x${enhImg.height}');
    print('   Detected Skew: $skewAngle° (Was Deskewed: ${optResult.wasDeskewed})');
    print('   Contrast Stretch: Min Lum = $minL, Max Lum = $maxL (Range: ${maxL - minL})');
    print('   Quality: ${optResult.quality.recommendation}');
  }

  // Also extract a micro-crop of vowel marks from sample_text_block to verify stroke preservation
  final sampleFile = File('test/fixtures/sample_text_block.jpg');
  if (sampleFile.existsSync()) {
    final decoded = img.decodeImage(sampleFile.readAsBytesSync())!;
    // Crop a 300x120 region containing Bengali vowels and digits
    final cropOrig = img.copyCrop(decoded, x: 50, y: 30, width: 350, height: 120);
    final cropFile1 = File('${outDir.path}/crop_vowels_original.jpg');
    await cropFile1.writeAsBytes(img.encodeJpg(cropOrig, quality: 98));

    final enhFile = File('${outDir.path}/sample_text_block_03_contrast_enhanced.jpg');
    if (enhFile.existsSync()) {
      final enhDecoded = img.decodeImage(enhFile.readAsBytesSync())!;
      final cropEnh = img.copyCrop(enhDecoded, x: 50, y: 30, width: 350, height: 120);
      final cropFile2 = File('${outDir.path}/crop_vowels_enhanced.jpg');
      await cropFile2.writeAsBytes(img.encodeJpg(cropEnh, quality: 98));
      print('\n🔍 Micro-crop of Bengali vowel marks saved:');
      print('   Original: ${cropFile1.path} (${cropFile1.lengthSync()} bytes)');
      print('   Enhanced: ${cropFile2.path} (${cropFile2.lengthSync()} bytes)');
    }
  }

  print('\n✅ [VISUAL EVIDENCE GENERATED] All comparison artifacts saved to test_results/visual_comparison/');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
