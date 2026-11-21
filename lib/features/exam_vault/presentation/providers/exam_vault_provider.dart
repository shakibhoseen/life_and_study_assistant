import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/exam_application.dart';
import '../../data/services/exam_vault_service.dart';

class ExamVaultState {
  final bool isLoading;
  final List<ExamApplication> applications;
  final String searchQuery;
  final String selectedFilter; // 'all', 'admit_issued', 'upcoming', 'completed'
  final String? errorMessage;

  const ExamVaultState({
    this.isLoading = false,
    this.applications = const [],
    this.searchQuery = '',
    this.selectedFilter = 'all',
    this.errorMessage,
  });

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
    List<ExamApplication>? applications,
    String? searchQuery,
    String? selectedFilter,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ExamVaultState(
      isLoading: isLoading ?? this.isLoading,
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
    Future.microtask(() => loadApplications());
    return const ExamVaultState(isLoading: true);
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
  }

  Future<void> updateApplication(ExamApplication app) async {
    final updated = state.applications.map((a) {
      return a.id == app.id ? app : a;
    }).toList();
    await ExamVaultService.instance.saveApplications(updated);
    state = state.copyWith(applications: updated);
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

  Future<int> importBackup(String jsonString) async {
    final merged =
        await ExamVaultService.instance.importBackupFromJson(jsonString);
    state = state.copyWith(applications: merged);
    return merged.length;
  }
}

final examVaultProvider =
    NotifierProvider<ExamVaultNotifier, ExamVaultState>(ExamVaultNotifier.new);
