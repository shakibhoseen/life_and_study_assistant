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
  });
}
