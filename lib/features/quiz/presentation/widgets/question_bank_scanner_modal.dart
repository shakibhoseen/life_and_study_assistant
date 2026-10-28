import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../core/services/ai/ai_media_limits.dart';
import '../../../../core/services/ai/models/question_bank_extract_result.dart';
import '../../../../core/services/ai/models/quiz_question.dart';
import '../../../../core/services/ai/question_bank_ocr_service.dart';
import '../../../../core/utils/bengali_math_sanitizer.dart';
import '../../../live_mcq/presentation/providers/exam_schedule_provider.dart';
import 'quiz_batch_correction_sheet.dart';
import 'quiz_drill_modal.dart';

class QuestionBankScannerModal extends ConsumerStatefulWidget {
  final List<QuizQuestion>? initialQuestions;
  final String? initialTitle;
  final String? initialSubject;
  final int? existingExamId;

  const QuestionBankScannerModal({
    super.key,
    this.initialQuestions,
    this.initialTitle,
    this.initialSubject,
    this.existingExamId,
  });

  static Future<void> show(
    BuildContext context, {
    List<QuizQuestion>? initialQuestions,
    String? initialTitle,
    String? initialSubject,
    int? existingExamId,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => QuestionBankScannerModal(
        initialQuestions: initialQuestions,
        initialTitle: initialTitle,
        initialSubject: initialSubject,
        existingExamId: existingExamId,
      ),
    );
  }

  @override
  ConsumerState<QuestionBankScannerModal> createState() =>
      _QuestionBankScannerModalState();
}

