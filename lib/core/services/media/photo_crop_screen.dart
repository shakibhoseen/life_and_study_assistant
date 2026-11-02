import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../ai/ai_media_limits.dart';
import 'crop_geometry.dart';

/// Trims a photo with a frame the user controls, over a picture that does not
/// move unless they move it.
///
/// The crop screen this replaces re-fitted the photo to the frame after every
/// change. Shrinking the frame zoomed the picture in, which then made the
/// frame's old size unreachable, so narrowing a selection was a one-way door
/// and widening it again meant starting over.
///
/// Here the picture is laid out once, whole and centred, and stays there. The
/// frame is dragged over it, any size from a corner of the page to all of it,
/// and the picture only moves when the user pinches or drags it themselves.
class PhotoCropScreen extends StatefulWidget {
  final File photo;
  final String title;

  const PhotoCropScreen({
    super.key,
    required this.photo,
    this.title = 'কেটে নিন',
  });

  /// Returns the trimmed photo, or null if the user backs out.
  static Future<File?> show(
    BuildContext context,
    File photo, {
    String title = 'কেটে নিন',
  }) {
    return Navigator.of(context).push<File>(
      MaterialPageRoute(
        builder: (_) => PhotoCropScreen(photo: photo, title: title),
      ),
    );
  }

  @override
  State<PhotoCropScreen> createState() => _PhotoCropScreenState();
}

/// Which part of the frame a drag is moving.
enum _Grip { topLeft, topRight, bottomLeft, bottomRight, body }

class _PhotoCropScreenState extends State<PhotoCropScreen> {
  /// Big enough to grab with a fingertip.
  static const double _handle = 30;

  /// A frame smaller than this is almost certainly a stray tap.
  static const double _minSide = 48;

  final _viewer = TransformationController();
  Size? _box;
  Rect? _frame;
  bool _working = false;

  @override
  void dispose() {
    _viewer.dispose();
    super.dispose();
  }

  void _resetFrame(Size box) {
    _box = box;
    // Starts on the whole picture: the common case is keeping most of the
    // page, so the user narrows from everything rather than building up.
    _frame = Offset.zero & box;
  }

  _Grip _gripAt(Offset point, Rect frame) {
    bool near(Offset corner) => (point - corner).distance <= _handle;
    if (near(frame.topLeft)) return _Grip.topLeft;
    if (near(frame.topRight)) return _Grip.topRight;
    if (near(frame.bottomLeft)) return _Grip.bottomLeft;
    if (near(frame.bottomRight)) return _Grip.bottomRight;
    return _Grip.body;
  }

  Rect _afterDrag(Rect frame, _Grip grip, Offset delta, Size box) {
    var next = switch (grip) {
      _Grip.topLeft => Rect.fromLTRB(
        frame.left + delta.dx,
        frame.top + delta.dy,
        frame.right,
        frame.bottom,
      ),
      _Grip.topRight => Rect.fromLTRB(
        frame.left,
        frame.top + delta.dy,
        frame.right + delta.dx,
        frame.bottom,
      ),
      _Grip.bottomLeft => Rect.fromLTRB(
        frame.left + delta.dx,
        frame.top,
        frame.right,
        frame.bottom + delta.dy,
      ),
      _Grip.bottomRight => Rect.fromLTRB(
        frame.left,
        frame.top,
        frame.right + delta.dx,
        frame.bottom + delta.dy,
      ),
      _Grip.body => frame.shift(delta),
    };

    if (grip == _Grip.body) {
      // Moving the whole frame keeps its size; it stops at the edges.
      final dx = next.left.clamp(0.0, box.width - next.width) - next.left;
      final dy = next.top.clamp(0.0, box.height - next.height) - next.top;
      return next.shift(Offset(dx, dy));
    }

    next = Rect.fromLTRB(
      next.left.clamp(0.0, box.width),
      next.top.clamp(0.0, box.height),
      next.right.clamp(0.0, box.width),
      next.bottom.clamp(0.0, box.height),
    );
    // A corner dragged past its opposite would invert the frame.
    if (next.width < _minSide || next.height < _minSide) return frame;
    return next;
  }

