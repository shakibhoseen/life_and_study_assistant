import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../core/services/ai/gemini_ai_service.dart';
import '../../../../core/services/ai/models/quiz_question.dart';
import '../../../../core/services/ai/quiz_batch_correction_service.dart';
import '../../../../core/services/voice/voice_recording_service.dart';
import '../../../live_mcq/presentation/providers/exam_schedule_provider.dart';
import '../providers/drill_history_provider.dart';

/// Reusable modal sheet that allows students to paste external AI (ChatGPT, Claude, etc.)
/// critiques or speak voice instructions to batch-fix or delete faulty questions with a 1-tap confirmation preview.
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
            final isDark = Theme.of(ctx).brightness == Brightness.dark;
            final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
            final selectedCount =
                parsedCorrections?.where((c) => c.isSelected).length ?? 0;

            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.85,
              ),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
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
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.grey.shade700
                            : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.auto_fix_high_rounded,
                          color: Color(0xFF6366F1),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'AI অ্যানালাইসিস দিয়ে অটো-ফিক্স',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              examId != null
                                  ? 'E-$examId পরীক্ষার প্রশ্নসমূহ সংশোধন ও আপডেট'
                                  : (topic != null && topic.isNotEmpty
                                        ? '$topic · এক্সটার্নাল AI দিয়ে এক ক্লিকে সমাধান'
                                        : 'এক্সটার্নাল AI-এর বিশ্লেষণ দিয়ে এক ক্লিকে সমাধান'),
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? Colors.grey.shade400
                                    : Colors.grey.shade600,
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
                  const SizedBox(height: 12),

                  // Content: either Input Mode or Review Mode
                  if (parsedCorrections == null) ...[
                    // Input Mode
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF0F172A)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDark
                              ? Colors.white12
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.info_outline,
                            size: 16,
                            color: Color(0xFF6366F1),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'ChatGPT, Claude বা অন্য যেকোনো AI থেকে পাওয়া উত্তরের পর্যালোচনা বা ভুলের টেক্সট এখানে পেস্ট করুন। সিস্টেম স্বয়ংক্রিয়ভাবে প্রশ্নের সঠিক উত্তর পরিবর্তন বা ত্রুটিপূর্ণ প্রশ্ন বাদ দেওয়ার প্রস্তাবনা তৈরি করবে।',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: isDark
                                    ? Colors.grey.shade300
                                    : const Color(0xFF334155),
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Voice Recording & Quick Paste Bar
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isRecordingVoice
                                  ? Colors.red.shade600
                                  : const Color(0xFF6366F1),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
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
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
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
                                        statusMessage =
                                            'AI আপনার কণ্ঠ বিশ্লেষণ করছে... 🎙️';
                                      });
                                      try {
                                        final audioFile =
                                            await VoiceRecordingService
                                                .instance
                                                .stopRecording();
                                        if (seconds < 1 || audioFile == null) {
                                          setSheetState(() {
                                            isAnalyzing = false;
                                            statusMessage =
                                                'রেকর্ডিং খুব সংক্ষিপ্ত ছিল। স্পষ্ট করে বলে থামুন।';
                                          });
                                          return;
                                        }

                                        final transcribed =
                                            await GeminiAiService.instance
                                                .transcribeVoice(audioFile);
                                        if (transcribed != null &&
                                            transcribed.trim().isNotEmpty) {
                                          textController.text =
                                              transcribed.trim();
                                          // Auto analyze transcribed text
                                          final items =
                                              await QuizBatchCorrectionService
                                                  .instance
                                                  .parseCorrections(
                                                    questions: questions,
                                                    externalAnalysis:
                                                        transcribed.trim(),
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
                                            statusMessage =
                                                'কোনো স্পষ্ট কণ্ঠস্বর বোঝা যায়নি। পুনরায় চেষ্টা করুন বা টাইপ করুন।';
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
                                          statusMessage =
                                              'কথা বলুন: "৩ নম্বর প্রশ্নের উত্তর গ হবে আর ৫ নম্বরটা বাদ দিন..."';
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
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: isDark
                                ? Colors.grey.shade300
                                : const Color(0xFF334155),
                            side: BorderSide(
                              color: isDark
                                  ? Colors.white24
                                  : Colors.grey.shade300,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(Icons.content_paste_rounded, size: 16),
                          label: const Text(
                            'পেস্ট',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
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
                      ],
                    ),
                    const SizedBox(height: 10),

                    TextField(
                      controller: textController,
                      maxLines: 4,
                      style: const TextStyle(fontSize: 12.5),
                      decoration: InputDecoration(
                        hintText:
                            'বা এখানে সরাসরি AI-এর বিশ্লেষণ পেস্ট করুন...\nযেমন:\n"প্রশ্ন ৩ এর উত্তর খ হবে, ক নয়..."\n"প্রশ্ন ৫ তথ্যগতভাবে ভুল, বাদ দেওয়া উচিত..."',
                        hintStyle: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Colors.grey.shade500
                              : Colors.grey.shade400,
                        ),
                        contentPadding: const EdgeInsets.all(12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
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
                    const SizedBox(height: 12),

                    if (statusMessage != null) ...[
                      Text(
                        statusMessage!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                    ],

                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
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
                              setSheetState(() {
                                isAnalyzing = true;
                                statusMessage = null;
                              });

                              try {
                                final items = await QuizBatchCorrectionService
                                    .instance
                                    .parseCorrections(
                                      questions: questions,
                                      externalAnalysis: text,
                                    );
                                if (items.isEmpty) {
                                  setSheetState(() {
                                    isAnalyzing = false;
                                    statusMessage = 'কোনো সুনির্দিষ্ট প্রশ্ন সংশোধন চিহ্নিত করা যায়নি। অনুগ্রহ করে বিশ্লেষণ টেক্সটটি যাচাই করুন।';
                                  });
                                } else {
                                  setSheetState(() {
                                    isAnalyzing = false;
                                    parsedCorrections = items;
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
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1E1B4B)
                            : const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle_outline,
                            size: 16,
                            color: Color(0xFF6366F1),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${parsedCorrections!.length}টি সংশোধনের প্রস্তাবনা পাওয়া গেছে ($selectedCountটি নির্বাচিত)',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? const Color(0xFFA5B4FC)
                                    : const Color(0xFF3730A3),
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
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

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
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF0F172A)
                                  : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: item.isSelected
                                    ? (item.isDelete
                                          ? Colors.red.shade400
                                          : const Color(0xFF6366F1))
                                    : (isDark
                                          ? Colors.white12
                                          : Colors.grey.shade300),
                                width: item.isSelected ? 1.5 : 1.0,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Checkbox(
                                  value: item.isSelected,
                                  activeColor: item.isDelete
                                      ? Colors.red
                                      : const Color(0xFF6366F1),
                                  onChanged: (val) {
                                    setSheetState(() {
                                      item.isSelected = val ?? false;
                                    });
                                  },
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'প্রশ্ন ${item.questionIndex + 1}: ${q?.questionText ?? item.questionSnippet}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      if (item.isDelete) ...[
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.red.withValues(
                                              alpha: 0.15,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: const Text(
                                            '🗑️ এই প্রশ্নটি বাতিল/ডিলিট করা হবে',
                                            style: TextStyle(
                                              color: Colors.red,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ] else ...[
                                        Row(
                                          children: [
                                            if (item
                                                .oldOptionText
                                                .isNotEmpty) ...[
                                              Flexible(
                                                child: Text(
                                                  'পূর্বের: ${item.oldOptionText}',
                                                  style: TextStyle(
                                                    decoration: TextDecoration
                                                        .lineThrough,
                                                    color: isDark
                                                        ? Colors.grey.shade400
                                                        : Colors.grey.shade600,
                                                    fontSize: 11,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              const Icon(
                                                Icons.arrow_forward,
                                                size: 12,
                                                color: Colors.green,
                                              ),
                                              const SizedBox(width: 6),
                                            ],
                                            Flexible(
                                              child: Text(
                                                'নতুন উত্তর: ${item.proposedOptionText.isNotEmpty ? item.proposedOptionText : (item.proposedCorrectIndex != null && q != null && item.proposedCorrectIndex! < q.options.length ? q.options[item.proposedCorrectIndex!] : "")}',
                                                style: const TextStyle(
                                                  color: Colors.green,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 11.5,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                      if (item.reason.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          '💡 ${item.reason}',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontStyle: FontStyle.italic,
                                            color: isDark
                                                ? Colors.amber.shade200
                                                : Colors.brown.shade800,
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
                    const SizedBox(height: 10),

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
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
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
                                            const SizedBox(width: 8),
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
    });
  }
}
