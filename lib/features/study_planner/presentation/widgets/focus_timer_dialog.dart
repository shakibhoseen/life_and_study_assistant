import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
        // Automatically mark task complete in study planner
        ref
            .read(adaptivePlannerProvider.notifier)
            .toggleTaskCompletion(widget.taskId);
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
    final progress = _totalSeconds > 0
        ? (_totalSeconds - _remainingSeconds) / _totalSeconds
        : 0.0;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.timer, color: Colors.indigo, size: 20),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Micro-Focus Timer',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Text(
                    widget.taskTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    widget.subject,
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

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
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation(
                        _isRunning ? Colors.indigo : Colors.grey,
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatTime(_remainingSeconds),
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      Text(
                        _isRunning ? 'Focusing...' : 'Ready to start',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Duration selector chips (if not running)
              if (!_isRunning) ...[
                Wrap(
                  spacing: 6,
                  children: [5, 10, 15, 25].map((m) {
                    final isSelected = _totalSeconds == m * 60;
                    return ChoiceChip(
                      label: Text(
                        '${m}m',
                        style: const TextStyle(fontSize: 11),
                      ),
                      selected: isSelected,
                      selectedColor: Colors.indigo.shade100,
                      onSelected: (_) => _changeDuration(m),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text(
                        'Start Focus',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: _startTimer,
                    ),
                  const SizedBox(width: 10),
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
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 54,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'অভিনন্দন! ফোকাস সেশন সমাপ্ত!',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'আজকের মাইক্রো-কমিটমেন্ট টাস্কটি স্বয়ংক্রিয়ভাবে সমাপ্ত (Completed ✓) মার্ক করা হয়েছে।',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white70
                            : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
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
