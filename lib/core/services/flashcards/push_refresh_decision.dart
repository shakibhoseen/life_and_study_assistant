/// Whether the push queue should be rebuilt, or left to run as scheduled.
///
/// Rebuilding cancels every pending push and starts the next one a full
/// interval from now. So a rebuild on every app open means the first push
/// keeps being pushed back: with hourly pushes, opening the app every
/// forty-five minutes through the day means none of them ever fires.
///
/// The guard against that used to be a thirty-second cooldown held in
/// memory, which a fresh launch cleared — so it stopped a double rebuild
/// within one session and nothing else.
bool shouldRebuildPushQueue({
  required String fingerprint,
  required String? lastFingerprint,
  required DateTime? lastBuiltAt,
  required DateTime now,
  required Duration interval,
  bool force = false,
}) {
  // The user changed a setting and is waiting to see it take effect.
  if (force) return true;

  // Nothing has ever been queued.
  if (lastFingerprint == null || lastBuiltAt == null) return true;

  // The cards or the window changed, so what is queued is wrong.
  if (fingerprint != lastFingerprint) return true;

  // Otherwise leave the queue alone until a push would have gone out
  // anyway, so opening the app does not keep moving the next one.
  return now.difference(lastBuiltAt) >= interval;
}
