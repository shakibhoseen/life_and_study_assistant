import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/services/ai/ai_media_limits.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../core/database/tables/weak_topics_table.dart';
import '../../../../core/services/ai/models/study_sheet_result.dart';
import '../../../../core/services/ai/study_sheet_ocr_service.dart';
import '../../../spaced_repetition/presentation/providers/spaced_repetition_provider.dart';
import '../../../topics/presentation/providers/topics_provider.dart';
import 'quiz_drill_modal.dart';

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
  final ImagePicker _picker = ImagePicker();
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
            Icon(Icons.tune, size: 14, color: Colors.grey.shade500),
            const SizedBox(width: 5),
            Text(
              'ছবির ধরন',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
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
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 6),
        Text(
          _detail.hint,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
        ),
      ],
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        // Deliberately above every preset: the picker keeps headroom and
        // _prepareImageBytes does the real reduction, so switching to a
        // sharper setting after the shot still has pixels to work with.
        maxWidth: AiMediaLimits.pickerHeadroom.toDouble(),
        maxHeight: AiMediaLimits.pickerHeadroom.toDouble(),
        imageQuality: AiMediaLimits.jpegQuality,
      );

      if (picked != null) {
        setState(() {
          _selectedImage = File(picked.path);
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

  Future<void> _analyzeImage() async {
    if (_selectedImage == null) return;

    setState(() {
      _isAnalyzing = true;
      _errorMessage = null;
    });

    try {
      final result = await StudySheetOcrService.instance.analyzeStudySheet(
        _selectedImage!,
        subjectHint: _selectedSubject,
        detail: _detail,
      );

      if (mounted) {
        setState(() {
          _result = result;
          _isAnalyzing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Analysis failed: $e';
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
              const SizedBox(width: 8),
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
          backgroundColor: const Color(0xFFBE123C),
          content: Row(
            children: [
              const Icon(Icons.bookmark_added, color: Colors.white, size: 20),
              const SizedBox(width: 8),
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
    final backgroundColor = isDark ? const Color(0xFF111827) : Colors.white;

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
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 44,
            height: 4.5,
            decoration: BoxDecoration(
              color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(4),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50.withValues(
                      alpha: isDark ? 0.15 : 1,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.camera_alt,
                    color: Color(0xFF6366F1),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Snap Study Sheet to Drill',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Camera / OCR converts book page to 5-MCQ AI Drill',
                        style: TextStyle(fontSize: 11.5, color: Colors.grey),
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
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50.withValues(
                          alpha: isDark ? 0.2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade300),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Colors.red,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: isDark
                                    ? Colors.red.shade200
                                    : Colors.red.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // If no image is chosen yet
                  if (_selectedImage == null) ...[
                    _buildImagePickerPrompt(isDark),
                  ] else ...[
                    // Image selected & Preview
                    _buildImagePreview(isDark),
                    const SizedBox(height: 16),

                    // Subject Selector
                    if (_result == null && !_isAnalyzing) ...[
                      _buildSubjectSelector(isDark),
                      const SizedBox(height: 16),
                      // Also here, not just before picking: the whole point is
                      // being able to try the same page cheaper or sharper
                      // without hunting for the photo again.
                      _buildDetailSelector(),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _analyzeImage,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E3A8A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.auto_awesome, size: 20),
                        label: const Text(
                          'Analyze Page & Generate Drill ⚡',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],

                    // Loading State
                    if (_isAnalyzing) ...[
                      const SizedBox(height: 24),
                      Center(
                        child: Column(
                          children: [
                            const SizedBox(
                              width: 36,
                              height: 36,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: Color(0xFF6366F1),
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'Gemini Vision is analyzing your study page...',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Extracting key formulas, mnemonics & formulating 5-MCQ drill',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
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
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2937) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF374151) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.document_scanner_outlined,
            size: 54,
            color: const Color(0xFF6366F1).withValues(alpha: 0.85),
          ),
          const SizedBox(height: 12),
          const Text(
            'Snap or Upload Any Study Page',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'Capture textbook rules, coaching lecture sheets, or grammar charts to test yourself immediately with AI.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 16),
          _buildDetailSelector(),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _pickImage(ImageSource.camera),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E3A8A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.camera_alt, size: 18),
                  label: const Text(
                    'Camera',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickImage(ImageSource.gallery),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
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

  Widget _buildImagePreview(bool isDark) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 180,
            width: double.infinity,
            color: isDark ? const Color(0xFF1F2937) : Colors.grey.shade200,
            child: Image.file(_selectedImage!, fit: BoxFit.cover),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: Colors.black.withValues(alpha: 0.65),
                child: IconButton(
                  icon: const Icon(
                    Icons.refresh,
                    size: 16,
                    color: Colors.white,
                  ),
                  onPressed: () => _pickImage(ImageSource.camera),
                  padding: EdgeInsets.zero,
                ),
              ),
              const SizedBox(width: 6),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2937) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF374151) : const Color(0xFFE2E8F0),
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
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
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
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFEEF2FF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFF6366F1).withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      result.subject,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.check_circle,
                    color: Color(0xFF10B981),
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Extracted via Gemini Vision',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF10B981),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                result.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                result.summary,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Key Rules & High Yield Points
        if (result.keyRules.isNotEmpty ||
            result.highYieldPoints.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1F2937) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF374151)
                    : const Color(0xFFE2E8F0),
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
                    const SizedBox(width: 6),
                    Text(
                      'High-Yield Rules & Mnemonics (${result.keyRules.length})',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...result.keyRules.take(3).map((rule) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('📌 ', style: TextStyle(fontSize: 12)),
                        Expanded(
                          child: Text(
                            rule,
                            style: const TextStyle(fontSize: 12, height: 1.3),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // 3 Action Buttons
        // 1. Primary: Start 5-MCQ Drill Now
        ElevatedButton.icon(
          onPressed: () => _startQuizDrill(result),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF10B981), // Emerald green
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: const Icon(Icons.bolt, size: 22),
          label: Text(
            '⚡ Start ${result.questions.length}-MCQ Drill Now',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 10),

        // 2. Save Rules to Spaced Repetition (Ebbinghaus)
        OutlinedButton.icon(
          onPressed: _rulesSaved
              ? null
              : () => _saveRulesToSpacedRepetition(result),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF6366F1),
            padding: const EdgeInsets.symmetric(vertical: 12),
            side: BorderSide(
              color: _rulesSaved ? Colors.grey : const Color(0xFF6366F1),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: Icon(_rulesSaved ? Icons.check : Icons.alarm_add, size: 18),
          label: Text(
            _rulesSaved
                ? 'Rules Saved to Spaced Repetition ✓'
                : '🧠 Save Rules to Spaced Repetition (Day 1)',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 8),

        // 3. Add to Weak Topics Spotlight
        TextButton.icon(
          onPressed: _topicAddedToWeak ? null : () => _addTopicToWeak(result),
          icon: Icon(
            _topicAddedToWeak
                ? Icons.bookmark_added
                : Icons.bookmark_add_outlined,
            size: 17,
            color: _topicAddedToWeak ? Colors.grey : const Color(0xFFBE123C),
          ),
          label: Text(
            _topicAddedToWeak
                ? 'Added to Weak Topics ✓'
                : '➕ Add Topic to Priority Focus',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: _topicAddedToWeak ? Colors.grey : const Color(0xFFBE123C),
            ),
          ),
        ),
      ],
    );
  }
}
