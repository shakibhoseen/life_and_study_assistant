import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/services/media/image_preprocessor_service.dart';
import '../../../../core/services/media/local_ocr_service.dart';
import '../../../../core/services/media/ocr_text_cleaner.dart';
import '../../../../core/services/media/photo_capture_service.dart';
import 'layout_debug_screen.dart';

/// Screen for local, offline Optical Character Recognition (OCR).
///
/// Supports Bengali, Math, and English text extraction with lightweight
/// image pre-processing (Grayscale, Contrast Boost, Binarization).
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
        const SnackBar(content: Text('অনুগ্রহ করে প্রথমে একটি ছবি নির্বাচন করুন')),
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
          _errorMessage =
              'ছবি থেকে কোনো লেখা শনাক্ত করা যায়নি। আলো বাড়িয়ে বা গ্রেস্কেল/কন্ট্রাস্ট ফিল্টার ব্যবহার করে আবার চেষ্টা করুন।';
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'ইমেজ টু টেক্সট (অফলাইন)',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status & Info Header
            _buildHeaderCard(isDark),
            const SizedBox(height: 14),

            // Image Picker / Preview Section
            if (_originalImage == null)
              _buildEmptyPickerCard(isDark, primaryColor)
            else
              _buildImagePreviewCard(isDark),

            const SizedBox(height: 16),

            // Pre-processing filter selector
            if (_originalImage != null) ...[
              _buildFilterSelector(isDark),
              const SizedBox(height: 14),
              _buildLayoutSelector(isDark),
              const SizedBox(height: 14),
              _buildLanguageSelector(isDark),
              const SizedBox(height: 16),
              _buildExtractButton(primaryColor),
              const SizedBox(height: 18),
            ],

            // Error display
            if (_errorMessage != null) ...[
              _buildErrorBanner(_errorMessage!),
              const SizedBox(height: 14),
            ],

            // Extracted text display area
            if (_textController.text.isNotEmpty || _isExtractingText)
              _buildExtractedTextCard(isDark),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFBFDBFE),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.offline_bolt_rounded,
              color: Colors.blueAccent,
              size: 22,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '১০০% অফলাইন • কোনো ক্লাউড AI নেই',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'বাংলা, অঙ্ক ও ইংরেজি টেক্সট সরাসরি ডিভাইসেই এক্সট্র্যাক্ট হয়। গ্রেস্কেল ও কন্ট্রাস্ট ব্যবহারে অ্যাকুরেসি বাড়ে।',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyPickerCard(bool isDark, Color primaryColor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.document_scanner_rounded,
              size: 44,
              color: primaryColor,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'ছবি থেকে লেখা বের করুন',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'বই, নোট বা প্রশ্নপত্রের ছবি তুলুন অথবা গ্যালারি থেকে সিলেক্ট করুন',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: () => _pickImage(ImageSource.camera),
                icon: const Icon(Icons.camera_alt_rounded, size: 18),
                label: const Text('ক্যামেরা'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => _pickImage(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_rounded, size: 18),
                label: const Text('গ্যালারি'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildImagePreviewCard(bool isDark) {
    final displayFile = _processedImage ?? _originalImage!;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.image_outlined, size: 18, color: Colors.indigo),
                    SizedBox(width: 6),
                    Text(
                      'ছবির প্রিভিউ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: _isProcessingImage ? null : _rotateImage,
                      icon: const Icon(Icons.rotate_right_rounded, size: 16),
                      label: const Text('ঘোরান', style: TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 2),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: () => _pickImage(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt, size: 15),
                      label: const Text('নতুন ছবি', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  constraints: const BoxConstraints(maxHeight: 260),
                  width: double.infinity,
                  color: isDark ? Colors.black26 : const Color(0xFFF8FAFC),
                  child: Image.file(
                    displayFile,
                    fit: BoxFit.contain,
                  ),
                ),
                if (_isProcessingImage)
                  Container(
                    color: Colors.black45,
                    padding: const EdgeInsets.all(16),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: 10),
                        Text(
                          'ফিল্টার প্রয়োগ হচ্ছে...',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
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

  Widget _buildFilterSelector(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.tune_rounded, size: 16, color: Colors.teal),
              SizedBox(width: 6),
              Text(
                'ইমেজ অপ্টিমাইজেশন (ফিল্টার)',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip(
                  label: 'হাই-কন্ট্রাস্ট (সুপারিশ)',
                  mode: ImageFilterMode.enhancedContrast,
                  icon: Icons.contrast,
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  label: 'গ্রেস্কেল (সাদা-কালো)',
                  mode: ImageFilterMode.grayscale,
                  icon: Icons.filter_b_and_w_rounded,
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  label: 'বাইনারাইজড (B&W)',
                  mode: ImageFilterMode.binarized,
                  icon: Icons.brightness_medium_rounded,
                ),
                const SizedBox(width: 8),
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
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      onSelected: _isProcessingImage ? null : (_) => _applyFilter(mode),
    );
  }

  Widget _buildLayoutSelector(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.view_column_rounded, size: 16, color: Colors.blueAccent),
              SizedBox(width: 6),
              Text(
                'পৃষ্ঠা লেআউট (কলাম মোড)',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: OcrLayoutMode.values.map((layout) {
                final isSelected = _selectedLayout == layout;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(
                      layout.label,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
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
          const SizedBox(height: 6),
          Text(
            _selectedLayout.description,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageSelector(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.translate_rounded, size: 16, color: Colors.purple),
              SizedBox(width: 6),
              Text(
                'ভাষা ও টাইপ নির্বাচন',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: OcrLanguagePreset.values.map((preset) {
                final isSelected = _selectedLanguage == preset;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(
                      preset.label,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
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
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
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
          _isExtractingText ? 'টেক্সট এক্সট্র্যাক্ট হচ্ছে...' : 'টেক্সট এক্সট্র্যাক্ট করুন ⚡',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.red, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExtractedTextCard(bool isDark) {
    final text = _textController.text;
    final charCount = text.length;
    final wordCount =
        text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline_rounded,
                      size: 18,
                      color: Colors.green,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'শনাক্তকৃত টেক্সট ($wordCount শব্দ, $charCount অক্ষর)',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
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
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _textController,
              maxLines: null,
              minLines: 5,
              style: const TextStyle(fontSize: 14, height: 1.5),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'এখানে এক্সট্র্যাক্ট করা টেক্সট প্রদর্শিত হবে...',
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                OutlinedButton.icon(
                  onPressed: _cleanExtractedText,
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 14),
                  label: const Text('সাজিয়ে নিন ✨', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _copyToClipboard,
                  icon: const Icon(Icons.copy, size: 14),
                  label: const Text('কপি', style: TextStyle(fontSize: 12)),
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
