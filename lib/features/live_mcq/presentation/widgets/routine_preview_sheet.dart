import 'package:flutter/material.dart';

import '../../../../core/services/ai/models/parsed_routine_item.dart';
import '../../../../core/utils/bengali_math_sanitizer.dart';
import '../../../../core/theme/fluent_tokens.dart';

/// Shows what an import is about to save, before it saves anything.
///
/// Every routine import until now wrote straight to the database, so a
/// misread PDF, an invented placeholder or a half-truncated reply all landed
/// silently and had to be discovered later. Nothing is written until the user
/// has seen the rows and said yes, and they can drop any row that is wrong.
class RoutinePreviewSheet extends StatefulWidget {
  final List<ParsedRoutineItem> items;

  /// Where these rows came from, shown so the user can judge them.
  final String sourceLabel;

  const RoutinePreviewSheet({
    super.key,
    required this.items,
    required this.sourceLabel,
  });

  /// Returns the rows the user accepted, or null if they cancelled.
  static Future<List<ParsedRoutineItem>?> show(
    BuildContext context,
    List<ParsedRoutineItem> items, {
    required String sourceLabel,
  }) {
    return showModalBottomSheet<List<ParsedRoutineItem>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          RoutinePreviewSheet(items: items, sourceLabel: sourceLabel),
    );
  }

  @override
  State<RoutinePreviewSheet> createState() => _RoutinePreviewSheetState();
}

class _RoutinePreviewSheetState extends State<RoutinePreviewSheet> {
  late final List<ParsedRoutineItem> _kept = [...widget.items];

  bool get _isStudyPlan =>
      widget.sourceLabel.toLowerCase().contains('mentor') ||
      widget.sourceLabel.toLowerCase().contains('study') ||
      widget.items.any(
        (it) =>
            it.examType.toLowerCase().contains('study') ||
            it.examType.toLowerCase().contains('session'),
      );

  static const List<String> _bnMonths = [
    '',
    'জানু',
    'ফেব্রু',
    'মার্চ',
    'এপ্রিল',
    'মে',
    'জুন',
    'জুলাই',
    'আগস্ট',
    'সেপ্টে',
    'অক্টো',
    'নভে',
    'ডিসে',
  ];

  /// The rest of the app counts in Bengali digits; a preview that counts in
  /// ASCII would read as a different app.
  static String _bn(Object n) => BengaliMathSanitizer.toBengaliDigits('$n');

  String _dateLabel(DateTime d) =>
      '${_bn(d.day)} ${_bnMonths[d.month]} ${_bn(d.year)}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    final dates = _kept.map((e) => e.date).toList()..sort();
    final tracks = _kept.map((e) => e.trackName).toSet();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(
              top: FluentSpacing.m,
              bottom: FluentSpacing.s,
            ),
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.onSurface.withValues(alpha: 0.2),
              borderRadius: FluentRadius.controlBorder,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FluentSpacing.l,
              FluentSpacing.xs,
              FluentSpacing.l,
              FluentSpacing.m,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.fact_check_outlined,
                      size: 19,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: FluentSpacing.s),
                    Expanded(
                      child: Text(
                        'যোগ করার আগে দেখে নিন',
                        style: FluentType.bodyStrong.copyWith(
                          fontSize: 15,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: FluentSpacing.s),
                Text(
                  _kept.isEmpty
                      ? (_isStudyPlan
                            ? 'কোনো স্টাডি সেশন রাখা হয়নি।'
                            : 'কোনো পরীক্ষা রাখা হয়নি।')
                      : '${_bn(_kept.length)}টি ${_isStudyPlan ? "স্টাডি সেশন" : "পরীক্ষা"} · '
                            '${_dateLabel(dates.first)} – ${_dateLabel(dates.last)}'
                            '${tracks.length == 1 ? " · ${tracks.first}" : " · ${_bn(tracks.length)}টি ট্র্যাক"}',
                  style: FluentType.caption.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
                const SizedBox(height: FluentSpacing.xs),
                Text(
                  'উৎস: ${widget.sourceLabel}',
                  style: FluentType.caption.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: _kept.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(FluentSpacing.xxl),
                    child: Text(
                      'সব সারি বাদ দেওয়া হয়েছে। বাতিল করে আবার চেষ্টা করুন।',
                      textAlign: TextAlign.center,
                      style: FluentType.body.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FluentSpacing.l,
                      vertical: FluentSpacing.m,
                    ),
                    itemCount: _kept.length,
                    separatorBuilder: (_, _) => const SizedBox(height: FluentSpacing.s),
                    itemBuilder: (context, i) => _buildRow(_kept[i], i),
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FluentSpacing.l,
              FluentSpacing.m,
              FluentSpacing.l,
              FluentSpacing.xl,
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: FluentSpacing.m),
                    ),
                    child: const Text('বাতিল'),
                  ),
                ),
                const SizedBox(width: FluentSpacing.m),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _kept.isEmpty
                        ? null
                        : () => Navigator.pop(context, _kept),
                    icon: const Icon(Icons.check, size: 18),
                    label: Text(
                      '${_bn(_kept.length)}টি ${_isStudyPlan ? "সেশন যোগ করুন" : "যোগ করুন"}',
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: FluentSpacing.m),
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

  Widget _buildRow(ParsedRoutineItem item, int index) {
    final title = (item.title == null || item.title!.trim().isEmpty)
        ? '${item.subject} ${item.examType}'
        : item.title!;

    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        FluentSpacing.m,
        FluentSpacing.s,
        FluentSpacing.xs,
        FluentSpacing.s,
      ),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: FluentRadius.cardBorder,
        border: Border.all(
          color: FluentStroke.card(brightness),
          width: FluentStroke.width,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _dateLabel(item.date),
                        style: FluentType.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.primary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: FluentSpacing.s),
                    Flexible(
                      child: Text(
                        // Left as written: "১০:০০ PM" is half one script and
                        // half the other, which reads worse than either.
                        item.examTime,
                        style: FluentType.caption.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.45),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: FluentSpacing.xs),
                Text(
                  title,
                  style: FluentType.bodyStrong.copyWith(
                    fontSize: 13,
                    color: scheme.onSurface,
                  ),
                ),
                if (item.topics.isNotEmpty) ...[
                  const SizedBox(height: FluentSpacing.xxs),
                  Text(
                    item.topics.join(', '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: FluentType.caption.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'এই সারিটি বাদ দিন',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.close,
              size: 17,
              color: scheme.onSurface.withValues(alpha: 0.45),
            ),
            onPressed: () => setState(() => _kept.removeAt(index)),
          ),
        ],
      ),
    );
  }
}
