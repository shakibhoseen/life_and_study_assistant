import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:permission_handler/permission_handler.dart';

enum BubbleLaunchResult {
  success,
  overlayPermissionDenied,
  microphonePermissionDenied,
  failed;

  bool get isSuccess => this == BubbleLaunchResult.success;
}

class LiveMcqBubbleService {
  LiveMcqBubbleService._();
  static final LiveMcqBubbleService instance = LiveMcqBubbleService._();

  bool _isBubbleRunning = false;
  bool get isBubbleRunning => _isBubbleRunning;

  /// Check whether system overlay permission (Draw over other apps) is granted
  Future<bool> checkPermission() async {
    try {
      return await FlutterOverlayWindow.isPermissionGranted();
    } catch (e) {
      debugPrint('Error checking overlay permission: $e');
      return false;
    }
  }

  /// Request system overlay permission from user
  Future<bool> requestPermission() async {
    try {
      final granted = await FlutterOverlayWindow.requestPermission();
      return granted ?? false;
    } catch (e) {
      debugPrint('Error requesting overlay permission: $e');
      return false;
    }
  }

  /// Check whether microphone permission is granted
  Future<bool> checkMicrophonePermission() async {
    try {
      final status = await Permission.microphone.status;
      return status.isGranted;
    } catch (e) {
      debugPrint('Error checking mic permission: $e');
      return false;
    }
  }

  /// Request microphone permission from user in the foreground activity
  Future<bool> requestMicrophonePermission() async {
    try {
      final status = await Permission.microphone.request();
      return status.isGranted;
    } catch (e) {
      debugPrint('Error requesting mic permission: $e');
      return false;
    }
  }

  /// Launch the floating bubble over LiveMCQ.
  /// Checks and requests both Overlay (draw over apps) and Microphone permissions
  /// in the foreground activity before starting the overlay service.
  Future<BubbleLaunchResult> startBubble() async {
    // 1. Verify / Request Overlay permission
    final hasPerm = await checkPermission();
    if (!hasPerm) {
      final requested = await requestPermission();
      if (!requested) return BubbleLaunchResult.overlayPermissionDenied;
    }

    // 2. Verify / Request Microphone permission upfront (essential because background overlay service cannot show permission dialog)
    final hasMic = await checkMicrophonePermission();
    if (!hasMic) {
      final requestedMic = await requestMicrophonePermission();
      if (!requestedMic) return BubbleLaunchResult.microphonePermissionDenied;
    }

    try {
      final isActive = await FlutterOverlayWindow.isActive();
      if (isActive) {
        try {
          await FlutterOverlayWindow.shareData('reset_to_collapsed');
          await FlutterOverlayWindow.closeOverlay();
          await Future.delayed(const Duration(milliseconds: 150));
        } catch (_) {}
      }

      // Start with compact bubble dimensions (110x110)
      await FlutterOverlayWindow.showOverlay(
        height: 110,
        width: 110,
        alignment: OverlayAlignment.centerRight,
        visibility: NotificationVisibility.visibilityPublic,
        flag: OverlayFlag.defaultFlag,
        overlayTitle: 'LiveMCQ Voice Companion',
        overlayContent: 'Floating over LiveMCQ to capture mistakes by voice',
        enableDrag: true,
        positionGravity: PositionGravity.auto,
        startPosition: const OverlayPosition(0, -200),
        dismissConfig: const OverlayDismissConfig(
          shape: OverlayDismissShape.circle,
          borderRadius: 16,
          backgroundColor: Color(0xCC333333),
          activeBackgroundColor: Colors.red,
          borderWidth: 2,
          borderColor: Colors.white24,
          activeBorderColor: Colors.white,
        ),
      );

      // Ensure cached FlutterEngine resets to collapsed state
      await Future.delayed(const Duration(milliseconds: 50));
      try {
        await FlutterOverlayWindow.shareData('reset_to_collapsed');
      } catch (_) {}

      _isBubbleRunning = true;
      return BubbleLaunchResult.success;
    } catch (e) {
      debugPrint('Error starting overlay bubble: $e');
      _isBubbleRunning = false;
      return BubbleLaunchResult.failed;
    }
  }

  /// Close / dismiss the floating bubble
  Future<void> stopBubble() async {
    try {
      try {
        await FlutterOverlayWindow.shareData('reset_to_collapsed');
      } catch (_) {}
      await FlutterOverlayWindow.closeOverlay();
      _isBubbleRunning = false;
    } catch (e) {
      debugPrint('Error closing overlay bubble: $e');
    }
  }

  /// Resize overlay window between collapsed (compact bubble) and expanded (recording dialog)
  Future<void> resizeOverlay({
    required int width,
    required int height,
    bool enableDrag = false,
  }) async {
    try {
      await FlutterOverlayWindow.resizeOverlay(width, height, enableDrag);
    } catch (e) {
      debugPrint('Error resizing overlay window: $e');
    }
  }

  /// Check if the overlay window is currently displayed
  Future<bool> isOverlayActive() async {
    try {
      final active = await FlutterOverlayWindow.isActive();
      _isBubbleRunning = active;
      return active;
    } catch (e) {
      return false;
    }
  }
}
