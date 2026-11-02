import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../ai/ai_media_limits.dart';

/// Takes a photo and lets the user trim it before anything is read from it.
///
/// A page shot with a phone holds the facing page, a thumb, the desk and the
/// margin of the book. All of that is read by the model and paid for, and the
/// extra text pulls questions in from the wrong page. Trimming is also the
/// only way to take half a crowded page, which is what the scanner asks for
/// when a page holds more than one reply can carry.
///
/// Cropping happens before the size reduction in [AiMediaLimits], so the
/// pixels the user keeps are spent on what they chose rather than on the
/// desk around it.
class PhotoCaptureService {
  PhotoCaptureService._();
  static final PhotoCaptureService instance = PhotoCaptureService._();

  @visibleForTesting
  ImagePicker picker = ImagePicker();

  /// The crop step, replaceable so the paths around it can be tested without
  /// a device. It returns the cropped path, or null when the user backs out.
  @visibleForTesting
  Future<String?> Function(String sourcePath, List<PlatformUiSettings> ui)
  runCrop = (sourcePath, ui) async {
    final cropped = await ImageCropper().cropImage(
      sourcePath: sourcePath,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: AiMediaLimits.jpegQuality,
      uiSettings: ui,
    );
    return cropped?.path;
  };

  /// A photo from [source], after the user has trimmed and straightened it.
  ///
  /// Null only when they back out of the camera or gallery. Backing out of
  /// the crop keeps the photo as shot, since they have already taken it.
  Future<File?> captureAndCrop({
    required ImageSource source,
    required BuildContext context,
    String title = 'কেটে নিন',
  }) async {
    final picked = await picker.pickImage(
      source: source,
      // Deliberately above every preset: the picker keeps headroom and the
      // real reduction happens just before the request, so a sharper setting
      // chosen after the shot still has pixels to work with.
      maxWidth: AiMediaLimits.pickerHeadroom.toDouble(),
      maxHeight: AiMediaLimits.pickerHeadroom.toDouble(),
      imageQuality: AiMediaLimits.jpegQuality,
    );
    if (picked == null) return null;

    if (!context.mounted) return File(picked.path);
    return cropExisting(path: picked.path, context: context, title: title);
  }

  /// Turns a photo a quarter turn and writes it back as a new file.
  ///
  /// A book held sideways under the camera comes out sideways, and the crop
  /// screen's own rotation is a fine-grained dial meant for straightening a
  /// degree or two. A page lying on its side needs a quarter turn, which is
  /// one tap here and is applied to the whole photo before any trimming.
  ///
  /// Returns the rotated file, or the original when the image cannot be
  /// decoded — a photo is never lost to a failed rotation.
  Future<File> rotateQuarterTurn(File photo, {bool clockwise = true}) async {
    try {
      final bytes = await photo.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return photo;

      final turned = img.copyRotate(decoded, angle: clockwise ? 90 : -90);
      final encoded = img.encodeJpg(turned, quality: AiMediaLimits.jpegQuality);

      // A new path each time: writing over the source leaves the old image
      // cached by anything already showing it.
      final dir = photo.parent.path;
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final rotated = File('$dir/rot_$stamp.jpg');
      await rotated.writeAsBytes(encoded, flush: true);
      return rotated;
    } catch (e) {
      debugPrint('Rotate failed, keeping the photo as it was: $e');
      return photo;
    }
  }

  /// Reopens the trim screen on a photo already taken.
  ///
  /// The first crop is rarely the last: a scan that comes back short is
  /// usually fixed by taking a narrower part of the same photo, and making
  /// the user shoot it again loses the framing they already had.
  Future<File?> cropExisting({
    required String path,
    required BuildContext context,
    String title = 'কেটে নিন',
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    try {
      final croppedPath = await runCrop(path, [
        AndroidUiSettings(
          toolbarTitle: title,
          toolbarColor: isDark
              ? const Color(0xFF1E293B)
              : const Color(0xFF6366F1),
          toolbarWidgetColor: Colors.white,
          statusBarLight: !isDark,
          backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.black,
          activeControlsWidgetColor: const Color(0xFF6366F1),
          // A page is rarely a tidy rectangle on the desk, so the user
          // frames it themselves rather than being held to a ratio.
          lockAspectRatio: false,
          hideBottomControls: false,
        ),
        IOSUiSettings(title: title, aspectRatioLockEnabled: false),
      ]);
      // Backing out of the crop keeps the photo as shot rather than losing it.
      return File(croppedPath ?? path);
    } catch (e) {
      // A missing crop screen must not cost the user their photo.
      debugPrint('Crop unavailable, using the photo as shot: $e');
      return File(path);
    }
  }
}
