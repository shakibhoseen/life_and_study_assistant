/// Something the user already knows they are weak at.
class RevisionCandidate {
  final String subject;
  final String label;

  /// Where it came from: a weak topic, or a question got wrong.
  final String source;

  const RevisionCandidate({
    required this.subject,
    required this.label,
    required this.source,
  });
}

/// Picks out what is worth revising for a particular exam.
///
/// The app knows tomorrow's exam and what it covers, and separately knows
/// which topics the user is weak at and which questions they got wrong. It
/// never put the two together, so the night before an exam on বাংলা সাহিত্য
/// nothing pointed at the literature cards sitting in the deck.
///
/// Matching is on words rather than whole strings, because an exam's topic
/// list is a sentence ("বাংলা সাহিত্যের আধুনিক যুগের লেখকগণ, গুরুত্বপূর্ণ
/// লেখকগণ: রবীন্দ্রনাথ...") while a weak topic is a phrase.
List<RevisionCandidate> revisionForExam({
  required String examTitle,
  required String examTopics,
  required List<RevisionCandidate> candidates,
  int limit = 5,
}) {
  final examWords = _meaningfulWords('$examTitle $examTopics');
  if (examWords.isEmpty) return const [];

  final scored = <(int, RevisionCandidate)>[];
  for (final candidate in candidates) {
    final words = _meaningfulWords('${candidate.subject} ${candidate.label}');
    if (words.isEmpty) continue;
    final shared = words.where((w) => _matchesAny(w, examWords)).length;
    // One shared word is a coincidence — a stray number, or a word that
    // joins every sentence.
    if (shared < 2) continue;
    scored.add((shared, candidate));
  }

  scored.sort((a, b) => b.$1.compareTo(a.$1));
  return [for (final entry in scored.take(limit)) entry.$2];
}

/// Whether [word] is the same word as one of [others], allowing for the
/// endings Bengali adds.
///
/// Checked against the real data and it matters: an exam listed
/// "বাংলা সাহিত্যের আধুনিক যুগের লেখকগণ" while the weak topic said
/// "বাংলা সাহিত্য". Matching whole words exactly, সাহিত্য and সাহিত্যের are
/// two different words and the exam found nothing to suggest.
///
/// One word has to start the other and the shared part has to run at least
/// four characters, so কার does not match কারক.
bool _matchesAny(String word, Set<String> others) {
  for (final other in others) {
    if (word == other) return true;
    final shorter = word.length < other.length ? word : other;
    final longer = word.length < other.length ? other : word;
    if (shorter.length >= 4 && longer.startsWith(shorter)) return true;
  }
  return false;
}

/// Words worth matching on, with the ones that join every sentence removed.
Set<String> _meaningfulWords(String text) {
  const ignore = {
    'এবং',
    'থেকে',
    'সংক্রান্ত',
    'বিষয়ক',
    'প্রশ্ন',
    'পরীক্ষা',
    'টেস্ট',
    'অনুশীলন',
    'প্র্যাকটিস',
    'মডেল',
    'and',
    'the',
    'test',
    'exam',
    'practice',
    'model',
    'part',
  };
  return text
      .toLowerCase()
      .replaceAll(RegExp(r'[^ঀ-৿a-z0-9\s]'), ' ')
      .split(RegExp(r'\s+'))
      // Short words and bare numbers match everything and mean nothing.
      .where((w) => w.length > 2 && !ignore.contains(w))
      .where((w) => int.tryParse(w) == null)
      .toSet();
}
