import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/services/reference/reference_service.dart';
import '../../../../core/theme/fluent_tokens.dart';
import '../providers/reference_provider.dart';
import '../widgets/reference_row_sheet.dart';

/// One reference table.
///
/// Two columns are drawn as a list rather than a grid: a conversion table is
/// read one line at a time, left to right, and a phone-width grid puts half
/// the characters it can show into borders and padding. Three or more columns
/// become a real table, scrolled sideways if it must be — a tense chart has
/// no meaning once its rows are split up.
class ReferenceSheetScreen extends ConsumerWidget {
  final String sheetKey;

  const ReferenceSheetScreen({super.key, required this.sheetKey});

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    ReferenceSheet sheet,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('টেবিলটি মুছবেন?'),
        content: Text('"${sheet.title}" ও এর সব সারি মুছে যাবে।'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('না'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('মুছুন'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await ref.read(referenceNotifierProvider.notifier).deleteSheet(sheetKey);
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(referenceSheetProvider(sheetKey));

    return Scaffold(
      appBar: AppBar(
        title: Text(async.value?.sheet.title ?? 'টেবিল'),
        actions: [
          if (async.value?.sheet.isCustom == true)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'টেবিল মুছুন',
              onPressed: () =>
                  _confirmDelete(context, ref, async.value!.sheet),
            ),
        ],
      ),
      floatingActionButton: async.value == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => ReferenceRowSheet.show(
                context,
                sheetKey: sheetKey,
                columns: async.value!.columns,
              ),
              icon: const Icon(Icons.add),
              label: const Text('সারি যোগ'),
            ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('টেবিল খোলা গেল না।\n$e')),
        data: (view) {
          if (view == null) {
            return const Center(child: Text('টেবিলটি আর নেই।'));
          }
          final columns = view.columns;
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              FluentSpacing.l,
              FluentSpacing.m,
              FluentSpacing.l,
              FluentSpacing.xxl * 3,
            ),
            children: [
              if (view.sheet.note.isNotEmpty) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: FluentSpacing.xs),
                    Expanded(
                      child: Text(
                        view.sheet.note,
                        style: FluentType.caption.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: FluentSpacing.l),
              ],
              if (columns.length <= 2)
                ..._pairRows(context, ref, view)
              else
                _WideTable(view: view),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _pairRows(
    BuildContext context,
    WidgetRef ref,
    ReferenceSheetView view,
  ) {
    return view.rows.map((row) {
      return _PairRow(sheet: view.sheet, row: row, columns: view.columns);
    }).toList();
  }
}

class _PairRow extends ConsumerWidget {
  final ReferenceSheet sheet;
  final ReferenceRow row;
  final List<String> columns;

  const _PairRow({
    required this.sheet,
    required this.row,
    required this.columns,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final cells = decodeStringList(row.cellsJson);
    final left = cells.isEmpty ? '' : cells.first;
    final right = cells.length > 1 ? cells[1] : '';

    return InkWell(
      onLongPress: () => _showActions(context, ref),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: FluentSpacing.s),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(left, style: FluentType.bodyStrong),
            if (right.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: FluentSpacing.xxs),
                child: Text(
                  right,
                  style: FluentType.body.copyWith(color: scheme.primary),
                ),
              ),
            if (row.note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: FluentSpacing.xxs),
                child: Text(
                  row.note,
                  style: FluentType.caption.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: FluentSpacing.s),
            Divider(height: 1, color: scheme.outlineVariant),
          ],
        ),
      ),
    );
  }

  void _showActions(BuildContext context, WidgetRef ref) =>
      showRowActions(context, ref, sheet: sheet, row: row, columns: columns);
}

/// What can be done with one line of a table.
///
/// Shared by both layouts. It used to live inside the two-column one, which
/// meant a table of three columns or more — a tense chart, the SI units —
/// had no way to edit, remove or revise a row at all. The long press is the
/// only affordance either layout has, so leaving it out of one left those
/// rows permanently stuck.
void showRowActions(
  BuildContext context,
  WidgetRef ref, {
  required ReferenceSheet sheet,
  required ReferenceRow row,
  required List<String> columns,
}) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.bolt_outlined),
              title: const Text('রিভিশনে পাঠান'),
              subtitle: const Text('Spaced Repetition-এ যোগ হবে'),
              onTap: () async {
                Navigator.of(ctx).pop();
                await ref
                    .read(referenceNotifierProvider.notifier)
                    .sendRowToReview(sheet: sheet, row: row);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('রিভিশনে যোগ হয়েছে।')),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('সম্পাদনা'),
              onTap: () {
                Navigator.of(ctx).pop();
                ReferenceRowSheet.show(
                  context,
                  sheetKey: sheet.sheetKey,
                  columns: columns,
                  row: row,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('সারিটি মুছুন'),
              onTap: () async {
                Navigator.of(ctx).pop();
                await ref
                    .read(referenceNotifierProvider.notifier)
                    .deleteRow(row.id);
              },
            ),
          ],
        ),
      ),
    );
}

class _WideTable extends ConsumerWidget {
  final ReferenceSheetView view;

  const _WideTable({required this.view});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 40,
        columnSpacing: FluentSpacing.xl,
        columns: view.columns
            .map(
              (c) => DataColumn(
                label: Text(
                  c,
                  style: FluentType.caption.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
            .toList(),
        rows: view.rows.map((row) {
          final cells = decodeStringList(row.cellsJson);
          return DataRow(
            // The same long press the two-column layout has. Without it a
            // row in a wide table could be added and never taken back.
            onLongPress: () => showRowActions(
              context,
              ref,
              sheet: view.sheet,
              row: row,
              columns: view.columns,
            ),
            cells: List.generate(view.columns.length, (i) {
              return DataCell(
                Text(
                  i < cells.length ? cells[i] : '',
                  style: i == 0 ? FluentType.bodyStrong : FluentType.body,
                ),
              );
            }),
          );
        }).toList(),
      ),
    );
  }
}
