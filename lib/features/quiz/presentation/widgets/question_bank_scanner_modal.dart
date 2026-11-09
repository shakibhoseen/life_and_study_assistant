import 'dart:async';
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
import '../../../../core/services/ai/cross_check_answers.dart';
import '../../domain/scan_preferences.dart';
import '../../domain/scan_review_tally.dart';
import '../../../../core/services/ai/models/question_bank_extract_result.dart';
import '../../../../core/services/ai/models/quiz_question.dart';
import '../../../../core/services/ai/question_bank_ocr_service.dart';
import '../../../../core/services/ai/question_text_parser.dart';
import '../../../../core/services/voice/device_dictation_service.dart';
import '../../../../core/utils/bengali_math_sanitizer.dart';
import '../../../../core/widgets/ai_progress_pipeline_widget.dart';
import '../../../live_mcq/presentation/providers/exam_schedule_provider.dart';
import 'question_review_card.dart';
import 'quiz_batch_correction_sheet.dart';
import 'quiz_drill_modal.dart';
import '../../../../core/services/media/photo_capture_service.dart';
import '../../../../core/widgets/ai_key_missing_notice.dart';
import '../../domain/merge_scanned_pages.dart';
import '../../../../core/widgets/photo_source_sheet.dart';

enum ScannerInputMode { imageOcr, textPaste }

/// What the review list is showing.
///
/// The first few come from the scan itself and are known the moment the page
/// comes back. The last two come from the optional AI verification pass, which
/// is what this filter used to consist of entirely — three bare ints with a
/// comment explaining them.
enum ReviewFilter {
  all,
  noAnswer,
  answersDisagree,
  unreadable,
  clean,
  aiWarning,
  aiVerified,
}

class QuestionBankScannerModal extends ConsumerStatefulWidget {
  final List<QuizQuestion>? initialQuestions;
  final String? initialTitle;
  final String? initialSubject;
  final int? existingExamId;
  final String? initialText;

  const QuestionBankScannerModal({
    super.key,
    this.initialQuestions,
    this.initialTitle,
    this.initialSubject,
    this.existingExamId,
    this.initialText,
  });

  static Future<void> show(
    BuildContext context, {
    List<QuizQuestion>? initialQuestions,
    String? initialTitle,
    String? initialSubject,
    int? existingExamId,
    String? initialText,
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
        initialText: initialText,
      ),
    );
  }

  @override
  ConsumerState<QuestionBankScannerModal> createState() =>
      _QuestionBankScannerModalState();
}

