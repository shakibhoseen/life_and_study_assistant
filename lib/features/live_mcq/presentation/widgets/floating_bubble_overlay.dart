import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/services/ai/models/voice_mistake_result.dart';
import '../../../../core/services/ai/voice_mistake_parser_service.dart';
import '../../../../core/services/voice/device_dictation_service.dart';
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

  // Measured on a real recording, this call ran to 159 seconds. Without a
  // clock on screen that is indistinguishable from the app having hung, so
  // the wait is counted out loud and given an honest expectation.
  Timer? _parseTimer;
  int _parseSeconds = 0;

  // The handset transcribes as the user speaks, with no keyboard to open and
  // nothing to upload. Sending the audio to Gemini instead was measured at up
  // to 159 seconds, and the point of the bubble is to stay out of the way
  // while the user is reading the exam.
  final TextEditingController _typedController = TextEditingController();
  bool _isTyping = false;
  bool _isDictating = false;
  String _heardText = '';
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
            _parseTimer?.cancel();
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
          _parseTimer?.cancel();
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
    _parseTimer?.cancel();
    _typedController.dispose();
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
      // Collapsed, the bubble must not take focus or it would swallow taps
      // meant for the app underneath.
      _isTyping = false;
      await FlutterOverlayWindow.updateFlag(OverlayFlag.defaultFlag);
      await FlutterOverlayWindow.resizeOverlay(110, 110, true);
    }
  }

  /// Listens through the phone's own recogniser and shows the words as they
  /// arrive.
  Future<void> _startDictation() async {
    final ok = await DeviceDictationService.instance.init();
    if (!mounted) return;

    if (!ok) {
      setState(() {
        _statusMessage =
            'ফোনে ভয়েস টাইপিং পাওয়া যায়নি। রেকর্ড করে পাঠাতে পারেন।';
      });
      return;
    }

    // Said plainly, because without the pack the recogniser does not fail
    // — it writes Bengali speech as English-sounding words, and the user is
    // left blaming their own pronunciation.

    setState(() {
      _isDictating = true;
      _heardText = '';
      _statusMessage = 'শুনছি… প্রশ্ন ও সঠিক উত্তর বলুন';
    });

    await DeviceDictationService.instance.listen(
      // Carry on from what is already in the box rather than
      // clearing it.
      seed: _typedController.text,
      onResult: (text, isFinal) {
        if (!mounted) return;
        setState(() {
          _heardText = text;
          _typedController.text = text;
          // isFinal now means the user pressed stop, not that a pause ended
          // an utterance, so the session stays open while they think.
          _statusMessage = isFinal ? 'শোনা শেষ' : 'শুনছি… $text';
        });
        // Left for the user to send rather than fired automatically: a
        // half-heard sentence saved on its own is worse than one more tap.
        if (isFinal) setState(() => _isDictating = false);
      },
    );
  }

  Future<void> _stopDictation() async {
    await DeviceDictationService.instance.stop();
    if (!mounted) return;

    // stop() banks the utterance in flight, so the service holds the whole
    // sentence even though the screen only ever saw the last piece.
    final heard = DeviceDictationService.instance.committedText.trim();
    _heardText = heard;
    _typedController.text = heard;
    if (heard.isEmpty) {
      // A network error on Bengali is not the user mumbling: without a
      // connection the online recogniser has nothing to answer with, and
      // this handset has no Bangla offline.
      final err = DeviceDictationService.instance.lastError ?? '';
      final offline = err.contains('network') || err.contains('error_network');
      setState(() {
        _isDictating = false;
        _statusMessage = offline
            ? 'বাংলা লেখার জন্য ইন্টারনেট লাগবে (ফোনে অফলাইন বাংলা নেই)।\n'
                  'নেট ছাড়া চাইলে মাইকে লম্বা চাপ দিয়ে রেকর্ড করুন।'
            : 'কিছু শোনা যায়নি। আবার বলুন।';
      });
      return;
    }

    setState(() {
      _isDictating = false;
      _statusMessage = 'শোনা শেষ — দেখে নিয়ে পাঠান';
    });
  }

  /// Opens a field the user can dictate into with the keyboard's own mic.
  ///
  /// The overlay is created non-focusable so it does not steal taps from the
  /// app beneath it, which also means no keyboard. Focus is taken only while
  /// typing and given straight back.
  Future<void> _startTyping() async {
    await FlutterOverlayWindow.updateFlag(OverlayFlag.focusPointer);
    if (!mounted) return;
    setState(() {
      _isTyping = true;
      _statusMessage = null;
    });
  }

  Future<void> _cancelTyping() async {
    await FlutterOverlayWindow.updateFlag(OverlayFlag.defaultFlag);
    if (!mounted) return;
    setState(() {
      _isTyping = false;
      _typedController.clear();
    });
  }

  /// Sends dictated or typed text instead of audio.
  Future<void> _parseTypedMistake() async {
    final text = _typedController.text.trim();
    if (text.isEmpty || _isProcessing) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'প্রশ্ন সাজানো হচ্ছে…';
    });

    try {
      final result = await VoiceMistakeParserService.instance
          .parseMistakeFromText(text);

      if (result == null) {
        setState(() {
          _isProcessing = false;
          _statusMessage =
              'লেখাটি থেকে প্রশ্ন বোঝা গেল না। আরেকটু বিস্তারিত লিখুন।';
        });
        return;
      }

      final db = AppDatabase();
      await VoiceMistakeParserService.instance.saveVoiceMistakeToDatabase(
        db,
        result,
      );
      await db.close();
      await FlutterOverlayWindow.shareData('mistake_added');
      await FlutterOverlayWindow.updateFlag(OverlayFlag.defaultFlag);

      if (!mounted) return;
      setState(() {
        _lastResult = result;
        _isProcessing = false;
        _isTyping = false;
        _typedController.clear();
        _statusMessage = 'Saved to Mistake Bank ✓';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _statusMessage = 'সমস্যা হয়েছে: $e';
      });
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

      // Mono 16 kHz: speech needs no more, and a recording a fraction of
      // the size spends a fraction of the time being uploaded. Gemini bills
      // audio by duration, so this costs nothing in tokens.
      await VoiceRecordingService.instance.startRecording(
        config: VoiceRecordingService.speechConfig,
      );
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
      _parseSeconds = 0;
      _statusMessage = _parseStatus(0);
    });

    _parseTimer?.cancel();
    _parseTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || !_isProcessing) {
        t.cancel();
        return;
      }
      setState(() {
        _parseSeconds++;
        _statusMessage = _parseStatus(_parseSeconds);
      });
    });

    try {
      final audioFile = await VoiceRecordingService.instance.stopRecording();

      // If user stopped in less than 1 second without speaking
      if (recordedDuration < 1) {
        setState(() {
          _isProcessing = false;
          _parseTimer?.cancel();
          _statusMessage =
              'রেকর্ডিং সংক্ষিপ্ত ছিল। প্রশ্নটি মুখে বলে তারপর থামুন।';
        });
        return;
      }

      if (audioFile != null) {
        final size = await audioFile.length();
        debugPrint(
          'Bubble voice: ${size ~/ 1024} KB, ${recordedDuration}s recorded',
        );
        final result = await VoiceMistakeParserService.instance
            .parseMistakeFromAudio(
              audioFile,
              durationSeconds: recordedDuration,
            );

        if (result == null) {
          setState(() {
            _isProcessing = false;
            _parseTimer?.cancel();
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
          _parseTimer?.cancel();
          _statusMessage = 'Saved to Mistake Bank ✓';
        });
      } else {
        setState(() {
          _isProcessing = false;
          _parseTimer?.cancel();
          _statusMessage = 'No audio captured';
        });
      }
    } on VoiceParseException catch (e) {
      // Same reason as the sheet: a busy server is not the user mumbling.
      setState(() {
        _isProcessing = false;
        _parseTimer?.cancel();
        _statusMessage = e.userMessage;
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _parseTimer?.cancel();
        _statusMessage = 'সমস্যা হয়েছে: $e';
      });
    }
  }

  /// What to say while the model is still thinking.
  ///
  /// Naming the stage and the usual wait is the difference between "it is
  /// working" and "it has frozen"; the number moving is what says the app is
  /// alive at all.
  String _parseStatus(int seconds) {
    if (seconds < 5) return 'ভয়েস পাঠানো হচ্ছে… ${seconds}s';
    if (seconds < 90) {
      return 'Gemini শুনছে ও প্রশ্ন সাজাচ্ছে… ${seconds}s\n'
          'সাধারণত ৩০–৯০ সেকেন্ড লাগে।';
    }
    return 'এখনো চলছে… ${seconds}s\n'
        'লম্বা রেকর্ডিং হলে দুই মিনিটের বেশি লাগতে পারে।';
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
              // The phone transcribes as you speak, so this is the fast
              // path. Recording and uploading audio is still available
              // underneath for when dictation is not installed.
              onTap: _isDictating
                  ? _stopDictation
                  : _isRecording
                  ? _stopRecordingAndParse
                  : _startDictation,
              onLongPress: _isRecording || _isDictating
                  ? null
                  : _startRecording,
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
                  (_isRecording || _isDictating) ? Icons.stop : Icons.mic,
                  color: Colors.white,
                  size: 38,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _isDictating
                  ? 'শুনছি…'
                  : _isRecording
                  ? 'Recording: ${_formatTimer(_recordSeconds)}'
                  : 'চেপে বলুন — ফোনই লিখে দেবে',
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

            // The keyboard's own mic transcribes on the device, so this is
            // immediate and does not depend on the model being free.
            if (!_isRecording) ...[
              const SizedBox(height: 14),
              if (!_isTyping && _heardText.isNotEmpty && !_isDictating) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Text(
                    _heardText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => setState(() {
                        _heardText = '';
                        _typedController.clear();
                        _statusMessage = null;
                      }),
                      child: const Text(
                        'আবার বলুন',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _startTyping,
                      child: const Text(
                        'ঠিক করুন',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _isProcessing ? null : _parseTypedMistake,
                      icon: const Icon(Icons.send, size: 16),
                      label: const Text(
                        'যোগ করুন',
                        style: TextStyle(fontSize: 12.5),
                      ),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
              ] else if (!_isTyping && !_isDictating)
                TextButton.icon(
                  onPressed: _startTyping,
                  icon: const Icon(
                    Icons.keyboard_alt_outlined,
                    size: 18,
                    color: Colors.white70,
                  ),
                  label: const Text(
                    'অথবা লিখুন',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: TextField(
                    controller: _typedController,
                    autofocus: true,
                    maxLines: 3,
                    minLines: 2,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'কীবোর্ডের 🎙 চেপে প্রশ্ন ও সঠিক উত্তর বলুন',
                      hintStyle: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11.5,
                      ),
                      filled: true,
                      fillColor: Colors.white10,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: _cancelTyping,
                      child: const Text(
                        'বাতিল',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: _isProcessing ? null : _parseTypedMistake,
                      icon: const Icon(Icons.send, size: 16),
                      label: const Text(
                        'যোগ করুন',
                        style: TextStyle(fontSize: 12.5),
                      ),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
              ],
            ],
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
                    'সঠিক উত্তর: ${(_lastResult!.correctIndex >= 0 && _lastResult!.correctIndex < _lastResult!.options.length) ? _lastResult!.options[_lastResult!.correctIndex] : "অজানা"}',
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
