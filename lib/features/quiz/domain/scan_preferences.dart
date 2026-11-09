import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/notification_constants.dart';
import '../../../core/services/ai/ai_media_limits.dart';

/// What the user has chosen about how a page is scanned.
///
/// These lived only in the scanning sheet's own state, so each one was
/// forgotten the moment the sheet closed: somebody who wanted full-resolution
/// pages with no AI-invented answers had to say so again for every page they
/// scanned. A control that does not stick is not a control, so they are kept
/// here and read back the next time.
///
/// The defaults are the careful ones. They are what someone gets before they
/// have expressed any preference, and the point of the careful side is that a
/// wrong answer is worse than a blank.
@immutable
class ScanPreferences {
  const ScanPreferences({
    this.trustPrintedAnswersOnly = true,
    this.withExplanations = false,
    this.crossCheckAnswers = true,
    this.detail = CaptureDetail.high,
  });

  /// Only an answer printed on the page is kept.
  final bool trustPrintedAnswersOnly;

  /// An explanation is written even where the page prints none.
  final bool withExplanations;

  /// The answers are read a second time and compared.
  final bool crossCheckAnswers;

  /// How much of the photo is sent.
  final CaptureDetail detail;

  ScanPreferences copyWith({
    bool? trustPrintedAnswersOnly,
    bool? withExplanations,
    bool? crossCheckAnswers,
    CaptureDetail? detail,
  }) {
    return ScanPreferences(
      trustPrintedAnswersOnly:
          trustPrintedAnswersOnly ?? this.trustPrintedAnswersOnly,
      withExplanations: withExplanations ?? this.withExplanations,
      crossCheckAnswers: crossCheckAnswers ?? this.crossCheckAnswers,
      detail: detail ?? this.detail,
    );
  }

  /// Reads what was chosen last time, falling back to the careful defaults.
  static Future<ScanPreferences> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return fromNames(
        trust: prefs.getBool(NotificationConstants.prefScanTrustPrintedAnswers),
        explain: prefs.getBool(NotificationConstants.prefScanWithExplanations),
        crossCheck: prefs.getBool(NotificationConstants.prefScanCrossCheck),
        detailName: prefs.getString(NotificationConstants.prefScanDetail),
      );
    } catch (e) {
      debugPrint('Scan preferences could not be read, using defaults: $e');
      return const ScanPreferences();
    }
  }

  /// Builds from stored values, ignoring anything unrecognised.
  ///
  /// Separate from [load] so the decisions can be tested without a platform:
  /// a detail name from an older build, or a renamed one, must not leave the
  /// scanner without a setting.
  @visibleForTesting
  static ScanPreferences fromNames({
    bool? trust,
    bool? explain,
    bool? crossCheck,
    String? detailName,
  }) {
    const fallback = ScanPreferences();
    return ScanPreferences(
      trustPrintedAnswersOnly: trust ?? fallback.trustPrintedAnswersOnly,
      withExplanations: explain ?? fallback.withExplanations,
      crossCheckAnswers: crossCheck ?? fallback.crossCheckAnswers,
      detail: CaptureDetail.values
          .where((d) => d.name == detailName)
          .firstOrNull ??
          fallback.detail,
    );
  }

  /// Remembers this choice. A failure here is not worth interrupting a scan
  /// for; the setting simply does not stick, and the user can set it again.
  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(
        NotificationConstants.prefScanTrustPrintedAnswers,
        trustPrintedAnswersOnly,
      );
      await prefs.setBool(
        NotificationConstants.prefScanWithExplanations,
        withExplanations,
      );
      await prefs.setBool(
        NotificationConstants.prefScanCrossCheck,
        crossCheckAnswers,
      );
      await prefs.setString(
        NotificationConstants.prefScanDetail,
        detail.name,
      );
    } catch (e) {
      debugPrint('Scan preferences could not be saved: $e');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ScanPreferences &&
      other.trustPrintedAnswersOnly == trustPrintedAnswersOnly &&
      other.withExplanations == withExplanations &&
      other.crossCheckAnswers == crossCheckAnswers &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(
    trustPrintedAnswersOnly,
    withExplanations,
    crossCheckAnswers,
    detail,
  );
}
