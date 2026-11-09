import 'package:shared_preferences/shared_preferences.dart';

import '../../config/notification_constants.dart';
import 'ai_cancellation.dart';

/// The models an AI call is allowed to use, in order.
///
/// The model is the user's choice, made in Settings. Swapping it for another
/// one when the first is busy sounds helpful and is not: the replacement is
/// usually a cheaper, weaker model, nothing on screen says the swap happened,
/// and the user is left wondering why the same page scanned worse today than
/// yesterday. So by default the answer is "the one they chose, and no other";
/// a busy server is waited out instead, which is what a 503 actually asks for.
///
/// Somebody who would rather have a weaker answer than none can turn
/// [NotificationConstants.prefAllowModelFallback] on.
Future<List<String>> modelsToTryFor(String preferred) async {
  bool allowFallback = false;
  try {
    final prefs = await SharedPreferences.getInstance();
    allowFallback =
        prefs.getBool(NotificationConstants.prefAllowModelFallback) ?? false;
  } catch (_) {
    // Unreadable settings mean the careful default, not a free-for-all.
  }

  if (!allowFallback) return [preferred];

  return [
    preferred,
    if (preferred != 'gemini-flash-latest') 'gemini-flash-latest',
    if (preferred != 'gemini-flash-lite-latest') 'gemini-flash-lite-latest',
  ];
}

/// Whether this failure is the server saying it is busy rather than anything
/// being wrong with the request.
///
/// Observed from the API: `503 UNAVAILABLE`, "This model is currently
/// experiencing high demand. Spikes in demand are usually temporary. Please
/// try again later." It is worth distinguishing, because the same request
/// succeeds a few seconds later — one measured scan went through on its second
/// attempt — whereas a bad key or an exhausted quota never will.
bool isServerBusy(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('503') ||
      text.contains('unavailable') ||
      text.contains('high demand') ||
      text.contains('overloaded');
}

/// How long to wait before each further attempt at a busy server.
///
/// Three tries over half a minute. A page scan is an expensive call the user
/// is already waiting on, so giving up at the first refusal wastes the whole
/// wait; going on much longer than this stops looking like working.
const List<Duration> serverBusyBackoff = [
  Duration(seconds: 5),
  Duration(seconds: 12),
  Duration(seconds: 25),
];

/// Runs [attempt], waiting and trying again while the server says it is busy.
///
/// Anything that is not a busy server is thrown straight away: a wrong key or
/// a malformed request will not fix itself, and retrying one only makes the
/// user wait longer for the same answer.
Future<T> withServerBusyRetry<T>(
  Future<T> Function() attempt, {
  void Function(int attemptNumber, Duration waiting)? onWaiting,
  AiCancellation? cancel,
}) async {
  for (var i = 0; ; i++) {
    if (cancel?.isCancelled ?? false) throw const AiCancelledException();
    try {
      return await attempt();
    } catch (error) {
      if (error is AiCancelledException) rethrow;
      if (i >= serverBusyBackoff.length || !isServerBusy(error)) rethrow;
      final wait = serverBusyBackoff[i];
      onWaiting?.call(i + 1, wait);
      // Waited through the cancellation rather than past it: these pauses run
      // to twenty-five seconds, and sitting them out after the user has asked
      // to stop is most of what "it is still going" feels like.
      if (cancel != null) {
        try {
          await cancel.guard(Future<void>.delayed(wait));
        } on AiCancelledException {
          rethrow;
        }
      } else {
        await Future<void>.delayed(wait);
      }
    }
  }
}