class _QuestionBankScannerModalState
    extends ConsumerState<QuestionBankScannerModal> {
  final ImagePicker _picker = ImagePicker();
  File? _questionImage;
  File? _answerKeyImage;
  String _selectedSubject = 'Auto Detect';
  CaptureDetail _detail = CaptureDetail.standard;

  bool _isScanning = false;
  String? _errorMessage;
  QuestionBankExtractResult? _result;
  List<QuizQuestion> _editableQuestions = [];
  final TextEditingController _titleController = TextEditingController();
  bool _isSavingToRoutine = false;
  bool _savedToRoutine = false;

  // AI Verification State
  final Map<int, QuestionVerificationResult> _verifications = {};
  final Set<int> _verifyingIndices = {};
  bool _isVerifyingAll = false;

  // Search & Filter State
  int _filterIndex = 0; // 0: All, 1: Warnings, 2: Verified
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  final List<String> _subjects = [
    'Auto Detect',
    'বাংলা ব্যাকরণ',
    'বাংলাদেশ বিষয়াবলী',
    'English Language & Literature',
    'Mathematics & Mental Ability',
    'General Science',
    'আন্তর্জাতিক বিষয়াবলী',
    'Computer & ICT',
    'Geography & Environment',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialQuestions != null &&
        widget.initialQuestions!.isNotEmpty) {
      _editableQuestions = List<QuizQuestion>.from(widget.initialQuestions!);
      _titleController.text = widget.initialTitle ?? 'টেস্ট পেপার প্রশ্নমালা';
      if (widget.initialSubject != null && widget.initialSubject!.isNotEmpty) {
        _selectedSubject = widget.initialSubject!;
      }
      _result = QuestionBankExtractResult(
        subject: widget.initialSubject ?? 'General',
        title: _titleController.text,
        questions: _editableQuestions,
        rawReference: widget.existingExamId != null
            ? 'Exam #${widget.existingExamId}'
            : 'Saved Test Paper',
      );
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(
    ImageSource source, {
    required bool isAnswerKey,
  }) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 2400,
        imageQuality: 85,
      );
      if (picked != null) {
        setState(() {
          if (isAnswerKey) {
            _answerKeyImage = File(picked.path);
          } else {
            _questionImage = File(picked.path);
          }
          _result = null;
          _errorMessage = null;
        });
      }
    } catch (e) {
      setState(() => _errorMessage = 'ছবি লোড করা যায়নি: $e');
    }
  }

  Future<void> _scanQuestionBank() async {
    if (_questionImage == null) return;

    setState(() {
      _isScanning = true;
      _errorMessage = null;
      _result = null;
      _verifications.clear();
      _verifyingIndices.clear();
    });

    try {
      final res = await QuestionBankOcrService.instance.extractQuestionBank(
        questionImage: _questionImage!,
        answerKeyImage: _answerKeyImage,
        subjectHint: _selectedSubject,
        detail: _detail,
      );

      if (mounted) {
        setState(() {
          _result = res;
          _editableQuestions = List<QuizQuestion>.from(res.questions);
          _titleController.text = res.title;
          _isScanning = false;
          _savedToRoutine = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _errorMessage = 'স্ক্যান ব্যর্থ হয়েছে: $e';
        });
      }
    }
  }

  Future<void> _verifySingleQuestion(int qIndex) async {
    if (qIndex < 0 || qIndex >= _editableQuestions.length) return;
    if (_verifyingIndices.contains(qIndex)) return;

    setState(() {
      _verifyingIndices.add(qIndex);
    });

    try {
      final ocrService = QuestionBankOcrService.instance;
      final q = _editableQuestions[qIndex];
      final subject = _selectedSubject != 'Auto Detect'
          ? _selectedSubject
          : (_result?.subject ?? 'General');

      final result = await ocrService.verifyQuestion(
        question: q,
        subject: subject,
      );

      if (mounted && result != null) {
        setState(() {
          _verifications[qIndex] = result;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade700,
            content: Text('AI যাচাই করা যায়নি: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _verifyingIndices.remove(qIndex);
        });
      }
    }
  }

  Future<void> _verifyAllQuestions() async {
    if (_isVerifyingAll || _editableQuestions.isEmpty) return;

    setState(() {
      _isVerifyingAll = true;
    });

    final ocrService = QuestionBankOcrService.instance;
    final subject = _selectedSubject != 'Auto Detect'
        ? _selectedSubject
        : (_result?.subject ?? 'General');

    for (int i = 0; i < _editableQuestions.length; i++) {
      if (!mounted) break;
      if (_verifications.containsKey(i)) continue;

      setState(() {
        _verifyingIndices.add(i);
      });

      try {
        final res = await ocrService.verifyQuestion(
          question: _editableQuestions[i],
          subject: subject,
        );
        if (mounted && res != null) {
          setState(() {
            _verifications[i] = res;
          });
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          _verifyingIndices.remove(i);
        });
      }
    }

    if (mounted) {
      setState(() {
        _isVerifyingAll = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF10B981),
          content: Text('সকল প্রশ্নের AI ফ্যাক্ট-চেক ও যাচাই সম্পন্ন হয়েছে!'),
        ),
      );
    }
  }

  void _applyCorrection(int qIndex, int correctIndex) {
    if (qIndex < 0 || qIndex >= _editableQuestions.length) return;
    final currentQ = _editableQuestions[qIndex];
    if (correctIndex < 0 || correctIndex >= currentQ.options.length) return;

    setState(() {
      _editableQuestions[qIndex] = currentQ.copyWith(
        correctIndex: correctIndex,
      );
      final existingVer = _verifications[qIndex];
      if (existingVer != null) {
        _verifications[qIndex] = QuestionVerificationResult(
          isCorrect: true,
          trueCorrectIndex: correctIndex,
          isAmbiguous: false,
          explanation:
              '${existingVer.explanation} (AI প্রস্তাবিত উত্তর প্রয়োগ করা হয়েছে)',
        );
      }
      _savedToRoutine = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.green.shade700,
        content: Text(
          'প্রশ্ন ${qIndex + 1}-এর সঠিক উত্তর "${currentQ.options[correctIndex]}" হিসেবে ঠিক করা হয়েছে ✓',
        ),
      ),
    );
  }

  void _deleteQuestion(int qIndex) {
    if (qIndex < 0 || qIndex >= _editableQuestions.length) return;
    final removed = _editableQuestions[qIndex];
    setState(() {
      _editableQuestions.removeAt(qIndex);
      _verifications.remove(qIndex);
      _verifyingIndices.remove(qIndex);
      _savedToRoutine = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.orange.shade800,
        content: Text('প্রশ্ন #${qIndex + 1} তালিকা থেকে বাদ দেওয়া হয়েছে'),
        action: SnackBarAction(
          label: 'আনডু',
          textColor: Colors.white,
          onPressed: () {
            setState(() {
              _editableQuestions.insert(qIndex, removed);
              _savedToRoutine = false;
            });
          },
        ),
      ),
    );
  }

  Future<void> _showEditQuestionDialog(int qIndex) async {
    if (qIndex < 0 || qIndex >= _editableQuestions.length) return;
    final q = _editableQuestions[qIndex];

    final questionTextCtrl = TextEditingController(text: q.questionText);
    final explanationCtrl = TextEditingController(text: q.explanation);
    final optionCtrls = q.options
        .map((opt) => TextEditingController(text: opt))
        .toList();
    int selectedCorrectIndex = q.correctIndex;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final isDark = Theme.of(ctx).brightness == Brightness.dark;
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              title: Row(
                children: [
                  const Icon(Icons.edit_note, color: Color(0xFF6366F1)),
                  const SizedBox(width: 8),
                  Text(
                    'প্রশ্ন #${qIndex + 1} সম্পাদনা',
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: questionTextCtrl,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'প্রশ্ন',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'অপশনসমূহ (সঠিক অপশনটি সিলেক্ট করুন):',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...List.generate(optionCtrls.length, (optIdx) {
                        final isSelected = selectedCorrectIndex == optIdx;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              IconButton(
                                icon: Icon(
                                  isSelected
                                      ? Icons.check_circle
                                      : Icons.radio_button_unchecked,
                                  color: isSelected
                                      ? Colors.green
                                      : Colors.grey,
                                ),
                                tooltip: 'সঠিক উত্তর হিসেবে চিহ্নিত করুন',
                                onPressed: () {
                                  setDialogState(
                                    () => selectedCorrectIndex = optIdx,
                                  );
                                },
                              ),
                              Expanded(
                                child: TextField(
                                  controller: optionCtrls[optIdx],
                                  decoration: InputDecoration(
                                    labelText: 'অপশন ${optIdx + 1}',
                                    border: const OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 8),
                      TextField(
                        controller: explanationCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'ব্যাখ্যা (ঐচ্ছিক)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('বাতিল'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final newQuestion = q.copyWith(
                      questionText: questionTextCtrl.text.trim(),
                      options: optionCtrls.map((c) => c.text.trim()).toList(),
                      correctIndex: selectedCorrectIndex,
                      explanation: explanationCtrl.text.trim(),
                    );
                    setState(() {
                      _editableQuestions[qIndex] = newQuestion;
                      _savedToRoutine = false;
                      _verifications.remove(qIndex);
                    });
                    Navigator.of(ctx).pop();
                  },
                  child: const Text('সংরক্ষণ করুন'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _startExamNow() {
    if (_editableQuestions.isEmpty) return;

    final title = _titleController.text.trim().isNotEmpty
        ? _titleController.text.trim()
        : (_result?.title ?? 'প্রশ্ন ব্যাংক প্র্যাকটিস');
    final subject = _result?.subject ?? 'General';

    Navigator.of(context).pop();

    QuizDrillModal.show(
      context,
      topic: title,
      subject: subject,
      examId: widget.existingExamId,
      customQuestions: _editableQuestions,
    );
  }

  void _copyAllQuestionsToClipboard() {
    final title = _titleController.text.trim().isNotEmpty
        ? _titleController.text.trim()
        : (_result?.title ?? 'প্রশ্ন ব্যাংক');
    final subject = _result?.subject ?? 'General';

    final buffer = StringBuffer();
    buffer.writeln('প্রশ্ন ব্যাংক পর্যালোচনা: $title');
    if (widget.existingExamId != null) {
      buffer.writeln('পরীক্ষা রেফারেন্স: E-${widget.existingExamId}');
    }
    buffer.writeln('বিষয়: $subject');
    buffer.writeln('মোট প্রশ্ন: ${_editableQuestions.length}টি');
    buffer.writeln('==============================\n');

    for (int i = 0; i < _editableQuestions.length; i++) {
      final q = _editableQuestions[i];
      buffer.writeln('প্রশ্ন ${i + 1}: ${q.questionText}');
      for (int optIdx = 0; optIdx < q.options.length; optIdx++) {
        final optChar = optIdx == 0
            ? 'ক'
            : (optIdx == 1 ? 'খ' : (optIdx == 2 ? 'গ' : 'ঘ'));
        buffer.writeln('  $optChar. ${q.options[optIdx]}');
      }
      final correctAns =
          q.correctIndex >= 0 && q.correctIndex < q.options.length
          ? q.options[q.correctIndex]
          : 'Unknown';
      buffer.writeln('• চিহ্নিত উত্তর: $correctAns');
      if (q.explanation.isNotEmpty) {
        buffer.writeln('• ব্যাখ্যা: ${q.explanation}');
      }
      buffer.writeln('');
    }
    buffer.writeln('==============================');
    buffer.writeln(
      'নির্দেশনা: অনুগ্রহ করে প্রতিটি প্রশ্ন ও উত্তর নিরপেক্ষভাবে যাচাই করুন। কোনো প্রশ্নে তথ্যের ভুল, ভুল উত্তর বা অস্পষ্টতা থাকলে বিস্তারিত বলুন।',
    );

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Color(0xFF10B981),
        content: Text(
          'সকল প্রশ্ন ক্লিপবোর্ডে কপি হয়েছে! অন্য AI-তে পেস্ট করতে পারেন।',
        ),
      ),
    );
  }

  Future<void> _showBatchFixSheet() async {
    final title = _titleController.text.trim().isNotEmpty
        ? _titleController.text.trim()
        : (_result?.title ?? 'প্রশ্ন ব্যাংক');
    final subject = _result?.subject ?? 'General';

    final updated = await QuizBatchCorrectionSheet.show(
      context,
      ref: ref,
      questions: _editableQuestions,
      examId: widget.existingExamId,
      topic: title,
      subject: subject,
    );

    if (updated != null && mounted) {
      setState(() {
        _editableQuestions = updated;
        _verifications.clear();
      });
    }
  }

  Future<void> _saveToRoutine() async {
    if (_isSavingToRoutine || _savedToRoutine || _editableQuestions.isEmpty) {
      return;
    }

    setState(() => _isSavingToRoutine = true);

    try {
      final db = ref.read(appDatabaseProvider);
      final title = _titleController.text.trim().isNotEmpty
          ? _titleController.text.trim()
          : (_result?.title ?? 'প্রশ্ন ব্যাংক প্র্যাকটিস');
      final subject = _result?.subject ?? 'General';

      final questionsJson = jsonEncode(
        _editableQuestions.map((q) => q.toJson()).toList(),
      );

      if (widget.existingExamId != null) {
        final existing = await (db.select(
          db.examSchedules,
        )..where((t) => t.id.equals(widget.existingExamId!))).getSingleOrNull();

        if (existing != null) {
          await (db.update(
            db.examSchedules,
          )..where((t) => t.id.equals(widget.existingExamId!))).write(
            ExamSchedulesCompanion(
              title: Value(title),
              topicsCovered: Value(title),
              subject: Value(subject),
              resourceSummary: Value(questionsJson),
            ),
          );
        }
      } else {
        final now = DateTime.now();
        await db.insertExamSchedulesDeduplicated([
          ExamSchedulesCompanion.insert(
            examDate: now,
            examTime: const Value('10:00 PM'),
            subject: Value(subject),
            title: title,
            topicsCovered: title,
            examType: const Value('Self Test'),
            trackName: const Value('Self Test'),
            resourceSummary: Value(questionsJson),
            rawReference: Value(
              'Question Bank OCR (${_editableQuestions.length} MCQs)',
            ),
          ),
        ]);
      }

      ref.invalidate(upcomingExamsStreamProvider);
      ref.invalidate(allExamsStreamProvider);
      ref.invalidate(distinctTracksStreamProvider);
      ref.invalidate(filteredExamsStreamProvider);

      if (mounted) {
        setState(() {
          _isSavingToRoutine = false;
          _savedToRoutine = true;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green.shade700,
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.existingExamId != null
                        ? '"$title" সফলভাবে আপডেট করা হয়েছে!'
                        : '"$title" সফলভাবে Self Test ট্যাবে সেভ করা হয়েছে!',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSavingToRoutine = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade700,
            content: Text('সংরক্ষণে সমস্যা হয়েছে: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF111827) : Colors.white;

    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 44,
            height: 4.5,
            decoration: BoxDecoration(
              color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(4),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50.withValues(
                      alpha: isDark ? 0.15 : 1,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.document_scanner_outlined,
                    color: Color(0xFF6366F1),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.existingExamId != null
                            ? 'টেস্ট পেপার প্রশ্নমালা ও AI ফ্যাক্ট-চেক'
                            : 'প্রশ্ন ব্যাংক স্ক্যানার ও কুইজ তৈরি',
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        widget.existingExamId != null
                            ? 'প্রশ্নসমূহ সম্পাদনা করুন ও AI দিয়ে সঠিক উত্তর যাচাই করুন'
                            : 'বই বা প্রশ্ন ব্যাংকের পাতার ছবি দিয়ে পরীক্ষা দিন',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark ? Colors.white60 : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Content Area
          Expanded(
            child: _isScanning
                ? _buildScanningState(isDark)
                : (_result != null
                      ? _buildResultReviewState(isDark)
                      : _buildInputState(isDark)),
          ),
        ],
      ),
    );
  }

  // ========================================================
  // INPUT STATE: Image Selection & Details
  // ========================================================
  Widget _buildInputState(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_errorMessage != null)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50.withValues(alpha: isDark ? 0.15 : 1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade300),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),

          // 1. Question Page Card
          _buildImageCard(
            title: '১. প্রশ্ন পাতার ছবি (আবশ্যক)',
            subtitle: 'বইয়ের যে পাতায় MCQ প্রশ্নগুলো ছাপা আছে',
            imageFile: _questionImage,
            isAnswerKey: false,
            isDark: isDark,
          ),

          const SizedBox(height: 14),

          // 2. Answer Key Card (Optional)
          _buildImageCard(
            title: '২. উত্তরপত্রের ছবি (ঐচ্ছিক)',
            subtitle: 'উত্তর যদি অন্য পাতায় বা সমাধান অংশে থাকে',
            imageFile: _answerKeyImage,
            isAnswerKey: true,
            isDark: isDark,
          ),

          const SizedBox(height: 16),

          // Subject hint selector
          Text(
            'বিষয় নির্বাচন (ঐচ্ছিক)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: _subjects.take(5).map((subj) {
              final selected = _selectedSubject == subj;
              return ChoiceChip(
                selected: selected,
                onSelected: (_) => setState(() => _selectedSubject = subj),
                label: Text(
                  subj,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 14),

          // Resolution detail
          Text(
            'ছবির কোয়ালিটি',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: CaptureDetail.values.map((d) {
              final selected = d == _detail;
              return ChoiceChip(
                selected: selected,
                onSelected: (_) => setState(() => _detail = d),
                label: Text(
                  '${d.label} · ~${d.approxTokens}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 24),

          // Scan Button
          ElevatedButton.icon(
            onPressed: _questionImage == null ? null : _scanQuestionBank,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              disabledBackgroundColor: isDark
                  ? Colors.grey.shade800
                  : Colors.grey.shade300,
            ),
            icon: const Icon(Icons.auto_awesome, size: 20),
            label: const Text(
              '⚡ প্রশ্ন ব্যাংক স্ক্যান করুন (Extract MCQs)',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageCard({
    required String title,
    required String subtitle,
    required File? imageFile,
    required bool isAnswerKey,
    required bool isDark,
  }) {
    final borderColor = isDark ? const Color(0xFF374151) : Colors.grey.shade300;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2937) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isAnswerKey ? Icons.key_outlined : Icons.menu_book,
                size: 18,
                color: isAnswerKey
                    ? Colors.amber.shade600
                    : const Color(0xFF4F46E5),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (imageFile != null)
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: Colors.red,
                  ),
                  tooltip: 'মুছুন',
                  onPressed: () => setState(() {
                    if (isAnswerKey) {
                      _answerKeyImage = null;
                    } else {
                      _questionImage = null;
                    }
                  }),
                ),
            ],
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white60 : Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 10),
          if (imageFile != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                children: [
                  Image.file(
                    imageFile,
                    height: 120,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                  Positioned(
                    bottom: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'ছবি যুক্ত হয়েছে ✓',
                        style: TextStyle(color: Colors.white, fontSize: 10.5),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(
                      ImageSource.camera,
                      isAnswerKey: isAnswerKey,
                    ),
                    icon: const Icon(Icons.camera_alt, size: 16),
                    label: const Text(
                      'ক্যামেরা',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(
                      ImageSource.gallery,
                      isAnswerKey: isAnswerKey,
                    ),
                    icon: const Icon(Icons.photo_library, size: 16),
                    label: const Text(
                      'গ্যালারি',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ========================================================
  // LOADING STATE
  // ========================================================
  Widget _buildScanningState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 44,
              height: 44,
              child: CircularProgressIndicator(
                strokeWidth: 3.5,
                color: Color(0xFF4F46E5),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Gemini Vision প্রশ্ন পাতা স্ক্যান করছে...',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'প্রশ্ন, ৪টি অপশন ও উত্তরমালা স্বয়ংক্রিয়ভাবে সাজানো হচ্ছে',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white60 : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ========================================================
  // REVIEW & START EXAM STATE
  // ========================================================
  Widget _buildResultReviewState(bool isDark) {
    final verifiedCount = _verifications.values
        .where((v) => v.isCorrect && !v.isAmbiguous)
        .length;
    final warningCount = _verifications.values
        .where((v) => !v.isCorrect || v.isAmbiguous)
        .length;

    return Column(
      children: [
        // Summary & Editable Title
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFEEF2FF),
            border: Border(
              bottom: BorderSide(
                color: isDark
                    ? const Color(0xFF334155)
                    : const Color(0xFFCBD5E1),
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4F46E5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _result?.subject ?? 'General',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.shade700,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${BengaliMathSanitizer.toBengaliDigits('${_editableQuestions.length}')}টি প্রশ্ন',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (widget.existingExamId == null)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: () => setState(() {
                        _result = null;
                        _verifications.clear();
                      }),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text(
                        'আবার তুলুন',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _titleController,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'পরীক্ষার শিরোনাম (টপিক)',
                  labelStyle: const TextStyle(fontSize: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),

              // AI Verification Action Bar
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isVerifyingAll ? null : _verifyAllQuestions,
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
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
                      icon: _isVerifyingAll
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF4F46E5),
                              ),
                            )
                          : const Icon(Icons.fact_check_outlined, size: 16),
                      label: Text(
                        _isVerifyingAll
                            ? 'সব প্রশ্ন AI যাচাই করছে...'
                            : '⚡ সব প্রশ্ন AI দিয়ে যাচাই করুন',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  if (_verifications.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    if (warningCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade100,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.amber.shade600),
                        ),
                        child: Text(
                          '⚠️ $warningCountটি অসঙ্গতি!',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ),
                    if (warningCount > 0 && verifiedCount > 0)
                      const SizedBox(width: 4),
                    if (verifiedCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.green.shade400),
                        ),
                        child: Text(
                          '✓ $verifiedCountটি সঠিক',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade900,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
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
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    icon: const Icon(Icons.copy_rounded, size: 13),
                    label: const Text(
                      'সব কপি',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: _copyAllQuestionsToClipboard,
                  ),
                  const SizedBox(width: 6),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    icon: const Icon(Icons.auto_fix_high_rounded, size: 13),
                    label: const Text(
                      'AI ফিক্স',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: _showBatchFixSheet,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 32,
                      child: TextField(
                        controller: _searchController,
                        onChanged: (val) =>
                            setState(() => _searchQuery = val.trim()),
                        style: const TextStyle(fontSize: 11.5),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'প্রশ্ন খুঁজুন...',
                          hintStyle: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade500,
                          ),
                          prefixIcon: const Icon(Icons.search, size: 15),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 26,
                          ),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 14),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 24,
                                  ),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (warningCount > 0 || verifiedCount > 0) ...[
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: Text(
                          'সব (${_editableQuestions.length})',
                          style: const TextStyle(fontSize: 11),
                        ),
                        selected: _filterIndex == 0,
                        onSelected: (_) => setState(() => _filterIndex = 0),
                        visualDensity: VisualDensity.compact,
                      ),
                      if (warningCount > 0) ...[
                        const SizedBox(width: 6),
                        ChoiceChip(
                          label: Text(
                            '⚠️ অসঙ্গতি ($warningCount)',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.amber.shade900,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          selected: _filterIndex == 1,
                          selectedColor: Colors.amber.shade100,
                          onSelected: (_) => setState(() => _filterIndex = 1),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                      if (verifiedCount > 0) ...[
                        const SizedBox(width: 6),
                        ChoiceChip(
                          label: Text(
                            '✓ সঠিক ($verifiedCount)',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.green.shade900,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          selected: _filterIndex == 2,
                          selectedColor: Colors.green.shade100,
                          onSelected: (_) => setState(() => _filterIndex = 2),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),

        // Questions List
        Expanded(
          child: () {
            final filteredIndices = <int>[];
            for (int i = 0; i < _editableQuestions.length; i++) {
              final q = _editableQuestions[i];
              final v = _verifications[i];
              if (_filterIndex == 1 &&
                  (v == null || (v.isCorrect && !v.isAmbiguous))) {
                continue;
              }
              if (_filterIndex == 2 &&
                  (v == null || !v.isCorrect || v.isAmbiguous)) {
                continue;
              }
              if (_searchQuery.isNotEmpty) {
                final query = _searchQuery.toLowerCase();
                final matchQ = q.questionText.toLowerCase().contains(query);
                final matchOpts = q.options.any(
                  (o) => o.toLowerCase().contains(query),
                );
                if (!matchQ && !matchOpts) continue;
              }
              filteredIndices.add(i);
            }

            if (filteredIndices.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.search_off,
                      size: 36,
                      color: isDark
                          ? Colors.grey.shade600
                          : Colors.grey.shade400,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _searchQuery.isNotEmpty
                          ? '"$_searchQuery" সম্পর্কিত কোনো প্রশ্ন পাওয়া যায়নি'
                          : 'কোনো প্রশ্ন মেলেনি',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(14),
              itemCount: filteredIndices.length,
              itemBuilder: (context, idx) {
                final qIndex = filteredIndices[idx];
                final q = _editableQuestions[qIndex];
                return _buildQuestionCard(qIndex, q, isDark);
              },
            );
          }(),
        ),

        // Bottom Action Buttons
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF111827) : Colors.white,
            border: Border(
              top: BorderSide(
                color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade200,
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: ElevatedButton.icon(
                    onPressed: _startExamNow,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.bolt, size: 20),
                    label: const Text(
                      '⚡ এখনই পরীক্ষা দিন (Start Exam)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: OutlinedButton.icon(
                    onPressed: _savedToRoutine ? null : _saveToRoutine,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF4F46E5),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: Icon(
                      _savedToRoutine
                          ? Icons.check
                          : (widget.existingExamId != null
                                ? Icons.save_as_outlined
                                : Icons.bookmark_add_outlined),
                      size: 18,
                    ),
                    label: Text(
                      _savedToRoutine
                          ? 'সেভ হয়েছে ✓'
                          : (widget.existingExamId != null
                                ? '💾 আপডেট করুন'
                                : '💾 সেভ করুন'),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuestionCard(int qIndex, QuizQuestion q, bool isDark) {
    final verification = _verifications[qIndex];
    final isVerifying = _verifyingIndices.contains(qIndex);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: q.needsReview
              ? Colors.orange.shade600
              : (verification != null &&
                        (!verification.isCorrect || verification.isAmbiguous)
                    ? Colors.amber.shade600
                    : (isDark
                          ? const Color(0xFF334155)
                          : Colors.grey.shade300)),
          width:
              q.needsReview ||
                  (verification != null &&
                      (!verification.isCorrect || verification.isAmbiguous))
              ? 1.8
              : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A row the scan could not actually read, or answered without
          // confidence, says so here. Without this the garbled ones look
          // exactly like the clean ones.
          if (q.needsReview) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 9),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: isDark ? 0.15 : 0.09),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    q.legible
                        ? Icons.help_outline
                        : Icons.visibility_off_outlined,
                    size: 15,
                    color: Colors.orange.shade800,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      !q.legible
                          ? 'ছবিতে এই প্রশ্নটি স্পষ্ট পড়া যায়নি — সংরক্ষণের আগে নিজে মিলিয়ে নিন বা বাদ দিন।'
                          : 'উত্তরটি অনিশ্চিত (${q.answerSource.label}) — মিলিয়ে নিন।',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        color: isDark
                            ? Colors.orange.shade200
                            : Colors.orange.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Question Header: Index, Action buttons (Edit & AI Verify)
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF334155)
                      : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '#${qIndex + 1}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Spacer(),
              // Edit button
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 16),
                tooltip: 'প্রশ্ন বা অপশন সম্পাদনা করুন',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                onPressed: () => _showEditQuestionDialog(qIndex),
              ),
              const SizedBox(width: 2),
              // Delete / Exclude button
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  size: 16,
                  color: Colors.redAccent,
                ),
                tooltip: 'অপ্রয়োজনীয় বা ভুল প্রশ্নটি বাদ দিন',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                onPressed: () => _deleteQuestion(qIndex),
              ),
              const SizedBox(width: 4),
              // AI Verify Single Button
              if (isVerifying)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                InkWell(
                  onTap: () => _verifySingleQuestion(qIndex),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: verification != null
                          ? (verification.isCorrect && !verification.isAmbiguous
                                ? Colors.green.shade50.withValues(
                                    alpha: isDark ? 0.2 : 1,
                                  )
                                : Colors.amber.shade50.withValues(
                                    alpha: isDark ? 0.2 : 1,
                                  ))
                          : (isDark
                                ? const Color(0xFF312E81).withValues(alpha: 0.4)
                                : const Color(0xFFEEF2FF)),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: verification != null
                            ? (verification.isCorrect &&
                                      !verification.isAmbiguous
                                  ? Colors.green
                                  : Colors.amber.shade700)
                            : const Color(0xFF818CF8),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          verification != null
                              ? (verification.isCorrect &&
                                        !verification.isAmbiguous
                                    ? Icons.check_circle_outline
                                    : Icons.warning_amber_rounded)
                              : Icons.auto_awesome,
                          size: 13,
                          color: verification != null
                              ? (verification.isCorrect &&
                                        !verification.isAmbiguous
                                    ? Colors.green
                                    : Colors.amber.shade800)
                              : const Color(0xFF6366F1),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          verification != null
                              ? (verification.isCorrect &&
                                        !verification.isAmbiguous
                                    ? 'AI পরীক্ষিত (সঠিক)'
                                    : 'অসঙ্গতি চিহ্নিত')
                              : 'AI যাচাই',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: verification != null
                                ? (verification.isCorrect &&
                                          !verification.isAmbiguous
                                      ? Colors.green
                                      : Colors.amber.shade900)
                                : const Color(0xFF4F46E5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),

          // Question text
          Text(
            q.questionText,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),

          // Verification Alert Box (if flawed, irrelevant, or discrepancy found)
          if (verification != null &&
              (verification.isFlawed || verification.isIrrelevant)) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.red.shade900.withValues(alpha: 0.25)
                    : Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark ? Colors.red.shade700 : Colors.red.shade300,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.cancel_outlined,
                        size: 16,
                        color: Colors.red.shade700,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          verification.isFlawed
                              ? '🚫 ত্রুটিপূর্ণ প্রশ্ন (Invalid / Flawed Question)'
                              : '🗑️ অপ্রয়োজনীয় প্রশ্ন (Redundant for BCS)',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? Colors.red.shade200
                                : Colors.red.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (verification.explanation.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      verification.explanation,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.delete_outline, size: 14),
                        label: const Text(
                          'প্রশ্নটি বাদ দিন',
                          style: TextStyle(fontSize: 11),
                        ),
                        onPressed: () => _deleteQuestion(qIndex),
                      ),
                      const SizedBox(width: 6),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.edit, size: 14),
                        label: const Text(
                          'সংশোধন করুন',
                          style: TextStyle(fontSize: 11),
                        ),
                        onPressed: () => _showEditQuestionDialog(qIndex),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else if (verification != null &&
              (!verification.isCorrect || verification.isAmbiguous)) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.amber.shade900.withValues(alpha: 0.25)
                    : Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark ? Colors.amber.shade700 : Colors.amber.shade400,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: Colors.amber.shade800,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '⚠️ সতর্কতা: বইয়ের উত্তরে অসঙ্গতি পাওয়া গেছে!',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? Colors.amber.shade200
                              : Colors.amber.shade900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '• বইয়ের চিহ্নিত উত্তর: অপশন ${q.correctIndex + 1} (${q.options.length > q.correctIndex ? q.options[q.correctIndex] : ''})',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  if (verification.trueCorrectIndex >= 0 &&
                      verification.trueCorrectIndex < q.options.length) ...[
                    const SizedBox(height: 2),
                    Text(
                      '• AI প্রস্তাবিত সঠিক উত্তর: অপশন ${verification.trueCorrectIndex + 1} (${q.options[verification.trueCorrectIndex]})',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF10B981),
                      ),
                    ),
                  ],
                  if (verification.explanation.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'ব্যাখ্যা: ${verification.explanation}',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontStyle: FontStyle.italic,
                        color: isDark
                            ? Colors.amber.shade100
                            : Colors.amber.shade900,
                      ),
                    ),
                  ],
                  if (verification.trueCorrectIndex >= 0 &&
                      verification.trueCorrectIndex < q.options.length &&
                      verification.trueCorrectIndex != q.correctIndex) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        icon: const Icon(Icons.check, size: 14),
                        label: const Text(
                          'সঠিক উত্তর হিসেবে গ্রহণ করুন',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: () => _applyCorrection(
                          qIndex,
                          verification.trueCorrectIndex,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ] else if (verification != null &&
              verification.isCorrect &&
              !verification.isAmbiguous) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.green.shade900.withValues(alpha: 0.2)
                    : Colors.green.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isDark ? Colors.green.shade700 : Colors.green.shade300,
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, size: 14, color: Colors.green),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '✓ AI যাচাইকৃত: চিহ্নিত উত্তরটি সঠিক। ${verification.explanation}',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: isDark
                            ? Colors.green.shade200
                            : Colors.green.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Options
          ...List.generate(q.options.length, (optIndex) {
            final isCorrect = optIndex == q.correctIndex;
            return InkWell(
              onTap: () {
                setState(() {
                  _editableQuestions[qIndex] = q.copyWith(
                    correctIndex: optIndex,
                  );
                  _savedToRoutine = false;
                });
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isCorrect
                      ? (isDark
                            ? Colors.green.withValues(alpha: 0.25)
                            : Colors.green.shade50)
                      : (isDark
                            ? const Color(0xFF0F172A)
                            : Colors.grey.shade50),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isCorrect
                        ? Colors.green
                        : (isDark
                              ? const Color(0xFF334155)
                              : Colors.grey.shade300),
                    width: isCorrect ? 1.5 : 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isCorrect
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 16,
                      color: isCorrect ? Colors.green : Colors.grey.shade400,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        q.options[optIndex],
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: isCorrect
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isCorrect
                              ? (isDark
                                    ? Colors.green.shade300
                                    : Colors.green.shade900)
                              : (isDark ? Colors.white70 : Colors.black87),
                        ),
                      ),
                    ),
                    if (isCorrect)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.shade700,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'চিহ্নিত উত্তর',
                          style: TextStyle(color: Colors.white, fontSize: 9.5),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),

          if (q.explanation.isNotEmpty && verification == null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : Colors.amber.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isDark ? Colors.amber.shade900 : Colors.amber.shade200,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 14,
                    color: isDark
                        ? Colors.amber.shade300
                        : Colors.amber.shade900,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'ব্যাখ্যা: ${q.explanation}',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? Colors.amber.shade200
                            : Colors.amber.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
