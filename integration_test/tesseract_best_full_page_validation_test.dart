// ignore_for_file: avoid_print
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Physical Device Validation: 10 Consecutive Full-Page Runs on Galaxy M32',
      (WidgetTester tester) async {
    print('🚀 [PHYSICAL VALIDATION] Initializing 10-Run Full-Page Best OCR Test on Galaxy M32...');

    // 1. Verify all 5 physical textbook images
    final testImagePaths = [
      '/data/local/tmp/col_left_exact.jpg',
      '/data/local/tmp/col_right_exact.jpg',
      '/data/local/tmp/manual_col1.jpg',
      '/data/local/tmp/manual_col2.jpg',
      '/data/local/tmp/mcq_book_page.jpg',
    ];

    for (final path in testImagePaths) {
      final f = File(path);
      expect(await f.exists(), isTrue, reason: 'Target image must exist at $path');
      print('   Image verified: $path (${await f.length()} bytes)');
    }

    // 2. Setup isolated cache directory inside app's internal storage
    final cacheDir = await getTemporaryDirectory();
    final bestBaseDir = Directory('${cacheDir.path}/test_tessdata_best_validation');
    final bestTessDir = Directory('${bestBaseDir.path}/tessdata');
    if (!await bestTessDir.exists()) {
      await bestTessDir.create(recursive: true);
    }

    // 3. Populate Best models
    final srcBestBen = File('/data/local/tmp/tessdata_best_parent/tessdata/ben.traineddata');
    final srcBestEng = File('/data/local/tmp/tessdata_best_parent/tessdata/eng.traineddata');
    final dstBestBen = File('${bestTessDir.path}/ben.traineddata');
    final dstBestEng = File('${bestTessDir.path}/eng.traineddata');

    await dstBestBen.writeAsBytes(await srcBestBen.readAsBytes(), flush: true);
    await dstBestEng.writeAsBytes(await srcBestEng.readAsBytes(), flush: true);

    // 4. Verify SHA-256 of loaded models
    String sha256Of(List<int> bytes) => sha256.convert(bytes).toString().toUpperCase();
    final benHash = sha256Of(await dstBestBen.readAsBytes());
    final engHash = sha256Of(await dstBestEng.readAsBytes());

    print('📋 [VALIDATION MODEL HASH AUDIT]');
    print('   Base Dir: ${bestBaseDir.path}');
    print('   - ben.traineddata: ${await dstBestBen.length()} bytes | SHA256: $benHash');
    print('   - eng.traineddata: ${await dstBestEng.length()} bytes | SHA256: $engHash');

    expect(benHash, '1CD0129288D1F74F6661C35E638E487BD146A66BB732ECD9E011E48DCB0DF623');
    expect(engHash, '8280AED0782FE27257A68EA10FE7EF324CA0F8D85BD2FD145D1C2B560BCB66BA');
    print('✅ Candidate B (Best) models verified with 100% hash parity.');

    const channel = MethodChannel('com.zavisoft.local_ocr');

    // Define 10-run schedule: 5 distinct images, then repeated
    final schedule = [
      {'run': 1, 'image': '/data/local/tmp/col_left_exact.jpg', 'label': 'Col-Left (Run 1)'},
      {'run': 2, 'image': '/data/local/tmp/col_right_exact.jpg', 'label': 'Col-Right (Run 1)'},
      {'run': 3, 'image': '/data/local/tmp/manual_col1.jpg', 'label': 'Manual-Col1 (Run 1)'},
      {'run': 4, 'image': '/data/local/tmp/manual_col2.jpg', 'label': 'Manual-Col2 (Run 1)'},
      {'run': 5, 'image': '/data/local/tmp/mcq_book_page.jpg', 'label': 'Full-Page (Run 1)'},
      {'run': 6, 'image': '/data/local/tmp/col_left_exact.jpg', 'label': 'Col-Left (Run 2)'},
      {'run': 7, 'image': '/data/local/tmp/col_right_exact.jpg', 'label': 'Col-Right (Run 2)'},
      {'run': 8, 'image': '/data/local/tmp/manual_col1.jpg', 'label': 'Manual-Col1 (Run 2)'},
      {'run': 9, 'image': '/data/local/tmp/manual_col2.jpg', 'label': 'Manual-Col2 (Run 2)'},
      {'run': 10, 'image': '/data/local/tmp/mcq_book_page.jpg', 'label': 'Full-Page (Run 2)'},
    ];

    final runResults = <Map<String, dynamic>>[];

    print('\n============================================================');
    print('🔄 EXECUTING 10 CONSECUTIVE OCR INFERENCES (CANDIDATE B: BEST)');
    print('============================================================');

    for (final item in schedule) {
      final runNum = item['run'] as int;
      final imgPath = item['image'] as String;
      final label = item['label'] as String;

      print('\n[STEP_RUN_START: Run $runNum | $label | Image: $imgPath]');

      final sw = Stopwatch()..start();
      String? rawText;
      String? errorMsg;

      try {
        rawText = await channel.invokeMethod<String>(
          'extractText',
          <String, dynamic>{
            'imagePath': imgPath,
            'tessData': bestBaseDir.path,
            'language': 'ben+eng',
            'args': {'psm': '6', 'preserve_interword_spaces': '1'},
          },
        );
      } catch (e) {
        errorMsg = e.toString();
        print('❌ Error in Run $runNum: $errorMsg');
      }
      sw.stop();

      final elapsed = sw.elapsedMilliseconds;
      final chars = (rawText ?? '').length;

      print('[STEP_RUN_DONE: Run $runNum | Elapsed: $elapsed ms | Chars: $chars | Error: ${errorMsg ?? "None"}]');

      runResults.add({
        'run': runNum,
        'label': label,
        'image': imgPath,
        'elapsedMs': elapsed,
        'charCount': chars,
        'error': errorMsg,
        'sample': (rawText != null && rawText.length > 100) ? rawText.substring(0, 100).replaceAll('\n', ' ') : rawText,
      });

      // Pause 2 seconds between runs to allow memory stabilization and logging
      await Future<void>.delayed(const Duration(seconds: 2));
    }

    print('\n============================================================');
    print('📊 [10-RUN PHYSICAL PERFORMANCE SUMMARY]');
    print('============================================================');
    for (final r in runResults) {
      print('Run ${r['run']}: ${r['label']} -> ${r['elapsedMs']} ms | ${r['charCount']} chars | Error: ${r['error'] ?? "None"}');
    }

    final totalTime = runResults.fold<int>(0, (acc, r) => acc + (r['elapsedMs'] as int));
    final avgTime = totalTime / runResults.length;
    print('\nTotal 10-Run OCR Time: ${totalTime / 1000} s (Avg: ${(avgTime / 1000).toStringAsFixed(2)} s per run)');
    print('Total Errors / Crashes: ${runResults.where((r) => r['error'] != null).length}');
    print('✅ [PHYSICAL VALIDATION TEST FINISHED SUCCESSFULLY]');
  }, timeout: const Timeout(Duration(minutes: 15)));
}
