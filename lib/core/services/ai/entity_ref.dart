/// A short, copyable name for one row in the app.
///
/// The user needs a way to say *which* question or exam they mean when they
/// bring it to the mentor: copy the tag off a card, paste it into chat, and
/// both sides are talking about the same row. The database id is already
/// stable and unique per table, so the tag is just that id with the table
/// written in front of it.
enum EntityKind {
  question('Q', 'প্রশ্ন'),
  exam('E', 'পরীক্ষা'),
  topic('T', 'টপিক');

  const EntityKind(this.prefix, this.label);

  /// The letter that opens the tag, e.g. `Q` in `Q-17`.
  final String prefix;

  /// What to call it in Bengali.
  final String label;

  static EntityKind? fromPrefix(String p) {
    final upper = p.toUpperCase();
    for (final k in EntityKind.values) {
      if (k.prefix == upper) return k;
    }
    return null;
  }
}

/// One `KIND-id` reference, such as `Q-17`.
class EntityRef {
  final EntityKind kind;
  final int id;

  const EntityRef(this.kind, this.id);

  String get tag => '${kind.prefix}-$id';

  @override
  String toString() => tag;

  @override
  bool operator ==(Object other) =>
      other is EntityRef && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  /// Reads a single tag, or null if this is not one.
  static EntityRef? tryParse(String raw) {
    final match = RegExp(r'^\s*([A-Za-z])\s*-\s*(\d{1,9})\s*$').firstMatch(raw);
    if (match == null) return null;
    final kind = EntityKind.fromPrefix(match.group(1)!);
    if (kind == null) return null;
    return EntityRef(kind, int.parse(match.group(2)!));
  }

  /// Finds every tag mentioned in a sentence.
  ///
  /// Word boundaries matter here: without them `Q-1` would also match inside
  /// a date or an ordinary hyphenated word.
  static List<EntityRef> findAll(String text) {
    final refs = <EntityRef>[];
    final matches = RegExp(r'(?<![A-Za-z0-9])([QETqet])-(\d{1,9})(?![0-9])')
        .allMatches(text);
    for (final m in matches) {
      final kind = EntityKind.fromPrefix(m.group(1)!);
      if (kind == null) continue;
      final ref = EntityRef(kind, int.parse(m.group(2)!));
      if (!refs.contains(ref)) refs.add(ref);
    }
    return refs;
  }
}
