import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/services/ai/models/quiz_question.dart';
import '../../../../core/utils/bengali_math_sanitizer.dart';
import '../../../chat/presentation/providers/chat_provider.dart';
import '../../../chat/presentation/screens/ai_chat_screen.dart';
import '../../../mistake_notebook/presentation/screens/mistake_notebook_screen.dart';
import '../../../mistake_notebook/presentation/widgets/ai_mistake_explainer_sheet.dart';
import '../../../quiz/presentation/providers/drill_history_provider.dart';
import '../../../quiz/presentation/widgets/quiz_drill_modal.dart';

class MistakeBankAndHubTab extends ConsumerStatefulWidget {
  final List<DrillQuestion> wrongQuestions;
  final void Function(List<DrillQuestion>) onStartMistakeBankDrill;

  const MistakeBankAndHubTab({
    super.key,
    required this.wrongQuestions,
    required this.onStartMistakeBankDrill,
  });

  @override
  ConsumerState<MistakeBankAndHubTab> createState() =>
      _MistakeBankAndHubTabState();
}

class _MistakeBankAndHubTabState extends ConsumerState<MistakeBankAndHubTab> {
  int _hubSubViewIndex = 0; // 0 = Mistake Bank, 1 = Drill History

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'today';
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    final months = [
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
    final minuteStr = dt.minute.toString().padLeft(2, '0');
    final timeStr =
        '${dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour)}:$minuteStr ${dt.hour >= 12 ? 'PM' : 'AM'}';
    return '${dt.day} ${months[dt.month - 1]}, $timeStr';
  }

