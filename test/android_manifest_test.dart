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
    // image_cropper ships its own CmUCropActivity, so this is a second entry
    // rather than the only one. An undeclared activity fails at the moment
    // the user taps, which nothing earlier would catch.
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

  test('the bubble service does not claim the microphone', () {
    final xml = manifest.readAsStringSync();
    // The overlay service runs for as long as the bubble is on screen. Giving
    // it the microphone type made the app hold the microphone for showing a
    // bubble, and other apps then found it taken. The type belongs to
    // MicForegroundService, which runs only while something is listening.
    expect(xml, contains('foregroundServiceType="specialUse"'));

    // That type lives on the bridge plugin's own service, which the build
    // merges in. Checked here so the two halves cannot be separated: dropping
    // the plugin would leave the app with no way to record at all.
    final bridge = File(
      'packages/overlay_bridge/android/src/main/AndroidManifest.xml',
    );
    expect(bridge.existsSync(), isTrue);
    final bridgeXml = bridge.readAsStringSync();
    expect(bridgeXml, contains('.MicForegroundService'));
    expect(bridgeXml, contains('foregroundServiceType="microphone"'));
  });

  test('background location is not asked for', () {
    final xml = manifest.readAsStringSync();
    // Nothing requests it: the Wi-Fi monitor asks for the foreground
    // permission only. Declaring it put every build in front of Play's
    // background-location review for a capability the app never uses.
    expect(xml, isNot(contains('ACCESS_BACKGROUND_LOCATION')));
  });

  test('the backup leaves the stored API key behind', () {
    final xml = manifest.readAsStringSync();
    // Backup is on, because the study data is worth keeping. The preferences
    // file is held back from it, because the Gemini API key sits there in
    // plain text and would otherwise travel to Google's backup and to any
    // new device.
    expect(xml, contains('android:fullBackupContent="@xml/backup_rules"'));
    expect(
      xml,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );

    for (final rules in [
      File('android/app/src/main/res/xml/backup_rules.xml'),
      File('android/app/src/main/res/xml/data_extraction_rules.xml'),
    ]) {
      expect(rules.existsSync(), isTrue, reason: '${rules.path} is missing');
      expect(
        rules.readAsStringSync(),
        contains('path="FlutterSharedPreferences.xml"'),
      );
    }
  });
}
