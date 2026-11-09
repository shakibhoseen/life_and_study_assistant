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

  /// JPEG quality for the one re-encode a photo is allowed.
  ///
  /// One, not three. A photo used to be re-encoded by the picker, again by the
  /// crop screen and again on its way to the model, each pass eating the thin
  /// strokes that tell খ, ঘ and ব apart in Bengali print. The picker hands
  /// over what the camera gave it, the crop screen writes at
  /// [cropQuality], and this is the single lossy step, just before the
  /// request.
  static const int jpegQuality = 92;

  /// What the crop screen writes its result at.
  ///
  /// Near enough to lossless to not be a second reduction. The crop has to
  /// write a file, so it cannot avoid re-encoding; it can avoid throwing
  /// anything away while it does.
  static const int cropQuality = 100;

  /// Nothing. The picker hands over the photo as the camera took it.
  ///
  /// It used to cap the longest side at 2048, with a comment explaining that
  /// the picker is not the place to economise because detail thrown away there
  /// cannot be recovered by raising the setting afterwards. That reasoning was
  /// right and the number contradicted it: a 4624px page arrived already down
  /// to 1920 or 2048 before the user's own choice was even consulted.
  ///
  /// The only reduction now is the one the user picked, and
  /// [CaptureDetail.full] means none at all.
  static const double? pickerMaxDimension = null;
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
  high(1280, 1032, 'পুরো পাতা', 'দূর থেকে তোলা পুরো পাতা, ছোট লেখা'),

  /// The photo as taken, with nothing taken off it.
  ///
  /// Here because the choice is the user's to make, and until now the ceiling
  /// was 1280 however much detail the page needed. Measured on one
  /// question-bank page: two readings of it at 1280 disagreed on six answers
  /// out of eighteen, every one a খ/ঘ/ব mix-up — the strokes that separate
  /// those letters are a pixel or two wide, and this is the step that was
  /// losing them.
  ///
  /// The token figure is a guess for a typical phone photo and will be wrong
  /// for any particular one; the badge during a scan reports what it actually
  /// cost, which is the number worth looking at.
  full(0, 3100, 'পূর্ণ', 'যেমন তুলেছেন তেমনই — ছোট করা হবে না');

  const CaptureDetail(this.dimension, this.approxTokens, this.label, this.hint);

  /// Longest side, in pixels, the photo is reduced to. Zero means it is not.
  final int dimension;

  /// Whether this setting reduces the photo at all.
  bool get reduces => dimension > 0;

  /// Roughly what the image alone costs at this size.
  final int approxTokens;

  final String label;
  final String hint;
}

/// Rough token cost of a call, worked out on the phone before it is made.
///
/// A non-streaming call reports nothing until it returns, so a wait can only
/// show what the request is likely to cost, not what it has spent. Shown as
/// an estimate, it answers the question a bare spinner cannot: is this doing
/// something, and roughly how much is it worth.
///
/// Bengali runs about 1.5 characters to the token against roughly 4 for
/// English, and a prompt here is mostly English instructions around Bengali
/// content, so 2.5 is the middle of that range. The image figure comes from
/// the tile arithmetic above, which is exact.
/// Why nothing here caps the model's output length.
///
/// `maxOutputTokens` is not a cap on the reply — it is the budget the reply
/// and the model's own reasoning are both paid from. Measured against
/// gemini-flash-latest on one question-bank page: the model spent 7,862
/// tokens thinking and was left 316 for the answer, which truncated the JSON
/// mid-object and lost the whole page. The cap did not keep the cost down; it
/// threw away what had already been paid for.
///
/// So no request sets it, and the model is allowed to finish. What a reply
/// should contain belongs in the prompt, which is read before the work starts
/// and not enforced by cutting the answer off partway through.
///
/// [estimateRequestTokens] is still here and still useful: an estimate shown
/// to the user before they spend is a different thing from a limit imposed on
/// the model while it works.
int estimateRequestTokens({
  required int promptChars,
  CaptureDetail? image,
  int expectedOutputTokens = 0,
}) {
  final promptTokens = (promptChars / 2.5).ceil();
  return promptTokens + (image?.approxTokens ?? 0) + expectedOutputTokens;
}
