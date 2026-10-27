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
import '../../../../core/utils/bengali_math_sanitizer.dart';

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

  // A verifier that cannot settle something is not the end of it: the user
  // knows things it does not, so they get to make the case themselves.
  final TextEditingController _evidenceController = TextEditingController();
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
    _mark = VerificationMark.parse(dq.verificationStatus);
    _markNote = dq.verificationNote;
    _markedAt = dq.verifiedAt;
    _fetchExplanation();
  }

  @override
  void dispose() {
    _evidenceController.dispose();
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
    );

    if (result == null) {
      debugPrint('MCQ verify: no usable solve returned');
    } else {
      debugPrint(
        'MCQ verify: ${result.verdict.name}'
        ' | stored=$_correctIndex solved=${result.solve.chosenIndex}'
        ' | ambiguity=${result.solve.ambiguity.name}'
        ' | proposal=${result.hasProposal}'
        ' | evidence=${result.evidence.name}'
        ' | explanationCheck=${result.explanationCheck.outcome.name}',
      );
    }

    if (result != null) {
      // Recording what the check found is not the same as changing the
      // answer: nothing about the question moves here.
      final mark = result.hasProposal
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
          correctedExplanation:
              'সংশোধিত উত্তর: $proposed। $reason\n\n(পূর্বের ব্যাখ্যা: ${dq.explanation})',
        );

    if (!mounted) return;
    setState(() => _correctionAccepted = true);
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
    var chosen = review?.suggestedCorrectIndex ?? _correctIndex;
    if (chosen < 0 || chosen >= optionCtrls.length) chosen = 0;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('প্রশ্ন সম্পাদনা', style: TextStyle(fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: questionCtrl,
                  maxLines: null,
                  style: const TextStyle(fontSize: 13.5),
                  decoration: const InputDecoration(
                    labelText: 'প্রশ্ন',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'অপশন (রেডিওতে সঠিকটি বেছে নিন)',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                RadioGroup<int>(
                  groupValue: chosen,
                  onChanged: (v) => setLocal(() => chosen = v ?? chosen),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < optionCtrls.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(
                            children: [
                              Radio<int>(
                                value: i,
                                visualDensity: VisualDensity.compact,
                              ),
                              Expanded(
                                child: TextField(
                                  controller: optionCtrls[i],
                                  style: const TextStyle(fontSize: 13),
                                  decoration: InputDecoration(
                                    labelText: 'অপশন $i',
                                    border: const OutlineInputBorder(),
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
    questionCtrl.dispose();
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

    final note = _review?.reasoning ?? '';
    await ref
        .read(appDatabaseProvider)
        .applyQuestionEdit(
          widget.question.id,
          questionText: newQuestion,
          options: newOptions,
          correctIndex: chosen,
          explanation: note.isEmpty
              ? _explanationText
              : 'আপনার সম্পাদনা অনুযায়ী সংশোধিত। $note'
                    '\n\n(পূর্বের ব্যাখ্যা: $_explanationText)',
        );

    if (!mounted) return;
    setState(() {
      _questionText = newQuestion;
      _options = newOptions;
      _correctIndex = chosen;
      _questionEdited = true;
      _mark = VerificationMark.none;
      _markNote = null;
      _markedAt = null;
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

  Widget _buildVerificationSection(bool isDark) {
    final result = _verification;

    if (result == null) {
      final hasMark = _mark != VerificationMark.none;
      return Align(
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // What an earlier check concluded, so reopening the sheet does not
            // start from nothing -- or cost another call.
            if (hasMark) ...[
              _buildMarkChip(isDark),
              if ((_markNote ?? '').isNotEmpty) ...[
                const SizedBox(height: 7),
                SelectableText(
                  _markNote!,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              ],
              const SizedBox(height: 9),
            ],
            OutlinedButton.icon(
              onPressed: _isVerifying ? null : _verify,
              icon: _isVerifying
                  ? const SizedBox(
                      width: 14,
                      height: 14,
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
              ),
            ),
            if (hasMark && _mark != VerificationMark.userVerified)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: TextButton.icon(
                  onPressed: _markVerifiedByUser,
                  icon: const Icon(Icons.how_to_reg_outlined, size: 16),
                  label: const Text(
                    'আমি নিশ্চিত করছি',
                    style: TextStyle(fontSize: 12.5),
                  ),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                ),
              ),
            if (_verifyFailed)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'যাচাই করা গেল না। API key বা ইন্টারনেট দেখুন।',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.redAccent.shade200,
                  ),
                ),
              ),
            // An edit clears the old verdict, so this is the only place left
            // to confirm that the edit was saved.
            if (_questionEdited)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      size: 15,
                      color: Colors.green,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'প্রশ্নটি সংরক্ষিত হয়েছে। আপনার পুরনো উত্তর ও ফলাফল অপরিবর্তিত আছে।',
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.45,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
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
      VerificationVerdict.supported => (Colors.green, Icons.verified_outlined),
      VerificationVerdict.likelyIncorrect => (
        Colors.redAccent,
        Icons.report_problem_outlined,
      ),
      VerificationVerdict.inconclusive => (
        isDark ? Colors.white38 : Colors.black45,
        result.agrees && result.solve.ambiguity == McqAmbiguity.none
            ? Icons.done_outlined
            : Icons.remove_circle_outline,
      ),
    };
    final headline = result.headline;

    String optionAt(int i) =>
        i >= 0 && i < _options.length ? _options[i] : '(অজানা)';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isDark ? 0.12 : 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: accent),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  headline,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            result.solve.reasoning,
            style: const TextStyle(fontSize: 13, height: 1.55),
          ),
          if (result.explanationCheck.outcome == MathCheckOutcome.fails) ...[
            const SizedBox(height: 8),
            Text(
              '⚠ ব্যাখ্যার হিসাবে গরমিল: ${result.explanationCheck.detail}',
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: Colors.redAccent.shade200,
              ),
            ),
          ],
          if (result.hasProposal && !_correctionAccepted) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: isDark ? Colors.white10 : Colors.white,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: isDark ? Colors.white24 : Colors.grey.shade300,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'সংশোধন প্রস্তাব',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.4,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 7),
                  _buildAnswerLine(
                    'বর্তমান উত্তর',
                    optionAt(result.storedIndex),
                    isDark,
                    false,
                  ),
                  const SizedBox(height: 4),
                  _buildAnswerLine(
                    'প্রস্তাবিত উত্তর',
                    optionAt(result.proposedIndex!),
                    isDark,
                    true,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 12,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          'প্রমাণের অবস্থা: ${result.independentlyVerified ? "যাচাই করা" : "উৎস পাওয়া যায়নি"}',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white38 : Colors.black45,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () =>
                              setState(() => _correctionAccepted = false),
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text(
                            'আগেরটাই রাখুন',
                            style: TextStyle(fontSize: 12.5),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: () =>
                              _acceptCorrection(result.proposedIndex!),
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text(
                            'সংশোধন গ্রহণ',
                            style: TextStyle(fontSize: 12.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          if (_correctionAccepted) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.check_circle, size: 15, color: Colors.green),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'সংশোধন সংরক্ষিত হয়েছে। আপনার পুরনো উত্তর ও ফলাফল অপরিবর্তিত আছে।',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.45,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (_mark == VerificationMark.userVerified) ...[
            const SizedBox(height: 10),
            _buildMarkChip(isDark),
          ] else ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _markVerifiedByUser,
                icon: const Icon(Icons.how_to_reg_outlined, size: 16),
                label: const Text(
                  'আমি নিশ্চিত করছি',
                  style: TextStyle(fontSize: 12.5),
                ),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
              ),
            ),
          ],
          const SizedBox(height: 4),
          _buildEvidenceSection(isDark),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 13,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  result.limitations,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.45,
                    color: isDark ? Colors.white38 : Colors.black45,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// A one-line badge saying who last stood behind this answer.
  ///
  /// The user's own mark gets the solid tick; a model agreeing gets a quieter
  /// one, because it is a second opinion rather than a guarantee.
  Widget _buildMarkChip(bool isDark) {
    final (colour, icon) = switch (_mark) {
      VerificationMark.userVerified => (Colors.green, Icons.verified),
      VerificationMark.modelAgreed => (
        isDark ? Colors.white54 : Colors.black45,
        Icons.check_circle_outline,
      ),
      VerificationMark.flagged => (Colors.orange.shade700, Icons.flag_outlined),
      VerificationMark.none => (Colors.transparent, Icons.circle),
    };
    final when = _markedAt;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: colour),
        const SizedBox(width: 6),
        Text(
          _mark.label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: colour,
          ),
        ),
        if (when != null) ...[
          const SizedBox(width: 6),
          Text(
            '· ${when.day}/${when.month}',
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white38 : Colors.black38,
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
    final review = _review;

    if (!_showEvidenceBox && review == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() => _showEvidenceBox = true),
          icon: const Icon(Icons.edit_note_outlined, size: 17),
          label: const Text(
            'একমত নন? আপনার যুক্তি দিন',
            style: TextStyle(fontSize: 12.5),
          ),
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 6),
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
            maxLines: 3,
            minLines: 2,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'যেমন: ১০:৬ লঘিষ্ঠ করলে ৫:৩ হয়, ৩:২ নয় — তাই সংরক্ষিত উত্তরটি ভুল।',
              hintStyle: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white30 : Colors.black38,
              ),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isReviewing ? null : _submitEvidence,
                  icon: _isReviewing
                      ? const SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_outlined, size: 15),
                  label: Text(
                    _isReviewing ? 'দেখা হচ্ছে…' : 'যুক্তি পাঠান',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => setState(() => _showEvidenceBox = false),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('বাতিল', style: TextStyle(fontSize: 12.5)),
              ),
            ],
          ),
          if (_reviewFailed)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'যুক্তিটি পাঠানো গেল না। ইন্টারনেট বা API key দেখুন।',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.redAccent.shade200,
                ),
              ),
            ),
        ],
        if (review != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : Colors.white,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: isDark ? Colors.white24 : Colors.grey.shade300,
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
                      size: 15,
                      color: review.settled
                          ? Colors.green
                          : (isDark ? Colors.white60 : Colors.black54),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        review.verdict.headline,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: review.settled
                              ? Colors.green
                              : (isDark ? Colors.white70 : Colors.black87),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                SelectableText(
                  review.reasoning,
                  style: const TextStyle(fontSize: 12.5, height: 1.5),
                ),
                if (review.userArithmeticHolds) ...[
                  const SizedBox(height: 7),
                  Text(
                    '✓ আপনার হিসাব কোডেই মিলিয়ে দেখা হয়েছে: ${review.userMathCheck.detail}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.45,
                      color: Colors.green,
                    ),
                  ),
                ],
                if (review.flaw != QuestionFlaw.none) ...[
                  const SizedBox(height: 8),
                  Text(
                    '⚠ ${review.flaw.label}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    review.flaw.guidance,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.45,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _openQuestionEditor,
                        icon: const Icon(Icons.tune, size: 15),
                        label: const Text(
                          'প্রশ্ন সম্পাদনা',
                          style: TextStyle(fontSize: 12.5),
                        ),
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                    if (review.suggestedCorrectIndex != null &&
                        review.suggestedCorrectIndex != _correctIndex &&
                        review.suggestedOptions == null &&
                        review.suggestedQuestionText == null) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: () =>
                              _acceptCorrection(review.suggestedCorrectIndex!),
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text(
                            'উত্তর বদলান',
                            style: TextStyle(fontSize: 12.5),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  review.limitations,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.4,
                    color: isDark ? Colors.white38 : Colors.black45,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_questionEdited) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.check_circle, size: 15, color: Colors.green),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'প্রশ্নটি সংরক্ষিত হয়েছে। আবার যাচাই চালাতে পারেন; আপনার পুরনো উত্তর ও ফলাফল অপরিবর্তিত আছে।',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.45,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 86,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              color: isDark ? Colors.white54 : Colors.black54,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
              color: highlight
                  ? (isDark ? Colors.green.shade200 : Colors.green.shade800)
                  : (isDark ? Colors.white : Colors.black87),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.82,
      ),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(2),
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
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    color: Color(0xFF8B5CF6),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'AI ভুল বিশ্লেষণ ও মেন্টর গাইড',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '${widget.question.subject} • ${widget.question.topic}',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
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
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(strokeWidth: 3),
                        SizedBox(height: 14),
                        Text(
                          'Gemini AI আপনার ভুলটি বিশ্লেষণ করছে...',
                          style: TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Question Banner
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF0F172A)
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white12
                                  : Colors.grey.shade300,
                            ),
                          ),
                          child: Text(
                            BengaliMathSanitizer.sanitize(_questionText),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                              height: 1.4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Formatted AI Output
                        SelectableText(
                          _explanation,
                          style: const TextStyle(fontSize: 13.5, height: 1.6),
                        ),
                        const SizedBox(height: 16),
                        _buildVerificationSection(isDark),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
          ),

          // Bottom Action Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : Colors.grey.shade50,
              border: Border(
                top: BorderSide(
                  color: isDark ? Colors.white10 : Colors.grey.shade200,
                ),
              ),
            ),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _copyToClipboard,
                  icon: Icon(_copied ? Icons.check : Icons.copy, size: 16),
                  label: Text(_copied ? 'কপি হয়েছে' : 'কপি করুন'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: _copied ? Colors.green : null,
                  ),
                ),
                const Spacer(),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8B5CF6),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
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
    );
  }
}
