import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/theme/fluent_tokens.dart';
import '../../../../core/utils/bengali_math_sanitizer.dart';
import '../../../quiz/presentation/providers/drill_history_provider.dart';
import '../../domain/models/mistake_folder.dart';
import 'ai_mistake_explainer_sheet.dart';

/// The status palette for this feature. One value each, picked to stay
/// readable on both the light and the dark card surface.
const Color _correctColor = Color(0xFF10B981); // green — the right answer
const Color _wrongColor = Color(0xFFE11D48); // red — what was answered
const Color _hintColor = Color(0xFFD97706); // amber — explanation / revisit

class NightlyReviewModal extends ConsumerStatefulWidget {
  final List<DrillQuestion> questions;

  const NightlyReviewModal({super.key, required this.questions});

  static Future<void> show(
    BuildContext context,
    List<DrillQuestion> questions,
  ) {
    if (questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'কোনো অমীমাংসিত ভুল প্রশ্ন নেই! আপনি সব আয়ত্ত করে ফেলেছেন। 🎉',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return Future.value();
    }

    return Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => NightlyReviewModal(questions: questions),
      ),
    );
  }

  @override
  ConsumerState<NightlyReviewModal> createState() => _NightlyReviewModalState();
}

class _NightlyReviewModalState extends ConsumerState<NightlyReviewModal> {
  int _currentIndex = 0;
  bool _isAnswerRevealed = false;
  int _masteredCount = 0;
  int _stillTrickyCount = 0;
  bool _isCompleted = false;

  void _revealAnswer() {
    setState(() {
      _isAnswerRevealed = true;
    });
  }

