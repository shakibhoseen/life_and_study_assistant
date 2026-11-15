import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../core/services/ai/claim_math_checker.dart';
import '../../../../core/services/ai/models/evidence_review.dart';
import '../../../../core/services/ai/models/mcq_verification.dart';
import '../../../../core/services/ai/models/verification_mark.dart';
import '../../../../core/services/ai/models/verification_result.dart';
import '../../../../core/services/ai/gemini_ai_service.dart';
import '../../../../core/theme/fluent_tokens.dart';
import '../../../../core/utils/bengali_math_sanitizer.dart';
import '../../../../core/widgets/ai_progress_pipeline_widget.dart';

/// The status palette for this feature. One value each, picked to stay
/// readable on both the light and the dark card surface.
const Color _correctColor = Color(0xFF10B981); // green — the right answer
const Color _wrongColor = Color(0xFFE11D48); // red — what was answered
const Color _hintColor = Color(0xFFD97706); // amber — caution / explanation

/// The dialog shape every confirm box in this sheet uses.
RoundedRectangleBorder get _dialogShape =>
    RoundedRectangleBorder(borderRadius: FluentRadius.cardBorder);

class AiMistakeExplainerSheet extends ConsumerStatefulWidget {
  final DrillQuestion question;

  const AiMistakeExplainerSheet({super.key, required this.question});

  static Future<void> show(BuildContext context, DrillQuestion question) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AiMistakeExplainerSheet(question: question),
    );
  }

  @override
  ConsumerState<AiMistakeExplainerSheet> createState() =>
      _AiMistakeExplainerSheetState();
}

