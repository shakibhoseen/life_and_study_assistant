import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../core/services/ai/ai_cancellation.dart';
import '../../../../core/services/ai/entity_ref.dart';
import '../../../../core/services/ai/gemini_ai_service.dart';
import '../../../../core/services/ai/gemini_prompts.dart';
import '../../../../core/services/ai/models/study_sheet_summary.dart';
import '../../../../core/services/ai/routine_parser_service.dart';
import '../../../../core/services/ai/models/quiz_question.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/services/calendar/calendar_sync_service.dart';
import '../../../../core/services/ai/quiz_generator_service.dart';
import '../../../../core/services/ai/voice_mistake_parser_service.dart';
import '../../../quiz/presentation/providers/drill_history_provider.dart';
import '../../../quiz/presentation/widgets/quiz_drill_modal.dart';
import '../../../quiz/presentation/widgets/question_bank_scanner_modal.dart';
import '../../../spaced_repetition/presentation/providers/spaced_repetition_provider.dart';
import '../../../topics/presentation/providers/topics_provider.dart';
import '../../domain/models/exam_source_info.dart';
import '../../../settings/presentation/screens/settings_screen.dart';
import '../providers/exam_schedule_provider.dart';
import '../widgets/exam_source_badge.dart';
import '../widgets/live_mcq_timeline_filter_bar.dart';
import '../widgets/live_mcq_track_filter_bar.dart';
import '../widgets/study_sheet_summary_card.dart';
import '../../../../core/widgets/animated_premium_background.dart';
import '../widgets/test_paper_card_summary.dart';
import '../widgets/voice_mistake_bottom_sheet.dart';
import '../widgets/exam_topic_checklist_widget.dart';
import '../widgets/exam_score_analytics_card.dart';
import '../../../focus/presentation/screens/pomodoro_focus_screen.dart';
import '../../../../core/services/quiz/bcs_question_bank_service.dart';

class LiveMcqScreen extends ConsumerStatefulWidget {
  const LiveMcqScreen({super.key});

  @override
  ConsumerState<LiveMcqScreen> createState() => _LiveMcqScreenState();
}

