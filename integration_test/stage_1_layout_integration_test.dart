// ignore_for_file: avoid_print
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:life_and_study_assistant/core/services/media/layout/layout_detection_models.dart';
import 'package:life_and_study_assistant/core/services/media/layout/layout_detection_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Stage 3.1: Full-Page Layout & Dual-Column Detection on Physical Device',
      (WidgetTester tester) async {
    print('🚀 [STAGE 3.1 DEVICE TEST] Starting Physical Device Layout Benchmark...');

    File imageFile = File('/data/local/tmp/mcq_book_page.png');
    if (!await imageFile.exists()) {
      imageFile = File('/sdcard/mcq_book_page.jpg');
    }
    expect(await imageFile.exists(), isTrue,
        reason: 'Test image must exist at /data/local/tmp/mcq_book_page.png');
    final fileSize = await imageFile.length();
    print('📦 Step 1: Loaded test image from ${imageFile.path} ($fileSize bytes)');

    final stopwatch = Stopwatch()..start();
    final result = await LayoutDetectionService.instance.analyzeLayout(
      imageFile,
      autoDeskew: true,
    );
    stopwatch.stop();

    print('📊 [STAGE 3.1 DEVICE RESULT]');
    print('   - LayoutType: ${result.layoutType.name}');
    print('   - isDualColumn: ${result.isDualColumn}');
    print('   - Skew Angle: ${result.skewAngle.toStringAsFixed(2)}°');
    print('   - Confidence: ${(result.confidence * 100).toStringAsFixed(1)}%');
    print('   - Image Dimensions: ${result.imageWidth}x${result.imageHeight}');
    print('   - Total Columns: ${result.columnBoxes.length}');
    print('   - Total Execution Time: ${stopwatch.elapsedMilliseconds} ms');

    if (result.gutter != null) {
      print('   - Gutter Region: [${result.gutter!.left} .. ${result.gutter!.right}] (center: ${result.gutter!.center}, width: ${result.gutter!.width}px)');
      print('   - Gutter Confidence: ${(result.gutter!.confidence * 100).toStringAsFixed(1)}%');
    }

    for (int i = 0; i < result.columnBoxes.length; i++) {
      final box = result.columnBoxes[i];
      print('   - Column $i Box: [x=${box.left}, y=${box.top}, w=${box.width}, h=${box.height}]');
    }

    for (int i = 0; i < result.columnCrops.length; i++) {
      final crop = result.columnCrops[i];
      final cropExists = await crop.exists();
      final cropSize = cropExists ? await crop.length() : 0;
      print('   - Column $i Crop: ${crop.path} ($cropSize bytes, exists: $cropExists)');
    }

    // Acceptance criteria
    expect(result.isDualColumn, isTrue, reason: 'Page must be recognized as dual column');
    expect(result.layoutType, LayoutType.dualColumnWhitespace);
    expect(result.columnBoxes.length, 2, reason: 'Exactly 2 column bounding boxes required');
    expect(result.columnCrops.length, 2, reason: 'Exactly 2 column crops required');
    expect(result.confidence, greaterThanOrEqualTo(0.80), reason: 'Confidence must be >= 0.80');
    expect(result.gutter, isNotNull, reason: 'Gutter region must be identified');
    expect(result.gutter!.center, closeTo(result.imageWidth * 0.50, result.imageWidth * 0.10));

    // Zero crosstalk / page spanning check
    expect(result.columnBoxes[0].left, 0);
    expect(result.columnBoxes[0].width, equals(result.gutter!.left));
    expect(result.columnBoxes[1].left, equals(result.gutter!.right));
    expect(result.columnBoxes[1].width, equals(result.imageWidth - result.gutter!.right));

    print('✅ [STAGE 3.1 DEVICE TEST PASSED]');
  });
}
