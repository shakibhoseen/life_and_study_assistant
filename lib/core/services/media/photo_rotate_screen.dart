import 'dart:io';

import 'package:flutter/material.dart';

import 'photo_capture_service.dart';

/// Stands a photo upright before anything is cropped out of it.
///
/// Rotation has to come first. Cropping a sideways page means framing a
/// sideways rectangle, and the crop screen's own rotation is a fine dial for
/// straightening a degree or two, not for a page lying across the frame.
/// Turning first means the crop that follows is drawn on a page the right way
/// up.
///
/// **Turning is free until it is confirmed.** The screen keeps a count of
/// quarter-turns and shows the photo through a [RotatedBox]; no pixels move
/// until the user goes on to the crop. The first version re-encoded the whole
/// file on every tap, which on a full-size phone photo meant seconds of a
/// frozen screen — and for a format the Dart decoder could not read, meant a
/// button that did nothing at all, silently, for ever.
///
/// The photo is shown whole, scaled to fit, so a turn that changes a portrait
/// page into a landscape one cannot push the edges out of view. Nothing here
/// zooms or pans: the one question being asked is which way is up.
class PhotoRotateScreen extends StatefulWidget {
  final File photo;

  const PhotoRotateScreen({super.key, required this.photo});

  /// Returns the upright photo, or null if the user backs out.
  static Future<File?> show(BuildContext context, File photo) {
    return Navigator.of(context).push<File>(
      MaterialPageRoute(builder: (_) => PhotoRotateScreen(photo: photo)),
    );
  }

  @override
  State<PhotoRotateScreen> createState() => _PhotoRotateScreenState();
}

class _PhotoRotateScreenState extends State<PhotoRotateScreen> {
  int _quarterTurns = 0;
  bool _baking = false;
  String? _error;

  void _turn({required bool clockwise}) {
    if (_baking) return;
    setState(() {
      _quarterTurns = (_quarterTurns + (clockwise ? 1 : -1)) % 4;
      _error = null;
    });
  }

  Future<void> _confirm() async {
    if (_baking) return;
    if (_quarterTurns == 0) {
      Navigator.of(context).pop(widget.photo);
      return;
    }

    setState(() {
      _baking = true;
      _error = null;
    });

    try {
      final upright = await PhotoCaptureService.instance.bakeQuarterTurns(
        widget.photo,
        _quarterTurns,
      );
      if (!mounted) return;
      Navigator.of(context).pop(upright);
    } catch (e) {
      debugPrint('Rotate: could not turn the page: $e');
      if (!mounted) return;
      // Said out loud rather than swallowed. Handing back the sideways photo
      // without a word is what made this impossible to report.
      setState(() {
        _baking = false;
        _error = 'ছবিটি ঘোরানো গেল না। অন্যভাবে তুলে বা গ্যালারি থেকে নিয়ে দেখুন।';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('সোজা করুন', style: TextStyle(fontSize: 16)),
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Center(
                child: RotatedBox(
                  quarterTurns: _quarterTurns,
                  // contain, never cover: a turned page must stay whole on
                  // screen rather than having its edges cut away.
                  child: Image.file(widget.photo, fit: BoxFit.contain),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Column(
                children: [
                  Text(
                    _error ?? 'পাতাটা সোজা করে নিন, তারপর কেটে নেবেন',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _error == null
                          ? Colors.white70
                          : Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton.filledTonal(
                        tooltip: 'বাঁয়ে ঘোরান',
                        onPressed: _baking
                            ? null
                            : () => _turn(clockwise: false),
                        icon: const Icon(Icons.rotate_left_rounded),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'ডানে ঘোরান',
                        onPressed: _baking
                            ? null
                            : () => _turn(clockwise: true),
                        icon: const Icon(Icons.rotate_right_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _baking ? null : _confirm,
                      icon: _baking
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.crop_rounded, size: 18),
                      label: Text(_baking ? 'ঘোরানো হচ্ছে…' : 'এবার কেটে নিন'),
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
}
