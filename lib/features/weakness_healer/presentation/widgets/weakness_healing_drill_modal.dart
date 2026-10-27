import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/tables/weak_topics_table.dart';
import '../../../../core/services/ai/quiz_generator_service.dart';
import '../../../../core/utils/bengali_math_sanitizer.dart';
import '../../../quiz/presentation/providers/drill_history_provider.dart';
import '../../../topics/presentation/providers/topics_provider.dart';

class WeaknessHealingDrillModal extends ConsumerStatefulWidget {
  final WeakTopic topic;
  final List<DrillQuestion> relatedMistakes;

  const WeaknessHealingDrillModal({
    super.key,
    required this.topic,
    this.relatedMistakes = const [],
  });

  static Future<void> show(
    BuildContext context, {
    required WeakTopic topic,
    List<DrillQuestion> relatedMistakes = const [],
  }) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => WeaknessHealingDrillModal(
          topic: topic,
          relatedMistakes: relatedMistakes,
        ),
      ),
    );
  }

  @override
  ConsumerState<WeaknessHealingDrillModal> createState() =>
      _WeaknessHealingDrillModalState();
}

class _WeaknessHealingDrillModalState
    extends ConsumerState<WeaknessHealingDrillModal> {
  bool _isLoading = true;
  final List<_HealingQuestionItem> _questions = [];
  int _currentIndex = 0;
  int? _selectedOptionIndex;
  bool _isAnswerSubmitted = false;
  int _correctCount = 0;
  bool _isCompleted = false;

  // 3-Minute Live Countdown Timer
  Timer? _countdownTimer;
  int _secondsRemaining = 180; // 3 minutes = 180 seconds

  @override
  void initState() {
    super.initState();
    _prepareQuestions();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _prepareQuestions() async {
    final List<_HealingQuestionItem> items = [];

    // 1. Add questions from user's actual mistakes on this topic (up to 3)
    for (final m in widget.relatedMistakes.take(3)) {
      List<String> options = [];
      try {
        final decoded = jsonDecode(m.optionsJson);
        if (decoded is List) {
          options = decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}

      if (options.length >= 2) {
        items.add(
          _HealingQuestionItem(
            questionText: m.questionText,
            options: options,
            correctIndex: m.correctIndex,
            explanation: m.explanation,
            sourceMistakeId: m.id,
          ),
        );
      }
    }

    // 2. If fewer than 3, generate high-yield AI questions for this weak topic
    if (items.length < 3) {
      final needed = 3 - items.length;
      try {
        final aiQuestions = await QuizGeneratorService.instance.generateQuiz(
          topic: widget.topic.topicName,
          subject: widget.topic.subject,
          count: needed,
        );

        for (final q in aiQuestions) {
          items.add(
            _HealingQuestionItem(
              questionText: q.questionText,
              options: q.options,
              correctIndex: q.correctIndex,
              explanation: q.explanation,
            ),
          );
        }
      } catch (_) {}
    }

    // Fallback if still empty
    if (items.isEmpty) {
      items.add(
        _HealingQuestionItem(
          questionText:
              '${widget.topic.topicName} সম্পর্কিত গুরুত্বপূর্ণ নিয়ম কোনটি?',
          options: const ['নিয়ম ১', 'নিয়ম ২', 'নিয়ম ৩', 'নিয়ম ৪'],
          correctIndex: 0,
          explanation: 'এই নিয়মটি পরীক্ষার জন্য অত্যন্ত গুরুত্বপূর্ণ।',
        ),
      );
    }

    if (mounted) {
      setState(() {
        _questions.addAll(items);
        _isLoading = false;
      });
      _startTimer();
    }
  }

  void _startTimer() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsRemaining <= 1) {
        timer.cancel();
        _finishSession();
      } else {
        setState(() {
          _secondsRemaining--;
        });
      }
    });
  }

  void _selectOption(int index) {
    if (_isAnswerSubmitted) return;
    setState(() {
      _selectedOptionIndex = index;
      _isAnswerSubmitted = true;
    });

    final currentQ = _questions[_currentIndex];
    final isCorrect = index == currentQ.correctIndex;

    if (isCorrect) {
      _correctCount++;
      // If this was an unmastered mistake from Mistake Bank, mark it mastered!
      if (currentQ.sourceMistakeId != null) {
        ref
            .read(drillHistoryNotifierProvider.notifier)
            .markQuestionMastered(currentQ.sourceMistakeId!, true);
      }
    }
  }

  void _nextQuestion() {
    if (_currentIndex + 1 >= _questions.length) {
      _finishSession();
    } else {
      setState(() {
        _currentIndex++;
        _selectedOptionIndex = null;
        _isAnswerSubmitted = false;
      });
    }
  }

  Future<void> _finishSession() async {
    _countdownTimer?.cancel();

    // Check if score warrants leveling up the topic
    final double scorePercent = _questions.isEmpty
        ? 0.0
        : (_correctCount / _questions.length) * 100.0;

    final currentLevel = widget.topic.proficiencyLevel;
    ProficiencyLevel newLevel = currentLevel;

    if (scorePercent >= 66.0) {
      if (currentLevel == ProficiencyLevel.weak) {
        newLevel = ProficiencyLevel.moderate;
      } else if (currentLevel == ProficiencyLevel.moderate) {
        newLevel = ProficiencyLevel.strong;
      }
    }

    // Persist new proficiency & reviewed timestamp
    if (newLevel != currentLevel) {
      await ref
          .read(topicsNotifierProvider.notifier)
          .updateProficiency(widget.topic.id, newLevel);
    }
    await ref
        .read(topicsNotifierProvider.notifier)
        .markReviewed(widget.topic.id);

    if (mounted) {
      setState(() {
        _isCompleted = true;
      });
    }
  }

  String _formatTimer(int totalSeconds) {
    final mins = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
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
            Icon(Icons.healing_rounded, color: Color(0xFF10B981), size: 22),
            SizedBox(width: 8),
            Text(
              '৩ মিনিটের হিলিং ড্রিল',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 14),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _secondsRemaining <= 30
                  ? Colors.redAccent.withValues(alpha: 0.15)
                  : const Color(0xFF10B981).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _secondsRemaining <= 30
                    ? Colors.redAccent
                    : const Color(0xFF10B981),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.timer_outlined,
                  size: 15,
                  color: _secondsRemaining <= 30
                      ? Colors.redAccent
                      : const Color(0xFF10B981),
                ),
                const SizedBox(width: 4),
                Text(
                  _formatTimer(_secondsRemaining),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: _secondsRemaining <= 30
                        ? Colors.redAccent
                        : const Color(0xFF10B981),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(strokeWidth: 3),
                    SizedBox(height: 16),
                    Text(
                      'দুর্বল টপিকের হিলিং প্রশ্ন প্রস্তুত হচ্ছে...',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ],
                ),
              )
            : (_isCompleted
                  ? _buildCompletionScreen(isDark)
                  : _buildQuestionView(isDark)),
      ),
    );
  }

  Widget _buildQuestionView(bool isDark) {
    final currentQ = _questions[_currentIndex];
    final total = _questions.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Topic and Progress Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${widget.topic.subject} • ${widget.topic.topicName}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF10B981),
                  ),
                ),
              ),
              Text(
                'প্রশ্ন ${_currentIndex + 1} / $total',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (_currentIndex + 1) / total,
              minHeight: 5,
              backgroundColor: isDark ? Colors.white12 : Colors.grey.shade300,
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF10B981),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Question Card
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (currentQ.sourceMistakeId != null) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.replay, size: 12, color: Colors.redAccent),
                          SizedBox(width: 4),
                          Text(
                            'পূর্বের ভুল প্রশ্ন',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.redAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  Text(
                    BengaliMathSanitizer.sanitize(currentQ.questionText),
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.bold,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 4 Options
                  ...List.generate(currentQ.options.length, (idx) {
                    final isSelected = _selectedOptionIndex == idx;
                    final isCorrect = idx == currentQ.correctIndex;

                    Color optBg = isDark
                        ? const Color(0xFF0F172A)
                        : const Color(0xFFF1F5F9);
                    Color optBorder = isDark
                        ? Colors.white10
                        : Colors.grey.shade300;
                    Color optTextColor = isDark ? Colors.white : Colors.black87;

                    if (_isAnswerSubmitted) {
                      if (isCorrect) {
                        optBg = Colors.green.withValues(alpha: 0.18);
                        optBorder = Colors.green;
                        optTextColor = Colors.green.shade800;
                      } else if (isSelected) {
                        optBg = Colors.red.withValues(alpha: 0.18);
                        optBorder = Colors.redAccent;
                        optTextColor = Colors.red.shade800;
                      }
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        onTap: () => _selectOption(idx),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: optBg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: optBorder),
                          ),
                          child: Row(
                            children: [
                              Text(
                                '${String.fromCharCode(65 + idx)}. ',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: optTextColor,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  BengaliMathSanitizer.sanitize(
                                    currentQ.options[idx],
                                  ),
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    color: optTextColor,
                                    fontWeight: isCorrect && _isAnswerSubmitted
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                              if (_isAnswerSubmitted && isCorrect)
                                const Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                  size: 18,
                                ),
                              if (_isAnswerSubmitted &&
                                  isSelected &&
                                  !isCorrect)
                                const Icon(
                                  Icons.cancel,
                                  color: Colors.redAccent,
                                  size: 18,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),

                  // Explanation after answer submission
                  if (_isAnswerSubmitted) ...[
                    const SizedBox(height: 12),
                    Container(
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
                                Icons.lightbulb_outline,
                                color: Colors.amber,
                                size: 16,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'ব্যাখ্যা ও মনে রাখার রুল:',
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
                            BengaliMathSanitizer.sanitize(currentQ.explanation),
                            style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Next / Finish Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: _nextQuestion,
                        child: Text(
                          _currentIndex + 1 >= total
                              ? 'ফলাফল ও হিলিং প্রগ্রেস দেখুন'
                              : 'পরবর্তী প্রশ্ন →',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletionScreen(bool isDark) {
    final total = _questions.length;
    final percent = total == 0 ? 0 : ((_correctCount / total) * 100).round();
    final isLevelUp = percent >= 66;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: (isLevelUp ? Colors.green : Colors.amber).withValues(
                  alpha: 0.15,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isLevelUp ? Icons.celebration_rounded : Icons.replay_rounded,
                color: isLevelUp ? Colors.green : Colors.amber,
                size: 64,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              isLevelUp ? '🎉 হিলিং সফল হয়েছে!' : 'খুব ভালো চেষ্টা! 👍',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              isLevelUp
                  ? '"${widget.topic.topicName}" টপিকটি সফলভাবে রিভিশন দেওয়া হয়েছে এবং আপনার প্রফিশিয়েন্সি লেভেল বৃদ্ধি পেয়েছে।'
                  : '"${widget.topic.topicName}" টপিকটি নিয়মিত রিভিশন দিন, শীঘ্রই এটি আপনার স্ট্রং জোনে চলে আসবে।',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            const SizedBox(height: 20),

            // Score Pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: (isLevelUp ? Colors.green : Colors.amber).withValues(
                  alpha: 0.1,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: (isLevelUp ? Colors.green : Colors.amber).withValues(
                    alpha: 0.3,
                  ),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    '$percent%',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: isLevelUp ? Colors.green : Colors.amber.shade800,
                    ),
                  ),
                  Text(
                    '$_correctCount / $total টি প্রশ্ন সঠিক হয়েছে',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'ড্যাশবোর্ডে ফিরে যান',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HealingQuestionItem {
  final String questionText;
  final List<String> options;
  final int correctIndex;
  final String explanation;
  final int? sourceMistakeId;

  _HealingQuestionItem({
    required this.questionText,
    required this.options,
    required this.correctIndex,
    required this.explanation,
    this.sourceMistakeId,
  });
}
