/// Rules for tidying study data that has drifted apart over time.
///
/// Two things went wrong on their own. The same subject arrived under an
/// English and a Bengali name depending on which screen created it, so one
/// subject's figures were split across two — ten questions under
/// "বাংলাদেশ বিষয়াবলী" and six under "Bangladesh Affairs". And weak topics
/// accumulated near-duplicates, along with entries where an exam's title had
/// been used as the topic.
///
/// The rules live here, apart from the database and the screen, because they
/// decide what gets merged and that is the part worth being sure of.
library;

/// The one name to keep for a subject that has been saved under several.
///
/// Bengali is the app's language, so that is the side kept. Only pairs that
/// are plainly the same subject are listed: a guess here merges two subjects
/// that should have stayed apart, which is worse than leaving them split.
const Map<String, String> _subjectAliases = {
  'bangladesh affairs': 'বাংলাদেশ বিষয়াবলী',
  'bangladesh affair': 'বাংলাদেশ বিষয়াবলী',
  'mathematics': 'গাণিতিক যুক্তি',
  'math': 'গাণিতিক যুক্তি',
  'maths': 'গাণিতিক যুক্তি',
  'general science': 'সাধারণ বিজ্ঞান',
  'science': 'সাধারণ বিজ্ঞান',
  'bangla literature': 'বাংলা সাহিত্য',
  'bangla grammar': 'বাংলা ব্যাকরণ',
  'english grammar': 'ইংরেজি',
  'english': 'ইংরেজি',
  'international affairs': 'আন্তর্জাতিক বিষয়াবলী',
  'general knowledge': 'সাধারণ জ্ঞান',
};

/// [subject] under the one name it should be saved as.
String canonicalSubject(String subject) {
  final trimmed = subject.trim();
  if (trimmed.isEmpty) return trimmed;
  return _subjectAliases[trimmed.toLowerCase()] ?? trimmed;
}

/// A key two topics share when they are the same topic written differently.
///
/// Strips what a person varies without meaning anything by it: the examples
/// in brackets, punctuation, and extra spacing. "মধ্যযুগ - মঙ্গলকাব্য
/// (অন্নদামঙ্গল)" and "মধ্যযুগ (মঙ্গলকাব্য ও ভারতচন্দ্র রায়গুণাকর)" both come
/// down to "মধ্যযুগ".
String topicMergeKey(String topic) {
  var text = topic.trim().toLowerCase();
  // Anything in brackets is an example, not the topic.
  text = text.replaceAll(RegExp(r'\([^)]*\)'), ' ');
  // A dash with spaces around it, or a comma, starts a list of examples. A
  // dash inside a word does not: নদ-নদী is one word, not a topic and a list.
  text = text.split(RegExp(r'\s[-–—]\s|[,;:]')).first;
  text = text.replaceAll(RegExp(r'[^ঀ-৿a-z0-9\s]'), ' ');
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return text;
}

/// A weak-topic row as the cleanup sees it.
class TopicRow {
  final int id;
  final String subject;
  final String topicName;

  const TopicRow({
    required this.id,
    required this.subject,
    required this.topicName,
  });
}

/// What tidying the weak-topics list would do.
class TopicCleanupPlan {
  /// Rows to delete, with the row each was a duplicate of.
  final Map<int, int> mergeInto;

  /// Rows to delete outright: an exam title that was saved as a topic.
  final List<int> drop;

  /// Rows whose subject should be rewritten, to its new name.
  final Map<int, String> renameSubject;

  const TopicCleanupPlan({
    required this.mergeInto,
    required this.drop,
    required this.renameSubject,
  });

  bool get isEmpty =>
      mergeInto.isEmpty && drop.isEmpty && renameSubject.isEmpty;

  int get changeCount => mergeInto.length + drop.length + renameSubject.length;
}

/// Works out what to merge, drop and rename, without touching anything.
///
/// Nothing is applied here on purpose: the user sees the plan first, because
/// a merge that was wrong is not something they could undo.
TopicCleanupPlan planTopicCleanup(List<TopicRow> rows) {
  final mergeInto = <int, int>{};
  final drop = <int>[];
  final renameSubject = <int, String>{};
  final keptByKey = <String, int>{};

  for (final row in rows) {
    final subject = canonicalSubject(row.subject);
    if (subject != row.subject.trim()) renameSubject[row.id] = subject;

    final topicKey = topicMergeKey(row.topicName);
    // An exam's title saved as its own topic says nothing about a weakness.
    if (topicKey.isEmpty || topicKey == topicMergeKey(row.subject)) {
      drop.add(row.id);
      renameSubject.remove(row.id);
      continue;
    }

    final key = '${subject.toLowerCase()}|$topicKey';
    final kept = keptByKey[key];
    if (kept == null) {
      keptByKey[key] = row.id;
    } else {
      mergeInto[row.id] = kept;
      renameSubject.remove(row.id);
    }
  }

  return TopicCleanupPlan(
    mergeInto: mergeInto,
    drop: drop,
    renameSubject: renameSubject,
  );
}

/// One subject's old name and the name it should take.
class SubjectAlias {
  final String from;
  final String to;

  const SubjectAlias(this.from, this.to);
}

/// Every alias, in the form the rewrite needs.
List<SubjectAlias> get subjectAliasesInUse => [
  for (final entry in _subjectAliases.entries)
    SubjectAlias(_displayCase(entry.key), entry.value),
];

/// The aliases are keyed in lower case; rows hold them as they were typed.
String _displayCase(String key) => key
    .split(' ')
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

/// What a cleanup would change across the whole database.
class StudyCleanupSummary {
  final TopicCleanupPlan plan;
  final int questionSubjectsToRename;
  final int cardSubjectsToRename;

  const StudyCleanupSummary({
    required this.plan,
    required this.questionSubjectsToRename,
    required this.cardSubjectsToRename,
  });

  bool get isEmpty =>
      plan.isEmpty &&
      questionSubjectsToRename == 0 &&
      cardSubjectsToRename == 0;
}
