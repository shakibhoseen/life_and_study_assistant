import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/tables/weak_topics_table.dart';
import '../../../../core/services/ai/models/quiz_question.dart';
import '../../../../core/services/ai/quiz_generator_service.dart';
import '../../../../core/theme/fluent_tokens.dart';
import '../../../../core/utils/bengali_math_sanitizer.dart';
import '../../../../core/widgets/ai_progress_pipeline_widget.dart';
import '../../../../core/widgets/celebration_confetti.dart';
import '../../../analytics/presentation/providers/study_streak_provider.dart';
import '../../../topics/presentation/providers/topics_provider.dart';
import '../providers/drill_history_provider.dart';
import 'quiz_batch_correction_sheet.dart';
import '../../../../core/widgets/ai_key_missing_notice.dart';
import '../../../../core/database/database_provider.dart';
import '../../../spaced_repetition/presentation/providers/spaced_repetition_provider.dart';
import '../../domain/weak_topic_signal.dart';

import 'package:shared_preferences/shared_preferences.dart';

enum QuizMode { practice, realExam }

/// The three status colours the quiz actually means something by: a right
/// answer, a wrong one, and one that was skipped.
///
/// They are kept here rather than typed at each call site so the same green
/// and the same red are used everywhere, and so each has a light-mode and a
/// dark-mode value that genuinely reads on that surface — the previous mix of
/// `Colors.green.shade900` and `Colors.greenAccent` did not.
Color _correctColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF4ADE80)
    : const Color(0xFF15803D);

Color _wrongColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFFF87171)
    : const Color(0xFFB91C1C);

Color _skippedColor(BuildContext context) =>
    Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);

/// Amber is the explanation/warning accent, legible on both themes.
Color _noticeColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFFFCD34D)
    : const Color(0xFFB45309);

class QuizDrillModal extends ConsumerStatefulWidget {
  final String topic;
  final String subject;
  final int? examId;
  final List<DrillQuestion>? mistakeQuestions;
  final List<QuizQuestion>? customQuestions;
  final VoidCallback? onCompleted;
  final QuizMode initialMode;

  const QuizDrillModal({
    super.key,
    required this.topic,
    required this.subject,
    this.examId,
    this.mistakeQuestions,
    this.customQuestions,
    this.onCompleted,
    this.initialMode = QuizMode.practice,
  });

  static Future<void> show(
    BuildContext context, {
    required String topic,
    required String subject,
    int? examId,
    List<DrillQuestion>? mistakeQuestions,
    List<QuizQuestion>? customQuestions,
    VoidCallback? onCompleted,
    QuizMode initialMode = QuizMode.practice,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => QuizDrillModal(
        topic: topic,
        subject: subject,
        examId: examId,
        mistakeQuestions: mistakeQuestions,
        customQuestions: customQuestions,
        onCompleted: onCompleted,
        initialMode: initialMode,
      ),
    );
  }

  @override
  ConsumerState<QuizDrillModal> createState() => _QuizDrillModalState();
}

class _QuizDrillModalState extends ConsumerState<QuizDrillModal> {
  late QuizMode _mode;
  bool _isLoading = true;
  String? _loadError;
  int? _liveTokens;
  List<QuizQuestion> _questions = [];
  int _currentIndex = 0;
  int? _selectedOptionIndex;
  bool _hasAnswered = false;
  int _correctCount = 0;
  bool _isFinished = false;
  final Map<int, int> _userAnswers = {};
  bool _hasPersisted = false;

