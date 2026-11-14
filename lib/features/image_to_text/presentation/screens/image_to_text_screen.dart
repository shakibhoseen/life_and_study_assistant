import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/services/media/image_preprocessor_service.dart';
import '../../../../core/services/media/local_ocr_service.dart';
import '../../../../core/services/media/ocr_text_cleaner.dart';
import '../../../../core/services/media/photo_capture_service.dart';
import '../../../../core/theme/fluent_tokens.dart';
import '../../../../core/widgets/premium_glass_card.dart';
import 'layout_debug_screen.dart';

/// Screen for local, offline Optical Character Recognition (OCR).
///
/// Supports Bengali, Math, and English text extraction with lightweight
/// image pre-processing (Grayscale, Contrast Boost, Binarization).
/// Status colours with a light-mode and a dark-mode value that reads on
/// either surface.
Color _okColour(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF4ADE80)
    : const Color(0xFF15803D);

Color _errorColour(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFFF87171)
    : const Color(0xFFB91C1C);

class ImageToTextScreen extends StatefulWidget {
  const ImageToTextScreen({super.key});

  @override
  State<ImageToTextScreen> createState() => _ImageToTextScreenState();
}

class _ImageToTextScreenState extends State<ImageToTextScreen> {
  File? _originalImage;
  File? _processedImage;
  ImageFilterMode _selectedFilter = ImageFilterMode.enhancedContrast;
  OcrLanguagePreset _selectedLanguage = OcrLanguagePreset.bengaliMathEnglish;
  OcrLayoutMode _selectedLayout = OcrLayoutMode.twoColumnsBook;

  bool _isProcessingImage = false;
  bool _isExtractingText = false;
  String? _errorMessage;

  final TextEditingController _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    setState(() {
      _errorMessage = null;
    });

