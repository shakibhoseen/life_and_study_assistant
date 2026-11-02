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
  late File _photo = widget.photo;
  bool _turning = false;

  Future<void> _turn({required bool clockwise}) async {
    if (_turning) return;
    setState(() => _turning = true);
    final turned = await PhotoCaptureService.instance.rotateQuarterTurn(
      _photo,
      clockwise: clockwise,
    );
    if (!mounted) return;
    setState(() {
      _photo = turned;
      _turning = false;
      // Flutter caches a decoded file by path and size, so without this the
      // old orientation stays on screen.
      imageCache.clear();
    });
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
                // contain, never cover: a turned page must stay whole on
                // screen rather than having its edges cut away.
                child: Image.file(
                  _photo,
                  key: ValueKey(_photo.path),
                  fit: BoxFit.contain,
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
                  const Text(
                    'পাতাটা সোজা করে নিন, তারপর কেটে নেবেন',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton.filledTonal(
                        tooltip: 'বাঁয়ে ঘোরান',
                        onPressed: _turning
                            ? null
                            : () => _turn(clockwise: false),
                        icon: const Icon(Icons.rotate_left_rounded),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'ডানে ঘোরান',
                        onPressed: _turning
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
                      onPressed: _turning
                          ? null
                          : () => Navigator.of(context).pop(_photo),
                      icon: const Icon(Icons.crop_rounded, size: 18),
                      label: const Text('এবার কেটে নিন'),
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
