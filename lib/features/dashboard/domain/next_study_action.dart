import 'package:flutter/foundation.dart';

/// Which of the day's study jobs is the one to do now.
enum StudyActionKind {
  /// Spaced reviews that have come due.
  dueReviews,

  /// A micro-commitment from today's plan that is not ticked off.
  unfinishedTask,

  /// Questions already answered wrong and not yet mastered.
  mistakeDrill,

  /// A topic marked weak, with nothing more specific to go at.
  weakTopic,

  /// Nothing is waiting.
  allClear,
}

/// The one thing to do next, with the reason it was chosen.
@immutable
class NextStudyAction {
  const NextStudyAction({
    required this.kind,
    required this.title,
    required this.why,
    required this.minutes,
    this.count = 0,
  });

  final StudyActionKind kind;

  /// What to do, in a few words.
  final String title;

  /// Why this one and not another. Shown, because a recommendation nobody can
  /// see the reason for is just another thing to distrust.
  final String why;

  /// Roughly how long it takes. The number that decides whether a tired person
  /// starts at all.
  final int minutes;

  /// How many of whatever it is, where that means something.
  final int count;

  bool get isAllClear => kind == StudyActionKind.allClear;
}

/// Picks the one job worth starting now.
///
/// The dashboard offers six separate calls to action — the plan's tasks, due
/// reviews, the mistake bank, the weakness healer, weak topics, the next
/// exam's revision — and ranks none of them. For somebody opening the app
/// tired after a day's work, choosing between six is the hard part, which is
/// the whole reason micro-commitments exist in the first place. This answers
/// the question instead of presenting it.
///
/// The order is deliberate:
///
/// 1. Due spaced reviews, because they are the only time-sensitive thing here.
///    A card due today and skipped loses its interval, and the whole point of
///    the schedule is that the day matters.
/// 2. An unfinished task from today's plan, because the plan was already sized
///    to today's energy and fatigue — something else has already done the
///    thinking about what fits.
/// 3. Mistakes not yet mastered: the highest-yield revision there is, since
///    these are questions already known to be wrong, but nothing is lost by
///    doing them tomorrow instead.
/// 4. A weak topic, last, because it is the broadest and least specific — a
///    subject rather than a task.
NextStudyAction pickNextStudyAction({
  required int dueReviews,
  String? unfinishedTaskTitle,
  int unfinishedTaskMinutes = 10,
  required int activeMistakes,
  required int weakTopics,
}) {
  if (dueReviews > 0) {
    return NextStudyAction(
      kind: StudyActionKind.dueReviews,
      title: '$dueReviews টি রিভিশন কার্ড আজ জমা',
      why: 'আজ না দেখলে ব্যবধানটা নষ্ট হয়',
      // A card is a glance, not a sitting. Capped so the figure stays
      // startable: "৪০ মিনিট" is a reason to put the phone down.
      minutes: dueReviews.clamp(1, 12),
      count: dueReviews,
    );
  }

  final task = unfinishedTaskTitle?.trim() ?? '';
  if (task.isNotEmpty) {
    return NextStudyAction(
      kind: StudyActionKind.unfinishedTask,
      title: task,
      why: 'আজকের রুটিনে আপনার এনার্জি অনুযায়ী বসানো',
      minutes: unfinishedTaskMinutes.clamp(1, 60),
      count: 1,
    );
  }

  if (activeMistakes > 0) {
    return NextStudyAction(
      kind: StudyActionKind.mistakeDrill,
      title: '$activeMistakes টি ভুল প্রশ্ন এখনো আয়ত্তে আসেনি',
      why: 'যেগুলো ভুল হয়েছে, সেগুলোই সবচেয়ে কাজে দেয়',
      minutes: (activeMistakes * 3 ~/ 2).clamp(2, 10),
      count: activeMistakes,
    );
  }

  if (weakTopics > 0) {
    return NextStudyAction(
      kind: StudyActionKind.weakTopic,
      title: '$weakTopics টি দুর্বল টপিক চিহ্নিত',
      why: 'নির্দিষ্ট কিছু বাকি নেই — টপিক ধরে এগোন',
      minutes: 3,
      count: weakTopics,
    );
  }

  return const NextStudyAction(
    kind: StudyActionKind.allClear,
    title: 'আজকের জন্য সব শেষ',
    why: 'নতুন পাতা স্ক্যান করে প্রশ্ন যোগ করতে পারেন',
    minutes: 0,
  );
}
