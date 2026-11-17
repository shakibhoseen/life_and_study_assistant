import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/services/ai/entity_ref.dart';
import '../../../../core/services/ai/models/verification_mark.dart';
import '../../../../core/theme/fluent_tokens.dart';
import '../../../../core/utils/bengali_math_sanitizer.dart';
import '../../../quiz/presentation/providers/drill_history_provider.dart';
import '../../domain/models/mistake_folder.dart';
import 'ai_mistake_explainer_sheet.dart';
import 'save_to_flashcard_sheet.dart';
import 'edit_question_dialog.dart';
import '../../../../core/database/database_provider.dart';
import 'mistake_kind_chips.dart';

/// The status palette for this feature. One value each, picked to stay
/// readable on both the light and the dark card surface, so "right", "wrong"
/// and "mastered" read the same wherever they appear.
const Color _correctColor = Color(0xFF10B981); // green — the right answer
const Color _wrongColor = Color(0xFFE11D48); // red — what was answered
const Color _hintColor = Color(0xFFD97706); // amber — explanation / undo

class MistakeQuestionCard extends ConsumerWidget {
  final DrillQuestion dq;
  final bool isDark;

  const MistakeQuestionCard({
    super.key,
    required this.dq,
    required this.isDark,
  });

  static String getOptionText(String optionsJson, int index) {
    try {
      final decoded = jsonDecode(optionsJson);
      if (decoded is List && index >= 0 && index < decoded.length) {
        return decoded[index].toString();
      }
    } catch (_) {}
    return '(অজানা)';
  }

