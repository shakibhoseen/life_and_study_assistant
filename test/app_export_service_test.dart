import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/services/export/app_export_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('export_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall methodCall) async => tempDir.path,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('AppExportService Tests', () {
    test(
      'resolves a valid export directory and creates default subfolder',
      () async {
        final dir = await AppExportService.getExportDirectory(
          subfolder: 'TestExportFolder',
        );
        expect(dir, isNotNull);
        expect(await dir.exists(), isTrue);
        expect(dir.path.contains('TestExportFolder'), isTrue);
      },
    );

    test(
      'saveToDownloads successfully creates and writes exported file',
      () async {
        const fileName = 'test_backup_export.json';
        const content = '{"test": "data", "count": 42}';

        final result = await AppExportService.saveToDownloads(
          fileName: fileName,
          content: content,
          subfolder: 'TestExports',
        );

        expect(result.success, isTrue);
        expect(result.filePath, isNotNull);
        expect(result.displayLocation, isNotNull);
        expect(result.wasCancelled, isFalse);

        final file = File(result.filePath!);
        expect(await file.exists(), isTrue);
        expect(await file.readAsString(), equals(content));
      },
    );

    test('ExportResult formats clear user-facing Bengali summary', () {
      const successResult = ExportResult(
        success: true,
        filePath:
            '/storage/emulated/0/Download/LifeAndStudyAssistant/backup.json',
        displayLocation: 'Download/LifeAndStudyAssistant/backup.json',
      );

      final summary = successResult.bengaliSummary;
      expect(summary.contains('সফলভাবে সেভ হয়েছে'), isTrue);
      expect(
        summary.contains('Download/LifeAndStudyAssistant/backup.json'),
        isTrue,
      );
      expect(summary.contains('File Manager'), isTrue);

      const cancelResult = ExportResult(success: false, wasCancelled: true);
      expect(cancelResult.bengaliSummary.contains('বাতিল'), isTrue);

      const errorResult = ExportResult(
        success: false,
        errorMessage: 'Storage full',
      );
      expect(errorResult.bengaliSummary.contains('Storage full'), isTrue);
    });
  });
}
