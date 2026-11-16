import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/services/reference/reference_service.dart';
import '../../../../core/theme/fluent_tokens.dart';
import '../providers/reference_provider.dart';

/// Adding a line to a table, or fixing one.
///
/// A field per column, so the shape of the sheet decides the shape of the
/// form. Editing a bundled line is allowed: a printed table can be wrong, or
/// an old edition, and the correction has to be the user's to make.
class ReferenceRowSheet extends ConsumerStatefulWidget {
  final String sheetKey;
  final List<String> columns;
  final ReferenceRow? row;

  const ReferenceRowSheet({
    super.key,
    required this.sheetKey,
    required this.columns,
    this.row,
  });

  static Future<void> show(
    BuildContext context, {
    required String sheetKey,
    required List<String> columns,
    ReferenceRow? row,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ReferenceRowSheet(
          sheetKey: sheetKey,
          columns: columns,
          row: row,
        ),
      ),
    );
  }

  @override
  ConsumerState<ReferenceRowSheet> createState() => _ReferenceRowSheetState();
}

class _ReferenceRowSheetState extends ConsumerState<ReferenceRowSheet> {
  late final List<TextEditingController> _cells;
  late final TextEditingController _note;
  bool _busy = false;
  String? _error;

  bool get _isEdit => widget.row != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.row == null
        ? const <String>[]
        : decodeStringList(widget.row!.cellsJson);
    _cells = List.generate(
      widget.columns.length,
      (i) => TextEditingController(
        text: i < existing.length ? existing[i] : '',
      ),
    );
    _note = TextEditingController(text: widget.row?.note ?? '');
  }

  @override
  void dispose() {
    for (final c in _cells) {
      c.dispose();
    }
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final cells = _cells.map((c) => c.text.trim()).toList();
    if (cells.every((c) => c.isEmpty)) {
      setState(() => _error = 'অন্তত একটি ঘর পূরণ করুন।');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final notifier = ref.read(referenceNotifierProvider.notifier);
    final ok = _isEdit
        ? await notifier.editRow(
            rowId: widget.row!.id,
            cells: cells,
            note: _note.text.trim(),
          )
        : await notifier.addRow(
            sheetKey: widget.sheetKey,
            cells: cells,
            note: _note.text.trim(),
          );

    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = 'সারিটি রাখা গেল না।';
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(FluentSpacing.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isEdit ? 'সারি সম্পাদনা' : 'নতুন সারি',
              style: FluentType.subtitle,
            ),
            const SizedBox(height: FluentSpacing.m),
            ...List.generate(widget.columns.length, (i) {
              return Padding(
                padding: const EdgeInsets.only(bottom: FluentSpacing.m),
                child: TextField(
                  controller: _cells[i],
                  enabled: !_busy,
                  autofocus: i == 0 && !_isEdit,
                  decoration: InputDecoration(
                    labelText: widget.columns[i],
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              );
            }),
            TextField(
              controller: _note,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: 'নোট (ঐচ্ছিক)',
                helperText: 'মনে রাখার কৌশল, বা কোন শর্তে প্রযোজ্য',
                errorText: _error,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: FluentSpacing.xl),
            Row(
              children: [
                const Spacer(),
                TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  child: const Text('বাতিল'),
                ),
                const SizedBox(width: FluentSpacing.s),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(_isEdit ? 'সংরক্ষণ' : 'যোগ করুন'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
