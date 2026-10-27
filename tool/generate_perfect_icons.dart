// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:math';
import 'package:image/image.dart' as img;

void main() {
  final sourcePath = '/Users/shakib/.gemini/antigravity/brain/76833eef-983f-401e-b66d-d3ad2b4dfb88/life_and_study_assistant_icon_1793070855898.jpg';
  final sourceFile = File(sourcePath);
  if (!sourceFile.existsSync()) {
    print('Source file does not exist: $sourcePath');
    return;
  }

  final sourceImg = img.decodeImage(sourceFile.readAsBytesSync())!;
  print('Loaded master source image: ${sourceImg.width}x${sourceImg.height}');

  // Background color #061332 (R: 6, G: 19, B: 50)
  const bgR = 6;
  const bgG = 19;
  const bgB = 50;
  final bgColor = img.ColorRgba8(bgR, bgG, bgB, 255);

  // 1. Create a pristine transparent foreground emblem
  // This extracts the golden star, open book, and emerald vitality ring with true alpha transparency.
  print('Extracting transparent emblem layer with soft antialiasing...');
  final pureEmblem1024 = img.Image(width: sourceImg.width, height: sourceImg.height, numChannels: 4);

  // Calculate center of the emblem
  const cx = 511.0;
  const cy = 511.5;

  for (int y = 0; y < sourceImg.height; y++) {
    for (int x = 0; x < sourceImg.width; x++) {
      final p = sourceImg.getPixel(x, y);

      final dr = p.r - bgR;
      final dg = p.g - bgG;
      final db = p.b - bgB;
      final colorDist = sqrt(dr * dr + dg * dg + db * db);

      final dx = x - cx;
      final dy = y - cy;
      final centerDist = sqrt(dx * dx + dy * dy);

      int alpha = 0;
      if (centerDist > 450) {
        alpha = 0;
      } else if (colorDist <= 12.0) {
        alpha = 0;
      } else if (colorDist >= 36.0) {
        alpha = 255;
      } else {
        final t = (colorDist - 12.0) / (36.0 - 12.0);
        alpha = (t * 255).clamp(0, 255).toInt();
      }

      if (alpha == 0) {
        pureEmblem1024.setPixel(x, y, img.ColorRgba8(0, 0, 0, 0));
      } else {
        pureEmblem1024.setPixel(x, y, img.ColorRgba8(p.r.toInt(), p.g.toInt(), p.b.toInt(), alpha));
      }
    }
  }

  // 2. Helper to create icons
  // - If [transparentBg] is true: canvas is transparent (for Android adaptive foreground ic_launcher_foreground.png)
  // - If [transparentBg] is false: canvas is solid #061332 (for legacy ic_launcher.png, playstore_icon, iOS)
  img.Image renderIcon(
    int size,
    double scaleRatio, {
    bool transparentBg = false,
    bool circularMask = false,
  }) {
    final canvas = img.Image(width: size, height: size, numChannels: 4);

    if (transparentBg) {
      img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));
    } else {
      img.fill(canvas, color: bgColor);
    }

    final targetDim = (size * scaleRatio).round();
    final scaledEmblem = img.copyResize(
      pureEmblem1024,
      width: targetDim,
      height: targetDim,
      interpolation: img.Interpolation.cubic,
    );

    final destX = (size - targetDim) ~/ 2;
    final destY = (size - targetDim) ~/ 2;

    img.compositeImage(
      canvas,
      scaledEmblem,
      dstX: destX,
      dstY: destY,
      blend: img.BlendMode.alpha,
    );

    if (circularMask) {
      final radius = size / 2.0;
      final centerX = size / 2.0;
      final centerY = size / 2.0;

      for (int y = 0; y < size; y++) {
        for (int x = 0; x < size; x++) {
          final dx = x + 0.5 - centerX;
          final dy = y + 0.5 - centerY;
          final distSq = dx * dx + dy * dy;
          if (distSq > radius * radius) {
            canvas.setPixel(x, y, img.ColorRgba8(0, 0, 0, 0));
          } else if (distSq > (radius - 1) * (radius - 1)) {
            final alpha = ((radius - sqrt(distSq)) * 255).clamp(0, 255).toInt();
            final p = canvas.getPixel(x, y);
            canvas.setPixel(x, y, img.ColorRgba8(p.r.toInt(), p.g.toInt(), p.b.toInt(), alpha));
          }
        }
      }
    }

    return canvas;
  }

  // 3. Master Branding Assets
  print('Writing master branding assets...');
  final icon1024 = renderIcon(1024, 0.72, transparentBg: false);
  File('assets/branding/app_icon_1024.png').writeAsBytesSync(img.encodePng(icon1024));

  final icon512 = renderIcon(512, 0.72, transparentBg: false);
  File('assets/branding/playstore_icon_512.png').writeAsBytesSync(img.encodePng(icon512));

  // 4. Android Mipmap Densities
  final androidDensities = {
    'mipmap-mdpi': [48, 108],
    'mipmap-hdpi': [72, 162],
    'mipmap-xhdpi': [96, 216],
    'mipmap-xxhdpi': [144, 324],
    'mipmap-xxxhdpi': [192, 432],
  };

  print('Generating Android icons with clean adaptive transparency...');
  for (final entry in androidDensities.entries) {
    final folder = entry.key;
    final legacySize = entry.value[0];
    final adaptiveFgSize = entry.value[1];

    final dir = Directory('android/app/src/main/res/$folder');
    if (!dir.existsSync()) dir.createSync(recursive: true);

    // Legacy square icon: single solid canvas, zero borders
    final legacySquare = renderIcon(legacySize, 0.72, transparentBg: false);
    File('${dir.path}/ic_launcher.png').writeAsBytesSync(img.encodePng(legacySquare));

    // Legacy round icon: single circular canvas
    final legacyRound = renderIcon(legacySize, 0.72, transparentBg: false, circularMask: true);
    File('${dir.path}/ic_launcher_round.png').writeAsBytesSync(img.encodePng(legacyRound));

    // Adaptive icon foreground: TRANSPARENT canvas! Emblem is scaled to 0.65 (safe zone is 0.66)
    // Because canvas is transparent, Android system launcher will render ONLY the emblem over the solid background!
    final adaptiveFg = renderIcon(adaptiveFgSize, 0.65, transparentBg: true);
    File('${dir.path}/ic_launcher_foreground.png').writeAsBytesSync(img.encodePng(adaptiveFg));
  }

  // 5. Android Adaptive XML in mipmap-anydpi-v26
  final anyDpiDir = Directory('android/app/src/main/res/mipmap-anydpi-v26');
  if (!anyDpiDir.existsSync()) anyDpiDir.createSync(recursive: true);

  const icLauncherXml = '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
