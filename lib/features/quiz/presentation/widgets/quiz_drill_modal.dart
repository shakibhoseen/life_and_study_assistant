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

class QuizDrillModal extends ConsumerStatefulWidget {
  final String topic;
  final String subject;
  final int? examId;
  final List<DrillQuestion>? mistakeQuestions;
  final List<QuizQuestion>? customQuestions;
  final VoidCallback? onCompleted;

  const QuizDrillModal({
    super.key,
    required this.topic,
    required this.subject,
    this.examId,
    this.mistakeQuestions,
    this.customQuestions,
    this.onCompleted,
  });

  static Future<void> show(
    BuildContext context, {
    required String topic,
    required String subject,
    int? examId,
    List<DrillQuestion>? mistakeQuestions,
    List<QuizQuestion>? customQuestions,
    VoidCallback? onCompleted,
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
      ),
    );
  }

  @override
  ConsumerState<QuizDrillModal> createState() => _QuizDrillModalState();
}

class _QuizDrillModalState extends ConsumerState<QuizDrillModal> {
  bool _isLoading = true;
  List<QuizQuestion> _questions = [];
  int _currentIndex = 0;
  int? _selectedOptionIndex;
  bool _hasAnswered = false;
  int _correctCount = 0;
  bool _isFinished = false;
  final Map<int, int> _userAnswers = {};
  bool _hasPersisted = false;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    if (widget.customQuestions != null && widget.customQuestions!.isNotEmpty) {
      setState(() {
        _questions = widget.customQuestions!;
        _isLoading = false;
      });
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
    }
  }

  void _onOptionSelected(int index) {
    if (_hasAnswered) return;
    setState(() {
      _selectedOptionIndex = index;
      _hasAnswered = true;
      _userAnswers[_currentIndex] = index;
      if (index == _questions[_currentIndex].correctIndex) {
        _correctCount++;
      }
    });
  }

  void _nextQuestion() {
    if (_currentIndex < _questions.length - 1) {
      setState(() {
        _currentIndex++;
        _selectedOptionIndex = null;
        _hasAnswered = false;
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
    for (int i = 0; i < _questions.length; i++) {
      final q = _questions[i];
      final selected = _userAnswers[i] ?? -1;
      final isCorrect = selected == q.correctIndex;

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

    final incorrectCount = _questions.length - _correctCount;
    final percent = (_correctCount / _questions.length) * 100.0;

    try {
      await ref
          .read(drillHistoryNotifierProvider.notifier)
          .saveDrillSession(
            subject: widget.subject,
            topic: widget.topic,
            totalQuestions: _questions.length,
            correctCount: _correctCount,
            incorrectCount: incorrectCount,
            scorePercentage: percent,
            questions: questionsCompanions,
          );
    } catch (e) {
      debugPrint('Error persisting drill session: $e');
    }
  }

  void _copyFullReviewToClipboard() {
    final buffer = StringBuffer();
    buffer.writeln('কুইজ পর্যালোচনা ও উত্তরপত্র (যাচাইয়ের জন্য):');
    if (widget.examId != null) {
      buffer.writeln('পরীক্ষা রেফারেন্স: E-${widget.examId}');
    }
    if (widget.subject.isNotEmpty) buffer.writeln('বিষয়: ${widget.subject}');
    if (widget.topic.isNotEmpty) buffer.writeln('টপিক: ${widget.topic}');
    buffer.writeln(
      'মোট প্রশ্ন: ${_questions.length}টি | সঠিক: $_correctCountটি | ভুল: ${_questions.length - _correctCount}টি',
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
    return Container(
      height: MediaQuery.of(context).size.height * 0.90,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.psychology,
                    color: Colors.indigo,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'LiveMCQ Drill & Practice',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo.shade900,
                        ),
                      ),
                      Text(
                        '${widget.subject} • ${widget.topic}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

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

    final question = _questions[_currentIndex];
    final progress = (_currentIndex + 1) / _questions.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Progress bar and counter
          Row(
            children: [
              Text(
                'Question ${_currentIndex + 1} of ${_questions.length}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo,
                ),
              ),
              const Spacer(),
              Text(
                'Score: $_correctCount',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.indigo.shade50,
            valueColor: const AlwaysStoppedAnimation(Colors.indigo),
            minHeight: 6,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 20),

          // Question Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Text(
              BengaliMathSanitizer.sanitize(question.questionText),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                height: 1.45,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Options
          ...List.generate(question.options.length, (index) {
            final optionText = BengaliMathSanitizer.sanitize(
              question.options[index],
            );
            final isCorrectOption = index == question.correctIndex;
            final isSelected = index == _selectedOptionIndex;

            Color borderColor = const Color(0xFFE2E8F0);
            Color bgColor = Colors.white;
            Color textColor = const Color(0xFF1E293B);
            IconData? icon;
            Color iconColor = Colors.transparent;

            if (_hasAnswered) {
              if (isCorrectOption) {
                borderColor = Colors.green.shade600;
                bgColor = Colors.green.shade50;
                textColor = Colors.green.shade900;
                icon = Icons.check_circle;
                iconColor = Colors.green.shade700;
              } else if (isSelected && !isCorrectOption) {
                borderColor = Colors.red.shade400;
                bgColor = Colors.red.shade50;
                textColor = Colors.red.shade900;
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
                      width: isSelected || isCorrectOption ? 1.5 : 1,
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

          // Explanation Box (Shown after answering)
          if (_hasAnswered) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.shade200),
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
                          color: Colors.amber.shade900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    BengaliMathSanitizer.sanitize(question.explanation),
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.brown.shade800,
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

  Widget _buildResultsState() {
    final total = _questions.length;
    final percent = total > 0 ? ((_correctCount / total) * 100).toInt() : 0;
    final isGood = _correctCount >= (total * 0.6).ceil();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final wrongQuestions = <QuizQuestion>[];
    for (int i = 0; i < _questions.length; i++) {
      if (_userAnswers[i] != _questions[i].correctIndex) {
        wrongQuestions.add(_questions[i]);
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        children: [
          // Result Header Circle
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
            'আপনি $totalটির মধ্যে $_correctCountটি প্রশ্নের সঠিক উত্তর দিয়েছেন ($percent%)',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          const SizedBox(height: 16),

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
                        'Re-drill ${wrongQuestions.length} Wrong Questions',
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
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Detailed Question-by-Question Review with Copy for External AI
          Row(
            children: [
              Expanded(
                child: Text(
                  '📋 প্রশ্নভিত্তিক পর্যালোচনা (Detailed Review)',
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
                icon: const Icon(Icons.auto_fix_high_rounded, size: 14),
                label: const Text(
                  'AI ফিক্স',
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

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isCorrect
                    ? (isDark
                          ? Colors.green.withValues(alpha: 0.15)
                          : const Color(0xFFF0FDF4))
                    : (isDark
                          ? Colors.orange.withValues(alpha: 0.15)
                          : const Color(0xFFFFF7ED)),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isCorrect
                      ? (isDark
                            ? Colors.green.withValues(alpha: 0.4)
                            : const Color(0xFFBBF7D0))
                      : (isDark
                            ? Colors.orange.withValues(alpha: 0.4)
                            : const Color(0xFFFED7AA)),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        isCorrect ? Icons.check_circle : Icons.cancel,
                        size: 16,
                        color: isCorrect
                            ? const Color(0xFF15803D)
                            : const Color(0xFFC2410C),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'প্রশ্ন ${i + 1}: ${isCorrect ? "সঠিক উত্তর" : "ভুল উত্তর"}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: isCorrect
                              ? const Color(0xFF15803D)
                              : const Color(0xFFC2410C),
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
                        color: isDark
                            ? Colors.red.withValues(alpha: 0.2)
                            : Colors.red.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '❌ আপনার উত্তর: ${selected >= 0 ? q.options[selected] : "উত্তর দেওয়া হয়নি"}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark
                              ? Colors.red.shade200
                              : Colors.red.shade900,
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
