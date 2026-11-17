import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/services/reference/reference_service.dart';
import '../../../../core/theme/fluent_tokens.dart';
import '../providers/reference_provider.dart';
import 'detail_body.dart';

/// Where a rule comes from, at length.
///
/// A conversion table needs no proof — ১ মাইল is ১.৬১ কিলোমিটার because that
/// is what it is. হেরনের সূত্র is different: four symbols to memorise and a
/// page to understand, and the page is what makes it stay. So this is empty
/// on almost every row by design, and worth having on the handful where
/// understanding beats memorising.
///
/// The app does not write these itself. A derivation is exactly what a cheap
/// model gets confidently wrong, and a wrong proof is worse than none — it
/// teaches a method that fails in the exam. The prompt goes out, the answer
/// comes back, and nothing in between touches it.
class RowDetailSheet extends ConsumerStatefulWidget {
  final ReferenceSheetView view;
  final ReferenceRow row;

  const RowDetailSheet({super.key, required this.view, required this.row});

  static Future<void> show(
    BuildContext context, {
    required ReferenceSheetView view,
    required ReferenceRow row,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: RowDetailSheet(view: view, row: row),
      ),
    );
  }

  @override
  ConsumerState<RowDetailSheet> createState() => _RowDetailSheetState();
}

class _RowDetailSheetState extends ConsumerState<RowDetailSheet> {
  late final TextEditingController _detail;
  late bool _editing;
  bool _busy = false;

  List<String> get _cells => decodeStringList(widget.row.cellsJson);

  String get _heading => _cells.where((c) => c.trim().isNotEmpty).join('  →  ');

  @override
  void initState() {
    super.initState();
    _detail = TextEditingController(text: widget.row.detail ?? '');
    // Straight into the editor when there is nothing to read yet, so the
    // first visit is not a dead end with an empty box.
    _editing = (widget.row.detail ?? '').trim().isEmpty;
  }

  @override
  void dispose() {
    _detail.dispose();
    super.dispose();
  }

  String get _prompt => derivationPrompt(
    sheetTitle: widget.view.sheet.title,
    columns: widget.view.columns,
    cells: _cells,
    note: widget.row.note,
  );

  Future<void> _save() async {
    setState(() => _busy = true);
    await ref
        .read(referenceNotifierProvider.notifier)
        .setRowDetail(rowId: widget.row.id, detail: _detail.text);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        // The buttons sit outside the scroll view, pinned at the bottom.
        // Inside it they ended up below the fold on a long derivation, so
        // saving meant scrolling past the whole thing first.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(FluentSpacing.l),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_heading, style: FluentType.bodyStrong),
                    Text(
                      widget.view.sheet.title,
                      style: FluentType.caption.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: FluentSpacing.l),

                    if (_editing) ...[
                      Container(
                        padding: const EdgeInsets.all(FluentSpacing.m),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(
                            alpha: 0.4,
                          ),
                          borderRadius: BorderRadius.circular(
                            FluentRadius.card,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'বাইরের AI দিয়ে লেখান',
                              style: FluentType.bodyStrong,
                            ),
                            const SizedBox(height: FluentSpacing.xxs),
                            Text(
                              'প্রম্পটটি কপি করে ChatGPT বা Claude-এ দিন, উত্তরটা '
                              'নিচে পেস্ট করুন। অ্যাপের নিজের AI দিয়ে প্রমাণ লেখাই '
                              'না — ভুল প্রমাণ না থাকার চেয়ে খারাপ।',
                              style: FluentType.caption.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: FluentSpacing.s),
                            OutlinedButton.icon(
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: _prompt));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('প্রম্পট কপি হয়েছে।'),
                                  ),
                                );
                              },
                              icon: const Icon(
                                Icons.copy_all_outlined,
                                size: 18,
                              ),
                              label: const Text('প্রম্পট কপি করুন'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: FluentSpacing.l),
                      TextField(
                        controller: _detail,
                        enabled: !_busy,
                        maxLines: 14,
                        minLines: 8,
                        decoration: const InputDecoration(
                          labelText: 'বিস্তারিত',
                          helperText: 'Markdown চলবে',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ] else
                      DetailBody(detail: widget.row.detail ?? ''),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                FluentSpacing.l,
                0,
                FluentSpacing.l,
                FluentSpacing.l,
              ),
              child: Row(
                children: [
                  if (!_editing)
                    TextButton.icon(
                      onPressed: () => setState(() => _editing = true),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('সম্পাদনা'),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: Text(_editing ? 'বাতিল' : 'বন্ধ'),
                  ),
                  if (_editing) ...[
                    const SizedBox(width: FluentSpacing.s),
                    FilledButton(
                      onPressed: _busy ? null : _save,
                      child: const Text('সংরক্ষণ'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
