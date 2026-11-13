import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/premium_glass_card.dart';
import '../../../../core/widgets/premium_ui_kit.dart';
import '../../../../core/widgets/animated_premium_background.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/services/ai/gemini_ai_service.dart';
import '../../../../core/services/ai/models/quiz_question.dart';
import '../../../../core/theme/theme_provider.dart';
import '../../../analytics/presentation/providers/study_streak_provider.dart';
import '../../../analytics/presentation/widgets/github_study_heatmap.dart';
import '../../../focus/presentation/screens/pomodoro_focus_screen.dart';
import '../../../live_mcq/presentation/providers/exam_schedule_provider.dart';
import '../../../live_mcq/presentation/widgets/voice_mistake_bottom_sheet.dart';
import '../../../quiz/presentation/providers/drill_history_provider.dart';
import '../../../quiz/presentation/widgets/quiz_drill_modal.dart';
import '../../../quiz/presentation/widgets/question_bank_scanner_modal.dart';
import '../../../quiz/presentation/widgets/study_sheet_camera_modal.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../spaced_repetition/presentation/providers/spaced_repetition_provider.dart';
import '../../../spaced_repetition/presentation/screens/spaced_repetition_screen.dart';
import '../../../study_planner/presentation/providers/adaptive_planner_provider.dart';
import '../../../study_planner/presentation/widgets/focus_timer_dialog.dart';
import '../../../weakness_healer/presentation/widgets/weakness_healing_drill_modal.dart';
import '../../../topics/presentation/providers/topics_provider.dart';
import '../../../mistake_notebook/presentation/screens/mistake_notebook_screen.dart';
import '../../../mistake_notebook/presentation/widgets/nightly_review_modal.dart';
import '../../../weakness_healer/presentation/widgets/weakness_healing_card.dart';
import '../../../analytics/presentation/providers/today_activity_provider.dart';
import '../../domain/next_study_action.dart';
import '../../domain/today_progress.dart';
import '../widgets/biometric_status_banner.dart';
import '../widgets/attention_card.dart';
import '../widgets/next_action_card.dart';
import '../widgets/today_progress_strip.dart';
import '../widgets/energy_tracker_card.dart';
import '../widgets/multi_track_exam_countdown_card.dart';
import '../widgets/study_plan_card.dart';
import '../../../weekly_routine/presentation/widgets/weekly_routine_card.dart';
import '../widgets/next_exam_revision_card.dart';
import '../widgets/exam_accountability_card.dart';
import '../widgets/weekly_study_goal_card.dart';
import '../../../live_mcq/presentation/widgets/exam_score_analytics_card.dart';
import '../../../image_to_text/presentation/screens/image_to_text_screen.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upcomingExams = ref.watch(upcomingExamsStreamProvider).value ?? [];
    final weakTopics = ref.watch(weakTopicsStreamProvider).value ?? [];
    final wrongQuestions = ref.watch(wrongQuestionsStreamProvider).value ?? [];
    final dueSpacedReviews =
        ref.watch(dueSpacedReviewsStreamProvider).value ?? [];
    final settings = ref.watch(settingsNotifierProvider).value;
    final hasGeminiKey = GeminiAiService.instance.hasApiKey;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final streak = ref.watch(studyStreakProvider).value ?? 0;
    final modelName = settings?.geminiModel ?? 'gemini-flash-lite-latest';
    final pillLabel = hasGeminiKey
        ? (modelName.contains('pro') ? 'Gemini Pro 🧠' : 'Gemini Flash ⚡')
        : 'AI Offline Fallback';

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/branding/playstore_icon_512.png',
                width: 32,
                height: 32,
                fit: BoxFit.cover,
                semanticLabel: 'অ্যাপ লোগো',
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.school, size: 28, color: Colors.indigo),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Life & Study',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  Text(
                    'Engineer & BCS Companion',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: isDark
                  ? (streak > 0
                        ? Colors.orange.withValues(alpha: 0.18)
                        : Colors.white10)
                  : (streak > 0
                        ? Colors.orange.shade50
                        : const Color(0xFFF1F5F9)),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark
                    ? (streak > 0 ? Colors.orangeAccent : Colors.white24)
                    : (streak > 0
                          ? Colors.orange.shade300
                          : const Color(0xFFCBD5E1)),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  streak > 0 ? '🔥' : '⚡',
                  style: const TextStyle(fontSize: 11),
                ),
                const SizedBox(width: 3),
                Text(
                  streak > 0 ? '$streak দিন' : 'স্ট্রিক',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: isDark
                        ? (streak > 0 ? Colors.orangeAccent : Colors.white70)
                        : (streak > 0
                              ? Colors.orange.shade900
                              : const Color(0xFF475569)),
                  ),
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: isDark
                  ? (hasGeminiKey
                        ? Colors.green.withValues(alpha: 0.18)
                        : Colors.amber.withValues(alpha: 0.18))
                  : (hasGeminiKey
                        ? Colors.green.shade50
                        : Colors.amber.shade50),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasGeminiKey
                    ? (isDark ? Colors.greenAccent : Colors.green.shade200)
                    : (isDark ? Colors.amber : Colors.amber.shade200),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.smart_toy_outlined,
                  size: 13,
                  color: isDark
                      ? (hasGeminiKey ? Colors.greenAccent : Colors.amber)
                      : (hasGeminiKey
                            ? Colors.green.shade800
                            : Colors.amber.shade800),
                ),
                const SizedBox(width: 4),
                Text(
                  pillLabel,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: isDark
                        ? (hasGeminiKey ? Colors.greenAccent : Colors.amber)
                        : (hasGeminiKey
                              ? Colors.green.shade800
                              : Colors.amber.shade800),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Animated gradient background fills the entire body.
          const Positioned.fill(child: AnimatedGradientBackground(child: SizedBox.expand())),
          // Floating orbs behind content.
          const FloatingOrb(top: 40, left: -40, size: 240, opacity: 0.07),
          const FloatingOrb(bottom: 80, right: -60, size: 200, opacity: 0.07),
          // Scrollable content on top.
          RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(upcomingExamsStreamProvider);
              ref.invalidate(weakTopicsStreamProvider);
              ref.invalidate(studyStreakProvider);
            },
            child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 0. The one thing to start now.
              //
              // Above everything else on purpose: the cards below offer six
              // separate calls to action and rank none of them, and choosing
              // between six is the hard part after a day's work.
              _buildNextAction(
                context,
                ref,
                dueSpacedReviews: dueSpacedReviews,
                wrongQuestions: wrongQuestions,
                weakTopics: weakTopics,
                streak: streak,
              ),
              const SizedBox(height: 6),
              PremiumSectionHeader(
                icon: Icons.event_available_outlined,
                label: 'পরীক্ষার দায়বদ্ধতা',
                subtitle: 'Exam accountability tracker',
              ),
              const SizedBox(height: 8),
              const ExamAccountabilityCard(),
              _buildTodayProgress(ref),
              const SizedBox(height: 10),
              _buildAttention(
                context,
                dueSpacedReviews: dueSpacedReviews,
                wrongQuestions: wrongQuestions,
                weakTopics: weakTopics,
              ),
              const SizedBox(height: 14),

              // 0.5. Quick Action & Productivity Bar
              PremiumSectionHeader(
                icon: Icons.flash_on_outlined,
                label: 'Quick Actions',
                subtitle: 'সব টুলে দ্রুত পৌঁছান',
              ),
              const SizedBox(height: 8),
              _buildQuickActionStrip(context, ref),
              const SizedBox(height: 14),

              // 1. Office & Attendance Status Banner
              const BiometricStatusBanner(),
              const SizedBox(height: 16),

              // 2. Post-work Energy & Mood Tracker
              PremiumSectionHeader(
                icon: Icons.battery_charging_full_outlined,
                label: 'এনার্জি ও মুড ট্র্যাকার',
                subtitle: 'Post-work energy log',
              ),
              const SizedBox(height: 8),
              const EnergyTrackerCard(),
              const SizedBox(height: 16),

              // 3. Adaptive AI Study Routine
              // Above the plan: the night before an exam, what that exam
              // covers beats a general schedule.
              const NextExamRevisionCard(),
              PremiumSectionHeader(
                icon: Icons.auto_stories_outlined,
                label: 'AI স্টাডি রুটিন',
                subtitle: 'আজকের পড়ার পরিকল্পনা',
              ),
              const SizedBox(height: 8),
              const StudyPlanCard(),

              const SizedBox(height: 16),
              const WeeklyRoutineCard(),
              const SizedBox(height: 16),

              // 3.5. Weekly Study Goal & Exam Score Analytics
              const WeeklyStudyGoalCard(),
              const SizedBox(height: 16),
              const ExamScoreAnalyticsCard(),
              const SizedBox(height: 16),

              // 4. GitHub-Style Study Activity Heatmap & Analytics
              PremiumSectionHeader(
                icon: Icons.insights_outlined,
                label: 'পড়ার অ্যানালিটিক্স',
                subtitle: 'Study streak & heatmap',
              ),
              const SizedBox(height: 8),
              const GithubStudyHeatmap(),
              const SizedBox(height: 16),

              // 5. Spaced Repetition (Forgetting Curve) & Office Flashcards Card
              _buildSpacedRepetitionCard(context, dueSpacedReviews.length),
              const SizedBox(height: 16),

              // 6. Mistake Bank Spotlight (if mistakes exist)
              if (wrongQuestions.isNotEmpty) ...[
                _buildMistakeBankSection(context, wrongQuestions),
                const SizedBox(height: 16),
              ],

              // 7. Multi-Track Exam Timeline & Live Countdown Card
              if (upcomingExams.isNotEmpty) ...[
                MultiTrackExamCountdownCard(exams: upcomingExams),
                const SizedBox(height: 16),
              ],

              // 7.5. Auto-Weakness Healer Card (Daily 3-Min Micro Drill - Optional & Configurable)
              const WeaknessHealingCard(),
              const SizedBox(height: 16),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
        ],
      ),
    );
  }

  /// Chooses the next job and says what starting it does.
  ///
  /// The choosing lives in [pickNextStudyAction]; what is here is only the
  /// wiring to the screens that already do each of these, so none of that work
  /// is written a second time.
  Widget _buildNextAction(
    BuildContext context,
    WidgetRef ref, {
    required List<SpacedReviewItem> dueSpacedReviews,
    required List<DrillQuestion> wrongQuestions,
    required List<WeakTopic> weakTopics,
    required int streak,
  }) {
    // The first task of today's plan that is not ticked off. The plan sized it
    // to today's energy already, so it beats anything this screen would guess.
    final plan = ref.watch(adaptivePlannerProvider).value;
    final pending = plan?.tasks.where((t) => !t.isCompleted).firstOrNull;

    final action = pickNextStudyAction(
      dueReviews: dueSpacedReviews.length,
      unfinishedTaskTitle: pending?.title,
      unfinishedTaskMinutes: pending?.estimatedMinutes ?? 10,
      activeMistakes: wrongQuestions.length,
      weakTopics: weakTopics.length,
    );

    VoidCallback? start;
    switch (action.kind) {
      case StudyActionKind.dueReviews:
        // The same door the "Open Hub" button below uses.
        start = () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SpacedRepetitionScreen()),
        );
      case StudyActionKind.unfinishedTask:
        final task = pending;
        start = task == null
            ? null
            : () => FocusTimerDialog.show(
                context,
                taskId: task.id,
                taskTitle: task.title,
                subject: task.subject,
                initialMinutes: task.estimatedMinutes,
              );
      case StudyActionKind.mistakeDrill:
        start = () => QuizDrillModal.show(
          context,
          topic: 'Mistake Bank Quick Drill',
          subject: 'Revision',
          customQuestions: _asQuizQuestions(wrongQuestions),
        );
      case StudyActionKind.weakTopic:
        final topic = weakTopics.firstOrNull;
        start = topic == null
            ? null
            : () => WeaknessHealingDrillModal.show(context, topic: topic);
      case StudyActionKind.allClear:
        start = () => QuestionBankScannerModal.show(context);
    }

    return NextActionCard(action: action, onStart: start, streakDays: streak);
  }

  /// Everything waiting, with its size, beside the one recommendation.
  ///
  /// The rows follow the same order as [pickNextStudyAction], so the backlog
  /// and the recommendation never look as though they disagree.
  Widget _buildAttention(
    BuildContext context, {
    required List<SpacedReviewItem> dueSpacedReviews,
    required List<DrillQuestion> wrongQuestions,
    required List<WeakTopic> weakTopics,
  }) {
    final firstWeakTopic = weakTopics.firstOrNull;

    return AttentionCard(
      items: [
        AttentionItem(
          label: 'রিভিশন কার্ড আজ জমা',
          count: dueSpacedReviews.length,
          icon: Icons.history_toggle_off,
          colour: const Color(0xFF6366F1),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SpacedRepetitionScreen()),
          ),
        ),
        AttentionItem(
          label: 'ভুল প্রশ্ন আয়ত্তে আসেনি',
          count: wrongQuestions.length,
          icon: Icons.error_outline,
          colour: const Color(0xFFF59E0B),
          onTap: () => QuizDrillModal.show(
            context,
            topic: 'Mistake Bank Quick Drill',
            subject: 'Revision',
            customQuestions: _asQuizQuestions(wrongQuestions),
          ),
        ),
        AttentionItem(
          label: 'দুর্বল টপিক চিহ্নিত',
          count: weakTopics.length,
          icon: Icons.track_changes,
          colour: const Color(0xFF14B8A6),
          onTap: firstWeakTopic == null
              ? null
              : () => WeaknessHealingDrillModal.show(
                  context,
                  topic: firstWeakTopic,
                ),
        ),
      ],
    );
  }

  /// How much of today is done, from the plan and the day's real activity.
  Widget _buildTodayProgress(WidgetRef ref) {
    final plan = ref.watch(adaptivePlannerProvider).value;
    final answered = ref.watch(questionsAnsweredTodayProvider).value ?? 0;

    return TodayProgressStrip(
      progress: summariseToday(
        tasks: plan?.tasks ?? const [],
        recommendedStudyMinutes: plan?.recommendedStudyMinutes ?? 0,
        questionsAnsweredToday: answered,
      ),
    );
  }

  /// Wrong answers as drillable questions.
  ///
  /// Lifted out of the Mistake Bank section so the card above can start the
  /// same drill without a second copy of the conversion.
  List<QuizQuestion> _asQuizQuestions(List<DrillQuestion> questions) {
    return questions.map((dq) {
      List<String> options = [];
      try {
        final decoded = jsonDecode(dq.optionsJson);
        if (decoded is List) {
          options = decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
      return QuizQuestion(
        questionText: dq.questionText,
        options: options,
        correctIndex: dq.correctIndex,
        explanation: dq.explanation,
      );
    }).toList();
  }

  Widget _buildQuickActionStrip(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // 0. LiveMCQ Voice Mistake Note & Floating Bubble
          _buildQuickActionPill(
            context,
            icon: Icons.mic_external_on_rounded,
            iconColor: const Color(0xFF8B5CF6),
            bgColor: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
            label: 'Voice Mistake',
            badge: 'Bubble 🎙️',
            onTap: () => VoiceMistakeBottomSheet.show(context),
          ),
          const SizedBox(width: 8),

          // 0.2. Image to Text (Offline Local OCR)
          _buildQuickActionPill(
            context,
            icon: Icons.document_scanner_rounded,
            iconColor: const Color(0xFF0284C7),
            bgColor: const Color(0xFF0284C7).withValues(alpha: 0.12),
            label: 'Image to Text',
            badge: 'Local OCR 📴',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ImageToTextScreen()),
            ),
          ),
          const SizedBox(width: 8),

          // 1. Mistake Notebook
          _buildQuickActionPill(
            context,
            icon: Icons.menu_book_rounded,
            iconColor: const Color(0xFFE11D48),
            bgColor: const Color(0xFFE11D48).withValues(alpha: 0.12),
            label: 'Mistake Book',
            badge: 'Folders 📓',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MistakeNotebookScreen()),
            ),
          ),
          const SizedBox(width: 8),

          // 1.5. Test Paper & Question Bank Scanner
          _buildQuickActionPill(
            context,
            icon: Icons.assignment_outlined,
            iconColor: const Color(0xFF0D9488),
            bgColor: const Color(0xFF0D9488).withValues(alpha: 0.12),
            label: 'Test Paper',
            badge: 'Exam 📝',
            onTap: () => QuestionBankScannerModal.show(context),
          ),
          const SizedBox(width: 8),

          // 2. Camera / Book Page to AI Drill
          _buildQuickActionPill(
            context,
            icon: Icons.camera_alt,
            iconColor: const Color(0xFF6366F1),
            bgColor: const Color(0xFF6366F1).withValues(alpha: 0.12),
            label: 'Book to Drill',
            badge: '⚡ Vision',
            onTap: () => StudySheetCameraModal.show(context),
          ),
          const SizedBox(width: 8),

          // 2. Pomodoro Focus Timer
          _buildQuickActionPill(
            context,
            icon: Icons.timer_outlined,
            iconColor: const Color(0xFF10B981),
            bgColor: const Color(0xFF10B981).withValues(alpha: 0.12),
            label: 'Focus Timer',
            badge: '15m Micro',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PomodoroFocusScreen()),
            ),
          ),
          const SizedBox(width: 8),

          // 3. Spaced Repetition Flashcards
          _buildQuickActionPill(
            context,
            icon: Icons.bolt,
            iconColor: const Color(0xFFF59E0B),
            bgColor: const Color(0xFFF59E0B).withValues(alpha: 0.12),
            label: 'Flashcards',
            badge: 'Ebbinghaus',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SpacedRepetitionScreen()),
            ),
          ),
          const SizedBox(width: 8),

          // 4. OLED Theme Toggle
          _buildQuickActionPill(
            context,
            icon: isDark ? Icons.light_mode : Icons.dark_mode,
            iconColor: isDark ? Colors.amber : const Color(0xFF1E3A8A),
            bgColor: (isDark ? Colors.amber : const Color(0xFF1E3A8A))
                .withValues(alpha: 0.12),
            label: isDark ? 'Light' : 'OLED Dark',
            badge: 'Midnight',
            onTap: () => ref.read(themeModeProvider.notifier).toggleTheme(),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionPill(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required String label,
    required String badge,
    required VoidCallback onTap,
  }) {
    return PremiumGlassCard(
      borderRadius: 12.0,
      blurSigma: 6.0,
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    badge,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: iconColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMistakeBankSection(
    BuildContext context,
    List<DrillQuestion> questions,
  ) {
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const MistakeNotebookScreen()),
      ),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.indigo.shade800, Colors.deepPurple.shade900],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.indigo.withValues(alpha: 0.4),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.menu_book_rounded,
                    color: Colors.amber,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'মিস্টেক নোটবুক: ${questions.length}টি বাকি ভুল',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'LiveMCQ ও প্র্যাকটিসের ভুলগুলো ফোল্ডার আকারে রিভিশন দিন',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white54,
                  size: 14,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: PremiumButton(
                    label: 'রাতের রিভিশন 🌙',
                    icon: Icons.nightlight_round,
                    onPressed: () => NightlyReviewModal.show(context, questions),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white60),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () {
                      final quizQuestions = questions.map((dq) {
                        List<String> options = [];
                        try {
                          final decoded = jsonDecode(dq.optionsJson);
                          if (decoded is List) {
                            options = decoded.map((e) => e.toString()).toList();
                          }
                        } catch (_) {}
                        return QuizQuestion(
                          questionText: dq.questionText,
                          options: options,
                          correctIndex: dq.correctIndex,
                          explanation: dq.explanation,
                        );
                      }).toList();

                      QuizDrillModal.show(
                        context,
                        topic: 'Mistake Bank Quick Drill',
                        subject: 'Revision',
                        customQuestions: quizQuestions,
                      );
                    },
                    icon: const Icon(Icons.flash_on, size: 14),
                    label: const Text(
                      'রি-ড্রিল ⚡',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
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

  Widget _buildSpacedRepetitionCard(BuildContext context, int dueCount) {
    return PremiumGlassCard(
      borderRadius: 16.0,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const PremiumIconBadge(
            icon: Icons.psychology,
            size: 44,
            iconSize: 22,
            color: Colors.purpleAccent,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Spaced Repetition',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    if (dueCount > 0) ...[
                      const SizedBox(width: 6),
                      PremiumTag(
                        label: '$dueCount Due',
                        color: Colors.redAccent,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  dueCount > 0
                      ? '$dueCount rules due before forgetting curve drops'
                      : 'Review rules & 5s office flashcards',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white70,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          PremiumButton(
            label: 'Open Hub',
            icon: Icons.open_in_new,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SpacedRepetitionScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
