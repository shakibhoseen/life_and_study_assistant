import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/theme/fluent_tokens.dart';
import '../../../../core/widgets/premium_glass_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/database/database_provider.dart';
import '../../../../core/services/ai/ai_media_limits.dart';
import '../../../../core/services/ai/models/voice_mistake_result.dart';
import '../../../../core/services/ai/voice_mistake_parser_service.dart';
import '../../../../core/services/overlay/live_mcq_bubble_service.dart';
import '../../../../core/services/voice/device_dictation_service.dart';
import '../../../../core/services/voice/voice_recording_service.dart';
import '../../../../core/widgets/ai_progress_pipeline_widget.dart';
import '../../../quiz/presentation/providers/drill_history_provider.dart';
import '../../../spaced_repetition/presentation/providers/spaced_repetition_provider.dart';
import '../../../topics/presentation/providers/topics_provider.dart';

class VoiceMistakeBottomSheet extends ConsumerStatefulWidget {
  const VoiceMistakeBottomSheet({super.key, this.initialText});

  /// Words to start from, carried in from the floating bubble.
  ///
  /// The bubble is a small window over another app; this sheet is the full
  /// screen with the keyboard and the rest of the controls. A note begun out
  /// there is finished in here rather than retyped.
  final String? initialText;

  static Future<void> show(BuildContext context, {String? initialText}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => VoiceMistakeBottomSheet(initialText: initialText),
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

  // Same reasoning as the bubble: the handset transcribes as you speak,
  // which is instant and free, while uploading the audio was measured at up
  // to 159 seconds and fails outright while the model is busy.
  bool _isDictating = false;
  bool _isProcessing = false;
  bool _isProcessingImage = false;

  // Measured at up to 159 seconds on a real recording. A spinner
  // with no number on it is indistinguishable from a hang.
  Timer? _parseTimer;
  int _parseSeconds = 0;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  VoiceMistakeResult? _parsedResult;
  String? _statusMessage;
  bool _isBubbleActive = false;

  @override
  void initState() {
    super.initState();
    final carried = widget.initialText?.trim() ?? '';
    if (carried.isNotEmpty) {
      _textController.text = carried;
      _statusMessage = 'বাবল থেকে আনা হয়েছে — দেখে নিয়ে পাঠান';
    }
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
    // Swiping the sheet away is the ordinary way out of it, and it never
    // passed through the stop button. Both services are singletons, so a
    // session left listening here went on holding the microphone for the
    // rest of the app's life. Not awaited, because dispose cannot be.
    unawaited(DeviceDictationService.instance.stop());
    unawaited(VoiceRecordingService.instance.cancelRecording());
    _textController.dispose();
    super.dispose();
  }

  /// Listens through the phone's own recogniser, writing into the same field
  /// the user can type in.
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
      _statusMessage = 'শুনছি… প্রশ্ন ও সঠিক উত্তর বলুন';
    });

    await DeviceDictationService.instance.listen(
      // Carry on from what is already in the box rather than
      // clearing it.
      seed: _textController.text,
      onResult: (text, isFinal) {
        if (!mounted) return;
        setState(() {
          _textController.text = text;
          // isFinal now means the user pressed stop, not that a pause ended
          // an utterance.
          _statusMessage = isFinal
              ? 'শোনা শেষ — দেখে নিয়ে পাঠান'
              : 'শুনছি… $text';
          if (isFinal) _isDictating = false;
        });
      },
    );
  }

  Future<void> _stopDictation() async {
    await DeviceDictationService.instance.stop();
    if (!mounted) return;

    // stop() banks the utterance in flight, so the service holds the whole
    // sentence even though the field only ever saw the last piece.
    final heard = DeviceDictationService.instance.committedText.trim();
    _textController.text = heard;
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

      // Mono 16 kHz: speech needs no more, and a recording a fraction of
      // the size spends a fraction of the time being uploaded. Gemini bills
      // audio by duration, so this costs nothing in tokens.
      await VoiceRecordingService.instance.startRecording(
        config: VoiceRecordingService.speechConfig,
      );
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
      if (recordedDuration < 1) {
        setState(() {
          _isProcessing = false;
          _parseTimer?.cancel();
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
            _parseTimer?.cancel();
            _statusMessage =
                'কোনো কথা বা প্রশ্ন শনাক্ত করা যায়নি। দয়া করে আবার বলুন।';
          });
        }
      } else {
        setState(() {
          _isProcessing = false;
          _parseTimer?.cancel();
          _statusMessage = 'No audio captured';
        });
      }
    } on VoiceParseException catch (e) {
      // Say what actually went wrong. "Please speak again" for a server
      // fault sends the user round the same loop.
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
  /// The stage and the usual wait turn "frozen" into "working"; the number
  /// moving is what says the app is alive at all.
  String _parseStatus(int seconds) {
    if (seconds < 5) return 'ভয়েস পাঠানো হচ্ছে… ${seconds}s';
    if (seconds < 90) {
      return 'Gemini শুনছে ও প্রশ্ন সাজাচ্ছে… ${seconds}s\n'
          'সাধারণত ৩০–৯০ সেকেন্ড লাগে।';
    }
    return 'এখনো চলছে… ${seconds}s\n'
        'লম্বা রেকর্ডিং হলে দুই মিনিটের বেশি লাগতে পারে।';
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
          _parseTimer?.cancel();
          _statusMessage =
              'কোনো প্রশ্ন শনাক্ত করা যায়নি। আরও সুনির্দিষ্ট করে লিখুন।';
        });
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _parseTimer?.cancel();
        _statusMessage = 'Error: $e';
      });
    }
  }

  Future<void> _pickImageAndParse(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        // As taken; the reduction belongs just before the request, where the
        // user's own setting is read.
        maxWidth: AiMediaLimits.pickerMaxDimension,
        maxHeight: AiMediaLimits.pickerMaxDimension,
      );
      if (picked == null) return;

      setState(() {
        _isProcessing = true;
        _isProcessingImage = true;
        _parseSeconds = 0;
        _statusMessage = 'AI স্ক্রিনশট থেকে প্রশ্ন ও উত্তর বিশ্লেষণ করছে…';
        _parsedResult = null;
      });

      _parseTimer?.cancel();
      _parseTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted || !_isProcessing) {
          t.cancel();
          return;
        }
        setState(() {
          _parseSeconds++;
          _statusMessage =
              'AI স্ক্রিনশট থেকে প্রশ্ন সমাধান করছে… ${_parseSeconds}s';
        });
      });

      final result = await VoiceMistakeParserService.instance
          .parseMistakeFromImage(File(picked.path));

      if (result != null) {
        await _saveAndRefresh(result, sourceTag: '[উৎস: LiveMCQ 📸]');
      } else {
        setState(() {
          _isProcessing = false;
          _parseTimer?.cancel();
          _statusMessage =
              'স্ক্রিনশট থেকে প্রশ্ন শনাক্ত করা যায়নি। স্পষ্ট ছবি দিয়ে আবার চেষ্টা করুন।';
        });
      }
    } on VoiceParseException catch (e) {
      setState(() {
        _isProcessing = false;
        _parseTimer?.cancel();
        _statusMessage = e.userMessage;
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _parseTimer?.cancel();
        _statusMessage = 'ছবি প্রসেসিংয়ে সমস্যা: $e';
      });
    }
  }

  Future<void> _saveAndRefresh(
    VoiceMistakeResult result, {
    String sourceTag = '[উৎস: LiveMCQ 🎙️]',
  }) async {
    final db = ref.read(appDatabaseProvider);
    final saved = await VoiceMistakeParserService.instance
        .saveVoiceMistakeToDatabase(db, result, sourceTag: sourceTag);

    ref.invalidate(wrongQuestionsStreamProvider);
    ref.invalidate(dueSpacedReviewsStreamProvider);
    ref.invalidate(allSpacedReviewsStreamProvider);
    ref.invalidate(weakTopicsStreamProvider);

    if (mounted) {
      setState(() {
        _parsedResult = result;
        _isProcessing = false;
        _parseTimer?.cancel();
        _statusMessage = saved
            ? 'Saved to Mistake Bank & Spaced Repetition ✓'
            : 'এই প্রশ্নটি আগেই সেভ করা আছে ✓';
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
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + FluentSpacing.l,
        left: FluentSpacing.xl,
        right: FluentSpacing.xl,
        top: FluentSpacing.m,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(FluentRadius.large),
        ),
        border: Border(
          top: FluentStroke.side(brightness),
          left: FluentStroke.side(brightness),
          right: FluentStroke.side(brightness),
        ),
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
                  color: scheme.onSurface.withValues(alpha: 0.2),
                  borderRadius: FluentRadius.controlBorder,
                ),
              ),
            ),
            const SizedBox(height: FluentSpacing.m),

            // Header Row
            Row(
              children: [
                PremiumIconBadge(
                  icon: Icons.mic,
                  size: 38,
                  iconSize: 22,
                  color: scheme.primary,
                ),
                const SizedBox(width: FluentSpacing.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'LiveMCQ Voice Mistake Note',
                        style: FluentType.subtitle.copyWith(fontSize: 16),
                      ),
                      Text(
                        'ভুল হওয়া প্রশ্ন মুখে বলুন — জেমিনি ব্যাখ্যাসহ সেভ করবে',
                        style: FluentType.caption.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.65),
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
            Divider(height: FluentSpacing.xxl, color: FluentStroke.divider(brightness)),

            // Launch Floating Bubble CTA Banner
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: FluentSpacing.l,
                vertical: FluentSpacing.m,
              ),
              decoration: BoxDecoration(
                color: _isBubbleActive
                    ? FluentLayer.subtle(
                        const Color(0xFF10B981),
                        brightness,
                      )
                    : scheme.onSurface.withValues(alpha: 0.04),
                borderRadius: FluentRadius.cardBorder,
                border: Border.all(
                  color: _isBubbleActive
                      ? const Color(0xFF10B981).withValues(alpha: 0.5)
                      : FluentStroke.card(brightness),
                  width: FluentStroke.width,
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
                        : scheme.primary,
                    size: 24,
                  ),
                  const SizedBox(width: FluentSpacing.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isBubbleActive
                              ? 'Floating Bubble is Active'
                              : 'LiveMCQ Floating Bubble',
                          style: FluentType.bodyStrong.copyWith(fontSize: 13),
                        ),
                        Text(
                          _isBubbleActive
                              ? 'Open LiveMCQ to speak without leaving the app'
                              : 'Messenger-style bubble over LiveMCQ app',
                          style: FluentType.caption.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.65),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _toggleFloatingBubble,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isBubbleActive
                          ? scheme.error
                          : scheme.primary,
                      foregroundColor: scheme.onPrimary,
                      elevation: 0,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: FluentSpacing.m,
                        vertical: FluentSpacing.s,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: FluentRadius.controlBorder,
                      ),
                    ),
                    child: Text(
                      _isBubbleActive ? 'Stop' : 'Launch',
                      style: FluentType.caption.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: FluentSpacing.xl),

            // Microphone Recording Area
            Center(
              child: Column(
                children: [
                  GestureDetector(
                    // Tap dictates on the device; a long press falls back to
                    // recording and uploading the audio.
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
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        borderRadius: FluentRadius.controlBorder,
                        color: (_isRecording || _isDictating)
                            ? scheme.error
                            : scheme.primary,
                        boxShadow: FluentElevation.card(brightness),
                      ),
                      child: Icon(
                        (_isRecording || _isDictating) ? Icons.stop : Icons.mic,
                        color: Colors.white,
                        size: 40,
                      ),
                    ),
                  ),
                  const SizedBox(height: FluentSpacing.m),
                  Text(
                    _isDictating
                        ? 'শুনছি…'
                        : _isRecording
                        ? 'Recording... ${_formatTimer(_recordSeconds)}'
                        : 'চেপে বলুন — ফোনই লিখে দেবে',
                    style: FluentType.bodyStrong.copyWith(
                      color: _isRecording ? scheme.error : scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: FluentSpacing.xs),
                  Text(
                    _statusMessage ??
                        'মুখে বলুন: "১২ নম্বর প্রশ্নে মানস সরোবর থেকে উৎপন্ন নদী ছিল ব্রহ্মপুত্র"\n'
                            '(দীর্ঘক্ষণ চেপে ধরলে রেকর্ড করে পাঠাবে)',
                    textAlign: TextAlign.center,
                    style: FluentType.caption.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: FluentSpacing.l),

            // LiveMCQ Screenshot / Camera Buttons (for non-copyable text in LiveMCQ)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                    label: const Text('LiveMCQ স্ক্রিনশট'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.primary,
                      side: FluentStroke.side(brightness),
                      backgroundColor: FluentLayer.subtle(
                        scheme.primary,
                        brightness,
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: FluentSpacing.m,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: FluentRadius.controlBorder,
                      ),
                    ),
                    onPressed: _isProcessing
                        ? null
                        : () => _pickImageAndParse(ImageSource.gallery),
                  ),
                ),
                const SizedBox(width: FluentSpacing.s),
                OutlinedButton.icon(
                  icon: const Icon(Icons.camera_alt_outlined, size: 18),
                  label: const Text('ক্যামেরা ছবি'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: scheme.onSurface.withValues(alpha: 0.75),
                    side: FluentStroke.side(brightness),
                    padding: const EdgeInsets.symmetric(
                      horizontal: FluentSpacing.l,
                      vertical: FluentSpacing.m,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: FluentRadius.controlBorder,
                    ),
                  ),
                  onPressed: _isProcessing
                      ? null
                      : () => _pickImageAndParse(ImageSource.camera),
                ),
              ],
            ),
            const SizedBox(height: FluentSpacing.l),

            // Processing state
            if (_isProcessing) ...[
              AiProgressPipelineWidget(
                type: _isProcessingImage ? AiTaskType.image : AiTaskType.audio,
                isCompact: true,
              ),
              const SizedBox(height: FluentSpacing.l),
            ],

            // Successfully Parsed Card
            if (_parsedResult != null) ...[
              Container(
                padding: const EdgeInsets.all(FluentSpacing.m),
                decoration: BoxDecoration(
                  color: FluentLayer.subtle(
                    const Color(0xFF10B981),
                    brightness,
                  ),
                  borderRadius: FluentRadius.cardBorder,
                  border: Border.all(
                    color: const Color(0xFF10B981).withValues(alpha: 0.35),
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
                          size: 18,
                        ),
                        const SizedBox(width: FluentSpacing.s),
                        Expanded(
                          child: Text(
                            'Saved: ${_parsedResult!.subject} • ${_parsedResult!.topic}',
                            style: FluentType.caption.copyWith(
                              color: const Color(0xFF10B981),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: FluentSpacing.s),
                    Text(
                      _parsedResult!.questionText,
                      style: FluentType.bodyStrong.copyWith(fontSize: 13),
                    ),
                    const SizedBox(height: FluentSpacing.s),
                    Text(
                      'সঠিক উত্তর: ${(_parsedResult!.correctIndex >= 0 && _parsedResult!.correctIndex < _parsedResult!.options.length) ? _parsedResult!.options[_parsedResult!.correctIndex] : "অজানা"}',
                      style: FluentType.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFF59E0B),
                      ),
                    ),
                    const SizedBox(height: FluentSpacing.xs),
                    Text(
                      'ব্যাখ্যা: ${_parsedResult!.explanation}',
                      style: FluentType.caption.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: FluentSpacing.l),
            ],

            // Text input alternative
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    style: FluentType.body.copyWith(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Or type mistake topic (e.g. পলাশী যুদ্ধ ১৭৫৭)',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: FluentSpacing.m,
                        vertical: FluentSpacing.m,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: FluentRadius.controlBorder,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: FluentSpacing.s),
                IconButton.filled(
                  onPressed: _parseTextMistake,
                  style: IconButton.styleFrom(
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
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
