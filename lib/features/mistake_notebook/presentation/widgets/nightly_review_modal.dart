import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/utils/bengali_math_sanitizer.dart';
import '../../../quiz/presentation/providers/drill_history_provider.dart';
import '../../domain/models/mistake_folder.dart';
import 'ai_mistake_explainer_sheet.dart';

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.nightlight_round, color: Colors.amber, size: 20),
            SizedBox(width: 8),
            Text(
              'রাতের ৫ মিনিটের রিভিশন',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'কার্ড ${_currentIndex + 1} / $total',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: source.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: source.color.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(source.icon, size: 12, color: source.color),
                            const SizedBox(width: 4),
                            Text(
                              source.banglaLabel,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: source.color,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: isDark
                      ? Colors.white12
                      : Colors.grey.shade300,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF8B5CF6),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Main Review Flashcard Body
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Subject & Topic Badge
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.indigo.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            currentQ.subject,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            currentQ.topic,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white70 : Colors.black87,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Question Text
                    Text(
                      BengaliMathSanitizer.sanitize(currentQ.questionText),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Unrevealed state: Tap to reveal
                    if (!_isAnswerRevealed) ...[
                      GestureDetector(
                        onTap: _revealAnswer,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            vertical: 24,
                            horizontal: 16,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF8B5CF6)
                                .withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: const Color(0xFF8B5CF6)
                                  .withValues(alpha: 0.3),
                              style: BorderStyle.solid,
                              width: 1.5,
                            ),
                          ),
                          child: const Column(
                            children: [
                              Icon(
                                Icons.touch_app_rounded,
                                color: Color(0xFF8B5CF6),
                                size: 36,
                              ),
                              SizedBox(height: 8),
                              Text(
                                'ট্যাপ করে সঠিক উত্তর ও ব্যাখ্যা দেখুন',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Color(0xFF8B5CF6),
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'মনে মনে সঠিক উত্তরটি আগে ভাবুন',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ] else ...[
                      // Revealed State: Options comparison
                      const Text(
                        'অপশনসমূহ:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...List.generate(options.length, (idx) {
                        final isCorrectOpt = idx == currentQ.correctIndex;
                        final isSelectedOpt = idx == currentQ.selectedIndex;

                        Color optBg = isDark
                            ? const Color(0xFF0F172A)
                            : const Color(0xFFF1F5F9);
                        Color optBorder = Colors.transparent;
                        Widget? trailingIcon;

                        if (isCorrectOpt) {
                          optBg = Colors.green.withValues(alpha: 0.15);
                          optBorder = Colors.green;
                          trailingIcon = const Icon(
                            Icons.check_circle,
                            color: Colors.green,
                            size: 18,
                          );
                        } else if (isSelectedOpt) {
                          optBg = Colors.red.withValues(alpha: 0.12);
                          optBorder = Colors.redAccent;
                          trailingIcon = const Icon(
                            Icons.cancel,
                            color: Colors.redAccent,
                            size: 18,
                          );
                        }

                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: optBg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: optBorder),
                          ),
                          child: Row(
                            children: [
                              Text(
                                '${String.fromCharCode(65 + idx)}. ',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  BengaliMathSanitizer.sanitize(options[idx]),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isCorrectOpt
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isCorrectOpt
                                        ? Colors.green.shade700
                                        : (isSelectedOpt
                                              ? Colors.red.shade700
                                              : null),
                                  ),
                                ),
                              ),
                              ?trailingIcon,
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 12),

                      // Explanation box
                      if (currentQ.explanation.isNotEmpty) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.amber.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(
                                    Icons.lightbulb,
                                    color: Colors.amber,
                                    size: 16,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'ব্যাখ্যা ও রুল:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: Colors.amber,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                BengaliMathSanitizer.sanitize(
                                  currentQ.explanation,
                                ),
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],

                      // AI Explainer button
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () =>
                              AiMistakeExplainerSheet.show(context, currentQ),
                          icon: const Icon(
                            Icons.auto_awesome,
                            size: 15,
                            color: Color(0xFF8B5CF6),
                          ),
                          label: const Text(
                            'AI ভুল বিশ্লেষণ ও শর্টকাট',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF8B5CF6),
                              fontWeight: FontWeight.bold,
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            border: Border(
              top: BorderSide(
                color: isDark ? Colors.white10 : Colors.grey.shade200,
              ),
            ),
          ),
          child: Row(
            children: [
              // Still Tricky Button
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => _handleAnswer(false),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text(
                    'এখনও ট্রিকি',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Mastered Button
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => _handleAnswer(true),
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text(
                    'আয়ত্তে এসেছে!',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.emoji_events_rounded,
                color: Colors.green,
                size: 64,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'দারুণ কাজ! আজকের রিভিশন শেষ! 🎉',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'ঘুমানোর আগে ভুলগুলো রিভিশন দেওয়ার কারণে আপনার দীর্ঘমেয়াদি স্মৃতিশক্তি ও রিটেনশন বহুগুণ বৃদ্ধি পাবে।',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            const SizedBox(height: 24),

            // Summary Pills
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildSummaryStat(
                  'আয়ত্তে এসেছে',
                  '$_masteredCount টি',
                  Colors.green,
                  Icons.check_circle,
                  isDark,
                ),
                const SizedBox(width: 16),
                _buildSummaryStat(
                  'পুনর্বার দেখবেন',
                  '$_stillTrickyCount টি',
                  Colors.amber.shade800,
                  Icons.replay,
                  isDark,
                ),
              ],
            ),
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Mistake Notebook এ ফিরে যান',
                  style: TextStyle(fontWeight: FontWeight.bold),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}
