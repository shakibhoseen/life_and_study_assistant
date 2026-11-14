import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/theme/fluent_tokens.dart';
import '../../../../core/services/ai/gemini_ai_service.dart';
import '../../../../core/services/ai/models/quiz_question.dart';
import '../../../../core/services/calendar/calendar_sync_service.dart';
import '../../../live_mcq/presentation/screens/live_mcq_screen.dart';
import '../../../quiz/presentation/widgets/question_bank_scanner_modal.dart';
import '../../../quiz/presentation/widgets/quiz_batch_correction_sheet.dart';
import '../../../quiz/presentation/widgets/quiz_drill_modal.dart';
import '../../../../core/widgets/ai_progress_pipeline_widget.dart';
import '../../../../core/widgets/premium_glass_card.dart';
import '../../../../core/widgets/premium_ui_kit.dart';

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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    final isDark = brightness == Brightness.dark;
    final onSurface = scheme.onSurface;
    final onSurfaceMuted = onSurface.withValues(alpha: 0.65);
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
        color: theme.cardTheme.color ?? theme.cardColor,
        borderRadius: FluentRadius.cardBorder,
        border: Border.all(
          color: FluentStroke.card(brightness),
          width: FluentStroke.width,
        ),
        boxShadow: FluentElevation.card(brightness),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header with Live Pulse indicator & Hub link
          Padding(
            padding: const EdgeInsets.only(
              left: FluentSpacing.l,
              right: FluentSpacing.m,
              top: FluentSpacing.m,
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: scheme.error, // Live indicator
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: FluentSpacing.s),
                Expanded(
                  child: Text(
                    'Multi-Track Exam Timeline',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: FluentType.bodyStrong.copyWith(color: onSurface),
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
                  label: Text('View All', style: FluentType.caption),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: scheme.primary,
                  ),
                ),
              ],
            ),
          ),

          // 2. Track Filter Chips (Horizontally Scrollable)
          if (tracks.length > 2) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: FluentSpacing.m),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: tracks.map((track) {
                    final isSelected = _selectedTrack == track;
                    final trackColor = track == 'All'
                        ? scheme.primary
                        : _getTrackColor(track);
                    return Padding(
                      padding: const EdgeInsets.only(
                        right: FluentSpacing.xs + 2,
                        bottom: FluentSpacing.s,
                      ),
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
                          style: FluentType.caption.copyWith(
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: isSelected
                                ? Colors.white
                                : onSurface.withValues(alpha: 0.85),
                          ),
                        ),
                        backgroundColor: FluentLayer.subtle(
                          onSurface,
                          brightness,
                        ),
                        selectedColor: trackColor,
                        side: BorderSide(
                          color: isSelected
                              ? trackColor
                              : FluentStroke.card(brightness),
                          width: FluentStroke.width,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: FluentRadius.controlBorder,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: FluentSpacing.xs,
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
            padding: const EdgeInsets.all(FluentSpacing.l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Track Pill + Exam Type + Date Status
                Row(
                  children: [
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: FluentSpacing.s,
                          vertical: FluentSpacing.xxs,
                        ),
                        decoration: BoxDecoration(
                          color: FluentLayer.subtle(
                            _getTrackColor(heroExam.trackName),
                            brightness,
                          ),
                          borderRadius: FluentRadius.controlBorder,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _getTrackIcon(heroExam.trackName),
                              size: 13,
                              color: _getTrackColor(heroExam.trackName),
                            ),
                            const SizedBox(width: FluentSpacing.xs),
                            Flexible(
                              child: Text(
                                heroExam.trackName,
                                style: FluentType.caption.copyWith(
                                  color: _getTrackColor(heroExam.trackName),
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: FluentSpacing.xs + 2),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(
                          ClipboardData(text: 'E-${heroExam.id}'),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: const Color(0xFF4F46E5),
                            content: Text(
                              'E-${heroExam.id} কপি হয়েছে! AI Mentor-এ এটি ব্যবহার করতে পারেন।',
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                      borderRadius: FluentRadius.controlBorder,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: FluentSpacing.xs + 2,
                          vertical: FluentSpacing.xxs,
                        ),
                        decoration: BoxDecoration(
                          color: FluentLayer.subtle(scheme.primary, brightness),
                          borderRadius: FluentRadius.controlBorder,
                        ),
                        child: Text(
                          'E-${heroExam.id}',
                          style: FluentType.caption.copyWith(
                            fontWeight: FontWeight.w600,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Flexible(child: _buildStatusBadge(difference, targetTime)),
                  ],
                ),
                const SizedBox(height: FluentSpacing.s),

                // Exam Title
                Text(
                  heroExam.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: FluentType.bodyStrong.copyWith(
                    fontSize: 16,
                    color: onSurface,
                  ),
                ),
                const SizedBox(height: FluentSpacing.xs),

                // Topics Covered
                Text(
                  heroExam.topicsCovered,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: FluentType.caption.copyWith(color: onSurfaceMuted),
                ),
                const SizedBox(height: FluentSpacing.m),

                // 4. Live Countdown Display
                _buildLiveCountdownBoxes(difference, targetTime, isDark),
                const SizedBox(height: FluentSpacing.m),

                // 5. Quick Actions Row (Practice Drill, AI Cheat Sheet, Add to Calendar, Test Paper Menu)
                () {
                  List<QuizQuestion> customQuestions = [];
                  if (heroExam.resourceSummary != null &&
                      heroExam.resourceSummary!.trim().startsWith('[')) {
                    try {
                      final decoded = jsonDecode(heroExam.resourceSummary!);
                      if (decoded is List) {
                        customQuestions = decoded
                            .map(
                              (e) => QuizQuestion.fromJson(
                                e as Map<String, dynamic>,
                              ),
                            )
                            .toList();
                      }
                    } catch (_) {}
                  }
                  final isCustomMcq = customQuestions.isNotEmpty;

                  return Row(
                    children: [
                      // A. Practice Drill
                      Expanded(
                        flex: 4,
                        child: ElevatedButton.icon(
                          icon: Icon(
                            isCustomMcq
                                ? Icons.play_arrow_rounded
                                : Icons.flash_on,
                            size: isCustomMcq ? 17 : 15,
                          ),
                          label: Text(
                            isCustomMcq
                                ? 'MCQ প্র্যাকটিস (${customQuestions.length})'
                                : 'Drill Topic',
                            style: FluentType.caption.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: scheme.primary,
                            foregroundColor: scheme.onPrimary,
                            elevation: 0,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              vertical: FluentSpacing.s,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: FluentRadius.controlBorder,
                            ),
                          ),
                          onPressed: () {
                            QuizDrillModal.show(
                              context,
                              topic: heroExam.topicsCovered,
                              subject: heroExam.title,
                              examId: heroExam.id,
                              customQuestions: isCustomMcq
                                  ? customQuestions
                                  : null,
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: FluentSpacing.s),

                      // B. AI Cheat Sheet Modal
                      Expanded(
                        flex: 4,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.auto_awesome, size: 15),
                          label: Text(
                            'AI Summary',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FluentType.caption.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            side: BorderSide(
                              color: FluentStroke.card(brightness),
                              width: FluentStroke.width,
                            ),
                            foregroundColor: onSurface,
                            padding: const EdgeInsets.symmetric(
                              vertical: FluentSpacing.s,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: FluentRadius.controlBorder,
                            ),
                          ),
                          onPressed: () =>
                              _showAiCheatSheetModal(context, heroExam),
                        ),
                      ),
                      const SizedBox(width: FluentSpacing.xs + 2),

                      // C. Calendar Sync Button
                      IconButton(
                        icon: const Icon(Icons.calendar_month, size: 20),
                        tooltip: 'Add to Calendar with alert',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => CalendarSyncService.instance
                            .addToGoogleCalendar(heroExam),
                      ),

                      // D. Test Paper Options (Batch Fix, Copy, Edit Scanner)
                      if (isCustomMcq) ...[
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert, size: 20),
                            tooltip: 'টেস্ট পেপার প্রশ্ন অপশন',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onSelected: (val) {
                              if (val == 'ai_fix') {
                                QuizBatchCorrectionSheet.show(
                                  context,
                                  ref: ref,
                                  questions: customQuestions,
                                  examId: heroExam.id,
                                  topic: heroExam.topicsCovered,
                                  subject: heroExam.title,
                                );
                              } else if (val == 'copy_questions') {
                                _copyExamQuestionsToClipboard(
                                  context,
                                  heroExam,
                                  customQuestions,
                                );
                              } else if (val == 'edit_scanner') {
                                QuestionBankScannerModal.show(
                                  context,
                                  initialQuestions: customQuestions,
                                  initialTitle: heroExam.title,
                                  initialSubject: heroExam.subject,
                                  existingExamId: heroExam.id,
                                );
                              }
                            },
                            itemBuilder: (ctx) => [
                              PopupMenuItem(
                                value: 'ai_fix',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.auto_fix_high_rounded,
                                      color: scheme.primary,
                                      size: 18,
                                    ),
                                    const SizedBox(width: FluentSpacing.s),
                                    Text(
                                      'AI ফিক্স (ব্যাচ সংশোধন)',
                                      style: FluentType.body.copyWith(
                                        color: onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'copy_questions',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.copy_rounded,
                                      color: scheme.primary,
                                      size: 18,
                                    ),
                                    const SizedBox(width: FluentSpacing.s),
                                    Text(
                                      'প্রশ্নসমূহ কপি করুন',
                                      style: FluentType.body.copyWith(
                                        color: onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'edit_scanner',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.edit_note_rounded,
                                      color: scheme.primary,
                                      size: 18,
                                    ),
                                    const SizedBox(width: FluentSpacing.s),
                                    Text(
                                      'প্রশ্ন সম্পাদনা ও টেস্ট পেপার',
                                      style: FluentType.body.copyWith(
                                        color: onSurface,
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
                  );
                }(),
              ],
            ),
          ),

          // 6. Compact Timeline of Other Upcoming Exams in this Track
          if (otherUpcoming.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: FluentSpacing.l,
                vertical: FluentSpacing.s,
              ),
              decoration: BoxDecoration(
                color: onSurface.withValues(alpha: isDark ? 0.04 : 0.03),
                border: Border(
                  top: BorderSide(
                    color: FluentStroke.divider(brightness),
                    width: FluentStroke.width,
                  ),
                ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(FluentRadius.card),
                  bottomRight: Radius.circular(FluentRadius.card),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Following Next in Timeline (${otherUpcoming.length})',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: FluentType.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: onSurfaceMuted,
                    ),
                  ),
                  const SizedBox(height: FluentSpacing.xs + 2),
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
                      padding: const EdgeInsets.symmetric(
                        vertical: FluentSpacing.xs,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _getTrackIcon(item.trackName),
                            size: 13,
                            color: _getTrackColor(item.trackName),
                          ),
                          const SizedBox(width: FluentSpacing.xs + 2),
                          Expanded(
                            flex: 3,
                            child: Text(
                              '${item.trackName}: ${item.title}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: FluentType.caption.copyWith(
                                color: onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(width: FluentSpacing.s),
                          Flexible(
                            flex: 2,
                            child: Text(
                              '$dayLabel • ${item.examTime}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              style: FluentType.caption.copyWith(
                                color: isToday ? scheme.error : onSurfaceMuted,
                                fontWeight: isToday
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
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
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final onSurfaceMuted = theme.colorScheme.onSurface.withValues(alpha: 0.65);
    const liveGreen = Color(0xFF10B981);

    if (diff.isNegative) {
      final hoursPassed = (-diff.inHours);
      if (hoursPassed < 3) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            vertical: FluentSpacing.s,
            horizontal: FluentSpacing.m,
          ),
          decoration: BoxDecoration(
            color: FluentLayer.subtle(liveGreen, brightness),
            borderRadius: FluentRadius.controlBorder,
            border: Border.all(
              color: liveGreen.withValues(alpha: 0.4),
              width: FluentStroke.width,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.mic, color: liveGreen, size: 18),
              const SizedBox(width: FluentSpacing.s),
              Flexible(
                child: Text(
                  'Exam is Live! Open LiveMCQ & Speak Mistakes 🎙️',
                  style: FluentType.caption.copyWith(
                    color: liveGreen,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      }
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: FluentSpacing.s),
        alignment: Alignment.center,
        child: Text(
          'Exam concluded. Log your mistake notes for review.',
          textAlign: TextAlign.center,
          style: FluentType.caption.copyWith(color: onSurfaceMuted),
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
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final onSurface = theme.colorScheme.onSurface;

    // Flexible, not a fixed width: at 1.5x text on a 320px screen four blocks
    // plus their separators no longer fit the row.
    return Flexible(
      child: Container(
        width: 58,
        padding: const EdgeInsets.symmetric(
          vertical: FluentSpacing.s,
          horizontal: FluentSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: FluentLayer.subtle(onSurface, brightness),
          borderRadius: FluentRadius.controlBorder,
          border: Border.all(
            color: FluentStroke.card(brightness),
            width: FluentStroke.width,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FluentType.subtitle.copyWith(
                fontSize: 18,
                color: onSurface,
              ),
            ),
            const SizedBox(height: FluentSpacing.xxs),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FluentType.caption.copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: onSurface.withValues(alpha: 0.65),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColon(bool isDark) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FluentSpacing.xs),
      child: Text(
        ':',
        style: FluentType.subtitle.copyWith(
          fontSize: 18,
          color: onSurface.withValues(alpha: 0.65),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(Duration diff, DateTime target) {
    final scheme = Theme.of(context).colorScheme;

    if (diff.isNegative) {
      return const PremiumTag(label: 'ACTIVE', color: Color(0xFF10B981));
    }

    if (diff.inHours < 1) {
      return PremiumTag(
        label: 'STARTS SOON',
        icon: Icons.local_fire_department,
        color: scheme.error,
      );
    }

    final isToday =
        target.year == _now.year &&
        target.month == _now.month &&
        target.day == _now.day;
    if (isToday) {
      return const PremiumTag(label: 'TODAY', color: Color(0xFFF59E0B));
    }

    return PremiumTag(label: 'in ${diff.inDays + 1}d', color: scheme.primary);
  }

  void _copyExamQuestionsToClipboard(
    BuildContext context,
    ExamSchedule exam,
    List<QuizQuestion> questions,
  ) {
    final buffer = StringBuffer();
    buffer.writeln('পরীক্ষা: ${exam.title}');
    buffer.writeln('রেফারেন্স: E-${exam.id}');
    if (exam.subject.isNotEmpty) buffer.writeln('বিষয়: ${exam.subject}');
    buffer.writeln('মোট প্রশ্ন: ${questions.length}টি');
    buffer.writeln('==============================\n');

    for (int i = 0; i < questions.length; i++) {
      final q = questions[i];
      buffer.writeln('প্রশ্ন ${i + 1}: ${q.questionText}');
      for (int optIdx = 0; optIdx < q.options.length; optIdx++) {
        final optChar = optIdx == 0
            ? 'ক'
            : (optIdx == 1 ? 'খ' : (optIdx == 2 ? 'গ' : 'ঘ'));
        buffer.writeln('  $optChar. ${q.options[optIdx]}');
      }
      final correctAns =
          q.correctIndex >= 0 && q.correctIndex < q.options.length
          ? q.options[q.correctIndex]
          : 'অজানা';
      buffer.writeln('• চিহ্নিত সঠিক উত্তর: $correctAns');
      if (q.explanation.isNotEmpty) {
        buffer.writeln('• ব্যাখ্যা: ${q.explanation}');
      }
      buffer.writeln('');
    }
    buffer.writeln('==============================');
    buffer.writeln(
      'নির্দেশনা: অনুগ্রহ করে প্রতিটি প্রশ্ন ও উত্তর নিরপেক্ষভাবে যাচাই করুন। কোনো প্রশ্নে তথ্যের ভুল, ভুল উত্তর বা অস্পষ্টতা থাকলে বিস্তারিত বলুন।',
    );

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF10B981),
        content: Text(
          'E-${exam.id} এর ${questions.length}টি প্রশ্ন ক্লিপবোর্ডে কপি হয়েছে!',
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final onSurface = scheme.onSurface;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      padding: const EdgeInsets.all(FluentSpacing.xl),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? theme.cardColor,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(FluentRadius.large),
        ),
        border: Border(
          top: BorderSide(
            color: FluentStroke.card(theme.brightness),
            width: FluentStroke.width,
          ),
        ),
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
                color: onSurface.withValues(alpha: 0.25),
                borderRadius: FluentRadius.controlBorder,
              ),
            ),
          ),
          const SizedBox(height: FluentSpacing.m),

          // Header
          Row(
            children: [
              const PremiumIconBadge(icon: Icons.auto_awesome),
              const SizedBox(width: FluentSpacing.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI High-Yield Cheat Sheet',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: FluentType.bodyStrong.copyWith(
                        fontSize: 16,
                        color: onSurface,
                      ),
                    ),
                    Text(
                      widget.exam.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FluentType.caption.copyWith(
                        color: onSurface.withValues(alpha: 0.65),
                      ),
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
          Divider(
            height: FluentSpacing.xl,
            color: FluentStroke.divider(theme.brightness),
          ),

          // Content
          if (_isLoading) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: FluentSpacing.m),
              child: AiProgressPipelineWidget(
                type: AiTaskType.text,
                customStatus: 'চিট শিট তৈরি হচ্ছে…',
              ),
            ),
          ] else ...[
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  _content ?? 'No content available.',
                  style: FluentType.body.copyWith(color: onSurface),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
