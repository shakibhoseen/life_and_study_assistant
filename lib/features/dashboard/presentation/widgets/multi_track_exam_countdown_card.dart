import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/services/ai/gemini_ai_service.dart';
import '../../../../core/services/calendar/calendar_sync_service.dart';
import '../../../live_mcq/presentation/screens/live_mcq_screen.dart';
import '../../../quiz/presentation/widgets/quiz_drill_modal.dart';

class MultiTrackExamCountdownCard extends ConsumerStatefulWidget {
  final List<ExamSchedule> exams;

  const MultiTrackExamCountdownCard({super.key, required this.exams});

  @override
  ConsumerState<MultiTrackExamCountdownCard> createState() =>
      _MultiTrackExamCountdownCardState();
}

class _MultiTrackExamCountdownCardState
    extends ConsumerState<MultiTrackExamCountdownCard> {
  String _selectedTrack = 'All';
  Timer? _tickerTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _startCountdownTicker();
  }

  void _startCountdownTicker() {
    _tickerTimer?.cancel();
    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _now = DateTime.now();
        });
      }
    });
  }

  @override
  void dispose() {
    _tickerTimer?.cancel();
    super.dispose();
  }

  List<String> _extractUniqueTracks() {
    final tracks = <String>{'All'};
    for (final e in widget.exams) {
      final name = e.trackName.trim();
      if (name.isNotEmpty) {
        tracks.add(name);
      }
    }
    return tracks.toList();
  }

  List<ExamSchedule> _getFilteredExams() {
    if (_selectedTrack == 'All') {
      return widget.exams;
    }
    return widget.exams
        .where((e) => e.trackName.trim() == _selectedTrack)
        .toList();
  }

  DateTime _parseExamTarget(ExamSchedule exam) {
    final d = exam.examDate;
    int hour = 22; // Default 10:00 PM
    int minute = 0;

    final time = exam.examTime.trim();
    final match = RegExp(
      r'(\d+):?(\d+)?\s*(AM|PM)?',
      caseSensitive: false,
    ).firstMatch(time);
    if (match != null) {
      int h = int.tryParse(match.group(1) ?? '') ?? 10;
      int m = int.tryParse(match.group(2) ?? '') ?? 0;
      final period = match.group(3)?.toUpperCase();
      if (period == 'PM' && h < 12) h += 12;
      if (period == 'AM' && h == 12) h = 0;
      hour = h;
      minute = m;
    }

    return DateTime(d.year, d.month, d.day, hour, minute);
  }

  Color _getTrackColor(String trackName) {
    final lower = trackName.toLowerCase();
    if (lower.contains('bcs') || lower.contains('৪৭')) {
      return const Color(0xFF10B981); // Emerald
    }
    if (lower.contains('petro') ||
        lower.contains('gas') ||
        lower.contains('titas')) {
      return const Color(0xFF6366F1); // Ocean Indigo
    }
    if (lower.contains('primary') ||
        lower.contains('প্রাথমিক') ||
        lower.contains('teacher')) {
      return const Color(0xFFF59E0B); // Golden Amber
    }
    return const Color(0xFF0EA5E9); // Sky Blue
  }

  IconData _getTrackIcon(String trackName) {
    final lower = trackName.toLowerCase();
    if (lower.contains('bcs') || lower.contains('৪৭')) {
      return Icons.school;
    }
    if (lower.contains('petro') ||
        lower.contains('gas') ||
        lower.contains('titas')) {
      return Icons.corporate_fare;
    }
    if (lower.contains('primary') ||
        lower.contains('প্রাথমিক') ||
        lower.contains('teacher')) {
      return Icons.menu_book;
    }
    return Icons.event_note;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tracks = _extractUniqueTracks();
    final filtered = _getFilteredExams();

    if (filtered.isEmpty) {
      return const SizedBox.shrink();
    }

    final heroExam = filtered.first;
    final otherUpcoming = filtered.skip(1).take(3).toList();
    final targetTime = _parseExamTarget(heroExam);
    final difference = targetTime.difference(_now);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header with Live Pulse indicator & Hub link
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 12, top: 14),
            child: Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEF4444), // Live red indicator
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Multi-Track Exam Timeline',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LiveMcqScreen()),
                    );
                  },
                  icon: const Icon(Icons.arrow_forward, size: 14),
                  label: const Text('View All', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: const Color(0xFF6366F1),
                  ),
                ),
              ],
            ),
          ),

          // 2. Track Filter Chips (Horizontally Scrollable)
          if (tracks.length > 2) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: tracks.map((track) {
                    final isSelected = _selectedTrack == track;
                    final trackColor = track == 'All'
                        ? const Color(0xFF6366F1)
                        : _getTrackColor(track);
                    return Padding(
                      padding: const EdgeInsets.only(right: 6, bottom: 8),
                      child: FilterChip(
                        selected: isSelected,
                        showCheckmark: false,
                        avatar: track != 'All'
                            ? Icon(
                                _getTrackIcon(track),
                                size: 14,
                                color: isSelected ? Colors.white : trackColor,
                              )
                            : null,
                        label: Text(
                          track == 'All'
                              ? 'All Tracks (${widget.exams.length})'
                              : track,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.w500,
                            color: isSelected
                                ? Colors.white
                                : (isDark
                                      ? Colors.grey.shade300
                                      : Colors.grey.shade800),
                          ),
                        ),
                        backgroundColor: isDark
                            ? const Color(0xFF1E293B)
                            : const Color(0xFFF1F5F9),
                        selectedColor: trackColor,
                        side: BorderSide(
                          color: isSelected ? trackColor : Colors.transparent,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 0,
                        ),
                        visualDensity: VisualDensity.compact,
                        onSelected: (selected) {
                          setState(() {
                            _selectedTrack = track;
                          });
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],

          const Divider(height: 1),

          // 3. Hero Exam Card with Live Countdown
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Track Pill + Exam Type + Date Status
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3.5,
                      ),
                      decoration: BoxDecoration(
                        color: _getTrackColor(heroExam.trackName)
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _getTrackColor(heroExam.trackName)
                              .withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _getTrackIcon(heroExam.trackName),
                            size: 13,
                            color: _getTrackColor(heroExam.trackName),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            heroExam.trackName,
                            style: TextStyle(
                              color: _getTrackColor(heroExam.trackName),
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    _buildStatusBadge(difference, targetTime),
                  ],
                ),
                const SizedBox(height: 10),

                // Exam Title
                Text(
                  heroExam.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),

                // Topics Covered
                Text(
                  heroExam.topicsCovered,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 14),

                // 4. Live Countdown Display
                _buildLiveCountdownBoxes(difference, targetTime, isDark),
                const SizedBox(height: 14),

                // 5. Quick Actions Row (Practice Drill, AI Cheat Sheet, Add to Calendar)
                Row(
                  children: [
                    // A. Practice Drill
                    Expanded(
                      flex: 4,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.flash_on, size: 15),
                        label: const Text(
                          'Drill Topic',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E3A8A),
                          foregroundColor: Colors.white,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () {
                          QuizDrillModal.show(
                            context,
                            topic: heroExam.topicsCovered,
                            subject: heroExam.title,
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),

                    // B. AI Cheat Sheet Modal
                    Expanded(
                      flex: 4,
                      child: OutlinedButton.icon(
                        icon: const Icon(
                          Icons.auto_awesome,
                          size: 15,
                          color: Color(0xFF10B981),
                        ),
                        label: const Text(
                          'AI Summary',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          side: const BorderSide(color: Color(0xFF10B981)),
                          foregroundColor: isDark
                              ? Colors.white
                              : const Color(0xFF047857),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () =>
                            _showAiCheatSheetModal(context, heroExam),
                      ),
                    ),
                    const SizedBox(width: 6),

                    // C. Calendar Sync Button
                    IconButton(
                      icon: const Icon(Icons.calendar_month, size: 20),
                      tooltip: 'Add to Calendar with alert',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => CalendarSyncService.instance
                          .addToGoogleCalendar(heroExam),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 6. Compact Timeline of Other Upcoming Exams in this Track
          if (otherUpcoming.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF060B18)
                    : const Color(0xFFF8FAFC),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Following Next in Timeline (${otherUpcoming.length})',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...otherUpcoming.map((item) {
                    final itemTarget = _parseExamTarget(item);
                    final isToday =
                        itemTarget.year == _now.year &&
                        itemTarget.month == _now.month &&
                        itemTarget.day == _now.day;
                    final isTomorrow =
                        itemTarget.difference(_now).inDays == 0 &&
                        itemTarget.day == _now.day + 1;

                    final dayLabel = isToday
                        ? 'Today'
                        : (isTomorrow
                              ? 'Tomorrow'
                              : '${itemTarget.day}/${itemTarget.month}');

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(
                            _getTrackIcon(item.trackName),
                            size: 13,
                            color: _getTrackColor(item.trackName),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${item.trackName}: ${item.title}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$dayLabel • ${item.examTime}',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: isToday
                                  ? const Color(0xFFEF4444)
                                  : Colors.grey,
                              fontWeight: isToday
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Live Ticker Box Display (Hours : Mins : Secs)
  Widget _buildLiveCountdownBoxes(Duration diff, DateTime target, bool isDark) {
    if (diff.isNegative) {
      final hoursPassed = (-diff.inHours);
      if (hoursPassed < 3) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF10B981)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.mic, color: Color(0xFF10B981), size: 18),
              SizedBox(width: 8),
              Text(
                'Exam is Live! Open LiveMCQ & Speak Mistakes 🎙️',
                style: TextStyle(
                  color: Color(0xFF10B981),
                  fontWeight: FontWeight.bold,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        );
      }
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        child: const Text(
          'Exam concluded. Log your mistake notes for review.',
          style: TextStyle(color: Colors.grey, fontSize: 11.5),
        ),
      );
    }

    final days = diff.inDays;
    final hours = diff.inHours % 24;
    final minutes = diff.inMinutes % 60;
    final seconds = diff.inSeconds % 60;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (days > 0) ...[
          _buildTimeBlock(days.toString().padLeft(2, '0'), 'DAYS', isDark),
          _buildColon(isDark),
        ],
        _buildTimeBlock(hours.toString().padLeft(2, '0'), 'HOURS', isDark),
        _buildColon(isDark),
        _buildTimeBlock(minutes.toString().padLeft(2, '0'), 'MINS', isDark),
        _buildColon(isDark),
        _buildTimeBlock(seconds.toString().padLeft(2, '0'), 'SECS', isDark),
      ],
    );
  }

  Widget _buildTimeBlock(String value, String label, bool isDark) {
    return Container(
      width: 58,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
        ),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColon(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Text(
        ':',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.grey : Colors.black54,
        ),
      ),
    );
  }

  Widget _buildStatusBadge(Duration diff, DateTime target) {
    if (diff.isNegative) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF10B981).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text(
          'ACTIVE',
          style: TextStyle(
            color: Color(0xFF10B981),
            fontWeight: FontWeight.bold,
            fontSize: 10.5,
          ),
        ),
      );
    }

    if (diff.inHours < 1) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFEF4444)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.local_fire_department,
              size: 12,
              color: Color(0xFFEF4444),
            ),
            SizedBox(width: 3),
            Text(
              'STARTS SOON',
              style: TextStyle(
                color: Color(0xFFEF4444),
                fontWeight: FontWeight.bold,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      );
    }

    final isToday =
        target.year == _now.year &&
        target.month == _now.month &&
        target.day == _now.day;
    if (isToday) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text(
          'TODAY',
          style: TextStyle(
            color: Color(0xFFF59E0B),
            fontWeight: FontWeight.bold,
            fontSize: 10.5,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF6366F1).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'in ${diff.inDays + 1}d',
        style: const TextStyle(
          color: Color(0xFF6366F1),
          fontWeight: FontWeight.bold,
          fontSize: 10.5,
        ),
      ),
    );
  }

  /// AI Quick Cheat Sheet / Summary Bottom Sheet Modal
  void _showAiCheatSheetModal(BuildContext context, ExamSchedule exam) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AiCheatSheetBottomSheet(exam: exam),
    );
  }
}

