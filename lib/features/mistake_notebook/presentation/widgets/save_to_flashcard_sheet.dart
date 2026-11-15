import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../core/theme/fluent_tokens.dart';
import '../../../spaced_repetition/presentation/providers/spaced_repetition_provider.dart';

/// The "correct / success" status colour for this feature. Readable on both
/// the light and the dark card surface.
const Color _successColor = Color(0xFF10B981);

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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    final isDark = brightness == Brightness.dark;
    final onSurface = scheme.onSurface;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
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
      ),
      padding: EdgeInsets.fromLTRB(
        FluentSpacing.xl,
        FluentSpacing.m,
        FluentSpacing.xl,
        FluentSpacing.xl + bottomInset,
      ),
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
                margin: const EdgeInsets.only(bottom: FluentSpacing.l),
                decoration: BoxDecoration(
                  color: onSurface.withValues(alpha: 0.24),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header Row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(FluentSpacing.s),
                  decoration: BoxDecoration(
                    color: FluentLayer.subtle(scheme.primary, brightness),
                    borderRadius: FluentRadius.controlBorder,
                  ),
                  child: Icon(
                    Icons.style_rounded,
                    color: scheme.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: FluentSpacing.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ফ্ল্যাশকার্ডে রূপান্তর',
                        style: FluentType.bodyStrong.copyWith(
                          fontSize: 16,
                          color: onSurface,
                        ),
                      ),
                      Text(
                        'ভুল প্রশ্নের স্পেসড রিপিটেশন মেমোরি কার্ড',
                        style: FluentType.caption.copyWith(
                          color: onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: FluentSpacing.l),

            // Subject & Topic Badge
            Wrap(
              spacing: FluentSpacing.s,
              children: [
                Chip(
                  label: Text(
                    widget.question.subject,
                    style: FluentType.caption.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  backgroundColor: FluentLayer.subtle(
                    scheme.primary,
                    brightness,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: FluentRadius.controlBorder,
                  ),
                  side: BorderSide.none,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
                Chip(
                  label: Text(
                    widget.question.topic,
                    style: FluentType.caption.copyWith(
                      color: onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                  backgroundColor: onSurface.withValues(alpha: 0.06),
                  shape: RoundedRectangleBorder(
                    borderRadius: FluentRadius.controlBorder,
                  ),
                  side: BorderSide.none,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: FluentSpacing.m),

            // Front (প্রশ্ন) Field
            Text(
              'কার্ডের সম্মুখভাগ (প্রশ্ন / Front):',
              style: FluentType.caption.copyWith(
                fontWeight: FontWeight.w600,
                color: onSurface.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: FluentSpacing.xs),
            TextField(
              controller: _titleController,
              maxLines: 3,
              style: FluentType.body.copyWith(color: onSurface),
              decoration: InputDecoration(
                filled: true,
                fillColor: onSurface.withValues(alpha: isDark ? 0.06 : 0.03),
                border: OutlineInputBorder(
                  borderRadius: FluentRadius.controlBorder,
                  borderSide: FluentStroke.side(brightness),
                ),
                contentPadding: const EdgeInsets.all(FluentSpacing.m),
              ),
            ),
            const SizedBox(height: FluentSpacing.l),

            // Back (উত্তর ও ব্যাখ্যা) Field
            Text(
              'কার্ডের পেছনভাগ (উত্তর ও নিয়ম / Back):',
              style: FluentType.caption.copyWith(
                fontWeight: FontWeight.w600,
                color: onSurface.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: FluentSpacing.xs),
            TextField(
              controller: _ruleController,
              maxLines: 4,
              style: FluentType.body.copyWith(color: onSurface),
              decoration: InputDecoration(
                filled: true,
                fillColor: onSurface.withValues(alpha: isDark ? 0.06 : 0.03),
                border: OutlineInputBorder(
                  borderRadius: FluentRadius.controlBorder,
                  borderSide: FluentStroke.side(brightness),
                ),
                contentPadding: const EdgeInsets.all(FluentSpacing.m),
              ),
            ),
            const SizedBox(height: FluentSpacing.l),

            // Info note
            Container(
              padding: const EdgeInsets.all(FluentSpacing.m),
              decoration: BoxDecoration(
                color: FluentLayer.subtle(_successColor, brightness),
                borderRadius: FluentRadius.cardBorder,
                border: Border.all(
                  color: _successColor.withValues(alpha: 0.3),
                  width: FluentStroke.width,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 16,
                    color: _successColor,
                  ),
                  const SizedBox(width: FluentSpacing.s),
                  Expanded(
                    child: Text(
                      'জিরো টোকেন খরচ: এটি লোকাল মেমোরি কার্ডে সংরক্ষিত হবে এবং কাল ১ম রিভিশন আসবে।',
                      style: FluentType.caption.copyWith(
                        color: _successColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: FluentSpacing.xl),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: FluentSpacing.m,
                      ),
                      side: FluentStroke.side(brightness),
                      shape: RoundedRectangleBorder(
                        borderRadius: FluentRadius.controlBorder,
                      ),
                    ),
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    child: const Text('বাতিল'),
                  ),
                ),
                const SizedBox(width: FluentSpacing.m),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: FluentRadius.controlBorder,
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: FluentSpacing.m,
                      ),
                    ),
                    onPressed: _isSaving ? null : _handleSave,
                    icon: _isSaving
                        ? SizedBox(
                            width: FluentSpacing.l,
                            height: FluentSpacing.l,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: scheme.onPrimary,
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