  Widget _buildVerificationBadge(VerificationMark mark) {
    final (colour, icon) = switch (mark) {
      VerificationMark.userVerified => (Colors.green, Icons.verified),
      VerificationMark.modelAgreed => (
        Colors.blueGrey,
        Icons.check_circle_outline,
      ),
      VerificationMark.flagged => (Colors.orange, Icons.flag_outlined),
      VerificationMark.none => (Colors.transparent, Icons.circle),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FluentSpacing.s,
        vertical: FluentSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.1),
        borderRadius: FluentRadius.controlBorder,
        border: Border.all(
          color: colour.withValues(alpha: 0.3),
          width: FluentStroke.width,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: colour),
          const SizedBox(width: FluentSpacing.xs),
          Flexible(
            child: Text(
              mark.label,
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

  Future<void> _editByHand(BuildContext context, WidgetRef ref) async {
    final edit = await EditQuestionDialog.show(context, dq);
    if (edit == null) return;

    // selectedIndex and isCorrect are deliberately untouched: they record
    // what was answered at the time, which a later correction does not undo.
    await ref
        .read(appDatabaseProvider)
        .applyQuestionEdit(
          dq.id,
          questionText: edit.questionText,
          options: edit.options,
          correctIndex: edit.correctIndex,
          explanation: edit.explanation,
        );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('প্রশ্নটি বদলানো হলো')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = detectMistakeSource(dq);

    List<String> options = [];
    try {
      final decoded = jsonDecode(dq.optionsJson);
      if (decoded is List) {
        options = decoded.map((e) => e.toString()).toList();
      }
    } catch (_) {}

    final userAns = (dq.selectedIndex >= 0 && dq.selectedIndex < options.length)
        ? options[dq.selectedIndex]
        : 'উত্তর দাগানো হয়নি';
    final correctAns =
        (dq.correctIndex >= 0 && dq.correctIndex < options.length)
        ? options[dq.correctIndex]
        : 'Unknown';

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    final onSurface = scheme.onSurface;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: FluentSpacing.m),
      shape: RoundedRectangleBorder(
        borderRadius: FluentRadius.cardBorder,
        side: FluentStroke.side(brightness),
      ),
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(FluentSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Subject & Topic, Source Badge, Menu
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: FluentSpacing.s,
                            vertical: FluentSpacing.xxs,
                          ),
                          decoration: BoxDecoration(
                            color: FluentLayer.subtle(
                              scheme.primary,
                              brightness,
                            ),
                            borderRadius: FluentRadius.controlBorder,
                          ),
                          child: Text(
                            dq.subject,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FluentType.caption.copyWith(
                              fontWeight: FontWeight.w600,
                              color: scheme.primary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: FluentSpacing.xs),
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: FluentSpacing.xs,
                            vertical: FluentSpacing.xxs,
                          ),
                          decoration: BoxDecoration(
                            color: FluentLayer.subtle(
                              source.color,
                              brightness,
                            ),
                            borderRadius: FluentRadius.controlBorder,
                            border: Border.all(
                              color: source.color.withValues(alpha: 0.25),
                              width: FluentStroke.width,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(source.icon, size: 12, color: source.color),
                              const SizedBox(width: FluentSpacing.xs),
                              Flexible(
                                child: Text(
                                  source.banglaLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: FluentType.caption.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: source.color,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (dq.isMastered) ...[
                  const SizedBox(width: FluentSpacing.xs),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FluentSpacing.xs,
                      vertical: FluentSpacing.xxs,
                    ),
                    decoration: BoxDecoration(
                      color: FluentLayer.subtle(_correctColor, brightness),
                      borderRadius: FluentRadius.controlBorder,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.check_circle,
                          size: 12,
                          color: _correctColor,
                        ),
                        const SizedBox(width: FluentSpacing.xs),
                        Text(
                          'আয়ত্তে এসেছে',
                          style: FluentType.caption.copyWith(
                            fontWeight: FontWeight.w600,
                            color: _correctColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(width: FluentSpacing.xs),
                SizedBox(
                  width: 24,
                  height: 24,
                  child: PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      Icons.more_vert,
                      size: 18,
                      color: onSurface.withValues(alpha: 0.65),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: FluentRadius.cardBorder,
                      side: FluentStroke.side(brightness),
                    ),
                    tooltip: 'Options',
                    onSelected: (val) {
                      if (val == 'toggle_mastered') {
                        HapticFeedback.mediumImpact();
                        ref
                            .read(drillHistoryNotifierProvider.notifier)
                            .markQuestionMastered(dq.id, !dq.isMastered);
                      } else if (val == 'edit') {
                        _editByHand(context, ref);
                      } else if (val == 'ai_explain') {
                        AiMistakeExplainerSheet.show(context, dq);
                      } else if (val == 'copy_ref') {
                        // Paste this into the mentor to talk about this exact
                        // question instead of describing it again.
                        final tag = EntityRef(EntityKind.question, dq.id).tag;
                        Clipboard.setData(ClipboardData(text: tag));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '$tag কপি হয়েছে — AI মেন্টরে পেস্ট করে বলুন কী সমস্যা',
                            ),
                          ),
                        );
                      } else if (val == 'delete') {
                        ref
                            .read(drillHistoryNotifierProvider.notifier)
                            .deleteQuestion(dq.id);
                      }
                    },
                    itemBuilder: (ctx) => [
                      PopupMenuItem(
                        value: 'toggle_mastered',
                        child: Row(
                          children: [
                            Icon(
                              dq.isMastered ? Icons.replay : Icons.check_circle,
                              size: 16,
                              color: dq.isMastered
                                  ? _hintColor
                                  : _correctColor,
                            ),
                            const SizedBox(width: FluentSpacing.s),
                            Text(
                              dq.isMastered
                                  ? 'আবার ভুল হিসেবে রাখুন'
                                  : 'আয়ত্তে এসেছে চিহ্নিত করুন',
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'ai_explain',
                        child: Row(
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              size: 16,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: FluentSpacing.s),
                            Text('AI ভুল বিশ্লেষণ ও শর্টকাট'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'copy_ref',
                        child: Row(
                          children: [
                            Icon(
                              Icons.tag,
                              size: 16,
                              color: onSurface.withValues(alpha: 0.65),
                            ),
                            const SizedBox(width: FluentSpacing.s),
                            Text(
                              'আইডি কপি (${EntityRef(EntityKind.question, dq.id).tag})',
                            ),
                          ],
                        ),
                      ),
                      // A typo or a misread option does not need the model,
                      // which costs tokens and a wait to fix what the user can
                      // already see.
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 16),
                            SizedBox(width: FluentSpacing.s),
                            Text('নিজে সম্পাদনা করুন'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline,
                              size: 16,
                              color: _wrongColor,
                            ),
                            SizedBox(width: FluentSpacing.s),
                            Text(
                              'নোটবুক থেকে মুছুন',
                              style: TextStyle(color: _wrongColor),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: FluentSpacing.s),

            // Topic name
            Text(
              'টপিক: ${dq.topic}',
              style: FluentType.caption.copyWith(
                color: onSurface.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: FluentSpacing.s),

            // Question Text
            Text(
              BengaliMathSanitizer.sanitize(dq.questionText),
              style: FluentType.bodyStrong.copyWith(color: onSurface),
            ),
            const SizedBox(height: FluentSpacing.m),

            // User's wrong answer (Red)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: FluentSpacing.m,
                vertical: FluentSpacing.s,
              ),
              decoration: BoxDecoration(
                color: FluentLayer.subtle(_wrongColor, brightness),
                borderRadius: FluentRadius.controlBorder,
                border: Border.all(
                  color: _wrongColor.withValues(alpha: 0.25),
                  width: FluentStroke.width,
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.cancel, color: _wrongColor, size: 16),
                  const SizedBox(width: FluentSpacing.s),
                  Expanded(
                    child: Text(
                      'আপনার উত্তর: $userAns',
                      style: FluentType.body.copyWith(
                        color: isDark
                            ? Colors.red.shade200
                            : Colors.red.shade900,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: FluentSpacing.s),

            // Correct answer (Green)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: FluentSpacing.m,
                vertical: FluentSpacing.s,
              ),
              decoration: BoxDecoration(
                color: FluentLayer.subtle(_correctColor, brightness),
                borderRadius: FluentRadius.controlBorder,
                border: Border.all(
                  color: _correctColor.withValues(alpha: 0.25),
                  width: FluentStroke.width,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle,
                    color: _correctColor,
                    size: 16,
                  ),
                  const SizedBox(width: FluentSpacing.s),
                  Expanded(
                    child: Text(
                      'সঠিক উত্তর: $correctAns',
                      style: FluentType.body.copyWith(
                        color: isDark
                            ? Colors.green.shade200
                            : Colors.green.shade900,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (dq.originalCorrectIndex != null) ...[
              const SizedBox(height: FluentSpacing.xs),
              Padding(
                padding: const EdgeInsets.only(left: FluentSpacing.xs),
                child: Text(
                  'পূর্বে সংরক্ষিত উত্তর ছিল: ${getOptionText(dq.originalOptionsJson ?? dq.optionsJson, dq.originalCorrectIndex!)}',
                  style: FluentType.caption.copyWith(
                    fontStyle: FontStyle.italic,
                    color: onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ),
            ],

            // Explanation & Key rule
            if (dq.explanation.isNotEmpty) ...[
              const SizedBox(height: FluentSpacing.s),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(FluentSpacing.m),
                decoration: BoxDecoration(
                  color: FluentLayer.subtle(_hintColor, brightness),
                  borderRadius: FluentRadius.cardBorder,
                  border: Border.all(
                    color: _hintColor.withValues(alpha: 0.25),
                    width: FluentStroke.width,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.lightbulb_outline,
                          size: 16,
                          color: _hintColor,
                        ),
                        const SizedBox(width: FluentSpacing.xs),
                        Flexible(
                          child: Text(
                            'ব্যাখ্যা ও মনে রাখার ট্রিকস:',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FluentType.caption.copyWith(
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Colors.amber.shade300
                                  : Colors.amber.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: FluentSpacing.xs),
                    MarkdownBody(
                      data: BengaliMathSanitizer.sanitize(dq.explanation),
                      selectable: true,
                      styleSheet:
                          MarkdownStyleSheet.fromTheme(
                            Theme.of(context),
                          ).copyWith(
                            p: FluentType.body.copyWith(color: onSurface),
                            strong: FluentType.bodyStrong.copyWith(
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
            const SizedBox(height: FluentSpacing.s),

            // Whether this answer has been checked, and by whom.
            Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                borderRadius: FluentRadius.controlBorder,
                onTap: () {
                  final tag = EntityRef(EntityKind.question, dq.id).tag;
                  Clipboard.setData(ClipboardData(text: tag));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '$tag কপি হয়েছে — AI মেন্টরে পেস্ট করে বলুন কী সমস্যা',
                      ),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FluentSpacing.xs,
                    vertical: FluentSpacing.xxs,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.copy,
                        size: 12,
                        color: onSurface.withValues(alpha: 0.45),
                      ),
                      const SizedBox(width: FluentSpacing.xs),
                      Flexible(
                        child: Text(
                          EntityRef(EntityKind.question, dq.id).tag,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: FluentType.caption.copyWith(
                            fontFamily: 'monospace',
                            letterSpacing: 0.4,
                            color: onSurface.withValues(alpha: 0.45),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: FluentSpacing.xs),

            if (VerificationMark.parse(dq.verificationStatus) !=
                VerificationMark.none) ...[
              _buildVerificationBadge(
                VerificationMark.parse(dq.verificationStatus),
              ),
              const SizedBox(height: FluentSpacing.s),
            ],

            // Which paper it came from, when the import knew. Worth seeing
            // on the question itself: a mistake on something that has been
            // asked three times is not the same mistake as one on a topic
            // that has been asked once.
            if ((dq.sourceExam ?? '').trim().isNotEmpty) ...[
              Row(
                children: [
                  Icon(
                    Icons.history_edu_outlined,
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: FluentSpacing.xs),
                  Expanded(
                    child: Text(
                      dq.sourceExam!.trim(),
                      style: FluentType.caption.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: FluentSpacing.s),
            ],

            // Why it went wrong — asked here, where the question is still
            // in front of the user, rather than on a screen they would have
            // to go and open.
            MistakeKindChips(dq: dq),
            const SizedBox(height: FluentSpacing.s),

            // Action Toolbar at Bottom of Card
            Row(
              children: [
                // AI Explainer button
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FluentSpacing.s,
                      vertical: FluentSpacing.xs,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: FluentRadius.controlBorder,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => AiMistakeExplainerSheet.show(context, dq),
                  icon: Icon(
                    Icons.auto_awesome,
                    size: 16,
                    color: scheme.primary,
                  ),
                  label: Text(
                    'AI বিশ্লেষণ',
                    style: FluentType.caption.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: FluentSpacing.xs),
                // Flashcard Save button (Zero token cost)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FluentSpacing.s,
                      vertical: FluentSpacing.xs,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: FluentRadius.controlBorder,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => SaveToFlashcardSheet.show(context, dq),
                  icon: Icon(
                    Icons.style_outlined,
                    size: 16,
                    color: onSurface.withValues(alpha: 0.65),
                  ),
                  label: Text(
                    'ফ্ল্যাশকার্ড',
                    style: FluentType.caption.copyWith(
                      color: onSurface.withValues(alpha: 0.65),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),

                // Toggle Mastered Button
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FluentSpacing.s,
                      vertical: FluentSpacing.xs,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: FluentRadius.controlBorder,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    ref
                        .read(drillHistoryNotifierProvider.notifier)
                        .markQuestionMastered(dq.id, !dq.isMastered);
                  },
                  icon: Icon(
                    dq.isMastered ? Icons.replay : Icons.check_circle_outline,
                    size: 16,
                    color: dq.isMastered ? _hintColor : _correctColor,
                  ),
                  label: Text(
                    dq.isMastered ? 'আবার ভুল রাখুন' : 'আয়ত্তে এসেছে',
                    style: FluentType.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: dq.isMastered ? _hintColor : _correctColor,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
