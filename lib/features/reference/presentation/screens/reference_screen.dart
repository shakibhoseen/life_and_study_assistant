import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/services/reference/reference_service.dart';
import '../../../../core/theme/fluent_tokens.dart';
import '../../../../core/utils/bengali_math_sanitizer.dart';
import '../providers/reference_provider.dart';
import '../widgets/reference_import_sheet.dart';
import 'reference_sheet_screen.dart';

String _bn(int value) => BengaliMathSanitizer.toBengaliDigits('$value');

/// The reference library: tables that only make sense whole.
///
/// Search sits at the top and searches rows, not titles, because the question
/// someone actually arrives with is "১ মাইল কত" — not "which table is that
/// in". The categories below are for browsing when there is no question yet.
class ReferenceScreen extends ConsumerStatefulWidget {
  const ReferenceScreen({super.key});

  @override
  ConsumerState<ReferenceScreen> createState() => _ReferenceScreenState();
}

class _ReferenceScreenState extends ConsumerState<ReferenceScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('সূত্র ও পরিমাপ')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => ReferenceImportSheet.show(context),
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('বই থেকে নিন'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FluentSpacing.l,
              FluentSpacing.m,
              FluentSpacing.l,
              FluentSpacing.s,
            ),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'খুঁজুন — যেমন মাইল, বিঘা, বৃত্ত',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: _query.trim().isEmpty
                ? const _Categories()
                : _Results(query: _query),
          ),
          // Keeps the last card clear of the floating button.
          const SizedBox(height: FluentSpacing.xxl * 2),
        ],
      ),
    );
  }
}

class _Categories extends ConsumerWidget {
  const _Categories();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grouped = ref.watch(referenceCategoriesProvider);

    return grouped.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _Message('টেবিল খোলা গেল না।\n$e'),
      data: (categories) {
        if (categories.isEmpty) {
          return const _Message('কোনো টেবিল নেই।');
        }
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: FluentSpacing.l),
          children: categories.entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: FluentSpacing.l),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.key, style: FluentType.bodyStrong),
                  const SizedBox(height: FluentSpacing.s),
                  ...entry.value.map((sheet) => _SheetTile(sheet: sheet)),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _SheetTile extends ConsumerWidget {
  final ReferenceSheet sheet;

  const _SheetTile({required this.sheet});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final view = ref.watch(referenceSheetProvider(sheet.sheetKey));
    final count = view.value?.rows.length;

    return Card(
      margin: const EdgeInsets.only(bottom: FluentSpacing.s),
      child: ListTile(
        title: Text(sheet.title, style: FluentType.body),
        subtitle: count == null
            ? null
            : Text(
                '${_bn(count)}টি সারি',
                style: FluentType.caption.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
        trailing: Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ReferenceSheetScreen(sheetKey: sheet.sheetKey),
          ),
        ),
      ),
    );
  }
}

class _Results extends ConsumerWidget {
  final String query;

  const _Results({required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final hits = ref.watch(referenceSearchProvider(query));

    return hits.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _Message('খোঁজা গেল না।\n$e'),
      data: (results) {
        if (results.isEmpty) {
          return const _Message('কিছু পাওয়া যায়নি।');
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: FluentSpacing.l),
          itemCount: results.length,
          itemBuilder: (context, i) {
            final hit = results[i];
            final cells = decodeStringList(hit.row.cellsJson);
            return Card(
              margin: const EdgeInsets.only(bottom: FluentSpacing.s),
              child: ListTile(
                title: Text(cells.join('  →  '), style: FluentType.body),
                subtitle: Text(
                  hit.sheet.title,
                  style: FluentType.caption.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                // Straight to the whole table: the line answers the question,
                // the table is why the user came to a reference at all.
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        ReferenceSheetScreen(sheetKey: hit.sheet.sheetKey),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  final String text;

  const _Message(this.text);

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(FluentSpacing.xxl),
      child: Text(text, textAlign: TextAlign.center, style: FluentType.body),
    ),
  );
}