  QuizQuestion _convertDrillQuestionToQuiz(DrillQuestion dq) {
    List<String> options = [];
    try {
      final decoded = jsonDecode(dq.optionsJson);
      if (decoded is List) {
        options = decoded.map((e) => e.toString()).toList();
      }
    } catch (_) {}

    return QuizQuestion(
      questionText: BengaliMathSanitizer.sanitize(dq.questionText),
      options: options.map((e) => BengaliMathSanitizer.sanitize(e)).toList(),
      correctIndex: dq.correctIndex,
      explanation: BengaliMathSanitizer.sanitize(dq.explanation),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(drillStatsStreamProvider);
    final historyAsync = ref.watch(drillHistoryStreamProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Overall Performance Dashboard Card
          statsAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (err, stack) => const SizedBox.shrink(),
            data: (stats) => _buildStatsCard(stats),
          ),
          const SizedBox(height: 14),

          // 2. Prominent Re-drill Action Banner (if active mistakes exist)
          if (widget.wrongQuestions.isNotEmpty) ...[
            _buildMistakeBanner(widget.wrongQuestions),
            const SizedBox(height: 14),
          ],

          // 3. Sub-segment Selector: Mistake Bank vs Drill History
          historyAsync.when(
            loading: () =>
                _buildSubViewSelector(widget.wrongQuestions.length, 0),
            error: (err, stack) =>
                _buildSubViewSelector(widget.wrongQuestions.length, 0),
            data: (history) => _buildSubViewSelector(
              widget.wrongQuestions.length,
              history.length,
            ),
          ),
          const SizedBox(height: 14),

          // 4. Sub-view Content
          if (_hubSubViewIndex == 0)
            _buildMistakeBankList(widget.wrongQuestions)
          else
            historyAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (err, _) =>
                  Center(child: Text('Error loading history: $err')),
              data: (history) => _buildDrillHistoryList(history),
            ),
        ],
      ),
    );
  }

  Widget _buildStatsCard(Map<String, dynamic> stats) {
    final totalDrills = stats['total_drills'] ?? 0;
    final totalAnswered = stats['total_answered'] ?? 0;
    final totalCorrect = stats['total_correct'] ?? 0;
    final activeMistakes = stats['active_wrong_count'] ?? 0;
    final accuracy = (stats['accuracy_percentage'] as num?)?.toDouble() ?? 0.0;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.analytics_outlined,
                  color: Colors.indigo,
                  size: 20,
                ),
                const SizedBox(width: 8),
                // Was an unconstrained Text + Spacer(): the title and the
                // accuracy badge both demanded their full intrinsic width,
                // so the row blew past the card on a narrow screen.
                const Expanded(
                  child: Text(
                    'Drill Performance Summary',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: accuracy >= 70
                        ? Colors.green.shade50
                        : (accuracy >= 40
                              ? Colors.orange.shade50
                              : Colors.red.shade50),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: accuracy >= 70
                          ? Colors.green.shade200
                          : (accuracy >= 40
                                ? Colors.orange.shade200
                                : Colors.red.shade200),
                    ),
                  ),
                  child: Text(
                    '${accuracy.toStringAsFixed(1)}% Accuracy',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: accuracy >= 70
                          ? Colors.green.shade800
                          : (accuracy >= 40
                                ? Colors.orange.shade800
                                : Colors.red.shade800),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _buildStatPill('Total Drills', '$totalDrills', Colors.indigo),
                const SizedBox(width: 8),
                _buildStatPill('Questions', '$totalAnswered', Colors.blueGrey),
                const SizedBox(width: 8),
                _buildStatPill('Correct', '$totalCorrect', Colors.green),
                const SizedBox(width: 8),
                _buildStatPill('Mistakes', '$activeMistakes', Colors.redAccent),
              ],
            ),
            if (totalAnswered > 0) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (accuracy / 100).clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: Colors.red.shade100,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    accuracy >= 70
                        ? Colors.green
                        : (accuracy >= 50 ? Colors.orange : Colors.redAccent),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatPill(String title, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMistakeBanner(List<DrillQuestion> wrongQuestions) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.indigo.shade700, Colors.indigo.shade900],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.indigo.withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.flash_on, color: Colors.amber, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${wrongQuestions.length} Mistakes to Master',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Practice your exact wrong questions until you get 100%!',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => widget.onStartMistakeBankDrill(wrongQuestions),
                child: const Text(
                  'Drill Now',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                ),
              ),
              const SizedBox(height: 4),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white70),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const MistakeNotebookScreen(),
                  ),
                ),
                child: const Text(
                  'Notebook 📓',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSubViewSelector(int mistakesCount, int historyCount) {
    return SegmentedButton<int>(
      segments: [
        ButtonSegment<int>(
          value: 0,
          icon: const Icon(Icons.highlight_off, size: 16),
          label: Text('Mistake Bank ($mistakesCount)'),
        ),
        ButtonSegment<int>(
          value: 1,
          icon: const Icon(Icons.history, size: 16),
          label: Text('Past Sessions ($historyCount)'),
        ),
      ],
      selected: {_hubSubViewIndex},
      onSelectionChanged: (set) {
        setState(() {
          _hubSubViewIndex = set.first;
        });
      },
    );
  }

  Widget _buildMistakeBankList(List<DrillQuestion> wrongQuestions) {
    if (wrongQuestions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: [
              Icon(Icons.verified, size: 64, color: Colors.green.shade400),
              const SizedBox(height: 12),
              const Text(
                'No Active Mistakes!',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'You have mastered all previous wrong questions.\nTake more drills to challenge yourself!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () {
                  QuizDrillModal.show(
                    context,
                    topic: 'General Review',
                    subject: 'Practice Drill',
                  );
                },
                icon: const Icon(Icons.flash_on, size: 16),
                label: const Text(
                  'নতুন ড্রিল শুরু করুন ⚡',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: wrongQuestions.length,
      itemBuilder: (context, index) {
        final dq = wrongQuestions[index];
        return _buildWrongQuestionCard(dq);
      },
    );
  }

  Widget _buildWrongQuestionCard(DrillQuestion dq) {
    List<String> options = [];
    try {
      final decoded = jsonDecode(dq.optionsJson);
      if (decoded is List) {
        options = decoded.map((e) => e.toString()).toList();
      }
    } catch (_) {}

    final userAns = (dq.selectedIndex >= 0 && dq.selectedIndex < options.length)
        ? options[dq.selectedIndex]
        : 'Not Answered / Invalid';

    final correctAns =
        (dq.correctIndex >= 0 && dq.correctIndex < options.length)
        ? options[dq.correctIndex]
        : 'Unknown';

    return Card(
      elevation: 1.5,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => AiMistakeExplainerSheet.show(context, dq),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.indigo.withValues(alpha: 0.2)
                                  : Colors.indigo.shade50,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              dq.subject,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.indigo.shade200
                                    : Colors.indigo.shade800,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '• ${dq.topic}',
                            style: TextStyle(
                              fontSize: 11.5,
                              color:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.white70
                                  : Colors.grey.shade700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatDateTime(dq.attemptedAt),
                    style: TextStyle(
                      fontSize: 10.5,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white54
                          : Colors.grey.shade500,
                    ),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: Icon(
                        Icons.more_vert,
                        size: 18,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white70
                            : Colors.grey.shade700,
                      ),
                      tooltip: 'Options',
                      onSelected: (val) async {
                        if (val == 'master') {
                          HapticFeedback.mediumImpact();
                          await ref
                              .read(drillHistoryNotifierProvider.notifier)
                              .markQuestionMastered(dq.id, true);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('Marked as mastered! 🎉'),
                                duration: const Duration(seconds: 4),
                                action: SnackBarAction(
                                  label: 'Undo',
                                  onPressed: () {
                                    ref
                                        .read(
                                          drillHistoryNotifierProvider.notifier,
                                        )
                                        .markQuestionMastered(dq.id, false);
                                  },
                                ),
                              ),
                            );
                          }
                        } else if (val == 'ask_ai') {
                          ref
                              .read(chatNotifierProvider.notifier)
                              .openOrCreateTopicSession(
                                subject: dq.subject,
                                topic: dq.topic,
                                initialPrompt:
                                    'আমি "${dq.subject}" বিষয়ের "${dq.topic}" টপিকের এই প্রশ্নটি ভুল করেছি:\n\n'
                                    'প্রশ্ন: ${dq.questionText}\n'
                                    'আমার উত্তর ছিল: $userAns\n'
                                    'সঠিক উত্তর: $correctAns\n'
                                    'ব্যাখ্যা: ${dq.explanation}\n\n'
                                    'আমাকে বুঝিয়ে বলো কেন আমার উত্তরটি ভুল এবং এই সংক্রান্ত নিয়মটি সহজে মনে রাখার উপায় কী?',
                              );
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AiChatScreen(),
                            ),
                          );
                        } else if (val == 'drill_single') {
                          final quizQ = _convertDrillQuestionToQuiz(dq);
                          QuizDrillModal.show(
                            context,
                            topic: dq.topic,
                            subject: dq.subject,
                            customQuestions: [quizQ],
                          );
                        }
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(
                          value: 'drill_single',
                          child: Row(
                            children: [
                              Icon(
                                Icons.refresh,
                                size: 16,
                                color: Colors.indigo,
                              ),
                              SizedBox(width: 8),
                              Text('Retry This Question'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'ask_ai',
                          child: Row(
                            children: [
                              Icon(
                                Icons.auto_awesome,
                                size: 16,
                                color: Colors.indigo,
                              ),
                              SizedBox(width: 8),
                              Text('Explain with AI Mentor'),
                            ],
                          ),
                        ),
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: 'master',
                          child: Row(
                            children: [
                              Icon(
                                Icons.done_all,
                                size: 16,
                                color: Colors.green,
                              ),
                              SizedBox(width: 8),
                              Text('Mark as Mastered'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                BengaliMathSanitizer.sanitize(dq.questionText),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF1E293B)
                      : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white12
                        : Colors.grey.shade200,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.close,
                          size: 16,
                          color: Colors.redAccent,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Your Answer: ${BengaliMathSanitizer.sanitize(userAns)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.redAccent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.check, size: 16, color: Colors.green),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Correct Answer: ${BengaliMathSanitizer.sanitize(correctAns)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (dq.explanation.trim().isNotEmpty) ...[
                      const Divider(height: 14),
                      Text(
                        'Explanation: ${BengaliMathSanitizer.sanitize(dq.explanation)}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontStyle: FontStyle.italic,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white70
                              : Colors.grey.shade800,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(
                      Icons.auto_awesome,
                      size: 14,
                      color: Colors.indigo,
                    ),
                    label: const Text(
                      'AI Explains',
                      style: TextStyle(fontSize: 11.5, color: Colors.indigo),
                    ),
                    onPressed: () => AiMistakeExplainerSheet.show(context, dq),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.done_all, size: 14),
                    label: const Text(
                      'Mastered (বুঝেছি)',
                      style: TextStyle(fontSize: 11.5),
                    ),
                    onPressed: () async {
                      HapticFeedback.mediumImpact();
                      await ref
                          .read(drillHistoryNotifierProvider.notifier)
                          .markQuestionMastered(dq.id, true);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Marked as mastered! 🎉'),
                            duration: const Duration(seconds: 4),
                            action: SnackBarAction(
                              label: 'Undo',
                              onPressed: () {
                                ref
                                    .read(drillHistoryNotifierProvider.notifier)
                                    .markQuestionMastered(dq.id, false);
                              },
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDrillHistoryList(List<DrillRecord> history) {
    if (history.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: [
              Icon(
                Icons.history_toggle_off,
                size: 64,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 12),
              const Text(
                'No Past Drill Sessions',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Start a drill from Weak Topics or AI Mentor to test your skills!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: history.length,
      itemBuilder: (context, index) {
        final r = history[index];
        final score = r.scorePercentage;
        Color badgeColor = Colors.green;
        if (score < 50) {
          badgeColor = Colors.redAccent;
        } else if (score < 75) {
          badgeColor = Colors.orangeAccent;
        }

        return Card(
          elevation: 1.5,
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: badgeColor.withValues(alpha: 0.3),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${r.correctCount}/${r.totalQuestions}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: badgeColor,
                          ),
                        ),
                        Text(
                          '${score.toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: badgeColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.indigo.withValues(alpha: 0.2)
                                    : Colors.indigo.shade50,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                r.subject,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color:
                                      Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.indigo.shade200
                                      : Colors.indigo.shade800,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _formatDateTime(r.createdAt),
                            style: TextStyle(
                              fontSize: 10.5,
                              color:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.white60
                                  : Colors.grey.shade600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        r.topic,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Correct: ${r.correctCount}  •  Mistakes: ${r.incorrectCount}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white70
                              : Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Drill again',
                  icon: const Icon(
                    Icons.refresh,
                    size: 20,
                    color: Colors.indigo,
                  ),
                  onPressed: () {
                    QuizDrillModal.show(
                      context,
                      topic: r.topic,
                      subject: r.subject,
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
