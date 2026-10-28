import 'package:flutter/material.dart';

import '../../../../core/database/app_database.dart';

/// Categorization of the origin of an exam schedule item.
enum ExamSourceKind {
  /// Imported from official PDF or digital routine schedule.
  pdfImport,

  /// Manually created by the user in the app.
  manual,

  /// Created through AI Mentor's `ADD_EXAM` action.
  aiMentor,

  /// AI-generated study sessions from `ROUTINE_PLAN`.
  aiStudyPlan,
}

/// Structured source metadata and display configuration.
class ExamSourceInfo {
  final ExamSourceKind kind;
  final String label;
  final IconData icon;

  const ExamSourceInfo({
    required this.kind,
    required this.label,
    required this.icon,
  });

  /// Identifies the source of an exam without guessing or assuming legacy
  /// records without metadata were AI-created.
  static ExamSourceInfo? resolve(ExamSchedule exam) {
    final raw = exam.rawReference?.trim() ?? '';
    final summary = exam.resourceSummary?.trim() ?? '';

    // 1. AI-generated study sessions from ROUTINE_PLAN
    // Distinguished by examType == 'Study Session' or explicit routine plan tags.
    if (exam.examType == 'Study Session' ||
        raw == 'AI Mentor Plan' ||
        raw == 'ai_study_plan' ||
        summary == 'AI Mentor Plan' ||
        summary == 'AI Study Plan') {
      return const ExamSourceInfo(
        kind: ExamSourceKind.aiStudyPlan,
        label: 'AI Study Plan',
        icon: Icons.auto_stories,
      );
    }

    // 2. Exam created through AI Mentor ADD_EXAM
    if (raw == 'ai_mentor' ||
        raw == 'AI Mentor' ||
        summary == 'AI Mentor' ||
        raw.startsWith('AI Mentor:')) {
      return const ExamSourceInfo(
        kind: ExamSourceKind.aiMentor,
        label: 'AI Mentor',
        icon: Icons.smart_toy_outlined,
      );
    }

    // 3. Manually created exam
    if (raw == 'manual' ||
        raw == 'নিজে যোগ করেছেন' ||
        summary == 'নিজে যোগ করেছেন') {
      return const ExamSourceInfo(
        kind: ExamSourceKind.manual,
        label: 'নিজে যোগ করেছেন',
        icon: Icons.person_outline,
      );
    }

    // 4. PDF / imported official routine
    if (raw.startsWith('PDF:') ||
        raw.startsWith('Image:') ||
        raw.startsWith('JSON import') ||
        summary.startsWith('Imported routine') ||
        raw.startsWith('Imported')) {
      // Preserve and display the existing import source
      String label = raw;
      if (label.isEmpty) {
        label = summary;
      }
      if (label.length > 28) {
        label = '${label.substring(0, 26)}…';
      }
      return ExamSourceInfo(
        kind: ExamSourceKind.pdfImport,
        label: label,
        icon: Icons.description_outlined,
      );
    }

    // 5. Existing records with missing source metadata
    // "Do not infer that an old record was AI-created."
    return null;
  }
}
