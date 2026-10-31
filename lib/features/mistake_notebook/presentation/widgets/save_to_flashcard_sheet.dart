import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../spaced_repetition/presentation/providers/spaced_repetition_provider.dart';

class SaveToFlashcardSheet extends ConsumerStatefulWidget {
  final DrillQuestion question;

  const SaveToFlashcardSheet({super.key, required this.question});

  static Future<bool?> show(BuildContext context, DrillQuestion question) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SaveToFlashcardSheet(question: question),
    );
  }

  @override
  ConsumerState<SaveToFlashcardSheet> createState() =>
      _SaveToFlashcardSheetState();
}

class _SaveToFlashcardSheetState extends ConsumerState<SaveToFlashcardSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _ruleController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: widget.question.questionText.trim(),
    );

    List<String> options = [];
    try {
      final decoded = jsonDecode(widget.question.optionsJson);
      if (decoded is List) {
        options = decoded.map((e) => e.toString()).toList();
      }
    } catch (_) {}

    final correctAns =
        (widget.question.correctIndex >= 0 &&
            widget.question.correctIndex < options.length)
        ? options[widget.question.correctIndex]
        : 'অজ্ঞাত';

    final buffer = StringBuffer('সঠিক উত্তর: $correctAns');
    if (widget.question.explanation.trim().isNotEmpty) {
      buffer.writeln('\n\nব্যাখ্যা:\n${widget.question.explanation.trim()}');
    }

    _ruleController = TextEditingController(text: buffer.toString());
  }

  @override
  void dispose() {
    _titleController.dispose();
    _ruleController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final title = _titleController.text.trim();
    final rule = _ruleController.text.trim();

    if (title.isEmpty || rule.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('প্রশ্ন ও উত্তর কোনোটি খালি রাখা যাবে না'),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final db = ref.read(appDatabaseProvider);

      // Check if already in flashcard deck
      final existing =
          await (db.select(db.spacedReviewItems)
                ..where((t) => t.title.equals(title))
                ..limit(1))
              .getSingleOrNull();

      if (existing != null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('এই প্রশ্নটি অলরেডি ফ্ল্যাশকার্ড ডেকে সংরক্ষিত আছে!'),
            backgroundColor: Colors.orange,
          ),
        );
        Navigator.pop(context, false);
        return;
      }

      await db.insertSpacedReviewItem(
        SpacedReviewItemsCompanion.insert(
          subject: widget.question.subject,
          topic: widget.question.topic,
          title: title,
          keyRule: rule,
          repetitionLevel: const drift.Value(1),
          intervalDays: const drift.Value(1),
          nextReviewDate: DateTime.now().add(const Duration(days: 1)),
        ),
      );

      // Refresh schedule
      await ref
          .read(spacedRepetitionNotifierProvider.notifier)
          .refreshFlashcardSchedule();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '✓ প্রশ্নটি ফ্ল্যাশকার্ড ডেকে যুক্ত হয়েছে! কাল প্রথম রিভিশন আসবে।',
          ),
          backgroundColor: Color(0xFF10B981),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('সংরক্ষণ ব্যর্থ হয়েছে: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111827) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header Row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.style_rounded,
                    color: Color(0xFF6366F1),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ফ্ল্যাশকার্ডে রূপান্তর',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'ভুল প্রশ্নের স্পেসড রিপিটেশন মেমোরি কার্ড',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Subject & Topic Badge
            Wrap(
              spacing: 8,
              children: [
                Chip(
                  label: Text(
                    widget.question.subject,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  backgroundColor: isDark
                      ? Colors.indigo.withValues(alpha: 0.25)
                      : Colors.indigo.shade50,
                  side: BorderSide.none,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
                Chip(
                  label: Text(
                    widget.question.topic,
                    style: const TextStyle(fontSize: 11),
                  ),
                  backgroundColor: isDark
                      ? Colors.white10
                      : Colors.grey.shade100,
                  side: BorderSide.none,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Front (প্রশ্ন) Field
            Text(
              'কার্ডের সম্মুখভাগ (প্রশ্ন / Front):',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _titleController,
              maxLines: 3,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: isDark ? Colors.white12 : Colors.grey.shade300,
                  ),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 14),

            // Back (উত্তর ও ব্যাখ্যা) Field
            Text(
              'কার্ডের পেছনভাগ (উত্তর ও নিয়ম / Back):',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _ruleController,
              maxLines: 4,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: isDark ? Colors.white12 : Colors.grey.shade300,
                  ),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 14),

            // Info note
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981)
                    .withValues(alpha: isDark ? 0.15 : 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFF10B981).withValues(alpha: 0.3),
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Color(0xFF10B981)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'জিরো টোকেন খরচ: এটি লোকাল মেমোরি কার্ডে সংরক্ষিত হবে এবং কাল ১ম রিভিশন আসবে।',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF10B981),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    child: const Text('বাতিল'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _isSaving ? null : _handleSave,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.bookmark_add_rounded, size: 18),
                    label: Text(
                      _isSaving ? 'সংরক্ষণ হচ্ছে...' : 'ফ্ল্যাশকার্ডে সেভ',
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
