import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:life_and_study_assistant/core/services/media/layout/layout_detection_models.dart';
import 'package:life_and_study_assistant/core/services/media/layout/layout_detection_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('layout_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// Helper to create a synthetic 2-column page with whitespace gutter
  File createDualColumnPage({
    int width = 1000,
    int height = 1400,
    bool hasDivider = false,
    double skewAngle = 0.0,
  }) {
    var page = img.Image(width: width, height: height);
    img.fill(page, color: img.ColorRgb8(255, 255, 255));

    // Left column: 80 to 460
    for (int y = 80; y < height - 80; y += 32) {
      for (int dy = 0; dy < 10; dy++) {
        for (int x = 80; x < 460; x++) {
          page.setPixelRgb(x, y + dy, 10, 10, 10);
        }
      }
    }

    if (hasDivider) {
      // Divider line at x = 500
      for (int y = 60; y < height - 60; y++) {
        page.setPixelRgb(500, y, 0, 0, 0);
        page.setPixelRgb(501, y, 0, 0, 0);
      }
    }

    // Right column: 540 to 920
    for (int y = 80; y < height - 80; y += 32) {
      for (int dy = 0; dy < 10; dy++) {
        for (int x = 540; x < 920; x++) {
          page.setPixelRgb(x, y + dy, 10, 10, 10);
        }
      }
    }

    if (skewAngle != 0.0) {
      page = img.copyRotate(page, angle: skewAngle);
    }

    final file = File('${tempDir.path}/page_${DateTime.now().microsecondsSinceEpoch}.jpg');
    file.writeAsBytesSync(img.encodeJpg(page));
    return file;
  }

  /// Helper to create a single-column page (no central gutter)
  File createSingleColumnPage({int width = 1000, int height = 1400}) {
    final page = img.Image(width: width, height: height);
    img.fill(page, color: img.ColorRgb8(255, 255, 255));

    // Full-width text spanning across the center (100 to 900)
    for (int y = 80; y < height - 80; y += 32) {
      for (int dy = 0; dy < 10; dy++) {
        for (int x = 100; x < 900; x++) {
          page.setPixelRgb(x, y + dy, 10, 10, 10);
        }
      }
    }

    final file = File('${tempDir.path}/single_${DateTime.now().microsecondsSinceEpoch}.jpg');
    file.writeAsBytesSync(img.encodeJpg(page));
    return file;
  }

  test('Benchmark 1: Whitespace dual-column page correctly detects gutter and 2 crops', () async {
    final file = createDualColumnPage(hasDivider: false);
    final result = await LayoutDetectionService.instance.analyzeLayout(file);

    expect(result.layoutType, LayoutType.dualColumnWhitespace);
    expect(result.gutter, isNotNull);
    expect(result.gutter!.hasDividerLine, isFalse);
    expect(result.gutter!.center, closeTo(500, 30));
    expect(result.columnBoxes.length, 2);
    expect(result.columnCrops.length, 2);
    expect(result.confidence, greaterThanOrEqualTo(0.60));
    expect(result.originalImage.existsSync(), isTrue);
  });

  test('Benchmark 2: Vertical divider line dual-column page detects divider', () async {
    final file = createDualColumnPage(hasDivider: true);
    final result = await LayoutDetectionService.instance.analyzeLayout(file);

    expect(result.layoutType, LayoutType.dualColumnDivider);
    expect(result.gutter, isNotNull);
    expect(result.gutter!.hasDividerLine, isTrue);
    expect(result.gutter!.center, closeTo(500, 20));
    expect(result.columnBoxes.length, 2);
    expect(result.columnCrops.length, 2);
  });

  test('Benchmark 3: Single column page safely avoids false split and defaults to 1 column', () async {
    final file = createSingleColumnPage();
    final result = await LayoutDetectionService.instance.analyzeLayout(file);

    expect(result.layoutType, LayoutType.singleColumn);
    expect(result.columnBoxes.length, 1);
    expect(result.columnCrops.length, 1);
    expect(result.failureReason, isNotNull);
    // Never forces a 50% split on a single column page
    expect(result.columnBoxes[0].width, equals(result.imageWidth));
  });

  test('Benchmark 4: Skewed page is automatically detected and deskewed', () async {
    // 3.5 degrees skew
    final file = createDualColumnPage(skewAngle: 3.5);
    final result = await LayoutDetectionService.instance.analyzeLayout(file);

    expect(result.skewAngle.abs(), greaterThan(1.5));
    expect(result.deskewedImage.existsSync(), isTrue);
    expect(result.columnBoxes.length, 2);
  });

  test('Benchmark 5: Real-world user book image layout analysis', () async {
    final userImage = File('/Users/shakib/.gemini/antigravity/brain/8b6824b5-c4fd-4d74-a304-916f3d179564/scratch/rot_180.jpg');
    if (!userImage.existsSync()) return;

    final result = await LayoutDetectionService.instance.analyzeLayout(userImage);

    // The user's page has 2 dense columns with a vertical space in between
    expect(result.isDualColumn, isTrue);
    expect(result.columnBoxes.length, 2);
    expect(result.columnCrops.length, 2);
    expect(result.gutter, isNotNull);
    expect(result.gutter!.center, closeTo(userImage.existsSync() ? result.imageWidth * 0.50 : 0, result.imageWidth * 0.15));
    expect(result.columnCrops[0].existsSync(), isTrue);
    expect(result.columnCrops[1].existsSync(), isTrue);
  });

  test('Benchmark 6 (Stage 3.1): Real full book page (mcq_book_page.png) detects dual-column layout', () async {
    final bookImage = File('test/fixtures/mcq_book_page.png');
    expect(bookImage.existsSync(), isTrue);

    final result = await LayoutDetectionService.instance.analyzeLayout(bookImage, autoDeskew: true);

    expect(result.layoutType, LayoutType.dualColumnWhitespace);
    expect(result.isDualColumn, isTrue);
    expect(result.confidence, greaterThanOrEqualTo(0.80));
    expect(result.gutter, isNotNull);
    // Gutter center in central spine region
    expect(result.gutter!.center, closeTo(result.imageWidth * 0.50, result.imageWidth * 0.10));
    expect(result.columnBoxes.length, 2);
    expect(result.columnCrops.length, 2);
    expect(result.columnCrops[0].existsSync(), isTrue);
    expect(result.columnCrops[1].existsSync(), isTrue);

    // Left and right column boxes span the page cleanly
    expect(result.columnBoxes[0].left, 0);
    expect(result.columnBoxes[0].width, equals(result.gutter!.left));
    expect(result.columnBoxes[1].left, equals(result.gutter!.right));
    expect(result.columnBoxes[1].width, equals(result.imageWidth - result.gutter!.right));
  });
}