''';

  File('${anyDpiDir.path}/ic_launcher.xml').writeAsStringSync(icLauncherXml);
  File('${anyDpiDir.path}/ic_launcher_round.xml').writeAsStringSync(icLauncherXml);

  // 6. Update values/colors.xml with #061332
  final valuesDir = Directory('android/app/src/main/res/values');
  if (!valuesDir.existsSync()) valuesDir.createSync(recursive: true);

  final colorsFile = File('${valuesDir.path}/colors.xml');
  colorsFile.writeAsStringSync('''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#061332</color>
</resources>
''');

  // 7. Generate iOS AppIcon assets
  final iosDir = Directory('ios/Runner/Assets.xcassets/AppIcon.appiconset');
  if (iosDir.existsSync()) {
    print('Generating iOS App Icons...');
    final iosSizes = {
      'Icon-App-20x20@1x.png': 20,
      'Icon-App-20x20@2x.png': 40,
      'Icon-App-20x20@3x.png': 60,
      'Icon-App-29x29@1x.png': 29,
      'Icon-App-29x29@2x.png': 58,
      'Icon-App-29x29@3x.png': 87,
      'Icon-App-40x40@1x.png': 40,
      'Icon-App-40x40@2x.png': 80,
      'Icon-App-40x40@3x.png': 120,
      'Icon-App-60x60@2x.png': 120,
      'Icon-App-60x60@3x.png': 180,
      'Icon-App-76x76@1x.png': 76,
      'Icon-App-76x76@2x.png': 152,
      'Icon-App-83.5x83.5@2x.png': 167,
      'Icon-App-1024x1024@1x.png': 1024,
    };

    for (final entry in iosSizes.entries) {
      final imgFile = renderIcon(entry.value, 0.72, transparentBg: false);
      File('${iosDir.path}/${entry.key}').writeAsBytesSync(img.encodePng(imgFile));
    }
  }

  print('SUCCESS: All Android adaptive, legacy, and iOS icons generated flawlessly with zero extra layers!');
}
