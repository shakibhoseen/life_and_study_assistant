import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/features/exam_vault/data/models/exam_application.dart';
import 'package:life_and_study_assistant/features/exam_vault/data/services/exam_vault_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final Directory tempDir;
  MockPathProviderPlatform(this.tempDir);

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir.path;

  @override
  Future<String?> getDownloadsPath() async => tempDir.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('exam_vault_test_');
    PathProviderPlatform.instance = MockPathProviderPlatform(tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ExamApplication Model Tests', () {
    test('toJson and fromJson serializes and deserializes accurately', () {
      final app = ExamApplication(
        id: 'test_123',
        postName: 'Senior Officer',
        organization: 'Bangladesh Bank',
        userId: 'BBSO10982',
        password: 'PassSecret@99',
        rollNo: '102938',
        trackingNo: 'TRK-9988',
        portalUrl: 'https://erecruitment.bb.org.bd',
        feeAmount: 200,
        isPaid: true,
        transactionId: 'TXN987654',
        rawSms: 'Fee received for Senior Officer. User ID: BBSO10982, Password: PassSecret@99',
        applicantCopyPdfPath: '/path/to/applicant.pdf',
        admitCardPdfPath: '/path/to/admit.pdf',
        applicantCopyDriveFileId: 'drive_file_applicant_99',
        admitCardDriveFileId: 'drive_file_admit_88',
        status: 'admitIssued',
        applicationDate: DateTime(2026, 11, 1),
        examDate: DateTime(2026, 12, 15),
        examTime: '10:00 AM - 11:00 AM',
        venueAndSeat: 'Dhaka College, Room 304',
        notes: 'Bring 2 black ballpoint pens',
        createdAt: DateTime(2026, 11, 1),
        updatedAt: DateTime(2026, 11, 2),
      );

      final json = app.toJson();
      final roundtrip = ExamApplication.fromJson(json);

      expect(roundtrip.id, equals('test_123'));
      expect(roundtrip.postName, equals('Senior Officer'));
      expect(roundtrip.organization, equals('Bangladesh Bank'));
      expect(roundtrip.userId, equals('BBSO10982'));
      expect(roundtrip.password, equals('PassSecret@99'));
      expect(roundtrip.rollNo, equals('102938'));
      expect(roundtrip.status, equals('admitIssued'));
      expect(roundtrip.statusLabelBn, contains('অ্যাডমিট এসেছে'));
      expect(roundtrip.hasApplicantCopy, isTrue);
      expect(roundtrip.hasAdmitCard, isTrue);
      expect(roundtrip.isApplicantCopySyncedToDrive, isTrue);
      expect(roundtrip.isAdmitCardSyncedToDrive, isTrue);
      expect(roundtrip.applicantCopyDriveFileId, equals('drive_file_applicant_99'));
      expect(roundtrip.admitCardDriveFileId, equals('drive_file_admit_88'));
      expect(roundtrip.transactionId, equals('TXN987654'));
    });

    test('daysUntilExam calculates countdown properly', () {
      final now = DateTime.now();
      final inFiveDays = now.add(const Duration(days: 5));

      final app = ExamApplication(
        id: '1',
        postName: '46th BCS',
        organization: 'BPSC',
        userId: 'BPSC99',
        password: '123',
        examDate: inFiveDays,
        createdAt: now,
        updatedAt: now,
      );

      expect(app.daysUntilExam, equals(5));
    });

    test('SMS extraction patterns correctly identify User ID, Password and TxID', () {
      const sms = 'Congratulations Shakib Hossen! Payment received for post Senior Officer. '
          'User ID: BBSO98471, Password: SecretKey99, TxID: TXN887711. Keep this for admit card.';

      final userMatch = RegExp(r'User\s*(?:ID|Id)?[:\s]+([A-Za-z0-9_-]+)', caseSensitive: false)
          .firstMatch(sms);
      final passMatch = RegExp(r'(?:Password|Pass|PIN)[:\s]+([A-Za-z0-9_@#!]+)', caseSensitive: false)
          .firstMatch(sms);
      final txMatch = RegExp(r'(?:TxID|Transaction\s*ID|Txn\s*ID)[:\s]+([A-Za-z0-9_-]+)', caseSensitive: false)
          .firstMatch(sms);

      expect(userMatch?.group(1), equals('BBSO98471'));
      expect(passMatch?.group(1), equals('SecretKey99'));
      expect(txMatch?.group(1), equals('TXN887711'));
    });

    test('Real Teletalk SMS extracts Post, Org, User, Pass, Fee, and URL', () {
      const smsRajuk = 'Congrats! SHAMIMA NASRIN TITLY, payment completed for Assistant Director (Administration) of RAJUK through . User: 3V9BDTQC and Pass: E267432A. For more jobs, visit http://alljobs.teletalk.com.bd';

      final postOrg = RegExp(
        r'(?:completed\s+for|charged\s+for|applied\s+for|received\s+for|for)\s+(.+?)(?:\s+post)?\s+of\s+([A-Za-z0-9\s&.-]+?)(?:\s*[\.,]|through|\.|\n|$)',
        caseSensitive: false,
      ).firstMatch(smsRajuk);

      final user = RegExp(r'User(?:\s*ID)?[:\s]+([A-Za-z0-9_-]+)', caseSensitive: false).firstMatch(smsRajuk);
      final pass = RegExp(r'(?:Password|Pass)[:\s]+([A-Za-z0-9_@#!]+)', caseSensitive: false).firstMatch(smsRajuk);
      final url = RegExp(r'(https?://[^\s,]+)', caseSensitive: false).firstMatch(smsRajuk);

      expect(postOrg?.group(1)?.trim(), equals('Assistant Director (Administration)'));
      expect(postOrg?.group(2)?.trim(), equals('RAJUK'));
      expect(user?.group(1)?.trim(), equals('3V9BDTQC'));
      expect(pass?.group(1)?.trim(), equals('E267432A'));
      expect(url?.group(1)?.trim(), equals('http://alljobs.teletalk.com.bd'));

      const smsBogmc = 'Congrats! MD. SHAKIB HOSSAIN,payment completed for Assistant Manager(Administration) post of BOGMC. User ID: 6NFC2HJZ, Password: MVDKBAD1.';
      final postOrgBogmc = RegExp(
        r'(?:completed\s+for|charged\s+for|applied\s+for|received\s+for|for)\s+(.+?)(?:\s+post)?\s+of\s+([A-Za-z0-9\s&.-]+?)(?:\s*[\.,]|through|\.|\n|$)',
        caseSensitive: false,
      ).firstMatch(smsBogmc);
      final userBogmc = RegExp(r'User(?:\s*ID)?[:\s]+([A-Za-z0-9_-]+)', caseSensitive: false).firstMatch(smsBogmc);
      final passBogmc = RegExp(r'(?:Password|Pass)[:\s]+([A-Za-z0-9_@#!]+)', caseSensitive: false).firstMatch(smsBogmc);

      expect(postOrgBogmc?.group(1)?.trim(), equals('Assistant Manager(Administration)'));
      expect(postOrgBogmc?.group(2)?.trim(), equals('BOGMC'));
      expect(userBogmc?.group(1)?.trim(), equals('6NFC2HJZ'));
      expect(passBogmc?.group(1)?.trim(), equals('MVDKBAD1'));
    });
  });

  group('ExamVaultService Tests', () {
    test('saveApplications and loadApplications persist to disk', () async {
      final now = DateTime.now();
      final app1 = ExamApplication(
        id: 'app_1',
        postName: 'Assistant Director',
        organization: 'NSI',
        userId: 'NSI001',
        password: 'PassOne',
        createdAt: now,
        updatedAt: now,
      );
      final app2 = ExamApplication(
        id: 'app_2',
        postName: 'Senior Officer',
        organization: 'Bangladesh Bank',
        userId: 'BB002',
        password: 'PassTwo',
        createdAt: now,
        updatedAt: now,
      );

      final success = await ExamVaultService.instance.saveApplications([app1, app2]);
      expect(success, isTrue);

      final loaded = await ExamVaultService.instance.loadApplications();
      expect(loaded.length, equals(2));
      expect(loaded.any((a) => a.userId == 'NSI001'), isTrue);
      expect(loaded.any((a) => a.userId == 'BB002'), isTrue);
    });

    test('importBackupFromJson safely merges without losing existing applications', () async {
      final now = DateTime.now();
      final app1 = ExamApplication(
        id: 'app_existing',
        postName: 'Old Application',
        organization: 'BPSC',
        userId: 'OLD001',
        password: 'old',
        createdAt: now,
        updatedAt: now,
      );
      await ExamVaultService.instance.saveApplications([app1]);

      final backupJson = jsonEncode({
        'version': 1,
        'applications': [
          {
            'id': 'app_imported',
            'postName': 'Imported Exam',
            'organization': 'Railways',
            'userId': 'RLY99',
            'password': 'pass',
            'createdAt': now.toIso8601String(),
            'updatedAt': now.toIso8601String(),
          }
        ]
      });

      final merged = await ExamVaultService.instance.importBackupFromJson(backupJson);
      expect(merged.length, equals(2));
      expect(merged.any((a) => a.id == 'app_existing'), isTrue);
      expect(merged.any((a) => a.id == 'app_imported'), isTrue);
    });

    test('exportBackupToFile maintains rolling dual backup (Latest + Previous)', () async {
      final now = DateTime.now();
      final app1 = ExamApplication(
        id: '1',
        postName: 'Post 1',
        organization: 'Org 1',
        userId: 'U1',
        password: 'P1',
        createdAt: now,
        updatedAt: now,
      );

      // Export 1
      final file1 = await ExamVaultService.instance.exportBackupToFile([app1]);
      expect(file1, isNotNull);
      expect(file1!.path, contains(ExamVaultService.masterBackupFileName));
      expect(await file1.exists(), isTrue);

      final app2 = ExamApplication(
        id: '2',
        postName: 'Post 2',
        organization: 'Org 2',
        userId: 'U2',
        password: 'P2',
        createdAt: now,
        updatedAt: now,
      );

      // Export 2
      final file2 = await ExamVaultService.instance.exportBackupToFile([app1, app2]);
      expect(file2, isNotNull);

      // Verify that Previous backup now exists containing app1!
      final prevFile = File(file2!.path.replaceAll(
        ExamVaultService.masterBackupFileName,
        ExamVaultService.previousBackupFileName,
      ));
      expect(await prevFile.exists(), isTrue);

      final prevContent = await prevFile.readAsString();
      expect(prevContent, contains('Post 1'));
      expect(prevContent, isNot(contains('Post 2')));

      final latestContent = await file2.readAsString();
      expect(latestContent, contains('Post 1'));
      expect(latestContent, contains('Post 2'));
    });

    test('exportFullBackupZip and importBackupFromZip bundles JSON and PDFs', () async {
      final now = DateTime.now();

      // Create a dummy PDF in temp
      final dummyPdf = File('${tempDir.path}/dummy_admit.pdf');
      await dummyPdf.writeAsString('%PDF-1.4 dummy admit card bytes');

      final app = ExamApplication(
        id: 'zip_test_1',
        postName: 'Assistant Director',
        organization: 'RAJUK',
        userId: '3V9BDT',
        password: 'Password@123',
        admitCardPdfPath: dummyPdf.path,
        createdAt: now,
        updatedAt: now,
      );

      final zipFile = await ExamVaultService.instance.exportFullBackupZip([app]);
      expect(zipFile, isNotNull);
      expect(await zipFile!.exists(), isTrue);
      expect(zipFile.path.endsWith('.zip'), isTrue);

      // Now import from zip
      final imported = await ExamVaultService.instance.importBackupFromZip(zipFile);
      expect(imported.length, equals(1));
      expect(imported.first.id, equals('zip_test_1'));
      expect(imported.first.organization, equals('RAJUK'));
    });
  });
}
