import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/fluent_tokens.dart';
import '../providers/adaptive_planner_provider.dart';

class FocusTimerDialog extends ConsumerStatefulWidget {
  final String taskId;
  final String taskTitle;
  final String subject;
  final int initialMinutes;

  const FocusTimerDialog({
    super.key,
    required this.taskId,
    required this.taskTitle,
    required this.subject,
    required this.initialMinutes,
  });

  static Future<void> show(
    BuildContext context, {
    required String taskId,
    required String taskTitle,
    required String subject,
    required int initialMinutes,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => FocusTimerDialog(
        taskId: taskId,
        taskTitle: taskTitle,
        subject: subject,
        initialMinutes: initialMinutes,
      ),
    );
  }

  @override
  ConsumerState<FocusTimerDialog> createState() => _FocusTimerDialogState();
}

class _FocusTimerDialogState extends ConsumerState<FocusTimerDialog> {
  late int _totalSeconds;
  late int _remainingSeconds;
  Timer? _timer;
  bool _isRunning = false;
  bool _isFinished = false;

  @override
  void initState() {
    super.initState();
    _totalSeconds =
        (widget.initialMinutes > 0 ? widget.initialMinutes : 10) * 60;
    _remainingSeconds = _totalSeconds;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    if (_isRunning) return;
    setState(() => _isRunning = true);

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() => _remainingSeconds--);
      } else {
        _timer?.cancel();
        setState(() {
          _isRunning = false;
          _isFinished = true;
        });
        // Finish it, not flip it. This called toggleTaskCompletion, so running
        // the timer on a task already ticked off unticked it — the opposite of
        // what the line above it said it did.
        unawaited(
          ref
              .read(adaptivePlannerProvider.notifier)
              .markTaskCompleted(widget.taskId),
        );
      }
    });
  }

  void _pauseTimer() {
    _timer?.cancel();
    setState(() => _isRunning = false);
  }

  void _resetTimer() {
    _timer?.cancel();
    setState(() {
      _isRunning = false;
      _remainingSeconds = _totalSeconds;
      _isFinished = false;
    });
  }

  void _changeDuration(int minutes) {
    _timer?.cancel();
    setState(() {
      _totalSeconds = minutes * 60;
      _remainingSeconds = _totalSeconds;
      _isRunning = false;
      _isFinished = false;
    });
  }

  String _formatTime(int totalSecs) {
    final mins = totalSecs ~/ 60;
    final secs = totalSecs % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final isDark = brightness == Brightness.dark;
    final onSurface = theme.colorScheme.onSurface;
    final progress = _totalSeconds > 0
        ? (_totalSeconds - _remainingSeconds) / _totalSeconds
        : 0.0;

    return AlertDialog(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: FluentRadius.cardBorder,
        side: FluentStroke.side(brightness),
      ),
      titlePadding: const EdgeInsets.fromLTRB(
        FluentSpacing.xl,
        FluentSpacing.xl,
        FluentSpacing.xl,
        0,
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: FluentSpacing.xl,
        vertical: FluentSpacing.l,
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(FluentSpacing.s),
            decoration: BoxDecoration(
              color: FluentLayer.subtle(Colors.indigo, brightness),
              borderRadius: FluentRadius.controlBorder,
            ),
            child: const Icon(Icons.timer, color: Colors.indigo, size: 20),
          ),
          const SizedBox(width: FluentSpacing.s),
          Expanded(
            child: Text(
              'Micro-Focus Timer',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: FluentType.bodyStrong.copyWith(color: onSurface),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Task info badge
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: FluentSpacing.m,
                vertical: FluentSpacing.s,
              ),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFF1F5F9),
                borderRadius: FluentRadius.cardBorder,
                border: Border.all(
                  color: FluentStroke.card(brightness),
                  width: FluentStroke.width,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    widget.taskTitle,
                    textAlign: TextAlign.center,
                    style: FluentType.bodyStrong.copyWith(color: onSurface),
                  ),
                  Text(
                    widget.subject,
                    style: FluentType.caption.copyWith(
                      color: onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: FluentSpacing.xl),

            if (!_isFinished) ...[
              // Circular Progress Timer
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 170,
                    height: 170,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 8,
                      backgroundColor: onSurface.withValues(alpha: 0.12),
                      valueColor: AlwaysStoppedAnimation(
                        _isRunning
                            ? (isDark ? const Color(0xFF818CF8) : Colors.indigo)
                            : Colors.grey,
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatTime(_remainingSeconds),
                        style: FluentType.title.copyWith(
                          fontSize: 36,
                          letterSpacing: 1.2,
                          color: onSurface,
                        ),
                      ),
                      Text(
                        _isRunning ? 'Focusing...' : 'Ready to start',
                        style: FluentType.caption.copyWith(
                          color: onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: FluentSpacing.xl),

              // Duration selector chips (if not running)
              if (!_isRunning) ...[
                Wrap(
                  spacing: FluentSpacing.s,
                  children: [5, 10, 15, 25].map((m) {
                    final isSelected = _totalSeconds == m * 60;
                    return ChoiceChip(
                      label: Text(
                        '${m}m',
                        style: FluentType.caption.copyWith(
                          color: isSelected
                              ? (isDark ? Colors.white : Colors.indigo.shade900)
                              : onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                      selected: isSelected,
                      shape: RoundedRectangleBorder(
                        borderRadius: FluentRadius.controlBorder,
                        side: FluentStroke.side(brightness),
                      ),
                      selectedColor: isDark
                          ? const Color(0xFF3730A3)
                          : Colors.indigo.shade100,
                      backgroundColor: isDark ? const Color(0xFF1E293B) : null,
                      onSelected: (_) => _changeDuration(m),
                    );
                  }).toList(),
                ),
                const SizedBox(height: FluentSpacing.l),
              ],

              // Controls
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isRunning)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber.shade800,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: FluentRadius.controlBorder,
                        ),
                      ),
                      icon: const Icon(Icons.pause),
                      label: const Text('Pause'),
                      onPressed: _pauseTimer,
                    )
                  else
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E3A8A),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: FluentRadius.controlBorder,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: FluentSpacing.xxl,
                          vertical: FluentSpacing.m,
                        ),
                      ),
                      icon: const Icon(Icons.play_arrow),
                      label: Text(
                        'Start Focus',
                        style: FluentType.bodyStrong.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      onPressed: _startTimer,
                    ),
                  const SizedBox(width: FluentSpacing.s),
                  TextButton.icon(
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Reset'),
                    onPressed: _resetTimer,
                  ),
                ],
              ),
            ] else ...[
              // Celebration Screen
              Container(
                padding: const EdgeInsets.all(FluentSpacing.l),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF064E3B).withValues(alpha: 0.3)
                      : Colors.green.shade50,
                  borderRadius: FluentRadius.cardBorder,
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF059669).withValues(alpha: 0.3)
                        : Colors.green.shade200,
                    width: FluentStroke.width,
                  ),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 54,
                    ),
                    const SizedBox(height: FluentSpacing.m),
                    Text(
                      'অভিনন্দন! ফোকাস সেশন সমাপ্ত!',
                      textAlign: TextAlign.center,
                      style: FluentType.bodyStrong.copyWith(color: onSurface),
                    ),
                    const SizedBox(height: FluentSpacing.s),
                    Text(
                      'আজকের মাইক্রো-কমিটমেন্ট টাস্কটি স্বয়ংক্রিয়ভাবে সমাপ্ত (Completed ✓) মার্ক করা হয়েছে।',
                      textAlign: TextAlign.center,
                      style: FluentType.caption.copyWith(
                        color: onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: FluentSpacing.l),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: FluentRadius.controlBorder,
                  ),
                  minimumSize: const Size(double.infinity, 44),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('Great, Done!'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
