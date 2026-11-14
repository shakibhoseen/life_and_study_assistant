import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/theme/fluent_tokens.dart';

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
/// Status colours for the debug readout, each with a light-mode and a
/// dark-mode value that reads on either surface.
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
      final picked = await ImagePicker().pickImage(source: source);
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('ছবি লোড করতে ব্যর্থ: $e')));
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
        title: Text(
          'Layout Debugger 🔬 (Phase 1)',
          style: FluentType.subtitle.copyWith(fontSize: 16),
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
            Tab(
              icon: Icon(Icons.layers_outlined, size: 18),
              text: 'Bounding Boxes & Gutter',
            ),
            Tab(icon: Icon(Icons.crop, size: 18), text: 'Column Crops'),
            Tab(
              icon: Icon(Icons.quiz_outlined, size: 18),
              text: 'MCQ Blocks (Phase 2)',
            ),
            Tab(
              icon: Icon(Icons.rotate_90_degrees_ccw_outlined, size: 18),
              text: 'Deskewed',
            ),
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
                  SizedBox(height: FluentSpacing.l),
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
        padding: const EdgeInsets.all(FluentSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.view_column_rounded, size: 56, color: primaryColor),
            const SizedBox(height: FluentSpacing.l),
            Text(
              'লেআউট ডিটেকশন ও বেঞ্চমার্ক',
              style: FluentType.subtitle.copyWith(fontSize: 18),
            ),
            const SizedBox(height: FluentSpacing.s),
            Text(
              'গ্যালারি বা ক্যামেরা থেকে একটি ছবি বেছে নিয়ে Deskew, Gutter এবং Bounding Box ভিজ্যুয়ালাইজ করুন।',
              textAlign: TextAlign.center,
              style: FluentType.body.copyWith(
                color: Theme.of(context).colorScheme.onSurface
                    .withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: FluentSpacing.xl),
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
        ? _okColour(context)
        : (a.confidence >= 0.50 ? _warnColour(context) : _badColour(context));

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FluentSpacing.l,
        vertical: FluentSpacing.m,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: FluentStroke.card(Theme.of(context).brightness),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: FluentSpacing.s,
                    vertical: FluentSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: a.isDualColumn
                        ? Theme.of(context).colorScheme.primary
                              .withValues(alpha: 0.15)
                        : Theme.of(context).colorScheme.primary
                              .withValues(alpha: 0.15),
                    borderRadius: FluentRadius.cardBorder,
                    border: Border.all(
                      color: a.isDualColumn
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.primary,
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
                        color: a.isDualColumn
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: FluentSpacing.xs),
                      Flexible(
                        child: Text(
                          a.layoutType.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: FluentType.caption.copyWith(
                            fontWeight: FontWeight.w600,
                            color: a.isDualColumn
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: FluentSpacing.s),
              _buildPill(
                label:
                    'Skew: ${a.skewAngle >= 0 ? "+" : ""}${a.skewAngle.toStringAsFixed(1)}°',
                color: a.skewAngle.abs() > 0.5
                    ? _warnColour(context)
                    : Theme.of(context).colorScheme.onSurface
                          .withValues(alpha: 0.65),
              ),
              const SizedBox(width: FluentSpacing.s),
              _buildPill(label: 'Confidence: $confPercent%', color: confColor),
            ],
          ),
          const SizedBox(height: FluentSpacing.s),
          if (_errorMessage != null) ...[
            Text(
              'ত্রুটি: $_errorMessage',
              style: FluentType.caption.copyWith(color: _badColour(context)),
            ),
          ] else if (a.gutter != null) ...[
            Text(
              'Gutter: x = ${a.gutter!.left} .. ${a.gutter!.right} (Center: ${a.gutter!.center}px, Width: ${a.gutter!.width}px)',
              style: FluentType.caption.copyWith(fontWeight: FontWeight.w600),
            ),
          ] else if (a.failureReason != null) ...[
            Text(
              'Fallback: ${a.failureReason}',
              style: FluentType.caption.copyWith(color: _warnColour(context)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPill({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FluentSpacing.s,
        vertical: FluentSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: FluentRadius.controlBorder,
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: FluentType.caption.copyWith(
          fontWeight: FontWeight.w600,
          color: color,
        ),
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
              child: Image.file(a.deskewedImage, fit: BoxFit.contain),
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
      padding: const EdgeInsets.all(FluentSpacing.m),
      itemCount: crops.length,
      itemBuilder: (context, idx) {
        final crop = crops[idx];
        return Card(
          margin: const EdgeInsets.only(bottom: FluentSpacing.l),
          shape: RoundedRectangleBorder(borderRadius: FluentRadius.cardBorder),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: FluentSpacing.l,
                  vertical: FluentSpacing.s,
                ),
                decoration: BoxDecoration(
                  color: idx == 0
                      ? Theme.of(context).colorScheme.primary
                            .withValues(alpha: 0.15)
                      : _okColour(context).withValues(alpha: 0.15),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'কলাম #${idx + 1} (${idx == 0 ? "বাম পাশ" : "ডান পাশ"})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FluentType.bodyStrong.copyWith(
                          color: idx == 0
                              ? Theme.of(context).colorScheme.primary
                              : _okColour(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: FluentSpacing.s),
                    Text(
                      '${(crop.lengthSync() / 1024).toStringAsFixed(1)} KB',
                      style: FluentType.caption.copyWith(
                        color: Theme.of(context).colorScheme.onSurface
                            .withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(12),
                ),
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
            SizedBox(height: FluentSpacing.l),
            Text('MCQ প্রশ্ন ও অপশন সেগমেন্টেশন হচ্ছে...'),
          ],
        ),
      );
    }

    if (_segmentationResult == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(FluentSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.quiz_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: FluentSpacing.m),
              Text(
                'Phase 2: Question & Option Segmentation',
                style: FluentType.subtitle.copyWith(fontSize: 16),
              ),
              const SizedBox(height: FluentSpacing.s),
              Text(
                'প্রতিটি কলাম থেকে প্রশ্ন নম্বর, প্রশ্ন টেক্সট ও অপশন ব্লক আলাদা করুন।',
                textAlign: TextAlign.center,
                style: FluentType.body.copyWith(
                  color: Theme.of(context).colorScheme.onSurface
                      .withValues(alpha: 0.65),
                ),
              ),
              const SizedBox(height: FluentSpacing.xl),
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
      padding: const EdgeInsets.all(FluentSpacing.m),
      children: [
        Container(
          padding: const EdgeInsets.all(FluentSpacing.m),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: FluentRadius.cardBorder,
            border: Border.all(
              color: Theme.of(context).colorScheme.primary
                  .withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Flexible(
                child: Text(
                  'মোট প্রশ্ন: ${seg.totalQuestions}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: FluentType.bodyStrong,
                ),
              ),
              Flexible(
                child: Text(
                  'নিখুঁত ৪-অপশন: ${seg.validMcqCount}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: FluentType.bodyStrong.copyWith(
                    color: _okColour(context),
                  ),
                ),
              ),
              Flexible(
                child: Text(
                  'রিভিউ প্রয়োজন: ${seg.reviewCount}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: FluentType.bodyStrong.copyWith(
                    color: seg.reviewCount > 0
                        ? _warnColour(context)
                        : Theme.of(context).colorScheme.onSurface
                              .withValues(alpha: 0.65),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: FluentSpacing.m),
        ...seg.questions.map((q) => _buildQuestionBlockCard(q, isDark)),
        if (seg.orphanBlocks.isNotEmpty) ...[
          const SizedBox(height: FluentSpacing.l),
          Text(
            'অসংলগ্ন / হেডার টেক্সট ব্লক (অক্ষত সংরক্ষিত):',
            style: FluentType.bodyStrong.copyWith(
              color: Theme.of(context).colorScheme.onSurface
                  .withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: FluentSpacing.s),
          ...seg.orphanBlocks.map((o) => _buildOrphanBlockCard(o, isDark)),
        ],
      ],
    );
  }

  Widget _buildQuestionBlockCard(SegmentedQuestionBlock q, bool isDark) {
    return Card(
      margin: const EdgeInsets.only(bottom: FluentSpacing.m),
      shape: RoundedRectangleBorder(borderRadius: FluentRadius.cardBorder),
      child: Padding(
        padding: const EdgeInsets.all(FluentSpacing.m),
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
                      q.questionNumber.isNotEmpty
                          ? 'প্রশ্ন ${q.questionNumber}'
                          : 'নম্বরহীন',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FluentType.caption.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: FluentSpacing.s),
                Flexible(
                  child: Text(
                    'কলাম ${q.columnId + 1}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FluentType.caption.copyWith(
                      color: Theme.of(context).colorScheme.onSurface
                          .withValues(alpha: 0.65),
                    ),
                  ),
                ),
                const Spacer(),
                if (q.hasDiagram) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FluentSpacing.s,
                      vertical: FluentSpacing.xxs,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary
                          .withValues(alpha: 0.15),
                      borderRadius: FluentRadius.controlBorder,
                    ),
                    child: Text(
                      'চিত্র/ম্যাথ 🖼️',
                      style: FluentType.caption.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: FluentSpacing.s),
                ],
                if (q.reviewRequired)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FluentSpacing.s,
                      vertical: FluentSpacing.xxs,
                    ),
                    decoration: BoxDecoration(
                      color: _warnColour(context).withValues(alpha: 0.15),
                      borderRadius: FluentRadius.controlBorder,
                    ),
                    child: Text(
                      'রিভিউ ⚠️',
                      style: FluentType.caption.copyWith(
                        color: _warnColour(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: FluentSpacing.s),
            Text(q.questionText, style: FluentType.bodyStrong),
            const SizedBox(height: FluentSpacing.s),
            ...List.generate(q.options.length, (optIdx) {
              final marker = optIdx < q.optionMarkers.length
                  ? q.optionMarkers[optIdx]
                  : '';
              return Padding(
                padding: const EdgeInsets.only(bottom: FluentSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      marker.isNotEmpty ? '($marker) ' : '• ',
                      style: FluentType.caption.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Expanded(
                      child: Text(q.options[optIdx], style: FluentType.body),
                    ),
                  ],
                ),
              );
            }),
            if (q.reviewReasons.isNotEmpty) ...[
              const SizedBox(height: FluentSpacing.s),
              Text(
                'কারণ: ${q.reviewReasons.join(", ")}',
                style: FluentType.caption.copyWith(color: _warnColour(context)),
              ),
            ],
            const SizedBox(height: FluentSpacing.xs),
            Text(
              'BBox: ${q.boundingBox.left}, ${q.boundingBox.top} (${q.boundingBox.width}x${q.boundingBox.height}) | Conf: ${(q.segmentationConfidence * 100).toStringAsFixed(0)}%',
              style: FluentType.caption.copyWith(
                color: Theme.of(context).colorScheme.onSurface
                    .withValues(alpha: 0.65),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrphanBlockCard(SegmentedQuestionBlock o, bool isDark) {
    return Card(
      margin: const EdgeInsets.only(bottom: FluentSpacing.s),
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(borderRadius: FluentRadius.cardBorder),
      child: Padding(
        padding: const EdgeInsets.all(FluentSpacing.m),
        child: Text(
          o.questionText,
          style: FluentType.caption.copyWith(fontStyle: FontStyle.italic),
        ),
      ),
    );
  }

  Widget _buildSingleImageView(File file) {
    return InteractiveViewer(
      maxScale: 4.0,
      child: Center(child: Image.file(file, fit: BoxFit.contain)),
    );
  }
}

/// Custom painter to draw gutter overlay and column bounding boxes on the image.
class _LayoutOverlayPainter extends CustomPainter {
  final LayoutAnalysisResult analysis;
  final Size renderedSize;

  _LayoutOverlayPainter({required this.analysis, required this.renderedSize});

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
        ..color = const Color(0xFFB45309).withValues(alpha: 0.35)
        ..style = PaintingStyle.fill;

      canvas.drawRect(gutterRect, gutterPaint);

      // Gutter center dashed line
      final linePaint = Paint()
        ..color = const Color(0xFFB45309)
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

      final boxColor = box.index == 0
          ? const Color(0xFF2563EB)
          : const Color(0xFF15803D);

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
