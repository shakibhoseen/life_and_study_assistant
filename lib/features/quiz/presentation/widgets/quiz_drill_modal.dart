import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/tables/weak_topics_table.dart';
import '../../../../core/services/ai/models/quiz_question.dart';
import '../../../../core/services/ai/quiz_generator_service.dart';
import '../../../../core/utils/bengali_math_sanitizer.dart';
import '../../../topics/presentation/providers/topics_provider.dart';
import '../providers/drill_history_provider.dart';
import 'quiz_batch_correction_sheet.dart';

enum QuizMode {
  practice,
  realExam,
}

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
    _loadQuestions();
  }

  @override
  void dispose() {
    _examTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadQuestions() async {
    if (widget.customQuestions != null && widget.customQuestions!.isNotEmpty) {
      setState(() {
        _questions = widget.customQuestions!;
        _isLoading = false;
      });
      if (_mode == QuizMode.realExam) {
        _startExamTimer();
      }
      return;
    }

    setState(() => _isLoading = true);
    final questions = await QuizGeneratorService.instance.generateQuiz(
      topic: widget.topic,
      subject: widget.subject,
      count: 5,
    );
    if (mounted) {
      setState(() {
        _questions = questions;
        _isLoading = false;
      });
      if (_mode == QuizMode.realExam) {
        _startExamTimer();
      }
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
      _hasAnswered = _mode == QuizMode.practice && _userAnswers.containsKey(index);
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
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 24),
                SizedBox(width: 8),
                Text('সাবমিট নিশ্চিতকরণ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            content: Text(
              'আপনার এখনো $unansweredটি প্রশ্নের উত্তর বাকি রয়েছে।\n\n'
              'নেগেটিভ মার্কিং (-০.৫০) এড়াতে স্কিপ করতে পারেন অথবা উত্তর দিয়ে সাবমিট করতে পারেন।\n\n'
              'আপনি কি নিশ্চিত এখনই পরীক্ষা জমা দিতে চান?',
              style: const TextStyle(fontSize: 13),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dCtx, false),
                child: const Text('না, ফিরে যাই'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  foregroundColor: Colors.white,
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
    setState(() {
      _isFinished = true;
    });
    await _persistDrillResults();
    widget.onCompleted?.call();
  }

  void _nextQuestion() {
    if (_currentIndex < _questions.length - 1) {
      setState(() {
        _currentIndex++;
        _selectedOptionIndex = _userAnswers[_currentIndex];
        _hasAnswered = _mode == QuizMode.practice && _userAnswers.containsKey(_currentIndex);
      });
    } else {
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
      final isCorrect = selected == q.correctIndex;

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
      buffer.writeln('প্রাপ্ত নেট স্কোর: ${net.toStringAsFixed(2)} / $total.00');
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
      final isCorrect = selected == q.correctIndex;
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
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'সম্পূর্ণ কুইজ ও উত্তরপত্র ক্লিপবোর্ডে কপি হয়েছে! অন্য AI-তে পেস্ট করতে পারেন।',
                style: TextStyle(fontSize: 12.5),
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
      });
    }
  }

  void _copySingleQuestionToClipboard(int index) {
    if (index < 0 || index >= _questions.length) return;
    final q = _questions[index];
    final selected = _userAnswers[index] ?? -1;
    final isCorrect = selected == q.correctIndex;
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isRealExam = _mode == QuizMode.realExam;

    return Container(
      height: MediaQuery.of(context).size.height * 0.90,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: isRealExam
                        ? Colors.red.withValues(alpha: 0.12)
                        : Colors.indigo.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isRealExam ? Icons.timer_rounded : Icons.psychology,
                    color: isRealExam ? Colors.red.shade600 : Colors.indigo,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isRealExam
                            ? 'রিয়েল এক্সাম (BCS স্ট্যান্ডার্ড)'
                            : 'LiveMCQ ড্রিল ও প্র্যাকটিস',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.indigo.shade900,
                        ),
                      ),
                      Text(
                        '${widget.subject} • ${widget.topic}',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.grey.shade400 : Colors.black54,
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
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _remainingSeconds < 60
                          ? Colors.red.withValues(alpha: 0.15)
                          : const Color(0xFF6366F1).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _remainingSeconds < 60
                            ? Colors.red.shade400
                            : const Color(0xFF6366F1).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 13,
                          color: _remainingSeconds < 60
                              ? Colors.red
                              : const Color(0xFF6366F1),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${(_remainingSeconds ~/ 60).toString().padLeft(2, '0')}:${(_remainingSeconds % 60).toString().padLeft(2, '0')}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _remainingSeconds < 60
                              ? Colors.red
                              : const Color(0xFF6366F1),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    onPressed: () => _submitRealExam(),
                    child: const Text(
                      'জমা দিন',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E293B)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _switchMode(QuizMode.practice),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: _mode == QuizMode.practice
                                ? (isDark
                                      ? const Color(0xFF334155)
                                      : Colors.white)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: _mode == QuizMode.practice
                                ? [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.06),
                                      blurRadius: 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.menu_book_rounded,
                                size: 14,
                                color: _mode == QuizMode.practice
                                    ? const Color(0xFF6366F1)
                                    : Colors.grey,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'প্র্যাকটিস মোড',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: _mode == QuizMode.practice
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: _mode == QuizMode.practice
                                      ? (isDark
                                            ? Colors.white
                                            : const Color(0xFF1E293B))
                                      : Colors.grey,
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
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: _mode == QuizMode.realExam
                                ? (isDark
                                      ? const Color(0xFF334155)
                                      : Colors.white)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: _mode == QuizMode.realExam
                                ? [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.06),
                                      blurRadius: 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.timer_rounded,
                                size: 14,
                                color: _mode == QuizMode.realExam
                                    ? Colors.red.shade600
                                    : Colors.grey,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'রিয়েল এক্সাম (-০.৫০)',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: _mode == QuizMode.realExam
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: _mode == QuizMode.realExam
                                      ? (isDark
                                            ? Colors.white
                                            : const Color(0xFF1E293B))
                                      : Colors.grey,
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

          const Divider(height: 1),

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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Colors.indigo),
          const SizedBox(height: 16),
          Text(
            'Crafting high-yield MCQs for you...',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Topic: ${widget.topic}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildQuizState() {
    if (_questions.isEmpty) {
      return const Center(child: Text('No questions available.'));
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final question = _questions[_currentIndex];
    final progress = (_currentIndex + 1) / _questions.length;
    final isRealExam = _mode == QuizMode.realExam;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
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
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (ctx, i) {
                  final isCurrent = i == _currentIndex;
                  final isAnswered = _userAnswers.containsKey(i);

                  Color bgColor;
                  Color textColor;
                  Border? border;

                  if (isCurrent) {
                    bgColor = const Color(0xFF6366F1);
                    textColor = Colors.white;
                    border = Border.all(color: Colors.white, width: 1.5);
                  } else if (isAnswered) {
                    bgColor = const Color(
                      0xFF10B981,
                    ).withValues(alpha: isDark ? 0.25 : 0.15);
                    textColor = isDark
                        ? const Color(0xFF6EE7B7)
                        : const Color(0xFF047857);
                    border = Border.all(
                      color: const Color(
                        0xFF10B981,
                      ).withValues(alpha: 0.5),
                    );
                  } else {
                    bgColor = isDark
                        ? const Color(0xFF1E293B)
                        : const Color(0xFFF1F5F9);
                    textColor = isDark
                        ? Colors.grey.shade400
                        : Colors.grey.shade600;
                  }

                  return GestureDetector(
                    onTap: () => _jumpToQuestion(i),
                    child: Container(
                      width: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(8),
                        border: border,
                      ),
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: isCurrent || isAnswered
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: textColor,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
          ],

          // Progress bar and counter
          Row(
            children: [
              Text(
                'প্রশ্ন ${_currentIndex + 1} / ${_questions.length}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF6366F1),
                ),
              ),
              const Spacer(),
              Text(
                isRealExam
                    ? 'উত্তরিত: ${_userAnswers.length}টি | বাকি: ${_questions.length - _userAnswers.length}টি'
                    : 'স্কোর: $_correctCount',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isRealExam
                      ? (isDark ? Colors.indigo.shade200 : Colors.indigo.shade800)
                      : Colors.green.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: isDark
                ? const Color(0xFF1E293B)
                : Colors.indigo.shade50,
            valueColor: AlwaysStoppedAnimation(
              isRealExam ? const Color(0xFF6366F1) : Colors.indigo,
            ),
            minHeight: 5,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 16),

          // Question Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF1E293B)
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark
                    ? Colors.white12
                    : const Color(0xFFE2E8F0),
              ),
            ),
            child: Text(
              BengaliMathSanitizer.sanitize(question.questionText),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                height: 1.45,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Options
          ...List.generate(question.options.length, (index) {
            final optionText = BengaliMathSanitizer.sanitize(
              question.options[index],
            );
            final isCorrectOption = index == question.correctIndex;
            final isSelected = index == _selectedOptionIndex;

            Color borderColor = isDark
                ? const Color(0xFF334155)
                : const Color(0xFFE2E8F0);
            Color bgColor = isDark
                ? const Color(0xFF1E293B)
                : Colors.white;
            Color textColor = isDark
                ? const Color(0xFFF1F5F9)
                : const Color(0xFF1E293B);
            IconData? icon;
            Color iconColor = Colors.transparent;

            if (isRealExam) {
              if (isSelected) {
                borderColor = const Color(0xFF6366F1);
                bgColor = isDark
                    ? const Color(0xFF312E81)
                    : const Color(0xFFEEF2FF);
                textColor = isDark
                    ? Colors.white
                    : const Color(0xFF4338CA);
                icon = Icons.check_circle_rounded;
                iconColor = const Color(0xFF6366F1);
              }
            } else if (_hasAnswered) {
              if (isCorrectOption) {
                borderColor = Colors.green.shade600;
                bgColor = isDark
                    ? Colors.green.shade900.withValues(alpha: 0.3)
                    : Colors.green.shade50;
                textColor = isDark
                    ? Colors.green.shade200
                    : Colors.green.shade900;
                icon = Icons.check_circle;
                iconColor = Colors.green.shade700;
              } else if (isSelected && !isCorrectOption) {
                borderColor = Colors.red.shade400;
                bgColor = isDark
                    ? Colors.red.shade900.withValues(alpha: 0.3)
                    : Colors.red.shade50;
                textColor = isDark
                    ? Colors.red.shade200
                    : Colors.red.shade900;
                icon = Icons.cancel;
                iconColor = Colors.red.shade700;
              }
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _onOptionSelected(index),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: borderColor,
                      width: isSelected || (!isRealExam && isCorrectOption)
                          ? 1.5
                          : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          optionText,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: textColor,
                          ),
                        ),
                      ),
                      if (icon != null) ...[
                        const SizedBox(width: 8),
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
            const SizedBox(height: 16),
            Row(
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.arrow_back, size: 16),
                  label: const Text('পূর্ববর্তী'),
                  onPressed: _currentIndex > 0
                      ? () => _jumpToQuestion(_currentIndex - 1)
                      : null,
                ),
                const SizedBox(width: 6),
                if (_selectedOptionIndex != null) ...[
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: Colors.red.shade600,
                    ),
                    icon: const Icon(Icons.clear_rounded, size: 15),
                    label: const Text(
                      'মুছুন',
                      style: TextStyle(fontSize: 11),
                    ),
                    onPressed: _clearSelectedOption,
                  ),
                ],
                const Spacer(),
                if (_currentIndex < _questions.length - 1) ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.arrow_forward, size: 16),
                    label: const Text('পরবর্তী'),
                    onPressed: () => _jumpToQuestion(_currentIndex + 1),
                  ),
                ] else ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: const Text('সাবমিট করুন'),
                    onPressed: () => _submitRealExam(),
                  ),
                ],
              ],
            ),
          ] else if (_hasAnswered) ...[
            // Explanation Box (Practice Mode Only)
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.amber.shade900.withValues(alpha: 0.25)
                    : Colors.amber.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark
                      ? Colors.amber.shade700.withValues(alpha: 0.5)
                      : Colors.amber.shade200,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('💡 ', style: TextStyle(fontSize: 14)),
                      Text(
                        'ব্যাখ্যা (Explanation):',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: isDark
                              ? Colors.amber.shade200
                              : Colors.amber.shade900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    BengaliMathSanitizer.sanitize(question.explanation),
                    style: TextStyle(
                      fontSize: 12.5,
                      color: isDark
                          ? Colors.amber.shade100
                          : Colors.brown.shade800,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3A8A),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.arrow_forward, size: 18),
                label: Text(
                  _currentIndex == _questions.length - 1
                      ? 'See Results & Summary'
                      : 'Next Question',
                  style: const TextStyle(fontWeight: FontWeight.bold),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
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
    final int percent = maxScore > 0 ? ((netScore / maxScore) * 100).toInt() : 0;
    final isGood = _mode == QuizMode.realExam
        ? (percent >= 50)
        : (_correctCount >= (total * 0.6).ceil());
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final timeSpent = _totalExamSeconds - _remainingSeconds;

    final wrongQuestions = <QuizQuestion>[];
    for (int i = 0; i < _questions.length; i++) {
      if (_userAnswers[i] != _questions[i].correctIndex) {
        wrongQuestions.add(_questions[i]);
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      child: Column(
        children: [
          if (_mode == QuizMode.realExam) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.timer_rounded,
                    size: 16,
                    color: Color(0xFF6366F1),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'রিয়েল এক্সাম ফলাফল (BCS ফরম্যাট: ভুল উত্তরে -০.৫০)',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? const Color(0xFFA5B4FC)
                          : const Color(0xFF4338CA),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Score Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isGood
                      ? [const Color(0xFF065F46), const Color(0xFF047857)]
                      : [const Color(0xFF991B1B), const Color(0xFFB91C1C)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: (isGood ? Colors.green : Colors.red)
                        .withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Text(
                    isGood
                        ? '🎉 চমৎকার পারফর্মেন্স!'
                        : '⚠️ আরেকটু মনোযোগ প্রয়োজন',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${netScore.toStringAsFixed(2)} / ${maxScore.toStringAsFixed(0)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                    ),
                  ),
                  Text(
                    'অর্জিত নেট স্কোর (${percent.clamp(0, 100)}%)',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      percent >= 70
                          ? '🏆 প্রিলি কাট-মার্ক উত্তীর্ণ রেঞ্জ'
                          : (percent >= 45
                                ? '👍 সন্তোষজনক, নেগেটিভ মার্কিং কমানো প্রয়োজন'
                                : '📚 দুর্বল টপিকগুলোতে পুনরায় রিভিশন দিন'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // 4 Stats Grid
            Row(
              children: [
                Expanded(
                  child: _buildMiniStat(
                    icon: Icons.check_circle_rounded,
                    color: Colors.green,
                    label: 'সঠিক',
                    value: '$correct (+$correct.00)',
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMiniStat(
                    icon: Icons.cancel_rounded,
                    color: Colors.red,
                    label: 'ভুল',
                    value: '$wrong (-${(wrong * 0.50).toStringAsFixed(2)})',
                    isDark: isDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildMiniStat(
                    icon: Icons.skip_next_rounded,
                    color: Colors.orange,
                    label: 'স্কিপড',
                    value: '$skipped (0.00)',
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMiniStat(
                    icon: Icons.timer_outlined,
                    color: Colors.indigo,
                    label: 'ব্যয়িত সময়',
                    value: '${timeSpent ~/ 60}মি ${timeSpent % 60}সে',
                    isDark: isDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ] else ...[
            // Result Header Circle (Practice Mode)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isGood
                    ? (isDark
                          ? Colors.green.withValues(alpha: 0.2)
                          : Colors.green.shade50)
                    : (isDark
                          ? Colors.amber.withValues(alpha: 0.2)
                          : Colors.amber.shade50),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isGood ? Icons.military_tech : Icons.refresh,
                color: isGood ? Colors.green.shade700 : Colors.amber.shade800,
                size: 48,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              isGood ? 'দারুণ প্রস্তুতি!' : 'আরেকটু রিভিশন প্রয়োজন',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'আপনি $totalটির মধ্যে $_correctCountটি প্রশ্নের সঠিক উত্তর দিয়েছেন (${total > 0 ? ((_correctCount / total) * 100).toInt() : 0}%)',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Mistake Bank Auto-Save & Re-drill Banner
          if (wrongQuestions.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.red.withValues(alpha: 0.18)
                    : const Color(0xFFFFF1F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark
                      ? Colors.red.withValues(alpha: 0.4)
                      : const Color(0xFFFECDD3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Color(0xFFBE123C),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${wrongQuestions.length}টি ভুল উত্তর Mistake Bank-এ সেভ হয়েছে!',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? Colors.red.shade200
                                : const Color(0xFF9F1239),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'পরবর্তীতে রিভিশন দিতে পারবেন অথবা এখনই পুনরায় চেষ্টা করতে পারেন।',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark
                          ? Colors.red.shade100
                          : const Color(0xFF881337),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFBE123C),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      icon: const Icon(Icons.replay, size: 15),
                      label: Text(
                        'ভুল ${wrongQuestions.length}টি প্রশ্ন পুনরায় দিন (Re-drill)',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
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
            const SizedBox(height: 16),
          ],

          // Detailed Question-by-Question Review with Copy and Voice/AI Batch Fix
          Row(
            children: [
              Expanded(
                child: Text(
                  '📋 প্রশ্নভিত্তিক পর্যালোচনা (Detailed Review)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isDark
                        ? Colors.indigo.shade200
                        : Colors.indigo.shade900,
                  ),
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  foregroundColor: isDark
                      ? const Color(0xFFA5B4FC)
                      : const Color(0xFF4F46E5),
                  side: BorderSide(
                    color: isDark
                        ? const Color(0xFF6366F1)
                        : const Color(0xFF4F46E5),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.copy_rounded, size: 14),
                label: const Text(
                  'কপি করুন',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                ),
                onPressed: _copyFullReviewToClipboard,
              ),
              const SizedBox(width: 6),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.mic_rounded, size: 14),
                label: const Text(
                  'AI ফিক্স / 🎙️ ভয়েস',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                ),
                onPressed: _showPasteExternalAiFixSheet,
              ),
            ],
          ),
          const SizedBox(height: 8),

          ...List.generate(_questions.length, (i) {
            final q = _questions[i];
            final selected = _userAnswers[i] ?? -1;
            final isCorrect = selected == q.correctIndex;
            final isSkipped = selected < 0;

            String statusLabel;
            Color statusColor;
            IconData statusIcon;

            if (_mode == QuizMode.realExam) {
              if (isCorrect) {
                statusLabel = 'প্রশ্ন ${i + 1} · সঠিক (+১.০০)';
                statusColor = const Color(0xFF15803D);
                statusIcon = Icons.check_circle;
              } else if (isSkipped) {
                statusLabel = 'প্রশ্ন ${i + 1} · স্কিপড (০.০০)';
                statusColor = Colors.grey.shade600;
                statusIcon = Icons.remove_circle_outline;
              } else {
                statusLabel = 'প্রশ্ন ${i + 1} · ভুল (-০.৫০)';
                statusColor = const Color(0xFFC2410C);
                statusIcon = Icons.cancel;
              }
            } else {
              statusLabel = 'প্রশ্ন ${i + 1}: ${isCorrect ? "সঠিক উত্তর" : "ভুল উত্তর"}';
              statusColor = isCorrect
                  ? const Color(0xFF15803D)
                  : const Color(0xFFC2410C);
              statusIcon = isCorrect ? Icons.check_circle : Icons.cancel;
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isCorrect
                    ? (isDark
                          ? Colors.green.withValues(alpha: 0.15)
                          : const Color(0xFFF0FDF4))
                    : (isSkipped
                          ? (isDark
                                ? Colors.grey.withValues(alpha: 0.15)
                                : const Color(0xFFF8FAFC))
                          : (isDark
                                ? Colors.orange.withValues(alpha: 0.15)
                                : const Color(0xFFFFF7ED))),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isCorrect
                      ? (isDark
                            ? Colors.green.withValues(alpha: 0.4)
                            : const Color(0xFFBBF7D0))
                      : (isSkipped
                            ? (isDark ? Colors.white12 : const Color(0xFFE2E8F0))
                            : (isDark
                                  ? Colors.orange.withValues(alpha: 0.4)
                                  : const Color(0xFFFED7AA))),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(statusIcon, size: 16, color: statusColor),
                      const SizedBox(width: 6),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
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
                  const SizedBox(height: 6),
                  Text(
                    q.questionText,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 8),

                  if (!isCorrect) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isSkipped
                            ? (isDark
                                  ? Colors.grey.withValues(alpha: 0.2)
                                  : Colors.grey.shade100)
                            : (isDark
                                  ? Colors.red.withValues(alpha: 0.2)
                                  : Colors.red.shade50),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isSkipped
                            ? '⏭️ কোনো উত্তর দেননি (স্কিপ করা হয়েছে)'
                            : '❌ আপনার উত্তর: ${q.options[selected]}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isSkipped
                              ? (isDark
                                    ? Colors.grey.shade300
                                    : Colors.grey.shade800)
                              : (isDark
                                    ? Colors.red.shade200
                                    : Colors.red.shade900),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],

                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.green.withValues(alpha: 0.2)
                          : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '✅ সঠিক উত্তর: ${q.options[q.correctIndex]}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark
                            ? Colors.greenAccent
                            : Colors.green.shade900,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                  if (q.explanation.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      '💡 ব্যাখ্যা: ${BengaliMathSanitizer.sanitize(q.explanation)}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark
                            ? Colors.amber.shade200
                            : Colors.brown.shade800,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),

          const SizedBox(height: 14),

          // Add to Weak Topics if score is low
          if (_correctCount < total) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.purple.withValues(alpha: 0.2)
                    : Colors.purple.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark
                      ? Colors.purple.withValues(alpha: 0.4)
                      : Colors.purple.shade100,
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.radar, color: Colors.deepPurple, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'দুর্বল টপিক রাডারে যুক্ত করবেন?',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12.5,
                          ),
                        ),
                        Text(
                          'টপিক: ${widget.topic}',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white70 : Colors.black54,
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
                            backgroundColor: Colors.deepPurple,
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
            const SizedBox(height: 16),
          ],

          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A8A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Finish Drill & Close',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
