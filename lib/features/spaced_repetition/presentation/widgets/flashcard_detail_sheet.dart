import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/flashcards/flashcard_service.dart';
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
  bool _marked = false;

  Future<void> _markRecalled() async {
    final id = widget.card.reviewItemId;
    if (id != null) {
      await ref
          .read(spacedRepetitionNotifierProvider.notifier)
          .advanceReview(id);
    }
    if (!mounted) return;
    setState(() => _marked = true);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = widget.card;
    final fromReview = card.reviewItemId != null;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.82,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 10),
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('🧠', style: TextStyle(fontSize: 17)),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          [
                            card.subject,
                            if (card.topic.isNotEmpty) card.topic,
                          ].join(' · '),
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                            color: isDark ? Colors.white54 : Colors.black45,
                          ),
                        ),
                      ),
                      if (fromReview)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.indigo.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'রিভিশন',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Shown in full: this is the whole reason the sheet exists.
                  SelectableText(
                    BengaliMathSanitizer.sanitize(card.title),
                    style: TextStyle(
                      fontSize: 17,
                      height: 1.45,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF0F172A)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SelectableText(
                      BengaliMathSanitizer.sanitize(card.content),
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.65,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ),
                  if ((card.mnemonic ?? '').isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(
                          alpha: isDark ? 0.14 : 0.1,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.amber.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('💡', style: TextStyle(fontSize: 14)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SelectableText(
                              BengaliMathSanitizer.sanitize(card.mnemonic!),
                              style: TextStyle(
                                fontSize: 13.5,
                                height: 1.55,
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
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
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
                const SizedBox(width: 4),
                Expanded(
                  child: _marked
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.check_circle,
                              size: 17,
                              color: Colors.green,
                            ),
                            const SizedBox(width: 7),
                            Text(
                              fromReview
                                  ? 'পরের রিভিশন পিছিয়ে দেওয়া হলো'
                                  : 'মনে রাখা হলো',
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        )
                      : FilledButton.icon(
                          onPressed: _markRecalled,
                          icon: const Icon(Icons.done, size: 18),
                          label: const Text('মনে থাকবে'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 13),
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
}
