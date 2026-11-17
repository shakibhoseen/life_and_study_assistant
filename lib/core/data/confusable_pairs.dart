/// The two things you keep swapping.
///
/// The app already records which option was picked and which was right. It
/// has never read the pair together, and the pair is the useful part: "কারকে
/// দুর্বল" sends somebody to re-read a whole chapter, while "অপাদান আর
/// অধিকরণ গুলিয়ে ফেলেন" is an afternoon's work on one distinction.
///
/// Nothing new is stored. This reads what every wrong answer already left
/// behind.
library;

/// A wrong answer, reduced to the two options involved.
class ConfusionEvidence {
  /// The option the user picked.
  final String chosen;

  /// The option that was right.
  final String correct;

  final String topic;

  const ConfusionEvidence({
    required this.chosen,
    required this.correct,
    required this.topic,
  });
}

/// Two options that keep being swapped for each other.
class ConfusablePair {
  /// The two options, in a stable order so the same pair reads the same way
  /// every time it is shown.
  final String first;
  final String second;

  /// How many wrong answers this pair accounts for.
  final int times;

  /// Where it happens most.
  final String topic;

  const ConfusablePair({
    required this.first,
    required this.second,
    required this.times,
    required this.topic,
  });
}

/// Longest an option can be and still be a thing you confuse.
///
/// A question whose options are full sentences has no "pair": picking the
/// wrong sentence is not a mix-up between two terms, and reporting it as one
/// would bury the real pairs under noise. Terms, names, dates and short
/// phrases are where confusion actually lives.
const int confusableMaxLength = 40;

/// How often a pair must recur before it is worth naming.
///
/// Once is a slip. The whole claim being made here is "you keep doing this",
/// and it should not be made on a single occurrence.
const int confusableMinTimes = 2;

/// Strips a leading option marker so "ক. অপাদান" and "অপাদান" are one thing.
String normaliseOption(String option) {
  final trimmed = option.trim();
  final marker = RegExp(r'^([ক-হA-Ha-h০-৯0-9])\s*[.):।]\s+');
  final match = marker.firstMatch(trimmed);
  final rest = match == null ? trimmed : trimmed.substring(match.end).trim();
  // "ক." alone is the answer itself, not a marker on something else.
  return (rest.isEmpty ? trimmed : rest).replaceAll(RegExp(r'\s+'), ' ');
}

/// The pairs the user keeps swapping, commonest first.
List<ConfusablePair> findConfusablePairs(
  List<ConfusionEvidence> evidence, {
  int minTimes = confusableMinTimes,
  int maxLength = confusableMaxLength,
}) {
  // Keyed by the unordered pair: which way round it went varies, and the
  // remedy — learn the difference — is the same either way.
  final counts = <String, int>{};
  final shown = <String, (String, String)>{};
  final topics = <String, Map<String, int>>{};

  for (final item in evidence) {
    final chosen = normaliseOption(item.chosen);
    final correct = normaliseOption(item.correct);

    if (chosen.isEmpty || correct.isEmpty) continue;
    if (chosen == correct) continue;
    if (chosen.length > maxLength || correct.length > maxLength) continue;

    final ordered = [chosen, correct]..sort();
    final key = ordered.join('\u0000');

    counts[key] = (counts[key] ?? 0) + 1;
    shown[key] ??= (ordered[0], ordered[1]);

    final topic = item.topic.trim();
    if (topic.isEmpty) continue;
    final perTopic = topics.putIfAbsent(key, () => <String, int>{});
    perTopic[topic] = (perTopic[topic] ?? 0) + 1;
  }

  final pairs = <ConfusablePair>[];
  for (final entry in counts.entries) {
    if (entry.value < minTimes) continue;
    final texts = shown[entry.key]!;

    final perTopic = topics[entry.key];
    var topic = '';
    if (perTopic != null && perTopic.isNotEmpty) {
      final ranked = perTopic.entries.toList()
        ..sort((a, b) {
          final byCount = b.value.compareTo(a.value);
          return byCount != 0 ? byCount : a.key.compareTo(b.key);
        });
      topic = ranked.first.key;
    }

    pairs.add(
      ConfusablePair(
        first: texts.$1,
        second: texts.$2,
        times: entry.value,
        topic: topic,
      ),
    );
  }

  pairs.sort((a, b) {
    final byTimes = b.times.compareTo(a.times);
    // Alphabetical on a tie, so the list does not reshuffle between builds.
    return byTimes != 0 ? byTimes : a.first.compareTo(b.first);
  });
  return pairs;
}