  Future<void> _handleAnswer(bool markMastered) async {
    final currentQ = widget.questions[_currentIndex];

    if (markMastered) {
      await ref
          .read(drillHistoryNotifierProvider.notifier)
          .markQuestionMastered(currentQ.id, true);
      _masteredCount++;
    } else {
      _stillTrickyCount++;
    }

    if (_currentIndex + 1 >= widget.questions.length) {
      setState(() {
        _isCompleted = true;
      });
    } else {
      setState(() {
        _currentIndex++;
        _isAnswerRevealed = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.nightlight_round, color: _hintColor, size: 20),
            const SizedBox(width: FluentSpacing.s),
            Flexible(
              child: Text(
                'রাতের ৫ মিনিটের রিভিশন',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FluentType.bodyStrong.copyWith(
                  fontSize: 16,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('শেষ করুন'),
          ),
        ],
      ),
      body: SafeArea(
        child: _isCompleted
            ? _buildCompletionScreen(isDark)
            : _buildReviewCardView(isDark),
      ),
    );
  }

  Widget _buildReviewCardView(bool isDark) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    final onSurface = scheme.onSurface;
    final total = widget.questions.length;
    final currentQ = widget.questions[_currentIndex];
    final progress = (_currentIndex + 1) / total;
    final source = detectMistakeSource(currentQ);

    List<String> options = [];
    try {
      final decoded = jsonDecode(currentQ.optionsJson);
      if (decoded is List) {
        options = decoded.map((e) => e.toString()).toList();
      }
    } catch (_) {}

    return Column(
      children: [
        // Top Progress Header
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: FluentSpacing.xl,
            vertical: FluentSpacing.m,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      'কার্ড ${_currentIndex + 1} / $total',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FluentType.bodyStrong.copyWith(
                        color: onSurface,
                      ),
                    ),
                  ),
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: FluentSpacing.s,
                              vertical: FluentSpacing.xxs,
                            ),
                            decoration: BoxDecoration(
                              color: FluentLayer.subtle(
                                source.color,
                                brightness,
                              ),
                              borderRadius: FluentRadius.controlBorder,
                              border: Border.all(
                                color: source.color.withValues(alpha: 0.3),
                                width: FluentStroke.width,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  source.icon,
                                  size: 12,
                                  color: source.color,
                                ),
                                const SizedBox(width: FluentSpacing.xs),
                                Flexible(
                                  child: Text(
                                    source.banglaLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: FluentType.caption.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: source.color,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: FluentSpacing.s),
              ClipRRect(
                borderRadius: FluentRadius.controlBorder,
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: FluentSpacing.xs + 2,
                  backgroundColor: onSurface.withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
                ),
              ),
            ],
          ),
        ),

        // Main Review Flashcard Body
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              FluentSpacing.l,
              FluentSpacing.xs,
              FluentSpacing.l,
              FluentSpacing.l,
            ),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: FluentRadius.cardBorder,
                side: FluentStroke.side(brightness),
              ),
              color: scheme.surface,
              child: Padding(
                padding: const EdgeInsets.all(FluentSpacing.l),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Subject & Topic Badge
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: FluentSpacing.s,
                            vertical: FluentSpacing.xs,
                          ),
                          decoration: BoxDecoration(
                            color: FluentLayer.subtle(
                              scheme.primary,
                              brightness,
                            ),
                            borderRadius: FluentRadius.controlBorder,
                          ),
                          child: Text(
                            currentQ.subject,
                            style: FluentType.caption.copyWith(
                              fontWeight: FontWeight.w600,
                              color: scheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: FluentSpacing.s),
                        Expanded(
                          child: Text(
                            currentQ.topic,
                            style: FluentType.caption.copyWith(
                              color: onSurface.withValues(alpha: 0.65),
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: FluentSpacing.l),

                    // Question Text
                    Text(
                      BengaliMathSanitizer.sanitize(currentQ.questionText),
                      style: FluentType.bodyStrong.copyWith(
                        fontSize: 16,
                        color: onSurface,
                      ),
                    ),
                    const SizedBox(height: FluentSpacing.xl),

                    // Unrevealed state: Tap to reveal
                    if (!_isAnswerRevealed) ...[
                      GestureDetector(
                        onTap: _revealAnswer,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            vertical: FluentSpacing.xxl,
                            horizontal: FluentSpacing.l,
                          ),
                          decoration: BoxDecoration(
                            color: FluentLayer.subtle(
                              scheme.primary,
                              brightness,
                            ),
                            borderRadius: FluentRadius.cardBorder,
                            border: Border.all(
                              color: scheme.primary.withValues(alpha: 0.3),
                              width: FluentStroke.width,
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.touch_app_rounded,
                                color: scheme.primary,
                                size: 36,
                              ),
                              const SizedBox(height: FluentSpacing.s),
                              Text(
                                'ট্যাপ করে সঠিক উত্তর ও ব্যাখ্যা দেখুন',
                                style: FluentType.bodyStrong.copyWith(
                                  color: scheme.primary,
                                ),
                              ),
                              const SizedBox(height: FluentSpacing.xs),
                              Text(
                                'মনে মনে সঠিক উত্তরটি আগে ভাবুন',
                                style: FluentType.caption.copyWith(
                                  color: onSurface.withValues(alpha: 0.65),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ] else ...[
                      // Revealed State: Options comparison
                      Text(
                        'অপশনসমূহ:',
                        style: FluentType.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          color: onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                      const SizedBox(height: FluentSpacing.s),
                      ...List.generate(options.length, (idx) {
                        final isCorrectOpt = idx == currentQ.correctIndex;
                        final isSelectedOpt = idx == currentQ.selectedIndex;

                        Color optBg = onSurface.withValues(alpha: 0.04);
                        Color optBorder = FluentStroke.card(brightness);
                        Widget? trailingIcon;

                        if (isCorrectOpt) {
                          optBg = FluentLayer.subtle(_correctColor, brightness);
                          optBorder = _correctColor;
                          trailingIcon = const Icon(
                            Icons.check_circle,
                            color: _correctColor,
                            size: 18,
                          );
                        } else if (isSelectedOpt) {
                          optBg = FluentLayer.subtle(_wrongColor, brightness);
                          optBorder = _wrongColor;
                          trailingIcon = const Icon(
                            Icons.cancel,
                            color: _wrongColor,
                            size: 18,
                          );
                        }

                        return Container(
                          margin: const EdgeInsets.only(
                            bottom: FluentSpacing.s,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: FluentSpacing.m,
                            vertical: FluentSpacing.s,
                          ),
                          decoration: BoxDecoration(
                            color: optBg,
                            borderRadius: FluentRadius.controlBorder,
                            border: Border.all(
                              color: optBorder,
                              width: FluentStroke.width,
                            ),
                          ),
                          child: Row(
                            children: [
                              Text(
                                '${String.fromCharCode(65 + idx)}. ',
                                style: FluentType.bodyStrong.copyWith(
                                  color: onSurface,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  BengaliMathSanitizer.sanitize(options[idx]),
                                  style: FluentType.body.copyWith(
                                    fontWeight: isCorrectOpt
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: isCorrectOpt
                                        ? (isDark
                                              ? Colors.green.shade200
                                              : Colors.green.shade900)
                                        : (isSelectedOpt
                                              ? (isDark
                                                    ? Colors.red.shade200
                                                    : Colors.red.shade900)
                                              : onSurface),
                                  ),
                                ),
                              ),
                              ?trailingIcon,
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: FluentSpacing.m),

                      // Explanation box
                      if (currentQ.explanation.isNotEmpty) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(FluentSpacing.m),
                          decoration: BoxDecoration(
                            color: FluentLayer.subtle(_hintColor, brightness),
                            borderRadius: FluentRadius.cardBorder,
                            border: Border.all(
                              color: _hintColor.withValues(alpha: 0.3),
                              width: FluentStroke.width,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.lightbulb,
                                    color: _hintColor,
                                    size: 16,
                                  ),
                                  const SizedBox(width: FluentSpacing.s),
                                  Flexible(
                                    child: Text(
                                      'ব্যাখ্যা ও রুল:',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: FluentType.caption.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: isDark
                                            ? Colors.amber.shade300
                                            : Colors.amber.shade900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: FluentSpacing.s),
                              Text(
                                BengaliMathSanitizer.sanitize(
                                  currentQ.explanation,
                                ),
                                style: FluentType.body.copyWith(
                                  color: onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: FluentSpacing.m),
                      ],

                      // AI Explainer button
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: FluentRadius.controlBorder,
                            ),
                          ),
                          onPressed: () =>
                              AiMistakeExplainerSheet.show(context, currentQ),
                          icon: Icon(
                            Icons.auto_awesome,
                            size: 16,
                            color: scheme.primary,
                          ),
                          label: Text(
                            'AI ভুল বিশ্লেষণ ও শর্টকাট',
                            style: FluentType.caption.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),

        // Bottom Decision Action Buttons
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: FluentSpacing.l,
            vertical: FluentSpacing.m,
          ),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(top: FluentStroke.side(brightness)),
          ),
          child: Row(
            children: [
              // Still Tricky Button
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _wrongColor,
                    side: const BorderSide(
                      color: _wrongColor,
                      width: FluentStroke.width,
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: FluentSpacing.m,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: FluentRadius.controlBorder,
                    ),
                  ),
                  onPressed: () => _handleAnswer(false),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: Text(
                    'এখনও ট্রিকি',
                    style: FluentType.bodyStrong,
                  ),
                ),
              ),
              const SizedBox(width: FluentSpacing.m),

              // Mastered Button
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _correctColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      vertical: FluentSpacing.m,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: FluentRadius.controlBorder,
                    ),
                  ),
                  onPressed: () => _handleAnswer(true),
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: Text(
                    'আয়ত্তে এসেছে!',
                    style: FluentType.bodyStrong,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompletionScreen(bool isDark) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    final onSurface = scheme.onSurface;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FluentSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(FluentSpacing.xl),
              decoration: BoxDecoration(
                color: FluentLayer.subtle(_correctColor, brightness),
                borderRadius: FluentRadius.cardBorder,
              ),
              child: const Icon(
                Icons.emoji_events_rounded,
                color: _correctColor,
                size: 64,
              ),
            ),
            const SizedBox(height: FluentSpacing.xl),
            Text(
              'দারুণ কাজ! আজকের রিভিশন শেষ! 🎉',
              textAlign: TextAlign.center,
              style: FluentType.subtitle.copyWith(color: onSurface),
            ),
            const SizedBox(height: FluentSpacing.m),
            Text(
              'ঘুমানোর আগে ভুলগুলো রিভিশন দেওয়ার কারণে আপনার দীর্ঘমেয়াদি স্মৃতিশক্তি ও রিটেনশন বহুগুণ বৃদ্ধি পাবে।',
              textAlign: TextAlign.center,
              style: FluentType.body.copyWith(
                color: onSurface.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: FluentSpacing.xxl),

            // Summary Pills
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildSummaryStat(
                  'আয়ত্তে এসেছে',
                  '$_masteredCount টি',
                  _correctColor,
                  Icons.check_circle,
                  isDark,
                ),
                const SizedBox(width: FluentSpacing.l),
                _buildSummaryStat(
                  'পুনর্বার দেখবেন',
                  '$_stillTrickyCount টি',
                  _hintColor,
                  Icons.replay,
                  isDark,
                ),
              ],
            ),
            const SizedBox(height: FluentSpacing.xxl + FluentSpacing.s),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    vertical: FluentSpacing.m,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: FluentRadius.controlBorder,
                  ),
                ),
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Mistake Notebook এ ফিরে যান',
                  style: FluentType.bodyStrong,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryStat(
    String label,
    String value,
    Color color,
    IconData icon,
    bool isDark,
  ) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FluentSpacing.l,
        vertical: FluentSpacing.m,
      ),
      decoration: BoxDecoration(
        color: FluentLayer.subtle(color, theme.brightness),
        borderRadius: FluentRadius.cardBorder,
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: FluentStroke.width,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: FluentSpacing.s),
              Text(
                value,
                style: FluentType.subtitle.copyWith(
                  fontSize: 18,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: FluentSpacing.xs),
          Text(
            label,
            style: FluentType.caption.copyWith(
              color: onSurface.withValues(alpha: 0.65),
            ),
          ),
        ],
      ),
    );
  }
}
