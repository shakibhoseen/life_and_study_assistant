import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/fluent_tokens.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../core/services/ai/gemini_ai_service.dart';
import '../../../../core/services/ai/models/quiz_question.dart';
import '../../../../core/services/ai/quiz_batch_correction_service.dart';
import '../../domain/external_audit_brief.dart';
import '../../domain/spoken_edit.dart';
import '../../../../core/services/voice/voice_recording_service.dart';
import '../../../live_mcq/presentation/providers/exam_schedule_provider.dart';
import '../providers/drill_history_provider.dart';
import '../../../../core/widgets/ai_progress_pipeline_widget.dart';
import '../../../../core/services/ai/ai_cancellation.dart';

/// Reusable modal sheet that allows students to paste external AI (ChatGPT, Claude, etc.)
/// critiques or speak voice instructions to batch-fix or delete faulty questions with a 1-tap confirmation preview.
/// The two status colours this sheet means something by — a correction it is
/// confident in and one that needs a look — kept here so the same green and
/// amber are used throughout and each reads on both themes.
Color _okColour(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF4ADE80)
    : const Color(0xFF15803D);

Color _warnColour(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFFFCD34D)
    : const Color(0xFFB45309);

Color _badColour(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFFF87171)
    : const Color(0xFFB91C1C);

