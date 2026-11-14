import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/tables/weak_topics_table.dart';
import '../../../../core/services/ai/quiz_generator_service.dart';
import '../../../../core/theme/fluent_tokens.dart';
import '../../../../core/utils/bengali_math_sanitizer.dart';
import '../../../../core/widgets/ai_progress_pipeline_widget.dart';
import '../../../quiz/presentation/providers/drill_history_provider.dart';
import '../../../topics/presentation/providers/topics_provider.dart';

/// The healing green. A status colour (this flow is a health meter), kept
/// while the gradients and coloured glows around it go.
const Color _healingAccent = Color(0xFF10B981);

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
  int? _liveTokens;
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
          onTokens: (tokens) {
            if (mounted) {
              setState(() {
                _liveTokens = tokens;
              });
            }
          },
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

    // Nothing is invented to fill a gap: a healing drill is answered and
    // scored, so a made-up question would be recorded as a topic the user
    // got wrong. An empty drill is reported instead.

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
    final timerColor = _secondsRemaining <= 30
        ? Colors.redAccent
        : _healingAccent;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(
              Icons.healing_rounded,
              color: _healingAccent,
              size: 22,
            ),
            const SizedBox(width: FluentSpacing.s),
            Flexible(
              child: Text(
                '৩ মিনিটের হিলিং ড্রিল',
                style: FluentType.subtitle.copyWith(fontSize: 16),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: FluentSpacing.m),
            padding: const EdgeInsets.symmetric(
              horizontal: FluentSpacing.s,
              vertical: FluentSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: FluentLayer.subtle(
                timerColor,
                Theme.of(context).brightness,
              ),
              borderRadius: FluentRadius.controlBorder,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.timer_outlined, size: 15, color: timerColor),
                const SizedBox(width: FluentSpacing.xs),
                Text(
                  _formatTimer(_secondsRemaining),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FluentType.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: timerColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? AiProgressPipelineWidget(
                type: AiTaskType.drill,
                isCompact: false,
                liveTokens: _liveTokens,
              )
            : (_isCompleted
                  ? _buildCompletionScreen(isDark)
                  : _buildQuestionView(isDark)),
      ),
    );
  }

  Widget _buildQuestionView(bool isDark) {
    if (_questions.isEmpty) {
      // Reached when nothing could be gathered and nothing was invented to
      // cover for it.
      return Padding(
        padding: const EdgeInsets.all(FluentSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 38,
              color: Colors.orange,
            ),
            const SizedBox(height: FluentSpacing.l),
            Text(
              'এই টপিকের জন্য ড্রিল তৈরি করা গেল না।\n'
              'ইন্টারনেট দেখে আবার চেষ্টা করুন।',
              textAlign: TextAlign.center,
              style: FluentType.body.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: FluentSpacing.xl),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: FluentRadius.controlBorder,
                ),
              ),
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, size: 18),
              label: Text('বন্ধ করুন', style: FluentType.bodyStrong),
            ),
          ],
        ),
      );
    }

    final currentQ = _questions[_currentIndex];
    final total = _questions.length;

    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(FluentSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Topic and Progress Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FluentSpacing.s,
                    vertical: FluentSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: FluentLayer.subtle(_healingAccent, brightness),
                    borderRadius: FluentRadius.controlBorder,
                  ),
                  child: Text(
                    '${widget.topic.subject} • ${widget.topic.topicName}',
                    style: FluentType.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: _healingAccent,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: FluentSpacing.s),
              Flexible(
                child: Text(
                  'প্রশ্ন ${_currentIndex + 1} / $total',
                  style: FluentType.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: FluentSpacing.s),
          ClipRRect(
            borderRadius: FluentRadius.controlBorder,
            child: LinearProgressIndicator(
              value: (_currentIndex + 1) / total,
              minHeight: 5,
              backgroundColor: scheme.onSurface.withValues(alpha: 0.10),
              valueColor: const AlwaysStoppedAnimation<Color>(_healingAccent),
            ),
          ),
          const SizedBox(height: FluentSpacing.l),

          // Question Card
          Card(
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
                  if (currentQ.sourceMistakeId != null) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: FluentSpacing.s),
                      padding: const EdgeInsets.symmetric(
                        horizontal: FluentSpacing.s,
                        vertical: FluentSpacing.xxs,
                      ),
                      decoration: BoxDecoration(
                        color: FluentLayer.subtle(Colors.redAccent, brightness),
                        borderRadius: FluentRadius.controlBorder,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.replay,
                            size: 12,
                            color: Colors.redAccent,
                          ),
                          const SizedBox(width: FluentSpacing.xs),
                          Flexible(
                            child: Text(
                              'পূর্বের ভুল প্রশ্ন',
                              style: FluentType.caption.copyWith(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.redAccent,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  Text(
                    BengaliMathSanitizer.sanitize(currentQ.questionText),
                    style: FluentType.bodyStrong.copyWith(
                      fontSize: 15,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: FluentSpacing.l),

                  // 4 Options
                  ...List.generate(currentQ.options.length, (idx) {
                    final isSelected = _selectedOptionIndex == idx;
                    final isCorrect = idx == currentQ.correctIndex;

                    Color optBg = scheme.onSurface.withValues(alpha: 0.04);
                    Color optBorder = FluentStroke.card(brightness);
                    Color optTextColor = scheme.onSurface;

                    if (_isAnswerSubmitted) {
                      if (isCorrect) {
                        optBg = FluentLayer.subtle(Colors.green, brightness);
                        optBorder = Colors.green;
                        optTextColor = Colors.green.shade800;
                      } else if (isSelected) {
                        optBg = FluentLayer.subtle(
                          Colors.redAccent,
                          brightness,
                        );
                        optBorder = Colors.redAccent;
                        optTextColor = Colors.red.shade800;
                      }
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: FluentSpacing.s),
                      child: InkWell(
                        onTap: () => _selectOption(idx),
                        borderRadius: FluentRadius.controlBorder,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: FluentSpacing.m,
                            vertical: FluentSpacing.m,
                          ),
                          decoration: BoxDecoration(
                            color: optBg,
                            borderRadius: FluentRadius.controlBorder,
                            border: Border.all(color: optBorder),
                          ),
                          child: Row(
                            children: [
                              Text(
                                '${String.fromCharCode(65 + idx)}. ',
                                style: FluentType.bodyStrong.copyWith(
                                  color: optTextColor,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  BengaliMathSanitizer.sanitize(
                                    currentQ.options[idx],
                                  ),
                                  style:
                                      (isCorrect && _isAnswerSubmitted
                                              ? FluentType.bodyStrong
                                              : FluentType.body)
                                          .copyWith(color: optTextColor),
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
                    const SizedBox(height: FluentSpacing.m),
                    Container(
                      padding: const EdgeInsets.all(FluentSpacing.m),
                      decoration: BoxDecoration(
                        color: FluentLayer.subtle(Colors.amber, brightness),
                        borderRadius: FluentRadius.controlBorder,
                        border: Border.all(
                          color: Colors.amber.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.lightbulb_outline,
                                color: Colors.amber,
                                size: 16,
                              ),
                              const SizedBox(width: FluentSpacing.s),
                              Flexible(
                                child: Text(
                                  'ব্যাখ্যা ও মনে রাখার রুল:',
                                  style: FluentType.caption.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.amber,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: FluentSpacing.s),
                          Text(
                            BengaliMathSanitizer.sanitize(currentQ.explanation),
                            style: FluentType.caption.copyWith(
                              color: scheme.onSurface.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: FluentSpacing.l),

                    // Next / Finish Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _healingAccent,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            vertical: FluentSpacing.m,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: FluentRadius.controlBorder,
                          ),
                        ),
                        onPressed: _nextQuestion,
                        child: Text(
                          _currentIndex + 1 >= total
                              ? 'ফলাফল ও হিলিং প্রগ্রেস দেখুন'
                              : 'পরবর্তী প্রশ্ন →',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: FluentType.bodyStrong,
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

    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final resultColor = isLevelUp ? Colors.green : Colors.amber;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FluentSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(FluentSpacing.xl),
              decoration: BoxDecoration(
                color: FluentLayer.subtle(resultColor, brightness),
                borderRadius: FluentRadius.cardBorder,
              ),
              child: Icon(
                isLevelUp ? Icons.celebration_rounded : Icons.replay_rounded,
                color: resultColor,
                size: 64,
              ),
            ),
            const SizedBox(height: FluentSpacing.xl),
            Text(
              isLevelUp ? '🎉 হিলিং সফল হয়েছে!' : 'খুব ভালো চেষ্টা! 👍',
              textAlign: TextAlign.center,
              style: FluentType.subtitle.copyWith(color: scheme.onSurface),
            ),
            const SizedBox(height: FluentSpacing.s),
            Text(
              isLevelUp
                  ? '"${widget.topic.topicName}" টপিকটি সফলভাবে রিভিশন দেওয়া হয়েছে এবং আপনার প্রফিশিয়েন্সি লেভেল বৃদ্ধি পেয়েছে।'
                  : '"${widget.topic.topicName}" টপিকটি নিয়মিত রিভিশন দিন, শীঘ্রই এটি আপনার স্ট্রং জোনে চলে আসবে।',
              textAlign: TextAlign.center,
              style: FluentType.body.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: FluentSpacing.xl),

            // Score Pill
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: FluentSpacing.xl,
                vertical: FluentSpacing.m,
              ),
              decoration: BoxDecoration(
                color: FluentLayer.subtle(resultColor, brightness),
                borderRadius: FluentRadius.controlBorder,
              ),
              child: Column(
                children: [
                  Text(
                    '$percent%',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FluentType.title.copyWith(
                      color: isLevelUp ? Colors.green : Colors.amber.shade800,
                    ),
                  ),
                  Text(
                    '$_correctCount / $total টি প্রশ্ন সঠিক হয়েছে',
                    textAlign: TextAlign.center,
                    style: FluentType.caption.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: FluentSpacing.xxl),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _healingAccent,
                  foregroundColor: Colors.white,
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
                  'ড্যাশবোর্ডে ফিরে যান',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FluentType.bodyStrong,
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