class _QuestionBankScannerModalState
    extends ConsumerState<QuestionBankScannerModal> {
  ScannerInputMode _inputMode = ScannerInputMode.imageOcr;
  final TextEditingController _pastedTextController = TextEditingController();
  final List<File> _questionImages = [];
  File? _answerKeyImage;
  String _selectedSubject = 'Auto Detect';
  /// A full page of small Bengali print is what this screen is for, which is
  /// what [CaptureDetail.high] describes and what the service itself defaults
  /// to. The modal used to send `standard` over the top of that, so a page
  /// went to the model at 1024px unless the user noticed and said otherwise.
  CaptureDetail _detail = CaptureDetail.high;

  /// Whether only an answer printed on the page may be kept.
  ///
  /// On by default. These books print their own answers and those are usually
  /// right, so a model that reasons over the top of them adds mistakes rather
  /// than removing any — and a wrong answer that looks certain is worse than
  /// a blank the reader fills in.
  bool _trustPrintedAnswersOnly = true;

  /// Whether the model writes an explanation where the page prints none.
  ///
  /// Off by default: it spends output tokens on every question, and output is
  /// the slow half of the wait. A single question can still be explained on
  /// demand afterwards.
  bool _withExplanations = false;

  /// Whether the answers are read a second time and compared.
  ///
  /// On by default. Measured on one page: two reads of it disagreed on six
  /// answers out of eighteen, and both reads reported every one as read off
  /// the page, with no hint of doubt. A model that takes খ for ঘ does not know
  /// it has, so nothing it reports can catch this — only reading twice can.
  /// The second read asks for the answer letters alone, so it costs a fraction
  /// of the first.
  bool _crossCheckAnswers = true;

  /// Set when the re-check could not be made at all, so the screen can say the
  /// answers went unchecked rather than implying they were confirmed.
  bool _crossCheckUnavailable = false;

  bool _isScanning = false;
  int _currentScanningPageIndex = 0;
  int _totalScanningPages = 0;
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
  ReviewFilter _filter = ReviewFilter.all;
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

  /// Writes the four scanning settings back, so the next page starts where
  /// the last one left off rather than at the defaults.
  void _rememberScanPreferences() {
    unawaited(
      ScanPreferences(
        trustPrintedAnswersOnly: _trustPrintedAnswersOnly,
        withExplanations: _withExplanations,
        crossCheckAnswers: _crossCheckAnswers,
        detail: _detail,
      ).save(),
    );
  }

  Future<void> _loadScanPreferences() async {
    final saved = await ScanPreferences.load();
    if (!mounted) return;
    setState(() {
      _trustPrintedAnswersOnly = saved.trustPrintedAnswersOnly;
      _withExplanations = saved.withExplanations;
      _crossCheckAnswers = saved.crossCheckAnswers;
      _detail = saved.detail;
    });
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadScanPreferences());
    if (widget.initialText != null && widget.initialText!.isNotEmpty) {
      _pastedTextController.text = widget.initialText!;
      _inputMode = ScannerInputMode.textPaste;
    }
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
    // Closing the modal while dictation is open otherwise leaves the
    // recogniser reopening itself in the background. Not awaited, because
    // dispose cannot be.
    unawaited(DeviceDictationService.instance.stop());
    _pastedTextController.dispose();
    _titleController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Reads another page into the same set.
  ///
  /// A model test spread over three pages is one test, so the pages add up
  /// here rather than becoming three separate papers to drill apart.
  Future<void> _addAnotherPage() async {
    // Not always the camera: a paper already photographed, shared or
    // downloaded is in the gallery and should not have to be shot again.
    final source = await PhotoSourceSheet.ask(
      context,
      title: 'পরের পাতা কোথা থেকে নেবেন?',
    );
    if (source == null || !mounted) return;

    final picked = await PhotoCaptureService.instance.captureAndCrop(
      source: source,
      context: context,
      title: 'পরের পাতার প্রশ্ন কেটে নিন',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _questionImages.add(picked);
      // NOTE: We deliberately PRESERVE _answerKeyImage!
      // In competitive test papers, 1 compact answer key covers the whole 1-200 questions.
      _errorMessage = null;
    });
    await _scanQuestionBank(append: true);
  }

  Future<void> _rotate({required bool isAnswerKey, int pageIndex = 0}) async {
    final current = isAnswerKey
        ? _answerKeyImage
        : (pageIndex < _questionImages.length
              ? _questionImages[pageIndex]
              : null);
    if (current == null) return;
    final turned = await PhotoCaptureService.instance.rotateQuarterTurn(
      current,
    );
    if (!mounted) return;
    setState(() {
      if (isAnswerKey) {
        _answerKeyImage = turned;
      } else if (pageIndex < _questionImages.length) {
        _questionImages[pageIndex] = turned;
      }
      // The page the model was asked about has changed, so the old read no
      // longer describes it.
      _result = null;
      _errorMessage = null;
      // Flutter caches a decoded file by path and size; a new path each turn
      // is what makes the preview actually redraw.
      imageCache.clear();
    });
  }

  Future<void> _recrop({required bool isAnswerKey, int pageIndex = 0}) async {
    final current = isAnswerKey
        ? _answerKeyImage
        : (pageIndex < _questionImages.length
              ? _questionImages[pageIndex]
              : null);
    if (current == null) return;
    final trimmed = await PhotoCaptureService.instance.cropExisting(
      path: current.path,
      context: context,
      title: isAnswerKey ? 'উত্তরপত্র কেটে নিন' : 'প্রশ্নের অংশ কেটে নিন',
    );
    if (trimmed == null || !mounted) return;
    setState(() {
      if (isAnswerKey) {
        _answerKeyImage = trimmed;
      } else if (pageIndex < _questionImages.length) {
        _questionImages[pageIndex] = trimmed;
      }
      _result = null;
      _errorMessage = null;
    });
  }

  Future<void> _pickImage(
    ImageSource source, {
    required bool isAnswerKey,
  }) async {
    try {
      if (!isAnswerKey && source == ImageSource.gallery) {
        final picker = ImagePicker();
        final pickedList = await picker.pickMultiImage(
          // As taken. This call used to carry its own 1920/90 and never
          // consulted AiMediaLimits, so picking "পূর্ণ" below could not
          // actually get a full-sized page.
          maxWidth: AiMediaLimits.pickerMaxDimension,
          maxHeight: AiMediaLimits.pickerMaxDimension,
        );
        if (pickedList.isNotEmpty) {
          setState(() {
            for (final xFile in pickedList) {
              _questionImages.add(File(xFile.path));
            }
            _result = null;
            _errorMessage = null;
          });
          return;
        }
      }

      if (!mounted) return;

      final picked = await PhotoCaptureService.instance.captureAndCrop(
        source: source,
        context: context,
        title: isAnswerKey ? 'উত্তরপত্র কেটে নিন' : 'প্রশ্নের অংশ কেটে নিন',
      );
      if (picked != null && mounted) {
        setState(() {
          if (isAnswerKey) {
            _answerKeyImage = picked;
          } else {
            _questionImages.add(picked);
          }
          _result = null;
          _errorMessage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'ছবি লোড করা যায়নি: $e');
      }
    }
  }

  int? _liveTokens;

  /// Characters of the reply received so far.
  ///
  /// The only figure that moves while the page is being read: the model sends
  /// no chunk at all until it stops reasoning, and every chunk after that
  /// carries text.
  int? _liveChars;

  /// How many pages have been read into this set so far.
  ///
  /// A full model test rarely fits on one page, and scanning the second one
  /// used to replace the first: the questions list was rebuilt from each
  /// reply, so a fifty-question test came out as whatever was on the last
  /// page photographed.
  int _pagesScanned = 0;

  Future<void> _scanQuestionBank({bool append = false}) async {
    if (_questionImages.isEmpty) return;

    setState(() {
      _isScanning = true;
      _liveTokens = null;
      _liveChars = null;
      _crossCheckUnavailable = false;
      _errorMessage = null;
      if (!append) {
        _result = null;
        _pagesScanned = 0;
        _verifications.clear();
        _verifyingIndices.clear();
      }
    });

    final pagesToScan = append
        ? [_questionImages.last]
        : List<File>.from(_questionImages);
    final totalPages = pagesToScan.length;

    try {
      int totalSpentTokens = 0;
      int newlyAdded = 0;
      int duplicatesTotal = 0;

      for (int i = 0; i < totalPages; i++) {
        if (!mounted || !_isScanning) break;
        final currentFile = pagesToScan[i];

        setState(() {
          _currentScanningPageIndex = i + 1;
          _totalScanningPages = totalPages;
        });

        final res = await QuestionBankOcrService.instance.extractQuestionBank(
          // The model's own running figure, replacing the estimate as soon as
          // the first chunk reports one.
          onTokens: (soFar) {
            if (mounted) setState(() => _liveTokens = soFar);
          },
          onChars: (soFar) {
            if (mounted) setState(() => _liveChars = soFar);
          },
          questionImage: currentFile,
          answerKeyImage: _answerKeyImage, // Shared across ALL pages!
          subjectHint: _selectedSubject,
          detail: _detail,
          trustPrintedAnswersOnly: _trustPrintedAnswersOnly,
          withExplanations: _withExplanations,
        );

        final spent = QuestionBankOcrService.instance.lastCallTokens ?? 0;
        totalSpentTokens += spent;

        // The same page read again, for the answers alone. A disagreement
        // clears the answer and hands the question back with both letters
        // shown; neither reading has a claim to be the right one.
        var pageQuestions = res.questions;
        if (_crossCheckAnswers) {
          if (mounted) {
            setState(() {
              _liveChars = null;
              _liveTokens = null;
            });
          }
          final secondRead = await QuestionBankOcrService.instance
              .readPrintedAnswers(
                questionImage: currentFile,
                answerKeyImage: _answerKeyImage,
                detail: _detail,
              );
          if (secondRead == null || secondRead.isEmpty) {
            // Not checked is not the same as checked and agreed, and the
            // answers are left alone rather than thrown away for what may be
            // a network fault.
            if (mounted) setState(() => _crossCheckUnavailable = true);
          } else {
            pageQuestions = crossCheckAnswers(pageQuestions, secondRead);
          }
        }

        final merge = mergeScannedPage(
          existing: _editableQuestions,
          fromPage: pageQuestions,
        );
        newlyAdded += merge.added;
        duplicatesTotal += merge.duplicates;

        if (mounted) {
          setState(() {
            _result = res;
            _editableQuestions = merge.questions;
            if (_titleController.text.trim().isEmpty) {
              _titleController.text = res.title;
            }
            _pagesScanned += 1;
          });
        }
      }

      if (mounted) {
        setState(() {
          _isScanning = false;
          _savedToRoutine = false;
        });
        if (totalSpentTokens > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                append
                    ? 'পাতা $_pagesScanned — $newlyAdded টি নতুন প্রশ্ন যোগ হলো'
                          '${duplicatesTotal > 0 ? ', $duplicatesTotal টি আগেই ছিল' : ''}'
                          ' · মোট ${_editableQuestions.length}টি · $totalSpentTokens টোকেন'
                    : '$newlyAdded টি প্রশ্ন — $totalSpentTokens টোকেন খরচ হয়েছে',
              ),
            ),
          );
        }
      }
    } on QuestionBankExtractException catch (e) {
      // Already phrased for the user, and says what to do next.
      debugPrint('Question bank scan failed: $e');
      if (mounted) {
        setState(() {
          _isScanning = false;
          _errorMessage = e.userMessage;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _errorMessage = 'স্ক্যান করার সময় সমস্যা হয়েছে: $e';
        });
      }
    }
  }

  bool _hasAnswerMarkersInPastedText() {
    final text = _pastedTextController.text.trim();
    if (text.isEmpty) return false;
    return RegExp(
      r'(?:(?:সঠিক\s*)?উত্তর|Ans(?:wer)?)\s*[\:\=\-]',
      caseSensitive: false,
    ).hasMatch(text);
  }

  Future<void> _processPastedText() async {
    final text = _pastedTextController.text.trim();
    if (text.isEmpty) return;

    final hasAnswers = _hasAnswerMarkersInPastedText();

    setState(() {
      _isScanning = true;
      _errorMessage = null;
      _currentScanningPageIndex = 1;
      _totalScanningPages = 1;
    });

    try {
      final res =
          await QuestionBankOcrService.instance.extractQuestionsFromText(
        rawText: text,
        subjectHint: _selectedSubject,
        forceAi: false,
        onTokens: (spent) {
          if (mounted) setState(() => _liveTokens = spent);
        },
      );

      final spent = QuestionBankOcrService.instance.lastCallTokens ?? 0;

      if (mounted) {
        final isAppending = _editableQuestions.isNotEmpty;
        final merge = mergeScannedPage(
          existing: _editableQuestions,
          fromPage: res.questions,
        );

        setState(() {
          _result = res;
          _editableQuestions = merge.questions;
          if (_titleController.text.trim().isEmpty) {
            _titleController.text = res.title;
          }
          _pagesScanned = isAppending ? _pagesScanned + 1 : 1;
          _isScanning = false;
          _savedToRoutine = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              !isAppending
                  ? '${merge.added}টি প্রশ্ন প্রসেস হয়েছে'
                      '${hasAnswers ? ' (সংযুক্ত উত্তরমালা থেকে)' : ' (উত্তর ও ব্যাখ্যা অনুপস্থিত)'}'
                      '${spent > 0 ? ' · $spent টোকেন' : ' (অফলাইন পার্স)'}'
                  : '${merge.added}টি নতুন প্রশ্ন যোগ হয়েছে'
                      '${merge.duplicates > 0 ? ' (${merge.duplicates}টি ডুপ্লিকেট বাদ)' : ''}'
                      ' · মোট ${_editableQuestions.length}টি প্রশ্ন',
            ),
          ),
        );
      }
    } on QuestionBankExtractException catch (e) {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _errorMessage = e.userMessage;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _errorMessage = 'টেক্সট প্রসেস করতে সমস্যা হয়েছে: $e';
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
          'প্রশ্ন ${qIndex + 1}-এর সঠিক উত্তর "${(correctIndex >= 0 && correctIndex < currentQ.options.length) ? currentQ.options[correctIndex] : ''}" হিসেবে ঠিক করা হয়েছে ✓',
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

  Future<void> _showPasteAnswerKeySheet() async {
    final textCtrl = TextEditingController();
    bool applyToUnansweredOnly = false;
    final unsolvedCount =
        _editableQuestions.where((q) => q.correctIndex < 0).length;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (sheetCtx, setSheetState) {
            return Container(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 16,
              ),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.paste_rounded,
                        color: Color(0xFF4F46E5),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '📋 উত্তরমালা পেস্ট করুন (Paste Answer Key)',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'পাঠ্যবই, টেস্ট পেপারের সমাধান অংশ বা বাইরের AI Agent থেকে উত্তরমালা পেস্ট করুন। অ্যাপ স্বয়ংক্রিয়ভাবে প্রশ্নের নম্বরের সাথে অপশন মিলিয়ে দেবে।\nযেমন:\n১. খ, ২. ঘ, ৩. ক\nঅথবা:\n1. B, 2. D, 3. A',
                    style: TextStyle(
                      fontSize: 11.5,
                      color:
                          isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Stack(
                    children: [
                      TextField(
                        controller: textCtrl,
                        maxLines: 5,
                        minLines: 3,
                        style: const TextStyle(fontSize: 12.5),
                        decoration: InputDecoration(
                          hintText: '১. খ, ২. ঘ, ৩. ক... অথবা B, D, A, C',
                          hintStyle: TextStyle(
                            fontSize: 11.5,
                            color: isDark
                                ? Colors.grey.shade500
                                : Colors.grey.shade400,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                        onChanged: (_) => setSheetState(() {}),
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final data =
                                await Clipboard.getData('text/plain');
                            if (data?.text != null && data!.text!.isNotEmpty) {
                              setSheetState(() => textCtrl.text = data.text!);
                            }
                          },
                          icon: const Icon(Icons.paste, size: 12),
                          label: const Text(
                            'পেস্ট',
                            style: TextStyle(fontSize: 11),
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (unsolvedCount > 0) ...[
                    const SizedBox(height: 6),
                    CheckboxListTile(
                      value: applyToUnansweredOnly,
                      onChanged: (val) => setSheetState(
                        () => applyToUnansweredOnly = val ?? false,
                      ),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'শুধুমাত্র অনুত্তরিত $unsolvedCountটি প্রশ্নে ক্রমানুসারে বসান',
                        style: const TextStyle(fontSize: 12),
                      ),
                      subtitle: const Text(
                        'অন থাকলে পূর্বে উত্তর দেওয়া প্রশ্নগুলোর মান পরিবর্তন হবে না',
                        style: TextStyle(fontSize: 10.5, color: Colors.grey),
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ],
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    onPressed: textCtrl.text.trim().isEmpty
                        ? null
                        : () {
                            final keyMap = QuestionTextParser.parseAnswerKey(
                              textCtrl.text,
                            );
                            if (keyMap.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'উত্তরমালা থেকে কোনো প্রশ্নের উত্তর সনাক্ত করা যায়নি।',
                                  ),
                                ),
                              );
                              return;
                            }
                            int updatedCount = 0;
                            setState(() {
                              if (applyToUnansweredOnly) {
                                final unanswered = <int>[];
                                for (
                                  int i = 0;
                                  i < _editableQuestions.length;
                                  i++
                                ) {
                                  if (_editableQuestions[i].correctIndex < 0) {
                                    unanswered.add(i);
                                  }
                                }
                                int u = 0;
                                for (final optIdx in keyMap.values) {
                                  if (u >= unanswered.length) break;
                                  final qIdx = unanswered[u++];
                                  final q = _editableQuestions[qIdx];
                                  if (optIdx >= 0 &&
                                      optIdx < q.options.length) {
                                    _editableQuestions[qIdx] = q.copyWith(
                                      correctIndex: optIdx,
                                      answerSource: AnswerSource.answerKey,
                                    );
                                    updatedCount++;
                                  }
                                }
                              } else {
                                for (final entry in keyMap.entries) {
                                  final qIdx = entry.key;
                                  final optIdx = entry.value;
                                  if (qIdx >= 0 &&
                                      qIdx < _editableQuestions.length) {
                                    final q = _editableQuestions[qIdx];
                                    if (optIdx >= 0 &&
                                        optIdx < q.options.length) {
                                      _editableQuestions[qIdx] = q.copyWith(
                                        correctIndex: optIdx,
                                        answerSource: AnswerSource.answerKey,
                                      );
                                      updatedCount++;
                                    }
                                  }
                                }
                              }
                              _savedToRoutine = false;
                            });
                            Navigator.of(ctx).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '$updatedCountটি প্রশ্নের উত্তর সফলভাবে যুক্ত হয়েছে! ✓',
                                ),
                              ),
                            );
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text(
                      'উত্তরমালা প্রয়োগ করুন (Apply)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showAddMoreTextSheet() async {
    final textCtrl = TextEditingController();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (sheetCtx, setSheetState) {
            return Container(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 16,
              ),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.note_add_outlined,
                        color: Color(0xFF4F46E5),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'আরও প্রশ্ন যোগ করুন (পেস্ট)',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'বর্তমান ${_editableQuestions.length}টি প্রশ্নের সাথে আরও নতুন প্রশ্ন যোগ করতে টেক্সটবুক বা AI এজেন্ট থেকে কপি করা MCQ পেস্ট করুন:',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Stack(
                    children: [
                      TextField(
                        controller: textCtrl,
                        maxLines: 6,
                        minLines: 3,
                        style: const TextStyle(fontSize: 12.5),
                        decoration: InputDecoration(
                          hintText: '১. প্রশ্ন...\nক) অপশন ১\nখ) অপশন ২...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          contentPadding: const EdgeInsets.all(10),
                        ),
                        onChanged: (_) => setSheetState(() {}),
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final data = await Clipboard.getData('text/plain');
                            if (data?.text != null && data!.text!.isNotEmpty) {
                              setSheetState(() => textCtrl.text = data.text!);
                            }
                          },
                          icon: const Icon(Icons.paste, size: 12),
                          label: const Text('পেস্ট', style: TextStyle(fontSize: 11)),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: textCtrl.text.trim().isEmpty
                        ? null
                        : () async {
                            final raw = textCtrl.text.trim();
                            if (raw.isEmpty) return;
                            Navigator.of(ctx).pop();
                            _pastedTextController.text = raw;
                            await _processPastedText();
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text(
                      'প্রশ্নে যুক্ত করুন (+ Merge)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showVoiceAnswerSheet(int qIndex) async {
    if (qIndex < 0 || qIndex >= _editableQuestions.length) return;
    final q = _editableQuestions[qIndex];

    int selectedOptIndex = q.correctIndex;
    final explanationCtrl = TextEditingController(text: q.explanation);
    bool isListening = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (sheetCtx, setSheetState) {
            void onSpeechResult(String recognizedWords, bool isFinal) {
              setSheetState(() {
                final lower = recognizedWords.toLowerCase();
                for (int i = 0; i < q.options.length; i++) {
                  final letterBn =
                      i == 0 ? 'ক' : (i == 1 ? 'খ' : (i == 2 ? 'গ' : 'ঘ'));
                  final letterEn =
                      i == 0 ? 'a' : (i == 1 ? 'b' : (i == 2 ? 'c' : 'd'));
                  if (lower.contains('উত্তর $letterBn') ||
                      lower.contains('উত্তর $letterEn') ||
                      lower.contains('অপশন $letterBn') ||
                      lower.contains('অপশন ${i + 1}') ||
                      lower.startsWith(letterBn) ||
                      lower.startsWith(letterEn)) {
                    selectedOptIndex = i;
                    break;
                  }
                }
                explanationCtrl.text = recognizedWords;
              });
            }

            return Container(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 16,
              ),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.mic, color: Color(0xFF4F46E5), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'প্রশ্ন #${qIndex + 1} - ভয়েস ইনপুট',
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          if (isListening) {
                            DeviceDictationService.instance.stop();
                          }
                          Navigator.of(ctx).pop();
                        },
                      ),
                    ],
                  ),
                  Text(
                    q.questionText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'সঠিক অপশনটি সিলেক্ট করুন বা মুখে বলুন:',
                    style: TextStyle(fontSize: 11.5),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: List.generate(q.options.length, (optIdx) {
                      final isSelected = selectedOptIndex == optIdx;
                      final prefix = optIdx == 0
                          ? 'ক'
                          : (optIdx == 1 ? 'খ' : (optIdx == 2 ? 'গ' : 'ঘ'));
                      return ChoiceChip(
                        label: Text(
                          '$prefix. ${q.options[optIdx]}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11),
                        ),
                        selected: isSelected,
                        selectedColor: Colors.green.shade100,
                        onSelected: (_) => setSheetState(
                          () => selectedOptIndex = optIdx,
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: explanationCtrl,
                    maxLines: 3,
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      labelText: 'ব্যাখ্যা (মুখে বলুন বা লিখুন)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.all(10),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            if (isListening) {
                              await DeviceDictationService.instance.stop();
                              setSheetState(() => isListening = false);
                            } else {
                              final ready =
                                  await DeviceDictationService.instance.init();
                              if (!ready) {
                                if (sheetCtx.mounted) {
                                  ScaffoldMessenger.of(sheetCtx).showSnackBar(
                                    const SnackBar(
                                      content: Text('মাইক্রোফোন চালু করা যায়নি।'),
                                    ),
                                  );
                                }
                                return;
                              }
                              setSheetState(() => isListening = true);
                              await DeviceDictationService.instance.listen(
                                onResult: onSpeechResult,
                              );
                            }
                          },
                          icon: Icon(
                            isListening ? Icons.stop : Icons.mic,
                            color: isListening
                                ? Colors.red
                                : const Color(0xFF4F46E5),
                          ),
                          label: Text(
                            isListening ? 'রেকর্ডিং বন্ধ করুন' : '🎙️ মুখে বলুন',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: selectedOptIndex < 0
                              ? null
                              : () {
                                  if (isListening) {
                                    DeviceDictationService.instance.stop();
                                  }
                                  setState(() {
                                    _editableQuestions[qIndex] = q.copyWith(
                                      correctIndex: selectedOptIndex,
                                      explanation: explanationCtrl.text.trim(),
                                      answerSource: AnswerSource.solved,
                                    );
                                    _savedToRoutine = false;
                                  });
                                  Navigator.of(ctx).pop();
                                },
                          icon: const Icon(Icons.check, size: 16),
                          label: const Text('সংরক্ষণ'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _solveSingleQuestionWithAi(int qIndex) async {
    if (qIndex < 0 || qIndex >= _editableQuestions.length) return;
    final q = _editableQuestions[qIndex];

    setState(() {
      _verifyingIndices.add(qIndex);
    });

    try {
      final res = await QuestionBankOcrService.instance.verifyQuestion(
        question: q,
        subject: _selectedSubject != 'Auto Detect'
            ? _selectedSubject
            : (_result?.subject ?? 'General'),
      );

      if (res != null && mounted) {
        setState(() {
          _editableQuestions[qIndex] = q.copyWith(
            correctIndex: res.trueCorrectIndex >= 0 ? res.trueCorrectIndex : 0,
            explanation:
                res.explanation.isNotEmpty ? res.explanation : q.explanation,
            answerSource: AnswerSource.solved,
          );
          _verifications[qIndex] = res;
          _savedToRoutine = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'প্রশ্ন #${qIndex + 1} এর উত্তর ও ব্যাখ্যা AI দ্বারা সমাধান করা হয়েছে! ✓',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AI সমাধান করতে সমস্যা হয়েছে: $e')),
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

  Future<void> _solveAllUnsolvedWithAi() async {
    final unsolved = <int>[];
    for (int i = 0; i < _editableQuestions.length; i++) {
      if (_editableQuestions[i].correctIndex < 0 ||
          _editableQuestions[i].explanation.isEmpty) {
        unsolved.add(i);
      }
    }

    if (unsolved.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('সব প্রশ্নের উত্তর ইতোমধ্যে সেট করা আছে!')),
      );
      return;
    }

    setState(() {
      _isVerifyingAll = true;
    });

    int solvedCount = 0;
    try {
      for (final qIndex in unsolved) {
        if (!mounted || !_isVerifyingAll) break;
        final q = _editableQuestions[qIndex];
        final res = await QuestionBankOcrService.instance.verifyQuestion(
          question: q,
          subject: _selectedSubject != 'Auto Detect'
              ? _selectedSubject
              : (_result?.subject ?? 'General'),
        );
        if (res != null && mounted) {
          setState(() {
            _editableQuestions[qIndex] = q.copyWith(
              correctIndex: res.trueCorrectIndex >= 0 ? res.trueCorrectIndex : 0,
              explanation:
                  res.explanation.isNotEmpty ? res.explanation : q.explanation,
              answerSource: AnswerSource.solved,
            );
            _verifications[qIndex] = res;
          });
          solvedCount++;
        }
      }

      if (mounted) {
        setState(() {
          _isVerifyingAll = false;
          _savedToRoutine = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$solvedCountটি প্রশ্ন AI দ্বারা সফলভাবে সমাধান করা হয়েছে! ✓',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isVerifyingAll = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AI সমাধান করার সময় সমস্যা হয়েছে: $e')),
        );
      }
    }
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

    final unsolvedIdx =
        _editableQuestions.indexWhere((q) => q.correctIndex < 0);
    if (unsolvedIdx >= 0) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.amber),
              SizedBox(width: 8),
              Text('উত্তরবিহীন প্রশ্ন রয়েছে', style: TextStyle(fontSize: 16)),
            ],
          ),
          content: Text(
            'প্রশ্ন #${unsolvedIdx + 1} সহ কিছু প্রশ্নের কোনো সঠিক উত্তর নির্বাচন করা হয়নি।\n\n'
            'পরীক্ষা শুরু করার আগে দয়া করে অপশনে ট্যাপ করে উত্তর সেট করুন, উত্তরমালা পেস্ট করুন, অথবা "AI সমাধান" বাটনে চাপ দিন।',
            style: const TextStyle(fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('ঠিক আছে'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _solveAllUnsolvedWithAi();
              },
              child: const Text('AI দিয়ে সমাধান করুন'),
            ),
          ],
        ),
      );
      return;
    }

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
          // A missing key is not a failure to report; it is a thing to go and
          // do, so it gets the way there rather than red text.
          if (_errorMessage != null &&
              AiKeyMissingNotice.looksLikeKeyProblem(_errorMessage!))
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: AiKeyMissingNotice(
                message: _errorMessage!,
                onRetry: () {
                  if (mounted) setState(() => _errorMessage = null);
                },
              ),
            )
          else if (_errorMessage != null)
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

          // Mode Switcher: 📷 বইয়ের পাতা স্ক্যান vs 📋 টেক্সট পেস্ট (বাইরের AI / চ্যাট)
          _buildInputModeSelector(isDark),

          const SizedBox(height: 14),

          if (_inputMode == ScannerInputMode.imageOcr) ...[
            // 1. Question Pages Section
            _buildQuestionPagesSection(isDark),

            const SizedBox(height: 14),

            // 2. Answer Key Card (Optional)
            _buildImageCard(
              title: '২. উত্তরপত্রের ছবি (ঐচ্ছিক)',
              subtitle: 'বইয়ের শেষে থাকা সংক্ষিপ্ত উত্তরমালা (১টি ছবিতেই ১-২০০ সব উত্তর থাকলে সেটিই সব পাতার জন্য ব্যবহৃত হবে)',
              imageFile: _answerKeyImage,
              isAnswerKey: true,
              isDark: isDark,
            ),
          ] else ...[
            // Text Paste Section
            _buildTextPasteSection(isDark),
          ],

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

          if (_inputMode == ScannerInputMode.imageOcr) ...[
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
                  onSelected: (_) {
                    setState(() => _detail = d);
                    _rememberScanPreferences();
                  },
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

            const SizedBox(height: 10),
            _ScanToggle(
              value: _trustPrintedAnswersOnly,
              onChanged: (v) {
                setState(() => _trustPrintedAnswersOnly = v);
                _rememberScanPreferences();
              },
              isDark: isDark,
              title: 'শুধু বইয়ের ছাপা উত্তর নেবে',
              subtitle: _trustPrintedAnswersOnly
                  ? 'ছাপা উত্তর না থাকলে ফাঁকা রাখবে — AI অনুমান করবে না'
                  : 'ছাপা উত্তর না থাকলে AI নিজে বের করার চেষ্টা করবে',
            ),
            _ScanToggle(
              value: _crossCheckAnswers,
              onChanged: (v) {
                setState(() => _crossCheckAnswers = v);
                _rememberScanPreferences();
              },
              isDark: isDark,
              title: 'উত্তর দুইবার মিলিয়ে নেবে',
              subtitle: _crossCheckAnswers
                  ? 'দুই পাঠে না মিললে ফাঁকা রেখে চিহ্ন দেবে — আপনি ঠিক করবেন'
                  : 'একবারই পড়বে — ভুল পড়া উত্তর ধরা পড়বে না',
            ),
            _ScanToggle(
              value: _withExplanations,
              onChanged: (v) {
                setState(() => _withExplanations = v);
                _rememberScanPreferences();
              },
              isDark: isDark,
              title: 'ব্যাখ্যাও লিখিয়ে নেবে',
              subtitle: _withExplanations
                  ? 'পাতায় ব্যাখ্যা না থাকলে AI লিখে দেবে — স্ক্যান ধীর হবে'
                  : 'পাতায় যা ছাপা আছে শুধু তাই — পরে প্রশ্নভেদে চাওয়া যাবে',
            ),
          ],

          const SizedBox(height: 24),

          // Action Button
          if (_inputMode == ScannerInputMode.imageOcr)
            ElevatedButton.icon(
              onPressed: _questionImages.isEmpty ? null : _scanQuestionBank,
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
              label: Text(
                _questionImages.length > 1
                    ? '⚡ ${_questionImages.length}টি পাতা স্ক্যান করুন (Extract MCQs)'
                    : '⚡ প্রশ্ন ব্যাংক স্ক্যান করুন (Extract MCQs)',
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
              ),
            )
          else
            ElevatedButton.icon(
              onPressed: _pastedTextController.text.trim().isEmpty
                  ? null
                  : _processPastedText,
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
              label: Text(
                _editableQuestions.isNotEmpty
                    ? '⚡ বিদ্যমান প্রশ্নে যোগ করুন (+${_editableQuestions.length}টি বর্তমান)'
                    : '⚡ টেক্সট থেকে কুইজ তৈরি করুন (Extract MCQs)',
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInputModeSelector(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _inputMode = ScannerInputMode.imageOcr),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                decoration: BoxDecoration(
                  color: _inputMode == ScannerInputMode.imageOcr
                      ? const Color(0xFF4F46E5)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.camera_alt_outlined,
                      size: 15,
                      color: _inputMode == ScannerInputMode.imageOcr
                          ? Colors.white
                          : (isDark ? Colors.grey.shade400 : Colors.grey.shade700),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'পাতার ছবি স্ক্যান',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: _inputMode == ScannerInputMode.imageOcr
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: _inputMode == ScannerInputMode.imageOcr
                              ? Colors.white
                              : (isDark ? Colors.grey.shade400 : Colors.grey.shade700),
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
              onTap: () => setState(() => _inputMode = ScannerInputMode.textPaste),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                decoration: BoxDecoration(
                  color: _inputMode == ScannerInputMode.textPaste
                      ? const Color(0xFF4F46E5)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.content_paste_rounded,
                      size: 15,
                      color: _inputMode == ScannerInputMode.textPaste
                          ? Colors.white
                          : (isDark ? Colors.grey.shade400 : Colors.grey.shade700),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'টেক্সট পেস্ট (AI/নোট)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: _inputMode == ScannerInputMode.textPaste
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: _inputMode == ScannerInputMode.textPaste
                              ? Colors.white
                              : (isDark ? Colors.grey.shade400 : Colors.grey.shade700),
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
    );
  }

  Widget _buildTextPasteSection(bool isDark) {
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
              const Icon(
                Icons.smart_toy_outlined,
                size: 18,
                color: Color(0xFF4F46E5),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'বাইরের Agent / চ্যাট থেকে কপি করা টেক্সট',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (_pastedTextController.text.isNotEmpty)
                IconButton(
                  icon: const Icon(
                    Icons.clear,
                    size: 18,
                    color: Colors.red,
                  ),
                  tooltip: 'মুছুন',
                  onPressed: () => setState(() => _pastedTextController.clear()),
                ),
            ],
          ),
          Text(
            'ChatGPT, Claude বা নোট থেকে MCQ প্রশ্ন পেস্ট করুন (স্বয়ংক্রিয়ভাবে প্রশ্ন, অপশন ও উত্তর সাজিয়ে নেবে)',
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white60 : Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 12),
          Stack(
            children: [
              TextField(
                controller: _pastedTextController,
                maxLines: 8,
                minLines: 5,
                style: const TextStyle(fontSize: 12.5, height: 1.45),
                decoration: InputDecoration(
                  hintText: 'এখানে টেক্সট পেস্ট করুন...\n\nযেমন:\n১. বাংলাদেশের প্রথম রাষ্ট্রপতি কে ছিলেন?\nক) বঙ্গবন্ধু শেখ মুজিবুর রহমান\nখ) সৈয়দ নজরুল ইসলাম\nগ) তাজউদ্দীন আহমদ\nঘ) খন্দকার মোশতাক আহমদ\nউত্তর: ক\nব্যাখ্যা: বঙ্গবন্ধু শেখ মুজিবুর রহমান ছিলেন...',
                  hintStyle: TextStyle(
                    fontSize: 11.5,
                    color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                  ),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF111827) : Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: Color(0xFF4F46E5),
                      width: 1.5,
                    ),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
                onChanged: (_) => setState(() {}),
              ),
              Positioned(
                bottom: 8,
                right: 8,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _pastedTextController.text =
                              '১. বাংলাদেশের প্রথম রাষ্ট্রপতি কে ছিলেন?\n'
                              'ক) বঙ্গবন্ধু শেখ মুজিবুর রহমান\n'
                              'খ) সৈয়দ নজরুল ইসলাম\n'
                              'গ) তাজউদ্দীন আহমদ\n'
                              'ঘ) খন্দকার মোশতাক আহমদ\n'
                              'উত্তর: ক\n'
                              'ব্যাখ্যা: ১৯৭১ সালের ১০ এপ্রিল গঠিত মুজিবনগর সরকারের রাষ্ট্রপতি ছিলেন বঙ্গবন্ধু শেখ মুজিবুর রহমান।\n\n'
                              '২. "সূর্য" শব্দের সমার্থক শব্দ কোনটি?\n'
                              'ক) সুধাকর\n'
                              'খ) তপন\n'
                              'গ) শশাঙ্ক\n'
                              'ঘ) বিধু\n'
                              'উত্তর: খ\n'
                              'ব্যাখ্যা: তপন শব্দের অর্থ সূর্য; সুধাকর ও বিধু শব্দের অর্থ চাঁদ।';
                        });
                      },
                      icon: const Icon(Icons.lightbulb_outline, size: 14),
                      label: const Text('নমুনা ফরম্যাট', style: TextStyle(fontSize: 11)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(width: 4),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final data = await Clipboard.getData('text/plain');
                        if (data?.text != null && data!.text!.isNotEmpty) {
                          setState(() {
                            _pastedTextController.text = data.text!;
                          });
                        }
                      },
                      icon: const Icon(Icons.paste, size: 13),
                      label: const Text('ক্লিপবোর্ড থেকে পেস্ট', style: TextStyle(fontSize: 11)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4F46E5),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_pastedTextController.text.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _hasAnswerMarkersInPastedText()
                    ? Colors.green.withValues(alpha: 0.1)
                    : const Color(0xFF4F46E5).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _hasAnswerMarkersInPastedText()
                      ? Colors.green.withValues(alpha: 0.3)
                      : const Color(0xFF4F46E5).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _hasAnswerMarkersInPastedText()
                        ? Icons.check_circle_outline
                        : Icons.auto_awesome,
                    size: 14,
                    color: _hasAnswerMarkersInPastedText()
                        ? Colors.green
                        : const Color(0xFF4F46E5),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _hasAnswerMarkersInPastedText()
                          ? 'উত্তরমালা পাওয়া গেছে (তাৎক্ষণিক পার্স হবে)'
                          : 'উত্তর ও ব্যাখ্যা অনুপস্থিত (রিভিউ স্ক্রিনে উত্তরমালা পেস্ট, ভয়েস বা AI দিয়ে সহজে সমাধান করতে পারবেন)',
                      style: TextStyle(
                        fontSize: 11,
                        color: _hasAnswerMarkersInPastedText()
                            ? (isDark
                                ? Colors.green.shade300
                                : Colors.green.shade800)
                            : (isDark
                                ? const Color(0xFF818CF8)
                                : const Color(0xFF4338CA)),
                        fontWeight: FontWeight.w500,
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

  Widget _buildQuestionPagesSection(bool isDark) {
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
              const Icon(
                Icons.menu_book,
                size: 18,
                color: Color(0xFF4F46E5),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '১. প্রশ্ন পাতার ছবি (আবশ্যক)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (_questionImages.isNotEmpty)
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: Colors.red,
                  ),
                  tooltip: 'সব পাতা মুছুন',
                  onPressed: () => setState(() {
                    _questionImages.clear();
                    _result = null;
                    _errorMessage = null;
                  }),
                ),
            ],
          ),
          Text(
            _questionImages.isEmpty
                ? 'বইয়ের যে পাতায় MCQ প্রশ্নগুলো ছাপা আছে (একাধিক পাতাও যোগ করতে পারেন)'
                : 'মোট ${_questionImages.length}টি প্রশ্ন পাতা যুক্ত হয়েছে',
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white60 : Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 10),
          if (_questionImages.isEmpty)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(
                      ImageSource.camera,
                      isAnswerKey: false,
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
                      isAnswerKey: false,
                    ),
                    icon: const Icon(Icons.photo_library, size: 16),
                    label: const Text(
                      'গ্যালারি (একাধিক)',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            )
          else ...[
            SizedBox(
              height: 130,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _questionImages.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final imgFile = _questionImages[index];
                  return Container(
                    width: 100,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: isDark ? Colors.black26 : Colors.grey.shade200,
                      border: Border.all(
                        color: isDark
                            ? Colors.grey.shade700
                            : Colors.grey.shade300,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(
                            imgFile,
                            key: ValueKey(imgFile.path),
                            fit: BoxFit.cover,
                          ),
                          Positioned(
                            top: 4,
                            left: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black87,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'পাতা ${index + 1}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 2,
                            right: 2,
                            child: CircleAvatar(
                              radius: 12,
                              backgroundColor:
                                  Colors.black.withValues(alpha: 0.65),
                              child: IconButton(
                                tooltip: 'পাতা মুছুন',
                                icon: const Icon(
                                  Icons.close,
                                  size: 13,
                                  color: Colors.white,
                                ),
                                padding: EdgeInsets.zero,
                                onPressed: () => setState(() {
                                  _questionImages.removeAt(index);
                                  _result = null;
                                  _errorMessage = null;
                                }),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 4,
                            right: 4,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircleAvatar(
                                  radius: 12,
                                  backgroundColor:
                                      Colors.black.withValues(alpha: 0.65),
                                  child: IconButton(
                                    tooltip: 'সোজা করুন',
                                    icon: const Icon(
                                      Icons.rotate_90_degrees_cw_rounded,
                                      size: 13,
                                      color: Colors.white,
                                    ),
                                    padding: EdgeInsets.zero,
                                    onPressed: () => _rotate(
                                      isAnswerKey: false,
                                      pageIndex: index,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                CircleAvatar(
                                  radius: 12,
                                  backgroundColor:
                                      Colors.black.withValues(alpha: 0.65),
                                  child: IconButton(
                                    tooltip: 'কাটুন',
                                    icon: const Icon(
                                      Icons.crop_rounded,
                                      size: 13,
                                      color: Colors.white,
                                    ),
                                    padding: EdgeInsets.zero,
                                    onPressed: () => _recrop(
                                      isAnswerKey: false,
                                      pageIndex: index,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(
                      ImageSource.camera,
                      isAnswerKey: false,
                    ),
                    icon: const Icon(Icons.add_a_photo, size: 14),
                    label: const Text(
                      '+ ক্যামেরা পাতা',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(
                      ImageSource.gallery,
                      isAnswerKey: false,
                    ),
                    icon: const Icon(Icons.add_photo_alternate, size: 14),
                    label: const Text(
                      '+ গ্যালারি পাতা',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
          ],
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
                      _questionImages.clear();
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
                  // contain, not cover: a page turned on its side must
                  // stay whole here rather than having its edges cut off.
                  Container(
                    height: 120,
                    width: double.infinity,
                    color: isDark ? Colors.black26 : Colors.grey.shade200,
                    child: Image.file(
                      imageFile,
                      key: ValueKey(imageFile.path),
                      fit: BoxFit.contain,
                    ),
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
                  // A scan that comes back short is usually fixed by taking
                  // a narrower part of the same photo, so the trim reopens
                  // rather than sending the user back to the camera.
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Row(
                      children: [
                        // A book shot sideways needs the whole page turned,
                        // not the crop frame tilted.
                        CircleAvatar(
                          radius: 15,
                          backgroundColor: Colors.black.withValues(alpha: 0.65),
                          child: IconButton(
                            tooltip: 'ঘুরিয়ে সোজা করুন',
                            icon: const Icon(
                              Icons.rotate_90_degrees_cw_rounded,
                              size: 15,
                              color: Colors.white,
                            ),
                            padding: EdgeInsets.zero,
                            onPressed: () => _rotate(isAnswerKey: isAnswerKey),
                          ),
                        ),
                        const SizedBox(width: 6),
                        CircleAvatar(
                          radius: 15,
                          backgroundColor: Colors.black.withValues(alpha: 0.65),
                          child: IconButton(
                            tooltip: 'আবার কাটুন',
                            icon: const Icon(
                              Icons.crop_rounded,
                              size: 15,
                              color: Colors.white,
                            ),
                            padding: EdgeInsets.zero,
                            onPressed: () => _recrop(isAnswerKey: isAnswerKey),
                          ),
                        ),
                      ],
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_inputMode == ScannerInputMode.textPaste)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF4F46E5).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFF4F46E5).withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF4F46E5),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _hasAnswerMarkersInPastedText()
                      ? 'টেক্সট প্রসেস ও কুইজ সাজানো হচ্ছে...'
                      : 'AI প্রশ্নগুলো সমাধান করছে ও সঠিক উত্তর বের করছে...',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF4F46E5),
                  ),
                ),
              ],
            ),
          )
        else if (_totalScanningPages > 1)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF4F46E5).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFF4F46E5).withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF4F46E5),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'পাতা $_currentScanningPageIndex / $_totalScanningPages স্ক্যান হচ্ছে...',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF4F46E5),
                  ),
                ),
              ],
            ),
          ),
        AiProgressPipelineWidget(
          type: _inputMode == ScannerInputMode.textPaste
              ? AiTaskType.general
              : AiTaskType.image,
          isCompact: false,
          // The real figure only. It used to be the estimate until the first
          // chunk arrived, which meant the badge opened on a large static
          // number and sat there for the whole reasoning stretch — the part of
          // the wait the user most needs reassuring about — and then jumped,
          // sometimes downwards. The estimate goes in its own slot now and is
          // shown with a `~` until there is something real to replace it.
          liveTokens: _liveTokens,
          liveChars: _liveChars,
          estimatedTokens: _inputMode == ScannerInputMode.textPaste
              ? 800
              : QuestionBankOcrService.instance.estimateTokensFor(
                  _detail,
                  pages:
                      (_answerKeyImage == null ? 1 : 2) *
                      (_totalScanningPages > 0 ? _totalScanningPages : 1),
                ),
          onCancel: () {
            if (mounted) {
              setState(() {
                _isScanning = false;
              });
            }
          },
        ),
      ],
    );
  }

  // ========================================================
  // REVIEW & START EXAM STATE
  // ========================================================
  /// The scan's own figures, as a row of chips that also filter the list.
  ///
  /// Always here once there are questions, which is the point: the screen used
  /// to show only what the optional AI verification had found, so a set nobody
  /// had verified looked perfect however much of it could not be read. These
  /// come from the scan itself and are there the moment the page comes back.
  Widget _buildTallyStrip(
    ScanTally tally,
    int warningCount,
    int verifiedCount,
    bool isDark,
  ) {
    Widget chip(
      ReviewFilter filter,
      String label,
      int count,
      Color colour, {
      bool alwaysShow = false,
    }) {
      if (count == 0 && !alwaysShow) return const SizedBox.shrink();
      final selected = _filter == filter;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(
            '$label ($count)',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: selected ? null : colour,
            ),
          ),
          selected: selected,
          selectedColor: colour.withValues(alpha: isDark ? 0.32 : 0.18),
          visualDensity: VisualDensity.compact,
          // Tapping a count takes the reader to the questions it counted,
          // which is the only reason to show a count on a screen like this.
          onSelected: (_) => setState(
            () => _filter = selected ? ReviewFilter.all : filter,
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip(
            ReviewFilter.all,
            'সব',
            tally.total,
            isDark ? Colors.white70 : Colors.black87,
            alwaysShow: true,
          ),
          chip(
            ReviewFilter.noAnswer,
            '⚠️ উত্তর নেই',
            tally.noAnswer,
            Colors.amber.shade800,
          ),
          chip(
            ReviewFilter.answersDisagree,
            '✕ দুই পাঠে মেলেনি',
            tally.disagreed,
            Colors.deepOrange.shade700,
          ),
          chip(
            ReviewFilter.unreadable,
            '👁 পড়া যায়নি',
            tally.unreadable,
            Colors.red.shade700,
          ),
          chip(
            ReviewFilter.aiWarning,
            '⚠️ অসঙ্গতি',
            warningCount,
            Colors.amber.shade900,
          ),
          chip(
            ReviewFilter.aiVerified,
            '✓ যাচাই হয়েছে',
            verifiedCount,
            Colors.green.shade800,
          ),
          chip(
            ReviewFilter.clean,
            '✓ ঠিক আছে',
            tally.clean,
            Colors.green.shade700,
          ),
        ],
      ),
    );
  }

  /// Whether a question belongs in the list under the filter now chosen.
  bool _passesFilter(QuizQuestion q, QuestionVerificationResult? v) {
    return switch (_filter) {
      ReviewFilter.all => true,
      ReviewFilter.noAnswer => !q.hasAnswer,
      ReviewFilter.answersDisagree => answersDisagree(q),
      ReviewFilter.unreadable => !q.legible,
      ReviewFilter.clean => !q.needsReview,
      ReviewFilter.aiWarning => v != null && (!v.isCorrect || v.isAmbiguous),
      ReviewFilter.aiVerified => v != null && v.isCorrect && !v.isAmbiguous,
    };
  }

  Widget _buildResultReviewState(bool isDark) {
    final verifiedCount = _verifications.values
        .where((v) => v.isCorrect && !v.isAmbiguous)
        .length;
    final warningCount = _verifications.values
        .where((v) => !v.isCorrect || v.isAmbiguous)
        .length;
    final tally = tallyScanIssues(_editableQuestions);
    final unsolvedCount = tally.noAnswer;

    return Column(
      children: [
        // Said plainly rather than left out: an unchecked answer looks exactly
        // like a confirmed one, and the whole point of the second read is that
        // the difference cannot be seen.
        if (_crossCheckUnavailable)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            color: Colors.orange.withValues(alpha: isDark ? 0.22 : 0.14),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 15,
                  color: Colors.orange.shade900,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'উত্তরগুলো দ্বিতীয়বার মিলিয়ে দেখা যায়নি — নিজে একবার দেখে নিন',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? Colors.orange.shade200
                          : Colors.orange.shade900,
                    ),
                  ),
                ),
              ],
            ),
          ),

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
              // A model test is usually spread over several pages, so adding
              // the next one is offered right where the first one lands.
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _pagesScanned > 1
                          ? 'পাতা $_pagesScanned · মোট ${_editableQuestions.length}টি প্রশ্ন'
                          : '${_editableQuestions.length}টি প্রশ্ন',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _isScanning ? null : _addAnotherPage,
                    icon: const Icon(Icons.add_a_photo_outlined, size: 16),
                    label: const Text(
                      'আরেক পাতা',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    onPressed: _isScanning ? null : _showAddMoreTextSheet,
                    icon: const Icon(Icons.note_add_outlined, size: 16),
                    label: const Text(
                      '+ আরও পেস্ট',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
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
                  const SizedBox(width: 6),
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
                    icon: const Icon(Icons.paste_rounded, size: 13),
                    label: const Text(
                      'উত্তরমালা',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: _showPasteAnswerKeySheet,
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
              if (_editableQuestions.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildTallyStrip(tally, warningCount, verifiedCount, isDark),
              ],
              if (unsolvedCount > 0) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50.withValues(
                      alpha: isDark ? 0.15 : 1,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade600),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 16,
                            color: Colors.amber.shade800,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '$unsolvedCountটি প্রশ্নের কোনো উত্তর বা ব্যাখ্যা নেই!',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? Colors.amber.shade200
                                    : Colors.amber.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'নিচে অপশনে ট্যাপ করে নিজে উত্তর দিন, পাঠ্যবই/অন্য এজেন্ট থেকে উত্তরমালা পেস্ট করুন, অথবা অ্যাপের AI দিয়ে সমাধান নিন:',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: isDark
                              ? Colors.grey.shade300
                              : Colors.grey.shade800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4F46E5),
                              foregroundColor: Colors.white,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                            ),
                            icon: const Icon(Icons.paste_rounded, size: 13),
                            label: const Text(
                              '📋 উত্তরমালা পেস্ট করুন',
                              style: TextStyle(fontSize: 11),
                            ),
                            onPressed: _showPasteAnswerKeySheet,
                          ),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              foregroundColor: isDark
                                  ? const Color(0xFFA5B4FC)
                                  : const Color(0xFF4F46E5),
                            ),
                            icon: const Icon(Icons.auto_awesome, size: 13),
                            label: const Text(
                              '⚡ অ্যাপের AI দিয়ে সব সমাধান',
                              style: TextStyle(fontSize: 11),
                            ),
                            onPressed: _solveAllUnsolvedWithAi,
                          ),
                        ],
                      ),
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
              if (!_passesFilter(q, _verifications[i])) continue;
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
    return QuestionReviewCard(
      qIndex: qIndex,
      question: q,
      isDark: isDark,
      verification: _verifications[qIndex],
      isVerifying: _verifyingIndices.contains(qIndex),
      onEdit: () => _showEditQuestionDialog(qIndex),
      onDelete: () => _deleteQuestion(qIndex),
      onVerify: () => _verifySingleQuestion(qIndex),
      onSolveWithAi: () => _solveSingleQuestionWithAi(qIndex),
      onVoiceAnswer: () => _showVoiceAnswerSheet(qIndex),
      onApplyCorrection: (correctIndex) =>
          _applyCorrection(qIndex, correctIndex),
      onPickAnswer: (optIndex) {
        setState(() {
          _editableQuestions[qIndex] = q.copyWith(
            correctIndex: optIndex,
            answerSource: AnswerSource.solved,
          );
          _savedToRoutine = false;
        });
      },
    );
  }
}


/// One setting in the scanner, as a plain row.
///
/// Not a SwitchListTile: a ListTile paints onto the nearest Material ancestor,
/// and this sheet draws its own background over one, which Flutter asserts
/// about. A row of its own sidesteps that and matches the rest of the sheet.
class _ScanToggle extends StatelessWidget {
  const _ScanToggle({
    required this.value,
    required this.onChanged,
    required this.isDark,
    required this.title,
    required this.subtitle,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final bool isDark;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.3,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            onChanged: onChanged,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}
