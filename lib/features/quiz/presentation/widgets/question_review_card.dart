import 'package:flutter/material.dart';

import '../../../../core/services/ai/models/quiz_question.dart';
import '../../../../core/services/ai/question_bank_ocr_service.dart';

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
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: question.needsReview
              ? Colors.orange.shade600
              : (verification != null &&
                        (!verification.isCorrect || verification.isAmbiguous)
                    ? Colors.amber.shade600
                    : (isDark
                          ? const Color(0xFF334155)
                          : Colors.grey.shade300)),
          width:
              question.needsReview ||
                  (verification != null &&
                      (!verification.isCorrect || verification.isAmbiguous))
              ? 1.8
              : 1.0,
        ),
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
            const SizedBox(height: 8),
          ],

          // A row the scan could not actually read, or answered without
          // confidence, says so here. Without this the garbled ones look
          // exactly like the clean ones.
          if (question.correctIndex < 0) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 9),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: isDark ? 0.2 : 0.12),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: Colors.amber.shade600),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.help_outline,
                    size: 15,
                    color: Colors.amber.shade900,
                  ),
                  const SizedBox(width: 7),
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
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? Colors.amber.shade200
                            : Colors.amber.shade900,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => onVoiceAnswer(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4F46E5).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.mic, size: 12, color: Color(0xFF4F46E5)),
                          SizedBox(width: 2),
                          Text(
                            'ভয়েস',
                            style: TextStyle(
                              fontSize: 10,
                              color: Color(0xFF4F46E5),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () => onSolveWithAi(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            size: 12,
                            color: Color(0xFF10B981),
                          ),
                          SizedBox(width: 2),
                          Text(
                            'AI সমাধান',
                            style: TextStyle(
                              fontSize: 10,
                              color: Color(0xFF10B981),
                              fontWeight: FontWeight.bold,
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
                    question.legible
                        ? Icons.help_outline
                        : Icons.visibility_off_outlined,
                    size: 15,
                    color: Colors.orange.shade800,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      !question.legible
                          ? 'ছবিতে এই প্রশ্নটি স্পষ্ট পড়া যায়নি — সংরক্ষণের আগে নিজে মিলিয়ে নিন বা বাদ দিন।'
                          : 'উত্তরটি অনিশ্চিত (${question.answerSource.label}) — মিলিয়ে নিন।',
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
                onPressed: () => onEdit(),
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
                onPressed: () => onDelete(),
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
                  onTap: () => onVerify(),
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
            question.questionText,
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
                        onPressed: () => onDelete(),
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
                      Flexible(
                        child: Text(
                          '⚠️ সতর্কতা: বইয়ের উত্তরে অসঙ্গতি পাওয়া গেছে!',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
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
                  const SizedBox(height: 6),
                  Text(
                    '• বইয়ের চিহ্নিত উত্তর: ${question.correctIndex >= 0 ? "অপশন ${question.correctIndex + 1}" : "অচিহ্নিত"} (${(question.correctIndex >= 0 && question.correctIndex < question.options.length) ? question.options[question.correctIndex] : ''})',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  if (verification.trueCorrectIndex >= 0 &&
                      verification.trueCorrectIndex < question.options.length) ...[
                    const SizedBox(height: 2),
                    Text(
                      '• AI প্রস্তাবিত সঠিক উত্তর: অপশন ${verification.trueCorrectIndex + 1} (${question.options[verification.trueCorrectIndex]})',
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
                      verification.trueCorrectIndex < question.options.length &&
                      verification.trueCorrectIndex != question.correctIndex) ...[
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
                        onPressed: () => onApplyCorrection(verification.trueCorrectIndex),
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
          ...List.generate(question.options.length, (optIndex) {
            final isCorrect = question.correctIndex >= 0 && optIndex == question.correctIndex;
            return InkWell(
              onTap: () {
                onPickAnswer(optIndex);
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
                        question.options[optIndex],
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

          if (question.explanation.isNotEmpty && verification == null) ...[
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
                      'ব্যাখ্যা: ${question.explanation}',
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
          ] else if (question.explanation.isEmpty && verification == null) ...[
            const SizedBox(height: 6),
            InkWell(
              onTap: () => onEdit(),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E293B).withValues(alpha: 0.5)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isDark ? const Color(0xFF334155) : Colors.grey.shade300,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.edit_note,
                      size: 14,
                      color: isDark ? Colors.blueGrey.shade300 : Colors.blueGrey,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '+ ব্যাখ্যা যোগ করুন (লিখুন বা মুখে বলুন)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? Colors.blueGrey.shade300
                              : Colors.blueGrey,
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
    final colour = isDark ? const Color(0xFFA5B4FC) : const Color(0xFF4F46E5);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: isDark ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: colour.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: colour),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
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
