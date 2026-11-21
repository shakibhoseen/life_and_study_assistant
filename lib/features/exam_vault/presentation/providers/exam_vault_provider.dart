import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../data/models/exam_application.dart';
import '../../data/services/exam_vault_service.dart';
import '../../data/services/google_drive_vault_service.dart';

class ExamVaultState {
  final bool isLoading;
  final bool isSyncingDrive;
  final GoogleSignInAccount? googleUser;
  final List<ExamApplication> applications;
  final String searchQuery;
  final String selectedFilter; // 'all', 'admit_issued', 'upcoming', 'completed'
  final String? errorMessage;

  const ExamVaultState({
    this.isLoading = false,
    this.isSyncingDrive = false,
    this.googleUser,
    this.applications = const [],
    this.searchQuery = '',
    this.selectedFilter = 'all',
    this.errorMessage,
  });

  bool get isGoogleSignedIn => googleUser != null;

  List<ExamApplication> get filteredApplications {
    return applications.where((app) {
      // 1. Text Search Filter
      final q = searchQuery.trim().toLowerCase();
      if (q.isNotEmpty) {
        final matchPost = app.postName.toLowerCase().contains(q);
        final matchOrg = app.organization.toLowerCase().contains(q);
        final matchUser = app.userId.toLowerCase().contains(q);
        final matchRoll = app.rollNo?.toLowerCase().contains(q) ?? false;
        final matchSms = app.rawSms?.toLowerCase().contains(q) ?? false;
        if (!matchPost && !matchOrg && !matchUser && !matchRoll && !matchSms) {
          return false;
        }
      }

      // 2. Status / Category Filter
      switch (selectedFilter) {
        case 'admit_issued':
          return app.status == 'admitIssued' || app.hasAdmitCard;
        case 'upcoming':
          return (app.examDate != null &&
                  app.examDate!.isAfter(
                    DateTime.now().subtract(const Duration(days: 1)),
                  )) ||
              app.status == 'examScheduled';
        case 'completed':
          return app.status == 'completed' || app.status == 'passed';
        case 'all':
        default:
          return true;
      }
    }).toList();
  }

  int get upcomingExamsCount {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return applications.where((a) {
      if (a.examDate == null) return false;
      final d = DateTime(a.examDate!.year, a.examDate!.month, a.examDate!.day);
      return !d.isBefore(today);
    }).length;
  }

  int get admitCardAvailableCount {
    return applications
        .where((a) => a.hasAdmitCard || a.status == 'admitIssued')
        .length;
  }

