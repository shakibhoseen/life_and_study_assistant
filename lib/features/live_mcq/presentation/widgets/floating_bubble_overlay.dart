import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/fluent_tokens.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/services/ai/models/voice_mistake_result.dart';
import '../../../../core/services/ai/voice_mistake_parser_service.dart';
import '../../../../core/services/overlay/bubble_handoff_service.dart';
import 'package:overlay_bridge/overlay_bridge.dart';

import '../../../../core/services/voice/device_dictation_service.dart';
import '../../../../core/services/voice/voice_recording_service.dart';
import '../../../../core/services/reference/reference_service.dart';
import '../../../reference/presentation/widgets/detail_body.dart';

enum OverlayMode {
  mistake,
  formula,
}

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

  // Formula Peek & Law states
  OverlayMode _mode = OverlayMode.mistake;
  final TextEditingController _formulaSearchController = TextEditingController();
  List<ReferenceHit> _formulaHits = [];
  ReferenceHit? _selectedFormulaHit;
  bool _isSearchingFormulas = false;
  late final AppDatabase _db = AppDatabase();
  bool _referenceSeeded = false;

  @override
  void initState() {
    super.initState();
    _isExpanded = false;
    unawaited(_refreshPendingCount());
    unawaited(_ensureReferenceSeeded().then((_) {
      unawaited(_searchFormulas(''));
    }));
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
      } else if (data == 'mode_formula') {
        if (mounted) {
          setState(() {
            _mode = OverlayMode.formula;
          });
        }
      } else if (data == 'mode_mistake') {
        if (mounted) {
          setState(() {
            _mode = OverlayMode.mistake;
          });
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
    _formulaSearchController.dispose();
    unawaited(_db.close());
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

  /// Ensures bundled reference tables (math formulas, units, measurements) are seeded in SQLite
  Future<void> _ensureReferenceSeeded() async {
    if (_referenceSeeded) return;
    try {
      final sheets = await ReferenceService.instance.sheets(_db);
      if (sheets.isEmpty) {
        await ReferenceService.instance.seed(_db);
      }
      _referenceSeeded = true;
    } catch (e) {
      debugPrint('Overlay: reference seed check failed: $e');
    }
  }

  /// Searches formulas or returns all formulas if query is empty
  Future<void> _searchFormulas(String query) async {
    await _ensureReferenceSeeded();
    final trimmed = query.trim();

    setState(() {
      _isSearchingFormulas = true;
    });

    try {
      final List<ReferenceHit> hits;
      if (trimmed.isEmpty) {
        hits = await _getAllFormulas();
      } else {
        hits = await ReferenceService.instance.search(_db, trimmed);
      }
      if (!mounted) return;
      setState(() {
        _formulaHits = hits;
        _isSearchingFormulas = false;
      });
    } catch (e) {
      debugPrint('Overlay: formula search failed: $e');
      if (!mounted) return;
      setState(() {
        _isSearchingFormulas = false;
      });
    }
  }

  /// Fetches all formulas across all tables, prioritizing laws & diagrams first
  Future<List<ReferenceHit>> _getAllFormulas() async {
    final sheets = await ReferenceService.instance.sheets(_db);
    final hits = <ReferenceHit>[];
    for (final sheet in sheets) {
      final rows = await ReferenceService.instance.rows(_db, sheet.sheetKey);
      for (final row in rows) {
        hits.add(ReferenceHit(sheet: sheet, row: row));
      }
    }

    hits.sort((a, b) {
      final aHasDetail = (a.row.detail ?? '').trim().isNotEmpty;
      final bHasDetail = (b.row.detail ?? '').trim().isNotEmpty;
      if (aHasDetail && !bHasDetail) return -1;
      if (!aHasDetail && bHasDetail) return 1;
      return 0;
    });

    return hits;
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
          boxShadow: FluentElevation.flyout(Brightness.dark),
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
                        horizontal: FluentSpacing.xs,
                        vertical: FluentSpacing.xxs,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1),
                        borderRadius: FluentRadius.controlBorder,
                        border: Border.all(color: Colors.white, width: 1.2),
                      ),
                      child: Center(
                        child: Text(
                          _pendingCount > 9 ? '9+' : '$_pendingCount',
                          style: FluentType.caption.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            height: 1.1,
                          ),
                        ),
                      ),
                    )
                  : Container(
                      padding: const EdgeInsets.all(FluentSpacing.xs),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF59E0B),
                        borderRadius: BorderRadius.all(
                          Radius.circular(FluentRadius.control),
                        ),
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
    final isFormulaMode = _mode == OverlayMode.formula;
    return Container(
      constraints: BoxConstraints(
        maxWidth: isFormulaMode ? 380 : 340,
        minWidth: 280,
      ),
      padding: const EdgeInsets.all(FluentSpacing.l),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.96),
        borderRadius: FluentRadius.cardBorder,
        border: Border.all(
          color: const Color(0xFF334155),
          width: FluentStroke.width,
        ),
        boxShadow: FluentElevation.flyout(Brightness.dark),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top bar
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(FluentSpacing.s),
                decoration: BoxDecoration(
                  color: isFormulaMode
                      ? const Color(0xFF6366F1).withValues(alpha: 0.2)
                      : const Color(0xFF10B981).withValues(alpha: 0.2),
                  borderRadius: FluentRadius.controlBorder,
                ),
                child: Icon(
                  isFormulaMode ? Icons.functions : Icons.mic,
                  color: isFormulaMode
                      ? const Color(0xFF818CF8)
                      : const Color(0xFF10B981),
                  size: 18,
                ),
              ),
              const SizedBox(width: FluentSpacing.s),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isFormulaMode ? 'কুইক সূত্র ও Law' : 'LiveMCQ Voice Note',
                      style: FluentType.bodyStrong.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      isFormulaMode
                          ? 'সূত্র, প্রমাণ ও ডায়াগ্রাম সাথে সাথে দেখুন'
                          : 'ভুল হওয়া প্রশ্ন মুখে বলুন — জেমিনি সেভ করবে',
                      style: FluentType.caption.copyWith(
                        color: Colors.white54,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
              const SizedBox(width: FluentSpacing.xs),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.grey, size: 22),
                tooltip: 'Minimize to Bubble',
                onPressed: _toggleExpand,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: FluentSpacing.xs),
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
                  await FlutterOverlayWindow.updateFlag(OverlayFlag.defaultFlag);
                  await FlutterOverlayWindow.resizeOverlay(110, 110, true);
                  await FlutterOverlayWindow.closeOverlay();
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: FluentSpacing.m),

          // Mode Switcher Tabs
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: FluentRadius.controlBorder,
              border: Border.all(color: const Color(0xFF334155)),
            ),
            padding: const EdgeInsets.all(3),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      if (_mode != OverlayMode.mistake) {
                        await FlutterOverlayWindow.updateFlag(OverlayFlag.defaultFlag);
                        setState(() {
                          _mode = OverlayMode.mistake;
                        });
                      }
                    },
                    borderRadius: FluentRadius.controlBorder,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: _mode == OverlayMode.mistake
                            ? const Color(0xFF10B981)
                            : Colors.transparent,
                        borderRadius: FluentRadius.controlBorder,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.mic,
                            size: 14,
                            color: _mode == OverlayMode.mistake
                                ? Colors.white
                                : Colors.white70,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'ভুল খাতা',
                            style: FluentType.caption.copyWith(
                              fontWeight: FontWeight.w600,
                              color: _mode == OverlayMode.mistake
                                  ? Colors.white
                                  : Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      if (_mode != OverlayMode.formula) {
                        setState(() {
                          _mode = OverlayMode.formula;
                        });
                        if (_formulaSearchController.text.trim().isNotEmpty) {
                          _searchFormulas(_formulaSearchController.text);
                        }
                      }
                    },
                    borderRadius: FluentRadius.controlBorder,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: _mode == OverlayMode.formula
                            ? const Color(0xFF6366F1)
                            : Colors.transparent,
                        borderRadius: FluentRadius.controlBorder,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.functions,
                            size: 14,
                            color: _mode == OverlayMode.formula
                                ? Colors.white
                                : Colors.white70,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'সূত্র ও Law',
                            style: FluentType.caption.copyWith(
                              fontWeight: FontWeight.w600,
                              color: _mode == OverlayMode.formula
                                  ? Colors.white
                                  : Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: FluentSpacing.m),

          if (_mode == OverlayMode.mistake)
            _buildMistakeSection()
          else if (_selectedFormulaHit != null)
            _buildFormulaDetailView(_selectedFormulaHit!)
          else
            _buildFormulaSearchView(),
        ],
      ),
    );
  }

  /// Voice note mistake dictation & transcription section
  Widget _buildMistakeSection() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_pendingCount > 0) ...[
          InkWell(
            onTap: _continueInApp,
              borderRadius: FluentRadius.controlBorder,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: FluentSpacing.m,
                  vertical: FluentSpacing.s,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.18),
                  borderRadius: FluentRadius.controlBorder,
                  border: Border.all(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.6),
                    width: FluentStroke.width,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.inventory_2_outlined,
                      color: Color(0xFFA5B4FC),
                      size: 16,
                    ),
                    const SizedBox(width: FluentSpacing.s),
                    Expanded(
                      child: Text(
                        '$_pendingCount টি সেভ হয়েছে',
                        style: FluentType.caption.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      'অ্যাপে যান',
                      style: FluentType.caption.copyWith(
                        color: const Color(0xFFA5B4FC),
                        fontWeight: FontWeight.w600,
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
            const SizedBox(height: FluentSpacing.m),
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
                  borderRadius: FluentRadius.controlBorder,
                  color: _isRecording
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF1E3A8A),
                  boxShadow: FluentElevation.card(Brightness.dark),
                ),
                child: Icon(
                  (_isRecording || _isDictating) ? Icons.stop : Icons.mic,
                  color: Colors.white,
                  size: 38,
                ),
              ),
            ),
            const SizedBox(height: FluentSpacing.m),
            Text(
              _isDictating
                  ? 'শুনছি…'
                  : _isRecording
                  ? 'Recording: ${_formatTimer(_recordSeconds)}'
                  : 'চেপে বলুন — ফোনই লিখে দেবে',
              style: FluentType.bodyStrong.copyWith(
                fontSize: 13,
                color: _isRecording ? Colors.redAccent : Colors.white,
              ),
            ),
            const SizedBox(height: FluentSpacing.xs),
            Text(
              _statusMessage ??
                  'e.g. "১২ নম্বর প্রশ্নে মানস সরোবরের নদী ছিল ব্রহ্মপুত্র"',
              textAlign: TextAlign.center,
              style: FluentType.caption.copyWith(color: Colors.white54),
            ),

            // The keyboard's own mic transcribes on the device, so this is
            // immediate and does not depend on the model being free.
            if (!_isRecording) ...[
              const SizedBox(height: FluentSpacing.l),
              if (!_isTyping && _heardText.isNotEmpty && !_isDictating) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: FluentSpacing.xl),
                  child: Text(
                    _heardText,
                    textAlign: TextAlign.center,
                    style: FluentType.body.copyWith(color: Colors.white),
                  ),
                ),
                const SizedBox(height: FluentSpacing.m),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => setState(() {
                        _heardText = '';
                        _typedController.clear();
                        _statusMessage = null;
                      }),
                      child: Text(
                        'আবার বলুন',
                        style: FluentType.caption.copyWith(color: Colors.white54),
                      ),
                    ),
                    const SizedBox(width: FluentSpacing.s),
                    TextButton(
                      onPressed: _startTyping,
                      child: Text(
                        'ঠিক করুন',
                        style: FluentType.caption.copyWith(color: Colors.white54),
                      ),
                    ),
                    const SizedBox(width: FluentSpacing.s),
                    FilledButton.icon(
                      onPressed: _isProcessing ? null : _parseTypedMistake,
                      icon: const Icon(Icons.send, size: 16),
                      label: Text(
                        'যোগ করুন',
                        style: FluentType.caption,
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
                  label: Text(
                    'অথবা লিখুন',
                    style: FluentType.caption.copyWith(color: Colors.white70),
                  ),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: FluentSpacing.xl),
                  child: TextField(
                    controller: _typedController,
                    autofocus: true,
                    maxLines: 3,
                    minLines: 2,
                    style: FluentType.body.copyWith(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'কীবোর্ডের 🎙 চেপে প্রশ্ন ও সঠিক উত্তর বলুন',
                      hintStyle: FluentType.caption.copyWith(
                        color: Colors.white38,
                      ),
                      filled: true,
                      fillColor: Colors.white10,
                      border: OutlineInputBorder(
                        borderRadius: FluentRadius.controlBorder,
                        borderSide: BorderSide.none,
                      ),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(height: FluentSpacing.m),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: _cancelTyping,
                      child: Text(
                        'বাতিল',
                        style: FluentType.caption.copyWith(color: Colors.white54),
                      ),
                    ),
                    const SizedBox(width: FluentSpacing.m),
                    FilledButton.icon(
                      onPressed: _isProcessing ? null : _parseTypedMistake,
                      icon: const Icon(Icons.send, size: 16),
                      label: Text(
                        'যোগ করুন',
                        style: FluentType.caption,
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
            const SizedBox(height: FluentSpacing.l),
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Color(0xFF10B981),
              ),
            ),
            const SizedBox(height: FluentSpacing.m),
            Text(
              'Gemini AI is parsing voice note...',
              style: FluentType.caption.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: FluentSpacing.xs),
            Text(
              'Generating MCQ, answer and explanation',
              style: FluentType.caption.copyWith(color: Colors.white54),
            ),
            const SizedBox(height: FluentSpacing.l),
          ],

          // Result Saved Card
          if (_lastResult != null) ...[
            Container(
              padding: const EdgeInsets.all(FluentSpacing.m),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: FluentRadius.cardBorder,
                border: Border.all(
                  color: const Color(0xFF10B981).withValues(alpha: 0.4),
                  width: FluentStroke.width,
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
                      const SizedBox(width: FluentSpacing.s),
                      Flexible(
                        child: Text(
                          '${_lastResult!.subject} • ${_lastResult!.topic}',
                          style: FluentType.caption.copyWith(
                            color: const Color(0xFF10B981),
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: FluentSpacing.s),
                  Text(
                    _lastResult!.questionText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: FluentType.caption.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: FluentSpacing.xs),
                  Text(
                    'সঠিক উত্তর: ${(_lastResult!.correctIndex >= 0 && _lastResult!.correctIndex < _lastResult!.options.length) ? _lastResult!.options[_lastResult!.correctIndex] : "অজানা"}',
                    style: FluentType.caption.copyWith(
                      color: const Color(0xFFF59E0B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: FluentSpacing.m),
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
                      side: const BorderSide(color: Colors.white24),
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: FluentRadius.controlBorder,
                      ),
                    ),
                    child: Text(
                      'Record Another',
                      style: FluentType.caption,
                    ),
                  ),
                ),
                const SizedBox(width: FluentSpacing.s),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _toggleExpand,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: FluentRadius.controlBorder,
                      ),
                    ),
                    child: Text(
                      'Done',
                      style: FluentType.caption.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      );
  }

  /// Search interface for formula peek
  Widget _buildFormulaSearchView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Search bar
        TextField(
          controller: _formulaSearchController,
          style: FluentType.body.copyWith(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'খুঁজুন — বৃত্ত, পিথাগোরাস, ত্বরণ...',
            hintStyle: FluentType.caption.copyWith(color: Colors.white38),
            prefixIcon: const Icon(Icons.search, color: Colors.white70, size: 20),
            suffixIcon: _formulaSearchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, color: Colors.white70, size: 18),
                    onPressed: () {
                      _formulaSearchController.clear();
                      _searchFormulas('');
                    },
                  )
                : null,
            filled: true,
            fillColor: Colors.white10,
            border: OutlineInputBorder(
              borderRadius: FluentRadius.controlBorder,
              borderSide: BorderSide.none,
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: FluentSpacing.m,
              vertical: FluentSpacing.s,
            ),
          ),
          onTap: () async {
            await FlutterOverlayWindow.updateFlag(OverlayFlag.focusPointer);
          },
          onChanged: (text) {
            _searchFormulas(text);
          },
        ),
        const SizedBox(height: FluentSpacing.s),

        // Quick horizontal tags when search query is empty
        if (_formulaSearchController.text.trim().isEmpty) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final tag in [
                  'সব',
                  'বৃত্ত',
                  'পিথাগোরাস',
                  'ত্রিভুজ',
                  'ঘনক',
                  'গতি',
                  'ত্বরণ',
                  'মাইল',
                  'পরিমাপ',
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      onTap: () {
                        if (tag == 'সব') {
                          _formulaSearchController.clear();
                          _searchFormulas('');
                        } else {
                          _formulaSearchController.text = tag;
                          _searchFormulas(tag);
                        }
                      },
                      borderRadius: FluentRadius.controlBorder,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: FluentRadius.controlBorder,
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: Text(
                          tag,
                          style: FluentType.caption.copyWith(
                            color: const Color(0xFFA5B4FC),
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: FluentSpacing.s),
        ],

        // Formula list count indicator
        if (_formulaHits.isNotEmpty && !_isSearchingFormulas) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              _formulaSearchController.text.trim().isEmpty
                  ? 'সকল সূত্র (${_formulaHits.length}টি)'
                  : 'অনুসন্ধান ফলাফল (${_formulaHits.length}টি)',
              style: FluentType.caption.copyWith(
                color: Colors.white54,
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
          ),
        ],

        // Loading indicator
        if (_isSearchingFormulas) ...[
          const Center(
            child: Padding(
              padding: EdgeInsets.all(FluentSpacing.m),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF6366F1),
                ),
              ),
            ),
          ),
        ] else if (_formulaHits.isEmpty &&
            _formulaSearchController.text.trim().isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.all(FluentSpacing.m),
            child: Center(
              child: Text(
                'কোনো সূত্র মেলেনি',
                style: FluentType.caption.copyWith(color: Colors.white54),
              ),
            ),
          ),
        ] else if (_formulaHits.isNotEmpty) ...[
          Container(
            constraints: const BoxConstraints(maxHeight: 300),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _formulaHits.length,
              separatorBuilder: (_, index) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final hit = _formulaHits[index];
                final cells = decodeStringList(hit.row.cellsJson);
                final hasDetail = (hit.row.detail ?? '').trim().isNotEmpty;

                return InkWell(
                  onTap: () async {
                    await FlutterOverlayWindow.updateFlag(
                      OverlayFlag.defaultFlag,
                    );
                    setState(() {
                      _selectedFormulaHit = hit;
                    });
                  },
                  borderRadius: FluentRadius.controlBorder,
                  child: Container(
                    padding: const EdgeInsets.all(FluentSpacing.s),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: FluentRadius.controlBorder,
                      border: Border.all(
                        color: hasDetail
                            ? const Color(0xFF10B981).withValues(alpha: 0.5)
                            : const Color(0xFF334155),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      hit.sheet.title,
                                      style: FluentType.caption.copyWith(
                                        color: const Color(0xFFA5B4FC),
                                        fontWeight: FontWeight.w600,
                                        fontSize: 11,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (hasDetail) ...[
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'Law/চিত্র',
                                        style: FluentType.caption.copyWith(
                                          color: const Color(0xFF10B981),
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                cells.join('  •  '),
                                style: FluentType.bodyStrong.copyWith(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (hit.row.note.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  hit.row.note,
                                  style: FluentType.caption.copyWith(
                                    color: Colors.white54,
                                    fontSize: 10,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right,
                          color: Colors.white38,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  /// Detail view for a selected formula (cells, law explanation, SVG)
  Widget _buildFormulaDetailView(ReferenceHit hit) {
    final cells = decodeStringList(hit.row.cellsJson);
    final columns = decodeStringList(hit.sheet.columnsJson);
    final hasDetail = (hit.row.detail ?? '').trim().isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'তালিকায় ফিরুন',
              onPressed: () {
                setState(() {
                  _selectedFormulaHit = null;
                });
              },
            ),
            const SizedBox(width: FluentSpacing.s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hit.sheet.title,
                    style: FluentType.bodyStrong.copyWith(color: Colors.white),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    hit.sheet.category.isNotEmpty
                        ? hit.sheet.category
                        : 'রেফারেন্স টেবিল',
                    style: FluentType.caption.copyWith(
                      color: const Color(0xFFA5B4FC),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(
                Icons.open_in_new,
                color: Color(0xFFA5B4FC),
                size: 18,
              ),
              tooltip: 'অ্যাপে বিস্তারিত দেখুন',
              onPressed: _continueInApp,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        const SizedBox(height: FluentSpacing.m),

        // Formula values / Row card
        Container(
          padding: const EdgeInsets.all(FluentSpacing.m),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: FluentRadius.cardBorder,
            border: Border.all(
              color: const Color(0xFF6366F1).withValues(alpha: 0.4),
              width: FluentStroke.width,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < cells.length; i++) ...[
                if (i < columns.length && columns[i].trim().isNotEmpty)
                  Text(
                    columns[i],
                    style: FluentType.caption.copyWith(
                      color: const Color(0xFFA5B4FC),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                Text(
                  cells[i],
                  style: FluentType.bodyStrong.copyWith(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
                if (i < cells.length - 1)
                  const Divider(color: Color(0xFF334155), height: 12),
              ],
              if (hit.row.note.trim().isNotEmpty) ...[
                const SizedBox(height: FluentSpacing.xs),
                Text(
                  'নোট: ${hit.row.note}',
                  style: FluentType.caption.copyWith(
                    color: const Color(0xFFF59E0B),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: FluentSpacing.m),

        // Detail body (Markdown prose + SVG figure)
        if (hasDetail) ...[
          Row(
            children: [
              const Icon(Icons.auto_stories, color: Color(0xFF10B981), size: 16),
              const SizedBox(width: FluentSpacing.xs),
              Text(
                'ব্যাখ্যা ও উৎপত্তি (Law):',
                style: FluentType.caption.copyWith(
                  color: const Color(0xFF10B981),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: FluentSpacing.s),
          Container(
            constraints: const BoxConstraints(maxHeight: 280),
            child: SingleChildScrollView(
              child: DetailBody(detail: hit.row.detail!),
            ),
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(FluentSpacing.m),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: FluentRadius.controlBorder,
            ),
            child: Column(
              children: [
                const Icon(Icons.info_outline, color: Colors.white38, size: 24),
                const SizedBox(height: FluentSpacing.xs),
                Text(
                  'এই সূত্রে এখনও বিস্তারিত ব্যাখ্যা বা ডায়াগ্রাম যোগ করা হয়নি।',
                  style: FluentType.caption.copyWith(color: Colors.white60),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: FluentSpacing.xs),
                Text(
                  'মূল অ্যাপে রেফারেন্স শীট থেকে এআই দিয়ে ব্যাখ্যা তৈরি করতে পারেন।',
                  style: FluentType.caption.copyWith(
                    color: Colors.white38,
                    fontSize: 11,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
