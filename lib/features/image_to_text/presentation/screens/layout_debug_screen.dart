import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:local_ocr/local_ocr.dart';

import '../../../../core/services/media/layout/layout_detection_models.dart';
import '../../../../core/services/media/layout/layout_detection_service.dart';
import '../../../../core/services/media/segmentation/question_segmentation_service.dart';
import '../../../../core/services/media/segmentation/segmentation_models.dart';

/// Interactive Debug Screen for Phase 1: Layout Detection & Phase 2: MCQ Segmentation.
///
/// Visualizes original image, deskew angle, gutter coordinates, column bounding boxes,
/// extracted column crops, and segmented questions/options.
class LayoutDebugScreen extends StatefulWidget {
  final File? initialImage;

  const LayoutDebugScreen({super.key, this.initialImage});

  @override
  State<LayoutDebugScreen> createState() => _LayoutDebugScreenState();
}

class _LayoutDebugScreenState extends State<LayoutDebugScreen>
    with SingleTickerProviderStateMixin {
  File? _currentImage;
  LayoutAnalysisResult? _analysis;
  PageSegmentationResult? _segmentationResult;
  bool _isAnalyzing = false;
  bool _isSegmenting = false;
  String? _errorMessage;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    if (widget.initialImage != null) {
      _currentImage = widget.initialImage;
      _runAnalysis(_currentImage!);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
      );
      if (picked == null) return;

      final file = File(picked.path);
      setState(() {
        _currentImage = file;
        _segmentationResult = null;
      });
      await _runAnalysis(file);
    } catch (e) {
      setState(() {
        _errorMessage = 'ছবি লোড করতে ব্যর্থ: $e';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ছবি লোড করতে ব্যর্থ: $e')),
        );
      }
    }
  }

  Future<void> _runAnalysis(File file) async {
    setState(() {
      _isAnalyzing = true;
      _errorMessage = null;
      _segmentationResult = null;
    });

    try {
      final result = await LayoutDetectionService.instance.analyzeLayout(file);
      if (!mounted) return;
      setState(() {
        _analysis = result;
        _isAnalyzing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isAnalyzing = false;
        _errorMessage = 'লেআউট বিশ্লেষণ ব্যর্থ: $e';
      });
    }
  }

  Future<void> _runSegmentation() async {
    if (_analysis == null) return;
    setState(() {
      _isSegmenting = true;
      _errorMessage = null;
    });

    try {
      final crops = _analysis!.columnCrops.isNotEmpty
          ? _analysis!.columnCrops
          : [_analysis!.deskewedImage];

      final columnLines = <int, List<TextLineBox>>{};

      for (int i = 0; i < crops.length; i++) {
        final hocr = await LocalOcr.extractHocr(crops[i].path);
        columnLines[i] = QuestionSegmentationService.parseHocrToLines(
          hocrText: hocr,
          columnId: i,
        );
      }

      final segResult = await QuestionSegmentationService.instance.segmentPage(
        layout: _analysis!,
        columnLines: columnLines,
        originalImageFile: _analysis!.originalImage,
      );

      if (!mounted) return;
      setState(() {
        _segmentationResult = segResult;
        _isSegmenting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSegmenting = false;
        _errorMessage = 'সেগমেন্টেশন ব্যর্থ: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Layout Debugger 🔬 (Phase 1)',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.photo_library_outlined),
            tooltip: 'গ্যালারি',
            onPressed: () => _pickImage(ImageSource.gallery),
          ),
          IconButton(
            icon: const Icon(Icons.camera_alt_outlined),
            tooltip: 'ক্যামেরা',
            onPressed: () => _pickImage(ImageSource.camera),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.layers_outlined, size: 18), text: 'Bounding Boxes & Gutter'),
            Tab(icon: Icon(Icons.crop, size: 18), text: 'Column Crops'),
            Tab(icon: Icon(Icons.quiz_outlined, size: 18), text: 'MCQ Blocks (Phase 2)'),
            Tab(icon: Icon(Icons.rotate_90_degrees_ccw_outlined, size: 18), text: 'Deskewed'),
            Tab(icon: Icon(Icons.image_outlined, size: 18), text: 'Original'),
          ],
        ),
      ),
      body: _isAnalyzing
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 14),
                  Text('লেআউট ও গাটার বিশ্লেষণ হচ্ছে...'),
                ],
              ),
            )
          : _analysis == null
              ? _buildEmptyState(primaryColor)
              : Column(
                  children: [
                    _buildMetricsHeader(isDark),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildOverlayView(),
                          _buildCropsView(isDark),
                          _buildMcqBlocksView(isDark),
                          _buildSingleImageView(_analysis!.deskewedImage),
                          _buildSingleImageView(_analysis!.originalImage),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildEmptyState(Color primaryColor) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.view_column_rounded, size: 56, color: primaryColor),
            const SizedBox(height: 14),
            const Text(
              'লেআউট ডিটেকশন ও বেঞ্চমার্ক',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'গ্যালারি বা ক্যামেরা থেকে একটি ছবি বেছে নিয়ে Deskew, Gutter এবং Bounding Box ভিজ্যুয়ালাইজ করুন।',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => _pickImage(ImageSource.gallery),
              icon: const Icon(Icons.photo_library),
              label: const Text('ছবি নির্বাচন করুন'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsHeader(bool isDark) {
    final a = _analysis!;
    final confPercent = (a.confidence * 100).toStringAsFixed(1);
    final confColor = a.confidence >= 0.70
        ? Colors.green
        : (a.confidence >= 0.50 ? Colors.amber : Colors.red);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: a.isDualColumn
                        ? Colors.blue.withValues(alpha: 0.15)
                        : Colors.purple.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: a.isDualColumn ? Colors.blue : Colors.purple,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        a.isDualColumn
                            ? Icons.view_column_rounded
                            : Icons.article_outlined,
                        size: 14,
                        color: a.isDualColumn ? Colors.blue : Colors.purple,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          a.layoutType.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: a.isDualColumn ? Colors.blue : Colors.purple,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _buildPill(
                label: 'Skew: ${a.skewAngle >= 0 ? "+" : ""}${a.skewAngle.toStringAsFixed(1)}°',
                color: a.skewAngle.abs() > 0.5 ? Colors.orange : Colors.grey,
              ),
              const SizedBox(width: 8),
              _buildPill(
                label: 'Confidence: $confPercent%',
                color: confColor,
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (_errorMessage != null) ...[
            Text(
              'ত্রুটি: $_errorMessage',
              style: const TextStyle(fontSize: 11, color: Colors.red),
            ),
          ] else if (a.gutter != null) ...[
            Text(
              'Gutter: x = ${a.gutter!.left} .. ${a.gutter!.right} (Center: ${a.gutter!.center}px, Width: ${a.gutter!.width}px)',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ] else if (a.failureReason != null) ...[
            Text(
              'Fallback: ${a.failureReason}',
              style: const TextStyle(fontSize: 11, color: Colors.orange),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPill({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Widget _buildOverlayView() {
    final a = _analysis!;
    return LayoutBuilder(
      builder: (context, constraints) {
        return InteractiveViewer(
          maxScale: 4.0,
          child: Center(
            child: CustomPaint(
              foregroundPainter: _LayoutOverlayPainter(
                analysis: a,
                renderedSize: Size(constraints.maxWidth, constraints.maxHeight),
              ),
              child: Image.file(
                a.deskewedImage,
                fit: BoxFit.contain,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCropsView(bool isDark) {
    final crops = _analysis!.columnCrops;
    if (crops.isEmpty) {
      return const Center(child: Text('কোনো কলাম ক্রপ পাওয়া যায়নি'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: crops.length,
      itemBuilder: (context, idx) {
        final crop = crops[idx];
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: idx == 0
                      ? Colors.blue.withValues(alpha: 0.15)
                      : Colors.green.withValues(alpha: 0.15),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'কলাম #${idx + 1} (${idx == 0 ? "বাম পাশ" : "ডান পাশ"})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: idx == 0 ? Colors.blue : Colors.green,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(crop.lengthSync() / 1024).toStringAsFixed(1)} KB',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              ClipRRect(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                child: InteractiveViewer(
                  maxScale: 3.0,
                  child: Image.file(crop, fit: BoxFit.contain),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMcqBlocksView(bool isDark) {
    if (_isSegmenting) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 14),
            Text('MCQ প্রশ্ন ও অপশন সেগমেন্টেশন হচ্ছে...'),
          ],
        ),
      );
    }

    if (_segmentationResult == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.quiz_outlined, size: 48, color: Colors.blueAccent),
              const SizedBox(height: 12),
              const Text(
                'Phase 2: Question & Option Segmentation',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 6),
              const Text(
                'প্রতিটি কলাম থেকে প্রশ্ন নম্বর, প্রশ্ন টেক্সট ও অপশন ব্লক আলাদা করুন।',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: _runSegmentation,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('MCQ সেগমেন্টেশন চালান'),
              ),
            ],
          ),
        ),
      );
    }

    final seg = _segmentationResult!;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blueAccent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Flexible(
                child: Text(
                  'মোট প্রশ্ন: ${seg.totalQuestions}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              Flexible(
                child: Text(
                  'নিখুঁত ৪-অপশন: ${seg.validMcqCount}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.green,
                  ),
                ),
              ),
              Flexible(
                child: Text(
                  'রিভিউ প্রয়োজন: ${seg.reviewCount}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: seg.reviewCount > 0 ? Colors.orange : Colors.grey,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ...seg.questions.map((q) => _buildQuestionBlockCard(q, isDark)),
        if (seg.orphanBlocks.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text(
            'অসংলগ্ন / হেডার টেক্সট ব্লক (অক্ষত সংরক্ষিত):',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          ...seg.orphanBlocks.map((o) => _buildOrphanBlockCard(o, isDark)),
        ],
      ],
    );
  }

  Widget _buildQuestionBlockCard(SegmentedQuestionBlock q, bool isDark) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      q.questionNumber.isNotEmpty ? 'প্রশ্ন ${q.questionNumber}' : 'নম্বরহীন',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'কলাম ${q.columnId + 1}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
                const Spacer(),
                if (q.hasDiagram) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'চিত্র/ম্যাথ 🖼️',
                      style: TextStyle(fontSize: 10, color: Colors.purple, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                if (q.reviewRequired)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'রিভিউ ⚠️',
                      style: TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              q.questionText,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 8),
            ...List.generate(q.options.length, (optIdx) {
              final marker = optIdx < q.optionMarkers.length ? q.optionMarkers[optIdx] : '';
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      marker.isNotEmpty ? '($marker) ' : '• ',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    Expanded(
                      child: Text(q.options[optIdx], style: const TextStyle(fontSize: 13)),
                    ),
                  ],
                ),
              );
            }),
            if (q.reviewReasons.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'কারণ: ${q.reviewReasons.join(", ")}',
                style: const TextStyle(fontSize: 11, color: Colors.orange),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              'BBox: ${q.boundingBox.left}, ${q.boundingBox.top} (${q.boundingBox.width}x${q.boundingBox.height}) | Conf: ${(q.segmentationConfidence * 100).toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrphanBlockCard(SegmentedQuestionBlock o, bool isDark) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isDark ? Colors.grey[850] : Colors.grey[100],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Text(
          o.questionText,
          style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
        ),
      ),
    );
  }

  Widget _buildSingleImageView(File file) {
    return InteractiveViewer(
      maxScale: 4.0,
      child: Center(
        child: Image.file(file, fit: BoxFit.contain),
      ),
    );
  }
}

/// Custom painter to draw gutter overlay and column bounding boxes on the image.
class _LayoutOverlayPainter extends CustomPainter {
  final LayoutAnalysisResult analysis;
  final Size renderedSize;

  _LayoutOverlayPainter({
    required this.analysis,
    required this.renderedSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width == 0 || size.height == 0) return;

    final scaleX = size.width / analysis.imageWidth;
    final scaleY = size.height / analysis.imageHeight;

    // 1. Draw Gutter if present
    if (analysis.gutter != null) {
      final g = analysis.gutter!;
      final gutterRect = Rect.fromLTRB(
        g.left * scaleX,
        0,
        g.right * scaleX,
        size.height,
      );

      final gutterPaint = Paint()
        ..color = Colors.orange.withValues(alpha: 0.35)
        ..style = PaintingStyle.fill;

      canvas.drawRect(gutterRect, gutterPaint);

      // Gutter center dashed line
      final linePaint = Paint()
        ..color = Colors.deepOrange
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;

      canvas.drawLine(
        Offset(g.center * scaleX, 0),
        Offset(g.center * scaleX, size.height),
        linePaint,
      );
    }

    // 2. Draw Column Bounding Boxes
    for (final box in analysis.columnBoxes) {
      final rect = Rect.fromLTWH(
        box.left * scaleX,
        box.top * scaleY,
        box.width * scaleX,
        box.height * scaleY,
      );

      final boxColor = box.index == 0 ? Colors.blue : Colors.green;

      final borderPaint = Paint()
        ..color = boxColor
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke;

      canvas.drawRect(rect, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LayoutOverlayPainter oldDelegate) {
    return oldDelegate.analysis != analysis;
  }
}
