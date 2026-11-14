import 'package:flutter/material.dart';

import '../../../../core/theme/fluent_tokens.dart';

import '../../../../core/services/ai/models/quiz_question.dart';
import '../../../../core/services/ai/question_bank_ocr_service.dart';

/// The three status colours this card means something by: a read it trusts,
/// one it wants a second look at, and one it could not read at all.
///
/// Kept here rather than typed at each call site so the same green, amber and
/// red are used throughout, and so each has a light-mode and a dark-mode value
/// that genuinely reads on that surface.
Color _okColour(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF4ADE80)
    : const Color(0xFF15803D);

Color _warnColour(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFFFCD34D)
    : const Color(0xFFB45309);

Color _badColour(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFFF87171)
    : const Color(0xFFB91C1C);

/// One scanned question, as it is reviewed before the set is saved.
///
/// Lifted out of the scanner modal, where it was seven hundred lines inside a
/// State object already holding fifty other members, and nothing in it ever
/// touched that State except through the handful of callbacks below. It owns
/// no state of its own: everything it shows is passed in, and every tap goes
/// back out, which is what let it move without changing behaviour.
class QuestionReviewCard extends StatelessWidget {
  const QuestionReviewCard({
    super.key,
    required this.qIndex,
    required this.question,
    required this.isDark,
    required this.verification,
    required this.isVerifying,
    required this.onEdit,
    required this.onDelete,
    required this.onVerify,
    required this.onSolveWithAi,
    required this.onVoiceAnswer,
    required this.onApplyCorrection,
    required this.onPickAnswer,
  });

  /// Where this question sits in the set being reviewed. Shown to the user,
  /// and the number the callbacks are about.
  final int qIndex;
  final QuizQuestion question;
  final bool isDark;

  /// What the last check of this question found, or null if none has run.
  final QuestionVerificationResult? verification;

  /// True while a check is in flight for this question.
  final bool isVerifying;

  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onVerify;
  final VoidCallback onSolveWithAi;
  final VoidCallback onVoiceAnswer;

  /// Accepts the answer a verification proposed, by its option index.
  final ValueChanged<int> onApplyCorrection;

  /// The user tapping an option to mark it the correct one.
  final ValueChanged<int> onPickAnswer;

  @override
  Widget build(BuildContext context) {
    // Taken into a local because Dart promotes locals and not fields: every
    // use below sits behind a `verification != null` check, which narrows a
    // local but can say nothing about a field someone could change between
    // the check and the use.
    final verification = this.verification;

    return Container(
      margin: const EdgeInsets.only(bottom: FluentSpacing.l),
      padding: const EdgeInsets.all(FluentSpacing.m),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: FluentRadius.cardBorder,
        border: Border.all(
          color: question.needsReview
              ? _warnColour(context)
              : (verification != null &&
                        (!verification.isCorrect || verification.isAmbiguous)
                    ? _warnColour(context)
                    : FluentStroke.card(Theme.of(context).brightness)),
          width:
              question.needsReview ||
                  (verification != null &&
                      (!verification.isCorrect || verification.isAmbiguous))
              ? 1.5
              : FluentStroke.width,
        ),
        boxShadow: FluentElevation.card(Theme.of(context).brightness),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Which test this question came off, where the page said so. One
          // page often carries the end of one model test and the start of the
          // next, and these books credit each question to an exam in
          // brackets; without showing it, a set scanned from such a page is
          // two tests the reader can no longer tell apart.
          if (question.sectionTitle != null || question.sourceExam != null) ...[
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (question.sectionTitle != null)
                  _OriginChip(
                    icon: Icons.bookmark_border,
                    label: question.sectionTitle!,
                    isDark: isDark,
                  ),
                if (question.sourceExam != null)
                  _OriginChip(
                    icon: Icons.history_edu_outlined,
                    label: question.sourceExam!,
                    isDark: isDark,
                  ),
              ],
            ),
            const SizedBox(height: FluentSpacing.s),
          ],

