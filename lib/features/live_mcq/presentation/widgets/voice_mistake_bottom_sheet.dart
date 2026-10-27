import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_provider.dart';
import '../../../../core/services/ai/models/voice_mistake_result.dart';
import '../../../../core/services/ai/voice_mistake_parser_service.dart';
import '../../../../core/services/overlay/live_mcq_bubble_service.dart';
import '../../../../core/services/voice/voice_recording_service.dart';
import '../../../quiz/presentation/providers/drill_history_provider.dart';
import '../../../spaced_repetition/presentation/providers/spaced_repetition_provider.dart';
import '../../../topics/presentation/providers/topics_provider.dart';

class VoiceMistakeBottomSheet extends ConsumerStatefulWidget {
  const VoiceMistakeBottomSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const VoiceMistakeBottomSheet(),
    );
  }

  @override
  ConsumerState<VoiceMistakeBottomSheet> createState() =>
      _VoiceMistakeBottomSheetState();
}

class _VoiceMistakeBottomSheetState
    extends ConsumerState<VoiceMistakeBottomSheet> {
  final TextEditingController _textController = TextEditingController();
  bool _isRecording = false;
  bool _isProcessing = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  VoiceMistakeResult? _parsedResult;
  String? _statusMessage;
  bool _isBubbleActive = false;

  @override
  void initState() {
    super.initState();
    _checkBubbleStatus();
  }

  Future<void> _checkBubbleStatus() async {
    final active = await LiveMcqBubbleService.instance.isOverlayActive();
    if (mounted) {
      setState(() {
        _isBubbleActive = active;
      });
    }
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    try {
      final hasPerm = await LiveMcqBubbleService.instance
          .checkMicrophonePermission();
      if (!hasPerm) {
        final requested = await LiveMcqBubbleService.instance
            .requestMicrophonePermission();
        if (!requested) {
          setState(() {
            _statusMessage =
                'Microphone permission denied. Please allow microphone access.';
          });
          return;
        }
      }

      await VoiceRecordingService.instance.startRecording();
      setState(() {
        _isRecording = true;
        _recordSeconds = 0;
        _parsedResult = null;
        _statusMessage = 'Listening... Speak your LiveMCQ mistake';
      });

      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          _recordSeconds++;
        });
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Mic error: $e';
      });
    }
  }

  Future<void> _stopRecordingAndParse() async {
    final recordedDuration = _recordSeconds;
    _recordTimer?.cancel();
    setState(() {
      _isRecording = false;
      _isProcessing = true;
      _statusMessage = 'Gemini AI is analyzing voice note...';
    });

    try {
      final audioFile = await VoiceRecordingService.instance.stopRecording();
      if (recordedDuration < 1) {
        setState(() {
          _isProcessing = false;
          _statusMessage =
              'রেকর্ডিং সংক্ষিপ্ত ছিল। মুখে প্রশ্নটি বলে তারপর থামুন।';
        });
        return;
      }

      if (audioFile != null) {
        final result = await VoiceMistakeParserService.instance
            .parseMistakeFromAudio(
              audioFile,
              durationSeconds: recordedDuration,
            );
        if (result != null) {
          await _saveAndRefresh(result);
        } else {
          setState(() {
            _isProcessing = false;
            _statusMessage =
                'কোনো কথা বা প্রশ্ন শনাক্ত করা যায়নি। দয়া করে আবার বলুন।';
          });
        }
      } else {
        setState(() {
          _isProcessing = false;
          _statusMessage = 'No audio captured';
        });
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Error: $e';
      });
    }
  }

  Future<void> _parseTextMistake() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Gemini AI is structuring question...';
    });

    try {
      final result = await VoiceMistakeParserService.instance
          .parseMistakeFromText(text);
      if (result != null) {
        await _saveAndRefresh(result);
      } else {
        setState(() {
          _isProcessing = false;
          _statusMessage =
              'কোনো প্রশ্ন শনাক্ত করা যায়নি। আরও সুনির্দিষ্ট করে লিখুন।';
        });
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Error: $e';
      });
    }
  }

  Future<void> _saveAndRefresh(VoiceMistakeResult result) async {
    final db = ref.read(appDatabaseProvider);
    await VoiceMistakeParserService.instance.saveVoiceMistakeToDatabase(
      db,
      result,
    );

    ref.invalidate(wrongQuestionsStreamProvider);
    ref.invalidate(dueSpacedReviewsStreamProvider);
    ref.invalidate(allSpacedReviewsStreamProvider);
    ref.invalidate(weakTopicsStreamProvider);

    if (mounted) {
      setState(() {
        _parsedResult = result;
        _isProcessing = false;
        _statusMessage = 'Saved to Mistake Bank & Spaced Repetition ✓';
        _textController.clear();
      });
    }
  }

  Future<void> _toggleFloatingBubble() async {
    if (_isBubbleActive) {
      await LiveMcqBubbleService.instance.stopBubble();
      if (mounted) setState(() => _isBubbleActive = false);
    } else {
      final result = await LiveMcqBubbleService.instance.startBubble();
      if (!mounted) return;

      switch (result) {
        case BubbleLaunchResult.success:
          setState(() => _isBubbleActive = true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Color(0xFF10B981),
              content: Text(
                'Floating Bubble Active! Open LiveMCQ and dictate mistakes freely.',
              ),
            ),
          );
          break;
        case BubbleLaunchResult.overlayPermissionDenied:
          setState(() => _isBubbleActive = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.redAccent,
              content: Text(
                'Please enable "Draw over other apps" permission in Settings.',
              ),
            ),
          );
          break;
        case BubbleLaunchResult.microphonePermissionDenied:
          setState(() => _isBubbleActive = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.redAccent,
              content: Text(
                'Microphone permission is required to record voice mistakes.',
              ),
            ),
          );
          break;
        case BubbleLaunchResult.failed:
          setState(() => _isBubbleActive = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.redAccent,
              content: Text(
                'Failed to launch floating bubble. Please try again.',
              ),
            ),
          );
          break;
      }
    }
  }

  String _formatTimer(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF111827) : Colors.white;

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        left: 20,
        right: 20,
        top: 12,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 44,
                height: 4.5,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Header Row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.mic,
                    color: Color(0xFF10B981),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'LiveMCQ Voice Mistake Note',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'ভুল হওয়া প্রশ্ন মুখে বলুন — জেমিনি ব্যাখ্যাসহ সেভ করবে',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
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
            const Divider(height: 24),

            // Launch Floating Bubble CTA Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _isBubbleActive
                    ? const Color(0xFF10B981).withValues(alpha: 0.15)
                    : (isDark
                          ? const Color(0xFF1E293B)
                          : const Color(0xFFF1F5F9)),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _isBubbleActive
                      ? const Color(0xFF10B981)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _isBubbleActive
                        ? Icons.bubble_chart
                        : Icons.bubble_chart_outlined,
                    color: _isBubbleActive
                        ? const Color(0xFF10B981)
                        : const Color(0xFF6366F1),
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isBubbleActive
                              ? 'Floating Bubble is Active'
                              : 'LiveMCQ Floating Bubble',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          _isBubbleActive
                              ? 'Open LiveMCQ to speak without leaving the app'
                              : 'Messenger-style bubble over LiveMCQ app',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _toggleFloatingBubble,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isBubbleActive
                          ? Colors.red.shade700
                          : const Color(0xFF1E3A8A),
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      _isBubbleActive ? 'Stop' : 'Launch',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Microphone Recording Area
            Center(
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _isRecording
                        ? _stopRecordingAndParse
                        : _startRecording,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isRecording
                            ? const Color(0xFFEF4444)
                            : const Color(0xFF10B981),
                        boxShadow: [
                          BoxShadow(
                            color:
                                (_isRecording
                                        ? Colors.red
                                        : const Color(0xFF10B981))
                                    .withValues(alpha: 0.4),
                            blurRadius: _isRecording ? 20 : 10,
                            spreadRadius: _isRecording ? 4 : 1,
                          ),
                        ],
                      ),
                      child: Icon(
                        _isRecording ? Icons.stop : Icons.mic,
                        color: Colors.white,
                        size: 40,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _isRecording
                        ? 'Recording... ${_formatTimer(_recordSeconds)}'
                        : 'Tap Mic to Speak Mistake',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: _isRecording ? Colors.redAccent : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _statusMessage ?? 'মুখে বলুন: "১২ নম্বর প্রশ্নে মানস সরোবর থেকে উৎপন্ন নদী ছিল ব্রহ্মপুত্র"',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Processing state
            if (_isProcessing) ...[
              const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Color(0xFF10B981),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Successfully Parsed Card
            if (_parsedResult != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E293B)
                      : const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF10B981).withValues(alpha: 0.4),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.check_circle,
                          color: Color(0xFF10B981),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Saved: ${_parsedResult!.subject} • ${_parsedResult!.topic}',
                            style: const TextStyle(
                              color: Color(0xFF10B981),
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _parsedResult!.questionText,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'সঠিক উত্তর: ${_parsedResult!.options[_parsedResult!.correctIndex]}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFF59E0B),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ব্যাখ্যা: ${_parsedResult!.explanation}',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? Colors.grey.shade300
                            : Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Text input alternative
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    style: const TextStyle(fontSize: 12.5),
                    decoration: InputDecoration(
                      hintText: 'Or type mistake topic (e.g. পলাশী যুদ্ধ ১৭৫৭)',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _parseTextMistake,
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF1E3A8A),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.send, size: 18),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
