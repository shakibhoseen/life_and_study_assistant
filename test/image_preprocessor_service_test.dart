import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:life_and_study_assistant/core/services/media/image_preprocessor_service.dart';
import 'package:life_and_study_assistant/core/services/media/local_ocr_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File sampleImageFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ocr_test_');
    final sample = img.Image(width: 200, height: 100);
    // Draw white background
    img.fill(sample, color: img.ColorRgb8(255, 255, 255));
    // Draw some dark pixels simulating text
    for (int x = 20; x < 80; x++) {
      sample.setPixelRgb(x, 50, 0, 0, 0);
    }
    final bytes = img.encodeJpg(sample);
    sampleImageFile = File('${tempDir.path}/sample.jpg');
    await sampleImageFile.writeAsBytes(bytes);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('ImagePreprocessorService returns identical file when mode is none',
      () async {
    final result = await ImagePreprocessorService.instance.processImage(
      inputFile: sampleImageFile,
      filterMode: ImageFilterMode.none,
    );
    expect(result.path, sampleImageFile.path);
  });

  test('ImagePreprocessorService applies grayscale filter correctly', () async {
    final result = await ImagePreprocessorService.instance.processImage(
      inputFile: sampleImageFile,
      filterMode: ImageFilterMode.grayscale,
    );
    expect(result.existsSync(), isTrue);
    expect(result.lengthSync(), greaterThan(0));
    expect(result.path, isNot(sampleImageFile.path));
  });

  test('ImagePreprocessorService applies enhancedContrast filter', () async {
    final result = await ImagePreprocessorService.instance.processImage(
      inputFile: sampleImageFile,
      filterMode: ImageFilterMode.enhancedContrast,
    );
    expect(result.existsSync(), isTrue);
    expect(result.lengthSync(), greaterThan(0));
  });

  test('ImagePreprocessorService applies binarized filter', () async {
    final result = await ImagePreprocessorService.instance.processImage(
      inputFile: sampleImageFile,
      filterMode: ImageFilterMode.binarized,
    );
    expect(result.existsSync(), isTrue);
    expect(result.lengthSync(), greaterThan(0));
  });

  test('LocalOcrService language presets have correct codes and labels', () {
    expect(
      OcrLanguagePreset.bengaliMathEnglish.code,
      'ben+eng+equ',
    );
    expect(
      OcrLanguagePreset.bengaliOnly.code,
      'ben',
    );
    expect(
      OcrLanguagePreset.englishMath.code,
      'eng+equ',
    );
  });
}
