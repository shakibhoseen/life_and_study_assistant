// ignore_for_file: avoid_print
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:life_and_study_assistant/core/services/media/local_ocr_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Stage 3.2: Full-Page Column-wise Native OCR & Reading Order Integration Benchmark',
      (WidgetTester tester) async {
    print('🚀 [STAGE 3.2 DEVICE BENCHMARK] Starting Full Pipeline on Samsung Galaxy M32...');

    File imageFile = File('/data/local/tmp/mcq_book_page.png');
    if (!await imageFile.exists()) {
      imageFile = File('/sdcard/mcq_book_page.jpg');
    }
    expect(await imageFile.exists(), isTrue,
        reason: 'Test image must exist on device storage');
    final fileSize = await imageFile.length();
    print('📦 Step 1: Input image verified at ${imageFile.path} ($fileSize bytes)');

    final stopwatch = Stopwatch()..start();
    final pageResult = await LocalOcrService.instance.processPage(
      imageFile: imageFile,
      languagePreset: OcrLanguagePreset.bengaliMathEnglish,
    );
    stopwatch.stop();

    print('📊 [STAGE 3.2 BENCHMARK RESULTS]');
    print('   - Page Dimensions: ${pageResult.pageWidth}x${pageResult.imageHeight}');
    print('   - Layout Type: ${pageResult.layoutType.name}');
    print('   - isDualColumn: ${pageResult.isDualColumn}');
    print('   - Layout Detection Time: ${pageResult.layoutElapsedMs} ms');
    print('   - Total OCR Time (Columns): ${pageResult.totalOcrElapsedMs} ms');
    print('   - Total End-to-End Time: ${pageResult.totalElapsedMs} ms (Stopwatch: ${stopwatch.elapsedMilliseconds} ms)');
    print('   - Columns Processed: ${pageResult.columns.length}');
    print('   - Total Merged Reading-Order Lines: ${pageResult.mergedLines.length}');

    // Column by column breakdown
    for (int i = 0; i < pageResult.columns.length; i++) {
      final col = pageResult.columns[i];
      print('   👉 [COLUMN $i]');
      print('      - Crop Origin Box: ${col.cropBox}');
      print('      - Native OCR Execution Time: ${col.ocrElapsedMs} ms');
      print('      - Line Count: ${col.pageLines.length}');
      print('      - Raw Text Characters: ${col.rawText.length}');
      print('      - First Line: ${col.pageLines.isNotEmpty ? col.pageLines.first.text : "(none)"}');
      print('      - Last Line: ${col.pageLines.isNotEmpty ? col.pageLines.last.text : "(none)"}');
    }

    // Verify Reading Order sequence
    print('📜 [READING ORDER VERIFICATION]');
    int prevCol = 0;
    bool columnOrderViolated = false;
    for (int i = 0; i < pageResult.mergedLines.length; i++) {
      final line = pageResult.mergedLines[i];
      if (line.columnId < prevCol) {
        columnOrderViolated = true;
      }
      prevCol = line.columnId;
    }
    print('   - Strict Sequential Reading Order (Col 0 -> Col 1): ${!columnOrderViolated}');

    // Coordinate mapping bounds check
    bool allBoxesWithinPage = true;
    for (final line in pageResult.mergedLines) {
      final box = line.boundingBox;
      if (box.left < 0 ||
          box.top < 0 ||
          box.right > pageResult.pageWidth ||
          box.bottom > pageResult.imageHeight) {
        allBoxesWithinPage = false;
        print('   ⚠️ Box out of bounds: $box on line "${line.text}"');
      }
    }
    print('   - All Mapped Bounding Boxes within Page Bounds: $allBoxesWithinPage');

    // Acceptance criteria
    expect(pageResult.isDualColumn, isTrue, reason: 'Must detect two columns');
    expect(pageResult.columns.length, 2, reason: 'Must process exactly 2 columns');
    expect(pageResult.columns[0].pageLines.isNotEmpty, isTrue, reason: 'Column 0 must have OCR lines');
    expect(pageResult.columns[1].pageLines.isNotEmpty, isTrue, reason: 'Column 1 must have OCR lines');
    expect(pageResult.mergedLines.length,
        equals(pageResult.columns[0].pageLines.length + pageResult.columns[1].pageLines.length));
    expect(columnOrderViolated, isFalse, reason: 'Column 1 text must never precede Column 0 text');
    expect(allBoxesWithinPage, isTrue, reason: 'All boxes must map within [0..pageWidth, 0..pageHeight]');

    print('✅ [STAGE 3.2 DEVICE BENCHMARK PASSED]');
  });
}
