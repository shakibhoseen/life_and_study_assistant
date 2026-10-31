import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/services/ai/entity_ref.dart';
import '../../../../core/services/ai/models/verification_mark.dart';
import '../../../../core/utils/bengali_math_sanitizer.dart';
import '../../../quiz/presentation/providers/drill_history_provider.dart';
import '../../domain/models/mistake_folder.dart';
import 'ai_mistake_explainer_sheet.dart';
import 'save_to_flashcard_sheet.dart';

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
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colour.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: colour),
          const SizedBox(width: 4),
          Text(
            mark.label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              color: colour,
            ),
          ),
        ],
      ),
    );
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

    return Card(
      elevation: 1.5,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(14),
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
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.indigo.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            dq.subject,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: source.color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: source.color.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(source.icon, size: 11, color: source.color),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  source.banglaLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
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
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, size: 12, color: Colors.green),
                        SizedBox(width: 3),
                        Text(
                          'আয়ত্তে এসেছে',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(width: 4),
                SizedBox(
                  width: 24,
                  height: 24,
                  child: PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      Icons.more_vert,
                      size: 18,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                    tooltip: 'Options',
                    onSelected: (val) {
                      if (val == 'toggle_mastered') {
                        HapticFeedback.mediumImpact();
                        ref
                            .read(drillHistoryNotifierProvider.notifier)
                            .markQuestionMastered(dq.id, !dq.isMastered);
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
                                  ? Colors.amber
                                  : Colors.green,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              dq.isMastered
                                  ? 'আবার ভুল হিসেবে রাখুন'
                                  : 'আয়ত্তে এসেছে চিহ্নিত করুন',
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'ai_explain',
                        child: Row(
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              size: 16,
                              color: Color(0xFF8B5CF6),
                            ),
                            SizedBox(width: 8),
                            Text('AI ভুল বিশ্লেষণ ও শর্টকাট'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'copy_ref',
                        child: Row(
                          children: [
                            const Icon(
                              Icons.tag,
                              size: 16,
                              color: Colors.blueGrey,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'আইডি কপি (${EntityRef(EntityKind.question, dq.id).tag})',
                            ),
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
                              color: Colors.red,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'নোটবুক থেকে মুছুন',
                              style: TextStyle(color: Colors.red),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Topic name
            Text(
              'টপিক: ${dq.topic}',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
            const SizedBox(height: 8),

            // Question Text
            Text(
              BengaliMathSanitizer.sanitize(dq.questionText),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),

            // User's wrong answer (Red)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.cancel, color: Colors.redAccent, size: 15),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'আপনার উত্তর: $userAns',
                      style: TextStyle(
                        fontSize: 11.5,
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
            const SizedBox(height: 6),

            // Correct answer (Green)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 15),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'সঠিক উত্তর: $correctAns',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark
                            ? Colors.green.shade200
                            : Colors.green.shade900,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (dq.originalCorrectIndex != null) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  'পূর্বে সংরক্ষিত উত্তর ছিল: ${getOptionText(dq.originalOptionsJson ?? dq.optionsJson, dq.originalCorrectIndex!)}',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontStyle: FontStyle.italic,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
              ),
            ],

            // Explanation & Key rule
            if (dq.explanation.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1C2237)
                      : Colors.amber.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.amber.withValues(alpha: 0.25),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.lightbulb_outline,
                          size: 14,
                          color: Colors.amber,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'ব্যাখ্যা ও মনে রাখার ট্রিকস:',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? Colors.amber.shade300
                                : Colors.amber.shade900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    MarkdownBody(
                      data: BengaliMathSanitizer.sanitize(dq.explanation),
                      selectable: true,
                      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                          .copyWith(
                            p: TextStyle(
                              fontSize: 11.5,
                              height: 1.45,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                            strong: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? Colors.amber.shade200
                                  : const Color(0xFF0F172A),
                            ),
                          ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),

            // Whether this answer has been checked, and by whom.
            Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                borderRadius: BorderRadius.circular(5),
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
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.copy,
                        size: 11,
                        color: isDark ? Colors.white30 : Colors.black26,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        EntityRef(EntityKind.question, dq.id).tag,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontFamily: 'monospace',
                          letterSpacing: 0.4,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),

            if (VerificationMark.parse(dq.verificationStatus) !=
                VerificationMark.none) ...[
              _buildVerificationBadge(
                VerificationMark.parse(dq.verificationStatus),
              ),
              const SizedBox(height: 6),
            ],

            // Action Toolbar at Bottom of Card
            Row(
              children: [
                // AI Explainer button
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => AiMistakeExplainerSheet.show(context, dq),
                  icon: const Icon(
                    Icons.auto_awesome,
                    size: 14,
                    color: Color(0xFF8B5CF6),
                  ),
                  label: const Text(
                    'AI বিশ্লেষণ',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF8B5CF6),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Flashcard Save button (Zero token cost)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => SaveToFlashcardSheet.show(context, dq),
                  icon: const Icon(
                    Icons.style_outlined,
                    size: 14,
                    color: Color(0xFF6366F1),
                  ),
                  label: const Text(
                    'ফ্ল্যাশকার্ড',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF6366F1),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),

                // Toggle Mastered Button
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
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
                    size: 14,
                    color: dq.isMastered ? Colors.amber : Colors.green,
                  ),
                  label: Text(
                    dq.isMastered ? 'আবার ভুল রাখুন' : 'আয়ত্তে এসেছে',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: dq.isMastered ? Colors.amber : Colors.green,
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
