import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Checks the pieces of the Android manifest that only fail on a device.
///
/// A plugin that needs an activity declared fails at the moment the user
/// taps, not at build time and not in a widget test, so the only cheap place
/// to catch a missing entry is here.
void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml');

  test('the manifest is where the build expects it', () {
    expect(manifest.existsSync(), isTrue);
  });

  test('a crop screen is declared', () {
    final xml = manifest.readAsStringSync();
    // image_cropper ships its own CmUCropActivity, so this entry is a second
    // one rather than the only one — checked on the built APK, which carries
    // both. It is kept because the base UCropActivity is what a crop started
    // without the plugin's subclass resolves to, and an undeclared activity
    // fails at the moment the user taps, which nothing earlier would catch.
    expect(xml, contains('com.yalantis.ucrop.UCropActivity'));
  });

  test('the overlay bubble service is declared', () {
    final xml = manifest.readAsStringSync();
    expect(xml, contains('flutter_overlay_window'));
  });

  test('notification receivers survive a reboot', () {
    final xml = manifest.readAsStringSync();
    expect(xml, contains('ScheduledNotificationBootReceiver'));
    expect(xml, contains('android.intent.action.BOOT_COMPLETED'));
  });
}
