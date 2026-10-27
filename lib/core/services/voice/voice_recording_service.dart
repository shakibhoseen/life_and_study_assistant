import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

class VoiceRecordingService {
  VoiceRecordingService._();
  static final VoiceRecordingService instance = VoiceRecordingService._();

  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  String? _currentFilePath;

  bool get isRecording => _isRecording;
  String? get currentFilePath => _currentFilePath;

  /// Check whether microphone permission is granted.
  /// Uses [Permission.microphone.status] first because the record plugin's native Android code
  /// checks if Activity == null and immediately returns false inside background Services and Overlays!
  Future<bool> hasPermission() async {
    try {
      final status = await Permission.microphone.status;
      if (status.isGranted) {
        return true;
      }
      return await _audioRecorder.hasPermission();
    } catch (e) {
      debugPrint('Error checking mic permission: $e');
      return false;
    }
  }

  /// Mono 16 kHz is all speech recognition uses, and it makes the upload a
  /// fraction of the size. It does not change the token cost, which Gemini
  /// charges by duration rather than by bytes.
  static const RecordConfig speechConfig = RecordConfig(
    encoder: AudioEncoder.aacLc,
    bitRate: 32000,
    sampleRate: 16000,
    numChannels: 1,
  );

  Future<void> startRecording({RecordConfig? config}) async {
    if (_isRecording) return;

    final hasPerm = await hasPermission();
    if (!hasPerm) {
      throw Exception('Microphone permission not granted');
    }

    final tempDir = await getTemporaryDirectory();
    final path =
        '${tempDir.path}/livemcq_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    _currentFilePath = path;

    await _audioRecorder.start(
      config ?? const RecordConfig(encoder: AudioEncoder.aacLc),
      path: path,
    );
    _isRecording = true;
  }

  Future<File?> stopRecording() async {
    if (!_isRecording) return null;

    final path = await _audioRecorder.stop();
    _isRecording = false;

    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        return file;
      }
    }
    return null;
  }

  Future<void> cancelRecording() async {
    if (_isRecording) {
      await _audioRecorder.cancel();
      _isRecording = false;
    }
  }

  void dispose() {
    _audioRecorder.dispose();
  }
}
