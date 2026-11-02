/// How many cards to queue ahead for the push series.
///
/// The queue is only rebuilt when the app is opened. A fixed twelve covered
/// about one day at hourly pushes, so a couple of days without opening the
/// app and the pushes simply stopped — with nothing to say why, which reads
/// as the feature having broken.
///
/// The count now follows the user's own window and interval, so a short
/// interval queues more and a long one queues fewer, and either way it lasts
/// [daysOfCover] days of not opening the app.
int flashcardQueueDepth({
  required int startHour,
  required int endHour,
  required int intervalMinutes,
  int daysOfCover = 3,
  int cap = 60,
}) {
  final windowHours = endHour - startHour;
  if (windowHours <= 0 || intervalMinutes <= 0) return 1;

  final perDay = (windowHours * 60) ~/ intervalMinutes;
  if (perDay <= 0) return 1;

  final wanted = perDay * daysOfCover;
  return wanted.clamp(1, cap);
}