class QuizBatchCorrectionSheet {
  static Future<List<QuizQuestion>?> show(
    BuildContext context, {
    required WidgetRef ref,
    required List<QuizQuestion> questions,
    int? examId,
    List<DrillQuestion>? mistakeQuestions,
    String? topic,
    String? subject,
    VoidCallback? onApplied,
  }) {
    final textController = TextEditingController();
    bool isAnalyzing = false;
    AiCancellation? analysisCancellation;
    bool isRecordingVoice = false;
    int recordingSeconds = 0;
    Timer? recordingTimer;
    List<QuestionCorrectionItem>? parsedCorrections;
    String? statusMessage;

    return showModalBottomSheet<List<QuizQuestion>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
            final selectedCount =
                parsedCorrections?.where((c) => c.isSelected).length ?? 0;

            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.85,
              ),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(FluentRadius.large),
                ),
                border: Border(
                  top: BorderSide(
                    color: FluentStroke.card(Theme.of(ctx).brightness),
                    width: FluentStroke.width,
                  ),
                ),
                boxShadow: FluentElevation.flyout(Theme.of(ctx).brightness),
              ),
              padding: EdgeInsets.only(
                left: FluentSpacing.l,
                right: FluentSpacing.l,
                top: FluentSpacing.m,
                bottom: bottomInset + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: FluentSpacing.m),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.onSurface
                            .withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(FluentSpacing.s),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary
                              .withValues(alpha: 0.15),
                          borderRadius: FluentRadius.cardBorder,
                        ),
                        child: Icon(
                          Icons.auto_fix_high_rounded,
                          color: Theme.of(context).colorScheme.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: FluentSpacing.m),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'AI অ্যানালাইসিস দিয়ে অটো-ফিক্স',
                              style: FluentType.bodyStrong,
                            ),
                            Text(
                              examId != null
                                  ? 'E-$examId পরীক্ষার প্রশ্নসমূহ সংশোধন ও আপডেট'
                                  : (topic != null && topic.isNotEmpty
                                        ? '$topic · এক্সটার্নাল AI দিয়ে এক ক্লিকে সমাধান'
                                        : 'এক্সটার্নাল AI-এর বিশ্লেষণ দিয়ে এক ক্লিকে সমাধান'),
                              style: FluentType.caption.copyWith(
                                color: Theme.of(context).colorScheme.onSurface
                                    .withValues(alpha: 0.65),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.pop(sheetCtx),
                      ),
                    ],
                  ),
                  const SizedBox(height: FluentSpacing.m),

                  // Content: either Input Mode or Review Mode
                  if (parsedCorrections == null) ...[
                    // Input Mode
                    Container(
                      padding: const EdgeInsets.all(FluentSpacing.m),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.onSurface
                            .withValues(alpha: 0.06),
                        borderRadius: FluentRadius.cardBorder,
                        border: Border.all(
                          color: FluentStroke.card(
                            Theme.of(context).brightness,
                          ),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 16,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: FluentSpacing.s),
                          Expanded(
                            child: Text(
                              'ChatGPT, Claude বা অন্য যেকোনো AI থেকে পাওয়া উত্তরের পর্যালোচনা বা ভুলের টেক্সট এখানে পেস্ট করুন। সিস্টেম স্বয়ংক্রিয়ভাবে প্রশ্নের সঠিক উত্তর পরিবর্তন বা ত্রুটিপূর্ণ প্রশ্ন বাদ দেওয়ার প্রস্তাবনা তৈরি করবে।',
                              style: FluentType.caption.copyWith(
                                color: Theme.of(context).colorScheme.onSurface
                                    .withValues(alpha: 0.65),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: FluentSpacing.m),

                    // Voice Recording & Quick Paste Bar
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isRecordingVoice
                                  ? _badColour(context)
                                  : Theme.of(context).colorScheme.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                vertical: FluentSpacing.m,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: FluentRadius.controlBorder,
                              ),
                              elevation: 0,
                            ),
                            icon: Icon(
                              isRecordingVoice
                                  ? Icons.stop_circle_rounded
                                  : Icons.mic_rounded,
                              size: 18,
                            ),
                            label: Text(
                              isRecordingVoice
                                  ? 'রেকর্ড থামান (${(recordingSeconds ~/ 60).toString().padLeft(2, '0')}:${(recordingSeconds % 60).toString().padLeft(2, '0')})'
                                  : '🎙️ মুখে বলুন (ভয়েস ফিক্স)',
                              style: FluentType.caption.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            onPressed: isAnalyzing
                                ? null
                                : () async {
                                    if (isRecordingVoice) {
                                      recordingTimer?.cancel();
                                      final seconds = recordingSeconds;
                                      setSheetState(() {
                                        isRecordingVoice = false;
                                        isAnalyzing = true;
                                        statusMessage = 'AI আপনার কণ্ঠ বিশ্লেষণ করছে... 🎙️';
                                      });
                                      try {
                                        final audioFile =
                                            await VoiceRecordingService.instance
                                                .stopRecording();
                                        if (seconds < 1 || audioFile == null) {
                                          setSheetState(() {
                                            isAnalyzing = false;
                                            statusMessage = 'রেকর্ডিং খুব সংক্ষিপ্ত ছিল। স্পষ্ট করে বলে থামুন।';
                                          });
                                          return;
                                        }

                                        final transcribed =
                                            await GeminiAiService.instance
                                                .transcribeVoice(audioFile);
                                        if (transcribed != null &&
                                            transcribed.trim().isNotEmpty) {
                                          textController.text = transcribed
                                              .trim();
                                          // Auto analyze transcribed text
                                          final items =
                                              await QuizBatchCorrectionService
                                                  .instance
                                                  .parseCorrections(
                                                    questions: questions,
                                                    externalAnalysis:
                                                        transcribed.trim(),
                                                    questionIds:
                                                        mistakeQuestions
                                                            ?.map((q) => q.id)
                                                            .toList(),
                                                  );
                                          if (items.isNotEmpty) {
                                            setSheetState(() {
                                              isAnalyzing = false;
                                              statusMessage = null;
                                              parsedCorrections = items;
                                            });
                                            return;
                                          } else {
                                            setSheetState(() {
                                              isAnalyzing = false;
                                              statusMessage =
                                                  'ভয়েস টেক্সট নেওয়া হয়েছে: "$transcribed"। নিচের বাটনে সংশোধন বিশ্লেষণ করুন।';
                                            });
                                            return;
                                          }
                                        } else {
                                          setSheetState(() {
                                            isAnalyzing = false;
                                            statusMessage = 'কোনো স্পষ্ট কণ্ঠস্বর বোঝা যায়নি। পুনরায় চেষ্টা করুন বা টাইপ করুন।';
                                          });
                                        }
                                      } catch (e) {
                                        setSheetState(() {
                                          isAnalyzing = false;
                                          statusMessage =
                                              'ভয়েস প্রসেসিং ত্রুটি: $e';
                                        });
                                      }
                                    } else {
                                      try {
                                        await VoiceRecordingService.instance
                                            .startRecording();
                                        recordingSeconds = 0;
                                        recordingTimer?.cancel();
                                        recordingTimer = Timer.periodic(
                                          const Duration(seconds: 1),
                                          (_) {
                                            setSheetState(() {
                                              recordingSeconds++;
                                            });
                                          },
                                        );
                                        setSheetState(() {
                                          isRecordingVoice = true;
                                          statusMessage = 'কথা বলুন: "৩ নম্বর প্রশ্নের উত্তর গ হবে আর ৫ নম্বরটা বাদ দিন..."';
                                        });
                                      } catch (e) {
                                        setSheetState(() {
                                          statusMessage =
                                              'মাইক্রোফোন চালু করা যায়নি: $e';
                                        });
                                      }
                                    }
                                  },
                          ),
                        ),
                        const SizedBox(width: FluentSpacing.s),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.65),
                            side: BorderSide(
                              color: Theme.of(context).colorScheme.onSurface
                                  .withValues(alpha: 0.65),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: FluentSpacing.m,
                              vertical: FluentSpacing.m,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: FluentRadius.controlBorder,
                            ),
                          ),
                          icon: const Icon(
                            Icons.content_paste_rounded,
                            size: 16,
                          ),
                          label: Text(
                            'পেস্ট',
                            style: FluentType.caption.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onPressed: isAnalyzing
                              ? null
                              : () async {
                                  final data = await Clipboard.getData(
                                    Clipboard.kTextPlain,
                                  );
                                  if (data?.text != null &&
                                      data!.text!.trim().isNotEmpty) {
                                    textController.text = data.text!.trim();
                                  }
                                },
                        ),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: FluentSpacing.s,
                            ),
                          ),
                          icon: const Icon(Icons.copy_all_rounded, size: 15),
                          label: const Text(
                            'প্রম্পট',
                            style: FluentType.caption,
                          ),
                          onPressed: () {
                            // Plain Bengali still works; this shape is simply
                            // the one that costs nothing to read.
                            Clipboard.setData(
                              ClipboardData(
                                text: externalCorrectionPromptTemplate(
                                  questions.length,
                                ),
                              ),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'প্রম্পট কপি হয়েছে — প্রশ্নগুলোর সাথে বাইরের AI-তে দিন',
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: FluentSpacing.s),

                    // The grammar, where it is used. A reader that understands
                    // seven phrases and says so is more use than one that
                    // understands nine and keeps them to itself.
                    Theme(
                      data: Theme.of(context)
                          .copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: const EdgeInsets.only(
                          bottom: FluentSpacing.s,
                        ),
                        leading: const Icon(Icons.mic_none, size: 18),
                        title: Text(
                          'মুখে বা টাইপ করে কীভাবে বলবেন',
                          style: FluentType.caption.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: FluentSpacing.s,
                            ),
                            child: Text(
                              voicePhrasingHelp,
                              style: FluentType.caption.copyWith(
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                          for (final (phrase, effect) in voiceFixPhrasebook)
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: FluentSpacing.s,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('• ', style: FluentType.caption),
                                  Expanded(
                                    child: RichText(
                                      text: TextSpan(
                                        style: DefaultTextStyle.of(context)
                                            .style
                                            .copyWith(fontSize: 11.5),
                                        children: [
                                          TextSpan(
                                            text: '"$phrase"',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          TextSpan(text: ' — $effect'),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: FluentSpacing.xxs),
                          Text(
                            voiceTargetHelp,
                            style: FluentType.caption.copyWith(
                              color: Theme.of(context).colorScheme.onSurface
                                  .withValues(alpha: 0.65),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: FluentSpacing.s),

                    // Tap a tag, then say or type only the words. Free speech
                    // is read too, but a tag removes the guessing: it is the
                    // difference between the app hoping it understood and
                    // knowing it did.
                    Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      children: [
                        for (final (label, prefix) in spokenEditChips)
                          ActionChip(
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            labelStyle: FluentType.caption,
                            label: Text(label),
                            onPressed: () {
                              final existing = textController.text.trimRight();
                              final lead = existing.isEmpty
                                  ? ''
                                  : '$existing\n';
                              textController.text = '$lead$prefix';
                              textController.selection =
                                  TextSelection.fromPosition(
                                    TextPosition(
                                      offset: textController.text.length,
                                    ),
                                  );
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: FluentSpacing.s),

                    TextField(
                      controller: textController,
                      maxLines: 4,
                      style: FluentType.caption,
                      decoration: InputDecoration(
                        hintText:
                            'AI-এর বিশ্লেষণ এখানে পেস্ট করুন — যেভাবে খুশি লিখুন।\n'
                            'এক লাইনেও চলবে: "৪ নম্বরটা ভুল, প্রশ্নটা ঠিক করো"\n'
                            'উপরের প্রম্পটে চাইলে JSON আসে — সেটা ফোনেই পড়া হয়, ফ্রি।',
                        hintStyle: FluentType.caption.copyWith(
                          color: Theme.of(context).colorScheme.onSurface
                              .withValues(alpha: 0.65),
                        ),
                        contentPadding: const EdgeInsets.all(FluentSpacing.m),
                        border: OutlineInputBorder(
                          borderRadius: FluentRadius.cardBorder,
                        ),
                        suffixIcon: IconButton(
                          tooltip: 'ক্লিপবোর্ড থেকে পেস্ট করুন',
                          icon: const Icon(
                            Icons.content_paste_rounded,
                            size: 20,
                          ),
                          onPressed: () async {
                            final data = await Clipboard.getData(
                              Clipboard.kTextPlain,
                            );
                            if (data?.text != null &&
                                data!.text!.trim().isNotEmpty) {
                              textController.text = data.text!.trim();
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: FluentSpacing.m),

                    if (statusMessage != null) ...[
                      Text(
                        statusMessage!,
                        style: FluentType.caption.copyWith(
                          color: _badColour(context),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: FluentSpacing.s),
                    ],

                    // The button's own spinner said only "wait". This
                    // counts the seconds so a slow call is visibly working
                    // rather than hung.
                    if (isAnalyzing) ...[
                      AiProgressPipelineWidget(
                        type: AiTaskType.text,
                        isCompact: true,
                        // Nothing is cut short to save tokens. Stopping is
                        // the user's call, so it needs to be reachable.
                        onCancel: () => analysisCancellation?.cancel(),
                      ),
                      const SizedBox(height: FluentSpacing.m),
                    ],

                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          vertical: FluentSpacing.m,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: FluentRadius.controlBorder,
                        ),
                      ),
                      icon: isAnalyzing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.manage_search_rounded, size: 18),
                      label: Text(
                        isAnalyzing
                            ? 'AI বিশ্লেষণ থেকে সংশোধন খোঁজা হচ্ছে...'
                            : 'সংশোধন বিশ্লেষণ করুন',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: isAnalyzing
                          ? null
                          : () async {
                              final text = textController.text.trim();
                              if (text.isEmpty) {
                                setSheetState(() {
                                  statusMessage =
                                      'অনুগ্রহ করে বিশ্লেষণ টেক্সট পেস্ট করুন';
                                });
                                return;
                              }
                              final cancellation = AiCancellation();
                              setSheetState(() {
                                isAnalyzing = true;
                                analysisCancellation = cancellation;
                                statusMessage = null;
                              });

                              try {
                                final items = await QuizBatchCorrectionService
                                    .instance
                                    .parseCorrections(
                                      questions: questions,
                                      externalAnalysis: text,
                                      // The notebook copies questions out with
                                      // their ids printed, so a reply keyed on
                                      // those reads back without a model call.
                                      questionIds: mistakeQuestions
                                          ?.map((q) => q.id)
                                          .toList(),
                                      cancellation: cancellation,
                                    );
                                if (items.isEmpty) {
                                  setSheetState(() {
                                    isAnalyzing = false;
                                    statusMessage =
                                        'এই লেখায় এমন কিছু পাওয়া যায়নি যা '
                                        'কোনো প্রশ্নে বসানো যায়।\n\n'
                                        'সাধারণ কারণ: উত্তরটা শুধু বর্ণনা, '
                                        'JSON নয়; অথবা প্রশ্ন নম্বর এই '
                                        'তালিকার সাথে মেলে না।\n\n'
                                        'কপি বাটনে যে নির্দেশনা যায়, সেটাসহ '
                                        'প্রশ্নগুলো পেস্ট করলে উত্তরটা এখানে '
                                        'হুবহু বসবে।';
                                  });
                                } else {
                                  final service =
                                      QuizBatchCorrectionService.instance;
                                  final wasFree = service.lastParseWasFree;
                                  final wasCut = service.lastReplyWasCut;
                                  setSheetState(() {
                                    isAnalyzing = false;
                                    parsedCorrections = items;
                                    // A cut reply means these are some of the
                                    // corrections, not all of them.
                                    statusMessage = wasCut
                                        ? '${items.length}টি সংশোধন পাওয়া গেছে, কিন্তু লেখা শেষ হয়নি — '
                                              'কম প্রশ্ন নিয়ে আবার চালান'
                                        : wasFree
                                        ? '${items.length}টি সংশোধন — ফোনেই পড়া হয়েছে, টোকেন খরচ হয়নি'
                                        : '${items.length}টি সংশোধন — AI দিয়ে পড়তে হয়েছে';
                                  });
                                }
                              } catch (e) {
                                setSheetState(() {
                                  isAnalyzing = false;
                                  statusMessage =
                                      'বিশ্লেষণ করার সময় সমস্যা হয়েছে: $e';
                                });
                              }
                            },
                    ),
                  ] else ...[
                    // Preview & Confirmation Mode
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: FluentSpacing.m,
                        vertical: FluentSpacing.s,
                      ),
                      decoration: BoxDecoration(
                        color: FluentLayer.subtle(
                          Theme.of(context).colorScheme.primary,
                          Theme.of(context).brightness,
                        ),
                        borderRadius: FluentRadius.cardBorder,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: 16,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: FluentSpacing.s),
                          Expanded(
                            child: Text(
                              '${parsedCorrections!.length}টি সংশোধনের প্রস্তাবনা পাওয়া গেছে ($selectedCountটি নির্বাচিত)',
                              style: FluentType.caption.copyWith(
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                            ),
                            onPressed: () {
                              final allSelected = parsedCorrections!.every(
                                (c) => c.isSelected,
                              );
                              setSheetState(() {
                                for (final c in parsedCorrections!) {
                                  c.isSelected = !allSelected;
                                }
                              });
                            },
                            child: Text(
                              parsedCorrections!.every((c) => c.isSelected)
                                  ? 'সব আনচেক'
                                  : 'সব নির্বাচন',
                              style: FluentType.caption,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: FluentSpacing.s),

                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: parsedCorrections!.length,
                        itemBuilder: (ctx, idx) {
                          final item = parsedCorrections![idx];
                          final q =
                              (item.questionIndex >= 0 &&
                                  item.questionIndex < questions.length)
                              ? questions[item.questionIndex]
                              : null;

                          return Container(
                            margin: const EdgeInsets.only(
                              bottom: FluentSpacing.s,
                            ),
                            padding: const EdgeInsets.all(FluentSpacing.m),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: FluentRadius.cardBorder,
                              border: Border.all(
                                color: item.isSelected
                                    ? (item.isDelete
                                          ? _badColour(context)
                                          : Theme.of(context)
                                                .colorScheme
                                                .primary)
                                    : (Theme.of(context).colorScheme.onSurface
                                          .withValues(alpha: 0.65)),
                                width: item.isSelected ? 1.5 : 1.0,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Checkbox(
                                  value: item.isSelected,
                                  activeColor: item.isDelete
                                      ? _badColour(context)
                                      : Theme.of(context).colorScheme.primary,
                                  onChanged: (val) {
                                    setSheetState(() {
                                      item.isSelected = val ?? false;
                                    });
                                  },
                                ),
                                const SizedBox(width: FluentSpacing.xs),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'প্রশ্ন ${item.questionIndex + 1}: ${q?.questionText ?? item.questionSnippet}',
                                        style: FluentType.caption.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: FluentSpacing.xs),
                                      if (item.isDelete) ...[
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: FluentSpacing.s,
                                            vertical: FluentSpacing.xxs,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _badColour(context)
                                                .withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            '🗑️ এই প্রশ্নটি বাতিল/ডিলিট করা হবে',
                                            style: FluentType.caption.copyWith(
                                              color: _badColour(context),
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ] else ...[
                                        Builder(
                                          builder: (_) {
                                            final targetOptions =
                                                item.newOptions ?? q?.options;
                                            final proposedText =
                                                item
                                                    .proposedOptionText
                                                    .isNotEmpty
                                                ? item.proposedOptionText
                                                : (item.proposedCorrectIndex !=
                                                              null &&
                                                          item.proposedCorrectIndex! >=
                                                              0 &&
                                                          targetOptions !=
                                                              null &&
                                                          item.proposedCorrectIndex! <
                                                              targetOptions
                                                                  .length
                                                      ? targetOptions[item
                                                            .proposedCorrectIndex!]
                                                      : '');

                                            if (proposedText.isNotEmpty) {
                                              return Row(
                                                children: [
                                                  if (item
                                                      .oldOptionText
                                                      .isNotEmpty) ...[
                                                    Flexible(
                                                      child: Text(
                                                        'পূর্বের: ${item.oldOptionText}',
                                                        style: FluentType
                                                            .caption
                                                            .copyWith(
                                                              decoration:
                                                                  TextDecoration
                                                                      .lineThrough,
                                                              color:
                                                                  Theme.of(
                                                                        context,
                                                                      )
                                                                      .colorScheme
                                                                      .onSurface
                                                                      .withValues(
                                                                        alpha:
                                                                            0.65,
                                                                      ),
                                                            ),
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                    const SizedBox(
                                                      width: FluentSpacing.s,
                                                    ),
                                                    Icon(
                                                      Icons.arrow_forward,
                                                      size: 12,
                                                      color: _okColour(context),
                                                    ),
                                                    const SizedBox(
                                                      width: FluentSpacing.s,
                                                    ),
                                                  ],
                                                  Flexible(
                                                    child: Text(
                                                      'নতুন উত্তর: $proposedText',
                                                      style: FluentType.caption
                                                          .copyWith(
                                                            color: _okColour(
                                                              context,
                                                            ),
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              );
                                            } else if (item.newQuestionText !=
                                                    null ||
                                                item.newOptions != null) {
                                              return Row(
                                                children: [
                                                  Icon(
                                                    Icons.edit_note_rounded,
                                                    size: 14,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .primary,
                                                  ),
                                                  SizedBox(
                                                    width: FluentSpacing.xs,
                                                  ),
                                                  Flexible(
                                                    child: Text(
                                                      'প্রশ্ন বা অপশন পরিমার্জন',
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: FluentType.caption
                                                          .copyWith(
                                                            color:
                                                                Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
                                                                    .primary,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                    ),
                                                  ),
                                                ],
                                              );
                                            } else if (item.newExplanation !=
                                                null) {
                                              return Row(
                                                children: [
                                                  Icon(
                                                    Icons.lightbulb_outline,
                                                    size: 14,
                                                    color: _warnColour(context),
                                                  ),
                                                  SizedBox(
                                                    width: FluentSpacing.xs,
                                                  ),
                                                  Flexible(
                                                    child: Text(
                                                      'ব্যাখ্যা পরিমার্জন',
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: FluentType.caption
                                                          .copyWith(
                                                            color: _warnColour(
                                                              context,
                                                            ),
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                    ),
                                                  ),
                                                ],
                                              );
                                            }
                                            return const SizedBox.shrink();
                                          },
                                        ),
                                      ],
                                      if (item.reason.isNotEmpty) ...[
                                        const SizedBox(
                                          height: FluentSpacing.xs,
                                        ),
                                        Text(
                                          '💡 ${item.reason}',
                                          style: FluentType.caption.copyWith(
                                            fontStyle: FontStyle.italic,
                                            color: _warnColour(context),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: FluentSpacing.m),

                    Row(
                      children: [
                        OutlinedButton(
                          onPressed: () {
                            setSheetState(() {
                              parsedCorrections = null;
                            });
                          },
                          child: const Text('পুনরায় পেস্ট'),
                        ),
                        const SizedBox(width: FluentSpacing.s),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _okColour(context),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                vertical: FluentSpacing.m,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: FluentRadius.controlBorder,
                              ),
                            ),
                            icon: const Icon(Icons.check, size: 18),
                            label: Text(
                              'সংশোধন নিশ্চিত করুন ($selectedCount)',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            onPressed: selectedCount == 0
                                ? null
                                : () async {
                                    final selectedItems = parsedCorrections!
                                        .where((c) => c.isSelected)
                                        .toList();

                                    // Apply to questions list
                                    final updatedList =
                                        QuizBatchCorrectionService.instance
                                            .applyCorrectionsToQuestions(
                                              questions: questions,
                                              corrections: selectedItems,
                                            );

                                    // Apply to DB if examId is present
                                    if (examId != null) {
                                      final db = ref.read(appDatabaseProvider);
                                      await QuizBatchCorrectionService.instance
                                          .applyCorrectionsToExam(
                                            db,
                                            examId: examId,
                                            corrections: selectedItems,
                                          );
                                      ref.invalidate(
                                        upcomingExamsStreamProvider,
                                      );
                                      ref.invalidate(allExamsStreamProvider);
                                      ref.invalidate(
                                        filteredExamsStreamProvider,
                                      );
                                    }

                                    // Apply to Mistake Notebook if mistakeQuestions is present
                                    if (mistakeQuestions != null &&
                                        mistakeQuestions.isNotEmpty) {
                                      final db = ref.read(appDatabaseProvider);
                                      await QuizBatchCorrectionService.instance
                                          .applyCorrectionsToMistakeQuestions(
                                            db,
                                            drillQuestions: mistakeQuestions,
                                            corrections: selectedItems,
                                          );
                                      ref.invalidate(allMistakesStreamProvider);
                                      ref.invalidate(
                                        drillHistoryNotifierProvider,
                                      );
                                    }

                                    onApplied?.call();

                                    if (sheetCtx.mounted) {
                                      Navigator.pop(sheetCtx, updatedList);
                                    }

                                    if (!context.mounted) return;

                                    final targetDesc = examId != null
                                        ? " এবং রুটিনে সেভ হয়েছে!"
                                        : (mistakeQuestions != null &&
                                                  mistakeQuestions.isNotEmpty
                                              ? " এবং মিস্টেক বুকে সেভ হয়েছে!"
                                              : "!");

                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        backgroundColor: const Color(
                                          0xFF10B981,
                                        ),
                                        content: Row(
                                          children: [
                                            const Icon(
                                              Icons.check_circle,
                                              color: Colors.white,
                                              size: 18,
                                            ),
                                            const SizedBox(
                                              width: FluentSpacing.s,
                                            ),
                                            Expanded(
                                              child: Text(
                                                '${selectedItems.length}টি প্রশ্ন সফলভাবে সংশোধন করা হয়েছে$targetDesc',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      recordingTimer?.cancel();
      VoiceRecordingService.instance.cancelRecording();
      textController.dispose();
    });
  }
}
