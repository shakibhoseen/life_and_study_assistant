import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/database/app_database.dart';
import '../../../focus/presentation/screens/pomodoro_focus_screen.dart';

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

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final total = _topics.length;
    final completed = _checkedTopics.length;
    final progress = total > 0 ? completed / total : 0.0;
    final isAllDone = completed == total && total > 0;

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      decoration: BoxDecoration(
        color: isDark
            ? (isAllDone
                ? const Color(0xFF064E3B).withValues(alpha: 0.25)
                : const Color(0xFF1E293B).withValues(alpha: 0.6))
            : (isAllDone
                ? const Color(0xFFECFDF5)
                : const Color(0xFFF8FAFC)),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isAllDone
              ? (isDark ? const Color(0xFF059669) : const Color(0xFF6EE7B7))
              : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header / Summary row (Tap to expand/collapse, with eye button for full text)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _isExpanded = !_isExpanded;
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
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
                                : (isDark
                                    ? const Color(0xFF93C5FD)
                                    : const Color(0xFF3B82F6)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      isAllDone
                                          ? 'সিলেবাস পড়া শেষ! ✓'
                                          : 'টপিক প্রস্তুতি ($completed/$total)',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: isAllDone
                                            ? const Color(0xFF10B981)
                                            : (isDark
                                                ? Colors.white
                                                : const Color(0xFF1E293B)),
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      '${(progress * 100).toInt()}%',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: isAllDone
                                            ? const Color(0xFF10B981)
                                            : (isDark
                                                ? Colors.white60
                                                : Colors.black54),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: LinearProgressIndicator(
                                    value: progress,
                                    minHeight: 3.5,
                                    backgroundColor: isDark
                                        ? Colors.grey.shade800
                                        : Colors.grey.shade200,
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
                const SizedBox(width: 4),

                // Eye button: Toggle between full raw text and checklist
                IconButton(
                  icon: Icon(
                    _showRawView && _isExpanded
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 19,
                    color: _showRawView && _isExpanded
                        ? (isDark
                            ? const Color(0xFF60A5FA)
                            : const Color(0xFF2563EB))
                        : (isDark ? Colors.white60 : Colors.black45),
                  ),
                  tooltip: _showRawView && _isExpanded
                      ? 'চেকলিস্টে ফিরে যান'
                      : 'আগের মতো সম্পূর্ণ টপিক টেক্সট দেখুন',
                  padding: const EdgeInsets.all(4),
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
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      _isExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 20,
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Expanded Content: Either Raw Text or Interactive Checklist
          if (_isExpanded && !_isLoading) ...[
            const Divider(height: 1),
            if (_showRawView) ...[
              // Mode 1: Full original topics text (একবারে আগের মতো সম্পূর্ণ সিলেবাস)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.article_outlined,
                          size: 15,
                          color: isDark
                              ? const Color(0xFF93C5FD)
                              : const Color(0xFF2563EB),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'সম্পূর্ণ টপিক বিবরণ (Original Topics):',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? const Color(0xFF93C5FD)
                                : const Color(0xFF1E40AF),
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 14),
                          tooltip: 'টপিক কপি করুন',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          color: isDark ? Colors.white60 : Colors.black54,
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
                        const SizedBox(width: 8),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          icon: const Icon(Icons.checklist_rounded, size: 14),
                          label: const Text(
                            'চেকলিস্ট মোড',
                            style: TextStyle(fontSize: 11),
                          ),
                          onPressed: () {
                            setState(() => _showRawView = false);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF0F172A).withValues(alpha: 0.5)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF334155)
                              : const Color(0xFFCBD5E1),
                        ),
                      ),
                      child: SelectableText(
                        'Topics: ${widget.exam.topicsCovered}',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.45,
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.9)
                              : const Color(0xFF1E293B),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Mode 2: Interactive Checklist
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Column(
                  children: [
                    ..._topics.map((t) {
                      final isChecked = _checkedTopics.contains(t);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: InkWell(
                          onTap: () => _toggleTopic(t),
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
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
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    onChanged: (_) => _toggleTopic(t),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    t,
                                    style: TextStyle(
                                      fontSize: 12,
                                      decoration: isChecked
                                          ? TextDecoration.lineThrough
                                          : null,
                                      color: isChecked
                                          ? (isDark
                                              ? Colors.white38
                                              : Colors.black38)
                                          : (isDark
                                              ? Colors.white
                                              : Colors.black87),
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
                                  color: isDark
                                      ? const Color(0xFFA5B4FC)
                                      : const Color(0xFF6366F1),
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
                    const SizedBox(height: 2),
                    Padding(
                      padding: const EdgeInsets.only(right: 4, bottom: 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                            ),
                            icon: const Icon(
                              Icons.visibility_outlined,
                              size: 13,
                            ),
                            label: const Text(
                              'একনজরে আগের মতো সম্পূর্ণ টেক্সট দেখুন',
                              style: TextStyle(fontSize: 11),
                            ),
                            onPressed: () {
                              setState(() => _showRawView = true);
                            },
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
