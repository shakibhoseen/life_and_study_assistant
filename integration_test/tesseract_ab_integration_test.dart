// ignore_for_file: avoid_print
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Rigorous A/B Benchmark: Tesseract Fast vs Tesseract Best on Galaxy M32',
      (WidgetTester tester) async {
    print('🚀 [RIGOROUS A/B BENCHMARK] Initializing Isolated Fast vs Best Test on Galaxy M32...');

    // 1. Verify test image
    final testImage = File('/data/local/tmp/col_left_exact.jpg');
    expect(await testImage.exists(), isTrue,
        reason: 'Target image must exist at /data/local/tmp/col_left_exact.jpg');
    print('📦 Step 1: Input image verified at ${testImage.path} (${await testImage.length()} bytes)');

    // 2. Setup isolated cache directories inside app's own internal storage
    final cacheDir = await getTemporaryDirectory();
    final fastBaseDir = Directory('${cacheDir.path}/test_tessdata_fast');
    final fastTessDir = Directory('${fastBaseDir.path}/tessdata');
    if (!await fastTessDir.exists()) {
      await fastTessDir.create(recursive: true);
    }

    final bestBaseDir = Directory('${cacheDir.path}/test_tessdata_best');
    final bestTessDir = Directory('${bestBaseDir.path}/tessdata');
    if (!await bestTessDir.exists()) {
      await bestTessDir.create(recursive: true);
    }

    // 3. Populate Fast models
    final srcFastBen = File('/data/local/tmp/tessdata_fast/tessdata/ben.traineddata');
    final srcFastEng = File('/data/local/tmp/tessdata_fast/tessdata/eng.traineddata');
    final dstFastBen = File('${fastTessDir.path}/ben.traineddata');
    final dstFastEng = File('${fastTessDir.path}/eng.traineddata');

    await dstFastBen.writeAsBytes(await srcFastBen.readAsBytes(), flush: true);
    await dstFastEng.writeAsBytes(await srcFastEng.readAsBytes(), flush: true);

    // 4. Populate Best models
    final srcBestBen = File('/data/local/tmp/tessdata_best_parent/tessdata/ben.traineddata');
    final srcBestEng = File('/data/local/tmp/tessdata_best_parent/tessdata/eng.traineddata');
    final dstBestBen = File('${bestTessDir.path}/ben.traineddata');
    final dstBestEng = File('${bestTessDir.path}/eng.traineddata');

    await dstBestBen.writeAsBytes(await srcBestBen.readAsBytes(), flush: true);
    await dstBestEng.writeAsBytes(await srcBestEng.readAsBytes(), flush: true);

    // 5. Compute SHA256 of copied files to guarantee model integrity
    String sha256Of(List<int> bytes) => sha256.convert(bytes).toString().toUpperCase();

    final fastBenHash = sha256Of(await dstFastBen.readAsBytes());
    final fastEngHash = sha256Of(await dstFastEng.readAsBytes());
    final bestBenHash = sha256Of(await dstBestBen.readAsBytes());
    final bestEngHash = sha256Of(await dstBestEng.readAsBytes());

    print('\n📋 [ISOLATED MODEL HASH AUDIT]');
    print('   Candidate A (Fast) Base Dir: ${fastBaseDir.path}');
    print('   - Fast ben.traineddata: ${await dstFastBen.length()} bytes | SHA256: $fastBenHash');
    print('   - Fast eng.traineddata: ${await dstFastEng.length()} bytes | SHA256: $fastEngHash');

    print('   Candidate B (Best) Base Dir: ${bestBaseDir.path}');
    print('   - Best ben.traineddata: ${await dstBestBen.length()} bytes | SHA256: $bestBenHash');
    print('   - Best eng.traineddata: ${await dstBestEng.length()} bytes | SHA256: $bestEngHash');

    // Strict validation assertions
    expect(fastBenHash, '31163084C279AAEBD376216F0C3D5C17AD4B5FEE8DB49DAE79C20000B5DE5964');
    expect(bestBenHash, '1CD0129288D1F74F6661C35E638E487BD146A66BB732ECD9E011E48DCB0DF623');
    print('✅ Model hashes verified: Zero model cross-contamination!');

    const channel = MethodChannel('com.zavisoft.local_ocr');

    // Alternating execution schedule to prevent thermal/caching bias:
    // Run 1: Fast -> Best
    // Run 2: Best -> Fast
    // Run 3: Fast -> Best
    final fastRuns = <Map<String, dynamic>>[];
    final bestRuns = <Map<String, dynamic>>[];

    Future<Map<String, dynamic>> executeOcr(String baseDir, String modelLabel) async {
      final sw = Stopwatch()..start();
      final text = await channel.invokeMethod<String>(
        'extractText',
        <String, dynamic>{
          'imagePath': testImage.path,
          'tessData': baseDir,
          'language': 'ben+eng',
          'args': {'psm': '6', 'preserve_interword_spaces': '1'},
        },
      );
      sw.stop();
      return {
        'model': modelLabel,
        'elapsedMs': sw.elapsedMilliseconds,
        'text': text ?? '',
        'charCount': (text ?? '').length,
      };
    }

    print('\n========================================================');
    print('🔄 EXECUTING ALTERNATING A/B TEST SCHEDULE (3 RUNS EACH)');
    print('========================================================');

    // Round 1: Fast then Best
    print('👉 Round 1: Running Fast...');
    final r1Fast = await executeOcr(fastBaseDir.path, 'Fast');
    fastRuns.add(r1Fast);
    print('   Fast R1: ${r1Fast['elapsedMs']} ms | chars: ${r1Fast['charCount']}');

    print('👉 Round 1: Running Best...');
    final r1Best = await executeOcr(bestBaseDir.path, 'Best');
    bestRuns.add(r1Best);
    print('   Best R1: ${r1Best['elapsedMs']} ms | chars: ${r1Best['charCount']}');

    // Round 2: Best then Fast (reversed to mitigate thermal bias)
    print('👉 Round 2: Running Best...');
    final r2Best = await executeOcr(bestBaseDir.path, 'Best');
    bestRuns.add(r2Best);
    print('   Best R2: ${r2Best['elapsedMs']} ms | chars: ${r2Best['charCount']}');

    print('👉 Round 2: Running Fast...');
    final r2Fast = await executeOcr(fastBaseDir.path, 'Fast');
    fastRuns.add(r2Fast);
    print('   Fast R2: ${r2Fast['elapsedMs']} ms | chars: ${r2Fast['charCount']}');

    // Round 3: Fast then Best
    print('👉 Round 3: Running Fast...');
    final r3Fast = await executeOcr(fastBaseDir.path, 'Fast');
    fastRuns.add(r3Fast);
    print('   Fast R3: ${r3Fast['elapsedMs']} ms | chars: ${r3Fast['charCount']}');

    print('👉 Round 3: Running Best...');
    final r3Best = await executeOcr(bestBaseDir.path, 'Best');
    bestRuns.add(r3Best);
    print('   Best R3: ${r3Best['elapsedMs']} ms | chars: ${r3Best['charCount']}');

    // Preserve all 6 raw outputs in isolated test output directory
    final outDir = Directory('${cacheDir.path}/ab_test_outputs');
    if (!await outDir.exists()) await outDir.create(recursive: true);

    for (int i = 0; i < 3; i++) {
      await File('${outDir.path}/raw_fast_run_${i + 1}.txt')
          .writeAsString(fastRuns[i]['text'] as String);
      await File('${outDir.path}/raw_best_run_${i + 1}.txt')
          .writeAsString(bestRuns[i]['text'] as String);
    }

    // Print summary metrics to logcat
    final fastTimes = fastRuns.map((r) => r['elapsedMs'] as int).toList()..sort();
    final bestTimes = bestRuns.map((r) => r['elapsedMs'] as int).toList()..sort();

    print('\n📊 [EMPIRICAL TIME AUDIT ON SAMSUNG GALAXY M32]');
    print('   Candidate A (Fast) Times: $fastTimes ms (Median: ${fastTimes[1]} ms)');
    print('   Candidate B (Best) Times: $bestTimes ms (Median: ${bestTimes[1]} ms)');
    print('   Fast Final Length: ${fastRuns.last['charCount']} characters');
    print('   Best Final Length: ${bestRuns.last['charCount']} characters');

    // Print full raw outputs to logcat for exact CER/WER evaluation
    print('\n================== [FULL RAW OCR OUTPUT: FAST] ==================');
    print(fastRuns.last['text']);
    print('================== [END RAW OCR OUTPUT: FAST] ==================');

    print('\n================== [FULL RAW OCR OUTPUT: BEST] ==================');
    print(bestRuns.last['text']);
    print('================== [END RAW OCR OUTPUT: BEST] ==================');

    print('\n✅ [A/B TEST SUCCESSFULLY COMPLETED ON GALAXY M32]');
  });
}