class _AiMistakeExplainerSheetState
    extends ConsumerState<AiMistakeExplainerSheet> {
  bool _isLoading = true;
  String _explanation = '';
  bool _copied = false;

  // Verification is deliberately opt-in: it costs a call, and most of the
  // time the explanation is fine.
  McqVerification? _verification;
  bool _isVerifying = false;
  bool _verifyFailed = false;
  List<String> _options = const [];

  /// Set once the user accepts a proposal, so the sheet can say so without
  /// re-reading the row.
  bool _correctionAccepted = false;

  /// Set when the user dismisses or rejects a proposal to keep the saved answer.
  bool _proposalDismissed = false;

  /// Set when a correction showed the user had actually answered correctly.
  bool _nowScoredCorrect = false;

  /// Live copy of snapshot fields so corrections and reverts reflect immediately.
  int? _originalCorrectIndex;
  String? _originalExplanation;
  String? _originalQuestionText;
  List<String>? _originalOptions;
  DateTime? _correctedAt;

  /// Whether this answer is one the user settled themselves, by correcting it
  /// or by vouching for it. Their decision outranks a verifier's recall.
  bool get _userDecided =>
      _correctionAccepted ||
      _questionEdited ||
      _correctedAt != null ||
      _mark == VerificationMark.userVerified;

  // A verifier that cannot settle something is not the end of it: the user
  // knows things it does not, so they get to make the case themselves.
  final TextEditingController _evidenceController = TextEditingController();
  final ScrollController _bodyScroll = ScrollController();
  final FocusNode _evidenceFocus = FocusNode();
  bool _showEvidenceBox = false;
  bool _isReviewing = false;
  EvidenceReview? _review;
  bool _reviewFailed = false;
  bool _questionEdited = false;

  // Live copies of the question, so an edit shows up here without the sheet
  // having to be closed and reopened.
  late String _questionText;
  late int _correctIndex;
  late String _explanationText;

  // What the last check concluded, kept on the row so reopening the sheet
  // shows it instead of paying for the same call again.
  VerificationMark _mark = VerificationMark.none;
  String? _markNote;
  DateTime? _markedAt;

  @override
  void initState() {
    super.initState();
    final dq = widget.question;
    _questionText = dq.questionText;
    _correctIndex = dq.correctIndex;
    _explanationText = dq.explanation;
    _options = _decodeOptions(dq.optionsJson);
    _originalCorrectIndex = dq.originalCorrectIndex;
    _originalExplanation = dq.originalExplanation;
    _originalQuestionText = dq.originalQuestionText;
    _originalOptions = dq.originalOptionsJson != null
        ? _decodeOptions(dq.originalOptionsJson!)
        : null;
    _correctedAt = dq.correctedAt;
    _mark = VerificationMark.parse(dq.verificationStatus);
    _markNote = dq.verificationNote;
    _markedAt = dq.verifiedAt;
    _fetchExplanation();
  }

  @override
  void dispose() {
    _evidenceController.dispose();
    _bodyScroll.dispose();
    _evidenceFocus.dispose();
    super.dispose();
  }

  static List<String> _decodeOptions(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.map((e) => e.toString()).toList();
    } catch (_) {}
    return const [];
  }

  /// Rechecks the question against its own options, answer and explanation.
  ///
  /// Read-only by design: whatever comes back is shown, and nothing is
  /// written to the question, the mistake list or the review schedule.
  Future<void> _verify() async {
    if (_isVerifying) return;
    setState(() {
      _isVerifying = true;
      _verifyFailed = false;
      _proposalDismissed = false;
    });

    final dq = widget.question;
    final options = _options;

    // correctIndex and the explanation go to the service only so it can
    // compare and run the local check. Neither reaches the model's prompt.
    final result = await GeminiAiService.instance.verifyAnswer(
      subject: dq.subject,
      topic: dq.topic,
      questionText: _questionText,
      options: options,
      correctIndex: _correctIndex,
      selectedIndex: dq.selectedIndex,
      explanation: _explanationText,
      userDecided: _userDecided,
    );

    if (result == null) {
      debugPrint('MCQ verify: no usable solve returned');
    } else {
      debugPrint(
        'MCQ verify: ${result.verdict.name}'
        ' | stored=$_correctIndex solved=${result.solve.chosenIndex}'
        ' | ambiguity=${result.solve.ambiguity.name}'
        ' | proposal=${result.hasProposal}'
        ' | dissent=${result.dissentIndex ?? -1}'
        ' | evidence=${result.evidence.name}'
        ' | explanationCheck=${result.explanationCheck.outcome.name}',
      );
    }

    if (result != null) {
      // Recording what the check found is not the same as changing the
      // answer: nothing about the question moves here.
      final mark = result.hasProblem
          ? VerificationMark.flagged
          : (result.agrees ? VerificationMark.modelAgreed : null);
      if (mark != null) {
        await ref
            .read(appDatabaseProvider)
            .saveVerificationMark(
              dq.id,
              status: mark.storageKey,
              note: result.solve.reasoning,
            );
        if (mounted) {
          setState(() {
            _mark = mark;
            _markNote = result.solve.reasoning;
            _markedAt = DateTime.now();
          });
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _options = options;
      _verification = result;
      _verifyFailed = result == null;
      _isVerifying = false;
    });
  }

  /// Puts the user's own name to the answer.
  Future<void> _markVerifiedByUser() async {
    await ref
        .read(appDatabaseProvider)
        .saveVerificationMark(
          widget.question.id,
          status: VerificationMark.userVerified.storageKey,
          note: _verification?.solve.reasoning ?? _markNote,
        );
    if (!mounted) return;
    setState(() {
      _mark = VerificationMark.userVerified;
      _markedAt = DateTime.now();
    });
  }

  /// Writes the correction the user accepted.
  ///
  /// Only reached from an explicit tap; the attempt history is left alone by
  /// the database method itself.
  Future<void> _acceptCorrection(int proposedIndex) async {
    final dq = widget.question;
    final proposed = proposedIndex >= 0 && proposedIndex < _options.length
        ? _options[proposedIndex]
        : '';
    final reason = _verification?.solve.reasoning ?? '';

    await ref
        .read(appDatabaseProvider)
        .acceptAnswerCorrection(
          dq.id,
          correctedIndex: proposedIndex,
          // The replaced text is kept in originalExplanation, so repeating it
          // here only leaves its broken arithmetic to be re-flagged forever.
          correctedExplanation: 'সংশোধিত উত্তর: $proposed। $reason',
        );

    if (!mounted) return;
    setState(() {
      _originalCorrectIndex ??= _correctIndex;
      _originalExplanation ??= _explanationText;
      _correctedAt = DateTime.now();
      _correctionAccepted = true;
      _proposalDismissed = false;
      _correctIndex = proposedIndex;
      _nowScoredCorrect = widget.question.selectedIndex == proposedIndex;
    });
  }

  /// Restores the question to its original pre-correction state.
  Future<void> _revertCorrection() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: _dialogShape,
        title: Text(
          'পূর্বের অবস্থায় ফিরবেন?',
          style: FluentType.bodyStrong.copyWith(fontSize: 16),
        ),
        content: Text(
          'সংশোধনটি বাতিল করে প্রশ্ন এবং উত্তরকে এর মূল অবস্থায় ফিরিয়ে আনা হবে। আপনার পূর্বের প্রচেষ্টার ইতিহাস অপরিবর্তিত থাকবে।',
          style: FluentType.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('থাক'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: _wrongColor,
              shape: RoundedRectangleBorder(
                borderRadius: FluentRadius.controlBorder,
              ),
            ),
            child: const Text('হ্যাঁ, ফিরুন'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final db = ref.read(appDatabaseProvider);
    await db.revertAnswerCorrection(widget.question.id);

    final updated = await (db.select(
      db.drillQuestions,
    )..where((t) => t.id.equals(widget.question.id))).getSingleOrNull();

    if (!mounted) return;
    if (updated != null) {
      setState(() {
        _questionText = updated.questionText;
        _correctIndex = updated.correctIndex;
        _explanationText = updated.explanation;
        _options = _decodeOptions(updated.optionsJson);
        _originalCorrectIndex = updated.originalCorrectIndex;
        _originalExplanation = updated.originalExplanation;
        _originalQuestionText = updated.originalQuestionText;
        _originalOptions = updated.originalOptionsJson != null
            ? _decodeOptions(updated.originalOptionsJson!)
            : null;
        _correctedAt = updated.correctedAt;
        _correctionAccepted = false;
        _questionEdited = false;
        _nowScoredCorrect = updated.isCorrect;
        _verification = null;
        _proposalDismissed = false;
      });
    }
  }

  /// Removes a question that is broken beyond correcting.
  ///
  /// A question whose own options contradict each other was never a mistake
  /// of the user's, so leaving it in the notebook teaches nothing.
  Future<void> _deleteQuestion() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: _dialogShape,
        title: Text(
          'প্রশ্নটি সরাবেন?',
          style: FluentType.bodyStrong.copyWith(fontSize: 16),
        ),
        content: Text(
          'প্রশ্নটি ভুল নোটবুক থেকে স্থায়ীভাবে মুছে যাবে। এটি ফেরানো যাবে না।',
          style: FluentType.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('থাক'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: _wrongColor,
              shape: RoundedRectangleBorder(
                borderRadius: FluentRadius.controlBorder,
              ),
            ),
            child: const Text('মুছে ফেলুন'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await ref.read(appDatabaseProvider).deleteDrillQuestion(widget.question.id);
    if (mounted) Navigator.pop(context);
  }

  /// Opens the box and brings it above the keyboard.
  ///
  /// The field sits at the bottom of a long sheet, so without this it opens
  /// behind the keyboard that opening it summons.
  void _openEvidenceBox() {
    setState(() => _showEvidenceBox = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _evidenceFocus.requestFocus();
      if (_bodyScroll.hasClients) {
        _bodyScroll.animateTo(
          _bodyScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Sends the user's own argument back for a second look.
  ///
  /// This is the one call that does show the model the stored answer, because
  /// the user is asking it to judge that answer. Nothing it returns is saved
  /// on its own.
  Future<void> _submitEvidence() async {
    final evidence = _evidenceController.text.trim();
    if (evidence.isEmpty || _isReviewing) return;

    setState(() {
      _isReviewing = true;
      _reviewFailed = false;
      _review = null;
    });

    final dq = widget.question;
    final result = await GeminiAiService.instance.reviewWithUserEvidence(
      subject: dq.subject,
      topic: dq.topic,
      questionText: _questionText,
      options: _options,
      correctIndex: _correctIndex,
      explanation: _explanationText,
      userEvidence: evidence,
    );

    if (result != null) {
      debugPrint(
        'MCQ evidence review: ${result.verdict.name}'
        ' | flaw=${result.flaw.name}'
        ' | suggestedIndex=${result.suggestedCorrectIndex ?? -1}'
        ' | rewritesQuestion=${result.suggestedQuestionText != null}'
        ' | rewritesOptions=${result.suggestedOptions != null}'
        ' | userMath=${result.userMathCheck.outcome.name}',
      );
    } else {
      debugPrint('MCQ evidence review: no usable reply');
    }

    if (result != null && result.flaw != QuestionFlaw.none) {
      // The question is wrong in a way choosing an option will not fix, so
      // the finding is kept even if the user does not edit it now.
      await ref
          .read(appDatabaseProvider)
          .saveVerificationMark(
            dq.id,
            status: VerificationMark.flagged.storageKey,
            note: '${result.flaw.label} — ${result.reasoning}',
          );
      if (mounted) {
        setState(() {
          _mark = VerificationMark.flagged;
          _markNote = '${result.flaw.label} — ${result.reasoning}';
          _markedAt = DateTime.now();
        });
      }
    }

    if (!mounted) return;
    setState(() {
      _review = result;
      _reviewFailed = result == null;
      _isReviewing = false;
    });
  }

  /// Opens the editor so the user can put the question itself right.
  ///
  /// Pre-filled with the review's suggestion where it made one, but every
  /// field stays editable: the suggestion is a starting point, not a verdict.
  Future<void> _openQuestionEditor() async {
    final review = _review;
    final questionCtrl = TextEditingController(
      text: review?.suggestedQuestionText ?? _questionText,
    );
    final seedOptions = review?.suggestedOptions ?? _options;
    final optionCtrls = [
      for (final o in seedOptions) TextEditingController(text: o),
    ];
    // A corrected answer can still leave a wrong explanation behind, so the
    // explanation is editable too rather than only ever machine-written.
    final explanationCtrl = TextEditingController(
      text: review?.reasoning.isNotEmpty == true
          ? review!.reasoning
          : _explanationText,
    );
    var chosen = review?.suggestedCorrectIndex ?? _correctIndex;
    if (chosen < 0 || chosen >= optionCtrls.length) chosen = 0;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          shape: _dialogShape,
          title: Text(
            'প্রশ্ন সম্পাদনা',
            style: FluentType.bodyStrong.copyWith(fontSize: 16),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: questionCtrl,
                  maxLines: null,
                  style: FluentType.body,
                  decoration: InputDecoration(
                    labelText: 'প্রশ্ন',
                    border: OutlineInputBorder(
                      borderRadius: FluentRadius.controlBorder,
                    ),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: FluentSpacing.l),
                TextField(
                  controller: explanationCtrl,
                  maxLines: null,
                  minLines: 2,
                  style: FluentType.body,
                  decoration: InputDecoration(
                    labelText: 'ব্যাখ্যা',
                    border: OutlineInputBorder(
                      borderRadius: FluentRadius.controlBorder,
                    ),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: FluentSpacing.l),
                Text(
                  'অপশন (রেডিওতে সঠিকটি বেছে নিন)',
                  style: FluentType.caption.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: FluentSpacing.xs),
                RadioGroup<int>(
                  groupValue: chosen,
                  onChanged: (v) => setLocal(() => chosen = v ?? chosen),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < optionCtrls.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(top: FluentSpacing.s),
                          child: Row(
                            children: [
                              Radio<int>(
                                value: i,
                                visualDensity: VisualDensity.compact,
                              ),
                              Expanded(
                                child: TextField(
                                  controller: optionCtrls[i],
                                  style: FluentType.body,
                                  decoration: InputDecoration(
                                    labelText: 'অপশন $i',
                                    border: OutlineInputBorder(
                                      borderRadius: FluentRadius.controlBorder,
                                    ),
                                    isDense: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('বাতিল'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('সংরক্ষণ'),
            ),
          ],
        ),
      ),
    );

    final newQuestion = questionCtrl.text.trim();
    final newOptions = [for (final c in optionCtrls) c.text.trim()];
    final newExplanation = explanationCtrl.text.trim();
    questionCtrl.dispose();
    explanationCtrl.dispose();
    for (final c in optionCtrls) {
      c.dispose();
    }

    if (saved != true || !mounted) return;
    if (newQuestion.isEmpty || newOptions.any((o) => o.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('প্রশ্ন ও সব অপশন পূরণ করুন')),
      );
      return;
    }

    await ref
        .read(appDatabaseProvider)
        .applyQuestionEdit(
          widget.question.id,
          questionText: newQuestion,
          options: newOptions,
          correctIndex: chosen,
          explanation: newExplanation,
        );

    if (!mounted) return;
    setState(() {
      _originalCorrectIndex ??= _correctIndex;
      _originalExplanation ??= _explanationText;
      _originalQuestionText ??= _questionText;
      _originalOptions ??= _options;
      _correctedAt = DateTime.now();
      _questionText = newQuestion;
      _options = newOptions;
      _correctIndex = chosen;
      _explanationText = newExplanation;
      _nowScoredCorrect = widget.question.selectedIndex == chosen;
      _questionEdited = true;
      _mark = VerificationMark.none;
      _markNote = null;
      _markedAt = null;
      _proposalDismissed = false;
      // The old verdict described the old question, so it goes.
      _verification = null;
      _review = null;
      _showEvidenceBox = false;
      _evidenceController.clear();
    });
  }

  Future<void> _fetchExplanation() async {
    final dq = widget.question;
    final options = _options;

    final userAns = (dq.selectedIndex >= 0 && dq.selectedIndex < options.length)
        ? options[dq.selectedIndex]
        : 'ভুল উত্তর';
    final correctAns = (_correctIndex >= 0 && _correctIndex < options.length)
        ? options[_correctIndex]
        : 'সঠিক উত্তর';

    final result = await GeminiAiService.instance.explainMistake(
      subject: dq.subject,
      topic: dq.topic,
      questionText: _questionText,
      options: options,
      userAns: userAns,
      correctAns: correctAns,
      explanation: dq.explanation,
    );

    if (mounted) {
      setState(() {
        _isLoading = false;
        _explanation = result;
      });
    }
  }

  Widget _buildCorrectionStatusBanner(bool isDark) {
    if (_originalCorrectIndex == null && _correctedAt == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final onSurface = theme.colorScheme.onSurface;

    String origText = '(অজানা)';
    if (_originalCorrectIndex != null) {
      final opts = _originalOptions ?? _options;
      if (_originalCorrectIndex! >= 0 && _originalCorrectIndex! < opts.length) {
        origText = opts[_originalCorrectIndex!];
      }
    }

    String currentText = '(অজানা)';
    if (_correctIndex >= 0 && _correctIndex < _options.length) {
      currentText = _options[_correctIndex];
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: FluentSpacing.l),
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
              const Icon(Icons.history, size: 16, color: _hintColor),
              const SizedBox(width: FluentSpacing.s),
              Expanded(
                child: Text(
                  'প্রশ্নটিতে পূর্বে সংশোধন প্রয়োগ করা হয়েছে',
                  style: FluentType.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? Colors.amber.shade200
                        : Colors.amber.shade900,
                  ),
                ),
              ),
              if (_correctedAt != null)
                Text(
                  '${_correctedAt!.day}/${_correctedAt!.month}/${_correctedAt!.year}',
                  style: FluentType.caption.copyWith(
                    color: onSurface.withValues(alpha: 0.45),
                  ),
                ),
            ],
          ),
          const SizedBox(height: FluentSpacing.s),
          if (_originalCorrectIndex != null) ...[
            _buildAnswerLine('মূল উত্তর ছিল', origText, isDark, false),
            const SizedBox(height: FluentSpacing.xs),
          ],
          _buildAnswerLine('বর্তমান উত্তর', currentText, isDark, true),
          const SizedBox(height: FluentSpacing.m),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'আপনার পছন্দ ও পরীক্ষার ইতিহাস অপরিবর্তিত আছে',
                  style: FluentType.caption.copyWith(
                    color: onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _revertCorrection,
                icon: const Icon(Icons.undo, size: 14),
                label: Text(
                  'পূর্বের অবস্থায় ফিরুন',
                  style: FluentType.caption,
                ),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: _wrongColor,
                  side: const BorderSide(
                    color: _wrongColor,
                    width: FluentStroke.width,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: FluentRadius.controlBorder,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: FluentSpacing.s,
                    vertical: FluentSpacing.xs,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationSection(bool isDark) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    final onSurface = scheme.onSurface;
    final result = _verification;

    if (result == null) {
      final hasMark = _mark != VerificationMark.none;
      return Align(
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCorrectionStatusBanner(isDark),
            // What an earlier check concluded, so reopening the sheet does not
            // start from nothing -- or cost another call.
            if (hasMark) ...[
              _buildMarkChip(isDark),
              if ((_markNote ?? '').isNotEmpty) ...[
                const SizedBox(height: FluentSpacing.s),
                SelectableText(
                  _markNote!,
                  style: FluentType.body.copyWith(color: onSurface),
                ),
              ],
              const SizedBox(height: FluentSpacing.s),
            ],
            OutlinedButton.icon(
              onPressed: _isVerifying ? null : _verify,
              icon: _isVerifying
                  ? const SizedBox(
                      width: FluentSpacing.l,
                      height: FluentSpacing.l,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.fact_check_outlined, size: 16),
              label: Text(
                _isVerifying
                    ? 'যাচাই চলছে…'
                    : (hasMark
                          ? 'আবার যাচাই করুন'
                          : 'উত্তর স্বাধীনভাবে যাচাই করুন'),
              ),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                side: FluentStroke.side(brightness),
                shape: RoundedRectangleBorder(
                  borderRadius: FluentRadius.controlBorder,
                ),
              ),
            ),
            if (hasMark && _mark != VerificationMark.userVerified)
              Padding(
                padding: const EdgeInsets.only(top: FluentSpacing.xs),
                child: TextButton.icon(
                  onPressed: _markVerifiedByUser,
                  icon: const Icon(Icons.how_to_reg_outlined, size: 16),
                  label: Text(
                    'আমি নিশ্চিত করছি',
                    style: FluentType.body,
                  ),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: FluentRadius.controlBorder,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: FluentSpacing.s,
                    ),
                  ),
                ),
              ),
            if (_verifyFailed)
              Padding(
                padding: const EdgeInsets.only(top: FluentSpacing.s),
                child: Text(
                  'যাচাই করা গেল না। API key বা ইন্টারনেট দেখুন।',
                  style: FluentType.caption.copyWith(color: _wrongColor),
                ),
              ),
            // An edit clears the old verdict, so this is the only place left
            // to confirm that the edit was saved.
            if (_questionEdited)
              Padding(
                padding: const EdgeInsets.only(top: FluentSpacing.m),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      size: 16,
                      color: _correctColor,
                    ),
                    const SizedBox(width: FluentSpacing.s),
                    Expanded(
                      child: Text(
                        'প্রশ্নটি সংরক্ষিত হয়েছে। আপনার পুরনো উত্তর ও ফলাফল অপরিবর্তিত আছে।',
                        style: FluentType.body.copyWith(color: onSurface),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }

    // Green is reserved for something actually settled. Agreement between two
    // models is two opinions, and reads as grey.
    final (accent, icon) = switch (result.verdict) {
      VerificationVerdict.supported => (_correctColor, Icons.verified_outlined),
      VerificationVerdict.likelyIncorrect => (
        _wrongColor,
        Icons.report_problem_outlined,
      ),
      VerificationVerdict.inconclusive => (
        onSurface.withValues(alpha: 0.45),
        result.agrees && result.solve.ambiguity == McqAmbiguity.none
            ? Icons.done_outlined
            : Icons.remove_circle_outline,
      ),
    };
    final headline = result.headline;

    String optionAt(int i) =>
        i >= 0 && i < _options.length ? _options[i] : '(অজানা)';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCorrectionStatusBanner(isDark),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(FluentSpacing.m),
          decoration: BoxDecoration(
            color: FluentLayer.subtle(accent, brightness),
            borderRadius: FluentRadius.cardBorder,
            border: Border.all(
              color: accent.withValues(alpha: 0.35),
              width: FluentStroke.width,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: accent),
                  const SizedBox(width: FluentSpacing.s),
                  Expanded(
                    child: Text(
                      headline,
                      style: FluentType.bodyStrong.copyWith(color: accent),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: FluentSpacing.s),
              SelectableText(
                result.solve.reasoning,
                style: FluentType.body.copyWith(color: onSurface),
              ),
              if (result.explanationCheck.outcome ==
                  MathCheckOutcome.fails) ...[
                const SizedBox(height: FluentSpacing.s),
                Text(
                  '⚠ ব্যাখ্যার হিসাবে গরমিল: ${result.explanationCheck.detail}',
                  style: FluentType.caption.copyWith(color: _wrongColor),
                ),
              ],
              if (result.agrees && !result.independentlyVerified) ...[
                const SizedBox(height: FluentSpacing.s),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FluentSpacing.s,
                    vertical: FluentSpacing.s,
                  ),
                  decoration: BoxDecoration(
                    color: onSurface.withValues(alpha: 0.06),
                    borderRadius: FluentRadius.controlBorder,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: _hintColor,
                      ),
                      const SizedBox(width: FluentSpacing.s),
                      Expanded(
                        child: Text(
                          'মডেলের সম্মতি কোনো তথ্যগত প্রমাণ নয় (বহিঃস্থ উৎস যাচাই করা হয়নি)।',
                          style: FluentType.caption.copyWith(color: onSurface),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (result.hasProposal &&
                  !_correctionAccepted &&
                  !_proposalDismissed) ...[
                const SizedBox(height: FluentSpacing.m),
                Container(
                  padding: const EdgeInsets.all(FluentSpacing.m),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: FluentRadius.cardBorder,
                    border: Border.all(
                      color: FluentStroke.card(brightness),
                      width: FluentStroke.width,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'সংশোধন প্রস্তাব',
                        style: FluentType.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                          color: onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                      const SizedBox(height: FluentSpacing.s),
                      _buildAnswerLine(
                        'বর্তমান উত্তর',
                        optionAt(result.storedIndex),
                        isDark,
                        false,
                      ),
                      const SizedBox(height: FluentSpacing.xs),
                      _buildAnswerLine(
                        'প্রস্তাবিত উত্তর',
                        optionAt(result.proposedIndex!),
                        isDark,
                        true,
                      ),
                      const SizedBox(height: FluentSpacing.s),
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 12,
                            color: onSurface.withValues(alpha: 0.45),
                          ),
                          const SizedBox(width: FluentSpacing.xs),
                          Expanded(
                            child: Text(
                              'প্রমাণের অবস্থা: ${result.independentlyVerified ? "যাচাই করা" : "উৎস পাওয়া যায়নি"}',
                              style: FluentType.caption.copyWith(
                                color: onSurface.withValues(alpha: 0.45),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: FluentSpacing.m),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                setState(() => _proposalDismissed = true);
                              },
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                side: FluentStroke.side(brightness),
                                shape: RoundedRectangleBorder(
                                  borderRadius: FluentRadius.controlBorder,
                                ),
                              ),
                              child: Text(
                                'আগেরটাই রাখুন',
                                style: FluentType.body,
                              ),
                            ),
                          ),
                          const SizedBox(width: FluentSpacing.s),
                          Expanded(
                            child: FilledButton(
                              onPressed: () =>
                                  _acceptCorrection(result.proposedIndex!),
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                shape: RoundedRectangleBorder(
                                  borderRadius: FluentRadius.controlBorder,
                                ),
                              ),
                              child: Text(
                                'সংশোধন গ্রহণ',
                                style: FluentType.body,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              if (_proposalDismissed && !_correctionAccepted) ...[
                const SizedBox(height: FluentSpacing.m),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FluentSpacing.m,
                    vertical: FluentSpacing.s,
                  ),
                  decoration: BoxDecoration(
                    color: onSurface.withValues(alpha: 0.06),
                    borderRadius: FluentRadius.controlBorder,
                    border: Border.all(
                      color: FluentStroke.card(brightness),
                      width: FluentStroke.width,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: onSurface.withValues(alpha: 0.65),
                      ),
                      const SizedBox(width: FluentSpacing.s),
                      Expanded(
                        child: Text(
                          'সংশোধন প্রস্তাব বাতিল করা হয়েছে। সংরক্ষিত উত্তরটি অপরিবর্তিত রাখা হয়েছে।',
                          style: FluentType.body.copyWith(color: onSurface),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_correctionAccepted) ...[
                const SizedBox(height: FluentSpacing.m),
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      size: 16,
                      color: _correctColor,
                    ),
                    const SizedBox(width: FluentSpacing.s),
                    Expanded(
                      child: Text(
                        _nowScoredCorrect
                            ? 'সংশোধন সংরক্ষিত হয়েছে। আপনি আসলে সঠিক উত্তরই দিয়েছিলেন, তাই এটি আর ভুল হিসেবে গণ্য হবে না।'
                            : 'সংশোধন সংরক্ষিত হয়েছে। আপনি যা বেছেছিলেন তা অপরিবর্তিত আছে।',
                        style: FluentType.body.copyWith(color: onSurface),
                      ),
                    ),
                  ],
                ),
              ],
              if (result.reviewerDissents) ...[
                const SizedBox(height: FluentSpacing.m),
                Container(
                  padding: const EdgeInsets.all(FluentSpacing.m),
                  decoration: BoxDecoration(
                    color: FluentLayer.subtle(_hintColor, brightness),
                    borderRadius: FluentRadius.cardBorder,
                    border: Border.all(
                      color: _hintColor.withValues(alpha: 0.3),
                      width: FluentStroke.width,
                    ),
                  ),
                  child: Text(
                    'যাচাইকারী "${optionAt(result.dissentIndex!)}" বেছেছে, '
                    'কিন্তু আপনি নিজে "${optionAt(result.storedIndex)}" ঠিক করেছেন। '
                    'আপনার সিদ্ধান্তই রাখা হয়েছে — বদলাতে চাইলে নিজে সম্পাদনা করুন।',
                    style: FluentType.body.copyWith(color: onSurface),
                  ),
                ),
              ],
              if (_mark == VerificationMark.userVerified) ...[
                const SizedBox(height: FluentSpacing.m),
                _buildMarkChip(isDark),
              ] else ...[
                const SizedBox(height: FluentSpacing.s),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _markVerifiedByUser,
                    icon: const Icon(Icons.how_to_reg_outlined, size: 16),
                    label: Text(
                      'আমি নিশ্চিত করছি',
                      style: FluentType.body,
                    ),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: FluentRadius.controlBorder,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: FluentSpacing.s,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: FluentSpacing.xs),
              _buildEvidenceSection(isDark),
              const SizedBox(height: FluentSpacing.m),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 12,
                    color: onSurface.withValues(alpha: 0.45),
                  ),
                  const SizedBox(width: FluentSpacing.xs),
                  Expanded(
                    child: Text(
                      result.limitations,
                      style: FluentType.caption.copyWith(
                        color: onSurface.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// A one-line badge saying who last stood behind this answer.
  ///
  /// The user's own mark gets the solid tick; a model agreeing gets a quieter
  /// one, because it is a second opinion rather than a guarantee.
  Widget _buildMarkChip(bool isDark) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final (colour, icon) = switch (_mark) {
      VerificationMark.userVerified => (_correctColor, Icons.verified),
      VerificationMark.modelAgreed => (
        onSurface.withValues(alpha: 0.55),
        Icons.check_circle_outline,
      ),
      VerificationMark.flagged => (_hintColor, Icons.flag_outlined),
      VerificationMark.none => (Colors.transparent, Icons.circle),
    };
    final when = _markedAt;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: colour),
        const SizedBox(width: FluentSpacing.s),
        Flexible(
          child: Text(
            _mark.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FluentType.caption.copyWith(
              fontWeight: FontWeight.w600,
              color: colour,
            ),
          ),
        ),
        if (when != null) ...[
          const SizedBox(width: FluentSpacing.s),
          Flexible(
            child: Text(
              '· ${when.day}/${when.month}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FluentType.caption.copyWith(
                color: onSurface.withValues(alpha: 0.45),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// The user's own case, and what came back from it.
  ///
  /// Offered whatever the verdict was: the user may know the verifier is
  /// wrong just as easily as they may know it is right.
  Widget _buildEvidenceSection(bool isDark) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    final onSurface = scheme.onSurface;
    final review = _review;

    if (!_showEvidenceBox && review == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _openEvidenceBox,
          icon: const Icon(Icons.edit_note_outlined, size: 16),
          label: Text(
            'একমত নন? আপনার যুক্তি দিন',
            style: FluentType.body,
          ),
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            shape: RoundedRectangleBorder(
              borderRadius: FluentRadius.controlBorder,
            ),
            padding: const EdgeInsets.symmetric(horizontal: FluentSpacing.s),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_showEvidenceBox) ...[
          TextField(
            controller: _evidenceController,
            focusNode: _evidenceFocus,
            maxLines: 3,
            minLines: 2,
            textInputAction: TextInputAction.newline,
            style: FluentType.body.copyWith(color: onSurface),
            decoration: InputDecoration(
              hintText: 'যেমন: ১০:৬ লঘিষ্ঠ করলে ৫:৩ হয়, ৩:২ নয় — তাই সংরক্ষিত উত্তরটি ভুল।',
              hintStyle: FluentType.caption.copyWith(
                color: onSurface.withValues(alpha: 0.45),
              ),
              border: OutlineInputBorder(
                borderRadius: FluentRadius.controlBorder,
              ),
              isDense: true,
            ),
          ),
          const SizedBox(height: FluentSpacing.s),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isReviewing ? null : _submitEvidence,
                  icon: _isReviewing
                      ? const SizedBox(
                          width: FluentSpacing.l,
                          height: FluentSpacing.l,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_outlined, size: 16),
                  label: Text(
                    _isReviewing ? 'দেখা হচ্ছে…' : 'যুক্তি পাঠান',
                    style: FluentType.body,
                  ),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: FluentRadius.controlBorder,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: FluentSpacing.s),
              OutlinedButton(
                onPressed: () => setState(() => _showEvidenceBox = false),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  side: FluentStroke.side(brightness),
                  shape: RoundedRectangleBorder(
                    borderRadius: FluentRadius.controlBorder,
                  ),
                ),
                child: Text('বাতিল', style: FluentType.body),
              ),
            ],
          ),
          if (_reviewFailed)
            Padding(
              padding: const EdgeInsets.only(top: FluentSpacing.s),
              child: Text(
                'যুক্তিটি পাঠানো গেল না। ইন্টারনেট বা API key দেখুন।',
                style: FluentType.caption.copyWith(color: _wrongColor),
              ),
            ),
        ],
        if (review != null) ...[
          const SizedBox(height: FluentSpacing.m),
          Container(
            padding: const EdgeInsets.all(FluentSpacing.m),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: FluentRadius.cardBorder,
              border: Border.all(
                color: FluentStroke.card(brightness),
                width: FluentStroke.width,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      review.verdict == EvidenceVerdict.storedLooksWrong
                          ? Icons.report_problem_outlined
                          : Icons.balance_outlined,
                      size: 16,
                      color: review.settled
                          ? _correctColor
                          : onSurface.withValues(alpha: 0.65),
                    ),
                    const SizedBox(width: FluentSpacing.s),
                    Expanded(
                      child: Text(
                        review.verdict.headline,
                        style: FluentType.bodyStrong.copyWith(
                          color: review.settled ? _correctColor : onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: FluentSpacing.s),
                SelectableText(
                  review.reasoning,
                  style: FluentType.body.copyWith(color: onSurface),
                ),
                if (review.conflictsWithUserMath) ...[
                  const SizedBox(height: FluentSpacing.s),
                  Text(
                    '⚠ আপনার হিসাব কোডে মিলে গেছে, অথচ যাচাইকারী সংরক্ষিত উত্তরেই স্থির। '
                    'দুটোর একটি ভুল, আর অ্যাপ নিজে থেকে পক্ষ নিচ্ছে না — আপনি দেখে সিদ্ধান্ত নিন।',
                    style: FluentType.body.copyWith(color: _hintColor),
                  ),
                ] else if (review.userArithmeticHolds) ...[
                  const SizedBox(height: FluentSpacing.s),
                  Text(
                    '✓ আপনার হিসাব কোডেই মিলিয়ে দেখা হয়েছে: ${review.userMathCheck.detail}',
                    style: FluentType.body.copyWith(color: _correctColor),
                  ),
                ],
                if (review.flaw != QuestionFlaw.none) ...[
                  const SizedBox(height: FluentSpacing.s),
                  Text(
                    '⚠ ${review.flaw.label}',
                    style: FluentType.bodyStrong.copyWith(color: _hintColor),
                  ),
                  const SizedBox(height: FluentSpacing.xxs),
                  Text(
                    review.flaw.guidance,
                    style: FluentType.body.copyWith(
                      color: onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ],
                const SizedBox(height: FluentSpacing.m),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _openQuestionEditor,
                        icon: const Icon(Icons.tune, size: 16),
                        label: Text(
                          'প্রশ্ন সম্পাদনা',
                          style: FluentType.body,
                        ),
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          side: FluentStroke.side(brightness),
                          shape: RoundedRectangleBorder(
                            borderRadius: FluentRadius.controlBorder,
                          ),
                        ),
                      ),
                    ),
                    if (review.suggestedCorrectIndex != null &&
                        review.suggestedCorrectIndex != _correctIndex &&
                        review.suggestedOptions == null &&
                        review.suggestedQuestionText == null) ...[
                      const SizedBox(width: FluentSpacing.s),
                      Expanded(
                        child: FilledButton(
                          onPressed: () =>
                              _acceptCorrection(review.suggestedCorrectIndex!),
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            shape: RoundedRectangleBorder(
                              borderRadius: FluentRadius.controlBorder,
                            ),
                          ),
                          child: Text(
                            'উত্তর বদলান',
                            style: FluentType.body,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (review.flaw != QuestionFlaw.none) ...[
                  const SizedBox(height: FluentSpacing.s),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _deleteQuestion,
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 16,
                        color: _wrongColor,
                      ),
                      label: Text(
                        'প্রশ্নটিই ভুল, সরিয়ে দিন',
                        style: FluentType.body.copyWith(color: _wrongColor),
                      ),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(
                          borderRadius: FluentRadius.controlBorder,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: FluentSpacing.s,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: FluentSpacing.s),
                Text(
                  review.limitations,
                  style: FluentType.caption.copyWith(
                    color: onSurface.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_questionEdited) ...[
          const SizedBox(height: FluentSpacing.m),
          Row(
            children: [
              const Icon(Icons.check_circle, size: 16, color: _correctColor),
              const SizedBox(width: FluentSpacing.s),
              Expanded(
                child: Text(
                  'প্রশ্নটি সংরক্ষিত হয়েছে। আবার যাচাই চালাতে পারেন; আপনার পুরনো উত্তর ও ফলাফল অপরিবর্তিত আছে।',
                  style: FluentType.body.copyWith(color: onSurface),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildAnswerLine(
    String label,
    String value,
    bool isDark,
    bool highlight,
  ) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          child: Text(
            label,
            style: FluentType.caption.copyWith(
              color: onSurface.withValues(alpha: 0.65),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: FluentType.body.copyWith(
              fontWeight: highlight ? FontWeight.w600 : FontWeight.w400,
              color: highlight
                  ? (isDark ? Colors.green.shade200 : Colors.green.shade900)
                  : onSurface,
            ),
          ),
        ),
      ],
    );
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: _explanation));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    final onSurface = scheme.onSurface;
    final isDark = brightness == Brightness.dark;
    // The sheet now has a text field in it, so it has to climb above the
    // keyboard instead of sitting under it.
    final keyboard = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboard),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.82 - keyboard * 0.4,
        ),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(FluentRadius.large),
          ),
          border: Border(
            top: FluentStroke.side(brightness),
            left: FluentStroke.side(brightness),
            right: FluentStroke.side(brightness),
          ),
          boxShadow: FluentElevation.flyout(brightness),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                color: onSurface.withValues(alpha: 0.24),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: FluentSpacing.l,
                vertical: FluentSpacing.s,
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(FluentSpacing.s),
                    decoration: BoxDecoration(
                      color: FluentLayer.subtle(scheme.primary, brightness),
                      borderRadius: FluentRadius.controlBorder,
                    ),
                    child: Icon(
                      Icons.auto_awesome,
                      color: scheme.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: FluentSpacing.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AI ভুল বিশ্লেষণ ও মেন্টর গাইড',
                          style: FluentType.bodyStrong.copyWith(
                            fontSize: 16,
                            color: onSurface,
                          ),
                        ),
                        Text(
                          '${widget.question.subject} • ${widget.question.topic}',
                          style: FluentType.caption.copyWith(
                            color: onSurface.withValues(alpha: 0.65),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_note, size: 20),
                    tooltip: 'প্রশ্ন বা উত্তর সংশোধন করুন',
                    onPressed: _openQuestionEditor,
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: _wrongColor,
                    ),
                    tooltip: 'ভুল বা অপ্রয়োজনীয় প্রশ্ন, নোটবুক থেকে মুছুন',
                    onPressed: _deleteQuestion,
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Content
            Expanded(
              child: _isLoading
                  ? const AiProgressPipelineWidget(
                      type: AiTaskType.explainer,
                      isCompact: false,
                    )
                  : SingleChildScrollView(
                      controller: _bodyScroll,
                      padding: const EdgeInsets.all(FluentSpacing.l),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Question Banner
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(FluentSpacing.m),
                            decoration: BoxDecoration(
                              color: onSurface.withValues(alpha: 0.04),
                              borderRadius: FluentRadius.cardBorder,
                              border: Border.all(
                                color: FluentStroke.card(brightness),
                                width: FluentStroke.width,
                              ),
                            ),
                            child: Text(
                              BengaliMathSanitizer.sanitize(_questionText),
                              style: FluentType.bodyStrong.copyWith(
                                color: onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(height: FluentSpacing.l),

                          // Formatted AI Output
                          SelectableText(
                            _explanation,
                            style: FluentType.body.copyWith(color: onSurface),
                          ),
                          const SizedBox(height: FluentSpacing.l),
                          _buildVerificationSection(isDark),
                          const SizedBox(height: FluentSpacing.l),
                        ],
                      ),
                    ),
            ),

            // Bottom Action Bar
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
                  OutlinedButton.icon(
                    onPressed: _isLoading ? null : _copyToClipboard,
                    icon: Icon(_copied ? Icons.check : Icons.copy, size: 16),
                    label: Text(_copied ? 'কপি হয়েছে' : 'কপি করুন'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: _copied ? _correctColor : null,
                      side: FluentStroke.side(brightness),
                      shape: RoundedRectangleBorder(
                        borderRadius: FluentRadius.controlBorder,
                      ),
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: FluentRadius.controlBorder,
                      ),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('বুঝেছি, ধন্যবাদ'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
