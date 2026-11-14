import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/services/ai/models/voice_mistake_result.dart';
import '../../../../core/services/ai/voice_mistake_parser_service.dart';
import '../../../../core/services/overlay/bubble_handoff_service.dart';
import 'package:overlay_bridge/overlay_bridge.dart';

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

  /// How many saved questions are waiting to be looked at in the app.
  ///
  /// Read from [BubbleHandoffService] rather than counted here, because the
  /// app is what clears them and the bubble has to follow it.
  int _pendingCount = 0;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _isExpanded = false;
    unawaited(_refreshPendingCount());
    WidgetsBinding.instance.addObserver(this);
    _overlaySub = FlutterOverlayWindow.overlayListener.listen((data) async {
      if (data == 'reset_to_collapsed' || data == 'reopen') {
        // The bubble is being reopened, so whatever the last session left
        // running has to be released before this screen claims to be idle.
        // Clearing the flags on their own left the microphone open behind a
        // bubble that showed nothing happening.
        await _releaseMic();
        await _refreshPendingCount();
        if (mounted) {
          setState(() {
            _isExpanded = false;
            _isRecording = false;
            _isDictating = false;
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
      // This screen already treats a resume as the end of whatever was in
      // progress; the microphone has to end with it.
      unawaited(_releaseMic());
      // A resume usually means the app has just been in front, which is where
      // the waiting questions get cleared.
      unawaited(_refreshPendingCount());
      if (mounted) {
        setState(() {
          _isExpanded = false;
          _isRecording = false;
          _isDictating = false;
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
    // Not awaited, because dispose cannot be: the release is handed to the
    // engine and runs on its own. It matters most here, since this widget
    // lives inside a foreground service that carries on after the bubble is
    // gone, and both services below are singletons in that same engine.
    unawaited(_releaseMic());
    _typedController.dispose();
    super.dispose();
  }

  /// Re-reads how many saved questions are still waiting in the app.
  Future<void> _refreshPendingCount() async {
    final count = (await BubbleHandoffService.instance.pending()).length;
    if (!mounted || count == _pendingCount) return;
    setState(() => _pendingCount = count);
  }

  /// Hands the microphone back, whatever state the bubble was in.
  ///
  /// Safe to call when nothing is running: both services check first, and
  /// neither throws. It deliberately touches no widget state, so it can be
  /// called from dispose.
  Future<void> _releaseMic() async {
    try {
      await DeviceDictationService.instance.stop();
    } catch (e) {
      debugPrint('Overlay: stopping dictation failed: $e');
    }
    try {
      await VoiceRecordingService.instance.cancelRecording();
    } catch (e) {
      debugPrint('Overlay: cancelling the recording failed: $e');
    }
    // The backstop, for a claim that was taken and then lost its way out. It
    // can also drop a claim the main app's own screens are holding, since the
    // service is one per process while the counters are one per engine; that
    // is harmless, because those screens are visible and Android asks nothing
    // of a visible app.
    try {
      await MicForegroundService.instance.releaseAll();
    } catch (e) {
      debugPrint('Overlay: releasing the microphone service failed: $e');
    }
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
      // Collapsing keeps what was typed but hides the field it was typed
      // into, so reopening the card looked exactly like the words had been
      // thrown away. They are put back in front of the user instead.
      if (_typedController.text.trim().isNotEmpty) {
        await _startTyping();
      }
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
      final saved = await VoiceMistakeParserService.instance
          .saveVoiceMistakeToDatabase(db, result);
      await db.close();
      // Left for the app to find when it next comes up. The stream below
      // reaches only an app that is already running and listening, and the
      // app listens for nothing; this is what survives the bubble being used
      // while the app is not even on screen.
      if (saved) {
        await BubbleHandoffService.instance.noteAdded(result.questionText);
      }
      await FlutterOverlayWindow.shareData('mistake_added');
      await FlutterOverlayWindow.updateFlag(OverlayFlag.defaultFlag);

      if (!mounted) return;
      setState(() {
        _lastResult = result;
        _isProcessing = false;
        _isTyping = false;
        _typedController.clear();
        _statusMessage = saved
            ? 'Saved to Mistake Bank ✓'
            : 'এটি আগেই সেভ করা আছে ✓';
      });
      if (saved) await _refreshPendingCount();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _statusMessage = 'সমস্যা হয়েছে: $e';
      });
    }
  }

  /// Carries whatever is in the bubble into the app and opens it.
  ///
  /// This is the way out of the bubble, in whatever state it is in. Words
  /// part way through being written come across and open the app's own voice
  /// sheet, already filled in, so the note is finished on a full screen
  /// instead of in a window the size of a stamp. With nothing written, the
  /// app simply comes up — on the Mistake Bank when the bubble has saved
  /// something, otherwise wherever the user left it.
  Future<void> _continueInApp() async {
    // Stopped first so the last thing said is in the box before it travels.
    if (_isDictating) {
      await DeviceDictationService.instance.stop();
      final heard = DeviceDictationService.instance.committedText.trim();
      if (heard.isNotEmpty) _typedController.text = heard;
    }
    // Written before the app is opened, so both are already there when it
    // comes up and asks what it was given and how it got here.
    await BubbleHandoffService.instance.noteDraft(_typedController.text);
    await BubbleHandoffService.instance.noteOpeningApp();
    final opened = await AppLauncher.instance.open();
    if (!mounted) return;
    if (!opened) {
      setState(() {
        _statusMessage = 'অ্যাপটি খোলা গেল না। নিজে খুলে দেখে নিন।';
      });
      return;
    }
    // Out of the way, so the app does not come up behind the bubble that
    // opened it. The bubble keeps running; this only collapses it.
    setState(() {
      _lastResult = null;
      _statusMessage = null;
      _isExpanded = false;
      _isDictating = false;
      _isTyping = false;
      // Cleared only once it is safely across: the sheet in the app now holds
      // these words, and leaving a copy here would have the user finishing
      // the same note twice.
      _typedController.clear();
      // The app clears what is waiting as it opens, so the badge goes now
      // rather than lingering until the next resume.
      _pendingCount = 0;
    });
    await FlutterOverlayWindow.updateFlag(OverlayFlag.defaultFlag);
    await FlutterOverlayWindow.resizeOverlay(110, 110, true);
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
        final saved = await VoiceMistakeParserService.instance
            .saveVoiceMistakeToDatabase(db, result);
        await db.close();

        // Left for the app to find when it next comes up, and only for a
        // question that was actually written. The stream below reaches an app
        // that is already running and listening, and the app listens for
        // nothing; this is what survives the bubble being used while the app
        // is not even on screen.
        if (saved) {
          await BubbleHandoffService.instance.noteAdded(result.questionText);
        }
        await FlutterOverlayWindow.shareData('mistake_added');

        setState(() {
          _lastResult = result;
          _isProcessing = false;
          _parseTimer?.cancel();
          _statusMessage = saved
              ? 'Saved to Mistake Bank ✓'
              : 'এটি আগেই সেভ করা আছে ✓';
        });
        if (saved) await _refreshPendingCount();
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
            // The bubble is collapsed nearly all the time, so this is the
            // only chance to say that something is waiting. Without it the
            // user had to expand the card to find out, which nobody does
            // without a reason to.
            Positioned(
              bottom: 2,
              right: 2,
              child: _pendingCount > 0
                  ? Container(
                      constraints: const BoxConstraints(
                        minWidth: 20,
                        minHeight: 20,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white, width: 1.2),
                      ),
                      child: Center(
                        child: Text(
                          _pendingCount > 9 ? '9+' : '$_pendingCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            height: 1.1,
                          ),
                        ),
                      ),
                    )
                  : Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF59E0B), // Golden amber mic badge
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.mic,
                        color: Colors.white,
                        size: 14,
                      ),
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
              // Always here, with nothing to wait for and nothing saved. The
              // banner below only appears once something has been saved, so
              // without this a half-written note left the user with no way
              // into the app at all.
              IconButton(
                icon: const Icon(
                  Icons.open_in_new,
                  color: Color(0xFFA5B4FC),
                  size: 20,
                ),
                tooltip: 'অ্যাপে নিয়ে যান',
                onPressed: _continueInApp,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 4),
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
                  // Before the window goes, not after: closing it tears down
                  // the screen, and anything still listening would be left
                  // running with nothing to turn it off.
                  await _releaseMic();
                  await FlutterOverlayWindow.resizeOverlay(110, 110, true);
                  await FlutterOverlayWindow.closeOverlay();
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Here for as long as anything is waiting, whatever else the card
          // happens to be showing. It used to sit in the result card, which
          // meant it vanished the moment the user tapped "Record Another" —
          // and after dictating three questions in a row there was no way
          // into the app left at all.
          if (_pendingCount > 0) ...[
            InkWell(
              onTap: _continueInApp,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.6),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.inventory_2_outlined,
                      color: Color(0xFFA5B4FC),
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$_pendingCount টি সেভ হয়েছে',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Text(
                      'অ্যাপে যান',
                      style: TextStyle(
                        color: Color(0xFFA5B4FC),
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      color: Color(0xFFA5B4FC),
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

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
                      Flexible(
                        child: Text(
                          '${_lastResult!.subject} • ${_lastResult!.topic}',
                          style: const TextStyle(
                            color: Color(0xFF10B981),
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
