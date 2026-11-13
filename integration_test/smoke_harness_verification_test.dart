// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Smoke Test: Verify Integration Test Runner on Galaxy M32', (
    WidgetTester tester,
  ) async {
    print('\n============================================================');
    print('🧪 [SMOKE TEST] Initializing Test Runner Verification...');
    print('============================================================');

    // 1. Verify test image
    final testImage = File('/data/local/tmp/sample_text_block.jpg');
    expect(
      await testImage.exists(),
      isTrue,
      reason: 'Sample image must exist on device',
    );
    final imgBytes = await testImage.readAsBytes();
    final imgHash = sha256.convert(imgBytes).toString().toUpperCase();
    print('   Target Image: ${testImage.path} (${imgBytes.length} bytes)');
    print('   Target Image SHA-256: $imgHash');

    // 2. Setup isolated cache directory
    final cacheDir = await getTemporaryDirectory();
    final smokeBaseDir = Directory('${cacheDir.path}/test_tessdata_smoke');
    final smokeTessDir = Directory('${smokeBaseDir.path}/tessdata');
    if (!await smokeTessDir.exists()) {
      await smokeTessDir.create(recursive: true);
    }

    // 3. Populate Fast models
    final srcFastBen = File(
      '/data/local/tmp/tessdata_fast/tessdata/ben.traineddata',
    );
    final srcFastEng = File(
      '/data/local/tmp/tessdata_fast/tessdata/eng.traineddata',
    );
    final dstBen = File('${smokeTessDir.path}/ben.traineddata');
    final dstEng = File('${smokeTessDir.path}/eng.traineddata');

    await dstBen.writeAsBytes(await srcFastBen.readAsBytes(), flush: true);
    await dstEng.writeAsBytes(await srcFastEng.readAsBytes(), flush: true);

    String sha256Of(List<int> bytes) =>
        sha256.convert(bytes).toString().toUpperCase();
    final benHash = sha256Of(await dstBen.readAsBytes());
    final engHash = sha256Of(await dstEng.readAsBytes());

    expect(
      benHash,
      '31163084C279AAEBD376216F0C3D5C17AD4B5FEE8DB49DAE79C20000B5DE5964',
    );
    expect(
      engHash,
      '7D4322BD2A7749724879683FC3912CB542F19906C83BCC1A52132556427170B2',
    );
    print('   Model files copied and verified with 100% hash parity.');

    const channel = MethodChannel('com.zavisoft.local_ocr');
    const runId = 'SMOKE_RUN_01';

    // 4. Emit structured START marker
    final startTime = DateTime.now().toUtc().toIso8601String();
    print(
      'BENCHMARK_MARKER: {"runId": "$runId", "event": "START", "timestamp": "$startTime", "image": "${testImage.path}", "sha256": "$imgHash", "model": "Fast"}',
    );

    final sw = Stopwatch()..start();
    String? rawText;
    String? errorMsg;

    try {
      rawText = await channel
          .invokeMethod<String>('extractText', <String, dynamic>{
            'imagePath': testImage.path,
            'tessData': smokeBaseDir.path,
            'language': 'ben+eng',
            'args': {'psm': '6', 'preserve_interword_spaces': '1'},
          })
          .timeout(const Duration(seconds: 60));
    } on TimeoutException catch (e) {
      errorMsg = 'Operation timed out after 60s: $e';
    } catch (e, st) {
      errorMsg = 'Exception: $e\n$st';
    }
    sw.stop();

    final endTime = DateTime.now().toUtc().toIso8601String();
    final elapsedMs = sw.elapsedMilliseconds;
    final charCount = (rawText ?? '').length;

    if (errorMsg != null) {
      print(
        'BENCHMARK_MARKER: {"runId": "$runId", "event": "ERROR", "timestamp": "$endTime", "elapsedMs": $elapsedMs, "error": "${errorMsg.replaceAll('"', "'")}", "status": "FAILED"}',
      );
      fail('Smoke test failed with error: $errorMsg');
    } else {
      print(
        'BENCHMARK_MARKER: {"runId": "$runId", "event": "COMPLETE", "timestamp": "$endTime", "elapsedMs": $elapsedMs, "charCount": $charCount, "status": "SUCCESS"}',
      );
    }

    // 5. Save raw output to isolated file
    final outputFile = File('${cacheDir.path}/${runId}_output.txt');
    await outputFile.writeAsString(rawText ?? '', flush: true);
    expect(await outputFile.exists(), isTrue);
    expect(await outputFile.length(), greaterThan(0));

    print(
      '   Raw OCR text saved to: ${outputFile.path} (${await outputFile.length()} bytes)',
    );
    print(
      '   Sample extracted text: "${(rawText ?? '').substring(0, math.min(60, charCount)).replaceAll('\n', ' ')}"',
    );
    print(
      '\n✅ [SMOKE TEST PASSED] Test harness, MethodChannel, and logging verified!',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}
