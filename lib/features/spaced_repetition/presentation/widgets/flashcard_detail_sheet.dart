import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/flashcards/flashcard_service.dart';
import '../../../../core/theme/fluent_tokens.dart';
import '../../../../core/utils/bengali_math_sanitizer.dart';
import '../providers/spaced_repetition_provider.dart';

/// The whole card, after its notification is tapped.
///
/// A notification shows one truncated title line and a capped body, which is
/// no place for a long rule or a formula. Everything the card holds is shown
/// here instead, scrollable and selectable.
class FlashcardDetailSheet extends ConsumerStatefulWidget {
  final FlashcardItem card;

  const FlashcardDetailSheet({super.key, required this.card});

  static Future<void> show(BuildContext context, FlashcardItem card) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FlashcardDetailSheet(card: card),
    );
  }

  @override
  ConsumerState<FlashcardDetailSheet> createState() =>
      _FlashcardDetailSheetState();
}

class _FlashcardDetailSheetState extends ConsumerState<FlashcardDetailSheet> {
  /// null until the card is graded, then true for recalled, false for forgot.
  bool? _recalled;

  Future<void> _grade({required bool recalled}) async {
    final id = widget.card.reviewItemId;
    if (id != null) {
      final notifier = ref.read(spacedRepetitionNotifierProvider.notifier);
      // Forgetting is the signal the schedule needs most: without it a card
      // the user could not recall is simply pushed further away.
      recalled
          ? await notifier.advanceReview(id)
          : await notifier.resetReview(id);
    }
    if (!mounted) return;
    setState(() => _recalled = recalled);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final card = widget.card;
    final fromReview = card.reviewItemId != null;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.82,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(FluentRadius.large),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(
              top: FluentSpacing.s,
              bottom: FluentSpacing.s,
            ),
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.onSurface.withValues(alpha: 0.3),
              borderRadius: FluentRadius.controlBorder,
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                FluentSpacing.xl,
                FluentSpacing.xs,
                FluentSpacing.xl,
                FluentSpacing.l,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('🧠', style: TextStyle(fontSize: 17)),
                      const SizedBox(width: FluentSpacing.s),
                      Expanded(
                        child: Text(
                          [
                            card.subject,
                            if (card.topic.isNotEmpty) card.topic,
                          ].join(' · '),
                          style: FluentType.caption.copyWith(
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                            color: scheme.onSurface.withValues(alpha: 0.65),
                          ),
                        ),
                      ),
                      if (fromReview)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: FluentSpacing.s,
                            vertical: FluentSpacing.xxs,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.indigo.withValues(alpha: 0.12),
                            borderRadius: FluentRadius.controlBorder,
                          ),
                          child: Text(
                            'রিভিশন',
                            style: FluentType.caption.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Colors.indigo,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: FluentSpacing.m),

                  // Shown in full: this is the whole reason the sheet exists.
                  SelectableText(
                    BengaliMathSanitizer.sanitize(card.title),
                    style: FluentType.subtitle.copyWith(
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: FluentSpacing.m),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(FluentSpacing.m),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF0F172A)
                          : const Color(0xFFF1F5F9),
                      borderRadius: FluentRadius.cardBorder,
                    ),
                    child: SelectableText(
                      BengaliMathSanitizer.sanitize(card.content),
                      style: FluentType.body.copyWith(color: scheme.onSurface),
                    ),
                  ),
                  if ((card.mnemonic ?? '').isNotEmpty) ...[
                    const SizedBox(height: FluentSpacing.m),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(FluentSpacing.m),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(
                          alpha: isDark ? 0.14 : 0.1,
                        ),
                        borderRadius: FluentRadius.cardBorder,
                        border: Border.all(
                          color: Colors.amber.withValues(alpha: 0.35),
                          width: FluentStroke.width,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('💡', style: TextStyle(fontSize: 14)),
                          const SizedBox(width: FluentSpacing.s),
                          Expanded(
                            child: SelectableText(
                              BengaliMathSanitizer.sanitize(card.mnemonic!),
                              style: FluentType.body.copyWith(
                                color: isDark
                                    ? Colors.amber.shade100
                                    : Colors.brown.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FluentSpacing.l,
              FluentSpacing.s,
              FluentSpacing.l,
              FluentSpacing.xl,
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'কপি করুন',
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(
                        text:
                            '${card.title}\n${card.content}'
                            '${(card.mnemonic ?? '').isEmpty ? '' : '\n${card.mnemonic}'}',
                      ),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('কার্ডটি কপি হয়েছে')),
                    );
                  },
                  icon: const Icon(Icons.copy_outlined, size: 19),
                ),
                const SizedBox(width: FluentSpacing.xs),
                Expanded(
                  child: _recalled != null
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _recalled!
                                  ? Icons.check_circle
                                  : Icons.refresh_rounded,
                              size: 17,
                              color: _recalled!
                                  ? Colors.green
                                  : Colors.orange.shade700,
                            ),
                            const SizedBox(width: FluentSpacing.s),
                            Flexible(
                              child: Text(
                                _recalled!
                                    ? (fromReview
                                          ? 'পরের রিভিশন পিছিয়ে দেওয়া হলো'
                                          : 'মনে রাখা হলো')
                                    : 'কালই আবার দেখাবে',
                                style: FluentType.caption.copyWith(
                                  color: _recalled!
                                      ? Colors.green
                                      : Colors.orange.shade700,
                                ),
                              ),
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            if (fromReview) ...[
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _grade(recalled: false),
                                  icon: const Icon(Icons.refresh, size: 17),
                                  label: Text('মনে নেই', style: FluentType.body),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.orange.shade800,
                                    side: BorderSide(
                                      color: Colors.orange.shade300,
                                      width: FluentStroke.width,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                          FluentRadius.controlBorder,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: FluentSpacing.m,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: FluentSpacing.s),
                            ],
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => _grade(recalled: true),
                                icon: const Icon(Icons.done, size: 18),
                                label: Text(
                                  'মনে থাকবে',
                                  style: FluentType.body,
                                ),
                                style: FilledButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: FluentRadius.controlBorder,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: FluentSpacing.m,
                                  ),
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
    );
  }
}