class _AiCheatSheetBottomSheet extends StatefulWidget {
  final ExamSchedule exam;

  const _AiCheatSheetBottomSheet({required this.exam});

  @override
  State<_AiCheatSheetBottomSheet> createState() =>
      _AiCheatSheetBottomSheetState();
}

class _AiCheatSheetBottomSheetState extends State<_AiCheatSheetBottomSheet> {
  bool _isLoading = true;
  String? _content;

  @override
  void initState() {
    super.initState();
    _fetchSummary();
  }

  Future<void> _fetchSummary() async {
    final result = await GeminiAiService.instance.getExamQuickRevision(
      subject: widget.exam.subject,
      title: widget.exam.title,
      topicsCovered: widget.exam.topicsCovered,
      examTime: widget.exam.examTime,
      trackName: widget.exam.trackName,
    );

    if (mounted) {
      setState(() {
        _isLoading = false;
        _content = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  color: Color(0xFF10B981),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AI High-Yield Cheat Sheet',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      widget.exam.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const Divider(height: 20),

          // Content
          if (_isLoading) ...[
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 36),
                child: Column(
                  children: [
                    CircularProgressIndicator(strokeWidth: 2.5),
                    SizedBox(height: 12),
                    Text(
                      'Gemini AI is crafting your high-yield cheat sheet...',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  _content ?? 'No content available.',
                  style: const TextStyle(fontSize: 13.5, height: 1.55),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
