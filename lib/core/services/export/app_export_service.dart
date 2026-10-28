import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Result object for an export operation.
class ExportResult {
  final bool success;
  final String? filePath;
  final String? displayLocation;
  final bool wasCancelled;
  final String? errorMessage;

  const ExportResult({
    required this.success,
    this.filePath,
    this.displayLocation,
    this.wasCancelled = false,
    this.errorMessage,
  });

  /// User-friendly location formatted for Bengali UI notifications.
  String get bengaliSummary {
    if (!success) {
      if (wasCancelled) {
        return 'এক্সপোর্ট বাতিল করা হয়েছে।';
      }
      return 'ফাইল সেভ করতে সমস্যা হয়েছে: ${errorMessage ?? "অজানা ত্রুটি"}';
    }

    final loc = displayLocation ?? filePath ?? '';
    return 'ফাইলটি সফলভাবে সেভ হয়েছে!\n'
        '📁 লোকেশন: $loc\n'
        '💡 আপনার ফোনের File Manager / Files অ্যাপের Download ফোল্ডারে এটি খুঁজে পাবেন।';
  }
}

/// Service providing unified export functionality across Android, iOS, and Desktop.
/// Resolves public Download folders, allows custom folder selection via SAF, and
/// ensures files are easily discoverable by the user.
class AppExportService {
  AppExportService._();

  static const String defaultSubfolder = 'LifeAndStudyAssistant';

  /// Resolves the most appropriate public directory for saving exported files.
  /// Prioritizes user-accessible Download folders over internal sandbox directories.
  static Future<Directory> getExportDirectory({
    String subfolder = defaultSubfolder,
  }) async {
    // 1. Android platform resolution
    if (!kIsWeb && Platform.isAndroid) {
      // Primary: Standard user-visible public Download directory
      final publicDownloadDir = Directory('/storage/emulated/0/Download');
      if (await publicDownloadDir.exists()) {
        try {
          final target = Directory('${publicDownloadDir.path}/$subfolder');
          if (!await target.exists()) {
            await target.create(recursive: true);
          }
          // Verify directory is writable
          final testFile = File('${target.path}/.probe_write');
          await testFile.writeAsString('ok');
          await testFile.delete();
          return target;
        } catch (e) {
          debugPrint('Cannot write directly to public Download/$subfolder: $e');
        }

        // Try the base Download directory directly
        try {
          final testFile = File('${publicDownloadDir.path}/.probe_write');
          await testFile.writeAsString('ok');
          await testFile.delete();
          return publicDownloadDir;
        } catch (_) {}
      }

      // Secondary: path_provider getDownloadsDirectory
      try {
        final downloads = await getDownloadsDirectory();
        if (downloads != null && await downloads.exists()) {
          final target = Directory('${downloads.path}/$subfolder');
          if (!await target.exists()) {
            await target.create(recursive: true);
          }
          return target;
        }
      } catch (e) {
        debugPrint('getDownloadsDirectory failed on Android: $e');
      }

      // Tertiary: External storage directory
      try {
        final ext = await getExternalStorageDirectory();
        if (ext != null) {
          final target = Directory('${ext.path}/$subfolder');
          if (!await target.exists()) {
            await target.create(recursive: true);
          }
          return target;
        }
      } catch (e) {
        debugPrint('getExternalStorageDirectory failed: $e');
      }
    }

    // 2. Desktop platforms (macOS, Windows, Linux)
    if (!kIsWeb &&
        (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      try {
        final downloads = await getDownloadsDirectory();
        if (downloads != null) {
          final target = Directory('${downloads.path}/$subfolder');
          if (!await target.exists()) {
            await target.create(recursive: true);
          }
          return target;
        }
      } catch (e) {
        debugPrint('Desktop getDownloadsDirectory failed: $e');
      }
    }

    // 3. iOS or fallback: Application Documents Directory
    final appDocs = await getApplicationDocumentsDirectory();
    final target = Directory('${appDocs.path}/$subfolder');
    if (!await target.exists()) {
      await target.create(recursive: true);
    }
    return target;
  }

  /// Saves content directly into the public Downloads / dedicated folder.
  /// If scoped storage restricts direct file writes, falls back to system picker.
  static Future<ExportResult> saveToDownloads({
    required String fileName,
    required String content,
    String subfolder = defaultSubfolder,
  }) async {
    final bytes = Uint8List.fromList(utf8.encode(content));
    return saveBytesToDownloads(
      fileName: fileName,
      bytes: bytes,
      subfolder: subfolder,
    );
  }

  /// Saves binary or text bytes directly into the public Downloads / dedicated folder.
  static Future<ExportResult> saveBytesToDownloads({
    required String fileName,
    required Uint8List bytes,
    String subfolder = defaultSubfolder,
  }) async {
    try {
      final dir = await getExportDirectory(subfolder: subfolder);
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);

      // Construct a clean display path for the user
      String displayLoc = file.path;
      if (displayLoc.contains('/Download/')) {
        displayLoc =
            'Download${displayLoc.substring(displayLoc.indexOf('/Download/') + 9)}';
      } else if (displayLoc.contains('/Downloads/')) {
        displayLoc =
            'Downloads${displayLoc.substring(displayLoc.indexOf('/Downloads/') + 10)}';
      }

      return ExportResult(
        success: true,
        filePath: file.path,
        displayLocation: displayLoc,
      );
    } catch (e) {
      debugPrint(
        'Direct write to Downloads failed ($e). Falling back to system file picker...',
      );
      // Fallback to SAF picker so user can pick folder directly
      return saveWithPicker(
        fileName: fileName,
        bytes: bytes,
        dialogTitle: 'Save to Downloads or Choose Folder',
      );
    }
  }

