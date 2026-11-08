import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const MethodChannel _channel = MethodChannel('overlay_bridge');

/// Brings the app to the front from the floating bubble.
///
/// The bubble floats over whatever the user is doing, and `flutter_overlay_window`
/// has nothing for getting back to the app, so everything the bubble adds used
/// to be invisible until the user found their own way there. Returns false when
/// the app could not be opened; the caller decides what to say about it.
class AppLauncher {
  AppLauncher._();
  static final AppLauncher instance = AppLauncher._();

  Future<bool> open() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('openApp') ?? false;
    } catch (e) {
      debugPrint('Could not open the app from the bubble: $e');
      return false;
    }
  }
}

/// Holds Android's `microphone` foreground-service type for exactly as long as
/// the microphone is open, and no longer.
///
/// The floating bubble runs inside a foreground service that lives for as long
/// as the bubble is on screen. That service used to carry the microphone type
/// itself, which meant the app told Android it was a microphone app merely for
/// showing a bubble — nothing had to be recording. The type is fixed in the
/// manifest and the overlay plugin starts its service without one, so it
/// cannot be switched off there. This claims the type separately, around the
/// recording itself.
///
/// Calls are reference counted, so dictation and recording can each ask for it
/// without one ending the other's claim. Everywhere but Android this does
/// nothing at all, which is also what keeps it quiet under `flutter test`.
class MicForegroundService {
  MicForegroundService._();
  static final MicForegroundService instance = MicForegroundService._();

  @visibleForTesting
  static const MethodChannel channel = _channel;

  /// True on the platform this matters on. Read through a getter so a test can
  /// reason about it without a device.
  bool get _supported => !kIsWeb && Platform.isAndroid;

  int _holders = 0;

  /// How many callers are currently holding the microphone open.
  @visibleForTesting
  int get holders => _holders;

  /// Claims the type for one caller. Pair every call with [release].
  ///
  /// A failure is swallowed rather than thrown: the microphone still works
  /// from the app's own screens without this, so a service that would not
  /// start must not take the recording down with it.
  Future<void> acquire({String? text}) async {
    _holders++;
    if (!_supported || _holders != 1) return;
    try {
      await channel.invokeMethod<bool>('start', {'text': text});
    } catch (e) {
      debugPrint('Mic foreground service would not start: $e');
    }
  }

  /// Releases one caller's claim, stopping the service once the last one goes.
  Future<void> release() async {
    if (_holders == 0) return;
    _holders--;
    if (!_supported || _holders != 0) return;
    try {
      await channel.invokeMethod<bool>('stop');
    } catch (e) {
      debugPrint('Mic foreground service would not stop: $e');
    }
  }

  /// Drops every claim at once.
  ///
  /// The backstop for a path that acquired and then lost its way out — a
  /// screen torn down mid-session, say. Without it one missed [release] would
  /// leave the type claimed for the rest of the app's life, which is the whole
  /// problem this class exists to end.
  Future<void> releaseAll() async {
    if (_holders == 0) return;
    _holders = 0;
    if (!_supported) return;
    try {
      await channel.invokeMethod<bool>('stop');
    } catch (e) {
      debugPrint('Mic foreground service would not stop: $e');
    }
  }
}
