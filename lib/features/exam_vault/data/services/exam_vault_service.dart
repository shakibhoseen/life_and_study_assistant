import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/services/export/app_export_service.dart';
import '../models/exam_application.dart';

class ExamVaultService {
  ExamVaultService._();
  static final ExamVaultService instance = ExamVaultService._();

  static const String _folderName = 'exam_vault';
  static const String _fileName = 'applications.json';
  static const String _attachmentsFolder = 'attachments';

  /// Returns the base directory for exam vault data
  Future<Directory> _getVaultDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final vaultDir = Directory(p.join(appDir.path, _folderName));
    if (!await vaultDir.exists()) {
      await vaultDir.create(recursive: true);
    }
    return vaultDir;
  }

  /// Returns the directory for storing saved PDFs
  Future<Directory> _getAttachmentsDirectory() async {
    final vaultDir = await _getVaultDirectory();
    final attachDir = Directory(p.join(vaultDir.path, _attachmentsFolder));
    if (!await attachDir.exists()) {
      await attachDir.create(recursive: true);
    }
    return attachDir;
  }

  /// Loads all saved exam applications from local JSON file
  Future<List<ExamApplication>> loadApplications() async {
    try {
      final vaultDir = await _getVaultDirectory();
      final file = File(p.join(vaultDir.path, _fileName));
      if (!await file.exists()) {
        return [];
      }

      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];

      final List decoded = jsonDecode(content);
      final list = decoded
          .map((item) => ExamApplication.fromJson(item as Map<String, dynamic>))
          .toList();

      // Sort: upcoming exams first, then newest applications
      list.sort((a, b) {
        if (a.examDate != null && b.examDate != null) {
          return a.examDate!.compareTo(b.examDate!);
        }
        if (a.examDate != null) return -1;
        if (b.examDate != null) return 1;
        return b.createdAt.compareTo(a.createdAt);
      });

      return list;
    } catch (e) {
      debugPrint('Error loading exam applications: $e');
      return [];
    }
  }

  /// Saves the complete list of exam applications to local storage
  Future<bool> saveApplications(List<ExamApplication> applications) async {
    try {
      final vaultDir = await _getVaultDirectory();
      final file = File(p.join(vaultDir.path, _fileName));
      final encoded = jsonEncode(applications.map((a) => a.toJson()).toList());
      await file.writeAsString(encoded, flush: true);
      return true;
    } catch (e) {
      debugPrint('Error saving exam applications: $e');
      return false;
    }
  }

  /// Copies a user-selected PDF into the app's secure internal vault directory
  /// so it is permanently preserved even if deleted from the phone's Download folder.
  Future<String?> copyDocumentToVault({
    required String sourcePath,
    required String examId,
    required String docType, // 'applicant_copy' or 'admit_card'
  }) async {
    try {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        debugPrint('Source file does not exist: $sourcePath');
        return null;
      }

      final attachDir = await _getAttachmentsDirectory();
      final extension = p.extension(sourcePath);
      final cleanExamId = examId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final targetFileName =
          '${cleanExamId}_${docType}_${DateTime.now().millisecondsSinceEpoch}$extension';
      final targetPath = p.join(attachDir.path, targetFileName);

      final copiedFile = await sourceFile.copy(targetPath);
      debugPrint('Document safely copied to vault: ${copiedFile.path}');
      return copiedFile.path;
    } catch (e) {
      debugPrint('Error copying document to vault: $e');
      return null;
    }
  }

  /// Opens a local document file using native viewer (PDF viewer, etc.)
  Future<OpenResult> openDocument(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return OpenResult(
          type: ResultType.fileNotFound,
          message: 'File not found at $filePath',
        );
      }
      return await OpenFilex.open(filePath);
    } catch (e) {
      debugPrint('Error opening document: $e');
      return OpenResult(
        type: ResultType.error,
        message: e.toString(),
      );
    }
  }

  /// Safely deletes a document file from storage
  Future<void> deleteDocument(String? filePath) async {
    if (filePath == null || filePath.isEmpty) return;
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Error deleting document file: $e');
    }
  }

  static const String masterBackupFileName = 'ExamVault_Latest_Backup.json';
  static const String previousBackupFileName = 'ExamVault_Previous_Backup.json';

  /// Generates the standard JSON string for backup
  String createBackupJsonString(List<ExamApplication> applications) {
    final data = {
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'count': applications.length,
      'applications': applications.map((a) => a.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// Exports all exam applications into a rolling dual-backup system:
  /// 1. ExamVault_Latest_Backup.json (Always the current newest master backup)
  /// 2. ExamVault_Previous_Backup.json (Safety copy of previous backup before overwrite)
  Future<File?> exportBackupToFile(List<ExamApplication> applications) async {
    try {
      final exportDir = await AppExportService.getExportDirectory(
        subfolder: 'LifeAndStudyAssistant/ExamVault',
      );

      final latestFile = File(p.join(exportDir.path, masterBackupFileName));
      final previousFile = File(p.join(exportDir.path, previousBackupFileName));

      // Rolling safety step: if Latest already exists, preserve it as Previous backup!
      if (await latestFile.exists()) {
        try {
          await latestFile.copy(previousFile.path);
          debugPrint('Previous backup safely preserved at: ${previousFile.path}');
        } catch (e) {
          debugPrint('Could not rotate previous backup: $e');
        }
      }

      final jsonContent = createBackupJsonString(applications);
      await latestFile.writeAsString(jsonContent, flush: true);
      return latestFile;
    } catch (e) {
      debugPrint('Error exporting backup to file: $e');
      return null;
    }
  }

  /// Shares backup file to Google Drive or other cloud storage via native share sheet
  Future<void> shareBackupToDrive(File file) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Exam Vault Backup (Google Drive)',
          text: 'Life & Study Assistant - Exam & Credential Vault Backup',
        ),
      );
    } catch (e) {
      debugPrint('Error sharing backup to drive: $e');
    }
  }

  /// Imports applications from a JSON backup string and merges them with existing applications.
  Future<List<ExamApplication>> importBackupFromJson(
    String jsonString, {
    bool overwriteExisting = false,
  }) async {
    try {
      final decoded = jsonDecode(jsonString);
      final List rawList;
      if (decoded is List) {
        rawList = decoded;
      } else if (decoded is Map<String, dynamic> &&
          decoded['applications'] is List) {
        rawList = decoded['applications'] as List;
      } else {
        throw const FormatException('Invalid backup JSON format');
      }

      final imported = rawList
          .map((item) => ExamApplication.fromJson(item as Map<String, dynamic>))
          .toList();

      final existing = await loadApplications();
      final map = {for (final a in existing) a.id: a};

      for (final a in imported) {
        if (overwriteExisting || !map.containsKey(a.id)) {
          map[a.id] = a;
        }
      }

      final merged = map.values.toList();
      await saveApplications(merged);
      return merged;
    } catch (e) {
      debugPrint('Error importing applications from JSON: $e');
      rethrow;
    }
  }
}
