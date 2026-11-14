import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/fluent_tokens.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../core/services/ai/ai_flashcard_service.dart';
import '../providers/spaced_repetition_provider.dart';
import '../../../../core/services/media/photo_capture_service.dart';
import '../../../../core/services/ai/ai_cancellation.dart';
import '../../../../core/widgets/ai_progress_pipeline_widget.dart';
import '../../../../core/widgets/ai_key_missing_notice.dart';
import '../../../settings/presentation/screens/settings_screen.dart';

class AiFlashcardGeneratorModal extends ConsumerStatefulWidget {
  final String? initialPrompt;

  const AiFlashcardGeneratorModal({super.key, this.initialPrompt});

  static Future<void> show(BuildContext context, {String? initialPrompt}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AiFlashcardGeneratorModal(initialPrompt: initialPrompt),
    );
  }

  @override
  ConsumerState<AiFlashcardGeneratorModal> createState() =>
      _AiFlashcardGeneratorModalState();
}

class _AiFlashcardGeneratorModalState
    extends ConsumerState<AiFlashcardGeneratorModal>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _promptController = TextEditingController();
  final TextEditingController _pasteController = TextEditingController();

  File? _selectedImage;

  bool _isLoading = false;
  String? _loadingStatus;
  List<AiFlashcardItem>? _generatedCards;
  AiCancellation? _cancellation;
  AiTaskType _loadingTaskType = AiTaskType.text;

  final List<String> _quickPromptChips = const [
    'বর্গক্ষেত্রের কর্ণের দৈর্ঘ্য ও সূত্র',
    'সমকোণী ও সমবাহু ত্রিভুজ',
    'বৃত্তের পরিধি ও ক্ষেত্রফল',
    'ণ-ত্ব ও ষ-ত্ব বিধানের নিয়ম',
    'অপাদান ও অধিকরণ কারক',
    'সংবিধানের গুরুত্বপূর্ণ অনুচ্ছেদ',
    'High Frequency BCS Vocab',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    if (widget.initialPrompt != null && widget.initialPrompt!.isNotEmpty) {
      _promptController.text = widget.initialPrompt!;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _promptController.dispose();
    _pasteController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await PhotoCaptureService.instance.captureAndCrop(
        source: source,
        context: context,
        title: 'মনে রাখার অংশটুকু কেটে নিন',
      );
      if (picked != null) {
        setState(() {
          _selectedImage = picked;
        });
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    }
  }

  Future<void> _generateFromPrompt() async {
    final query = _promptController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isLoading = true;
      _cancellation = AiCancellation();
      _loadingTaskType = AiTaskType.text;
      _loadingStatus = 'AI ফ্ল্যাশ কার্ড ও সূত্র তৈরি করছে...';
    });

    try {
      final cards = await AiFlashcardService.instance.generateFromPrompt(
        query,
        cancellation: _cancellation,
      );
      if (mounted) {
        setState(() {
          _generatedCards = cards;
          _isLoading = false;
        });
      }
    } on AiCancelledException {
      // The user stopped the wait. Nothing was asked for, so nothing is said
      // beyond confirming it stopped.
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('থামানো হলো। যা খরচ হয়ে গেছে তা ফেরত আসে না।'),
          ),
        );
      }
    } on FlashcardGenerationException catch (e) {
      // Already phrased for the user, and says what to do next. When what to
      // do next is "set a key", the snackbar carries the way there.
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.userMessage),
            duration: const Duration(seconds: 6),
            action: AiKeyMissingNotice.looksLikeKeyProblem(e.userMessage)
                ? SnackBarAction(
                    label: 'সেটিংস',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    ),
                  )
                : null,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('কার্ড তৈরি করতে সমস্যা হয়েছে: $e')),
        );
      }
    }
  }

  Future<void> _generateFromImage() async {
    if (_selectedImage == null) return;

    setState(() {
      _isLoading = true;
      _cancellation = AiCancellation();
      _loadingTaskType = AiTaskType.image;
      _loadingStatus =
          'বইয়ের পাতা স্ক্যান করে গুরুত্বপূর্ণ সূত্রগুলো বের করা হচ্ছে...';
    });

    try {
      final cards = await AiFlashcardService.instance.extractFromBookImage(
        _selectedImage!,
        cancellation: _cancellation,
      );
      if (mounted) {
        setState(() {
          _generatedCards = cards;
          _isLoading = false;
        });
      }
    } on AiCancelledException {
      // The user stopped the wait. Nothing was asked for, so nothing is said
      // beyond confirming it stopped.
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('থামানো হলো। যা খরচ হয়ে গেছে তা ফেরত আসে না।'),
          ),
        );
      }
    } on FlashcardGenerationException catch (e) {
      // Already phrased for the user, and says what to do next. When what to
      // do next is "set a key", the snackbar carries the way there.
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.userMessage),
            duration: const Duration(seconds: 6),
            action: AiKeyMissingNotice.looksLikeKeyProblem(e.userMessage)
                ? SnackBarAction(
                    label: 'সেটিংস',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    ),
                  )
                : null,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ছবি থেকে স্ক্যান করতে সমস্যা হয়েছে: $e')),
        );
      }
    }
  }

  Future<void> _generateFromPaste() async {
    final text = _pasteController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _isLoading = true;
      _cancellation = AiCancellation();
      _loadingTaskType = AiTaskType.text;
      _loadingStatus = 'টেক্সট থেকে ফ্ল্যাশ কার্ড সাজানো হচ্ছে...';
    });

    try {
      final cards = await AiFlashcardService.instance.parseFromExternalText(
        text,
        cancellation: _cancellation,
      );
      final wasFree = AiFlashcardService.instance.lastParseWasFree;
      if (mounted) {
        setState(() {
          _generatedCards = cards;
          _isLoading = false;
        });
        if (cards.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                wasFree
                    ? '${cards.length}টি কার্ড — ফোনেই পড়া হয়েছে, টোকেন খরচ হয়নি'
                    : '${cards.length}টি কার্ড — AI দিয়ে পড়তে হয়েছে',
              ),
            ),
          );
        }
      }
    } on AiCancelledException {
      // The user stopped the wait. Nothing was asked for, so nothing is said
      // beyond confirming it stopped.
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('থামানো হলো। যা খরচ হয়ে গেছে তা ফেরত আসে না।'),
          ),
        );
      }
    } on FlashcardGenerationException catch (e) {
      // Already phrased for the user, and says what to do next. When what to
      // do next is "set a key", the snackbar carries the way there.
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.userMessage),
            duration: const Duration(seconds: 6),
            action: AiKeyMissingNotice.looksLikeKeyProblem(e.userMessage)
                ? SnackBarAction(
                    label: 'সেটিংস',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    ),
                  )
                : null,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('টেক্সট পার্স করতে সমস্যা হয়েছে: $e')),
        );
      }
    }
  }

  Future<void> _saveCards() async {
    if (_generatedCards == null || _generatedCards!.isEmpty) return;

    final selected = _generatedCards!.where((c) => c.isSelected).toList();
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('অন্তত একটি ফ্ল্যাশ কার্ড সিলেক্ট করুন')),
      );
      return;
    }

    try {
      final db = ref.read(appDatabaseProvider);
      final count = await AiFlashcardService.instance.saveToSpacedRepetition(
        db,
        selected,
      );

      ref.invalidate(allSpacedReviewsStreamProvider);
      ref.invalidate(dueSpacedReviewsStreamProvider);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: FluentSpacing.s),
                Expanded(
                  child: Text(
                    '$countটি ফ্ল্যাশ কার্ড স্পেসড রিপিটেশন ট্র্যাকে যুক্ত হয়েছে! ⚡',
                    style: FluentType.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('সেভ করতে সমস্যা হয়েছে: $e')));
      }
    }
  }

  void _showEditCardDialog(int index) {
    if (_generatedCards == null || index >= _generatedCards!.length) return;
    final card = _generatedCards![index];

    final frontCtrl = TextEditingController(text: card.front);
    final backCtrl = TextEditingController(text: card.back);
    final subjectCtrl = TextEditingController(text: card.subject);
    final topicCtrl = TextEditingController(text: card.topic);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: FluentRadius.cardBorder,
          side: FluentStroke.side(Theme.of(ctx).brightness),
        ),
        title: Row(
          children: [
            Icon(
              Icons.edit,
              size: 18,
              color: Theme.of(ctx).colorScheme.primary,
            ),
            const SizedBox(width: FluentSpacing.s),
            Flexible(
              child: Text(
                'ফ্ল্যাশ কার্ড সম্পাদনা',
                style: FluentType.subtitle.copyWith(
                  color: Theme.of(ctx).colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: subjectCtrl,
                decoration: const InputDecoration(
                  labelText: 'বিষয় (Subject)',
                  isDense: true,
                ),
              ),
              const SizedBox(height: FluentSpacing.m),
              TextField(
                controller: topicCtrl,
                decoration: const InputDecoration(
                  labelText: 'টপিক (Topic)',
                  isDense: true,
                ),
              ),
              const SizedBox(height: FluentSpacing.m),
              TextField(
                controller: frontCtrl,
                decoration: const InputDecoration(
                  labelText: 'সামনে (প্রশ্ন বা সূত্র শিরোনাম)',
                  isDense: true,
                ),
              ),
              const SizedBox(height: FluentSpacing.m),
              TextField(
                controller: backCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'পেছনে (সূত্র, উত্তর বা শর্টকাট)',
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('বাতিল'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _generatedCards![index] = card.copyWith(
                  subject: subjectCtrl.text.trim(),
                  topic: topicCtrl.text.trim(),
                  front: frontCtrl.text.trim(),
                  back: backCtrl.text.trim(),
                );
              });
              Navigator.pop(ctx);
            },
            child: const Text('সংরক্ষণ'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final brightness = Theme.of(context).brightness;
    final scheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(FluentRadius.large),
        ),
        border: Border(
          top: BorderSide(
            color: FluentStroke.card(brightness),
            width: FluentStroke.width,
          ),
        ),
        boxShadow: FluentElevation.flyout(brightness),
      ),
      padding: EdgeInsets.only(
        left: FluentSpacing.l,
        right: FluentSpacing.l,
        top: FluentSpacing.m,
        bottom: bottomInset + FluentSpacing.l,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: FluentSpacing.m),
              decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: 0.2),
                borderRadius: FluentRadius.controlBorder,
              ),
            ),
          ),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(FluentSpacing.s),
                decoration: BoxDecoration(
                  color: FluentLayer.subtle(scheme.primary, brightness),
                  borderRadius: FluentRadius.controlBorder,
                ),
                child: Icon(
                  Icons.auto_awesome,
                  color: scheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: FluentSpacing.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI ফ্ল্যাশ কার্ড ও সূত্র জেনারেটর',
                      style: FluentType.bodyStrong.copyWith(
                        color: scheme.onSurface,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'বইয়ের ছবি, প্রম্পট বা বাহ্যিক AI থেকে সরাসরি ফ্ল্যাশ কার্ড বানান',
                      style: FluentType.caption.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.65),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                visualDensity: VisualDensity.compact,
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: FluentSpacing.m),

          // Content Switch: Generator Tabs vs Generated Cards Preview
          if (_generatedCards == null) ...[
            // Tab Bar
            TabBar(
              controller: _tabController,
              labelColor: scheme.primary,
              unselectedLabelColor: scheme.onSurface.withValues(alpha: 0.65),
              indicatorColor: scheme.primary,
              tabs: const [
                Tab(
                  icon: Icon(Icons.chat_bubble_outline, size: 18),
                  text: 'প্রম্পট',
                ),
                Tab(
                  icon: Icon(Icons.camera_alt_outlined, size: 18),
                  text: 'বইয়ের ছবি',
                ),
                Tab(
                  icon: Icon(Icons.content_paste_rounded, size: 18),
                  text: 'পেস্ট',
                ),
              ],
            ),
            const SizedBox(height: FluentSpacing.m),

            Expanded(
              child: _isLoading
                  ? _buildLoadingState(isDark)
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildPromptTab(isDark),
                        _buildImageTab(isDark),
                        _buildPasteTab(isDark),
                      ],
                    ),
            ),
          ] else ...[
            // Preview & Confirm Generated Cards
            Expanded(child: _buildCardsPreview(isDark)),
          ],
        ],
      ),
    );
  }

  Widget _buildLoadingState(bool isDark) {
    // A bare spinner says only "wait", with no sense of how long or whether
    // anything is happening. The pipeline counts the seconds, names the
    // stage, and gives the user a way out.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FluentSpacing.l),
      child: AiProgressPipelineWidget(
        type: _loadingTaskType,
        customStatus: _loadingStatus,
        onCancel: _cancelLoading,
      ),
    );
  }

  void _cancelLoading() => _cancellation?.cancel();

  Widget _buildPromptTab(bool isDark) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _promptController,
            maxLines: 2,
            decoration: InputDecoration(
              hintText:
                  'যেমন: বর্গক্ষেত্রের কর্ণের দৈর্ঘ্য ও পরিমিতির সূত্র...',
              hintStyle: FluentType.body.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.5),
              ),
              filled: true,
              fillColor: scheme.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: FluentRadius.controlBorder,
                borderSide: FluentStroke.side(brightness),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: FluentRadius.controlBorder,
                borderSide: FluentStroke.side(brightness),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: FluentRadius.controlBorder,
                borderSide: BorderSide(
                  color: scheme.primary,
                  width: FluentStroke.width,
                ),
              ),
            ),
          ),
          const SizedBox(height: FluentSpacing.m),

          Text(
            'দ্রুত সিলেক্ট করার জন্য টপিক:',
            style: FluentType.caption.copyWith(
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: FluentSpacing.s),
          Wrap(
            spacing: FluentSpacing.s,
            runSpacing: FluentSpacing.xs,
            children: _quickPromptChips.map((chipText) {
              return ActionChip(
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(
                  borderRadius: FluentRadius.controlBorder,
                  side: FluentStroke.side(brightness),
                ),
                backgroundColor: scheme.surfaceContainerHighest,
                label: Text(
                  chipText,
                  style: FluentType.caption.copyWith(color: scheme.onSurface),
                ),
                onPressed: () {
                  _promptController.text = chipText;
                  _generateFromPrompt();
                },
              );
            }).toList(),
          ),
          const SizedBox(height: FluentSpacing.l),

          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: FluentSpacing.m),
              shape: RoundedRectangleBorder(
                borderRadius: FluentRadius.controlBorder,
              ),
            ),
            icon: const Icon(Icons.bolt_rounded, size: 18),
            label: const Text(
              'ফ্ল্যাশ কার্ড তৈরি করুন ⚡',
              style: FluentType.bodyStrong,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onPressed: _generateFromPrompt,
          ),
        ],
      ),
    );
  }

  Widget _buildImageTab(bool isDark) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(FluentSpacing.l),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? Colors.white12 : Colors.grey.shade300,
              ),
            ),
            child: Column(
              children: [
                if (_selectedImage != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    // contain, not cover: a page turned on its side must
                    // stay whole here rather than having its edges cut off.
                    child: Container(
                      height: 140,
                      width: double.infinity,
                      color: isDark ? Colors.black26 : Colors.grey.shade200,
                      child: Image.file(
                        _selectedImage!,
                        key: ValueKey(_selectedImage!.path),
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: FluentSpacing.m),
                  Text(
                    'নির্বাচিত ছবি: ${_selectedImage!.path.split("/").last}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const SizedBox(height: FluentSpacing.m),
                ] else ...[
                  const Icon(
                    Icons.menu_book_rounded,
                    size: 44,
                    color: Color(0xFF6366F1),
                  ),
                  const SizedBox(height: FluentSpacing.s),
                  const Text(
                    'বইয়ের সূত্র বা নিয়মের পেজ স্ক্যান করুন',
                    style: FluentType.bodyStrong,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: FluentSpacing.xs),
                  const Text(
                    'খায়রুলস বেসিক ম্যাথ, এমপিথ্রি বা হ্যান্ডনোটের ছবি দিন',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const SizedBox(height: FluentSpacing.l),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.camera_alt, size: 16),
                      label: const Text('ক্যামেরা'),
                      onPressed: () => _pickImage(ImageSource.camera),
                    ),
                    const SizedBox(width: FluentSpacing.m),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.photo_library, size: 16),
                      label: const Text('গ্যালারি'),
                      onPressed: () => _pickImage(ImageSource.gallery),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: FluentSpacing.l),

          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: FluentSpacing.m),
              shape: RoundedRectangleBorder(
                borderRadius: FluentRadius.controlBorder,
              ),
            ),
            icon: const Icon(Icons.document_scanner, size: 18),
            label: const Text(
              'সূত্র ও নিয়ম স্ক্যান করুন 🔍',
              style: FluentType.bodyStrong,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onPressed: _selectedImage == null ? null : _generateFromImage,
          ),
        ],
      ),
    );
  }

  Widget _buildPasteTab(bool isDark) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Any format works, but one of them is free, so it is offered up
          // front rather than left for the user to discover.
          Container(
            margin: const EdgeInsets.only(bottom: FluentSpacing.m),
            padding: const EdgeInsets.all(FluentSpacing.m),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF14532D).withValues(alpha: 0.35)
                  : const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDark ? Colors.green.shade900 : Colors.green.shade200,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'যেকোনো ফরম্যাট চলবে — সাধারণ লেখা, টেবিল, নোট। '
                  'তবে JSON হলে ফোনেই পড়া হয়, কোনো টোকেন খরচ হয় না।',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark
                        ? Colors.green.shade200
                        : Colors.green.shade900,
                  ),
                ),
                const SizedBox(height: FluentSpacing.s),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(
                        const ClipboardData(
                          text: externalFlashcardPromptTemplate,
                        ),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'প্রম্পট কপি হয়েছে — ChatGPT বা Claude-এ পেস্ট করুন',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy_all_rounded, size: 16),
                    label: const Text(
                      'বাইরের AI-এর জন্য প্রম্পট কপি করুন',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: FluentSpacing.xs),
                    ),
                  ),
                ),
              ],
            ),
          ),
          TextField(
            controller: _pasteController,
            maxLines: 6,
            decoration: InputDecoration(
              hintText:
                  'ChatGPT, Claude বা যেকোনো সোর্স থেকে সূত্র/নোট পেস্ট করুন:\n\n'
                  'যেমন:\n'
                  'বর্গক্ষেত্রের কর্ণের দৈর্ঘ্য: d = √2a\n'
                  'বর্গক্ষেত্রের ক্ষেত্রফল: A = a² = d²/2\n'
                  'বৃত্তের পরিধি: 2πr',
              hintStyle: FluentType.body.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.5),
              ),
              filled: true,
              fillColor: scheme.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: FluentRadius.controlBorder,
                borderSide: FluentStroke.side(brightness),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: FluentRadius.controlBorder,
                borderSide: FluentStroke.side(brightness),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: FluentRadius.controlBorder,
                borderSide: BorderSide(
                  color: scheme.primary,
                  width: FluentStroke.width,
                ),
              ),
            ),
          ),
          const SizedBox(height: FluentSpacing.m),

          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: FluentSpacing.m),
              shape: RoundedRectangleBorder(
                borderRadius: FluentRadius.controlBorder,
              ),
            ),
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text(
              'ফ্ল্যাশ কার্ডে রূপান্তর করুন 🪄',
              style: FluentType.bodyStrong,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onPressed: _generateFromPaste,
          ),
        ],
      ),
    );
  }

  Widget _buildCardsPreview(bool isDark) {
    final scheme = Theme.of(context).colorScheme;
    final cards = _generatedCards!;
    final selectedCount = cards.where((c) => c.isSelected).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'তৈরিকৃত কার্ড (${cards.length}টির মধ্যে $selectedCountটি নির্বাচিত)',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Row(
              children: [
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () {
                    setState(() {
                      for (final c in cards) {
                        c.isSelected = true;
                      }
                    });
                  },
                  child: const Text(
                    'সব নির্বাচন',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () {
                    setState(() {
                      _generatedCards = null;
                    });
                  },
                  child: const Text(
                    'পুনরায় তৈরি',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: FluentSpacing.s),

        Expanded(
          child: ListView.builder(
            itemCount: cards.length,
            itemBuilder: (ctx, index) {
              final card = cards[index];

              return Container(
                margin: const EdgeInsets.only(bottom: FluentSpacing.s),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: card.isSelected
                        ? const Color(0xFF6366F1)
                        : (isDark ? Colors.white12 : Colors.grey.shade300),
                    width: card.isSelected ? 1.5 : 1,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(FluentSpacing.m),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: card.isSelected,
                        activeColor: const Color(0xFF6366F1),
                        visualDensity: VisualDensity.compact,
                        onChanged: (val) {
                          setState(() {
                            card.isSelected = val ?? false;
                          });
                        },
                      ),
                      const SizedBox(width: FluentSpacing.xs),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Tags
                            Row(
                              children: [
                                Flexible(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF6366F1)
                                          .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '${card.subject} • ${card.topic}',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF6366F1),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 15),
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  onPressed: () => _showEditCardDialog(index),
                                ),
                              ],
                            ),
                            const SizedBox(height: FluentSpacing.s),

                            // How directly the exam asks for this, and why it
                            // was picked. Shown because the user is choosing
                            // what to keep, and a reason they can read beats a
                            // rating they cannot question.
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Flexible(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: switch (card.priority) {
                                        CardPriority.high => Colors.green,
                                        CardPriority.medium => Colors.blueGrey,
                                        CardPriority.low => Colors.grey,
                                      }.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      card.priority.label,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: switch (card.priority) {
                                          CardPriority.high => Colors.green,
                                          CardPriority.medium => Colors.blueGrey,
                                          CardPriority.low => Colors.grey,
                                        },
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                if ((card.why ?? '').isNotEmpty) ...[
                                  const SizedBox(width: FluentSpacing.s),
                                  Expanded(
                                    child: Text(
                                      card.why!,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        height: 1.35,
                                        color: isDark
                                            ? Colors.white54
                                            : Colors.black54,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: FluentSpacing.s),

                            // Front (Question / Concept)
                            Text(
                              'সামনে: ${card.front}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: FluentSpacing.s),

                            // Back (Formula / Rule)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(FluentSpacing.s),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF0F172A)
                                    : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                card.back,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.4,
                                  color: isDark
                                      ? Colors.indigo.shade200
                                      : Colors.indigo.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: FluentSpacing.m),

        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: scheme.primary,
            foregroundColor: scheme.onPrimary,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: FluentSpacing.m),
            shape: RoundedRectangleBorder(
              borderRadius: FluentRadius.controlBorder,
            ),
          ),
          icon: const Icon(Icons.check, size: 18),
          label: Text(
            'ফ্ল্যাশ কার্ডে যুক্ত করুন ($selectedCountটি)',
            style: FluentType.bodyStrong,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          onPressed: selectedCount == 0 ? null : _saveCards,
        ),
      ],
    );
  }
}
