import 'dart:ui';

/// Maps a crop drawn on screen back onto the photo's own pixels.
///
/// The photo is shown scaled to fit its box, so the rectangle the user draws
/// is in screen units while the crop has to happen in image units. Getting
/// this wrong is the kind of mistake that looks fine until the cropped page
/// comes back shifted, so it lives apart from the widget and is tested on
/// its own.
class CropGeometry {
  /// Where a [imageWidth] x [imageHeight] photo sits inside [box] when scaled
  /// to fit it whole, centred, with its proportions kept.
  static Rect fittedImageRect({
    required Size box,
    required int imageWidth,
    required int imageHeight,
  }) {
    if (imageWidth <= 0 || imageHeight <= 0) return Offset.zero & box;

    final scale = (box.width / imageWidth) < (box.height / imageHeight)
        ? box.width / imageWidth
        : box.height / imageHeight;
    final width = imageWidth * scale;
    final height = imageHeight * scale;
    return Rect.fromLTWH(
      (box.width - width) / 2,
      (box.height - height) / 2,
      width,
      height,
    );
  }

  /// The pixel rectangle of [displayRect], which is drawn in [box] over a
  /// photo of [imageWidth] x [imageHeight].
  ///
  /// Clamped to the photo, so a frame dragged past the edge crops to the edge
  /// rather than to coordinates that do not exist.
  static Rect toImagePixels({
    required Rect displayRect,
    required Size box,
    required int imageWidth,
    required int imageHeight,
  }) {
    final fitted = fittedImageRect(
      box: box,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
    );
    if (fitted.width <= 0 || fitted.height <= 0) {
      return Rect.fromLTWH(0, 0, imageWidth.toDouble(), imageHeight.toDouble());
    }

    final scale = imageWidth / fitted.width;
    final left = ((displayRect.left - fitted.left) * scale).clamp(
      0.0,
      imageWidth.toDouble(),
    );
    final top = ((displayRect.top - fitted.top) * scale).clamp(
      0.0,
      imageHeight.toDouble(),
    );
    final right = ((displayRect.right - fitted.left) * scale).clamp(
      0.0,
      imageWidth.toDouble(),
    );
    final bottom = ((displayRect.bottom - fitted.top) * scale).clamp(
      0.0,
      imageHeight.toDouble(),
    );

    return Rect.fromLTRB(left, top, right, bottom);
  }
}
