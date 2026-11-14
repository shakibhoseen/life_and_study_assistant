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
import '../../../../core/theme/fluent_tokens.dart';
import '../../../../core/widgets/animated_premium_background.dart';
import '../../../../core/widgets/premium_glass_card.dart';
import '../../../../core/widgets/premium_ui_kit.dart';
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
        title: Text(
          'LiveMCQ Hub',
          style: FluentType.subtitle.copyWith(fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.quiz_outlined),
            tooltip: 'বিসিএস প্রশ্ন ব্যাংক প্র্যাকটিস',
            onPressed: () => _openBcsQuestionBank(context),
          ),
          IconButton(
            icon: const Icon(Icons.document_scanner_outlined),
            tooltip: 'প্রশ্ন ব্যাংক স্ক্যান করে এক্সাম তৈরি',
            onPressed: () => QuestionBankScannerModal.show(context),
          ),
          IconButton(
            icon: const Icon(Icons.mic),
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
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  foregroundColor: Theme.of(context).colorScheme.primary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: FluentRadius.controlBorder,
                    side: FluentStroke.side(Theme.of(context).brightness),
                  ),
                  tooltip: 'প্রশ্ন ব্যাংক স্ক্যান করে এক্সাম',
                  onPressed: () => QuestionBankScannerModal.show(context),
                  child: const Icon(Icons.document_scanner_outlined, size: 20),
                ),
                const SizedBox(height: FluentSpacing.m),
                FloatingActionButton.small(
                  heroTag: 'fab_screenshot_mistake_mcq',
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  foregroundColor: Theme.of(context).colorScheme.primary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: FluentRadius.controlBorder,
                    side: FluentStroke.side(Theme.of(context).brightness),
                  ),
                  tooltip: 'LiveMCQ স্ক্রিনশট থেকে ভুল সেভ',
                  onPressed: () => _pickAndParseScreenshotMistake(context),
                  child: const Icon(Icons.add_photo_alternate_rounded, size: 20),
                ),
                const SizedBox(height: FluentSpacing.m),
                FloatingActionButton.small(
                  heroTag: 'fab_voice_bubble_mcq',
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  foregroundColor: Theme.of(context).colorScheme.primary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: FluentRadius.controlBorder,
                    side: FluentStroke.side(Theme.of(context).brightness),
                  ),
                  tooltip: 'Voice Mistake Note & Floating Bubble',
                  onPressed: () => VoiceMistakeBottomSheet.show(context),
                  child: const Icon(Icons.mic, size: 20),
                ),
                const SizedBox(height: FluentSpacing.m),
                FloatingActionButton.extended(
                  heroTag: 'fab_add_exam_mcq',
                  elevation: 0,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: FluentRadius.controlBorder,
                  ),
                  icon: const Icon(Icons.add),
                  label: Text('Add Exam', style: FluentType.bodyStrong),
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
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.35),
                      ),
                      const SizedBox(height: FluentSpacing.m),
                      Text(
                        selectedTrack == 'All'
                            ? 'No LiveMCQ exams scheduled'
                            : 'No exams found under "$selectedTrack"',
                        textAlign: TextAlign.center,
                        style: FluentType.body.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                      if (selectedTrack != 'All') ...[
                        const SizedBox(height: FluentSpacing.s),
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;

    if (currentFilter == ExamTimelineFilter.upcoming) {
      if (upcomingExams.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(FluentSpacing.xxl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 56,
                  color: const Color(0xFF10B981),
                ),
                const SizedBox(height: FluentSpacing.m),
                Text(
                  'No upcoming exams right now!',
                  textAlign: TextAlign.center,
                  style: FluentType.subtitle.copyWith(
                    fontSize: 16,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: FluentSpacing.xs),
                Text(
                  pastExams.isNotEmpty
                      ? '${pastExams.length} past exams have already occurred or passed.'
                      : 'Add an exam or import a routine to get started.',
                  textAlign: TextAlign.center,
                  style: FluentType.caption.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
                if (pastExams.isNotEmpty) ...[
                  const SizedBox(height: FluentSpacing.l),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: FluentRadius.controlBorder,
                      ),
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
            margin: const EdgeInsets.only(
              top: FluentSpacing.s,
              bottom: FluentSpacing.xl,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: FluentSpacing.m,
              vertical: FluentSpacing.m,
            ),
            decoration: BoxDecoration(
              color: theme.cardTheme.color ?? theme.cardColor,
              borderRadius: FluentRadius.cardBorder,
              border: Border.all(
                color: FluentStroke.card(brightness),
                width: FluentStroke.width,
              ),
              boxShadow: FluentElevation.card(brightness),
            ),
            child: Row(
              children: [
                PremiumIconBadge(
                  icon: Icons.history,
                  size: 28,
                  iconSize: 16,
                  color: scheme.onSurface.withValues(alpha: 0.65),
                ),
                const SizedBox(width: FluentSpacing.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${pastExams.length} past exam(s) archived',
                        style: FluentType.bodyStrong.copyWith(
                          fontSize: 13,
                          color: scheme.onSurface,
                        ),
                      ),
                      Text(
                        'Older dates are archived so you can focus on upcoming tests.',
                        style: FluentType.caption.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: FluentSpacing.s),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: scheme.primary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: FluentRadius.controlBorder,
                    ),
                    side: FluentStroke.side(brightness),
                    padding: const EdgeInsets.symmetric(
                      horizontal: FluentSpacing.m,
                      vertical: FluentSpacing.s,
                    ),
                    textStyle: FluentType.caption.copyWith(
                      fontWeight: FontWeight.w600,
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
                color: scheme.onSurface.withValues(alpha: 0.35),
              ),
              const SizedBox(height: FluentSpacing.m),
              Text(
                'No past exams found',
                textAlign: TextAlign.center,
                style: FluentType.bodyStrong.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
              const SizedBox(height: FluentSpacing.s),
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
              margin: const EdgeInsets.only(bottom: FluentSpacing.m),
              padding: const EdgeInsets.symmetric(
                horizontal: FluentSpacing.m,
                vertical: FluentSpacing.s,
              ),
              decoration: BoxDecoration(
                color: FluentLayer.subtle(scheme.primary, brightness),
                borderRadius: FluentRadius.cardBorder,
                border: Border.all(
                  color: FluentStroke.card(brightness),
                  width: FluentStroke.width,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: scheme.primary),
                  const SizedBox(width: FluentSpacing.s),
                  Expanded(
                    child: Text(
                      'Showing ${pastExams.length} past exams (most recent first). Tap "Drill Topic" to practice.',
                      style: FluentType.caption.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.85),
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
                color: scheme.onSurface.withValues(alpha: 0.35),
              ),
              const SizedBox(height: FluentSpacing.m),
              Text(
                'No completed exams yet',
                textAlign: TextAlign.center,
                style: FluentType.bodyStrong.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
              const SizedBox(height: FluentSpacing.s),
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
              padding: EdgeInsets.only(bottom: FluentSpacing.m),
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
            color: scheme.primary,
          ),
          ...upcomingExams.map((e) => _buildExamCard(e, todayStart)),
          const SizedBox(height: FluentSpacing.l),
        ],
        if (pastExams.isNotEmpty || completedExams.isNotEmpty) ...[
          _buildSectionHeaderCard(
            title:
                '📜 Past & Completed Exams (${pastExams.length + completedExams.length})',
            color: scheme.onSurface.withValues(alpha: 0.45),
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
  }) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(
        bottom: FluentSpacing.s,
        top: FluentSpacing.xs,
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 20,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
          const SizedBox(width: FluentSpacing.m),
          Expanded(
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: FluentType.bodyStrong.copyWith(color: scheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExamCard(ExamSchedule exam, DateTime todayStart) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    final isDark = brightness == Brightness.dark;
    final examDateOnly = DateTime(
      exam.examDate.year,
      exam.examDate.month,
      exam.examDate.day,
    );
    final daysDiff = examDateOnly.difference(todayStart).inDays;
    final isToday = daysDiff == 0;
    final isTomorrow = daysDiff == 1;
    final isPast = daysDiff < 0;

    // Status accents. Green and amber stay because they carry meaning here:
    // done vs. happening today. Everything else is neutral.
    const doneAccent = Color(0xFF10B981);
    const todayAccent = Color(0xFFF59E0B);
    final baseSurface = theme.cardTheme.color ?? theme.cardColor;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: FluentSpacing.m),
      shape: RoundedRectangleBorder(
        borderRadius: FluentRadius.cardBorder,
        side: BorderSide(
          color: exam.completedStatus
              ? doneAccent.withValues(alpha: 0.45)
              : isToday
              ? todayAccent.withValues(alpha: 0.55)
              : FluentStroke.card(brightness),
          width: FluentStroke.width,
        ),
      ),
      color: isToday
          ? Color.alphaBlend(
              FluentLayer.subtle(todayAccent, brightness),
              baseSurface,
            )
          : (exam.completedStatus
                ? Color.alphaBlend(
                    FluentLayer.subtle(doneAccent, brightness),
                    baseSurface,
                  )
                : baseSurface),
      child: Padding(
        padding: const EdgeInsets.all(FluentSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Badge Row
            Row(
              children: [
                // Track Pill
                Flexible(
                  child: PremiumTag(
                    label: exam.trackName,
                    icon: Icons.bookmark_outline,
                    color: _getTrackColor(exam.trackName),
                  ),
                ),
                const SizedBox(width: FluentSpacing.s),

                // Status Badge (Today / Tomorrow / in X d / Passed / Done)
                Flexible(
                  child: PremiumTag(
                    label: exam.completedStatus
                        ? 'Done ✓'
                        : isToday
                        ? 'TODAY 🎯'
                        : isTomorrow
                        ? 'Tomorrow ⏳'
                        : isPast
                        ? 'Passed (${-daysDiff}d ago)'
                        : 'in $daysDiff d',
                    icon: isToday && !exam.completedStatus
                        ? Icons.stars
                        : null,
                    color: exam.completedStatus
                        ? doneAccent
                        : isToday
                        ? todayAccent
                        : isPast
                        ? scheme.error
                        : scheme.primary,
                  ),
                ),
                const Spacer(),

                // Calendar date text
                Text(
                  _formatExamDate(exam.examDate),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FluentType.caption.copyWith(
                    fontWeight: isToday ? FontWeight.w600 : FontWeight.w400,
                    color: isToday
                        ? todayAccent
                        : scheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),

                const SizedBox(width: FluentSpacing.xs),
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
                  borderRadius: FluentRadius.controlBorder,
                  onTap: () => _copyExamRef(exam.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FluentSpacing.xs,
                      vertical: FluentSpacing.xxs,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.copy,
                          size: 12,
                          color: scheme.onSurface.withValues(alpha: 0.45),
                        ),
                        const SizedBox(width: FluentSpacing.xs),
                        Flexible(
                          child: Text(
                            EntityRef(EntityKind.exam, exam.id).tag,
                            style: FluentType.caption.copyWith(
                              fontFamily: 'monospace',
                              letterSpacing: 0.4,
                              color: scheme.onSurface.withValues(alpha: 0.45),
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
              style: FluentType.bodyStrong.copyWith(
                fontSize: 15,
                decoration: exam.completedStatus
                    ? TextDecoration.lineThrough
                    : null,
                color: exam.completedStatus
                    ? scheme.onSurface.withValues(alpha: 0.45)
                    : scheme.onSurface,
              ),
            ),
            const SizedBox(height: FluentSpacing.s),

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
                padding: const EdgeInsets.only(top: FluentSpacing.s),
                child: Container(
                  padding: const EdgeInsets.all(FluentSpacing.s),
                  decoration: BoxDecoration(
                    color: scheme.onSurface.withValues(alpha: 0.04),
                    borderRadius: FluentRadius.cardBorder,
                    border: Border.all(
                      color: FluentStroke.card(brightness),
                      width: FluentStroke.width,
                    ),
                  ),
                  child: Text(
                    summaryText,
                    style: FluentType.caption.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ),
              );
            }(),

            const SizedBox(height: FluentSpacing.m),

            // Bottom Quick Action Bar: Drill Topic & Done toggle
            Row(
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FluentSpacing.m,
                      vertical: FluentSpacing.xs + 2,
                    ),
                    visualDensity: VisualDensity.compact,
                    foregroundColor: scheme.primary,
                    side: FluentStroke.side(brightness),
                    shape: RoundedRectangleBorder(
                      borderRadius: FluentRadius.controlBorder,
                    ),
                  ),
                  icon: const Icon(Icons.psychology, size: 15),
                  label: Text('Drill Topic', style: FluentType.caption.copyWith(
                    fontWeight: FontWeight.w600,
                  )),
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
                const SizedBox(width: FluentSpacing.s),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FluentSpacing.s,
                      vertical: FluentSpacing.xs + 2,
                    ),
                    visualDensity: VisualDensity.compact,
                    foregroundColor: scheme.onSurface.withValues(alpha: 0.75),
                    side: FluentStroke.side(brightness),
                    shape: RoundedRectangleBorder(
                      borderRadius: FluentRadius.controlBorder,
                    ),
                  ),
                  icon: const Icon(Icons.timer_outlined, size: 14),
                  label: Text('টাইমার', style: FluentType.caption.copyWith(
                    fontWeight: FontWeight.w600,
                  )),
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
                  const SizedBox(width: FluentSpacing.s),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: FluentSpacing.s,
                        vertical: FluentSpacing.xs + 2,
                      ),
                      visualDensity: VisualDensity.compact,
                      foregroundColor: scheme.primary,
                      side: FluentStroke.side(brightness),
                      backgroundColor: FluentLayer.subtle(
                        scheme.primary,
                        brightness,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: FluentRadius.controlBorder,
                      ),
                    ),
                    icon: const Icon(Icons.mic, size: 14),
                    label: Text('Voice Mistake', style: FluentType.caption
                        .copyWith(fontWeight: FontWeight.w600)),
                    onPressed: () => VoiceMistakeBottomSheet.show(context),
                  ),
                ],
                const SizedBox(width: FluentSpacing.s),
                IconButton(
                  style: IconButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: scheme.primary,
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
                        horizontal: FluentSpacing.s,
                        vertical: FluentSpacing.xs + 2,
                      ),
                      visualDensity: VisualDensity.compact,
                      foregroundColor: isDark
                          ? const Color(0xFF34D399)
                          : const Color(0xFF047857),
                    ),
                    icon: const Icon(Icons.check, size: 15),
                    label: Text('Mark Done', style: FluentType.caption.copyWith(
                      fontWeight: FontWeight.w600,
                    )),
                    onPressed: () {
                      _showScoreDialog(context, exam);
                    },
                  )
                else
                  Flexible(
                    child: Text(
                      'Score: ${exam.score != null ? "${exam.score!.toStringAsFixed(1)} marks" : "Completed ✓"}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FluentType.caption.copyWith(
                        color: isDark
                            ? const Color(0xFF34D399)
                            : const Color(0xFF047857),
                        fontWeight: FontWeight.w600,
                      ),
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
        final scheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: FluentRadius.cardBorder,
          ),
          title: Row(
            children: [
              Icon(Icons.menu_book_rounded, color: scheme.primary),
              const SizedBox(width: FluentSpacing.s),
              Expanded(
                child: Text(
                  exam.title,
                  style: FluentType.bodyStrong.copyWith(fontSize: 15),
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
                  style: FluentType.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
                const SizedBox(height: FluentSpacing.s),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(FluentSpacing.m),
                  decoration: BoxDecoration(
                    color: scheme.onSurface.withValues(alpha: 0.04),
                    borderRadius: FluentRadius.cardBorder,
                    border: Border.all(
                      color: FluentStroke.card(Theme.of(ctx).brightness),
                      width: FluentStroke.width,
                    ),
                  ),
                  child: SelectableText(
                    'Topics: ${exam.topicsCovered}',
                    style: FluentType.body.copyWith(color: scheme.onSurface),
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
            Text(exam.title, style: FluentType.bodyStrong),
            const SizedBox(height: FluentSpacing.m),
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
          final scheme = Theme.of(ctx).colorScheme;
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: FluentRadius.cardBorder,
            ),
            title: Row(
              children: [
                Icon(Icons.bookmark_outline, color: scheme.primary),
                const SizedBox(width: FluentSpacing.s),
                Flexible(
                  child: Text(
                    'ট্র্যাক পরিবর্তন করুন',
                    style: FluentType.subtitle.copyWith(fontSize: 16),
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
                    style: FluentType.caption.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                  const SizedBox(height: FluentSpacing.m),
                  Text(
                    'ট্র্যাক নির্বাচন করুন:',
                    style: FluentType.bodyStrong.copyWith(fontSize: 13),
                  ),
                  const SizedBox(height: FluentSpacing.s),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FluentSpacing.m,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: FluentStroke.card(Theme.of(ctx).brightness),
                        width: FluentStroke.width,
                      ),
                      borderRadius: FluentRadius.controlBorder,
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: isCustom ? 'custom' : selected,
                        dropdownColor: scheme.surface,
                        items: [
                          ...suggestions.map(
                            (t) => DropdownMenuItem(
                              value: t,
                              child: Text(
                                t,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: FluentType.body.copyWith(fontSize: 13),
                              ),
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'custom',
                            child: Text(
                              '+ নতুন ট্র্যাক লিখুন (Custom)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: FluentType.body.copyWith(
                                fontSize: 13,
                                color: scheme.primary,
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
                    const SizedBox(height: FluentSpacing.m),
                    TextField(
                      controller: customController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'নতুন ট্র্যাকের নাম (যেমন: Self Test)',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: FluentSpacing.m,
                          vertical: FluentSpacing.m,
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

  Widget _buildSummarizerTab() {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(FluentSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'পড়ার নোট ও PDF থেকে সারাংশ',
            style: FluentType.subtitle.copyWith(fontSize: 16),
          ),
          const SizedBox(height: FluentSpacing.s),
          Text(
            'পড়ার নোট বা স্টাডি শিটের লেখা পেস্ট করুন। ৫টি গুরুত্বপূর্ণ পয়েন্ট, '
            'বিগত পরীক্ষার প্রশ্ন আর মনে রাখার কৌশল বেরিয়ে আসবে।',
            style: FluentType.caption.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: FluentSpacing.l),
          TextField(
            controller: _subjectController,
            decoration: const InputDecoration(
              labelText: 'বিষয় (যেমন বাংলা ব্যাকরণ, গণিত, বিজ্ঞান)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: FluentSpacing.m),
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
                const SizedBox(width: FluentSpacing.m),
                Expanded(
                  child: Text(
                    'AI পড়ছে… ${_summarySeconds}s',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FluentType.body.copyWith(fontSize: 13),
                  ),
                ),
                TextButton.icon(
                  onPressed: _cancelSummarizer,
                  icon: const Icon(Icons.stop_circle_outlined, size: 18),
                  label: const Text('থামাও'),
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.error,
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
              padding: const EdgeInsets.only(top: FluentSpacing.s),
              child: Text(
                _studySheetLength > GeminiPrompts.largeStudySheetChars
                    ? 'লেখাটা বড় — $_studySheetLength অক্ষর, পুরোটাই পাঠানো হবে'
                    : '$_studySheetLength অক্ষর',
                style: FluentType.caption.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ),
          const SizedBox(height: FluentSpacing.xl),
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
                    style: FluentType.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(ctx).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: FluentSpacing.s),
                  DropdownButtonFormField<String>(
                    initialValue: selectedTrack,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: FluentSpacing.m,
                        vertical: FluentSpacing.m,
                      ),
                    ),
                    items: defaultTracks
                        .map(
                          (t) => DropdownMenuItem(
                            value: t,
                            child: Text(
                              t,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: FluentType.body.copyWith(fontSize: 13),
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
                    const SizedBox(height: FluentSpacing.s),
                    TextField(
                      controller: customTrackController,
                      decoration: const InputDecoration(
                        labelText: 'প্রোগ্রামের নাম লিখুন',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                  const SizedBox(height: FluentSpacing.m),
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'পরীক্ষার নাম (যেমন Day-12: বাংলা ব্যাকরণ)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: FluentSpacing.m),
                  TextField(
                    controller: topicsController,
                    decoration: const InputDecoration(
                      labelText: 'যে টপিকগুলো আছে',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: FluentSpacing.m),
                  TextField(
                    controller: summaryController,
                    decoration: const InputDecoration(
                      labelText: 'নোট বা লক্ষ্য নম্বর',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: FluentSpacing.m),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Exam Date: ${selectedDate.toIso8601String().substring(0, 10)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FluentType.body.copyWith(fontSize: 13),
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
            title: Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  color: Theme.of(ctx).colorScheme.primary,
                  size: 22,
                ),
                const SizedBox(width: FluentSpacing.s),
                Flexible(
                  child: Text(
                    'Import Routine (AI / Text)',
                    style: FluentType.subtitle.copyWith(fontSize: 16),
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
                    style: FluentType.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(ctx).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: FluentSpacing.s),
                  DropdownButtonFormField<String>(
                    initialValue: selectedTrack,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: FluentSpacing.m,
                        vertical: FluentSpacing.s,
                      ),
                    ),
                    items: trackOptions
                        .map(
                          (t) => DropdownMenuItem(
                            value: t,
                            child: Text(
                              t,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: FluentType.caption,
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
                  const SizedBox(height: FluentSpacing.m),
                  Container(
                    padding: const EdgeInsets.all(FluentSpacing.m),
                    decoration: BoxDecoration(
                      color: FluentLayer.subtle(
                        Theme.of(ctx).colorScheme.primary,
                        Theme.of(ctx).brightness,
                      ),
                      borderRadius: FluentRadius.cardBorder,
                      border: Border.all(
                        color: FluentStroke.card(Theme.of(ctx).brightness),
                        width: FluentStroke.width,
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
                            const SizedBox(width: FluentSpacing.s),
                            Expanded(
                              child: Text(
                                'ChatGPT / Claude দিয়ে রুটিন আনবেন?',
                                style: FluentType.caption.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: FluentSpacing.xs),
                        Text(
                          'প্রম্পট কপি করে ChatGPT বা Claude-এ আপনার রুটিন (PDF/ছবি/টেক্সট) সহ দিন। AI যে JSON কোড দেবে তা নিচে পেস্ট করে সেভ করুন। এতে কোনো টোকেন লিমিট নেই!',
                          style: FluentType.caption.copyWith(
                            color: Theme.of(ctx).colorScheme.onSurface
                                .withValues(alpha: 0.65),
                          ),
                        ),
                        const SizedBox(height: FluentSpacing.s),
                        Wrap(
                          spacing: FluentSpacing.s,
                          runSpacing: FluentSpacing.s,
                          children: [
                            OutlinedButton.icon(
                              icon: const Icon(Icons.copy, size: 14),
                              label: Text(
                                'Copy AI Prompt',
                                style: FluentType.caption,
                              ),
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                shape: RoundedRectangleBorder(
                                  borderRadius: FluentRadius.controlBorder,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: FluentSpacing.m,
                                  vertical: FluentSpacing.xs,
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
                              label: Text(
                                'Paste from Clipboard',
                                style: FluentType.caption,
                              ),
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                shape: RoundedRectangleBorder(
                                  borderRadius: FluentRadius.controlBorder,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: FluentSpacing.m,
                                  vertical: FluentSpacing.xs,
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
                  const SizedBox(height: FluentSpacing.m),
                  Text(
                    'Paste Facebook post text, notice routine, or AI JSON below:',
                    style: FluentType.caption.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurface
                          .withValues(alpha: 0.65),
                    ),
                  ),
                  const SizedBox(height: FluentSpacing.m),
                  TextField(
                    controller: textController,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      hintText: 'e.g.\n{"track_name": "52nd BCS", "exams": [...]}\nOR\n52nd BCS 135 Days Routine:\n28 Oct | 10:00 PM | Bangla: কারক ও বিভক্তি',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: FluentSpacing.s),
                  TextButton.icon(
                    icon: Icon(
                      Icons.flash_on,
                      size: 16,
                      color: Theme.of(ctx).colorScheme.primary,
                    ),
                    label: Text(
                      'Insert Multi-Track Sample Routine',
                      style: FluentType.caption,
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
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        final brightness = Theme.of(ctx).brightness;
        return Container(
          padding: const EdgeInsets.all(FluentSpacing.xl),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(FluentRadius.large),
            ),
            border: Border(
              top: FluentStroke.side(brightness),
              left: FluentStroke.side(brightness),
              right: FluentStroke.side(brightness),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: FluentSpacing.l),
                  decoration: BoxDecoration(
                    color: scheme.onSurface.withValues(alpha: 0.2),
                    borderRadius: FluentRadius.controlBorder,
                  ),
                ),
              ),
              Text(
                'PDF ইম্পোর্ট অপশন',
                style: FluentType.subtitle.copyWith(fontSize: 16),
              ),
              const SizedBox(height: FluentSpacing.l),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: PremiumIconBadge(
                  icon: Icons.calendar_month,
                  color: scheme.primary,
                ),
                title: Text(
                  'পরীক্ষার রুটিন PDF',
                  style: FluentType.bodyStrong,
                ),
                subtitle: const Text(
                  'LiveMCQ বা কোচিং রুটিন থেকে পরীক্ষার তালিকা ও শিডিউল সেভ করুন',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndParsePdf(context);
                },
              ),
              Divider(
                height: FluentSpacing.xl,
                color: FluentStroke.divider(brightness),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: PremiumIconBadge(
                  icon: Icons.menu_book_rounded,
                  color: scheme.primary,
                ),
                title: Text(
                  'পড়ার রিসোর্স / লেকচার শিট PDF',
                  style: FluentType.bodyStrong,
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

    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error_outline, color: scheme.error, size: 24),
            const SizedBox(width: FluentSpacing.s),
            Expanded(
              child: Text(
                'রুটিন নিষ্কাশনে ত্রুটি / Diagnostic',
                style: FluentType.subtitle.copyWith(fontSize: 16),
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
                style: FluentType.bodyStrong.copyWith(fontSize: 13),
              ),
              const SizedBox(height: FluentSpacing.m),

              // Diagnostic Info Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(FluentSpacing.m),
                decoration: BoxDecoration(
                  color: scheme.onSurface.withValues(alpha: 0.04),
                  borderRadius: FluentRadius.cardBorder,
                  border: Border.all(
                    color: FluentStroke.card(brightness),
                    width: FluentStroke.width,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🔍 বিস্তারিত কারণ / Diagnostic Info:',
                      style: FluentType.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: FluentSpacing.s),
                    if (model != null)
                      Text(
                        '• Model: $model',
                        style: FluentType.caption.copyWith(
                          color: scheme.onSurface
                              .withValues(alpha: 0.65),
                        ),
                      ),
                    if (finishReason != null)
                      Text(
                        '• Finish Reason: $finishReason'
                        '${finishReason == "maxTokens" ? " (টোকেন লিমিটের কারণে আউটপুট কেটে গেছে)" : ""}',
                        style: FluentType.caption.copyWith(
                          color: finishReason == "maxTokens"
                              ? Colors.amber.shade700
                              : scheme.onSurface
                                    .withValues(alpha: 0.65),
                          fontWeight: finishReason == "maxTokens"
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    if (tokens != null && tokens > 0)
                      Text(
                        '• Tokens Used: $tokens',
                        style: FluentType.caption.copyWith(
                          color: scheme.onSurface
                              .withValues(alpha: 0.65),
                        ),
                      ),
                    if (technicalDetails != null &&
                        technicalDetails.isNotEmpty) ...[
                      const SizedBox(height: FluentSpacing.xs),
                      Text(
                        '• Details: $technicalDetails',
                        style: FluentType.caption.copyWith(
                          fontFamily: 'monospace',
                          color: scheme.error,
                        ),
                      ),
                    ],
                    if (isTooLarge) ...[
                      const SizedBox(height: FluentSpacing.xs),
                      Text(
                        '⚠️ ফাইল সাইজ Gemini API লিমিটের বেশি। PDF ফাইলটি ছোট করুন বা ChatGPT ব্যবহার করুন।',
                        style: FluentType.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Colors.amber.shade700,
                        ),
                      ),
                    ],
                    if (rawSnippet != null && rawSnippet.isNotEmpty) ...[
                      const SizedBox(height: FluentSpacing.s),
                      Text(
                        'Gemini Raw Output:',
                        style: FluentType.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface
                              .withValues(alpha: 0.65),
                        ),
                      ),
                      const SizedBox(height: FluentSpacing.xxs),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 120),
                        width: double.infinity,
                        padding: const EdgeInsets.all(FluentSpacing.s),
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: FluentRadius.controlBorder,
                          border: Border.all(
                            color: FluentStroke.card(brightness),
                            width: FluentStroke.width,
                          ),
                        ),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            rawSnippet,
                            style: FluentType.caption.copyWith(
                              fontFamily: 'monospace',
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: FluentSpacing.m),
              // Helpful Recommendation Card
              Container(
                padding: const EdgeInsets.all(FluentSpacing.m),
                decoration: BoxDecoration(
                  color: FluentLayer.subtle(scheme.primary, brightness),
                  borderRadius: FluentRadius.cardBorder,
                  border: Border.all(
                    color: FluentStroke.card(brightness),
                    width: FluentStroke.width,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.lightbulb_outline,
                      size: 16,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: FluentSpacing.s),
                    Expanded(
                      child: Text(
                        '💡 বড় বা দীর্ঘমেয়াদী রুটিনের (যেমন ১৩৫ দিনের বিসিএস রুটিন) জন্য ChatGPT বা Claude দিয়ে রুটিন নিয়ে আসুন। নিচের বাটন চেপে প্রম্পট কপি করে ChatGPT-তে আপনার রুটিন দিলেই কোনো টোকেন লিমিট ছাড়া শতভাগ নির্ভুল ফলাফল পাওয়া যাবে!',
                        style: FluentType.caption.copyWith(
                          color: scheme.onSurface
                              .withValues(alpha: 0.65),
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
            label: Text(
              'Copy ChatGPT Prompt',
              style: FluentType.caption,
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
                style: FluentType.bodyStrong.copyWith(color: Colors.white),
              ),
              const SizedBox(height: FluentSpacing.xs),
              Text(
                '📁 $displayLoc',
                style: FluentType.caption.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: FluentSpacing.xxs),
              Text(
                '💡 ফোনের Download ফোল্ডারে ফাইলটি পাবেন।',
                style: FluentType.caption.copyWith(color: Colors.white70),
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