          // A row the scan could not actually read, or answered without
          // confidence, says so here. Without this the garbled ones look
          // exactly like the clean ones.
          if (question.correctIndex < 0) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: FluentSpacing.s),
              padding: const EdgeInsets.symmetric(
                horizontal: FluentSpacing.s,
                vertical: FluentSpacing.s,
              ),
              decoration: BoxDecoration(
                color: FluentLayer.subtle(
                  _warnColour(context),
                  Theme.of(context).brightness,
                ),
                borderRadius: FluentRadius.controlBorder,
                border: Border.all(color: _warnColour(context)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.help_outline,
                    size: 15,
                    color: _warnColour(context),
                  ),
                  const SizedBox(width: FluentSpacing.s),
                  Expanded(
                    child: Text(
                      // Naming the letter that was read matters: the reader can
                      // look at their own page and settle in one tap what the
                      // model could not. খ, ঘ and ব are the usual culprits.
                      // Both letters, where two reads of the page disagreed.
                      // The reader has the page in front of them, so naming
                      // what each read saw turns a blank into one tap.
                      question.secondReadLetter != null &&
                              question.printedAnswerLetter != null &&
                              question.secondReadLetter !=
                                  question.printedAnswerLetter
                          ? 'দুই পাঠে উত্তর মেলেনি '
                                '("${question.printedAnswerLetter}" বনাম '
                                '"${question.secondReadLetter}") '
                                '— বই দেখে সঠিক অপশনে ট্যাপ করুন'
                          : question.printedAnswerLetter != null
                          ? 'বইয়ে উত্তর আছে, কিন্তু অক্ষরটা পড়া যায়নি '
                                '(দেখাচ্ছে "${question.printedAnswerLetter}") '
                                '— সঠিক অপশনে ট্যাপ করুন'
                          : 'উত্তর নির্বাচিত নেই — অপশনে ট্যাপ করুন বা সমাধান দিন',
                      style: FluentType.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: _warnColour(context),
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => onVoiceAnswer(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: FluentSpacing.s,
                        vertical: FluentSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4F46E5).withValues(alpha: 0.1),
                        borderRadius: FluentRadius.controlBorder,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.mic, size: 12, color: Color(0xFF4F46E5)),
                          SizedBox(width: FluentSpacing.xxs),
                          Text(
                            'ভয়েস',
                            style: FluentType.caption.copyWith(
                              color: Color(0xFF4F46E5),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: FluentSpacing.xs),
                  InkWell(
                    onTap: () => onSolveWithAi(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: FluentSpacing.s,
                        vertical: FluentSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: FluentLayer.subtle(
                          _okColour(context),
                          Theme.of(context).brightness,
                        ),
                        borderRadius: FluentRadius.controlBorder,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            size: 12,
                            color: _okColour(context),
                          ),
                          SizedBox(width: FluentSpacing.xxs),
                          Text(
                            'AI সমাধান',
                            style: FluentType.caption.copyWith(
                              color: _okColour(context),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (question.needsReview) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: FluentSpacing.s),
              padding: const EdgeInsets.symmetric(
                horizontal: FluentSpacing.s,
                vertical: FluentSpacing.s,
              ),
              decoration: BoxDecoration(
                color: FluentLayer.subtle(
                  _warnColour(context),
                  Theme.of(context).brightness,
                ),
                borderRadius: FluentRadius.controlBorder,
                border: Border.all(
                  color: _warnColour(context).withValues(alpha: 0.35),
                  width: FluentStroke.width,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    question.legible
                        ? Icons.help_outline
                        : Icons.visibility_off_outlined,
                    size: 15,
                    color: _warnColour(context),
                  ),
                  const SizedBox(width: FluentSpacing.s),
                  Expanded(
                    child: Text(
                      !question.legible
                          ? 'ছবিতে এই প্রশ্নটি স্পষ্ট পড়া যায়নি — সংরক্ষণের আগে নিজে মিলিয়ে নিন বা বাদ দিন।'
                          : 'উত্তরটি অনিশ্চিত (${question.answerSource.label}) — মিলিয়ে নিন।',
                      style: FluentType.caption.copyWith(
                        color: _warnColour(context),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: FluentSpacing.s,
                  vertical: FluentSpacing.xxs,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurface
                      .withValues(alpha: 0.06),
                  borderRadius: FluentRadius.controlBorder,
                ),
                child: Text(
                  '#${qIndex + 1}',
                  style: FluentType.caption.copyWith(
                    fontWeight: FontWeight.w600,
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
                onPressed: () => onEdit(),
              ),
              const SizedBox(width: FluentSpacing.xxs),
              // Delete / Exclude button
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  size: 16,
                  color: _badColour(context),
                ),
                tooltip: 'অপ্রয়োজনীয় বা ভুল প্রশ্নটি বাদ দিন',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                onPressed: () => onDelete(),
              ),
              const SizedBox(width: FluentSpacing.xs),
              // AI Verify Single Button
              if (isVerifying)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                InkWell(
                  onTap: () => onVerify(),
                  borderRadius: FluentRadius.controlBorder,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FluentSpacing.s,
                      vertical: FluentSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: verification != null
                          ? FluentLayer.subtle(
                              verification.isCorrect &&
                                      !verification.isAmbiguous
                                  ? _okColour(context)
                                  : _warnColour(context),
                              Theme.of(context).brightness,
                            )
                          : FluentLayer.subtle(
                              Theme.of(context).colorScheme.primary,
                              Theme.of(context).brightness,
                            ),
                      borderRadius: FluentRadius.controlBorder,
                      border: Border.all(
                        color: verification != null
                            ? (verification.isCorrect &&
                                      !verification.isAmbiguous
                                  ? _okColour(context)
                                  : _warnColour(context))
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
                                    ? _okColour(context)
                                    : _warnColour(context))
                              : const Color(0xFF6366F1),
                        ),
                        const SizedBox(width: FluentSpacing.xs),
                        Text(
                          verification != null
                              ? (verification.isCorrect &&
                                        !verification.isAmbiguous
                                    ? 'AI পরীক্ষিত (সঠিক)'
                                    : 'অসঙ্গতি চিহ্নিত')
                              : 'AI যাচাই',
                          style: FluentType.caption.copyWith(
                            fontWeight: FontWeight.w600,
                            color: verification != null
                                ? (verification.isCorrect &&
                                          !verification.isAmbiguous
                                      ? _okColour(context)
                                      : _warnColour(context))
                                : const Color(0xFF4F46E5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: FluentSpacing.s),

          // Question text
          Text(question.questionText, style: FluentType.bodyStrong),
          const SizedBox(height: FluentSpacing.m),

          // Verification Alert Box (if flawed, irrelevant, or discrepancy found)
          if (verification != null &&
              (verification.isFlawed || verification.isIrrelevant)) ...[
            Container(
              margin: const EdgeInsets.only(bottom: FluentSpacing.m),
              padding: const EdgeInsets.all(FluentSpacing.m),
              decoration: BoxDecoration(
                color: FluentLayer.subtle(
                  _badColour(context),
                  Theme.of(context).brightness,
                ),
                borderRadius: FluentRadius.cardBorder,
                border: Border.all(color: _badColour(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.cancel_outlined,
                        size: 16,
                        color: _badColour(context),
                      ),
                      const SizedBox(width: FluentSpacing.s),
                      Expanded(
                        child: Text(
                          verification.isFlawed
                              ? '🚫 ত্রুটিপূর্ণ প্রশ্ন (Invalid / Flawed Question)'
                              : '🗑️ অপ্রয়োজনীয় প্রশ্ন (Redundant for BCS)',
                          style: FluentType.caption.copyWith(
                            fontWeight: FontWeight.w600,
                            color: _badColour(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (verification.explanation.isNotEmpty) ...[
                    const SizedBox(height: FluentSpacing.xs),
                    Text(
                      verification.explanation,
                      style: FluentType.caption.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                  const SizedBox(height: FluentSpacing.s),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _badColour(context),
                          side: BorderSide(color: _badColour(context)),
                          padding: const EdgeInsets.symmetric(
                            horizontal: FluentSpacing.s,
                            vertical: FluentSpacing.xs,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.delete_outline, size: 14),
                        label: const Text(
                          'প্রশ্নটি বাদ দিন',
                          style: FluentType.caption,
                        ),
                        onPressed: () => onDelete(),
                      ),
                      const SizedBox(width: FluentSpacing.s),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: FluentSpacing.s,
                            vertical: FluentSpacing.xs,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.edit, size: 14),
                        label: const Text(
                          'সংশোধন করুন',
                          style: FluentType.caption,
                        ),
                        onPressed: () => onEdit(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else if (verification != null &&
              (!verification.isCorrect || verification.isAmbiguous)) ...[
            Container(
              margin: const EdgeInsets.only(bottom: FluentSpacing.m),
              padding: const EdgeInsets.all(FluentSpacing.m),
              decoration: BoxDecoration(
                color: FluentLayer.subtle(
                  _warnColour(context),
                  Theme.of(context).brightness,
                ),
                borderRadius: FluentRadius.cardBorder,
                border: Border.all(color: _warnColour(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: _warnColour(context),
                      ),
                      const SizedBox(width: FluentSpacing.s),
                      Flexible(
                        child: Text(
                          '⚠️ সতর্কতা: বইয়ের উত্তরে অসঙ্গতি পাওয়া গেছে!',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: FluentType.caption.copyWith(
                            fontWeight: FontWeight.w600,
                            color: _warnColour(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: FluentSpacing.s),
                  Text(
                    '• বইয়ের চিহ্নিত উত্তর: ${question.correctIndex >= 0 ? "অপশন ${question.correctIndex + 1}" : "অচিহ্নিত"} (${(question.correctIndex >= 0 && question.correctIndex < question.options.length) ? question.options[question.correctIndex] : ''})',
                    style: FluentType.caption.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  if (verification.trueCorrectIndex >= 0 &&
                      verification.trueCorrectIndex <
                          question.options.length) ...[
                    const SizedBox(height: FluentSpacing.xxs),
                    Text(
                      '• AI প্রস্তাবিত সঠিক উত্তর: অপশন ${verification.trueCorrectIndex + 1} (${question.options[verification.trueCorrectIndex]})',
                      style: FluentType.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: _okColour(context),
                      ),
                    ),
                  ],
                  if (verification.explanation.isNotEmpty) ...[
                    const SizedBox(height: FluentSpacing.xs),
                    Text(
                      'ব্যাখ্যা: ${verification.explanation}',
                      style: FluentType.caption.copyWith(
                        fontStyle: FontStyle.italic,
                        color: _warnColour(context),
                      ),
                    ),
                  ],
                  if (verification.trueCorrectIndex >= 0 &&
                      verification.trueCorrectIndex < question.options.length &&
                      verification.trueCorrectIndex !=
                          question.correctIndex) ...[
                    const SizedBox(height: FluentSpacing.s),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: FluentSpacing.m,
                            vertical: FluentSpacing.xs,
                          ),
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(
                            borderRadius: FluentRadius.controlBorder,
                          ),
                        ),
                        icon: const Icon(Icons.check, size: 14),
                        label: Text(
                          'সঠিক উত্তর হিসেবে গ্রহণ করুন',
                          style: FluentType.caption.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onPressed: () =>
                            onApplyCorrection(verification.trueCorrectIndex),
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
              margin: const EdgeInsets.only(bottom: FluentSpacing.s),
              padding: const EdgeInsets.symmetric(
                horizontal: FluentSpacing.m,
                vertical: FluentSpacing.s,
              ),
              decoration: BoxDecoration(
                color: FluentLayer.subtle(
                  _okColour(context),
                  Theme.of(context).brightness,
                ),
                borderRadius: FluentRadius.controlBorder,
                border: Border.all(color: _okColour(context)),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, size: 14, color: _okColour(context)),
                  const SizedBox(width: FluentSpacing.s),
                  Expanded(
                    child: Text(
                      '✓ AI যাচাইকৃত: চিহ্নিত উত্তরটি সঠিক। ${verification.explanation}',
                      style: FluentType.caption.copyWith(
                        color: _okColour(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Options
          ...List.generate(question.options.length, (optIndex) {
            final isCorrect =
                question.correctIndex >= 0 && optIndex == question.correctIndex;
            return InkWell(
              onTap: () {
                onPickAnswer(optIndex);
              },
              borderRadius: FluentRadius.cardBorder,
              child: Container(
                margin: const EdgeInsets.only(bottom: FluentSpacing.s),
                padding: const EdgeInsets.symmetric(
                  horizontal: FluentSpacing.m,
                  vertical: FluentSpacing.s,
                ),
                decoration: BoxDecoration(
                  color: isCorrect
                      ? FluentLayer.subtle(
                          _okColour(context),
                          Theme.of(context).brightness,
                        )
                      : Theme.of(context).colorScheme.surface,
                  borderRadius: FluentRadius.controlBorder,
                  border: Border.all(
                    color: isCorrect
                        ? _okColour(context)
                        : FluentStroke.card(Theme.of(context).brightness),
                    width: isCorrect ? 1.5 : FluentStroke.width,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isCorrect
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 16,
                      color: isCorrect
                          ? _okColour(context)
                          : Theme.of(context).colorScheme.onSurface
                                .withValues(alpha: 0.65),
                    ),
                    const SizedBox(width: FluentSpacing.s),
                    Expanded(
                      child: Text(
                        question.options[optIndex],
                        style: FluentType.caption.copyWith(
                          fontWeight: isCorrect
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isCorrect
                              ? (_okColour(context))
                              : (Theme.of(context).colorScheme.onSurface),
                        ),
                      ),
                    ),
                    if (isCorrect)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: FluentSpacing.s,
                          vertical: FluentSpacing.xxs,
                        ),
                        decoration: BoxDecoration(
                          color: _okColour(context),
                          borderRadius: FluentRadius.controlBorder,
                        ),
                        child: Text(
                          'চিহ্নিত উত্তর',
                          style: FluentType.caption.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),

          if (question.explanation.isNotEmpty && verification == null) ...[
            const SizedBox(height: FluentSpacing.s),
            Container(
              padding: const EdgeInsets.all(FluentSpacing.s),
              decoration: BoxDecoration(
                color: FluentLayer.subtle(
                  _warnColour(context),
                  Theme.of(context).brightness,
                ),
                borderRadius: FluentRadius.controlBorder,
                border: Border.all(
                  color: _warnColour(context).withValues(alpha: 0.35),
                  width: FluentStroke.width,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 14,
                    color: _warnColour(context),
                  ),
                  const SizedBox(width: FluentSpacing.s),
                  Expanded(
                    child: Text(
                      'ব্যাখ্যা: ${question.explanation}',
                      style: FluentType.caption.copyWith(
                        color: _warnColour(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (question.explanation.isEmpty && verification == null) ...[
            const SizedBox(height: FluentSpacing.s),
            InkWell(
              onTap: () => onEdit(),
              borderRadius: FluentRadius.controlBorder,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: FluentSpacing.s,
                  vertical: FluentSpacing.s,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurface
                      .withValues(alpha: 0.06),
                  borderRadius: FluentRadius.controlBorder,
                  border: Border.all(
                    color: FluentStroke.card(Theme.of(context).brightness),
                    width: FluentStroke.width,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.edit_note,
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurface
                          .withValues(alpha: 0.65),
                    ),
                    const SizedBox(width: FluentSpacing.s),
                    Flexible(
                      child: Text(
                        '+ ব্যাখ্যা যোগ করুন (লিখুন বা মুখে বলুন)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FluentType.caption.copyWith(
                          color: Theme.of(context).colorScheme.onSurface
                              .withValues(alpha: 0.65),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A small label saying where a scanned question came from.
class _OriginChip extends StatelessWidget {
  const _OriginChip({
    required this.icon,
    required this.label,
    required this.isDark,
  });

  final IconData icon;
  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final colour = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FluentSpacing.s,
        vertical: FluentSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: FluentLayer.subtle(colour, Theme.of(context).brightness),
        borderRadius: FluentRadius.controlBorder,
        border: Border.all(
          color: colour.withValues(alpha: 0.35),
          width: FluentStroke.width,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: colour),
          const SizedBox(width: FluentSpacing.xs),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FluentType.caption.copyWith(
                fontWeight: FontWeight.w600,
                color: colour,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
