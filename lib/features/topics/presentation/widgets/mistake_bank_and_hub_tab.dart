import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/services/ai/models/quiz_question.dart';
import '../../../../core/theme/fluent_tokens.dart';
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
      padding: const EdgeInsets.fromLTRB(
        FluentSpacing.l,
        FluentSpacing.l,
        FluentSpacing.l,
        80,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Overall Performance Dashboard Card
          statsAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (err, stack) => const SizedBox.shrink(),
            data: (stats) => _buildStatsCard(stats),
          ),
          const SizedBox(height: FluentSpacing.l),

          // 2. Prominent Re-drill Action Banner (if active mistakes exist)
          if (widget.wrongQuestions.isNotEmpty) ...[
            _buildMistakeBanner(widget.wrongQuestions),
            const SizedBox(height: FluentSpacing.l),
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
          const SizedBox(height: FluentSpacing.l),

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

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    final accuracyColor = accuracy >= 70
        ? Colors.green
        : (accuracy >= 40 ? Colors.orange : Colors.redAccent);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: FluentRadius.cardBorder,
        side: FluentStroke.side(brightness),
      ),
      child: Padding(
        padding: const EdgeInsets.all(FluentSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.analytics_outlined,
                  color: scheme.primary,
                  size: 20,
                ),
                const SizedBox(width: FluentSpacing.s),
                // Was an unconstrained Text + Spacer(): the title and the
                // accuracy badge both demanded their full intrinsic width,
                // so the row blew past the card on a narrow screen.
                Expanded(
                  child: Text(
                    'Drill Performance Summary',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: FluentType.bodyStrong.copyWith(
                      fontSize: 15,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: FluentSpacing.s),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FluentSpacing.s,
                    vertical: FluentSpacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: FluentLayer.subtle(accuracyColor, brightness),
                    borderRadius: FluentRadius.controlBorder,
                  ),
                  child: Text(
                    '${accuracy.toStringAsFixed(1)}% Accuracy',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FluentType.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: accuracyColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: FluentSpacing.l),
            Row(
              children: [
                _buildStatPill('Total Drills', '$totalDrills', scheme.primary),
                const SizedBox(width: FluentSpacing.s),
                _buildStatPill(
                  'Questions',
                  '$totalAnswered',
                  scheme.onSurface.withValues(alpha: 0.75),
                ),
                const SizedBox(width: FluentSpacing.s),
                _buildStatPill('Correct', '$totalCorrect', Colors.green),
                const SizedBox(width: FluentSpacing.s),
                _buildStatPill('Mistakes', '$activeMistakes', Colors.redAccent),
              ],
            ),
            if (totalAnswered > 0) ...[
              const SizedBox(height: FluentSpacing.m),
              ClipRRect(
                borderRadius: FluentRadius.controlBorder,
                child: LinearProgressIndicator(
                  value: (accuracy / 100).clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: scheme.onSurface.withValues(alpha: 0.10),
                  valueColor: AlwaysStoppedAnimation<Color>(accuracyColor),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatPill(String title, String value, Color color) {
    final scheme = Theme.of(context).colorScheme;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: FluentSpacing.s,
          horizontal: FluentSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: FluentLayer.subtle(color, Theme.of(context).brightness),
          borderRadius: FluentRadius.controlBorder,
        ),
        child: Column(
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FluentType.bodyStrong.copyWith(
                fontSize: 16,
                color: color,
              ),
            ),
            const SizedBox(height: FluentSpacing.xxs),
            Text(
              title,
              style: FluentType.caption.copyWith(
                fontSize: 10,
                color: scheme.onSurface.withValues(alpha: 0.65),
              ),
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
    final scheme = Theme.of(context).colorScheme;
    final onAccent = scheme.onPrimary;

    return Container(
      padding: const EdgeInsets.all(FluentSpacing.m),
      decoration: BoxDecoration(
        // A flat accent panel: Fluent marks the thing you act on with the
        // accent fill, not with a gradient and a coloured glow.
        color: scheme.primary,
        borderRadius: FluentRadius.cardBorder,
        boxShadow: FluentElevation.card(Theme.of(context).brightness),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(FluentSpacing.s),
            decoration: BoxDecoration(
              color: onAccent.withValues(alpha: 0.16),
              borderRadius: FluentRadius.controlBorder,
            ),
            child: Icon(Icons.flash_on, color: onAccent, size: 24),
          ),
          const SizedBox(width: FluentSpacing.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${wrongQuestions.length} Mistakes to Master',
                  style: FluentType.bodyStrong.copyWith(color: onAccent),
                ),
                const SizedBox(height: FluentSpacing.xxs),
                Text(
                  'Practice your exact wrong questions until you get 100%!',
                  style: FluentType.caption.copyWith(
                    color: onAccent.withValues(alpha: 0.80),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: FluentSpacing.s),
          Column(
            children: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: onAccent,
                  foregroundColor: scheme.primary,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: FluentSpacing.m,
                    vertical: FluentSpacing.xs + 2,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: FluentRadius.controlBorder,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => widget.onStartMistakeBankDrill(wrongQuestions),
                child: Text(
                  'Drill Now',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FluentType.caption.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: FluentSpacing.xs),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: onAccent,
                  side: BorderSide(color: onAccent.withValues(alpha: 0.55)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: FluentSpacing.m,
                    vertical: FluentSpacing.xs,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: FluentRadius.controlBorder,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const MistakeNotebookScreen(),
                  ),
                ),
                child: Text(
                  'Notebook 📓',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FluentType.caption.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// A Fluent segmented control.
  ///
  /// Hand-rolled rather than [SegmentedButton] because Material sizes every
  /// segment to its widest intrinsic label: at 320px with 1.5x text the two
  /// labels together were wider than the screen and the row overflowed.
  /// Here each half is an [Expanded] with an ellipsising label, so the
  /// control always fits the width it is given.
  Widget _buildSubViewSelector(int mistakesCount, int historyCount) {
    final brightness = Theme.of(context).brightness;

    return Container(
      padding: const EdgeInsets.all(FluentSpacing.xs),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.onSurface.withValues(alpha: 0.04),
        borderRadius: FluentRadius.controlBorder,
        border: Border.all(
          color: FluentStroke.card(brightness),
          width: FluentStroke.width,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildSubViewSegment(
              index: 0,
              icon: Icons.highlight_off,
              label: 'Mistake Bank ($mistakesCount)',
            ),
          ),
          const SizedBox(width: FluentSpacing.xs),
          Expanded(
            child: _buildSubViewSegment(
              index: 1,
              icon: Icons.history,
              label: 'Past Sessions ($historyCount)',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubViewSegment({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _hubSubViewIndex == index;
    final foreground = selected
        ? scheme.primary
        : scheme.onSurface.withValues(alpha: 0.65);

    return Material(
      color: selected
          ? FluentLayer.subtle(scheme.primary, Theme.of(context).brightness)
          : Colors.transparent,
      borderRadius: FluentRadius.controlBorder,
      child: InkWell(
        borderRadius: FluentRadius.controlBorder,
        onTap: () {
          setState(() {
            _hubSubViewIndex = index;
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: FluentSpacing.s,
            vertical: FluentSpacing.s,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: foreground),
              const SizedBox(width: FluentSpacing.xs + 2),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FluentType.caption.copyWith(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMistakeBankList(List<DrillQuestion> wrongQuestions) {
    if (wrongQuestions.isEmpty) {
      final scheme = Theme.of(context).colorScheme;

      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: [
              const Icon(Icons.verified, size: 64, color: Colors.green),
              const SizedBox(height: FluentSpacing.m),
              Text(
                'No Active Mistakes!',
                textAlign: TextAlign.center,
                style: FluentType.subtitle.copyWith(
                  fontSize: 17,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: FluentSpacing.s),
              Text(
                'You have mastered all previous wrong questions.\nTake more drills to challenge yourself!',
                textAlign: TextAlign.center,
                style: FluentType.caption.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
              const SizedBox(height: FluentSpacing.l),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: FluentSpacing.m,
                    vertical: FluentSpacing.s,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: FluentRadius.controlBorder,
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
                label: Text(
                  'নতুন ড্রিল শুরু করুন ⚡',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FluentType.caption.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
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

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    final secondaryText = scheme.onSurface.withValues(alpha: 0.65);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: FluentSpacing.m),
      shape: RoundedRectangleBorder(
        borderRadius: FluentRadius.cardBorder,
        side: FluentStroke.side(brightness),
      ),
      child: InkWell(
        borderRadius: FluentRadius.cardBorder,
        onTap: () => AiMistakeExplainerSheet.show(context, dq),
        child: Padding(
          padding: const EdgeInsets.all(FluentSpacing.m),
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
                              horizontal: FluentSpacing.s,
                              vertical: FluentSpacing.xxs,
                            ),
                            decoration: BoxDecoration(
                              color: FluentLayer.subtle(
                                scheme.primary,
                                brightness,
                              ),
                              borderRadius: FluentRadius.controlBorder,
                            ),
                            child: Text(
                              dq.subject,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: FluentType.caption.copyWith(
                                fontWeight: FontWeight.w600,
                                color: scheme.primary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: FluentSpacing.s),
                        Flexible(
                          child: Text(
                            '• ${dq.topic}',
                            style: FluentType.caption.copyWith(
                              color: secondaryText,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: FluentSpacing.s),
                  Flexible(
                    child: Text(
                      _formatDateTime(dq.attemptedAt),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FluentType.caption.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                  const SizedBox(width: FluentSpacing.xs),
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: Icon(
                        Icons.more_vert,
                        size: 18,
                        color: secondaryText,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: FluentRadius.cardBorder,
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
                        PopupMenuItem(
                          value: 'drill_single',
                          child: Row(
                            children: [
                              Icon(
                                Icons.refresh,
                                size: 16,
                                color: scheme.primary,
                              ),
                              const SizedBox(width: FluentSpacing.s),
                              Text(
                                'Retry This Question',
                                style: FluentType.body,
                              ),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'ask_ai',
                          child: Row(
                            children: [
                              Icon(
                                Icons.auto_awesome,
                                size: 16,
                                color: scheme.primary,
                              ),
                              const SizedBox(width: FluentSpacing.s),
                              Text(
                                'Explain with AI Mentor',
                                style: FluentType.body,
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuDivider(),
                        PopupMenuItem(
                          value: 'master',
                          child: Row(
                            children: [
                              const Icon(
                                Icons.done_all,
                                size: 16,
                                color: Colors.green,
                              ),
                              const SizedBox(width: FluentSpacing.s),
                              Text('Mark as Mastered', style: FluentType.body),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: FluentSpacing.s),
              Text(
                BengaliMathSanitizer.sanitize(dq.questionText),
                style: FluentType.bodyStrong.copyWith(color: scheme.onSurface),
              ),
              const SizedBox(height: FluentSpacing.s),
              Container(
                padding: const EdgeInsets.all(FluentSpacing.m),
                decoration: BoxDecoration(
                  color: scheme.onSurface.withValues(alpha: 0.04),
                  borderRadius: FluentRadius.controlBorder,
                  border: Border.all(
                    color: FluentStroke.card(brightness),
                    width: FluentStroke.width,
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
                        const SizedBox(width: FluentSpacing.s),
                        Expanded(
                          child: Text(
                            'Your Answer: ${BengaliMathSanitizer.sanitize(userAns)}',
                            style: FluentType.caption.copyWith(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: FluentSpacing.xs),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.check, size: 16, color: Colors.green),
                        const SizedBox(width: FluentSpacing.s),
                        Expanded(
                          child: Text(
                            'Correct Answer: ${BengaliMathSanitizer.sanitize(correctAns)}',
                            style: FluentType.caption.copyWith(
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (dq.explanation.trim().isNotEmpty) ...[
                      Divider(
                        height: FluentSpacing.l,
                        color: FluentStroke.divider(brightness),
                      ),
                      Text(
                        'Explanation: ${BengaliMathSanitizer.sanitize(dq.explanation)}',
                        style: FluentType.caption.copyWith(
                          color: secondaryText,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: FluentSpacing.s),
              // A Wrap, not a Row: at 320px / 1.5x text the two action
              // buttons together are wider than the card and the Row
              // overflowed. Wrap drops the second button to its own line.
              Wrap(
                alignment: WrapAlignment.end,
                spacing: FluentSpacing.s,
                runSpacing: FluentSpacing.s,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: FluentSpacing.s,
                        vertical: FluentSpacing.xs,
                      ),
                      visualDensity: VisualDensity.compact,
                      side: BorderSide(color: FluentStroke.card(brightness)),
                      shape: RoundedRectangleBorder(
                        borderRadius: FluentRadius.controlBorder,
                      ),
                    ),
                    icon: Icon(
                      Icons.auto_awesome,
                      size: 14,
                      color: scheme.primary,
                    ),
                    label: Text(
                      'AI Explains',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FluentType.caption.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onPressed: () => AiMistakeExplainerSheet.show(context, dq),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: FluentSpacing.m,
                        vertical: FluentSpacing.xs,
                      ),
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: FluentRadius.controlBorder,
                      ),
                    ),
                    icon: const Icon(Icons.done_all, size: 14),
                    label: Text(
                      'Mastered (বুঝেছি)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FluentType.caption.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
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
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.35),
              ),
              const SizedBox(height: FluentSpacing.m),
              Text(
                'No Past Drill Sessions',
                textAlign: TextAlign.center,
                style: FluentType.subtitle.copyWith(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: FluentSpacing.s),
              Text(
                'Start a drill from Weak Topics or AI Mentor to test your skills!',
                textAlign: TextAlign.center,
                style: FluentType.caption.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.65),
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

        final scheme = Theme.of(context).colorScheme;
        final brightness = Theme.of(context).brightness;
        final secondaryText = scheme.onSurface.withValues(alpha: 0.65);

        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: FluentSpacing.m),
          shape: RoundedRectangleBorder(
            borderRadius: FluentRadius.cardBorder,
            side: FluentStroke.side(brightness),
          ),
          child: Padding(
            padding: const EdgeInsets.all(FluentSpacing.m),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: FluentLayer.subtle(badgeColor, brightness),
                    borderRadius: FluentRadius.controlBorder,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${r.correctCount}/${r.totalQuestions}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: FluentType.caption.copyWith(
                            fontWeight: FontWeight.w600,
                            color: badgeColor,
                          ),
                        ),
                        Text(
                          '${score.toStringAsFixed(0)}%',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: FluentType.caption.copyWith(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: badgeColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: FluentSpacing.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: FluentSpacing.s,
                                vertical: FluentSpacing.xxs,
                              ),
                              decoration: BoxDecoration(
                                color: FluentLayer.subtle(
                                  scheme.primary,
                                  brightness,
                                ),
                                borderRadius: FluentRadius.controlBorder,
                              ),
                              child: Text(
                                r.subject,
                                style: FluentType.caption.copyWith(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: scheme.primary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          const SizedBox(width: FluentSpacing.s),
                          // Flexible, not a bare Text after a Spacer: the
                          // timestamp used to demand its full width and push
                          // the row over the edge on a narrow screen.
                          Flexible(
                            child: Text(
                              _formatDateTime(r.createdAt),
                              textAlign: TextAlign.end,
                              style: FluentType.caption.copyWith(
                                fontSize: 10,
                                color: secondaryText,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: FluentSpacing.xs),
                      Text(
                        r.topic,
                        style: FluentType.bodyStrong.copyWith(
                          color: scheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: FluentSpacing.xxs),
                      Text(
                        'Correct: ${r.correctCount}  •  Mistakes: ${r.incorrectCount}',
                        style: FluentType.caption.copyWith(
                          color: secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: FluentSpacing.s),
                IconButton(
                  tooltip: 'Drill again',
                  icon: Icon(Icons.refresh, size: 20, color: scheme.primary),
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
