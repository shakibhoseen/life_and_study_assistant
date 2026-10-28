import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../core/services/ai/entity_ref.dart';
import '../../../../core/services/ai/gemini_ai_service.dart';
import '../../../../core/services/ai/models/study_sheet_summary.dart';
import '../../../../core/services/ai/routine_parser_service.dart';
import '../../../../core/services/ai/models/quiz_question.dart';
import '../../../../core/services/calendar/calendar_sync_service.dart';
import '../../../../core/utils/bengali_math_sanitizer.dart';
import '../../../quiz/presentation/widgets/quiz_drill_modal.dart';
import '../../../quiz/presentation/widgets/quiz_batch_correction_sheet.dart';
import '../../../quiz/presentation/widgets/question_bank_scanner_modal.dart';
import '../../domain/models/exam_source_info.dart';
import '../../../settings/presentation/screens/settings_screen.dart';
import '../providers/exam_schedule_provider.dart';
import '../widgets/voice_mistake_bottom_sheet.dart';

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
  final Set<int> _expandedTestPaperExams = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
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
            tooltip: 'Upload Routine PDF',
            onPressed: () => _pickAndParsePdf(context),
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
            Tab(icon: Icon(Icons.event_note), text: 'Exam Schedules'),
            Tab(icon: Icon(Icons.summarize), text: 'AI Study Summarizer'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildSchedulesTab(), _buildSummarizerTab()],
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111827) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade200,
          ),
        ),
      ),
      child: Column(
        children: [
          // Search Input Bar
          Container(
            height: 38,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: TextField(
              controller: _searchController,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white : Colors.black87,
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                hintText: 'Search by topic, subject or routine...',
                hintStyle: TextStyle(
                  fontSize: 12.5,
                  color: isDark ? Colors.white54 : Colors.grey.shade500,
                ),
                prefixIcon: Icon(
                  Icons.search,
                  size: 18,
                  color: isDark ? Colors.white54 : Colors.grey,
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.clear,
                          size: 16,
                          color: isDark ? Colors.white70 : Colors.grey.shade700,
                        ),
                        onPressed: () {
                          _searchController.clear();
                          ref
                              .read(examSearchQueryProvider.notifier)
                              .setQuery('');
                        },
                      )
                    : null,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
              onChanged: (val) {
                ref.read(examSearchQueryProvider.notifier).setQuery(val);
              },
            ),
          ),
          const SizedBox(height: 8),

          // Timeline Filter Chips Row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildTimelineChip(
                  label: 'Upcoming',
                  count: upcomingCount,
                  icon: Icons.upcoming,
                  isSelected: currentFilter == ExamTimelineFilter.upcoming,
                  activeColor: isDark
                      ? const Color(0xFF3B82F6)
                      : const Color(0xFF1E3A8A),
                  onTap: () => ref
                      .read(examTimelineFilterProvider.notifier)
                      .setFilter(ExamTimelineFilter.upcoming),
                ),
                const SizedBox(width: 8),
                _buildTimelineChip(
                  label: 'Past',
                  count: pastCount,
                  icon: Icons.history,
                  isSelected: currentFilter == ExamTimelineFilter.past,
                  activeColor: isDark
                      ? const Color(0xFFF43F5E)
                      : const Color(0xFFBE123C),
                  onTap: () => ref
                      .read(examTimelineFilterProvider.notifier)
                      .setFilter(ExamTimelineFilter.past),
                ),
                const SizedBox(width: 8),
                _buildTimelineChip(
                  label: 'Completed',
                  count: completedCount,
                  icon: Icons.check_circle_outline,
                  isSelected: currentFilter == ExamTimelineFilter.completed,
                  activeColor: isDark
                      ? const Color(0xFF10B981)
                      : const Color(0xFF047857),
                  onTap: () => ref
                      .read(examTimelineFilterProvider.notifier)
                      .setFilter(ExamTimelineFilter.completed),
                ),
                const SizedBox(width: 8),
                _buildTimelineChip(
                  label: 'All',
                  count: allCount,
                  icon: Icons.list_alt,
                  isSelected: currentFilter == ExamTimelineFilter.all,
                  activeColor: isDark
                      ? const Color(0xFF64748B)
                      : const Color(0xFF475569),
                  onTap: () => ref
                      .read(examTimelineFilterProvider.notifier)
                      .setFilter(ExamTimelineFilter.all),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineChip({
    required String label,
    required int count,
    required IconData icon,
    required bool isSelected,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor
              : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? activeColor
                : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
            width: isSelected ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected
                  ? Colors.white
                  : (isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B)),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected
                    ? Colors.white
                    : (isDark
                          ? const Color(0xFFE2E8F0)
                          : const Color(0xFF334155)),
              ),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.25)
                    : (isDark
                          ? const Color(0xFF0F172A)
                          : const Color(0xFFE2E8F0)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isSelected
                      ? Colors.white
                      : (isDark
                            ? const Color(0xFFCBD5E1)
                            : const Color(0xFF475569)),
                ),
              ),
            ),
          ],
        ),
      ),
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
        itemCount: completedExams.length,
        itemBuilder: (context, index) {
          return _buildExamCard(completedExams[index], todayStart);
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
                      Text(
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
                    if (val == 'copy_ref') {
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
                        Text(
                          EntityRef(EntityKind.exam, exam.id).tag,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontFamily: 'monospace',
                            letterSpacing: 0.4,
                            color: isDark ? Colors.white38 : Colors.black38,
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

            // Topics Covered
            Text(
              'Topics: ${exam.topicsCovered}',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white70
                    : Colors.black87,
              ),
            ),

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
                      ref
                          .read(examScheduleNotifierProvider.notifier)
                          .markCompleted(exam.id);
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
    final isExpanded = _expandedTestPaperExams.contains(exam.id);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1E293B).withValues(alpha: 0.6)
            : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFF4F46E5)
                      .withValues(alpha: isDark ? 0.2 : 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.menu_book_rounded,
                  size: 16,
                  color: Color(0xFF4F46E5),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'টেস্ট পেপার প্রশ্নমালা (${BengaliMathSanitizer.toBengaliDigits('${questions.length}')}টি MCQ)',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              InkWell(
                onTap: () {
                  setState(() {
                    if (isExpanded) {
                      _expandedTestPaperExams.remove(exam.id);
                    } else {
                      _expandedTestPaperExams.add(exam.id);
                    }
                  });
                },
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isExpanded ? 'সংক্ষেপ' : 'প্রশ্ন দেখুন',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? const Color(0xFFA5B4FC)
                              : const Color(0xFF4F46E5),
                        ),
                      ),
                      Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: 16,
                        color: isDark
                            ? const Color(0xFFA5B4FC)
                            : const Color(0xFF4F46E5),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // If Expanded: Show the list of questions cleanly formatted
          if (isExpanded) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),
            ...List.generate(questions.length, (idx) {
              final q = questions[idx];
              final hasLeadingNumber = RegExp(r'^(\d+|[০-৯]+)\.')
                  .hasMatch(q.questionText.trim());
              final displayText = hasLeadingNumber
                  ? q.questionText
                  : '${idx + 1}. ${q.questionText}';
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayText,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: q.options.asMap().entries.map((optEntry) {
                        final isCorrect = optEntry.key == q.correctIndex;
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isCorrect
                                ? (isDark
                                      ? Colors.green.shade900.withValues(
                                          alpha: 0.3,
                                        )
                                      : Colors.green.shade50)
                                : (isDark
                                      ? const Color(0xFF0F172A)
                                      : Colors.white),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isCorrect
                                  ? Colors.green
                                  : (isDark
                                        ? Colors.white12
                                        : Colors.grey.shade300),
                              width: isCorrect ? 1.2 : 0.8,
                            ),
                          ),
                          child: Text(
                            optEntry.value,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: isCorrect
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isCorrect
                                  ? (isDark
                                        ? Colors.green.shade300
                                        : Colors.green.shade800)
                                  : (isDark ? Colors.white70 : Colors.black87),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    if (q.explanation.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        '💡 ব্যাখ্যা: ${q.explanation}',
                        style: TextStyle(
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                          color: isDark
                              ? Colors.amber.shade200
                              : Colors.amber.shade900,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
          ] else ...[
            const SizedBox(height: 6),
            Text(
              '১ম প্রশ্ন: ${questions.first.questionText}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
          ],

          const SizedBox(height: 8),

          // Bottom Action Row
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  foregroundColor: isDark
                      ? const Color(0xFFA5B4FC)
                      : const Color(0xFF4F46E5),
                  side: BorderSide(
                    color: isDark
                        ? const Color(0xFF6366F1)
                        : const Color(0xFF4F46E5),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                icon: const Icon(Icons.edit_note, size: 14),
                label: const Text(
                  'সম্পাদনা',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
                onPressed: () => QuestionBankScannerModal.show(
                  context,
                  initialQuestions: questions,
                  initialTitle: exam.title,
                  initialSubject: exam.subject,
                  existingExamId: exam.id,
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  foregroundColor: isDark
                      ? const Color(0xFFA5B4FC)
                      : const Color(0xFF4F46E5),
                  side: BorderSide(
                    color: isDark
                        ? const Color(0xFF6366F1)
                        : const Color(0xFF4F46E5),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                icon: const Icon(Icons.copy_rounded, size: 13),
                label: const Text(
                  'কপি',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
                onPressed: () => _copyExamQuestionsToClipboard(exam, questions),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                icon: const Icon(Icons.auto_fix_high_rounded, size: 13),
                label: const Text(
                  'AI ফিক্স',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
                onPressed: () => QuizBatchCorrectionSheet.show(
                  context,
                  ref: ref,
                  questions: questions,
                  examId: exam.id,
                  topic: exam.topicsCovered,
                  subject: exam.title,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _copyExamQuestionsToClipboard(
    ExamSchedule exam,
    List<QuizQuestion> questions,
  ) {
    final buffer = StringBuffer();
    buffer.writeln('পরীক্ষা: ${exam.title}');
    buffer.writeln('রেফারেন্স: E-${exam.id}');
    if (exam.subject.isNotEmpty) buffer.writeln('বিষয়: ${exam.subject}');
    buffer.writeln('মোট প্রশ্ন: ${questions.length}টি');
    buffer.writeln('==============================\n');

    for (int i = 0; i < questions.length; i++) {
      final q = questions[i];
      buffer.writeln('প্রশ্ন ${i + 1}: ${q.questionText}');
      for (int optIdx = 0; optIdx < q.options.length; optIdx++) {
        final optChar = optIdx == 0
            ? 'ক'
            : (optIdx == 1 ? 'খ' : (optIdx == 2 ? 'গ' : 'ঘ'));
        buffer.writeln('  $optChar. ${q.options[optIdx]}');
      }
      final correctAns =
          q.correctIndex >= 0 && q.correctIndex < q.options.length
          ? q.options[q.correctIndex]
          : 'Unknown';
      buffer.writeln('• সঠিক উত্তর: $correctAns');
      if (q.explanation.isNotEmpty) {
        buffer.writeln('• ব্যাখ্যা: ${q.explanation}');
      }
      buffer.writeln('');
    }
    buffer.writeln('==============================');
    buffer.writeln(
      'নির্দেশনা: উপরের প্রশ্ন ও উত্তরগুলো যাচাই করে কোনো ভুল বা অসঙ্গতি থাকলে চিহ্নিত করুন।',
    );

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Color(0xFF10B981),
        content: Text(
          'পরীক্ষার সকল প্রশ্ন ক্লিপবোর্ডে কপি হয়েছে! অন্য AI-তে পেস্ট করতে পারেন।',
        ),
      ),
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
                labelText: 'Score / Marks obtained',
                hintText: 'e.g. 78.50',
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
            },
            child: const Text('Save Score'),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceBadge(ExamSourceInfo source, bool isDark) {
    Color bg;
    Color border;
    Color text;

    switch (source.kind) {
      case ExamSourceKind.aiMentor:
        bg = isDark ? const Color(0xFF2E1065) : const Color(0xFFF3E8FF);
        border = isDark ? const Color(0xFF7E22CE) : const Color(0xFFD8B4FE);
        text = isDark ? const Color(0xFFD8B4FE) : const Color(0xFF6B21A8);
        break;
      case ExamSourceKind.aiStudyPlan:
        bg = isDark ? const Color(0xFF042F2E) : const Color(0xFFCCFBF1);
        border = isDark ? const Color(0xFF0F766E) : const Color(0xFF5EEAD4);
        text = isDark ? const Color(0xFF5EEAD4) : const Color(0xFF0F766E);
        break;
      case ExamSourceKind.manual:
        bg = isDark ? const Color(0xFF451A03) : const Color(0xFFFEF3C7);
        border = isDark ? const Color(0xFFB45309) : const Color(0xFFFDE68A);
        text = isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E);
        break;
      case ExamSourceKind.pdfImport:
        bg = isDark ? const Color(0xFF172554) : const Color(0xFFEFF6FF);
        border = isDark ? const Color(0xFF1D4ED8) : const Color(0xFFBFDBFE);
        text = isDark ? const Color(0xFF93C5FD) : const Color(0xFF1E40AF);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: border, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(source.icon, size: 10.5, color: text),
          const SizedBox(width: 3.5),
          Flexible(
            child: Text(
              source.label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: text,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
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
                Text(
                  'ট্র্যাক পরিবর্তন করুন',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return tracksAsync.when(
      loading: () => const SizedBox(height: 48),
      error: (_, _) => const SizedBox.shrink(),
      data: (tracks) {
        final allTracks = ['All', ...tracks];
        return Container(
          height: 48,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF111827) : Colors.white,
            border: Border(
              bottom: BorderSide(
                color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade200,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: allTracks.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final track = allTracks[index];
                    final isSelected = selectedTrack == track;
                    final isAll = track == 'All';

                    return ChoiceChip(
                      showCheckmark: false,
                      avatar: isAll
                          ? Icon(
                              Icons.layers,
                              size: 14,
                              color: isSelected ? Colors.white : Colors.indigo,
                            )
                          : Icon(
                              Icons.bookmark,
                              size: 14,
                              color: isSelected
                                  ? _getTrackColor(track)
                                  : Colors.grey,
                            ),
                      selected: isSelected,
                      label: Text(
                        isAll ? 'All Programs' : track,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected
                              ? (isAll
                                  ? Colors.white
                                  : (isDark
                                      ? Colors.white
                                      : _getTrackColor(track)))
                              : (isDark ? Colors.white70 : Colors.black87),
                        ),
                      ),
                      selectedColor: isAll
                          ? Colors.indigo
                          : _getTrackBackgroundColor(track, isDark),
                      backgroundColor: isDark
                          ? const Color(0xFF1E293B)
                          : Colors.grey.shade50,
                      side: BorderSide(
                        color: isSelected
                            ? (isAll ? Colors.indigo : _getTrackColor(track))
                            : (isDark
                                ? const Color(0xFF334155)
                                : Colors.grey.shade300),
                        width: isSelected ? 1.5 : 1,
                      ),
                      onSelected: (_) {
                        ref.read(selectedTrackProvider.notifier).setTrack(track);
                      },
                    );
                  },
                ),
              ),
              if (selectedTrack != 'All') ...[
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Tooltip(
                    message: '“$selectedTrack” ট্র্যাকের সব পরীক্ষা মুছুন',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _confirmDeleteTrack(context, selectedTrack),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.red.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.delete_outline,
                              size: 14,
                              color: Colors.red,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'ট্র্যাক মুছুন',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDeleteTrack(
    BuildContext context,
    String trackName,
  ) async {
    final db = ref.read(appDatabaseProvider);
    final count = await (db.select(db.examSchedules)
          ..where((t) => t.trackName.equals(trackName)))
        .get()
        .then((list) => list.length);

    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'ট্র্যাকের সব পরীক্ষা মুছবেন?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bookmark, color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      trackName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Colors.red,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'এই ট্র্যাকে মোট $countটি পরীক্ষা রয়েছে।\n\n'
              'ডিলিট করলে এই ট্র্যাকের সবগুলো পরীক্ষা একবারে মুছে যাবে। অন্য কোনো ট্র্যাক বা পরীক্ষা অক্ষত থাকবে।\n\n'
              'আপনি কি নিশ্চিতভাবে এই ট্র্যাকের সব পরীক্ষা মুছে ফেলতে চান?',
              style: const TextStyle(fontSize: 12.5, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('বাতিল'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.delete_forever, size: 16),
            label: Text('হ্যাঁ, $countটি পরীক্ষা মুছুন'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final deletedCount = await ref
          .read(examScheduleNotifierProvider.notifier)
          .deleteExamsByTrack(trackName);

      // Reset filter to All Programs
      ref.read(selectedTrackProvider.notifier).setTrack('All');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade800,
            behavior: SnackBarBehavior.floating,
            content: Text(
              '“$trackName” ট্র্যাকের $deletedCountটি পরীক্ষা সফলভাবে মুছে ফেলা হয়েছে।',
            ),
          ),
        );
      }
    }
  }

  Color _getTrackColor(String track) {
    final lower = track.toLowerCase();
    if (lower.contains('vocab')) return Colors.orange.shade800;
    if (lower.contains('friday') ||
        lower.contains('mega') ||
        lower.contains('model')) {
      return Colors.teal.shade800;
    }
    if (lower.contains('135') ||
        lower.contains('140') ||
        lower.contains('200') ||
        lower.contains('bcs')) {
      return Colors.deepPurple.shade700;
    }
    if (lower.contains('primary')) return Colors.blue.shade800;
    return Colors.indigo.shade800;
  }

  Color _getTrackBackgroundColor(String track, [bool isDark = false]) {
    final lower = track.toLowerCase();
    if (lower.contains('vocab')) {
      return isDark
          ? Colors.orange.withValues(alpha: 0.2)
          : Colors.orange.shade50;
    }
    if (lower.contains('friday') ||
        lower.contains('mega') ||
        lower.contains('model')) {
      return isDark ? Colors.teal.withValues(alpha: 0.2) : Colors.teal.shade50;
    }
    if (lower.contains('135') ||
        lower.contains('140') ||
        lower.contains('200') ||
        lower.contains('bcs')) {
      return isDark
          ? Colors.deepPurple.withValues(alpha: 0.2)
          : Colors.deepPurple.shade50;
    }
    if (lower.contains('primary')) {
      return isDark ? Colors.blue.withValues(alpha: 0.2) : Colors.blue.shade50;
    }
    return isDark
        ? Colors.indigo.withValues(alpha: 0.2)
        : Colors.indigo.shade50;
  }

  Widget _buildSummarizerTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'LiveMCQ Study Material & PDF Summarizer',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'Paste study notes or text extracted from LiveMCQ study sheets. Gemini AI will synthesize 5 high-yield bullet points, past exam questions, and memory mnemonics.',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _subjectController,
            decoration: const InputDecoration(
              labelText: 'Subject (e.g. Bangla Grammar, Math, Science)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _studySheetController,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Paste study sheet text or topics here...',
              border: OutlineInputBorder(),
              hintText: 'e.g. কারক ও বিভক্তি: বাক্যের ক্রিয়ার সাথে অন্য পদের সম্বন্ধ...',
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: _isSummarizing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(
                _isSummarizing
                    ? 'Synthesizing with AI...'
                    : 'Generate 5-Point Summary',
              ),
              onPressed: _isSummarizing ? null : _runSummarizer,
            ),
          ),
          const SizedBox(height: 20),
          if (_summaryResult != null) _buildSummaryDisplay(_summaryResult!),
        ],
      ),
    );
  }

  Future<void> _runSummarizer() async {
    final text = _studySheetController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please paste some study text first.')),
      );
      return;
    }

    setState(() {
      _isSummarizing = true;
    });

    final summary = await GeminiAiService.instance.summarizeStudySheet(
      content: text,
      subject: _subjectController.text.trim(),
    );

    setState(() {
      _isSummarizing = false;
      _summaryResult = summary;
    });
  }

  Widget _buildSummaryDisplay(StudySheetSummary summary) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? const Color(0xFF334155) : Colors.transparent,
        ),
      ),
      color: isDark ? const Color(0xFF111827) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.stars, color: Colors.amber, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    summary.title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                ),
              ],
            ),
            Divider(
              height: 24,
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            ),
            Text(
              '🎯 5 High-Yield Bullet Points:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            ...summary.highYieldPoints.asMap().entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${entry.key + 1}. ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isDark ? const Color(0xFF818CF8) : Colors.indigo,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        BengaliMathSanitizer.sanitize(entry.value),
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: isDark
                              ? const Color(0xFFE2E8F0)
                              : const Color(0xFF1E293B),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (summary.recurringPastQuestions.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                '🔄 Recurring Past Exam Traps:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 6),
              ...summary.recurringPastQuestions.map(
                (q) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '• ',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? const Color(0xFF818CF8)
                              : Colors.indigo,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          BengaliMathSanitizer.sanitize(q),
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: isDark
                                ? const Color(0xFFCBD5E1)
                                : const Color(0xFF334155),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (summary.mnemonics.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                '🧠 Memory Shortcut (Mnemonic):',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 6),
              ...summary.mnemonics.map(
                (m) => Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.purple.withValues(alpha: 0.25)
                        : Colors.purple.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark
                          ? Colors.purple.withValues(alpha: 0.5)
                          : Colors.purple.shade100,
                    ),
                  ),
                  child: Text(
                    m,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? Colors.purple.shade200
                          : Colors.purple.shade900,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark
                      ? const Color(0xFF3B82F6)
                      : const Color(0xFF1E3A8A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.psychology, size: 18),
                label: const Text(
                  '🎯 5-Question LiveMCQ Drill',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
                onPressed: () {
                  QuizDrillModal.show(
                    context,
                    topic: summary.title,
                    subject: _subjectController.text.trim().isNotEmpty
                        ? _subjectController.text.trim()
                        : 'LiveMCQ Study Sheet',
                  );
                },
              ),
            ),
          ],
        ),
      ),
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
                        labelText: 'Enter Custom Program Name',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'Exam Title (e.g. Day-12: Bangla Grammar)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: topicsController,
                    decoration: const InputDecoration(
                      labelText: 'Topics Covered',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: summaryController,
                    decoration: const InputDecoration(
                      labelText: 'Resource Summary / Target Marks',
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
                Text(
                  'Import Routine (AI / Text)',
                  style: TextStyle(fontSize: 16),
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
                        labelText: 'Specify Program / Track Name',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx)
                          .colorScheme
                          .primaryContainer
                          .withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(ctx)
                            .colorScheme
                            .primary
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
                      hintText:
                          'e.g.\n{"track_name": "52nd BCS", "exams": [...]}\nOR\n52nd BCS 135 Days Routine:\n28 Oct | 10:00 PM | Bangla: কারক ও বিভক্তি',
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
              userMessage:
                  'রুটিন PDF থেকে কোনো পরীক্ষার তথ্য পাওয়া যায়নি। ফাইলটি স্পষ্ট কিনা যাচাই করুন।',
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
