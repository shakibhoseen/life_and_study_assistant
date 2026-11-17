/// Why a question was got wrong — not which topic it was in.
///
/// The app already knows where the user is weak. What it has never known is
/// what kind of wrong they go. "শতকরায় দুর্বল" is a fact about a chapter;
/// "আমি তাড়াহুড়োয় বিয়োগে ভুল করি" is a fact about a person, and only the
/// second one tells anybody what to do differently tomorrow.
///
/// The five kinds are chosen so that each has a *different remedy*. That is
/// the whole test of the list: two kinds that lead to the same action should
/// be one kind, and a kind nobody can act on should not be offered. More
/// options would be easy to invent and would only make the tagging slower,
/// which is the thing that kills a habit like this.
library;

enum MistakeKind {
  /// Never learnt it. The remedy is to go and learn it.
  neverKnew,

  /// Knew it once. The remedy is revision, not study.
  forgot,

  /// Knew the method and slipped. The remedy is slower arithmetic, not more
  /// theory — and the topic is not actually weak.
  calculation,

  /// Answered a question other than the one asked. The remedy is exam
  /// technique, and it is invisible in any topic-based view.
  misread,

  /// Knew the material and picked the plausible wrong option. The remedy is
  /// the distinction between those two specific things.
  trap,
}

extension MistakeKindText on MistakeKind {
  /// Stored as the enum name, so these can change freely.
  String get label => switch (this) {
    MistakeKind.neverKnew => 'জানতাম না',
    MistakeKind.forgot => 'জানতাম, ভুলে গেছি',
    MistakeKind.calculation => 'হিসাবে ভুল',
    MistakeKind.misread => 'প্রশ্ন ভুল পড়েছি',
    MistakeKind.trap => 'ফাঁদে পড়েছি',
  };

  /// What this kind of mistake asks the user to do differently.
  String get remedy => switch (this) {
    MistakeKind.neverKnew => 'টপিকটা একবার পড়ে ফেলুন — এটা ফাঁক, ভুল নয়।',
    MistakeKind.forgot => 'রিভিশনে পাঠান। পড়া নয়, মনে রাখাটাই এখানে কাজ।',
    MistakeKind.calculation =>
      'টপিক দুর্বল নয় — হিসাবটা ধীরে করুন, শেষে একবার মিলিয়ে নিন।',
    MistakeKind.misread =>
      'প্রশ্নে "নয়", "ছাড়া", "সঠিক নয়" জাতীয় শব্দ দাগিয়ে পড়ার অভ্যাস করুন।',
    MistakeKind.trap =>
      'যে দুটো অপশন গুলিয়েছেন, সেই দুটোর পার্থক্যটা আলাদা করে দেখে নিন।',
  };
}

/// Parses a stored name back, tolerating a value this build does not know.
MistakeKind? mistakeKindFromName(String? name) {
  if (name == null || name.isEmpty) return null;
  for (final kind in MistakeKind.values) {
    if (kind.name == name) return kind;
  }
  return null;
}

/// How often each kind happens, and where.
class MistakePattern {
  /// Tagged mistakes per kind, commonest first.
  final List<MapEntry<MistakeKind, int>> byKind;

  /// Mistakes that have been tagged at all.
  final int tagged;

  /// Mistakes with no tag yet. Shown so a thin pattern is read as thin
  /// rather than as the truth about the user.
  final int untagged;

  /// For each kind, the topic it happens in most, and how often.
  final Map<MistakeKind, MapEntry<String, int>> worstTopicByKind;

  const MistakePattern({
    required this.byKind,
    required this.tagged,
    required this.untagged,
    required this.worstTopicByKind,
  });

  static const MistakePattern empty = MistakePattern(
    byKind: [],
    tagged: 0,
    untagged: 0,
    worstTopicByKind: {},
  );

  MistakeKind? get dominant => byKind.isEmpty ? null : byKind.first.key;

  /// Share of tagged mistakes the commonest kind accounts for, 0..1.
  double get dominantShare =>
      tagged == 0 || byKind.isEmpty ? 0 : byKind.first.value / tagged;

  /// Whether there is enough here to say anything.
  ///
  /// Four tagged mistakes can make any kind look like 50% of a person. The
  /// screen says so rather than drawing a conclusion from them.
  bool get isThin => tagged < 8;
}

/// One mistake, as the pattern sees it.
class TaggedMistake {
  final MistakeKind? kind;
  final String topic;

  const TaggedMistake({required this.kind, required this.topic});
}

/// Counts the kinds, and finds where each one concentrates.
MistakePattern summariseMistakes(List<TaggedMistake> mistakes) {
  if (mistakes.isEmpty) return MistakePattern.empty;

  final counts = <MistakeKind, int>{};
  final topics = <MistakeKind, Map<String, int>>{};
  var untagged = 0;

  for (final mistake in mistakes) {
    final kind = mistake.kind;
    if (kind == null) {
      untagged++;
      continue;
    }
    counts[kind] = (counts[kind] ?? 0) + 1;

    final topic = mistake.topic.trim();
    if (topic.isEmpty) continue;
    final perTopic = topics.putIfAbsent(kind, () => <String, int>{});
    perTopic[topic] = (perTopic[topic] ?? 0) + 1;
  }

  final byKind = counts.entries.toList()
    // Commonest first; ties broken by the enum's own order so the list does
    // not reshuffle itself between builds.
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      return byCount != 0 ? byCount : a.key.index.compareTo(b.key.index);
    });

  final worst = <MistakeKind, MapEntry<String, int>>{};
  for (final entry in topics.entries) {
    final ranked = entry.value.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    if (ranked.isNotEmpty) worst[entry.key] = ranked.first;
  }

  return MistakePattern(
    byKind: byKind,
    tagged: counts.values.fold(0, (a, b) => a + b),
    untagged: untagged,
    worstTopicByKind: worst,
  );
}
