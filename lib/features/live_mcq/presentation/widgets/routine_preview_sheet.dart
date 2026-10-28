import 'package:flutter/material.dart';

import '../../../../core/services/ai/models/parsed_routine_item.dart';
import '../../../../core/utils/bengali_math_sanitizer.dart';

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;

    final dates = _kept.map((e) => e.date).toList()..sort();
    final tracks = _kept.map((e) => e.trackName).toSet();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.fact_check_outlined,
                      size: 19,
                      color: Colors.indigo,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'যোগ করার আগে দেখে নিন',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _kept.isEmpty
                      ? (_isStudyPlan
                            ? 'কোনো স্টাডি সেশন রাখা হয়নি।'
                            : 'কোনো পরীক্ষা রাখা হয়নি।')
                      : '${_bn(_kept.length)}টি ${_isStudyPlan ? "স্টাডি সেশন" : "পরীক্ষা"} · '
                            '${_dateLabel(dates.first)} – ${_dateLabel(dates.last)}'
                            '${tracks.length == 1 ? " · ${tracks.first}" : " · ${_bn(tracks.length)}টি ট্র্যাক"}',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'উৎস: ${widget.sourceLabel}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: _kept.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      'সব সারি বাদ দেওয়া হয়েছে। বাতিল করে আবার চেষ্টা করুন।',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    itemCount: _kept.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 7),
                    itemBuilder: (context, i) => _buildRow(_kept[i], i, isDark),
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 18),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: const Text('বাতিল'),
                  ),
                ),
                const SizedBox(width: 10),
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

  Widget _buildRow(ParsedRoutineItem item, int index, bool isDark) {
    final title = (item.title == null || item.title!.trim().isEmpty)
        ? '${item.subject} ${item.examType}'
        : item.title!;

    return Container(
      padding: const EdgeInsets.fromLTRB(11, 9, 5, 9),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey.shade300,
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
                    Text(
                      _dateLabel(item.date),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      // Left as written: "১০:০০ PM" is half one script and
                      // half the other, which reads worse than either.
                      item.examTime,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white38 : Colors.black45,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                if (item.topics.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.topics.join(', '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      color: isDark ? Colors.white60 : Colors.black54,
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
              color: isDark ? Colors.white38 : Colors.black38,
            ),
            onPressed: () => setState(() => _kept.removeAt(index)),
          ),
        ],
      ),
    );
  }
}
