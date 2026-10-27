/// Sizing rules for images sent to Gemini.
///
/// Gemini bills an image by tiling it into 768x768 squares at 258 tokens a
/// tile (anything up to 384x384 is a single tile). That makes cost a step
/// function of the longest side, not a smooth curve, and the steps are what
/// matter when picking a size. For a 4:3 phone photo:
///
///   1920 -> 1440x1920 -> 2x3 tiles -> 1548 tokens
///   1600 -> 1200x1600 -> 2x3 tiles -> 1548 tokens   (no saving at all)
///   1280 ->  960x1280 -> 2x2 tiles -> 1032 tokens   (-33%)
///   1024 ->  768x1024 -> 1x2 tiles ->  516 tokens   (-67%)
///
/// So shrinking from 1920 to 1600 buys nothing, while 1024 lands the width
/// exactly on one tile and cuts the cost by two thirds. 1280 is the middle
/// step: a real saving while keeping noticeably more detail than 1024, which
/// matters because these photos are read for Bengali text where conjuncts
/// and matras blur first.
class AiMediaLimits {
  AiMediaLimits._();

  /// Longest side of an image handed to the model.
  ///
  /// Sits on a tile boundary on purpose; see the table above before changing
  /// it, because intermediate values cost the same as the step above them.
  static const int maxImageDimension = 1280;

  /// JPEG quality used when re-encoding.
  static const int jpegQuality = 85;

  /// What the image picker is allowed to hand over.
  ///
  /// Above every [CaptureDetail] on purpose. The picker is not the place to
  /// economise: if it cropped straight to the chosen preset, raising the
  /// setting afterwards could not recover detail that was already thrown
  /// away. The real reduction happens just before the request instead.
  static const int pickerHeadroom = 2048;
}

/// How much detail a photo needs, chosen before the shot is taken.
///
/// Verified against a real page of Khairul's Basic Math shot in landscape
/// from close range: the Bengali text, the conjuncts and the fractions all
/// stayed legible down to 768px. A whole page shot from further away puts
/// roughly half that many pixels on each character, so it needs a step up.
///
/// Each value sits on a 768px tile boundary, because anything between two
/// boundaries costs the same as the boundary above it.
enum CaptureDetail {
  low(768, 258, 'কাছ থেকে', 'একটি MCQ বা কয়েক লাইন, বড় লেখা'),
  standard(1024, 516, 'সাধারণ', 'আধা পাতা বা একটি অনুচ্ছেদ'),
  high(1280, 1032, 'পুরো পাতা', 'দূর থেকে তোলা পুরো পাতা, ছোট লেখা');

  const CaptureDetail(this.dimension, this.approxTokens, this.label, this.hint);

  /// Longest side, in pixels, the photo is reduced to.
  final int dimension;

  /// Roughly what the image alone costs at this size.
  final int approxTokens;

  final String label;
  final String hint;
}
