import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Asks whether a photo should come from the camera or the gallery.
///
/// Anywhere a page is added, both are reasonable: the next page of a test is
/// usually shot there and then, but a paper already photographed, shared or
/// downloaded is sitting in the gallery and should not have to be shot again.
class PhotoSourceSheet {
  /// Null when the user backs out without choosing.
  static Future<ImageSource?> ask(
    BuildContext context, {
    String title = 'ছবি কোথা থেকে নেবেন?',
  }) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: const Text('ক্যামেরা'),
              subtitle: const Text(
                'এখনই পাতাটা তুলুন',
                style: TextStyle(fontSize: 12),
              ),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('গ্যালারি'),
              subtitle: const Text(
                'আগে তোলা বা পাঠানো ছবি থেকে',
                style: TextStyle(fontSize: 12),
              ),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