  ExamVaultState copyWith({
    bool? isLoading,
    bool? isSyncingDrive,
    GoogleSignInAccount? googleUser,
    bool clearGoogleUser = false,
    List<ExamApplication>? applications,
    String? searchQuery,
    String? selectedFilter,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ExamVaultState(
      isLoading: isLoading ?? this.isLoading,
      isSyncingDrive: isSyncingDrive ?? this.isSyncingDrive,
      googleUser: clearGoogleUser ? null : (googleUser ?? this.googleUser),
      applications: applications ?? this.applications,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedFilter: selectedFilter ?? this.selectedFilter,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class ExamVaultNotifier extends Notifier<ExamVaultState> {
  @override
  ExamVaultState build() {
    Future.microtask(() async {
      await loadApplications();
      await initGoogleAuth();
    });
    return const ExamVaultState(isLoading: true);
  }

  Future<void> initGoogleAuth() async {
    try {
      final user = await GoogleDriveVaultService.instance.signInSilently();
      if (user != null) {
        state = state.copyWith(googleUser: user);
        await autoSyncOrRestore(isSilent: true);
      }
    } catch (_) {}
  }

  Future<GoogleSignInAccount?> signInGoogle() async {
    try {
      state = state.copyWith(isSyncingDrive: true, clearError: true);
      final user = await GoogleDriveVaultService.instance.signIn();
      state = state.copyWith(isSyncingDrive: false, googleUser: user);
      if (user != null) {
        await autoSyncOrRestore(isSilent: false);
      }
      return user;
    } catch (e) {
      state = state.copyWith(isSyncingDrive: false, errorMessage: e.toString());
      rethrow;
    }
  }

  /// Automatically synchronizes local vault data with Google Drive on sign-in / app start.
  /// - Downloads and merges any existing backup from Drive (ExamVault folder).
  /// - Uploads local applications and PDF documents to Drive.
  Future<void> autoSyncOrRestore({bool isSilent = false}) async {
    if (!GoogleDriveVaultService.instance.isSignedIn) return;

    try {
      if (!isSilent) {
        state = state.copyWith(isSyncingDrive: true, clearError: true);
      }

      // Check if Drive has an existing backup in ExamVault folder
      final driveBackupJson =
          await GoogleDriveVaultService.instance.downloadBackupFromDrive();

      if (driveBackupJson != null && driveBackupJson.trim().isNotEmpty) {
        final mergedCount = await importBackup(driveBackupJson);
        debugPrint(
            'Auto-sync: successfully imported/merged $mergedCount applications from Google Drive');
      }

      // Ensure Drive is updated with current local data & PDFs
      await syncToGoogleDrive();

      if (!isSilent) {
        state = state.copyWith(isSyncingDrive: false);
      }
    } catch (e) {
      debugPrint('AutoSyncOrRestore error: $e');
      if (!isSilent) {
        state = state.copyWith(isSyncingDrive: false);
      }
    }
  }

  void _triggerAutoSync() {
    if (GoogleDriveVaultService.instance.isSignedIn) {
      syncToGoogleDrive().catchError((e) {
        debugPrint('Auto background sync failed: $e');
        return (success: false, pdfCount: 0);
      });
    }
  }

  Future<void> setGoogleServerClientId(String? id) async {
    await GoogleDriveVaultService.instance.setServerClientId(id);
    await initGoogleAuth();
  }

  Future<void> signOutGoogle() async {
    await GoogleDriveVaultService.instance.signOut();
    state = state.copyWith(clearGoogleUser: true);
  }

  Future<({bool success, int pdfCount})> syncToGoogleDrive() async {
    try {
      state = state.copyWith(isSyncingDrive: true, clearError: true);

      // Step 1: Upload any local PDFs to Drive and get their Drive File IDs
      int pdfCount = 0;
      final updatedApps = <ExamApplication>[];

      for (final app in state.applications) {
        var modifiedApp = app;

        // Check applicant copy
        if (app.applicantCopyPdfPath != null &&
            app.applicantCopyPdfPath!.isNotEmpty) {
          final file = File(app.applicantCopyPdfPath!);
          if (await file.exists()) {
            final cleanOrg = app.organization
                .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
            final cleanPost =
                app.postName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
            final cleanUser =
                app.userId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
            final remoteName =
                '${cleanOrg}_${cleanPost}_${cleanUser}_applicant_copy.pdf';

            final driveId =
                await GoogleDriveVaultService.instance.uploadPdfFile(
              file: file,
              remoteFileName: remoteName,
            );
            if (driveId != null) {
              modifiedApp =
                  modifiedApp.copyWith(applicantCopyDriveFileId: driveId);
              pdfCount++;
            }
          }
        }

        // Check admit card
        if (app.admitCardPdfPath != null && app.admitCardPdfPath!.isNotEmpty) {
          final file = File(app.admitCardPdfPath!);
          if (await file.exists()) {
            final cleanOrg = app.organization
                .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
            final cleanPost =
                app.postName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
            final cleanUser =
                app.userId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
            final remoteName =
                '${cleanOrg}_${cleanPost}_${cleanUser}_admit_card.pdf';

            final driveId =
                await GoogleDriveVaultService.instance.uploadPdfFile(
              file: file,
              remoteFileName: remoteName,
            );
            if (driveId != null) {
              modifiedApp =
                  modifiedApp.copyWith(admitCardDriveFileId: driveId);
              pdfCount++;
            }
          }
        }

        updatedApps.add(modifiedApp);
      }

      // Save locally with updated Drive IDs
      await ExamVaultService.instance.saveApplications(updatedApps);

      // Step 2: Upload rolling JSON backup (contains all metadata + PDF Drive file IDs)
      final jsonContent =
          ExamVaultService.instance.createBackupJsonString(updatedApps);
      final success =
          await GoogleDriveVaultService.instance.syncBackupToDrive(jsonContent);

      state = state.copyWith(
        isSyncingDrive: false,
        applications: updatedApps,
        googleUser: GoogleDriveVaultService.instance.currentUser,
      );
      return (success: success, pdfCount: pdfCount);
    } catch (e) {
      state = state.copyWith(isSyncingDrive: false, errorMessage: e.toString());
      rethrow;
    }
  }

  /// Downloads a PDF document from Google Drive if the local file is missing
  Future<File?> downloadPdfDocument(
    String examId, {
    required bool isAdmitCard,
  }) async {
    try {
      final appIndex = state.applications.indexWhere((a) => a.id == examId);
      if (appIndex == -1) return null;
      final app = state.applications[appIndex];

      final driveFileId = isAdmitCard
          ? app.admitCardDriveFileId
          : app.applicantCopyDriveFileId;
      if (driveFileId == null || driveFileId.isEmpty) return null;

      final docType = isAdmitCard ? 'admit_card' : 'applicant_copy';
      final localPath =
          await ExamVaultService.instance.getLocalPdfPathForDownload(
        examId: examId,
        docType: docType,
      );

      final downloaded =
          await GoogleDriveVaultService.instance.downloadPdfFile(
        fileId: driveFileId,
        localDestinationPath: localPath,
      );

      if (downloaded != null) {
        // Update application local path
        final updatedApp = isAdmitCard
            ? app.copyWith(admitCardPdfPath: downloaded.path)
            : app.copyWith(applicantCopyPdfPath: downloaded.path);

        final updatedList = List<ExamApplication>.from(state.applications);
        updatedList[appIndex] = updatedApp;
        await ExamVaultService.instance.saveApplications(updatedList);
        state = state.copyWith(applications: updatedList);
      }

      return downloaded;
    } catch (e) {
      debugPrint('Error downloading PDF from Drive: $e');
      return null;
    }
  }

  Future<int> restoreFromGoogleDrive({bool usePrevious = false}) async {
    try {
      state = state.copyWith(isSyncingDrive: true, clearError: true);
      final jsonContent = await GoogleDriveVaultService.instance
          .downloadBackupFromDrive(usePrevious: usePrevious);
      if (jsonContent == null) {
        state = state.copyWith(isSyncingDrive: false);
        return 0;
      }
      final count = await importBackup(jsonContent);
      state = state.copyWith(
        isSyncingDrive: false,
        googleUser: GoogleDriveVaultService.instance.currentUser,
      );
      return count;
    } catch (e) {
      state = state.copyWith(isSyncingDrive: false, errorMessage: e.toString());
      rethrow;
    }
  }

  Future<void> loadApplications() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final list = await ExamVaultService.instance.loadApplications();
      state = state.copyWith(isLoading: false, applications: list);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> addApplication(ExamApplication app) async {
    final updated = [app, ...state.applications];
    await ExamVaultService.instance.saveApplications(updated);
    state = state.copyWith(applications: updated);
    _triggerAutoSync();
  }

  Future<void> updateApplication(ExamApplication app) async {
    final updated = state.applications.map((a) {
      return a.id == app.id ? app : a;
    }).toList();
    await ExamVaultService.instance.saveApplications(updated);
    state = state.copyWith(applications: updated);
    _triggerAutoSync();
  }

  Future<void> deleteApplication(String id) async {
    final target = state.applications.firstWhere((a) => a.id == id);
    if (target.applicantCopyPdfPath != null) {
      await ExamVaultService.instance
          .deleteDocument(target.applicantCopyPdfPath);
    }
    if (target.admitCardPdfPath != null) {
      await ExamVaultService.instance.deleteDocument(target.admitCardPdfPath);
    }

    final updated = state.applications.where((a) => a.id != id).toList();
    await ExamVaultService.instance.saveApplications(updated);
    state = state.copyWith(applications: updated);
    _triggerAutoSync();
  }

  Future<void> updateStatus(String id, String newStatus) async {
    final updated = state.applications.map((a) {
      if (a.id == id) {
        return a.copyWith(status: newStatus, updatedAt: DateTime.now());
      }
      return a;
    }).toList();
    await ExamVaultService.instance.saveApplications(updated);
    state = state.copyWith(applications: updated);
    _triggerAutoSync();
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void setSelectedFilter(String filter) {
    state = state.copyWith(selectedFilter: filter);
  }

  Future<File?> exportBackup() async {
    return await ExamVaultService.instance
        .exportBackupToFile(state.applications);
  }

  Future<File?> exportFullBackupZip() async {
    return await ExamVaultService.instance
        .exportFullBackupZip(state.applications);
  }

  Future<int> importBackup(String jsonString) async {
    final merged =
        await ExamVaultService.instance.importBackupFromJson(jsonString);
    state = state.copyWith(applications: merged);
    return merged.length;
  }

  Future<int> importBackupFromFile(File file) async {
    final isZip = file.path.toLowerCase().endsWith('.zip');
    List<ExamApplication> merged;
    if (isZip) {
      merged = await ExamVaultService.instance.importBackupFromZip(file);
    } else {
      final content = await file.readAsString();
      merged = await ExamVaultService.instance.importBackupFromJson(content);
    }
    state = state.copyWith(applications: merged);
    return merged.length;
  }
}

final examVaultProvider =
    NotifierProvider<ExamVaultNotifier, ExamVaultState>(ExamVaultNotifier.new);
