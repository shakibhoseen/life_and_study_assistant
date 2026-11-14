import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/services/ai/ai_media_limits.dart';
import '../../../../core/theme/fluent_tokens.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../core/database/tables/weak_topics_table.dart';
import '../../../../core/services/ai/models/study_sheet_result.dart';
import '../../../../core/services/ai/study_sheet_ocr_service.dart';
import '../../../../core/widgets/ai_progress_pipeline_widget.dart';
import '../../../spaced_repetition/presentation/providers/spaced_repetition_provider.dart';
import '../../../topics/presentation/providers/topics_provider.dart';
import 'quiz_drill_modal.dart';
import '../../../../core/services/media/photo_capture_service.dart';
import '../../../../core/widgets/ai_key_missing_notice.dart';

/// The one status colour this sheet means something by, with a light-mode and
/// a dark-mode value that reads on either surface.
Color _badColour(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFFF87171)
    : const Color(0xFFB91C1C);

class StudySheetCameraModal extends ConsumerStatefulWidget {
  const StudySheetCameraModal({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const StudySheetCameraModal(),
    );
  }

  @override
  ConsumerState<StudySheetCameraModal> createState() =>
      _StudySheetCameraModalState();
}

class _StudySheetCameraModalState extends ConsumerState<StudySheetCameraModal> {
  File? _selectedImage;
  String _selectedSubject = 'Auto Detect';
  bool _isAnalyzing = false;
  StudySheetResult? _result;
  String? _errorMessage;
  bool _rulesSaved = false;
  CaptureDetail _detail = CaptureDetail.standard;
  bool _topicAddedToWeak = false;

  final List<String> _subjects = [
    'Auto Detect',
    'Bangla Grammar',
    'English Language & Literature',
    'Mathematics & Mental Ability',
    'General Science',
    'Bangladesh Affairs',
    'International Affairs',
    'Computer & ICT',
    'Geography & Environment',
  ];