  Future<void> _apply() async {
    final box = _box;
    final frame = _frame;
    if (box == null || frame == null || _working) return;
    setState(() => _working = true);

    try {
      final bytes = await widget.photo.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        if (mounted) Navigator.of(context).pop(widget.photo);
        return;
      }

      final pixels = CropGeometry.toImagePixels(
        displayRect: frame,
        box: box,
        imageWidth: decoded.width,
        imageHeight: decoded.height,
      );
      if (pixels.width < 1 || pixels.height < 1) {
        if (mounted) Navigator.of(context).pop(widget.photo);
        return;
      }

      final cropped = img.copyCrop(
        decoded,
        x: pixels.left.round(),
        y: pixels.top.round(),
        width: pixels.width.round(),
        height: pixels.height.round(),
      );
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final out = File('${widget.photo.parent.path}/crop_$stamp.jpg');
      await out.writeAsBytes(
        img.encodeJpg(cropped, quality: AiMediaLimits.jpegQuality),
        flush: true,
      );
      if (mounted) Navigator.of(context).pop(out);
    } catch (e) {
      debugPrint('Crop failed, keeping the photo as it was: $e');
      if (mounted) Navigator.of(context).pop(widget.photo);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title, style: const TextStyle(fontSize: 16)),
        actions: [
          TextButton(
            onPressed: _working
                ? null
                : () => setState(() => _resetFrame(_box ?? Size.zero)),
            child: const Text(
              'পুরোটা',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final box = Size(constraints.maxWidth, constraints.maxHeight);
                if (_box != box) {
                  // Laid out once per size; the picture does not re-fit
                  // itself afterwards whatever the frame does.
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _resetFrame(box));
                  });
                }
                final frame = _frame ?? (Offset.zero & box);

                return Stack(
                  children: [
                    Positioned.fill(
                      child: InteractiveViewer(
                        transformationController: _viewer,
                        minScale: 1,
                        maxScale: 5,
                        child: Image.file(
                          widget.photo,
                          key: ValueKey(widget.photo.path),
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onPanStart: (d) =>
                            _grip = _gripAt(d.localPosition, frame),
                        onPanUpdate: (d) {
                          final grip = _grip;
                          if (grip == null) return;
                          setState(() {
                            _frame = _afterDrag(frame, grip, d.delta, box);
                          });
                        },
                        onPanEnd: (_) => _grip = null,
                        child: CustomPaint(painter: _CropFramePainter(frame)),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Column(
                children: [
                  const Text(
                    'কোণা টেনে ছোট-বড় করুন। ছবি নিজে থেকে জুম হবে না — '
                    'দুই আঙুলে চাইলে জুম করতে পারেন।',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 11.5),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _working ? null : _apply,
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('কেটে নিন'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  _Grip? _grip;
}

class _CropFramePainter extends CustomPainter {
  final Rect frame;

  _CropFramePainter(this.frame);

  @override
  void paint(Canvas canvas, Size size) {
    final outside = Path()
      ..addRect(Offset.zero & size)
      ..addRect(frame)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(outside, Paint()..color = Colors.black54);

    canvas.drawRect(
      frame,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );

    // Corner marks, so where to grab is obvious without a legend.
    final corner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = Colors.white;
    const arm = 22.0;
    for (final (point, dx, dy) in [
      (frame.topLeft, 1.0, 1.0),
      (frame.topRight, -1.0, 1.0),
      (frame.bottomLeft, 1.0, -1.0),
      (frame.bottomRight, -1.0, -1.0),
    ]) {
      canvas.drawLine(point, point + Offset(arm * dx, 0), corner);
      canvas.drawLine(point, point + Offset(0, arm * dy), corner);
    }
  }

  @override
  bool shouldRepaint(_CropFramePainter old) => old.frame != frame;
}