class _LiveMcqScreenState extends ConsumerState<LiveMcqScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _studySheetController = TextEditingController();
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  bool _isSummarizing = false;
  StudySheetSummary? _summaryResult;
  AiCancellation? _summaryCancellation;
  Timer? _summaryTicker;
  int _summarySeconds = 0;
  final Set<int> _expandedTestPaperExams = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _summaryTicker?.cancel();
    _summaryCancellation?.cancel();
    _tabController.dispose();
    _studySheetController.dispose();
    _subjectController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'LiveMCQ Hub',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.quiz_outlined,
              color: Color(0xFFF59E0B),
            ),
            tooltip: 'বিসিএস প্রশ্ন ব্যাংক প্র্যাকটিস',
            onPressed: () => _openBcsQuestionBank(context),
          ),
          IconButton(
            icon: const Icon(
              Icons.document_scanner_outlined,
              color: Color(0xFF10B981),
            ),
            tooltip: 'প্রশ্ন ব্যাংক স্ক্যান করে এক্সাম তৈরি',
            onPressed: () => QuestionBankScannerModal.show(context),
          ),
          IconButton(
            icon: const Icon(Icons.mic, color: Color(0xFF6366F1)),
            tooltip: 'Voice Mistake Note & Floating Bubble',
            onPressed: () => VoiceMistakeBottomSheet.show(context),
          ),
          IconButton(
            icon: const Icon(Icons.calendar_month),
            tooltip: 'Export Track Schedule to Calendar (.ics)',
            onPressed: () => _exportCurrentTrackToIcs(context),
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'PDF ইম্পোর্ট (রুটিন বা পড়ার লেকচার শিট)',
            onPressed: () => _showPdfOptionsSheet(context),
          ),
          IconButton(
            icon: const Icon(Icons.playlist_add),
            tooltip: 'Import Routine (AI / Text / JSON)',
            onPressed: () => _showImportRoutineDialog(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.event_note), text: 'পরীক্ষার সূচি'),
            Tab(icon: Icon(Icons.summarize), text: 'পড়ার সারাংশ'),
          ],
        ),
      ),
      body: Stack(
        children: [
          const Positioned.fill(
            child: AnimatedGradientBackground(child: SizedBox.expand()),
          ),
          const FloatingOrb(top: 30, right: -40, size: 260, opacity: 0.16),
          const FloatingOrb(bottom: 60, left: -40, size: 220, opacity: 0.13),
          TabBarView(
            controller: _tabController,
            children: [_buildSchedulesTab(), _buildSummarizerTab()],
          ),
        ],
      ),
      floatingActionButton: _tabController.index == 0
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.small(
                  heroTag: 'fab_scan_qb_mcq',
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  tooltip: 'প্রশ্ন ব্যাংক স্ক্যান করে এক্সাম',
                  onPressed: () => QuestionBankScannerModal.show(context),
                  child: const Icon(Icons.document_scanner_outlined, size: 20),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.small(
                  heroTag: 'fab_screenshot_mistake_mcq',
                  backgroundColor: const Color(0xFF0284C7),
                  foregroundColor: Colors.white,
                  tooltip: 'LiveMCQ স্ক্রিনশট থেকে ভুল সেভ',
                  onPressed: () => _pickAndParseScreenshotMistake(context),
                  child: const Icon(Icons.add_photo_alternate_rounded, size: 20),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.small(
                  heroTag: 'fab_voice_bubble_mcq',
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  tooltip: 'Voice Mistake Note & Floating Bubble',
                  onPressed: () => VoiceMistakeBottomSheet.show(context),
                  child: const Icon(Icons.mic, size: 20),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.extended(
                  heroTag: 'fab_add_exam_mcq',
                  icon: const Icon(Icons.add),
                  label: const Text('Add Exam'),
                  onPressed: () => _showAddExamDialog(context),
                ),
              ],
            )
          : null,
    );
  }

  Future<void> _openBcsQuestionBank(BuildContext context) async {
    final questions = await BcsQuestionBankService.loadAllQuestions();
    if (!context.mounted) return;
    if (questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('প্রশ্ন ব্যাংক লোড করা যায়নি')),
      );
      return;
    }
    QuizDrillModal.show(
      context,
      topic: 'বিসিএস মূল প্রশ্ন সমাধান',
      subject: 'বিসিএস প্রশ্ন ব্যাংক',
      customQuestions: questions,
    );
  }

  void _copyExamRef(int examId) {
    final tag = EntityRef(EntityKind.exam, examId).tag;
    Clipboard.setData(ClipboardData(text: tag));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$tag কপি হয়েছে — AI মেন্টরে পেস্ট করে বলুন কী সমস্যা'),
      ),
    );
  }

  String _formatExamDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final monthStr = months[date.month - 1];
    final dayStr = date.day.toString().padLeft(2, '0');
    final weekdayStr = weekdays[date.weekday - 1];
    return '$dayStr $monthStr ($weekdayStr)';
  }

  Widget _buildSchedulesTab() {
    final selectedTrack = ref.watch(selectedTrackProvider);
    final tracksAsync = ref.watch(distinctTracksStreamProvider);
    final examsAsync = ref.watch(filteredExamsStreamProvider);
    final currentTimelineFilter = ref.watch(examTimelineFilterProvider);
    final searchQuery = ref.watch(examSearchQueryProvider).trim().toLowerCase();

    return Column(
      children: [
        _buildTrackFilterBar(tracksAsync, selectedTrack),
        Expanded(
          child: examsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => Center(child: Text('Error: $err')),
            data: (rawExams) {
              if (rawExams.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.event_busy,
                        size: 64,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        selectedTrack == 'All'
                            ? 'No LiveMCQ exams scheduled'
                            : 'No exams found under "$selectedTrack"',
                        style: const TextStyle(color: Colors.grey),
                      ),
                      if (selectedTrack != 'All') ...[
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () {
                            ref
                                .read(selectedTrackProvider.notifier)
                                .setTrack('All');
                          },
                          child: const Text('Show All Programs'),
                        ),
                      ],
                    ],
                  ),
                );
              }

              // Apply search query filter if user typed anything
              final exams = searchQuery.isEmpty
                  ? rawExams
                  : rawExams.where((e) {
                      final titleMatch = e.title.toLowerCase().contains(
                        searchQuery,
                      );
                      final topicMatch = e.topicsCovered.toLowerCase().contains(
                        searchQuery,
                      );
                      final trackMatch = e.trackName.toLowerCase().contains(
                        searchQuery,
                      );
                      return titleMatch || topicMatch || trackMatch;
                    }).toList();

              // Partition into Upcoming, Past, and Completed
              final now = DateTime.now();
              final todayStart = DateTime(now.year, now.month, now.day);

              final upcomingExams = <ExamSchedule>[];
              final pastExams = <ExamSchedule>[];
              final completedExams = <ExamSchedule>[];

              for (final exam in exams) {
                if (exam.completedStatus) {
                  completedExams.add(exam);
                } else {
                  final examDateOnly = DateTime(
                    exam.examDate.year,
                    exam.examDate.month,
                    exam.examDate.day,
                  );
                  final daysDiff = examDateOnly.difference(todayStart).inDays;
                  if (daysDiff >= 0) {
                    upcomingExams.add(exam);
                  } else {
                    pastExams.add(exam);
                  }
                }
              }

              // Sort upcoming: ASCENDING (today first, then tomorrow, then upcoming dates)
              upcomingExams.sort((a, b) => a.examDate.compareTo(b.examDate));

              // Sort past: DESCENDING (most recent first: yesterday, 2 days ago, then older)
              pastExams.sort((a, b) => b.examDate.compareTo(a.examDate));

              // Sort completed: DESCENDING
              completedExams.sort((a, b) => b.examDate.compareTo(a.examDate));

              return Column(
                children: [
                  _buildTimelineFilterBar(
                    currentFilter: currentTimelineFilter,
                    upcomingCount: upcomingExams.length,
                    pastCount: pastExams.length,
                    completedCount: completedExams.length,
                    allCount: exams.length,
                  ),
                  Expanded(
                    child: _buildExamsListView(
                      currentFilter: currentTimelineFilter,
                      upcomingExams: upcomingExams,
                      pastExams: pastExams,
                      completedExams: completedExams,
                      todayStart: todayStart,
                      selectedTrack: selectedTrack,
                      searchQuery: searchQuery,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineFilterBar({
    required ExamTimelineFilter currentFilter,
    required int upcomingCount,
    required int pastCount,
    required int completedCount,
    required int allCount,
  }) {
    return LiveMcqTimelineFilterBar(
      searchController: _searchController,
      currentFilter: currentFilter,
      upcomingCount: upcomingCount,
      pastCount: pastCount,
      completedCount: completedCount,
      allCount: allCount,
      onFilterChanged: (filter) =>
          ref.read(examTimelineFilterProvider.notifier).setFilter(filter),
      onSearchChanged: (val) =>
          ref.read(examSearchQueryProvider.notifier).setQuery(val),
      onSearchClear: () {
        _searchController.clear();
        ref.read(examSearchQueryProvider.notifier).setQuery('');
      },
    );
  }

  Widget _buildExamsListView({
    required ExamTimelineFilter currentFilter,
    required List<ExamSchedule> upcomingExams,
    required List<ExamSchedule> pastExams,
    required List<ExamSchedule> completedExams,
    required DateTime todayStart,
    required String selectedTrack,
    required String searchQuery,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (currentFilter == ExamTimelineFilter.upcoming) {
      if (upcomingExams.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 56,
                  color: Colors.teal.shade400,
                ),
                const SizedBox(height: 12),
                Text(
                  'No upcoming exams right now!',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  pastExams.isNotEmpty
                      ? '${pastExams.length} past exams have already occurred or passed.'
                      : 'Add an exam or import a routine to get started.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark ? const Color(0xFF94A3B8) : Colors.grey,
                  ),
                ),
                if (pastExams.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDark
                          ? const Color(0xFF3B82F6)
                          : const Color(0xFF1E3A8A),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.history, size: 16),
                    label: Text('View Past Exams (${pastExams.length})'),
                    onPressed: () {
                      ref
                          .read(examTimelineFilterProvider.notifier)
                          .setFilter(ExamTimelineFilter.past);
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      }

      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
        itemCount: upcomingExams.length + (pastExams.isNotEmpty ? 1 : 0),
        itemBuilder: (context, index) {
          if (index < upcomingExams.length) {
            return _buildExamCard(upcomingExams[index], todayStart);
          }
          // Bottom archived hint banner
          return Container(
            margin: const EdgeInsets.only(top: 8, bottom: 20),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF334155)
                    : const Color(0xFFE2E8F0),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.history,
                    size: 16,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${pastExams.length} past exam(s) archived',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF334155),
                        ),
                      ),
                      Text(
                        'Older dates are archived so you can focus on upcoming tests.',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark
                        ? const Color(0xFF0F172A)
                        : Colors.white,
                    foregroundColor: isDark
                        ? const Color(0xFF93C5FD)
                        : const Color(0xFF1E3A8A),
                    elevation: 0,
                    side: BorderSide(
                      color: isDark
                          ? const Color(0xFF334155)
                          : const Color(0xFFCBD5E1),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: () {
                    ref
                        .read(examTimelineFilterProvider.notifier)
                        .setFilter(ExamTimelineFilter.past);
                  },
                  child: const Text('View Past'),
                ),
              ],
            ),
          );
        },
      );
    }

    if (currentFilter == ExamTimelineFilter.past) {
      if (pastExams.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.history_toggle_off,
                size: 56,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 12),
              const Text(
                'No past exams found',
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  ref
                      .read(examTimelineFilterProvider.notifier)
                      .setFilter(ExamTimelineFilter.upcoming);
                },
                child: const Text('Back to Upcoming Exams'),
              ),
            ],
          ),
        );
      }

      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
        itemCount: pastExams.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF881337).withValues(alpha: 0.25)
                    : const Color(0xFFFFF1F2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFFBE123C)
                      : const Color(0xFFFECDD3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: isDark
                        ? const Color(0xFFFB7185)
                        : const Color(0xFFBE123C),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Showing ${pastExams.length} past exams (most recent first). Tap "Drill Topic" to practice.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark
                            ? const Color(0xFFFECDD3)
                            : const Color(0xFF9F1239),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
          return _buildExamCard(pastExams[index - 1], todayStart);
        },
      );
    }

    if (currentFilter == ExamTimelineFilter.completed) {
      if (completedExams.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.fact_check_outlined,
                size: 56,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 12),
              const Text(
                'No completed exams yet',
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  ref
                      .read(examTimelineFilterProvider.notifier)
                      .setFilter(ExamTimelineFilter.upcoming);
                },
                child: const Text('View Upcoming Schedule'),
              ),
            ],
          ),
        );
      }

      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
        itemCount: completedExams.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: ExamScoreAnalyticsCard(),
            );
          }
          return _buildExamCard(completedExams[index - 1], todayStart);
        },
      );
    }

    // ExamTimelineFilter.all: Show partitioned with Upcoming on top, Past at bottom
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      children: [
        if (upcomingExams.isNotEmpty) ...[
          _buildSectionHeaderCard(
            title: '🎯 Upcoming & Active Exams (${upcomingExams.length})',
            color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF1E3A8A),
            bgColor: const Color(0xFFEFF6FF),
          ),
          ...upcomingExams.map((e) => _buildExamCard(e, todayStart)),
          const SizedBox(height: 14),
        ],
        if (pastExams.isNotEmpty || completedExams.isNotEmpty) ...[
          _buildSectionHeaderCard(
            title:
                '📜 Past & Completed Exams (${pastExams.length + completedExams.length})',
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            bgColor: const Color(0xFFF1F5F9),
          ),
          ...pastExams.map((e) => _buildExamCard(e, todayStart)),
          ...completedExams.map((e) => _buildExamCard(e, todayStart)),
        ],
      ],
    );
  }

  Widget _buildSectionHeaderCard({
    required String title,
    required Color color,
    required Color bgColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveBg = isDark ? color.withValues(alpha: 0.15) : bgColor;
    final effectiveBorderColor = isDark
        ? color.withValues(alpha: 0.4)
        : color.withValues(alpha: 0.2);
    final effectiveTextColor = isDark ? Colors.white : color;

    return Container(
      margin: const EdgeInsets.only(bottom: 10, top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: effectiveBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: effectiveBorderColor),
      ),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.bold,
          color: effectiveTextColor,
        ),
      ),
    );
  }

  Widget _buildExamCard(ExamSchedule exam, DateTime todayStart) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final examDateOnly = DateTime(
      exam.examDate.year,
      exam.examDate.month,
      exam.examDate.day,
    );
    final daysDiff = examDateOnly.difference(todayStart).inDays;
    final isToday = daysDiff == 0;
    final isTomorrow = daysDiff == 1;
    final isPast = daysDiff < 0;

    return Card(
      elevation: isToday ? 2.5 : 1,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: exam.completedStatus
              ? (isDark ? const Color(0xFF059669) : const Color(0xFF86EFAC))
              : isToday
              ? const Color(0xFFF59E0B)
              : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          width: isToday ? 1.6 : 1,
        ),
      ),
      color: isToday
          ? (isDark ? const Color(0xFF261D11) : const Color(0xFFFFFDF5))
          : (exam.completedStatus
                ? (isDark ? const Color(0xFF062315) : const Color(0xFFF0FDF4))
                : (isDark ? const Color(0xFF111827) : Colors.white)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Badge Row
            Row(
              children: [
                // Track Pill
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _getTrackBackgroundColor(exam.trackName, isDark),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _getTrackColor(exam.trackName)
                            .withValues(alpha: isDark ? 0.6 : 0.35),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.bookmark_outline,
                          size: 11,
                          color: isDark
                              ? const Color(0xFF93C5FD)
                              : _getTrackColor(exam.trackName),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            exam.trackName,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? const Color(0xFFE2E8F0)
                                  : _getTrackColor(exam.trackName),
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Status Badge (Today / Tomorrow / in X d / Passed / Done)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: exam.completedStatus
                        ? (isDark
                              ? const Color(0xFF064E3B)
                              : const Color(0xFFDCFCE7))
                        : isToday
                        ? (isDark
                              ? const Color(0xFF78350F)
                              : const Color(0xFFFEF3C7))
                        : isTomorrow
                        ? (isDark
                              ? const Color(0xFF312E81)
                              : const Color(0xFFEEF2FF))
                        : isPast
                        ? (isDark
                              ? const Color(0xFF881337)
                              : const Color(0xFFFFF1F2))
                        : (isDark
                              ? const Color(0xFF1E3A8A)
                              : const Color(0xFFEFF6FF)),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: exam.completedStatus
                          ? (isDark
                                ? const Color(0xFF059669)
                                : const Color(0xFF86EFAC))
                          : isToday
                          ? (isDark
                                ? const Color(0xFFD97706)
                                : const Color(0xFFFDE68A))
                          : isTomorrow
                          ? (isDark
                                ? const Color(0xFF6366F1)
                                : const Color(0xFFC7D2FE))
                          : isPast
                          ? (isDark
                                ? const Color(0xFFE11D48)
                                : const Color(0xFFFECDD3))
                          : (isDark
                                ? const Color(0xFF3B82F6)
                                : const Color(0xFFBFDBFE)),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isToday && !exam.completedStatus) ...[
                        Icon(
                          Icons.stars,
                          size: 11,
                          color: isDark
                              ? const Color(0xFFFCD34D)
                              : const Color(0xFFB45309),
                        ),
                        const SizedBox(width: 3),
                      ],
                      Flexible(
                        child: Text(
                          exam.completedStatus
                              ? 'Done ✓'
                              : isToday
                              ? 'TODAY 🎯'
                              : isTomorrow
                              ? 'Tomorrow ⏳'
                              : isPast
                              ? 'Passed (${-daysDiff}d ago)'
                              : 'in $daysDiff d',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: exam.completedStatus
                                ? (isDark
                                      ? const Color(0xFF6EE7B7)
                                      : const Color(0xFF15803D))
                                : isToday
                                ? (isDark
                                      ? const Color(0xFFFCD34D)
                                      : const Color(0xFFB45309))
                                : isTomorrow
                                ? (isDark
                                      ? const Color(0xFFA5B4FC)
                                      : const Color(0xFF4338CA))
                                : isPast
                                ? (isDark
                                      ? const Color(0xFFFDA4AF)
                                      : const Color(0xFFBE123C))
                                : (isDark
                                      ? const Color(0xFF93C5FD)
                                      : const Color(0xFF1D4ED8)),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),

                // Calendar date text
                Text(
                  _formatExamDate(exam.examDate),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
                    color: isToday
                        ? (isDark
                              ? const Color(0xFFFCD34D)
                              : const Color(0xFFB45309))
                        : (isDark
                              ? Colors.grey.shade400
                              : Colors.grey.shade600),
                  ),
                ),

                const SizedBox(width: 4),
                // Popup menu
                SizedBox(
                  width: 24,
                  height: 24,
                  child: PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.more_vert, size: 18),
                    onSelected: (val) {
                      if (val == 'view_topics') {
                        _showFullTopicsDialog(context, exam);
                      } else if (val == 'copy_ref') {
                        _copyExamRef(exam.id);
                      } else if (val == 'calendar') {
                        CalendarSyncService.instance.addToGoogleCalendar(exam);
                      } else if (val == 'done') {
                        ref
                            .read(examScheduleNotifierProvider.notifier)
                            .markCompleted(exam.id);
                      } else if (val == 'undone') {
                        ref
                            .read(examScheduleNotifierProvider.notifier)
                            .markIncomplete(exam.id);
                      } else if (val == 'score') {
                        _showScoreDialog(context, exam);
                      } else if (val == 'change_track') {
                        _showChangeTrackDialog(context, exam);
                      } else if (val == 'voice_mistake') {
                        VoiceMistakeBottomSheet.show(context);
                      } else if (val == 'delete') {
                        ref
                            .read(examScheduleNotifierProvider.notifier)
                            .deleteExam(exam.id);
                      }
                    },
                    itemBuilder: (ctx) => [
                      PopupMenuItem(
                        value: 'view_topics',
                        child: Row(
                          children: [
                            const Icon(
                              Icons.visibility_outlined,
                              size: 16,
                              color: Color(0xFF0284C7),
                            ),
                            const SizedBox(width: 8),
                            const Flexible(
                              child: Text('সম্পূর্ণ টপিক টেক্সট দেখুন'),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'copy_ref',
                        child: Row(
                          children: [
                            const Icon(
                              Icons.tag,
                              size: 16,
                              color: Colors.blueGrey,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'আইডি কপি (${EntityRef(EntityKind.exam, exam.id).tag})',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'calendar',
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_month,
                              size: 16,
                              color: Color(0xFF1E3A8A),
                            ),
                            SizedBox(width: 8),
                            Flexible(child: Text('Add to Calendar')),
                          ],
                        ),
                      ),
                      if (!exam.completedStatus)
                        const PopupMenuItem(
                          value: 'done',
                          child: Row(
                            children: [
                              Icon(
                                Icons.check_circle,
                                size: 16,
                                color: Colors.green,
                              ),
                              SizedBox(width: 8),
                              Flexible(child: Text('Mark as Completed')),
                            ],
                          ),
                        )
                      else
                        const PopupMenuItem(
                          value: 'undone',
                          child: Row(
                            children: [
                              Icon(
                                Icons.restart_alt,
                                size: 16,
                                color: Colors.orange,
                              ),
                              SizedBox(width: 8),
                              Flexible(child: Text('Mark as Incomplete')),
                            ],
                          ),
                        ),
                      const PopupMenuItem(
                        value: 'score',
                        child: Row(
                          children: [
                            Icon(
                              Icons.grade_outlined,
                              size: 16,
                              color: Colors.indigo,
                            ),
                            SizedBox(width: 8),
                            Flexible(child: Text('Record Score')),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'change_track',
                        child: Row(
                          children: [
                            Icon(
                              Icons.bookmark_outline,
                              size: 16,
                              color: Colors.blueAccent,
                            ),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text('ট্র্যাক পরিবর্তন (Change Track)'),
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'voice_mistake',
                        child: Row(
                          children: [
                            Icon(Icons.mic, size: 16, color: Color(0xFF6366F1)),
                            SizedBox(width: 8),
                            Flexible(child: Text('Record Mistake Voice Note')),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline,
                              size: 16,
                              color: Colors.red,
                            ),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Delete Exam',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Exam ID Tag (tappable to copy) & Origin Source Badge
            Row(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(5),
                  onTap: () => _copyExamRef(exam.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.copy,
                          size: 11,
                          color: isDark ? Colors.white30 : Colors.black26,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            EntityRef(EntityKind.exam, exam.id).tag,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontFamily: 'monospace',
                              letterSpacing: 0.4,
                              color: isDark ? Colors.white38 : Colors.black38,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                () {
                  final sourceInfo = ExamSourceInfo.resolve(exam);
                  if (sourceInfo == null) return const SizedBox.shrink();
                  return Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: _buildSourceBadge(sourceInfo, isDark),
                    ),
                  );
                }(),
              ],
            ),
            const SizedBox(height: 4),

            // Exam Title
            Text(
              exam.title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                decoration: exam.completedStatus
                    ? TextDecoration.lineThrough
                    : null,
                color: exam.completedStatus
                    ? Colors.grey.shade600
                    : (Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : const Color(0xFF0F172A)),
              ),
            ),
            const SizedBox(height: 6),

            // Topics Covered with interactive checklist
            ExamTopicChecklistWidget(exam: exam),

            () {
              final summaryText = exam.resourceSummary?.trim() ?? '';
              final isRedundantSummary =
                  summaryText.isEmpty ||
                  summaryText == 'AI Mentor' ||
                  summaryText == 'AI Mentor Plan' ||
                  summaryText == 'AI Study Plan' ||
                  summaryText == 'নিজে যোগ করেছেন' ||
                  summaryText.startsWith('Imported routine');

              if (isRedundantSummary) return const SizedBox.shrink();

              // Cleanly format test paper MCQs instead of dumping raw JSON
              if (summaryText.startsWith('[')) {
                try {
                  final decoded = jsonDecode(summaryText);
                  if (decoded is List && decoded.isNotEmpty) {
                    final questions = decoded
                        .map(
                          (e) =>
                              QuizQuestion.fromJson(e as Map<String, dynamic>),
                        )
                        .toList();
                    return _buildTestPaperCardSummary(
                      context,
                      exam,
                      questions,
                      isDark,
                    );
                  }
                } catch (_) {}
              }

              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1E293B)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    summaryText,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ),
              );
            }(),

            const SizedBox(height: 10),

            // Bottom Quick Action Bar: Drill Topic & Done toggle
            Row(
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    visualDensity: VisualDensity.compact,
                    foregroundColor:
                        Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF93C5FD)
                        : const Color(0xFF1E3A8A),
                    side: BorderSide(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white12
                          : const Color(0xFFCBD5E1),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.psychology, size: 15),
                  label: const Text(
                    'Drill Topic',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: () {
                    List<QuizQuestion>? customQuestions;
                    if (exam.resourceSummary != null &&
                        exam.resourceSummary!.trim().startsWith('[')) {
                      try {
                        final decoded = jsonDecode(exam.resourceSummary!);
                        if (decoded is List) {
                          customQuestions = decoded
                              .map(
                                (e) => QuizQuestion.fromJson(
                                  e as Map<String, dynamic>,
                                ),
                              )
                              .toList();
                        }
                      } catch (_) {}
                    }
                    QuizDrillModal.show(
                      context,
                      topic: exam.topicsCovered,
                      subject: exam.title,
                      examId: exam.id,
                      customQuestions: customQuestions,
                    );
                  },
                ),
                const SizedBox(width: 6),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    visualDensity: VisualDensity.compact,
                    foregroundColor: isDark
                        ? const Color(0xFFFBBF24)
                        : const Color(0xFFD97706),
                    side: BorderSide(
                      color: isDark
                          ? const Color(0xFFB45309)
                          : const Color(0xFFFDE68A),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.timer_outlined, size: 14),
                  label: const Text(
                    'টাইমার',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PomodoroFocusScreen(),
                      ),
                    );
                  },
                ),
                if (isPast || exam.completedStatus) ...[
                  const SizedBox(width: 6),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      visualDensity: VisualDensity.compact,
                      foregroundColor: isDark
                          ? const Color(0xFFA5B4FC)
                          : const Color(0xFF6366F1),
                      side: BorderSide(
                        color: isDark
                            ? const Color(0xFF4338CA)
                            : const Color(0xFFC7D2FE),
                      ),
                      backgroundColor: isDark
                          ? const Color(0xFF312E81).withValues(alpha: 0.3)
                          : const Color(0xFFEEF2FF),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.mic, size: 14),
                    label: const Text(
                      'Voice Mistake',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () => VoiceMistakeBottomSheet.show(context),
                  ),
                ],
                const SizedBox(width: 6),
                IconButton(
                  style: IconButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: isDark
                        ? const Color(0xFFA5B4FC)
                        : const Color(0xFF6366F1),
                  ),
                  icon: const Icon(Icons.calendar_month, size: 18),
                  tooltip: 'Sync to Calendar with 30m alert',
                  onPressed: () =>
                      CalendarSyncService.instance.addToGoogleCalendar(exam),
                ),
                const SizedBox(width: 6),
                if (!exam.completedStatus)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      visualDensity: VisualDensity.compact,
                      foregroundColor: isDark
                          ? const Color(0xFF34D399)
                          : const Color(0xFF047857),
                    ),
                    icon: const Icon(Icons.check, size: 15),
                    label: const Text(
                      'Mark Done',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () {
                      _showScoreDialog(context, exam);
                    },
                  )
                else
                  Text(
                    'Score: ${exam.score != null ? "${exam.score!.toStringAsFixed(1)} marks" : "Completed ✓"}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark
                          ? const Color(0xFF34D399)
                          : const Color(0xFF047857),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTestPaperCardSummary(
    BuildContext context,
    ExamSchedule exam,
    List<QuizQuestion> questions,
    bool isDark,
  ) {
    return TestPaperCardSummary(
      exam: exam,
      questions: questions,
      isExpanded: _expandedTestPaperExams.contains(exam.id),
      onToggleExpand: () {
        setState(() {
          if (_expandedTestPaperExams.contains(exam.id)) {
            _expandedTestPaperExams.remove(exam.id);
          } else {
            _expandedTestPaperExams.add(exam.id);
          }
        });
      },
    );
  }

  void _showFullTopicsDialog(BuildContext context, ExamSchedule exam) {
    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(
                Icons.menu_book_rounded,
                color: Color(0xFF1E3A8A),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  exam.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'সম্পূর্ণ সিলেবাস ও টপিক (Original Topics):',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1E293B)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF334155)
                          : const Color(0xFFCBD5E1),
                    ),
                  ),
                  child: SelectableText(
                    'Topics: ${exam.topicsCovered}',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('কপি করুন'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: exam.topicsCovered));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('টপিক টেক্সট কপি হয়েছে ✓')),
                );
              },
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ঠিক আছে'),
            ),
          ],
        );
      },
    );
  }

  void _showScoreDialog(BuildContext context, ExamSchedule exam) {
    final scoreController = TextEditingController(
      text: exam.score?.toStringAsFixed(1) ?? '',
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Record LiveMCQ Score'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              exam.title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: scoreController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'প্রাপ্ত নম্বর',
                hintText: 'যেমন ৭৮.৫০',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final val = double.tryParse(scoreController.text.trim());
              ref
                  .read(examScheduleNotifierProvider.notifier)
                  .markCompleted(exam.id, score: val);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    val != null
                        ? 'অভিনন্দন! স্কোর ${val.toStringAsFixed(1)} সংরক্ষিত হয়েছে 🎉'
                        : 'পরীক্ষা সম্পন্ন চিহ্নিত হয়েছে ✓',
                  ),
                  backgroundColor: const Color(0xFF10B981),
                ),
              );
            },
            child: const Text('Save Score'),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceBadge(ExamSourceInfo source, bool isDark) {
    return ExamSourceBadge(source: source, isDark: isDark);
  }

  void _showChangeTrackDialog(BuildContext context, ExamSchedule exam) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final distinctTracks = ref.read(distinctTracksStreamProvider).value ?? [];
    final suggestions = <String>{
      ...distinctTracks,
      'Self Test',
      'Self Study',
      'General BCS',
    }.toList();

    String selected = exam.trackName;
    bool isCustom = !suggestions.contains(selected);
    final customController = TextEditingController(
      text: isCustom ? selected : '',
    );

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(Icons.bookmark_outline, color: Color(0xFF2563EB)),
                SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'ট্র্যাক পরিবর্তন করুন',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'পরীক্ষা: ${exam.title}',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'ট্র্যাক নির্বাচন করুন:',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: isDark ? Colors.white24 : Colors.grey.shade300,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: isCustom ? 'custom' : selected,
                        dropdownColor: isDark
                            ? const Color(0xFF1E293B)
                            : Colors.white,
                        items: [
                          ...suggestions.map(
                            (t) => DropdownMenuItem(
                              value: t,
                              child: Text(
                                t,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ),
                          const DropdownMenuItem(
                            value: 'custom',
                            child: Text(
                              '+ নতুন ট্র্যাক লিখুন (Custom)',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.blueAccent,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (val) {
                          if (val == null) return;
                          setDialogState(() {
                            if (val == 'custom') {
                              isCustom = true;
                            } else {
                              isCustom = false;
                              selected = val;
                            }
                          });
                        },
                      ),
                    ),
                  ),
                  if (isCustom) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: customController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'নতুন ট্র্যাকের নাম (যেমন: Self Test)',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final finalTrack = isCustom
                      ? customController.text.trim()
                      : selected;
                  if (finalTrack.isNotEmpty && finalTrack != exam.trackName) {
                    await ref
                        .read(examScheduleNotifierProvider.notifier)
                        .updateExamTrack(exam.id, finalTrack);
                    ref.invalidate(distinctTracksStreamProvider);
                    ref.invalidate(filteredExamsStreamProvider);
                    ref.invalidate(upcomingExamsStreamProvider);
                    ref.invalidate(allExamsStreamProvider);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: Colors.teal.shade800,
                          content: Text(
                            'ট্র্যাক পরিবর্তন করে "$finalTrack" করা হয়েছে',
                          ),
                        ),
                      );
                    }
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTrackFilterBar(
    AsyncValue<List<String>> tracksAsync,
    String selectedTrack,
  ) {
    return LiveMcqTrackFilterBar(
      tracksAsync: tracksAsync,
      selectedTrack: selectedTrack,
    );
  }

  Color _getTrackColor(String track) =>
      LiveMcqTrackFilterBar.getTrackColor(track);

  Color _getTrackBackgroundColor(String track, [bool isDark = false]) =>
      LiveMcqTrackFilterBar.getTrackBackgroundColor(track, isDark);

  Widget _buildSummarizerTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'পড়ার নোট ও PDF থেকে সারাংশ',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'পড়ার নোট বা স্টাডি শিটের লেখা পেস্ট করুন। ৫টি গুরুত্বপূর্ণ পয়েন্ট, '
            'বিগত পরীক্ষার প্রশ্ন আর মনে রাখার কৌশল বেরিয়ে আসবে।',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _subjectController,
            decoration: const InputDecoration(
              labelText: 'বিষয় (যেমন বাংলা ব্যাকরণ, গণিত, বিজ্ঞান)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _studySheetController,
            maxLines: 5,
            // The size line below has to keep up with the typing it reports.
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'পড়ার নোট বা টপিক এখানে পেস্ট করুন...',
              border: OutlineInputBorder(),
              hintText: 'e.g. কারক ও বিভক্তি: বাক্যের ক্রিয়ার সাথে অন্য পদের সম্বন্ধ...',
            ),
          ),
          const SizedBox(height: 12),
          if (_isSummarizing)
            // A wait of unknown length reads as a hang. The seconds show it
            // is working, and the stop button means the user is never held
            // here against their will.
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'AI পড়ছে… ${_summarySeconds}s',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                TextButton.icon(
                  onPressed: _cancelSummarizer,
                  icon: const Icon(Icons.stop_circle_outlined, size: 18),
                  label: const Text('থামাও'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                  ),
                ),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.auto_awesome),
                label: const Text('৫ পয়েন্টে সারাংশ বানাও'),
                onPressed: _runSummarizer,
              ),
            ),
          if (!_isSummarizing && _studySheetLength > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _studySheetLength > GeminiPrompts.largeStudySheetChars
                    ? 'লেখাটা বড় — $_studySheetLength অক্ষর, পুরোটাই পাঠানো হবে'
                    : '$_studySheetLength অক্ষর',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ),
            ),
          const SizedBox(height: 20),
          if (_summaryResult != null) _buildSummaryDisplay(_summaryResult!),
        ],
      ),
    );
  }

  int get _studySheetLength => _studySheetController.text.trim().length;

  void _cancelSummarizer() {
    _summaryCancellation?.cancel();
  }

  void _endSummaryRun() {
    _summaryTicker?.cancel();
    _summaryTicker = null;
    _summaryCancellation = null;
    if (mounted) setState(() => _isSummarizing = false);
  }

  Future<void> _runSummarizer() async {
    final text = _studySheetController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('আগে কিছু লেখা বসান।')));
      return;
    }

    final cancellation = AiCancellation();
    setState(() {
      _isSummarizing = true;
      _summaryCancellation = cancellation;
      _summarySeconds = 0;
    });
    _summaryTicker?.cancel();
    _summaryTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _summarySeconds++);
    });

    try {
      final summary = await GeminiAiService.instance.summarizeStudySheet(
        content: text,
        subject: _subjectController.text.trim(),
        cancellation: cancellation,
      );
      if (!mounted) return;
      setState(() => _summaryResult = summary);
    } on AiCancelledException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('থামানো হলো। যা খরচ হয়ে গেছে তা ফেরত আসে না।'),
        ),
      );
    } finally {
      _endSummaryRun();
    }
  }

  Widget _buildSummaryDisplay(StudySheetSummary summary) {
    return StudySheetSummaryCard(
      summary: summary,
      subject: _subjectController.text.trim(),
    );
  }

  void _showAddExamDialog(BuildContext context) {
    final titleController = TextEditingController();
    final topicsController = TextEditingController();
    final summaryController = TextEditingController();
    final customTrackController = TextEditingController();
    DateTime selectedDate = DateTime.now().add(const Duration(days: 3));

    final defaultTracks = [
      '52nd BCS 135-Day',
      'Vocabulary Booster',
      'Friday Mega Model Test',
      'Primary Exam Track',
      '200-Day Routine',
      'General BCS',
      'Custom Track...',
    ];
    String selectedTrack = '52nd BCS 135-Day';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isCustom = selectedTrack == 'Custom Track...';

          return AlertDialog(
            title: const Text('Add LiveMCQ Exam'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Program / Track:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(ctx).brightness == Brightness.dark
                          ? Colors.white
                          : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: selectedTrack,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                    ),
                    items: defaultTracks
                        .map(
                          (t) => DropdownMenuItem(
                            value: t,
                            child: Text(
                              t,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() {
                          selectedTrack = val;
                        });
                      }
                    },
                  ),
                  if (isCustom) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: customTrackController,
                      decoration: const InputDecoration(
                        labelText: 'প্রোগ্রামের নাম লিখুন',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'পরীক্ষার নাম (যেমন Day-12: বাংলা ব্যাকরণ)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: topicsController,
                    decoration: const InputDecoration(
                      labelText: 'যে টপিকগুলো আছে',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: summaryController,
                    decoration: const InputDecoration(
                      labelText: 'নোট বা লক্ষ্য নম্বর',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Exam Date: ${selectedDate.toIso8601String().substring(0, 10)}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    trailing: const Icon(Icons.calendar_today, size: 20),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setDialogState(() {
                          selectedDate = picked;
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  final title = titleController.text.trim();
                  final topics = topicsController.text.trim();
                  if (title.isNotEmpty && topics.isNotEmpty) {
                    final finalTrack =
                        isCustom && customTrackController.text.trim().isNotEmpty
                        ? customTrackController.text.trim()
                        : (isCustom ? 'General BCS' : selectedTrack);

                    final summary = summaryController.text.trim();
                    ref
                        .read(examScheduleNotifierProvider.notifier)
                        .addExam(
                          examDate: selectedDate,
                          title: title,
                          topicsCovered: topics,
                          resourceSummary: summary.isNotEmpty
                              ? summary
                              : 'নিজে যোগ করেছেন',
                          trackName: finalTrack,
                          rawReference: 'manual',
                        );
                    ref.invalidate(distinctTracksStreamProvider);
                    ref.invalidate(filteredExamsStreamProvider);
                    ref.invalidate(upcomingExamsStreamProvider);
                    Navigator.pop(ctx);
                  }
                },
                child: const Text('Add'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showImportRoutineDialog(BuildContext context) {
    final textController = TextEditingController();
    final customTrackController = TextEditingController();
    bool isProcessing = false;
    String selectedTrack = 'Auto-detect from Routine';
    final trackOptions = [
      'Auto-detect from Routine',
      '52nd BCS 135-Day',
      'Vocabulary Booster',
      'Friday Mega Model Test',
      'Primary Exam Track',
      '200-Day Routine',
      'Custom Track...',
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isCustom = selectedTrack == 'Custom Track...';

          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.auto_awesome, color: Colors.indigo, size: 22),
                SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Import Routine (AI / Text)',
                    style: TextStyle(fontSize: 16),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Program / Routine Track:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(ctx).brightness == Brightness.dark
                          ? Colors.white
                          : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: selectedTrack,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                    items: trackOptions
                        .map(
                          (t) => DropdownMenuItem(
                            value: t,
                            child: Text(
                              t,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() {
                          selectedTrack = val;
                        });
                      }
                    },
                  ),
                  if (isCustom) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: customTrackController,
                      decoration: const InputDecoration(
                        labelText: 'প্রোগ্রাম বা ট্র্যাকের নাম',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.primaryContainer
                          .withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(ctx).colorScheme.primary
                            .withValues(alpha: 0.25),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.smart_toy_outlined,
                              size: 16,
                              color: Theme.of(ctx).colorScheme.primary,
                            ),
                            const SizedBox(width: 6),
                            const Expanded(
                              child: Text(
                                'ChatGPT / Claude দিয়ে রুটিন আনবেন?',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'প্রম্পট কপি করে ChatGPT বা Claude-এ আপনার রুটিন (PDF/ছবি/টেক্সট) সহ দিন। AI যে JSON কোড দেবে তা নিচে পেস্ট করে সেভ করুন। এতে কোনো টোকেন লিমিট নেই!',
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(ctx).brightness == Brightness.dark
                                ? Colors.white70
                                : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            OutlinedButton.icon(
                              icon: const Icon(Icons.copy, size: 14),
                              label: const Text(
                                'Copy AI Prompt',
                                style: TextStyle(fontSize: 11),
                              ),
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                              ),
                              onPressed: () {
                                Clipboard.setData(
                                  const ClipboardData(
                                    text: RoutineParserService
                                        .externalAiRoutinePrompt,
                                  ),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      '📋 External AI Prompt কপি হয়েছে! রুটিন সহ ChatGPT/Claude-এ পেস্ট করুন।',
                                    ),
                                    duration: Duration(seconds: 3),
                                  ),
                                );
                              },
                            ),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.content_paste, size: 14),
                              label: const Text(
                                'Paste from Clipboard',
                                style: TextStyle(fontSize: 11),
                              ),
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                              ),
                              onPressed: () async {
                                final data = await Clipboard.getData(
                                  Clipboard.kTextPlain,
                                );
                                if (data != null &&
                                    data.text != null &&
                                    data.text!.isNotEmpty) {
                                  textController.text = data.text!;
                                  setDialogState(() {});
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Paste Facebook post text, notice routine, or AI JSON below:',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(ctx).brightness == Brightness.dark
                          ? Colors.white70
                          : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: textController,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      hintText: 'e.g.\n{"track_name": "52nd BCS", "exams": [...]}\nOR\n52nd BCS 135 Days Routine:\n28 Oct | 10:00 PM | Bangla: কারক ও বিভক্তি',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    icon: const Icon(
                      Icons.flash_on,
                      size: 16,
                      color: Colors.amber,
                    ),
                    label: const Text(
                      'Insert Multi-Track Sample Routine',
                      style: TextStyle(fontSize: 11),
                    ),
                    onPressed: () {
                      textController.text =
                          '52nd BCS 135-Day Syllabus Routine:\n'
                          '2026-10-28 | 10:00 PM | Bangla Grammar: কারক ও বিভক্তি | 135 Days Syllabus\n'
                          '2026-10-30 | 10:00 PM | Mathematics: শতকরা ও লাভ-ক্ষতি | 135 Days Syllabus\n\n'
                          'Daily Vocabulary Booster:\n'
                          '2026-10-27 | 10:30 PM | English: Synonyms & Antonyms (Set 1-5)\n'
                          '2026-10-28 | 10:30 PM | English: Idioms & Phrases (Set 1-3)\n\n'
                          'Friday Full Model Test:\n'
                          '2026-10-31 | 09:00 PM | 200 Marks Full BCS Simulation Test 01';
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isProcessing
                    ? null
                    : () async {
                        final input = textController.text.trim();
                        if (input.isEmpty) return;

                        setDialogState(() {
                          isProcessing = true;
                        });

                        final nav = Navigator.of(ctx);
                        final messenger = ScaffoldMessenger.of(context);

                        final items = await RoutineParserService.instance
                            .parseRoutineFromText(input);
                        if (!mounted) return;

                        if (items.isNotEmpty) {
                          String? overrideTrack;
                          if (selectedTrack == 'Custom Track...' &&
                              customTrackController.text.trim().isNotEmpty) {
                            overrideTrack = customTrackController.text.trim();
                          } else if (selectedTrack !=
                                  'Auto-detect from Routine' &&
                              selectedTrack != 'Custom Track...') {
                            overrideTrack = selectedTrack;
                          }

                          final db = ref.read(appDatabaseProvider);
                          final result = await RoutineParserService.instance
                              .saveParsedRoutinesToDatabase(
                                db,
                                items,
                                overrideTrack: overrideTrack,
                              );
                          ref.invalidate(upcomingExamsStreamProvider);
                          ref.invalidate(allExamsStreamProvider);
                          ref.invalidate(distinctTracksStreamProvider);
                          ref.invalidate(filteredExamsStreamProvider);

                          nav.pop();
                          messenger.showSnackBar(
                            SnackBar(
                              backgroundColor: result.allDuplicates
                                  ? Colors.amber.shade900
                                  : Colors.green.shade800,
                              content: Text(result.toBengaliMessage()),
                            ),
                          );
                        } else {
                          setDialogState(() {
                            isProcessing = false;
                          });
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Could not extract schedules from text.',
                              ),
                            ),
                          );
                        }
                      },
                child: isProcessing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Parse & Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showPdfOptionsSheet(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'PDF ইম্পোর্ট অপশন',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 14),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.calendar_month,
                    color: Color(0xFF6366F1),
                  ),
                ),
                title: const Text(
                  'পরীক্ষার রুটিন PDF',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
                  'LiveMCQ বা কোচিং রুটিন থেকে পরীক্ষার তালিকা ও শিডিউল সেভ করুন',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndParsePdf(context);
                },
              ),
              const Divider(height: 20),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.menu_book_rounded,
                    color: Color(0xFF10B981),
                  ),
                ),
                title: const Text(
                  'পড়ার রিসোর্স / লেকচার শিট PDF',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
                  'PDF পড়ে তাৎক্ষণিক ১০টি প্রশ্নে পরীক্ষা দিন (Active Recall)',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndParseStudyPdf(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickAndParseStudyPdf(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final pickedFiles = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (pickedFiles.isNotEmpty && pickedFiles.first.path != null) {
        final filePath = pickedFiles.first.path!;
        final file = File(filePath);
        final fileName = file.path.split('/').last;

        messenger.showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 15),
            backgroundColor: const Color(0xFF10B981),
            content: Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'AI $fileName থেকে ১০টি প্রশ্ন তৈরি করছে...',
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        );

        final questions = await QuizGeneratorService.instance
            .generateQuizFromStudyPdf(file, count: 10);

        if (!context.mounted) return;
        messenger.hideCurrentSnackBar();

        if (questions.isNotEmpty) {
          QuizDrillModal.show(
            context,
            subject: 'Study PDF Drill',
            topic: fileName.replaceAll('.pdf', ''),
            customQuestions: questions,
          );
        } else {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'PDF থেকে প্রশ্ন তৈরি করা সম্ভব হয়নি। ফাইলটি যাচাই করুন।',
              ),
            ),
          );
        }
      }
    } on QuizGenerationException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade800,
          content: Text(e.userMessage),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade800,
          content: Text('PDF পড়তে সমস্যা হয়েছে: $e'),
        ),
      );
    }
  }

  Future<void> _pickAndParseScreenshotMistake(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (picked == null) return;

      messenger.showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 15),
          backgroundColor: Color(0xFF0284C7),
          content: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'AI LiveMCQ স্ক্রিনশট থেকে প্রশ্ন সমাধান করছে…',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      );

      final result = await VoiceMistakeParserService.instance
          .parseMistakeFromImage(File(picked.path));

      if (!context.mounted) return;
      messenger.hideCurrentSnackBar();

      if (result != null) {
        final db = ref.read(appDatabaseProvider);
        await VoiceMistakeParserService.instance.saveVoiceMistakeToDatabase(
          db,
          result,
          sourceTag: '[উৎস: LiveMCQ 📸]',
        );
        ref.invalidate(wrongQuestionsStreamProvider);
        ref.invalidate(dueSpacedReviewsStreamProvider);
        ref.invalidate(allSpacedReviewsStreamProvider);
        ref.invalidate(weakTopicsStreamProvider);

        if (!context.mounted) return;
        showDialog(
          context: context,
          builder: (dlgCtx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Color(0xFF10B981), size: 22),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'ভুল প্রশ্ন সংরক্ষিত ✓',
                    style: TextStyle(fontSize: 15),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${result.subject} • ${result.topic}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF6366F1),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    result.questionText,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '✅ সঠিক উত্তর: ${(result.correctIndex >= 0 && result.correctIndex < result.options.length) ? result.options[result.correctIndex] : "অজানা"}',
                    style: const TextStyle(
                      color: Color(0xFF10B981),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '💡 ব্যাখ্যা: ${result.explanation}',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dlgCtx),
                child: const Text('ঠিক আছে'),
              ),
            ],
          ),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'স্ক্রিনশট থেকে প্রশ্ন শনাক্ত করা যায়নি। স্পষ্ট ছবি দিন।',
            ),
          ),
        );
      }
    } on VoiceParseException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade800,
          content: Text(e.userMessage),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade800,
          content: Text('স্ক্রিনশট বিশ্লেষণে সমস্যা: $e'),
        ),
      );
    }
  }

  Future<void> _pickAndParsePdf(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);

    // Ensure API Key is available before opening file picker
    await RoutineParserService.instance.init();
    if (RoutineParserService.instance.cachedApiKey == null ||
        RoutineParserService.instance.cachedApiKey!.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade800,
          content: const Text(
            'Gemini API Key সেট করা নেই। রুটিন PDF বিশ্লেষণ করতে Settings এ গিয়ে API Key দিন।',
          ),
          action: SnackBarAction(
            label: 'Settings',
            textColor: Colors.amber,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ),
      );
      return;
    }

    try {
      final pickedFiles = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (pickedFiles.isNotEmpty && pickedFiles.first.path != null) {
        final filePath = pickedFiles.first.path!;
        final file = File(filePath);

        messenger.showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 10),
            backgroundColor: Colors.indigo.shade900,
            content: Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Analyzing ${file.path.split("/").last} with Gemini AI Vision (টোকেন অপ্টিমাইজড)...',
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        );

        final items = await RoutineParserService.instance.parseRoutineFromPdf(
          file,
        );
        if (!mounted) return;

        if (items.isNotEmpty) {
          final db = ref.read(appDatabaseProvider);
          final result = await RoutineParserService.instance
              .saveParsedRoutinesToDatabase(db, items);
          ref.invalidate(upcomingExamsStreamProvider);
          ref.invalidate(allExamsStreamProvider);
          ref.invalidate(distinctTracksStreamProvider);
          ref.invalidate(filteredExamsStreamProvider);

          final wasTruncated =
              RoutineParserService.instance.lastParseWasTruncated;

          messenger.showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 6),
              backgroundColor: result.allDuplicates
                  ? Colors.amber.shade900
                  : (wasTruncated
                        ? Colors.orange.shade900
                        : Colors.green.shade800),
              content: Text(
                wasTruncated
                    ? '⚠️ Gemini টোকেন লিমিটের কারণে আংশিক (${result.insertedCount}টি) পরীক্ষা উদ্ধার হয়েছে। বাকি পরীক্ষার জন্য ChatGPT Prompt ব্যবহার করুন।'
                    : result.toBengaliMessage(),
              ),
              action: wasTruncated
                  ? SnackBarAction(
                      label: 'AI Prompt',
                      textColor: Colors.amber,
                      onPressed: () {
                        Clipboard.setData(
                          const ClipboardData(
                            text: RoutineParserService.externalAiRoutinePrompt,
                          ),
                        );
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text(
                              '📋 External AI Prompt কপি হয়েছে! ChatGPT-তে রুটিন ফাইল সহ দিন।',
                            ),
                          ),
                        );
                      },
                    )
                  : null,
            ),
          );
        } else {
          if (!mounted) return;
          _showRoutineExtractionDiagnosticDialog(
            this.context,
            RoutineParserException(
              userMessage: 'রুটিন PDF থেকে কোনো পরীক্ষার তথ্য পাওয়া যায়নি। ফাইলটি স্পষ্ট কিনা যাচাই করুন।',
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error picking or parsing PDF: $e');
      if (!mounted) return;
      _showRoutineExtractionDiagnosticDialog(this.context, e);
    }
  }

  void _showRoutineExtractionDiagnosticDialog(
    BuildContext context,
    dynamic error,
  ) {
    String userMessage = 'রুটিন নিষ্কাশন সফল হয়নি।';
    String? technicalDetails;
    String? rawSnippet;
    String? finishReason;
    int? tokens;
    String? model;
    bool isQuota = false;
    bool isTooLarge = false;

    if (error is RoutineParserException) {
      userMessage = error.userMessage;
      technicalDetails = error.technicalDetails;
      rawSnippet = error.rawResponseSnippet;
      finishReason = error.finishReason;
      tokens = error.totalTokens;
      model = error.modelName;
      isQuota = error.isQuotaOrRateLimit;
      isTooLarge = error.isPayloadTooLarge;
    } else {
      userMessage = error.toString().replaceFirst('Exception: ', '');
      technicalDetails = error.toString();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.redAccent, size: 24),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'রুটিন নিষ্কাশনে ত্রুটি / Diagnostic',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                userMessage,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),

              // Diagnostic Info Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E293B)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🔍 বিস্তারিত কারণ / Diagnostic Info:',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (model != null)
                      Text(
                        '• Model: $model',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    if (finishReason != null)
                      Text(
                        '• Finish Reason: $finishReason'
                        '${finishReason == "maxTokens" ? " (টোকেন লিমিটের কারণে আউটপুট কেটে গেছে)" : ""}',
                        style: TextStyle(
                          fontSize: 11,
                          color: finishReason == "maxTokens"
                              ? Colors.amber.shade700
                              : (isDark ? Colors.white60 : Colors.black54),
                          fontWeight: finishReason == "maxTokens"
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    if (tokens != null && tokens > 0)
                      Text(
                        '• Tokens Used: $tokens',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    if (technicalDetails != null &&
                        technicalDetails.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '• Details: $technicalDetails',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontFamily: 'monospace',
                          color: isDark
                              ? Colors.red.shade300
                              : Colors.red.shade800,
                        ),
                      ),
                    ],
                    if (isTooLarge) ...[
                      const SizedBox(height: 4),
                      Text(
                        '⚠️ ফাইল সাইজ Gemini API লিমিটের বেশি। PDF ফাইলটি ছোট করুন বা ChatGPT ব্যবহার করুন।',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade700,
                        ),
                      ),
                    ],
                    if (rawSnippet != null && rawSnippet.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Gemini Raw Output:',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 120),
                        width: double.infinity,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.black26 : Colors.white,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isDark
                                ? Colors.white12
                                : const Color(0xFFCBD5E1),
                          ),
                        ),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            rawSnippet,
                            style: const TextStyle(
                              fontSize: 10,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 12),
              // Helpful Recommendation Card
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.indigo.withValues(alpha: isDark ? 0.2 : 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.indigo.withValues(alpha: isDark ? 0.4 : 0.2),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.lightbulb_outline,
                      size: 16,
                      color: Colors.amber,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '💡 বড় বা দীর্ঘমেয়াদী রুটিনের (যেমন ১৩৫ দিনের বিসিএস রুটিন) জন্য ChatGPT বা Claude দিয়ে রুটিন নিয়ে আসুন। নিচের বাটন চেপে প্রম্পট কপি করে ChatGPT-তে আপনার রুটিন দিলেই কোনো টোকেন লিমিট ছাড়া শতভাগ নির্ভুল ফলাফল পাওয়া যাবে!',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          OutlinedButton.icon(
            icon: const Icon(Icons.copy, size: 14),
            label: const Text(
              'Copy ChatGPT Prompt',
              style: TextStyle(fontSize: 11),
            ),
            onPressed: () {
              Clipboard.setData(
                const ClipboardData(
                  text: RoutineParserService.externalAiRoutinePrompt,
                ),
              );
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    '📋 Prompt কপি হয়েছে! ChatGPT-তে রুটিন ফাইল সহ দিন।',
                  ),
                  duration: Duration(seconds: 4),
                ),
              );
            },
          ),
          if (isQuota || model == 'gemini-flash-lite-latest')
            TextButton.icon(
              icon: const Icon(Icons.settings, size: 14),
              label: const Text(
                'Settings (Change Model)',
                style: TextStyle(fontSize: 11),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
            ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ঠিক আছে (Close)'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportCurrentTrackToIcs(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final selectedTrack = ref.read(selectedTrackProvider);
    final exams = ref.read(filteredExamsStreamProvider).value ?? [];

    if (exams.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('No exams found to export for "$selectedTrack".'),
        ),
      );
      return;
    }

    try {
      final file = await CalendarSyncService.instance.generateIcsFile(
        exams,
        trackName: selectedTrack,
      );

      String displayLoc = file.path;
      if (displayLoc.contains('/Download/')) {
        displayLoc =
            'Download${displayLoc.substring(displayLoc.indexOf('/Download/') + 9)}';
      } else if (displayLoc.contains('/Downloads/')) {
        displayLoc =
            'Downloads${displayLoc.substring(displayLoc.indexOf('/Downloads/') + 10)}';
      }

      messenger.showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF1E3A8A),
          duration: const Duration(seconds: 6),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${exams.length}টি পরীক্ষার রুটিন ক্যালেন্ডার ফাইলে এক্সপোর্ট হয়েছে!',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '📁 $displayLoc',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 2),
              const Text(
                '💡 ফোনের Download ফোল্ডারে ফাইলটি পাবেন।',
                style: TextStyle(color: Colors.tealAccent, fontSize: 11),
              ),
            ],
          ),
          action: SnackBarAction(
            textColor: Colors.tealAccent,
            label: 'Open',
            onPressed: () async {
              final uri = Uri.file(file.path);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri);
              }
            },
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to export calendar: $e')),
      );
    }
  }
}