  /// Opens the native platform "Save As" / file dialog (Android Storage Access Framework,
  /// iOS Files, or Desktop Save Dialog) allowing the user to choose ANY custom folder
  /// (Downloads, Documents, custom folders, SD card, etc.).
  static Future<ExportResult> saveWithPicker({
    required String fileName,
    Uint8List? bytes,
    String? content,
    String? dialogTitle,
  }) async {
    try {
      final dataBytes =
          bytes ??
          (content != null
              ? Uint8List.fromList(utf8.encode(content))
              : Uint8List(0));

      final uri = await FilePicker.saveFile(
        dialogTitle: dialogTitle ?? 'ফোল্ডার পছন্দ করে সেভ করুন',
        fileName: fileName,
        bytes: dataBytes,
      );

      if (uri == null) {
        return const ExportResult(success: false, wasCancelled: true);
      }

      String selectedPath;
      try {
        selectedPath = uri.toFilePath();
      } catch (_) {
        selectedPath = uri.path;
      }

      if (selectedPath.isEmpty) {
        return const ExportResult(success: false, wasCancelled: true);
      }

      // If the platform didn't automatically write the bytes to selectedPath, write them now
      final file = File(selectedPath);
      if (!await file.exists() || await file.length() == 0) {
        try {
          await file.writeAsBytes(dataBytes);
        } catch (_) {}
      }

      String displayLoc = selectedPath;
      if (displayLoc.contains('/Download/')) {
        displayLoc =
            'Download${displayLoc.substring(displayLoc.indexOf('/Download/') + 9)}';
      } else if (displayLoc.contains('/Downloads/')) {
        displayLoc =
            'Downloads${displayLoc.substring(displayLoc.indexOf('/Downloads/') + 10)}';
      }

      return ExportResult(
        success: true,
        filePath: selectedPath,
        displayLocation: displayLoc,
      );
    } catch (e) {
      debugPrint('FilePicker saveFile failed: $e');
      return ExportResult(success: false, errorMessage: e.toString());
    }
  }
}
