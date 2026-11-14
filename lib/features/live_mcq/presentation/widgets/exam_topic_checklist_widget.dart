import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/database/app_database.dart';
import '../../../focus/presentation/screens/pomodoro_focus_screen.dart';
import '../../../../core/theme/fluent_tokens.dart';

/// An interactive checklist widget that parses an exam's `topicsCovered` text
/// into discrete, checkable study targets with progress tracking.
class ExamTopicChecklistWidget extends StatefulWidget {
  final ExamSchedule exam;

  const ExamTopicChecklistWidget({
    super.key,
    required this.exam,
  });

  @override
  State<ExamTopicChecklistWidget> createState() =>
      _ExamTopicChecklistWidgetState();
}

class _ExamTopicChecklistWidgetState extends State<ExamTopicChecklistWidget> {
  bool _isExpanded = false;
  bool _showRawView = false;
  List<String> _topics = [];
  final Set<String> _checkedTopics = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _parseTopics();
    _loadCheckedStatus();
  }

  @override
  void didUpdateWidget(covariant ExamTopicChecklistWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.exam.topicsCovered != widget.exam.topicsCovered ||
        oldWidget.exam.id != widget.exam.id) {
      _parseTopics();
      _loadCheckedStatus();
    }
  }

  void _parseTopics() {
    final raw = widget.exam.topicsCovered;
    // Split by newlines, bullet symbols, semicolons, and commas
    final parts = raw
        .split(RegExp(r'[\n•;]+|,\s*(?=[A-Z\u0980-\u09FF])'))
        .map((s) => s.trim())
        .where((s) {
      if (s.isEmpty) return false;
      // Filter out pure section prefixes like "Math:" or "Topic:"
      final lower = s.toLowerCase();
      if (lower == 'math:' || lower == 'topic:' || lower == 'syllabus:') {
        return false;
      }
      return true;
    }).toList();

    _topics = parts.isNotEmpty ? parts : [raw.trim()];
  }

  String _prefKey(String topic) =>
      'exam_${widget.exam.id}_topic_${topic.hashCode}';

  Future<void> _loadCheckedStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final checked = <String>{};
    for (final t in _topics) {
      if (prefs.getBool(_prefKey(t)) == true) {
        checked.add(t);
      }
    }
    if (mounted) {
      setState(() {
        _checkedTopics.clear();
        _checkedTopics.addAll(checked);
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleTopic(String topic) async {
    final prefs = await SharedPreferences.getInstance();
    final isChecked = _checkedTopics.contains(topic);
    setState(() {
      if (isChecked) {
        _checkedTopics.remove(topic);
      } else {
        _checkedTopics.add(topic);
      }
    });
    await prefs.setBool(_prefKey(topic), !isChecked);
  }

  @override
  Widget build(BuildContext context) {
    if (_topics.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final total = _topics.length;
    final completed = _checkedTopics.length;
    final progress = total > 0 ? completed / total : 0.0;
    final isAllDone = completed == total && total > 0;

    return Container(
      margin: const EdgeInsets.only(
        top: FluentSpacing.s,
        bottom: FluentSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: isAllDone
            ? FluentLayer.subtle(const Color(0xFF10B981), brightness)
            : scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: FluentRadius.cardBorder,
        border: Border.all(
          color: isAllDone
              ? const Color(0xFF10B981).withValues(alpha: 0.35)
              : FluentStroke.card(brightness),
          width: FluentStroke.width,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header / Summary row (Tap to expand/collapse, with eye button for full text)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: FluentSpacing.s,
              vertical: FluentSpacing.s,
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _isExpanded = !_isExpanded;
                      });
                    },
                    borderRadius: FluentRadius.controlBorder,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: FluentSpacing.xs,
                        vertical: FluentSpacing.xs,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isAllDone
                                ? Icons.check_circle
                                : Icons.checklist_rounded,
                            size: 16,
                            color: isAllDone
                                ? const Color(0xFF10B981)
                                : scheme.primary,
                          ),
                          const SizedBox(width: FluentSpacing.s),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        isAllDone
                                            ? 'সিলেবাস পড়া শেষ! ✓'
                                            : 'টপিক প্রস্তুতি ($completed/$total)',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: FluentType.caption.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: isAllDone
                                              ? const Color(0xFF10B981)
                                              : scheme.onSurface,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: FluentSpacing.s),
                                    Text(
                                      '${(progress * 100).toInt()}%',
                                      style: FluentType.caption.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: isAllDone
                                            ? const Color(0xFF10B981)
                                            : scheme.onSurface
                                                  .withValues(alpha: 0.65),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: FluentSpacing.xs),
                                ClipRRect(
                                  borderRadius: FluentRadius.controlBorder,
                                  child: LinearProgressIndicator(
                                    value: progress,
                                    minHeight: 4,
                                    backgroundColor: scheme.onSurface
                                        .withValues(alpha: 0.10),
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      isAllDone
                                          ? const Color(0xFF10B981)
                                          : const Color(0xFF3B82F6),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: FluentSpacing.xs),

                // Eye button: Toggle between full raw text and checklist
                IconButton(
                  icon: Icon(
                    _showRawView && _isExpanded
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 19,
                    color: _showRawView && _isExpanded
                        ? scheme.primary
                        : scheme.onSurface.withValues(alpha: 0.55),
                  ),
                  tooltip: _showRawView && _isExpanded
                      ? 'চেকলিস্টে ফিরে যান'
                      : 'আগের মতো সম্পূর্ণ টপিক টেক্সট দেখুন',
                  padding: const EdgeInsets.all(FluentSpacing.xs),
                  constraints: const BoxConstraints(
                    minWidth: 30,
                    minHeight: 30,
                  ),
                  onPressed: () {
                    setState(() {
                      if (!_isExpanded) {
                        _isExpanded = true;
                        _showRawView = true;
                      } else {
                        _showRawView = !_showRawView;
                      }
                    });
                  },
                ),

                // Expand / Collapse chevron
                InkWell(
                  onTap: () {
                    setState(() {
                      _isExpanded = !_isExpanded;
                    });
                  },
                  borderRadius: FluentRadius.controlBorder,
                  child: Padding(
                    padding: const EdgeInsets.all(FluentSpacing.xs),
                    child: Icon(
                      _isExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 20,
                      color: scheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Expanded Content: Either Raw Text or Interactive Checklist
          if (_isExpanded && !_isLoading) ...[
            Divider(height: 1, color: FluentStroke.divider(brightness)),
            if (_showRawView) ...[
              // Mode 1: Full original topics text (একবারে আগের মতো সম্পূর্ণ সিলেবাস)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  FluentSpacing.m,
                  FluentSpacing.s,
                  FluentSpacing.m,
                  FluentSpacing.m,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.article_outlined,
                          size: 15,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: FluentSpacing.s),
                        Expanded(
                          child: Text(
                            'সম্পূর্ণ টপিক বিবরণ (Original Topics):',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: FluentType.caption.copyWith(
                              fontWeight: FontWeight.w600,
                              color: scheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: FluentSpacing.s),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 14),
                          tooltip: 'টপিক কপি করুন',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          color: scheme.onSurface.withValues(alpha: 0.65),
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(text: widget.exam.topicsCovered),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('টপিক টেক্সট কপি হয়েছে ✓'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: FluentSpacing.s),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: FluentSpacing.s,
                              vertical: FluentSpacing.xxs,
                            ),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          icon: const Icon(Icons.checklist_rounded, size: 14),
                          label: Text(
                            'চেকলিস্ট মোড',
                            style: FluentType.caption,
                          ),
                          onPressed: () {
                            setState(() => _showRawView = false);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: FluentSpacing.s),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(FluentSpacing.m),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: FluentRadius.cardBorder,
                        border: Border.all(
                          color: FluentStroke.card(brightness),
                          width: FluentStroke.width,
                        ),
                      ),
                      child: SelectableText(
                        'Topics: ${widget.exam.topicsCovered}',
                        style: FluentType.body.copyWith(
                          fontSize: 13,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Mode 2: Interactive Checklist
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: FluentSpacing.s,
                  vertical: FluentSpacing.xs,
                ),
                child: Column(
                  children: [
                    ..._topics.map((t) {
                      final isChecked = _checkedTopics.contains(t);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: FluentSpacing.xxs),
                        child: InkWell(
                          onTap: () => _toggleTopic(t),
                          borderRadius: FluentRadius.controlBorder,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: FluentSpacing.s,
                              vertical: FluentSpacing.xs,
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: Checkbox(
                                    value: isChecked,
                                    activeColor: const Color(0xFF10B981),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: FluentRadius.controlBorder,
                                    ),
                                    onChanged: (_) => _toggleTopic(t),
                                  ),
                                ),
                                const SizedBox(width: FluentSpacing.s),
                                Expanded(
                                  child: Text(
                                    t,
                                    style: FluentType.caption.copyWith(
                                      decoration: isChecked
                                          ? TextDecoration.lineThrough
                                          : null,
                                      color: isChecked
                                          ? scheme.onSurface
                                                .withValues(alpha: 0.45)
                                          : scheme.onSurface,
                                    ),
                                  ),
                                ),
                                // Quick study timer button for this topic
                                IconButton(
                                  icon: const Icon(
                                    Icons.timer_outlined,
                                    size: 15,
                                  ),
                                  tooltip: 'এই টপিকে ফোকাস টাইমার শুরু করুন',
                                  color: scheme.primary,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const PomodoroFocusScreen(),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: FluentSpacing.xxs),
                    Padding(
                      padding: const EdgeInsets.only(
                        right: FluentSpacing.xs,
                        bottom: FluentSpacing.xxs,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Flexible(
                            child: TextButton.icon(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: FluentSpacing.s,
                                  vertical: FluentSpacing.xxs,
                                ),
                              ),
                              icon: const Icon(
                                Icons.visibility_outlined,
                                size: 13,
                              ),
                              label: Text(
                                'একনজরে আগের মতো সম্পূর্ণ টেক্সট দেখুন',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.end,
                                style: FluentType.caption,
                              ),
                              onPressed: () {
                                setState(() => _showRawView = true);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