  /// Lets the shot be sized before it is taken.
  ///
  /// A close-up of one MCQ stays readable at 768px, while a whole page shot
  /// from further away needs 1280 — and the model bills roughly four times as
  /// much for the latter. Choosing up front is the difference, so the cost of
  /// each option is on the chip rather than hidden.
  Widget _buildDetailSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.tune,
              size: 14,
              color: Theme.of(context).colorScheme.onSurface
                  .withValues(alpha: 0.65),
            ),
            const SizedBox(width: FluentSpacing.xs),
            Flexible(
              child: Text(
                'ছবির ধরন',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FluentType.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface
                      .withValues(alpha: 0.65),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: FluentSpacing.s),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: CaptureDetail.values.map((d) {
            final selected = d == _detail;
            return ChoiceChip(
              selected: selected,
              onSelected: (_) => setState(() {
                _detail = d;
                _result = null;
              }),
              label: Text(
                '${d.label} · ~${d.approxTokens}',
                style: FluentType.caption.copyWith(
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: FluentSpacing.s),
        Text(
          _detail.hint,
          style: FluentType.caption.copyWith(
            color: Theme.of(context).colorScheme.onSurface
                .withValues(alpha: 0.65),
          ),
        ),
      ],
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await PhotoCaptureService.instance.captureAndCrop(
        source: source,
        context: context,
        title: 'পড়ার অংশটুকু কেটে নিন',
      );

      if (picked != null) {
        setState(() {
          _selectedImage = picked;
          _result = null;
          _errorMessage = null;
          _rulesSaved = false;
          _topicAddedToWeak = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not access camera/gallery: $e';
      });
    }
  }

  int? _liveTokens;

  /// Characters of the reply received so far — see [_liveTokens]; this is the
  /// one that moves while the page is being read.
  int? _liveChars;

  Future<void> _analyzeImage() async {
    if (_selectedImage == null) return;

    setState(() {
      _isAnalyzing = true;
      _errorMessage = null;
      _liveTokens = null;
      _liveChars = null;
    });

    try {
      final result = await StudySheetOcrService.instance.analyzeStudySheet(
        _selectedImage!,
        subjectHint: _selectedSubject,
        detail: _detail,
        // The real figure, as the model reports it chunk by chunk. It holds
        // still while the model reasons, then climbs as the reply is written.
        onTokens: (soFar) {
          if (mounted) setState(() => _liveTokens = soFar);
        },
        onChars: (soFar) {
          if (mounted) setState(() => _liveChars = soFar);
        },
      );

      final spent = StudySheetOcrService.instance.lastCallTokens;
      if (mounted) {
        setState(() {
          _result = result;
          _isAnalyzing = false;
        });
        if (spent != null && spent > 0) {
          // The estimate during the wait was a guess; this is the bill.
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('পড়া হলো — $spent টোকেন খরচ হয়েছে')),
          );
        }
      }
    } on StudySheetReadException catch (e) {
      // Already phrased for the user, and says the photo is still here.
      if (mounted) {
        setState(() {
          _errorMessage = e.userMessage;
          _isAnalyzing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'পড়া গেল না: $e';
          _isAnalyzing = false;
        });
      }
    }
  }

  Future<void> _saveRulesToSpacedRepetition(StudySheetResult result) async {
    final db = ref.read(appDatabaseProvider);
    final tomorrow = DateTime.now().add(const Duration(days: 1));

    int savedCount = 0;
    for (final rule in result.keyRules) {
      await db.insertSpacedReviewItem(
        SpacedReviewItemsCompanion.insert(
          subject: result.subject,
          topic: result.title,
          title: rule.length > 50 ? '${rule.substring(0, 50)}...' : rule,
          keyRule: rule,
          nextReviewDate: tomorrow,
        ),
      );
      savedCount++;
    }

    ref.invalidate(dueSpacedReviewsStreamProvider);
    ref.invalidate(allSpacedReviewsStreamProvider);

    if (mounted) {
      setState(() {
        _rulesSaved = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF1E3A8A),
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: FluentSpacing.s),
              Expanded(
                child: Text(
                  '$savedCount tricky rules added to Spaced Repetition (Day 1 Review)!',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  Future<void> _addTopicToWeak(StudySheetResult result) async {
    final db = ref.read(appDatabaseProvider);
    await db.insertWeakTopic(
      WeakTopicsCompanion.insert(
        subject: result.subject,
        topicName: result.title,
        proficiencyLevel: ProficiencyLevel.weak,
      ),
    );

    ref.invalidate(weakTopicsStreamProvider);

    if (mounted) {
      setState(() {
        _topicAddedToWeak = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _badColour(context),
          content: Row(
            children: [
              const Icon(Icons.bookmark_added, color: Colors.white, size: 20),
              const SizedBox(width: FluentSpacing.s),
              Expanded(
                child: Text(
                  '"${result.title}" added to Weak Topics spotlight!',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  void _startQuizDrill(StudySheetResult result) {
    Navigator.of(context).pop(); // Close camera bottom sheet

    QuizDrillModal.show(
      context,
      topic: result.title.contains('বই') || result.title.contains('OCR')
          ? result.title
          : 'বই স্ক্যান: ${result.title}',
      subject: result.subject,
      customQuestions: result.questions,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = Theme.of(context).colorScheme.surface;

    return Container(
      height: MediaQuery.of(context).size.height * 0.90,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(
              top: FluentSpacing.m,
              bottom: FluentSpacing.s,
            ),
            width: 44,
            height: 4.5,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurface
                  .withValues(alpha: 0.65),
              borderRadius: FluentRadius.controlBorder,
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: FluentSpacing.xl,
              vertical: FluentSpacing.s,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(FluentSpacing.s),
                  decoration: BoxDecoration(
                    color: FluentLayer.subtle(
                      Theme.of(context).colorScheme.primary,
                      Theme.of(context).brightness,
                    ),
                    borderRadius: FluentRadius.controlBorder,
                  ),
                  child: Icon(
                    Icons.camera_alt,
                    color: Theme.of(context).colorScheme.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: FluentSpacing.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Snap Study Sheet to Drill',
                        style: FluentType.subtitle.copyWith(fontSize: 17),
                      ),
                      Text(
                        'Camera / OCR converts book page to 5-MCQ AI Drill',
                        style: FluentType.caption.copyWith(
                          color: Theme.of(context).colorScheme.onSurface
                              .withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 22),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Main Scrollable Body
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(FluentSpacing.l),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_errorMessage != null &&
                      AiKeyMissingNotice.looksLikeKeyProblem(
                        _errorMessage!,
                      )) ...[
                    // A missing key is a thing to go and do, not a failure
                    // to report.
                    AiKeyMissingNotice(
                      message: _errorMessage!,
                      onRetry: () {
                        if (mounted) setState(() => _errorMessage = null);
                      },
                    ),
                    const SizedBox(height: FluentSpacing.m),
                  ] else if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(FluentSpacing.m),
                      decoration: BoxDecoration(
                        color: FluentLayer.subtle(
                          _badColour(context),
                          Theme.of(context).brightness,
                        ),
                        borderRadius: FluentRadius.cardBorder,
                        border: Border.all(color: _badColour(context)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: _badColour(context),
                            size: 20,
                          ),
                          const SizedBox(width: FluentSpacing.s),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: FluentType.caption.copyWith(
                                color: _badColour(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_selectedImage != null) ...[
                      // The photo survived the failure, so trying again is
                      // one tap rather than another trip to the camera.
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _isAnalyzing ? null : _analyzeImage,
                          icon: const Icon(Icons.refresh, size: 17),
                          label: const Text(
                            'আবার চেষ্টা করুন',
                            style: FluentType.caption,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: FluentSpacing.m),
                  ],

                  // If no image is chosen yet
                  if (_selectedImage == null) ...[
                    _buildImagePickerPrompt(isDark),
                  ] else ...[
                    // Image selected & Preview
                    _buildImagePreview(isDark),
                    const SizedBox(height: FluentSpacing.l),

                    // Subject Selector
                    if (_result == null && !_isAnalyzing) ...[
                      _buildSubjectSelector(isDark),
                      const SizedBox(height: FluentSpacing.l),
                      // Also here, not just before picking: the whole point is
                      // being able to try the same page cheaper or sharper
                      // without hunting for the photo again.
                      _buildDetailSelector(),
                      const SizedBox(height: FluentSpacing.l),
                      ElevatedButton.icon(
                        onPressed: _analyzeImage,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E3A8A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            vertical: FluentSpacing.l,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: FluentRadius.controlBorder,
                          ),
                        ),
                        icon: const Icon(Icons.auto_awesome, size: 20),
                        label: const Text(
                          'Analyze Page & Generate Drill ⚡',
                          style: FluentType.bodyStrong,
                        ),
                      ),
                    ],

                    // Loading State
                    if (_isAnalyzing) ...[
                      const SizedBox(height: FluentSpacing.l),
                      AiProgressPipelineWidget(
                        type: AiTaskType.image,
                        isCompact: false,
                        // What the call is worth, so the wait reads as work
                        // being done rather than time passing.
                        // The real figure only; the estimate has its own slot
                        // and is marked as an estimate there.
                        liveTokens: _liveTokens,
                        liveChars: _liveChars,
                        estimatedTokens: StudySheetOcrService.instance
                            .estimateTokensFor(_detail),
                      ),
                      const SizedBox(height: FluentSpacing.l),
                    ],

                    // Results Extracted
                    if (_result != null) ...[
                      _buildAnalysisResultCard(_result!, isDark),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePickerPrompt(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(FluentSpacing.xxl),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: FluentRadius.cardBorder,
        border: Border.all(
          color: FluentStroke.card(Theme.of(context).brightness),
          width: FluentStroke.width,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.document_scanner_outlined,
            size: 54,
            color: Theme.of(context).colorScheme.primary
                .withValues(alpha: 0.85),
          ),
          const SizedBox(height: FluentSpacing.m),
          Text(
            'Snap or Upload Any Study Page',
            style: FluentType.subtitle.copyWith(fontSize: 16),
          ),
          const SizedBox(height: FluentSpacing.s),
          Text(
            'Capture textbook rules, coaching lecture sheets, or grammar charts to test yourself immediately with AI.',
            textAlign: TextAlign.center,
            style: FluentType.caption.copyWith(
              color: Theme.of(context).colorScheme.onSurface
                  .withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: FluentSpacing.l),
          _buildDetailSelector(),
          const SizedBox(height: FluentSpacing.l),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _pickImage(ImageSource.camera),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E3A8A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      vertical: FluentSpacing.m,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: FluentRadius.controlBorder,
                    ),
                  ),
                  icon: const Icon(Icons.camera_alt, size: 18),
                  label: const Text(
                    'Camera',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: FluentSpacing.m),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickImage(ImageSource.gallery),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: FluentSpacing.m,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: FluentRadius.controlBorder,
                    ),
                  ),
                  icon: const Icon(Icons.photo_library, size: 18),
                  label: const Text(
                    'Gallery',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _rotateImage() async {
    final current = _selectedImage;
    if (current == null) return;
    final turned = await PhotoCaptureService.instance.rotateQuarterTurn(
      current,
    );
    if (!mounted) return;
    setState(() {
      _selectedImage = turned;
      // The page the model was asked about has changed.
      _result = null;
      _errorMessage = null;
      // Flutter caches a decoded file by path and size; a new path each turn
      // is what makes the preview redraw.
      imageCache.clear();
    });
  }

  Future<void> _recropImage() async {
    final current = _selectedImage;
    if (current == null) return;
    final trimmed = await PhotoCaptureService.instance.cropExisting(
      path: current.path,
      context: context,
      title: 'পড়ার অংশটুকু কেটে নিন',
    );
    if (trimmed == null || !mounted) return;
    setState(() {
      _selectedImage = trimmed;
      _result = null;
      _errorMessage = null;
      imageCache.clear();
    });
  }

  Widget _buildImagePreview(bool isDark) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: FluentRadius.cardBorder,
          child: Container(
            height: 180,
            width: double.infinity,
            color: Theme.of(context).colorScheme.onSurface
                .withValues(alpha: 0.06),
            // contain, not cover: a page turned on its side must stay
            // whole in the preview rather than having its edges cut off.
            child: Image.file(_selectedImage!, fit: BoxFit.contain),
          ),
        ),
        Positioned(
          top: FluentSpacing.s,
          right: FluentSpacing.s,
          child: Row(
            children: [
              // A book shot sideways needs the whole page turned, not the
              // crop frame tilted.
              CircleAvatar(
                radius: 16,
                backgroundColor: Colors.black.withValues(alpha: 0.65),
                child: IconButton(
                  tooltip: 'ঘুরিয়ে সোজা করুন',
                  icon: const Icon(
                    Icons.rotate_90_degrees_cw_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                  onPressed: _rotateImage,
                  padding: EdgeInsets.zero,
                ),
              ),
              const SizedBox(width: FluentSpacing.s),
              CircleAvatar(
                radius: 16,
                backgroundColor: Colors.black.withValues(alpha: 0.65),
                child: IconButton(
                  tooltip: 'আবার কাটুন',
                  icon: const Icon(
                    Icons.crop_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                  onPressed: _recropImage,
                  padding: EdgeInsets.zero,
                ),
              ),
              const SizedBox(width: FluentSpacing.s),
              CircleAvatar(
                radius: 16,
                backgroundColor: Colors.black.withValues(alpha: 0.65),
                child: IconButton(
                  tooltip: 'আবার তুলুন',
                  icon: const Icon(
                    Icons.refresh,
                    size: 16,
                    color: Colors.white,
                  ),
                  onPressed: () => _pickImage(ImageSource.camera),
                  padding: EdgeInsets.zero,
                ),
              ),
              const SizedBox(width: FluentSpacing.s),
              CircleAvatar(
                radius: 16,
                backgroundColor: Colors.black.withValues(alpha: 0.65),
                child: IconButton(
                  icon: const Icon(Icons.close, size: 16, color: Colors.white),
                  onPressed: () {
                    setState(() {
                      _selectedImage = null;
                      _result = null;
                    });
                  },
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSubjectSelector(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FluentSpacing.l,
        vertical: FluentSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
        borderRadius: FluentRadius.cardBorder,
        border: Border.all(
          color: FluentStroke.card(Theme.of(context).brightness),
          width: FluentStroke.width,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedSubject,
          isExpanded: true,
          icon: const Icon(Icons.arrow_drop_down),
          items: _subjects.map((sub) {
            return DropdownMenuItem<String>(
              value: sub,
              child: Text(
                'Subject: $sub',
                style: FluentType.body.copyWith(fontWeight: FontWeight.w500),
              ),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) {
              setState(() {
                _selectedSubject = val;
              });
            }
          },
        ),
      ),
    );
  }

  Widget _buildAnalysisResultCard(StudySheetResult result, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Extracted Topic Badge & Title
        Container(
          padding: const EdgeInsets.all(FluentSpacing.l),
          decoration: BoxDecoration(
            color: FluentLayer.subtle(
              Theme.of(context).colorScheme.primary,
              Theme.of(context).brightness,
            ),
            borderRadius: FluentRadius.cardBorder,
            border: Border.all(
              color: Theme.of(context).colorScheme.primary
                  .withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: FluentSpacing.s,
                        vertical: FluentSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: FluentRadius.controlBorder,
                      ),
                      child: Text(
                        result.subject,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FluentType.caption.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.check_circle,
                    color: Color(0xFF10B981),
                    size: 16,
                  ),
                  const SizedBox(width: FluentSpacing.xs),
                  Text(
                    'Extracted via Gemini Vision',
                    style: FluentType.caption.copyWith(
                      color: Color(0xFF10B981),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: FluentSpacing.s),
              Text(
                result.title,
                style: FluentType.subtitle.copyWith(fontSize: 16),
              ),
              const SizedBox(height: FluentSpacing.s),
              Text(
                result.summary,
                style: FluentType.caption.copyWith(
                  color: Theme.of(context).colorScheme.onSurface
                      .withValues(alpha: 0.65),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: FluentSpacing.l),

        // Key Rules & High Yield Points
        if (result.keyRules.isNotEmpty ||
            result.highYieldPoints.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(FluentSpacing.l),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: FluentRadius.cardBorder,
              border: Border.all(
                color: FluentStroke.card(Theme.of(context).brightness),
                width: FluentStroke.width,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.psychology,
                      size: 18,
                      color: Color(0xFF6366F1),
                    ),
                    const SizedBox(width: FluentSpacing.s),
                    Flexible(
                      child: Text(
                        'High-Yield Rules & Mnemonics (${result.keyRules.length})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FluentType.bodyStrong,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: FluentSpacing.s),
                ...result.keyRules.take(3).map((rule) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: FluentSpacing.s),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('📌 ', style: FluentType.caption),
                        Expanded(child: Text(rule, style: FluentType.caption)),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: FluentSpacing.l),
        ],

        // 3 Action Buttons
        // 1. Primary: Start 5-MCQ Drill Now
        ElevatedButton.icon(
          onPressed: () => _startQuizDrill(result),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF10B981), // Emerald green
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: FluentSpacing.l),
            shape: RoundedRectangleBorder(
              borderRadius: FluentRadius.controlBorder,
            ),
          ),
          icon: const Icon(Icons.bolt, size: 22),
          label: Text(
            '⚡ Start ${result.questions.length}-MCQ Drill Now',
            style: FluentType.bodyStrong,
          ),
        ),
        const SizedBox(height: FluentSpacing.m),

        // 2. Save Rules to Spaced Repetition (Ebbinghaus)
        OutlinedButton.icon(
          onPressed: _rulesSaved
              ? null
              : () => _saveRulesToSpacedRepetition(result),
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.primary,
            padding: const EdgeInsets.symmetric(vertical: FluentSpacing.m),
            side: BorderSide(
              color: _rulesSaved
                  ? Theme.of(context).colorScheme.onSurface
                        .withValues(alpha: 0.65)
                  : Theme.of(context).colorScheme.primary,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: FluentRadius.controlBorder,
            ),
          ),
          icon: Icon(_rulesSaved ? Icons.check : Icons.alarm_add, size: 18),
          label: Text(
            _rulesSaved
                ? 'Rules Saved to Spaced Repetition ✓'
                : '🧠 Save Rules to Spaced Repetition (Day 1)',
            style: FluentType.bodyStrong,
          ),
        ),
        const SizedBox(height: FluentSpacing.s),

        // 3. Add to Weak Topics Spotlight
        TextButton.icon(
          onPressed: _topicAddedToWeak ? null : () => _addTopicToWeak(result),
          icon: Icon(
            _topicAddedToWeak
                ? Icons.bookmark_added
                : Icons.bookmark_add_outlined,
            size: 17,
            color: _topicAddedToWeak
                ? Theme.of(context).colorScheme.onSurface
                      .withValues(alpha: 0.65)
                : _badColour(context),
          ),
          label: Text(
            _topicAddedToWeak
                ? 'Added to Weak Topics ✓'
                : '➕ Add Topic to Priority Focus',
            style: FluentType.caption.copyWith(
              fontWeight: FontWeight.w600,
              color: _topicAddedToWeak
                  ? Theme.of(context).colorScheme.onSurface
                        .withValues(alpha: 0.65)
                  : _badColour(context),
            ),
          ),
        ),
      ],
    );
  }
}
