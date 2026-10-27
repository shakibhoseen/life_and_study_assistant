import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/services/ai/models/voice_mistake_result.dart';
import '../../../../core/services/ai/voice_mistake_parser_service.dart';
import '../../../../core/services/voice/voice_recording_service.dart';

class FloatingBubbleOverlay extends StatefulWidget {
  const FloatingBubbleOverlay({super.key});

  @override
  State<FloatingBubbleOverlay> createState() => _FloatingBubbleOverlayState();
}

class _FloatingBubbleOverlayState extends State<FloatingBubbleOverlay>
    with WidgetsBindingObserver {
  bool _isExpanded = false;
  bool _isRecording = false;
  bool _isProcessing = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  StreamSubscription? _overlaySub;
  VoiceMistakeResult? _lastResult;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _isExpanded = false;
    WidgetsBinding.instance.addObserver(this);
    _overlaySub = FlutterOverlayWindow.overlayListener.listen((data) {
      if (data == 'reset_to_collapsed' || data == 'reopen') {
        if (mounted) {
          setState(() {
            _isExpanded = false;
            _isRecording = false;
            _isProcessing = false;
            _statusMessage = null;
            _lastResult = null;
          });
          WidgetsBinding.instance.scheduleFrame();
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (mounted) {
        setState(() {
          _isExpanded = false;
          _isRecording = false;
          _isProcessing = false;
          _statusMessage = null;
        });
        WidgetsBinding.instance.scheduleFrame();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _overlaySub?.cancel();
    _recordTimer?.cancel();
    super.dispose();
  }

  void _toggleExpand() async {
    final nextExpanded = !_isExpanded;
    setState(() {
      _isExpanded = nextExpanded;
      _statusMessage = null;
    });

    if (nextExpanded) {
      await FlutterOverlayWindow.resizeOverlay(
        WindowSize.matchParent,
        WindowSize.matchParent,
        false,
      );
    } else {
      await FlutterOverlayWindow.resizeOverlay(110, 110, true);
    }
  }

  Future<void> _startRecording() async {
    try {
      final hasPerm = await VoiceRecordingService.instance.hasPermission();
      if (!hasPerm) {
        setState(() {
          _statusMessage =
              'মাইক্রোফোন পারমিশন পাওয়া যায়নি। অ্যাপ ওপেন করে অনুমতি দিন।';
        });
        return;
      }

      await VoiceRecordingService.instance.startRecording();
      setState(() {
        _isRecording = true;
        _recordSeconds = 0;
        _lastResult = null;
        _statusMessage = 'শুনছি... আপনার ভুল হওয়া প্রশ্ন ও উত্তর বলুন';
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
      _statusMessage = 'ভয়েস বিশ্লেষণ করা হচ্ছে...';
    });

    try {
      final audioFile = await VoiceRecordingService.instance.stopRecording();

      // If user stopped in less than 1 second without speaking
      if (recordedDuration < 1) {
        setState(() {
          _isProcessing = false;
          _statusMessage =
              'রেকর্ডিং সংক্ষিপ্ত ছিল। প্রশ্নটি মুখে বলে তারপর থামুন।';
        });
        return;
      }

      if (audioFile != null) {
        final result = await VoiceMistakeParserService.instance
            .parseMistakeFromAudio(
              audioFile,
              durationSeconds: recordedDuration,
            );

        if (result == null) {
          setState(() {
            _isProcessing = false;
            _statusMessage = 'কোনো কথা বা প্রশ্ন শনাক্ত করা যায়নি। আবার বলুন।';
          });
          return;
        }

        // Save into local Drift database ONLY if valid result
        final db = AppDatabase();
        await VoiceMistakeParserService.instance.saveVoiceMistakeToDatabase(
          db,
          result,
        );
        await db.close();

        // Notify main app over stream
        await FlutterOverlayWindow.shareData('mistake_added');

        setState(() {
          _lastResult = result;
          _isProcessing = false;
          _statusMessage = 'Saved to Mistake Bank ✓';
        });
      } else {
        setState(() {
          _isProcessing = false;
          _statusMessage = 'No audio captured';
        });
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Parse error: $e';
      });
    }
  }

  String _formatTimer(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_isExpanded) {
      return Material(
        color: Colors.black.withValues(alpha: 0.65),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleExpand,
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                child: GestureDetector(
                  onTap: () {}, // Prevent taps inside the card from collapsing
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    child: _buildExpandedCard(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      elevation: 0.0,
      child: Center(child: _buildCollapsedBubble()),
    );
  }

  /// Compact Messenger-style floating circular chat head
  Widget _buildCollapsedBubble() {
    return GestureDetector(
      onTap: _toggleExpand,
      child: Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          color: const Color(0xFF061332), // Midnight Navy
          shape: BoxShape.circle,
          border: Border.all(
            color: const Color(0xFF10B981),
            width: 2.2,
          ), // Emerald border
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(Icons.school, color: Colors.white, size: 28),
            Positioned(
              bottom: 2,
              right: 2,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Color(0xFFF59E0B), // Golden amber mic badge
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mic, color: Colors.white, size: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Expanded glassmorphic card over LiveMCQ
  Widget _buildExpandedCard() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 340, minWidth: 280),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF334155), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top bar
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.mic,
                  color: Color(0xFF10B981),
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'LiveMCQ Voice Note',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      'ভুল হওয়া প্রশ্ন মুখে বলুন — জেমিনি সেভ করবে',
                      style: TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.grey, size: 22),
                tooltip: 'Minimize to Bubble',
                onPressed: _toggleExpand,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(
                  Icons.power_settings_new,
                  color: Colors.redAccent,
                  size: 18,
                ),
                tooltip: 'Close Overlay',
                onPressed: () async {
                  setState(() {
                    _isExpanded = false;
                  });
                  await FlutterOverlayWindow.resizeOverlay(110, 110, true);
                  await FlutterOverlayWindow.closeOverlay();
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Central Microphone Action
          if (!_isProcessing && _lastResult == null) ...[
            GestureDetector(
              onTap: _isRecording ? _stopRecordingAndParse : _startRecording,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isRecording
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF1E3A8A),
                  boxShadow: [
                    BoxShadow(
                      color: (_isRecording ? Colors.red : Colors.indigo)
                          .withValues(alpha: 0.4),
                      blurRadius: _isRecording ? 18 : 8,
                      spreadRadius: _isRecording ? 4 : 1,
                    ),
                  ],
                ),
                child: Icon(
                  _isRecording ? Icons.stop : Icons.mic,
                  color: Colors.white,
                  size: 38,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _isRecording
                  ? 'Recording: ${_formatTimer(_recordSeconds)}'
                  : 'Tap to Speak Mistake',
              style: TextStyle(
                color: _isRecording ? Colors.redAccent : Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _statusMessage ??
                  'e.g. "১২ নম্বর প্রশ্নে মানস সরোবরের নদী ছিল ব্রহ্মপুত্র"',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 10.5),
            ),
          ],

          // Loading / Parsing indicator
          if (_isProcessing) ...[
            const SizedBox(height: 14),
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Color(0xFF10B981),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Gemini AI is parsing voice note...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Generating MCQ, answer and explanation',
              style: TextStyle(color: Colors.grey, fontSize: 10),
            ),
            const SizedBox(height: 14),
          ],

          // Result Saved Card
          if (_lastResult != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(10),
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
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${_lastResult!.subject} • ${_lastResult!.topic}',
                        style: const TextStyle(
                          color: Color(0xFF10B981),
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _lastResult!.questionText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'সঠিক উত্তর: ${_lastResult!.options[_lastResult!.correctIndex]}',
                    style: const TextStyle(
                      color: Color(0xFFF59E0B),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _lastResult = null;
                        _statusMessage = null;
                      });
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.grey),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text(
                      'Record Another',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _toggleExpand,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text(
                      'Done',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