  Timer? _examTimer;
  int _remainingSeconds = 0;
  int _totalExamSeconds = 0;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    // The remembered size is read first so the drill is the length the user
    // last chose, not five every time.
    _loadDrillSize().then((_) => _loadQuestions());
  }

  @override
  void dispose() {
    _examTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadQuestions() async {
    _examTimer?.cancel();
    if (widget.customQuestions != null && widget.customQuestions!.isNotEmpty) {
      setState(() {
        _questions = widget.customQuestions!;
        _isLoading = false;
        _isFinished = false;
        _currentIndex = 0;
        _selectedOptionIndex = null;
        _hasAnswered = false;
        _correctCount = 0;
        _userAnswers.clear();
        _hasPersisted = false;
        _mistakesSaved = false;
      });
      if (_mode == QuizMode.realExam) {
        _startExamTimer();
      }
      return;
    }

    setState(() {
      _isLoading = true;
      _loadError = null;
      _liveTokens = null;
    });
    try {
      final questions = await QuizGeneratorService.instance.generateQuiz(
        topic: widget.topic,
        subject: widget.subject,
        count: _drillSize,
        onTokens: (tokens) {
          if (mounted) {
            setState(() {
              _liveTokens = tokens;
            });
          }
        },
      );
      if (!mounted) return;
      setState(() {
        _questions = questions;
        _isLoading = false;
        _isFinished = false;
        _currentIndex = 0;
        _selectedOptionIndex = null;
        _hasAnswered = false;
        _correctCount = 0;
        _userAnswers.clear();
        _hasPersisted = false;
        _mistakesSaved = false;
      });
      if (_mode == QuizMode.realExam) {
        _startExamTimer();
      }
    } on QuizGenerationException catch (e) {
      // Nothing is shown rather than something invented: a drill the user
      // answers is scored and remembered, so a made-up question would end up
      // in the mistake notebook as a topic they are weak at.
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = e.userMessage;
      });
    }
  }

  void _startExamTimer() {
    _examTimer?.cancel();
    if (_questions.isEmpty) return;
    _totalExamSeconds = _questions.length * 60; // 1 min per MCQ
    _remainingSeconds = _totalExamSeconds;
    _examTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_remainingSeconds > 0) {
        setState(() {
          _remainingSeconds--;
        });
      } else {
        timer.cancel();
        _submitRealExam(timeExpired: true);
      }
    });
  }

  void _switchMode(QuizMode newMode) {
    if (_mode == newMode) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _mode = newMode;
      _currentIndex = 0;
      _selectedOptionIndex = null;
      _hasAnswered = false;
      _correctCount = 0;
      _isFinished = false;
      _userAnswers.clear();
      _hasPersisted = false;
    });
    if (newMode == QuizMode.realExam) {
      _startExamTimer();
    } else {
      _examTimer?.cancel();
    }
  }

  void _onOptionSelected(int index) {
    if (_mode == QuizMode.realExam) {
      if (_isFinished) return;
      HapticFeedback.selectionClick();
      setState(() {
        _selectedOptionIndex = index;
        _userAnswers[_currentIndex] = index;
      });
      return;
    }

    if (_hasAnswered) return;
    HapticFeedback.selectionClick();
    setState(() {
      _selectedOptionIndex = index;
      _hasAnswered = true;
      _userAnswers[_currentIndex] = index;
      if (index == _questions[_currentIndex].correctIndex) {
        _correctCount++;
      }
    });
  }

  void _clearSelectedOption() {
    HapticFeedback.selectionClick();
    setState(() {
      _userAnswers.remove(_currentIndex);
      _selectedOptionIndex = null;
    });
  }

  void _jumpToQuestion(int index) {
    if (index < 0 || index >= _questions.length) return;
    HapticFeedback.selectionClick();
    setState(() {
      _currentIndex = index;
      _selectedOptionIndex = _userAnswers[index];
      _hasAnswered =
          _mode == QuizMode.practice && _userAnswers.containsKey(index);
    });
  }

  Future<void> _submitRealExam({bool timeExpired = false}) async {
    if (_isFinished) return;

    if (!timeExpired) {
      final unanswered = _questions.length - _userAnswers.length;
      if (unanswered > 0) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (dCtx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: FluentRadius.cardBorder,
            ),
            title: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.amber.shade700,
                  size: 20,
                ),
                const SizedBox(width: FluentSpacing.s),
                Flexible(
                  child: Text(
                    'সাবমিট নিশ্চিতকরণ',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FluentType.subtitle.copyWith(
                      fontSize: 16,
                      color: Theme.of(dCtx).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            content: Text(
              'আপনার এখনো $unansweredটি প্রশ্নের উত্তর বাকি রয়েছে।\n\n'
              'নেগেটিভ মার্কিং (-০.৫০) এড়াতে স্কিপ করতে পারেন অথবা উত্তর দিয়ে সাবমিট করতে পারেন।\n\n'
              'আপনি কি নিশ্চিত এখনই পরীক্ষা জমা দিতে চান?',
              style: FluentType.body.copyWith(
                color: Theme.of(dCtx).colorScheme.onSurface
                    .withValues(alpha: 0.80),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dCtx, false),
                child: const Text('না, ফিরে যাই'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(dCtx).colorScheme.primary,
                  foregroundColor: Theme.of(dCtx).colorScheme.onPrimary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: FluentRadius.controlBorder,
                  ),
                ),
                onPressed: () => Navigator.pop(dCtx, true),
                child: const Text('হ্যাঁ, সাবমিট করুন'),
              ),
            ],
          ),
        );
        if (proceed != true) return;
      }
    }

    _examTimer?.cancel();
    HapticFeedback.mediumImpact();
    setState(() {
      _isFinished = true;
    });
    await _persistDrillResults();
    widget.onCompleted?.call();
  }

  /// Moves on without an answer.
  ///
  /// Recorded as skipped rather than wrong: it does not count against the
  /// score, because not knowing something is not the same as getting it
  /// wrong. It does go into the revision deck, which is the whole point of
  /// admitting it.
  void _skipQuestion() {
    HapticFeedback.selectionClick();
    setState(() {
      _userAnswers[_currentIndex] = -1;
    });
    _nextQuestion();
  }

  void _nextQuestion() {
    if (_currentIndex < _questions.length - 1) {
      setState(() {
        _currentIndex++;
        _selectedOptionIndex = _userAnswers[_currentIndex];
        _hasAnswered =
            _mode == QuizMode.practice &&
            _userAnswers.containsKey(_currentIndex);
      });
    } else {
      HapticFeedback.mediumImpact();
      setState(() {
        _isFinished = true;
      });
      _persistDrillResults();
      widget.onCompleted?.call();
    }
  }

  Future<void> _persistDrillResults() async {
    if (_hasPersisted || _questions.isEmpty) return;
    _hasPersisted = true;

    final questionsCompanions = <DrillQuestionsCompanion>[];
    int calculatedCorrect = 0;
    int calculatedWrong = 0;

    for (int i = 0; i < _questions.length; i++) {
      final q = _questions[i];
      final selected = _userAnswers[i] ?? -1;
      final isCorrect = q.isCorrectChoice(selected);

      if (selected >= 0) {
        if (isCorrect) {
          calculatedCorrect++;
        } else {
          calculatedWrong++;
        }
      }

      questionsCompanions.add(
        DrillQuestionsCompanion.insert(
          subject: widget.subject,
          topic: widget.topic,
          questionText: q.questionText,
          optionsJson: jsonEncode(q.options),
          correctIndex: q.correctIndex,
          selectedIndex: selected,
          isCorrect: isCorrect,
          explanation: Value(q.explanation),
          isMastered: const Value(false),
          attemptedAt: Value(DateTime.now()),
        ),
      );
    }

    _correctCount = calculatedCorrect;
    final total = _questions.length;

    double percent = 0.0;
    if (_mode == QuizMode.realExam) {
      // BCS standard negative marking: +1 for correct, -0.50 for wrong
      final netScore = (calculatedCorrect * 1.0) - (calculatedWrong * 0.50);
      percent = total > 0
          ? ((netScore / (total * 1.0)) * 100.0).clamp(0.0, 100.0)
          : 0.0;
    } else {
      percent = total > 0 ? (calculatedCorrect / total) * 100.0 : 0.0;
    }

    try {
      await ref
          .read(drillHistoryNotifierProvider.notifier)
          .saveDrillSession(
            subject: widget.subject,
            topic: widget.topic,
            totalQuestions: total,
            correctCount: calculatedCorrect,
            incorrectCount: calculatedWrong,
            scorePercentage: percent,
            questions: questionsCompanions,
          );
      ref.invalidate(studyStreakProvider);
    } catch (e) {
      debugPrint('Error persisting drill session: $e');
    }
  }

  void _copyFullReviewToClipboard() {
    final total = _questions.length;
    int calcCorrect = 0;
    int calcWrong = 0;
    int calcSkipped = 0;
    for (int i = 0; i < total; i++) {
      final a = _userAnswers[i];
      if (a == null || a < 0) {
        calcSkipped++;
      } else if (a == _questions[i].correctIndex) {
        calcCorrect++;
      } else {
        calcWrong++;
      }
    }

    final buffer = StringBuffer();
    buffer.writeln('কুইজ পর্যালোচনা ও উত্তরপত্র (যাচাইয়ের জন্য):');
    if (_mode == QuizMode.realExam) {
      final net = (calcCorrect * 1.0) - (calcWrong * 0.50);
      buffer.writeln('মোড: রিয়েল এক্সাম (BCS নেগেটিভ মার্কিং -০.৫০)');
      buffer.writeln(
        'প্রাপ্ত নেট স্কোর: ${net.toStringAsFixed(2)} / $total.00',
      );
    } else {
      buffer.writeln('মোড: প্র্যাকটিস ড্রিল');
    }
    if (widget.examId != null) {
      buffer.writeln('পরীক্ষা রেফারেন্স: E-${widget.examId}');
    }
    if (widget.subject.isNotEmpty) buffer.writeln('বিষয়: ${widget.subject}');
    if (widget.topic.isNotEmpty) buffer.writeln('টপিক: ${widget.topic}');
    buffer.writeln(
      'মোট প্রশ্ন: $totalটি | সঠিক: $calcCorrectটি | ভুল: $calcWrongটি | স্কিপ: $calcSkippedটি',
    );
    buffer.writeln('==============================\n');

    for (int i = 0; i < _questions.length; i++) {
      final q = _questions[i];
      final selected = _userAnswers[i] ?? -1;
      final isCorrect = q.isCorrectChoice(selected);
      final userAnsText = selected >= 0 && selected < q.options.length
          ? q.options[selected]
          : 'উত্তর দেওয়া হয়নি';
      final correctAnsText =
          q.correctIndex >= 0 && q.correctIndex < q.options.length
          ? q.options[q.correctIndex]
          : 'Unknown';

      final refTag =
          (widget.mistakeQuestions != null &&
              i < widget.mistakeQuestions!.length)
          ? ' [Q-${widget.mistakeQuestions![i].id}]'
          : '';
      buffer.writeln('প্রশ্ন ${i + 1}$refTag: ${q.questionText}');
      buffer.writeln('অপশনসমূহ:');
      for (int optIdx = 0; optIdx < q.options.length; optIdx++) {
        final optChar = optIdx == 0
            ? 'ক'
            : (optIdx == 1 ? 'খ' : (optIdx == 2 ? 'গ' : 'ঘ'));
        buffer.writeln('  $optChar. ${q.options[optIdx]}');
      }
      buffer.writeln(
        '• পরীক্ষার্থীর উত্তর: $userAnsText ${isCorrect ? "(সঠিক ✓)" : "(ভুল ❌)"}',
      );
      buffer.writeln('• সিস্টেমের সঠিক উত্তর: $correctAnsText');
      if (q.explanation.isNotEmpty) {
        buffer.writeln('• প্রদত্ত ব্যাখ্যা: ${q.explanation}');
      }
      buffer.writeln('');
    }

    buffer.writeln('==============================');
    buffer.writeln(
      'নির্দেশনা: অনুগ্রহ করে উপরের প্রতিটি প্রশ্ন ও উত্তর নিরপেক্ষভাবে যাচাই করুন। কোনো প্রশ্নে তথ্যের ভুল, ভুল অপশন বা বিকল্প সঠিক উত্তর থাকলে বিস্তারিত বুঝিয়ে দিন।',
    );

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Color(0xFF10B981),
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white, size: 18),
            SizedBox(width: FluentSpacing.s),
            Expanded(
              child: Text(
                'সম্পূর্ণ কুইজ ও উত্তরপত্র ক্লিপবোর্ডে কপি হয়েছে! অন্য AI-তে পেস্ট করতে পারেন।',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPasteExternalAiFixSheet() async {
    final answersByText = <String, int>{};
    for (int i = 0; i < _questions.length; i++) {
      final ans = _userAnswers[i];
      if (ans != null) {
        answersByText[_questions[i].questionText] = ans;
      }
    }

    final updated = await QuizBatchCorrectionSheet.show(
      context,
      ref: ref,
      questions: _questions,
      examId: widget.examId,
      mistakeQuestions: widget.mistakeQuestions,
      topic: widget.topic,
      subject: widget.subject,
    );

    if (updated != null && mounted) {
      setState(() {
        _questions = updated;
        _userAnswers.clear();
        int newCorrect = 0;
        for (int i = 0; i < _questions.length; i++) {
          final userAns = answersByText[_questions[i].questionText];
          if (userAns != null) {
            _userAnswers[i] = userAns;
            if (userAns == _questions[i].correctIndex) {
              newCorrect++;
            }
          }
        }
        _correctCount = newCorrect;
        if (_currentIndex >= _questions.length) {
          _currentIndex = _questions.isEmpty ? 0 : _questions.length - 1;
        }
      });
    }
  }

  void _copySingleQuestionToClipboard(int index) {
    if (index < 0 || index >= _questions.length) return;
    final q = _questions[index];
    final selected = _userAnswers[index] ?? -1;
    final isCorrect = q.isCorrectChoice(selected);
    final userAnsText = selected >= 0 && selected < q.options.length
        ? q.options[selected]
        : 'উত্তর দেওয়া হয়নি';
    final correctAnsText =
        q.correctIndex >= 0 && q.correctIndex < q.options.length
        ? q.options[q.correctIndex]
        : 'Unknown';

    final buffer = StringBuffer();
    if (widget.subject.isNotEmpty) buffer.writeln('বিষয়: ${widget.subject}');
    if (widget.topic.isNotEmpty) buffer.writeln('টপিক: ${widget.topic}');
    buffer.writeln('প্রশ্ন: ${q.questionText}');
    buffer.writeln('অপশনসমূহ:');
    for (int optIdx = 0; optIdx < q.options.length; optIdx++) {
      final optChar = optIdx == 0
          ? 'ক'
          : (optIdx == 1 ? 'খ' : (optIdx == 2 ? 'গ' : 'ঘ'));
      buffer.writeln('  $optChar. ${q.options[optIdx]}');
    }
    buffer.writeln(
      '• পরীক্ষার্থীর উত্তর: $userAnsText ${isCorrect ? "(সঠিক ✓)" : "(ভুল ❌)"}',
    );
    buffer.writeln('• সিস্টেমের সঠিক উত্তর: $correctAnsText');
    if (q.explanation.isNotEmpty) {
      buffer.writeln('• প্রদত্ত ব্যাখ্যা: ${q.explanation}');
    }
    buffer.writeln(
      '\nঅনুগ্রহ করে প্রশ্নটি ফ্যাক্ট-চেক করে সঠিক উত্তর ও ব্যাখ্যা দিন।',
    );

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF10B981),
        content: Text('প্রশ্ন ${index + 1}-এর বিবরণ কপি হয়েছে!'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    final isDark = brightness == Brightness.dark;
    final isRealExam = _mode == QuizMode.realExam;
    final headerAccent = isRealExam ? _wrongColor(context) : scheme.primary;

    return Container(
      height: MediaQuery.of(context).size.height * 0.90,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(FluentRadius.large),
        ),
        border: Border(
          top: BorderSide(
            color: FluentStroke.card(brightness),
            width: FluentStroke.width,
          ),
        ),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(
              top: FluentSpacing.m,
              bottom: FluentSpacing.s,
            ),
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.onSurface.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: FluentSpacing.l,
              vertical: FluentSpacing.xs + 2,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(FluentSpacing.s),
                  decoration: BoxDecoration(
                    color: FluentLayer.subtle(headerAccent, brightness),
                    borderRadius: FluentRadius.controlBorder,
                  ),
                  child: Icon(
                    isRealExam ? Icons.timer_rounded : Icons.psychology,
                    color: headerAccent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: FluentSpacing.s),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isRealExam
                            ? 'রিয়েল এক্সাম (BCS স্ট্যান্ডার্ড)'
                            : 'LiveMCQ ড্রিল ও প্র্যাকটিস',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FluentType.bodyStrong.copyWith(
                          fontSize: 15,
                          color: scheme.onSurface,
                        ),
                      ),
                      Text(
                        '${widget.subject} • ${widget.topic}',
                        style: FluentType.caption.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.65),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (isRealExam &&
                    !_isFinished &&
                    !_isLoading &&
                    _questions.isNotEmpty) ...[
                  Builder(
                    builder: (chipCtx) {
                      // Under a minute the timer turns into the error colour:
                      // it is the one moment the clock outranks the accent.
                      final urgent = _remainingSeconds < 60;
                      final timerColor = urgent
                          ? _wrongColor(chipCtx)
                          : scheme.primary;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: FluentSpacing.s,
                          vertical: FluentSpacing.xs,
                        ),
                        decoration: BoxDecoration(
                          color: FluentLayer.subtle(timerColor, brightness),
                          borderRadius: FluentRadius.controlBorder,
                          border: Border.all(
                            color: timerColor.withValues(alpha: 0.4),
                            width: FluentStroke.width,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.timer_outlined,
                              size: 13,
                              color: timerColor,
                            ),
                            const SizedBox(width: FluentSpacing.xs),
                            Text(
                              '${(_remainingSeconds ~/ 60).toString().padLeft(2, '0')}:${(_remainingSeconds % 60).toString().padLeft(2, '0')}',
                              style: FluentType.caption.copyWith(
                                fontWeight: FontWeight.w600,
                                color: timerColor,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: FluentSpacing.xs + 2),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: FluentSpacing.m,
                        vertical: FluentSpacing.xs + 2,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: FluentRadius.controlBorder,
                      ),
                      elevation: 0,
                    ),
                    onPressed: () => _submitRealExam(),
                    child: const Text(
                      'জমা দিন',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: FluentSpacing.xs),
                ],
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Mode Toggle Pills (Shown before exam completes)
          if (!_isFinished && !_isLoading && _questions.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: FluentSpacing.l,
                vertical: FluentSpacing.xs,
              ),
              child: Container(
                padding: const EdgeInsets.all(FluentSpacing.xs),
                decoration: BoxDecoration(
                  color: scheme.onSurface.withValues(
                    alpha: isDark ? 0.06 : 0.04,
                  ),
                  borderRadius: FluentRadius.controlBorder,
                  border: Border.all(
                    color: FluentStroke.card(brightness),
                    width: FluentStroke.width,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _switchMode(QuizMode.practice),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: FluentSpacing.xs + 2,
                          ),
                          decoration: BoxDecoration(
                            color: _mode == QuizMode.practice
                                ? scheme.surface
                                : Colors.transparent,
                            borderRadius: FluentRadius.controlBorder,
                            border: _mode == QuizMode.practice
                                ? Border.all(
                                    color: FluentStroke.card(brightness),
                                    width: FluentStroke.width,
                                  )
                                : null,
                            boxShadow: _mode == QuizMode.practice
                                ? FluentElevation.card(brightness)
                                : null,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.menu_book_rounded,
                                size: 14,
                                color: _mode == QuizMode.practice
                                    ? scheme.primary
                                    : scheme.onSurface.withValues(alpha: 0.55),
                              ),
                              const SizedBox(width: FluentSpacing.xs + 2),
                              Flexible(
                                child: Text(
                                  'প্র্যাকটিস মোড',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: FluentType.caption.copyWith(
                                    fontWeight: _mode == QuizMode.practice
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: _mode == QuizMode.practice
                                        ? scheme.onSurface
                                        : scheme.onSurface.withValues(
                                            alpha: 0.55,
                                          ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _switchMode(QuizMode.realExam),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: FluentSpacing.xs + 2,
                          ),
                          decoration: BoxDecoration(
                            color: _mode == QuizMode.realExam
                                ? scheme.surface
                                : Colors.transparent,
                            borderRadius: FluentRadius.controlBorder,
                            border: _mode == QuizMode.realExam
                                ? Border.all(
                                    color: FluentStroke.card(brightness),
                                    width: FluentStroke.width,
                                  )
                                : null,
                            boxShadow: _mode == QuizMode.realExam
                                ? FluentElevation.card(brightness)
                                : null,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.timer_rounded,
                                size: 14,
                                color: _mode == QuizMode.realExam
                                    ? _wrongColor(context)
                                    : scheme.onSurface.withValues(alpha: 0.55),
                              ),
                              const SizedBox(width: FluentSpacing.xs + 2),
                              Flexible(
                                child: Text(
                                  'রিয়েল এক্সাম (-০.৫০)',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: FluentType.caption.copyWith(
                                    fontWeight: _mode == QuizMode.realExam
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: _mode == QuizMode.realExam
                                        ? scheme.onSurface
                                        : scheme.onSurface.withValues(
                                            alpha: 0.55,
                                          ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          Divider(
            height: FluentStroke.width,
            thickness: FluentStroke.width,
            color: FluentStroke.divider(brightness),
          ),

          Expanded(
            child: _isLoading
                ? _buildLoadingState()
                : (_isFinished ? _buildResultsState() : _buildQuizState()),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return AiProgressPipelineWidget(
      type: AiTaskType.drill,
      isCompact: false,
      customSubtitle: 'টপিক: ${widget.topic} • ${widget.subject}',
      liveTokens: _liveTokens,
    );
  }

  Widget _buildQuizState() {
    if (_loadError != null &&
        AiKeyMissingNotice.looksLikeKeyProblem(_loadError!)) {
      // A missing key is a thing to go and do, not a failure to report.
      return Padding(
        padding: const EdgeInsets.all(FluentSpacing.xl),
        child: AiKeyMissingNotice(
          message: _loadError!,
          onRetry: _loadQuestions,
        ),
      );
    }
    if (_loadError != null) {
      return Padding(
        padding: const EdgeInsets.all(FluentSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 36,
              color: _noticeColor(context),
            ),
            const SizedBox(height: FluentSpacing.m),
            Text(
              _loadError!,
              textAlign: TextAlign.center,
              style: FluentType.body.copyWith(
                color: Theme.of(context).colorScheme.onSurface
                    .withValues(alpha: 0.80),
              ),
            ),
            const SizedBox(height: FluentSpacing.l),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: FluentRadius.controlBorder,
                ),
              ),
              onPressed: _loadQuestions,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('আবার চেষ্টা'),
            ),
          ],
        ),
      );
    }
    if (_questions.isEmpty) {
      return const Center(child: Text('কোনো প্রশ্ন নেই।'));
    }
    if (_currentIndex >= _questions.length) {
      _currentIndex = _questions.length - 1;
    }
    if (_currentIndex < 0) {
      _currentIndex = 0;
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    final isDark = brightness == Brightness.dark;
    final question = _questions[_currentIndex];
    final progress = (_currentIndex + 1) / _questions.length;
    final isRealExam = _mode == QuizMode.realExam;
    final correctColor = _correctColor(context);
    final wrongColor = _wrongColor(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(FluentSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Question Navigator Strip in Real Exam Mode
          if (isRealExam) ...[
            SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _questions.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: FluentSpacing.xs + 2),
                itemBuilder: (ctx, i) {
                  final isCurrent = i == _currentIndex;
                  final isAnswered = _userAnswers.containsKey(i);

                  Color bgColor;
                  Color textColor;
                  Border? border;

                  if (isCurrent) {
                    bgColor = scheme.primary;
                    textColor = scheme.onPrimary;
                    border = Border.all(
                      color: scheme.primary,
                      width: FluentStroke.width,
                    );
                  } else if (isAnswered) {
                    bgColor = FluentLayer.subtle(correctColor, brightness);
                    textColor = correctColor;
                    border = Border.all(
                      color: correctColor.withValues(alpha: 0.5),
                      width: FluentStroke.width,
                    );
                  } else {
                    bgColor = scheme.onSurface.withValues(
                      alpha: isDark ? 0.06 : 0.04,
                    );
                    textColor = scheme.onSurface.withValues(alpha: 0.65);
                    border = Border.all(
                      color: FluentStroke.card(brightness),
                      width: FluentStroke.width,
                    );
                  }

                  return GestureDetector(
                    onTap: () => _jumpToQuestion(i),
                    child: Container(
                      width: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: FluentRadius.controlBorder,
                        border: border,
                      ),
                      child: Text(
                        '${i + 1}',
                        style: FluentType.caption.copyWith(
                          fontWeight: isCurrent || isAnswered
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: textColor,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: FluentSpacing.m),
          ],

          // Progress bar and counter
          Row(
            children: [
              Text(
                'প্রশ্ন ${_currentIndex + 1} / ${_questions.length}',
                style: FluentType.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: FluentSpacing.s),
              Expanded(
                child: Text(
                  isRealExam
                      ? 'উত্তরিত: ${_userAnswers.length}টি | বাকি: ${_questions.length - _userAnswers.length}টি'
                      : 'স্কোর: $_correctCount',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: FluentType.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isRealExam ? scheme.primary : correctColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: FluentSpacing.s),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: scheme.onSurface.withValues(
              alpha: isDark ? 0.10 : 0.08,
            ),
            valueColor: AlwaysStoppedAnimation(scheme.primary),
            minHeight: 4,
            borderRadius: FluentRadius.controlBorder,
          ),
          const SizedBox(height: FluentSpacing.l),

          // Question Card — the thing actually being read, so it gets the
          // largest type on the screen rather than a shouting weight.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(FluentSpacing.l),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: FluentRadius.cardBorder,
              border: Border.all(
                color: FluentStroke.card(brightness),
                width: FluentStroke.width,
              ),
              boxShadow: FluentElevation.card(brightness),
            ),
            child: Text(
              BengaliMathSanitizer.sanitize(question.questionText),
              style: FluentType.bodyStrong.copyWith(
                fontSize: 16,
                color: scheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: FluentSpacing.l),

          // Options
          ...List.generate(question.options.length, (index) {
            final optionText = BengaliMathSanitizer.sanitize(
              question.options[index],
            );
            final isCorrectOption = index == question.correctIndex;
            final isSelected = index == _selectedOptionIndex;

            // An answer option is a control, so it takes the 4px control
            // radius. The green/red/accent states are the signal the whole
            // screen exists for, so they keep their colour — only the surface
            // and the stroke become neutral Fluent.
            Color borderColor = FluentStroke.card(brightness);
            Color bgColor = scheme.surface;
            Color textColor = scheme.onSurface;
            IconData? icon;
            Color iconColor = Colors.transparent;
            bool emphasised = false;

            if (isRealExam) {
              if (isSelected) {
                borderColor = scheme.primary;
                bgColor = FluentLayer.subtle(scheme.primary, brightness);
                textColor = scheme.onSurface;
                icon = Icons.check_circle_rounded;
                iconColor = scheme.primary;
                emphasised = true;
              }
            } else if (_hasAnswered) {
              if (isCorrectOption) {
                borderColor = correctColor;
                bgColor = FluentLayer.subtle(correctColor, brightness);
                textColor = scheme.onSurface;
                icon = Icons.check_circle;
                iconColor = correctColor;
                emphasised = true;
              } else if (isSelected && !isCorrectOption) {
                borderColor = wrongColor;
                bgColor = FluentLayer.subtle(wrongColor, brightness);
                textColor = scheme.onSurface;
                icon = Icons.cancel;
                iconColor = wrongColor;
                emphasised = true;
              }
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: FluentSpacing.s),
              child: InkWell(
                borderRadius: FluentRadius.controlBorder,
                onTap: () => _onOptionSelected(index),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FluentSpacing.m,
                    vertical: FluentSpacing.m,
                  ),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: FluentRadius.controlBorder,
                    border: Border.all(
                      color: borderColor,
                      width: emphasised ? 1.5 : FluentStroke.width,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          optionText,
                          style: FluentType.body.copyWith(
                            fontWeight: emphasised
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: textColor,
                          ),
                        ),
                      ),
                      if (icon != null) ...[
                        const SizedBox(width: FluentSpacing.s),
                        Icon(icon, color: iconColor, size: 20),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }),

          // Real Exam Action Buttons
          if (isRealExam) ...[
            const SizedBox(height: FluentSpacing.l),
            Row(
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(
                      color: FluentStroke.card(brightness),
                      width: FluentStroke.width,
                    ),
                    foregroundColor: scheme.onSurface,
                    shape: RoundedRectangleBorder(
                      borderRadius: FluentRadius.controlBorder,
                    ),
                  ),
                  icon: const Icon(Icons.arrow_back, size: 16),
                  label: const Text('পূর্ববর্তী'),
                  onPressed: _currentIndex > 0
                      ? () => _jumpToQuestion(_currentIndex - 1)
                      : null,
                ),
                const SizedBox(width: FluentSpacing.xs + 2),
                if (_selectedOptionIndex != null) ...[
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: wrongColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: FluentRadius.controlBorder,
                      ),
                    ),
                    icon: const Icon(Icons.clear_rounded, size: 15),
                    label: Text('মুছুন', style: FluentType.caption),
                    onPressed: _clearSelectedOption,
                  ),
                ],
                const Spacer(),
                if (_currentIndex < _questions.length - 1) ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                      visualDensity: VisualDensity.compact,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: FluentRadius.controlBorder,
                      ),
                    ),
                    icon: const Icon(Icons.arrow_forward, size: 16),
                    label: const Text('পরবর্তী'),
                    onPressed: () => _jumpToQuestion(_currentIndex + 1),
                  ),
                ] else ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                      visualDensity: VisualDensity.compact,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: FluentRadius.controlBorder,
                      ),
                    ),
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: const Text('সাবমিট করুন'),
                    onPressed: () => _submitRealExam(),
                  ),
                ],
              ],
            ),
          ] else if (!_hasAnswered) ...[
            // A question the user simply does not know had no way past it:
            // practice mode only moved on once an option was picked, so the
            // choice was to guess or to abandon the drill.
            const SizedBox(height: FluentSpacing.s),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _skipQuestion,
                icon: const Icon(Icons.skip_next_rounded, size: 18),
                label: Text(
                  _currentIndex == _questions.length - 1
                      ? 'জানি না — ফলাফল দেখুন'
                      : 'জানি না — পরেরটা',
                  style: FluentType.caption,
                ),
                style: TextButton.styleFrom(
                  foregroundColor: _noticeColor(context),
                ),
              ),
            ),
          ] else if (_hasAnswered) ...[
            // Explanation Box (Practice Mode Only)
            const SizedBox(height: FluentSpacing.s),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(FluentSpacing.m),
              decoration: BoxDecoration(
                color: FluentLayer.subtle(
                  _noticeColor(context),
                  Theme.of(context).brightness,
                ),
                borderRadius: FluentRadius.cardBorder,
                border: Border.all(
                  color: _noticeColor(context).withValues(alpha: 0.35),
                  width: FluentStroke.width,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('💡 ', style: TextStyle(fontSize: 14)),
                      Flexible(
                        child: Text(
                          'ব্যাখ্যা (Explanation):',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: FluentType.caption.copyWith(
                            fontWeight: FontWeight.w600,
                            color: _noticeColor(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: FluentSpacing.xs),
                  Text(
                    BengaliMathSanitizer.sanitize(question.explanation),
                    style: FluentType.body.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: FluentSpacing.l),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: FluentRadius.controlBorder,
                  ),
                ),
                icon: const Icon(Icons.arrow_forward, size: 18),
                label: Text(
                  _currentIndex == _questions.length - 1
                      ? 'See Results & Summary'
                      : 'Next Question',
                  style: FluentType.bodyStrong,
                ),
                onPressed: _nextQuestion,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMiniStat({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    required bool isDark,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FluentSpacing.m,
        vertical: FluentSpacing.s,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: FluentRadius.controlBorder,
        border: Border.all(
          color: FluentStroke.card(Theme.of(context).brightness),
          width: FluentStroke.width,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: FluentSpacing.s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FluentType.caption.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
                Text(
                  value,
                  style: FluentType.bodyStrong.copyWith(
                    color: scheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _mistakesSaved = false;

  /// How many questions an AI drill asks for.
  ///
  /// It was fixed at five with no way to change it, which is a short practice
  /// and nothing like a model test. The generator handles larger sets well —
  /// measured at fifteen, comfortably inside its token budget — so the size
  /// is the user's to pick, and the pick is remembered for next time.
  int _drillSize = 5;

  static const _drillSizes = [5, 10, 20];

  Future<void> _loadDrillSize() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt('drill_question_count');
    if (saved != null && mounted) setState(() => _drillSize = saved);
  }

  Future<void> _setDrillSize(int size) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('drill_question_count', size);
    if (!mounted) return;
    _examTimer?.cancel();
    setState(() {
      _drillSize = size;
      _currentIndex = 0;
      _selectedOptionIndex = null;
      _hasAnswered = false;
      _correctCount = 0;
      _isFinished = false;
      _userAnswers.clear();
      _hasPersisted = false;
      _mistakesSaved = false;
    });
    await _loadQuestions();
  }

  /// Offered on the result screen, where the user has just seen how the last
  /// size felt, rather than before they know what they are choosing.
  Widget _buildSizeChooser(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FluentSpacing.l,
        FluentSpacing.s,
        FluentSpacing.l,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'আবার অনুশীলন করুন',
            style: FluentType.bodyStrong.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: FluentSpacing.s),
          Wrap(
            spacing: FluentSpacing.s,
            children: [
              for (final size in _drillSizes)
                OutlinedButton(
                  onPressed: () => _setDrillSize(size),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: FluentRadius.controlBorder,
                    ),
                    side: BorderSide(
                      color: FluentStroke.card(Theme.of(context).brightness),
                      width: FluentStroke.width,
                    ),
                  ),
                  child: Text('$size টি প্রশ্ন', style: FluentType.caption),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Puts what was answered wrong into the revision schedule.
  ///
  /// Due tomorrow, because a question just got wrong is the one most worth
  /// seeing again soonest.
  Future<void> _saveMistakesToReview() async {
    final db = ref.read(appDatabaseProvider);
    final wrong = <DrillQuestion>[];
    for (var i = 0; i < _questions.length; i++) {
      final answer = _userAnswers[i];
      // Skipped counts here even though it does not count against the score:
      // "I did not know this" is the clearest case for seeing it again.
      if (answer == null) continue;
      if (answer >= 0 && answer == _questions[i].correctIndex) continue;
      final q = _questions[i];
      wrong.add(
        DrillQuestion(
          id: 0,
          subject: (q.subject ?? '').isEmpty ? widget.subject : q.subject!,
          topic: widget.topic,
          questionText: q.questionText,
          optionsJson: jsonEncode(q.options),
          correctIndex: q.correctIndex,
          selectedIndex: answer,
          isCorrect: false,
          explanation: q.explanation,
          isMastered: false,
          attemptedAt: DateTime.now(),
        ),
      );
    }

    final added = await db.addMistakesToReview(wrong);

    // The weak-topics list and the healing drill built on it were fed by
    // spoken mistakes, the chat and hand-typed entries — never by what the
    // user actually gets wrong in a drill.
    final weak = weakTopicsFromDrill(
      tallyByTopic([
        for (var i = 0; i < _questions.length; i++)
          if (_userAnswers[i] != null)
            (
              subject: (_questions[i].subject ?? '').isEmpty
                  ? widget.subject
                  : _questions[i].subject!,
              topic: widget.topic,
              // Skipped counts as not knowing it, which is what the weak
              // list is for.
              wasWrong: _userAnswers[i] != _questions[i].correctIndex,
            ),
      ]),
    );
    for (final topic in weak) {
      await db.insertWeakTopic(
        WeakTopicsCompanion.insert(
          subject: topic.subject,
          topicName: topic.topic,
          proficiencyLevel: ProficiencyLevel.weak,
          notes: Value('ড্রিলে ${topic.asked}টির মধ্যে ${topic.wrong}টি ভুল'),
        ),
      );
    }
    // Cards are pushed from a queue built at startup, so a new card only
    // reaches the user once that queue is rebuilt.
    await ref
        .read(spacedRepetitionNotifierProvider.notifier)
        .refreshFlashcardSchedule(force: true);
    if (!mounted) return;
    setState(() => _mistakesSaved = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          [
            added == wrong.length
                ? '$added টি প্রশ্ন কাল থেকে রিভিশনে আসবে'
                : '$added টি যোগ হলো, বাকিগুলো আগেই ছিল',
            if (weak.isNotEmpty) '"${weak.first.topic}" দুর্বল তালিকায় গেল',
          ].join(' · '),
        ),
      ),
    );
  }

  Widget _buildResultsState() {
    final total = _questions.length;
    int correct = 0;
    int wrong = 0;
    int skipped = 0;
    for (int i = 0; i < total; i++) {
      final ans = _userAnswers[i];
      if (ans == null || ans < 0) {
        skipped++;
      } else if (ans == _questions[i].correctIndex) {
        correct++;
      } else {
        wrong++;
      }
    }

    final double netScore = (correct * 1.0) - (wrong * 0.50);
    final double maxScore = total * 1.0;
    final int percent = maxScore > 0
        ? ((netScore / maxScore) * 100).toInt()
        : 0;
    final isGood = _mode == QuizMode.realExam
        ? (percent >= 50)
        : (_correctCount >= (total * 0.6).ceil());
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final timeSpent = _totalExamSeconds - _remainingSeconds;

    final wrongQuestions = <QuizQuestion>[];
    for (int i = 0; i < _questions.length; i++) {
      if (_userAnswers[i] != _questions[i].correctIndex) {
        wrongQuestions.add(_questions[i]);
      }
    }

    return CelebrationConfetti(
      trigger: isGood,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: Column(
          children: [
            // The point of a drill is that what you got wrong comes back.
            // Until now that loop closed one question at a time, by hand,
            // from the notebook — so in practice it did not close.
            if (wrong + skipped > 0) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _mistakesSaved ? null : _saveMistakesToReview,
                    icon: Icon(
                      _mistakesSaved
                          ? Icons.check_circle_outline
                          : Icons.event_repeat_rounded,
                      size: 18,
                    ),
                    label: Text(
                      _mistakesSaved
                          ? 'রিভিশনে যোগ হয়েছে'
                          : 'যেগুলো পারিনি (${wrong + skipped} টি) রিভিশনে যোগ করুন',
                    ),
                  ),
                ),
              ),
            ],
            if (widget.customQuestions == null) _buildSizeChooser(isDark),
            if (_mode == QuizMode.realExam) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: FluentSpacing.m,
                  vertical: FluentSpacing.xs + 2,
                ),
                decoration: BoxDecoration(
                  color: FluentLayer.subtle(
                    scheme.primary,
                    Theme.of(context).brightness,
                  ),
                  borderRadius: FluentRadius.controlBorder,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.timer_rounded, size: 16, color: scheme.primary),
                    const SizedBox(width: FluentSpacing.s),
                    Flexible(
                      child: Text(
                        'রিয়েল এক্সাম ফলাফল (BCS ফরম্যাট: ভুল উত্তরে -০.৫০)',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: FluentType.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: FluentSpacing.m),
              // Score Banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(FluentSpacing.l),
                decoration: BoxDecoration(
                  color: isGood ? _correctColor(context) : _wrongColor(context),
                  borderRadius: FluentRadius.cardBorder,
                  boxShadow: FluentElevation.card(Theme.of(context).brightness),
                ),
                child: Column(
                  children: [
                    Text(
                      isGood
                          ? '🎉 চমৎকার পারফর্মেন্স!'
                          : '⚠️ আরেকটু মনোযোগ প্রয়োজন',
                      textAlign: TextAlign.center,
                      style: FluentType.subtitle.copyWith(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: FluentSpacing.s),
                    Text(
                      '${netScore.toStringAsFixed(2)} / ${maxScore.toStringAsFixed(0)}',
                      style: FluentType.title.copyWith(
                        color: Colors.white,
                        fontSize: 32,
                      ),
                    ),
                    Text(
                      'অর্জিত নেট স্কোর (${percent.clamp(0, 100)}%)',
                      style: FluentType.caption.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(height: FluentSpacing.m),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: FluentSpacing.m,
                        vertical: FluentSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.25),
                        borderRadius: FluentRadius.controlBorder,
                      ),
                      child: Text(
                        percent >= 70
                            ? '🏆 প্রিলি কাট-মার্ক উত্তীর্ণ রেঞ্জ'
                            : (percent >= 45
                                  ? '👍 সন্তোষজনক, নেগেটিভ মার্কিং কমানো প্রয়োজন'
                                  : '📚 দুর্বল টপিকগুলোতে পুনরায় রিভিশন দিন'),
                        textAlign: TextAlign.center,
                        style: FluentType.caption.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: FluentSpacing.m),
              // 4 Stats Grid
              Row(
                children: [
                  Expanded(
                    child: _buildMiniStat(
                      icon: Icons.check_circle_rounded,
                      color: _correctColor(context),
                      label: 'সঠিক',
                      value: '$correct (+$correct.00)',
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: FluentSpacing.s),
                  Expanded(
                    child: _buildMiniStat(
                      icon: Icons.cancel_rounded,
                      color: _wrongColor(context),
                      label: 'ভুল',
                      value: '$wrong (-${(wrong * 0.50).toStringAsFixed(2)})',
                      isDark: isDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: FluentSpacing.s),
              Row(
                children: [
                  Expanded(
                    child: _buildMiniStat(
                      icon: Icons.skip_next_rounded,
                      color: _skippedColor(context),
                      label: 'স্কিপড',
                      value: '$skipped (0.00)',
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: FluentSpacing.s),
                  Expanded(
                    child: _buildMiniStat(
                      icon: Icons.timer_outlined,
                      color: scheme.primary,
                      label: 'ব্যয়িত সময়',
                      value: '${timeSpent ~/ 60}মি ${timeSpent % 60}সে',
                      isDark: isDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: FluentSpacing.l),
            ] else ...[
              // Result Header Circle (Practice Mode)
              Container(
                padding: const EdgeInsets.all(FluentSpacing.l),
                decoration: BoxDecoration(
                  color: FluentLayer.subtle(
                    isGood ? _correctColor(context) : _noticeColor(context),
                    Theme.of(context).brightness,
                  ),
                  borderRadius: FluentRadius.controlBorder,
                ),
                child: Icon(
                  isGood ? Icons.military_tech : Icons.refresh,
                  color: isGood
                      ? _correctColor(context)
                      : _noticeColor(context),
                  size: 48,
                ),
              ),
              const SizedBox(height: FluentSpacing.m),
              Text(
                isGood ? 'দারুণ প্রস্তুতি!' : 'আরেকটু রিভিশন প্রয়োজন',
                textAlign: TextAlign.center,
                style: FluentType.subtitle.copyWith(
                  fontSize: 18,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: FluentSpacing.s),
              Text(
                'আপনি $totalটির মধ্যে $_correctCountটি প্রশ্নের সঠিক উত্তর দিয়েছেন (${total > 0 ? ((_correctCount / total) * 100).toInt() : 0}%)',
                textAlign: TextAlign.center,
                style: FluentType.body.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
              const SizedBox(height: FluentSpacing.l),
            ],

            // Mistake Bank Auto-Save & Re-drill Banner
            if (wrongQuestions.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(FluentSpacing.m),
                decoration: BoxDecoration(
                  color: FluentLayer.subtle(
                    _wrongColor(context),
                    Theme.of(context).brightness,
                  ),
                  borderRadius: FluentRadius.cardBorder,
                  border: Border.all(
                    color: _wrongColor(context).withValues(alpha: 0.35),
                    width: FluentStroke.width,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: _wrongColor(context),
                          size: 18,
                        ),
                        const SizedBox(width: FluentSpacing.s),
                        Expanded(
                          child: Text(
                            '${wrongQuestions.length}টি ভুল উত্তর Mistake Bank-এ সেভ হয়েছে!',
                            style: FluentType.bodyStrong.copyWith(
                              color: _wrongColor(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: FluentSpacing.xs),
                    Text(
                      'পরবর্তীতে রিভিশন দিতে পারবেন অথবা এখনই পুনরায় চেষ্টা করতে পারেন।',
                      style: FluentType.caption.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                    const SizedBox(height: FluentSpacing.s),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: scheme.primary,
                          foregroundColor: scheme.onPrimary,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            vertical: FluentSpacing.s,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: FluentRadius.controlBorder,
                          ),
                        ),
                        icon: const Icon(Icons.replay, size: 15),
                        label: Text(
                          'ভুল ${wrongQuestions.length}টি প্রশ্ন পুনরায় দিন (Re-drill)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: FluentType.caption.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onPressed: () {
                          setState(() {
                            _questions = List.from(wrongQuestions);
                            _currentIndex = 0;
                            _selectedOptionIndex = null;
                            _hasAnswered = false;
                            _correctCount = 0;
                            _isFinished = false;
                            _userAnswers.clear();
                            _hasPersisted = false;
                          });
                          if (_mode == QuizMode.realExam) {
                            _startExamTimer();
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: FluentSpacing.l),
            ],

            // Detailed Question-by-Question Review with Copy and Voice/AI Batch Fix
            Row(
              children: [
                Expanded(
                  child: Text(
                    '📋 প্রশ্নভিত্তিক পর্যালোচনা (Detailed Review)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FluentType.bodyStrong.copyWith(
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: FluentSpacing.m,
                      vertical: FluentSpacing.xs,
                    ),
                    foregroundColor: scheme.primary,
                    side: BorderSide(
                      color: FluentStroke.card(Theme.of(context).brightness),
                      width: FluentStroke.width,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: FluentRadius.controlBorder,
                    ),
                  ),
                  icon: const Icon(Icons.copy_rounded, size: 14),
                  label: Text(
                    'কপি করুন',
                    style: FluentType.caption.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: _copyFullReviewToClipboard,
                ),
                const SizedBox(width: FluentSpacing.s),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: FluentSpacing.m,
                      vertical: FluentSpacing.xs,
                    ),
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: FluentRadius.controlBorder,
                    ),
                  ),
                  icon: const Icon(Icons.mic_rounded, size: 14),
                  label: Text(
                    'AI ফিক্স / 🎙️ ভয়েস',
                    style: FluentType.caption.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: _showPasteExternalAiFixSheet,
                ),
              ],
            ),
            const SizedBox(height: FluentSpacing.s),

            ...List.generate(_questions.length, (i) {
              final q = _questions[i];
              final selected = _userAnswers[i] ?? -1;
              final isCorrect = q.isCorrectChoice(selected);
              final isSkipped = selected < 0;

              String statusLabel;
              Color statusColor;
              IconData statusIcon;

              if (_mode == QuizMode.realExam) {
                if (isCorrect) {
                  statusLabel = 'প্রশ্ন ${i + 1} · সঠিক (+১.০০)';
                  statusColor = _correctColor(context);
                  statusIcon = Icons.check_circle;
                } else if (isSkipped) {
                  statusLabel = 'প্রশ্ন ${i + 1} · স্কিপড (০.০০)';
                  statusColor = _skippedColor(context);
                  statusIcon = Icons.remove_circle_outline;
                } else {
                  statusLabel = 'প্রশ্ন ${i + 1} · ভুল (-০.৫০)';
                  statusColor = _wrongColor(context);
                  statusIcon = Icons.cancel;
                }
              } else {
                if (isCorrect) {
                  statusLabel = 'প্রশ্ন ${i + 1}: সঠিক উত্তর';
                  statusColor = _correctColor(context);
                  statusIcon = Icons.check_circle;
                } else if (isSkipped) {
                  statusLabel = 'প্রশ্ন ${i + 1}: উত্তর দেননি (স্কিপড)';
                  statusColor = _skippedColor(context);
                  statusIcon = Icons.remove_circle_outline;
                } else {
                  statusLabel = 'প্রশ্ন ${i + 1}: ভুল উত্তর';
                  statusColor = _wrongColor(context);
                  statusIcon = Icons.cancel;
                }
              }

              return Container(
                margin: const EdgeInsets.only(bottom: FluentSpacing.s),
                padding: const EdgeInsets.all(FluentSpacing.m),
                decoration: BoxDecoration(
                  color: isSkipped
                      ? Theme.of(context).colorScheme.surface
                      : FluentLayer.subtle(
                          statusColor,
                          Theme.of(context).brightness,
                        ),
                  borderRadius: FluentRadius.cardBorder,
                  border: Border.all(
                    color: isSkipped
                        ? FluentStroke.card(Theme.of(context).brightness)
                        : statusColor.withValues(alpha: 0.35),
                    width: FluentStroke.width,
                  ),
                  boxShadow: FluentElevation.card(Theme.of(context).brightness),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(statusIcon, size: 16, color: statusColor),
                        const SizedBox(width: FluentSpacing.s),
                        Flexible(
                          child: Text(
                            statusLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FluentType.caption.copyWith(
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.copy_rounded, size: 15),
                          tooltip: 'এই প্রশ্ন ও উত্তর কপি করুন',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          onPressed: () => _copySingleQuestionToClipboard(i),
                        ),
                      ],
                    ),
                    const SizedBox(height: FluentSpacing.s),
                    Text(
                      q.questionText,
                      style: FluentType.bodyStrong.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: FluentSpacing.s),

                    if (!isCorrect) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: FluentSpacing.s,
                          vertical: FluentSpacing.xs,
                        ),
                        decoration: BoxDecoration(
                          color: FluentLayer.subtle(
                            isSkipped
                                ? _skippedColor(context)
                                : _wrongColor(context),
                            Theme.of(context).brightness,
                          ),
                          borderRadius: FluentRadius.controlBorder,
                        ),
                        child: Text(
                          isSkipped
                              ? '⏭️ কোনো উত্তর দেননি (স্কিপ করা হয়েছে)'
                              : '❌ আপনার উত্তর: ${(selected >= 0 && selected < q.options.length) ? q.options[selected] : "অজানা"}',
                          style: FluentType.caption.copyWith(
                            color: isSkipped
                                ? Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.65)
                                : _wrongColor(context),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: FluentSpacing.xs),
                    ],

                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: FluentSpacing.s,
                        vertical: FluentSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: FluentLayer.subtle(
                          _correctColor(context),
                          Theme.of(context).brightness,
                        ),
                        borderRadius: FluentRadius.controlBorder,
                      ),
                      child: Text(
                        '✅ সঠিক উত্তর: ${(q.correctIndex >= 0 && q.correctIndex < q.options.length) ? q.options[q.correctIndex] : "অজানা"}',
                        style: FluentType.caption.copyWith(
                          color: _correctColor(context),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),

                    if (q.explanation.isNotEmpty) ...[
                      const SizedBox(height: FluentSpacing.s),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('💡 ', style: TextStyle(fontSize: 12)),
                          Expanded(
                            child: MarkdownBody(
                              data: BengaliMathSanitizer.sanitize(
                                q.explanation,
                              ),
                              styleSheet:
                                  MarkdownStyleSheet.fromTheme(
                                    Theme.of(context),
                                  ).copyWith(
                                    p: FluentType.caption.copyWith(
                                      color: _noticeColor(context),
                                    ),
                                    strong: FluentType.caption.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: _noticeColor(context),
                                    ),
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            }),

            const SizedBox(height: FluentSpacing.l),

            // Add to Weak Topics if score is low
            if (_correctCount < total) ...[
              Container(
                padding: const EdgeInsets.all(FluentSpacing.m),
                decoration: BoxDecoration(
                  color: FluentLayer.subtle(
                    scheme.primary,
                    Theme.of(context).brightness,
                  ),
                  borderRadius: FluentRadius.cardBorder,
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: 0.35),
                    width: FluentStroke.width,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.radar, color: scheme.primary, size: 22),
                    const SizedBox(width: FluentSpacing.m),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'দুর্বল টপিক রাডারে যুক্ত করবেন?',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: FluentType.bodyStrong.copyWith(
                              color: scheme.onSurface,
                            ),
                          ),
                          Text(
                            'টপিক: ${widget.topic}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FluentType.caption.copyWith(
                              color: scheme.onSurface.withValues(alpha: 0.65),
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        await ref
                            .read(topicsNotifierProvider.notifier)
                            .addTopic(
                              subject: widget.subject,
                              topicName: widget.topic,
                              proficiencyLevel: ProficiencyLevel.weak,
                              notes:
                                  'Added from drill test ($_correctCount/$total)',
                            );
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: scheme.primary,
                              content: Text(
                                '"${widget.topic}" দুর্বল টপিক রাডারে যুক্ত হয়েছে!',
                              ),
                            ),
                          );
                        }
                      },
                      child: const Text('Add Topic'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: FluentSpacing.l),
            ],

            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: FluentRadius.controlBorder,
                  ),
                ),
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Finish Drill & Close',
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