    try {
      final cropped = await PhotoCaptureService.instance.captureAndCrop(
        source: source,
        context: context,
        title: 'প্রয়োজনীয় অংশ কাটুন',
      );

      if (cropped == null) return;

      setState(() {
        _originalImage = cropped;
        _isProcessingImage = true;
      });

      await _applyFilter(_selectedFilter);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'ছবি লোড করতে সমস্যা হয়েছে: $e';
        _isProcessingImage = false;
      });
    }
  }

  Future<void> _rotateImage() async {
    if (_originalImage == null || _isProcessingImage) return;

    setState(() {
      _isProcessingImage = true;
    });

    try {
      final rotated = await PhotoCaptureService.instance.rotateQuarterTurn(
        _originalImage!,
        clockwise: true,
      );

      _originalImage = rotated;
      await _applyFilter(_selectedFilter);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessingImage = false;
        _errorMessage = 'ছবি ঘোরাতে সমস্যা হয়েছে: $e';
      });
    }
  }

  Future<void> _applyFilter(ImageFilterMode mode) async {
    if (_originalImage == null) return;

    setState(() {
      _selectedFilter = mode;
      _isProcessingImage = true;
      _errorMessage = null;
    });

    try {
      final processed = await ImagePreprocessorService.instance.processImage(
        inputFile: _originalImage!,
        filterMode: mode,
      );

      if (!mounted) return;
      setState(() {
        _processedImage = processed;
        _isProcessingImage = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _processedImage = _originalImage;
        _isProcessingImage = false;
        _errorMessage = 'প্রি-প্রসেসিং করতে সমস্যা হয়েছে: $e';
      });
    }
  }

  Future<void> _extractText() async {
    final imageToScan = _processedImage ?? _originalImage;
    if (imageToScan == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('অনুগ্রহ করে প্রথমে একটি ছবি নির্বাচন করুন'),
        ),
      );
      return;
    }

    setState(() {
      _isExtractingText = true;
      _errorMessage = null;
    });

    try {
      final result = await LocalOcrService.instance.extractText(
        imageFile: imageToScan,
        languagePreset: _selectedLanguage,
        layoutMode: _selectedLayout,
      );

      if (!mounted) return;
      setState(() {
        _textController.text = result;
        _isExtractingText = false;
      });

      if (result.isEmpty) {
        setState(() {
          _errorMessage = 'ছবি থেকে কোনো লেখা শনাক্ত করা যায়নি। আলো বাড়িয়ে বা গ্রেস্কেল/কন্ট্রাস্ট ফিল্টার ব্যবহার করে আবার চেষ্টা করুন।';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isExtractingText = false;
        _errorMessage = 'টেক্সট এক্সট্র্যাক্ট করতে সমস্যা হয়েছে: $e';
      });
    }
  }

  void _copyToClipboard() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('টেক্সট ক্লিপবোর্ডে কপি করা হয়েছে! 📋'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _cleanExtractedText() {
    final text = _textController.text;
    if (text.trim().isEmpty) return;

    final cleaned = OcrTextCleaner.clean(text);
    setState(() {
      _textController.text = cleaned;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('টেক্সট ও অপশনগুলো সুন্দরভাবে সাজানো হয়েছে ✨'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _clearAll() {
    setState(() {
      _originalImage = null;
      _processedImage = null;
      _textController.clear();
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'ইমেজ টু টেক্সট (অফলাইন)',
          style: FluentType.subtitle.copyWith(fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics_outlined),
            tooltip: 'লেআউট ডিবাগ ও কলাম ভিউ (Phase 1)',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LayoutDebugScreen(
                    initialImage: _processedImage ?? _originalImage,
                  ),
                ),
              );
            },
          ),
          if (_originalImage != null || _textController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'রিসেট করুন',
              onPressed: _clearAll,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: FluentSpacing.l,
          vertical: FluentSpacing.m,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status & Info Header
            _buildHeaderCard(),
            const SizedBox(height: FluentSpacing.m),

            // Image Picker / Preview Section
            if (_originalImage == null)
              _buildEmptyPickerCard(primaryColor)
            else
              _buildImagePreviewCard(),

            const SizedBox(height: FluentSpacing.l),

            // Pre-processing filter selector
            if (_originalImage != null) ...[
              _buildFilterSelector(),
              const SizedBox(height: FluentSpacing.m),
              _buildLayoutSelector(),
              const SizedBox(height: FluentSpacing.m),
              _buildLanguageSelector(),
              const SizedBox(height: FluentSpacing.l),
              _buildExtractButton(primaryColor),
              const SizedBox(height: FluentSpacing.xl),
            ],

            // Error display
            if (_errorMessage != null) ...[
              _buildErrorBanner(_errorMessage!),
              const SizedBox(height: FluentSpacing.m),
            ],

            // Extracted text display area
            if (_textController.text.isNotEmpty || _isExtractingText)
              _buildExtractedTextCard(),

            const SizedBox(height: FluentSpacing.xxl),
          ],
        ),
      ),
    );
  }

  /// The Fluent card surface: solid layer, 1px stroke, 8px radius, shadow2.
  BoxDecoration _cardDecoration(BuildContext context) {
    final theme = Theme.of(context);
    return BoxDecoration(
      color: theme.cardTheme.color ?? theme.cardColor,
      borderRadius: FluentRadius.cardBorder,
      border: Border.all(
        color: FluentStroke.card(theme.brightness),
        width: FluentStroke.width,
      ),
      boxShadow: FluentElevation.card(theme.brightness),
    );
  }

  Widget _buildHeaderCard() {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final onSurface = theme.colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.all(FluentSpacing.m),
      decoration: BoxDecoration(
        color: FluentLayer.subtle(primary, theme.brightness),
        borderRadius: FluentRadius.cardBorder,
        border: Border.all(
          color: FluentStroke.card(theme.brightness),
          width: FluentStroke.width,
        ),
      ),
      child: Row(
        children: [
          PremiumIconBadge(
            icon: Icons.offline_bolt_rounded,
            size: 36,
            iconSize: 20,
            color: primary,
          ),
          const SizedBox(width: FluentSpacing.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '১০০% অফলাইন • কোনো ক্লাউড AI নেই',
                  style: FluentType.bodyStrong.copyWith(color: onSurface),
                ),
                const SizedBox(height: FluentSpacing.xxs),
                Text(
                  'বাংলা, অঙ্ক ও ইংরেজি টেক্সট সরাসরি ডিভাইসেই এক্সট্র্যাক্ট হয়। গ্রেস্কেল ও কন্ট্রাস্ট ব্যবহারে অ্যাকুরেসি বাড়ে।',
                  style: FluentType.caption.copyWith(
                    color: onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyPickerCard(Color primaryColor) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: FluentSpacing.xxl + FluentSpacing.m,
        horizontal: FluentSpacing.xl,
      ),
      decoration: _cardDecoration(context),
      child: Column(
        children: [
          PremiumIconBadge(
            icon: Icons.document_scanner_rounded,
            size: 72,
            iconSize: 40,
            color: primaryColor,
          ),
          const SizedBox(height: FluentSpacing.l),
          Text(
            'ছবি থেকে লেখা বের করুন',
            style: FluentType.bodyStrong.copyWith(
              fontSize: 16,
              color: onSurface,
            ),
          ),
          const SizedBox(height: FluentSpacing.s),
          Text(
            'বই, নোট বা প্রশ্নপত্রের ছবি তুলুন অথবা গ্যালারি থেকে সিলেক্ট করুন',
            textAlign: TextAlign.center,
            style: FluentType.caption.copyWith(
              color: onSurface.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: FluentSpacing.xl),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: () => _pickImage(ImageSource.camera),
                icon: const Icon(Icons.camera_alt_rounded, size: 18),
                label: const Text('ক্যামেরা'),
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: FluentSpacing.l,
                    vertical: FluentSpacing.m,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: FluentRadius.controlBorder,
                  ),
                ),
              ),
              const SizedBox(width: FluentSpacing.m),
              OutlinedButton.icon(
                onPressed: () => _pickImage(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_rounded, size: 18),
                label: const Text('গ্যালারি'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FluentSpacing.l,
                    vertical: FluentSpacing.m,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: FluentRadius.controlBorder,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildImagePreviewCard() {
    final displayFile = _processedImage ?? _originalImage!;
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    return Container(
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: FluentSpacing.m,
              vertical: FluentSpacing.s,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.image_outlined,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: FluentSpacing.s),
                      Flexible(
                        child: Text(
                          'ছবির প্রিভিউ',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: FluentType.bodyStrong.copyWith(
                            color: onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: FluentSpacing.s),
                Row(
                  children: [
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: FluentSpacing.s,
                        ),
                      ),
                      onPressed: _isProcessingImage ? null : _rotateImage,
                      icon: const Icon(Icons.rotate_right_rounded, size: 16),
                      label: const Text('ঘোরান', style: FluentType.caption),
                    ),
                    const SizedBox(width: FluentSpacing.xs),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: FluentSpacing.s,
                        ),
                      ),
                      onPressed: () => _pickImage(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt, size: 15),
                      label: const Text('নতুন ছবি', style: FluentType.caption),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Divider(height: 1, color: FluentStroke.divider(theme.brightness)),
          ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(FluentRadius.card),
              bottomRight: Radius.circular(FluentRadius.card),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  constraints: const BoxConstraints(maxHeight: 260),
                  width: double.infinity,
                  color: onSurface.withValues(alpha: 0.05),
                  child: Image.file(displayFile, fit: BoxFit.contain),
                ),
                if (_isProcessingImage)
                  Container(
                    color: Colors.black45,
                    padding: const EdgeInsets.all(FluentSpacing.l),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: FluentSpacing.s),
                        Flexible(
                          child: Text(
                            'ফিল্টার প্রয়োগ হচ্ছে...',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FluentType.caption.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterSelector() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(FluentSpacing.m),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: FluentRadius.cardBorder,
        border: Border.all(
          color: FluentStroke.card(theme.brightness),
          width: FluentStroke.width,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.tune_rounded,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              SizedBox(width: FluentSpacing.s),
              Expanded(
                child: Text(
                  'ইমেজ অপ্টিমাইজেশন (ফিল্টার)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FluentType.bodyStrong,
                ),
              ),
            ],
          ),
          const SizedBox(height: FluentSpacing.s),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip(
                  label: 'হাই-কন্ট্রাস্ট (সুপারিশ)',
                  mode: ImageFilterMode.enhancedContrast,
                  icon: Icons.contrast,
                ),
                const SizedBox(width: FluentSpacing.s),
                _buildFilterChip(
                  label: 'গ্রেস্কেল (সাদা-কালো)',
                  mode: ImageFilterMode.grayscale,
                  icon: Icons.filter_b_and_w_rounded,
                ),
                const SizedBox(width: FluentSpacing.s),
                _buildFilterChip(
                  label: 'বাইনারাইজড (B&W)',
                  mode: ImageFilterMode.binarized,
                  icon: Icons.brightness_medium_rounded,
                ),
                const SizedBox(width: FluentSpacing.s),
                _buildFilterChip(
                  label: 'মূল ছবি (Original)',
                  mode: ImageFilterMode.none,
                  icon: Icons.image_outlined,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required ImageFilterMode mode,
    required IconData icon,
  }) {
    final isSelected = _selectedFilter == mode;

    return ChoiceChip(
      avatar: Icon(icon, size: 14),
      label: Text(
        label,
        style: FluentType.caption.copyWith(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      onSelected: _isProcessingImage ? null : (_) => _applyFilter(mode),
    );
  }

  Widget _buildLayoutSelector() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(FluentSpacing.m),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: FluentRadius.cardBorder,
        border: Border.all(
          color: FluentStroke.card(theme.brightness),
          width: FluentStroke.width,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.view_column_rounded,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              SizedBox(width: FluentSpacing.s),
              Expanded(
                child: Text(
                  'পৃষ্ঠা লেআউট (কলাম মোড)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FluentType.bodyStrong,
                ),
              ),
            ],
          ),
          const SizedBox(height: FluentSpacing.s),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: OcrLayoutMode.values.map((layout) {
                final isSelected = _selectedLayout == layout;
                return Padding(
                  padding: const EdgeInsets.only(right: FluentSpacing.s),
                  child: ChoiceChip(
                    label: Text(
                      layout.label,
                      style: FluentType.caption.copyWith(
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    selected: isSelected,
                    onSelected: (val) {
                      if (val) {
                        setState(() {
                          _selectedLayout = layout;
                        });
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: FluentSpacing.s),
          Text(
            _selectedLayout.description,
            style: FluentType.caption.copyWith(
              color: Theme.of(context).colorScheme.onSurface
                  .withValues(alpha: 0.65),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageSelector() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(FluentSpacing.m),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: FluentRadius.cardBorder,
        border: Border.all(
          color: FluentStroke.card(theme.brightness),
          width: FluentStroke.width,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.translate_rounded,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              SizedBox(width: FluentSpacing.s),
              Expanded(
                child: Text(
                  'ভাষা ও টাইপ নির্বাচন',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FluentType.bodyStrong,
                ),
              ),
            ],
          ),
          const SizedBox(height: FluentSpacing.s),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: OcrLanguagePreset.values.map((preset) {
                final isSelected = _selectedLanguage == preset;
                return Padding(
                  padding: const EdgeInsets.only(right: FluentSpacing.s),
                  child: ChoiceChip(
                    label: Text(
                      preset.label,
                      style: FluentType.caption.copyWith(
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    selected: isSelected,
                    onSelected: (val) {
                      if (val) {
                        setState(() {
                          _selectedLanguage = preset;
                        });
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExtractButton(Color primaryColor) {
    return SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        onPressed: (_isExtractingText || _isProcessingImage)
            ? null
            : _extractText,
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: FluentRadius.controlBorder,
          ),
          elevation: 0,
        ),
        icon: _isExtractingText
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.text_fields_rounded, size: 20),
        label: Text(
          _isExtractingText
              ? 'টেক্সট এক্সট্র্যাক্ট হচ্ছে...'
              : 'টেক্সট এক্সট্র্যাক্ট করুন ⚡',
          style: FluentType.bodyStrong,
        ),
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(FluentSpacing.m),
      decoration: BoxDecoration(
        color: FluentLayer.subtle(
          _errorColour(context),
          Theme.of(context).brightness,
        ),
        borderRadius: FluentRadius.cardBorder,
        border: Border.all(
          color: _errorColour(context).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: _errorColour(context),
            size: 20,
          ),
          const SizedBox(width: FluentSpacing.s),
          Expanded(
            child: Text(
              message,
              style: FluentType.caption.copyWith(color: _errorColour(context)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExtractedTextCard() {
    final theme = Theme.of(context);
    final text = _textController.text;
    final charCount = text.length;
    final wordCount = text.trim().isEmpty
        ? 0
        : text.trim().split(RegExp(r'\s+')).length;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: FluentRadius.cardBorder,
        border: Border.all(
          color: FluentStroke.card(theme.brightness),
          width: FluentStroke.width,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: FluentSpacing.l,
              vertical: FluentSpacing.m,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline_rounded,
                        size: 18,
                        color: _okColour(context),
                      ),
                      const SizedBox(width: FluentSpacing.s),
                      Flexible(
                        child: Text(
                          'শনাক্তকৃত টেক্সট ($wordCount শব্দ, $charCount অক্ষর)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: FluentType.bodyStrong,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: FluentSpacing.s),
                if (text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    tooltip: 'কপি করুন',
                    onPressed: _copyToClipboard,
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(FluentSpacing.m),
            child: TextField(
              controller: _textController,
              maxLines: null,
              minLines: 5,
              style: FluentType.body,
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'এখানে এক্সট্র্যাক্ট করা টেক্সট প্রদর্শিত হবে...',
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: FluentSpacing.m,
              vertical: FluentSpacing.s,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                OutlinedButton.icon(
                  onPressed: _cleanExtractedText,
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 14),
                  label: const Text('সাজিয়ে নিন ✨', style: FluentType.caption),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _copyToClipboard,
                  icon: const Icon(Icons.copy, size: 14),
                  label: const Text('কপি', style: FluentType.caption),
                  style: ElevatedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
