import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/services/ai/gemini_ai_service.dart';
import '../../../../core/services/ai/models/quiz_question.dart';
import '../../../../core/theme/theme_provider.dart';
import '../../../analytics/presentation/widgets/github_study_heatmap.dart';
import '../../../focus/presentation/screens/pomodoro_focus_screen.dart';
import '../../../live_mcq/presentation/providers/exam_schedule_provider.dart';
import '../../../live_mcq/presentation/widgets/voice_mistake_bottom_sheet.dart';
import '../../../quiz/presentation/providers/drill_history_provider.dart';
import '../../../quiz/presentation/widgets/quiz_drill_modal.dart';
import '../../../quiz/presentation/widgets/study_sheet_camera_modal.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../spaced_repetition/presentation/providers/spaced_repetition_provider.dart';
import '../../../spaced_repetition/presentation/screens/spaced_repetition_screen.dart';
import '../../../topics/presentation/providers/topics_provider.dart';
import '../../../mistake_notebook/presentation/screens/mistake_notebook_screen.dart';
import '../../../mistake_notebook/presentation/widgets/nightly_review_modal.dart';
import '../../../weakness_healer/presentation/widgets/weakness_healing_card.dart';
import '../widgets/automation_test_card.dart';
import '../widgets/biometric_status_banner.dart';
import '../widgets/energy_tracker_card.dart';
import '../widgets/multi_track_exam_countdown_card.dart';
import '../widgets/study_plan_card.dart';
import '../../../weekly_routine/presentation/widgets/weekly_routine_card.dart';

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
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(upcomingExamsStreamProvider);
          ref.invalidate(weakTopicsStreamProvider);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 0. Quick Action & Productivity Bar
              _buildQuickActionStrip(context, ref),
              const SizedBox(height: 14),

              // 1. Office & Attendance Status Banner
              const BiometricStatusBanner(),
              const SizedBox(height: 16),

              // 2. Post-work Energy & Mood Tracker
              const EnergyTrackerCard(),
              const SizedBox(height: 16),

              // 3. Adaptive AI Study Routine
              const StudyPlanCard(),

              const SizedBox(height: 16),
              const WeeklyRoutineCard(),
              const SizedBox(height: 16),

              // 4. GitHub-Style Study Activity Heatmap & Analytics
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

              // 8. Weak Topics Spotlight
              if (weakTopics.isNotEmpty) ...[
                _buildWeakTopicsSection(context, weakTopics),
                const SizedBox(height: 16),
              ],

              // 9. Automation & Triggers Testing Lab
              const AutomationTestCard(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: isDark ? const Color(0xFF111827) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
        ),
      ),
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

  Widget _buildWeakTopicsSection(BuildContext context, List<dynamic> topics) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.flag, color: Colors.deepOrange, size: 20),
                SizedBox(width: 8),
                Text(
                  'Core Weak Topics (LiveMCQ Focus)',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: topics.take(4).map((t) {
                return Chip(
                  labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                  label: Text(
                    '${t.subject}: ${t.topicName}',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  backgroundColor: isDark
                      ? Colors.deepOrange.withValues(alpha: 0.18)
                      : Colors.deepOrange.shade50,
                  avatar: const Icon(
                    Icons.circle,
                    size: 10,
                    color: Colors.deepOrange,
                  ),
                );
              }).toList(),
            ),
          ],
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
              color: Colors.indigo.withValues(alpha: 0.25),
              blurRadius: 8,
              offset: const Offset(0, 3),
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
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.black87,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () =>
                        NightlyReviewModal.show(context, questions),
                    icon: const Icon(Icons.nightlight_round, size: 14),
                    label: const Text(
                      'রাতের রিভিশন 🌙',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.purple.withValues(alpha: 0.2)
                    : Colors.purple.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.psychology,
                color: isDark ? Colors.purpleAccent : Colors.purple,
                size: 24,
              ),
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
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.red.withValues(alpha: 0.25)
                                : Colors.red.shade100,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$dueCount Due',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? Colors.redAccent
                                  : Colors.red.shade900,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dueCount > 0
                        ? '$dueCount rules due before forgetting curve drops'
                        : 'Review rules & 5s office flashcards',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SpacedRepetitionScreen(),
                  ),
                );
              },
              child: const Text(
                'Open Hub',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
