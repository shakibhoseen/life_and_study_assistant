import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../database/app_database.dart';
import 'entity_ref.dart';

/// Looks up the rows a message referred to by tag.
///
/// The mentor cannot be asked to fix `Q-17` unless it is told what `Q-17`
/// says. This reads only the rows actually named, so a message with no tags
/// costs nothing and adds nothing to the prompt.
class EntityRefResolver {
  EntityRefResolver._();

  /// How much of one row to spell out. Enough to judge it, not the whole row.
  static const int maxTopicsChars = 160;
  static const int maxExplanationChars = 300;

  /// Renders the named rows as a short block for the prompt, or null when the
  /// message named none.
  static Future<String?> describe(AppDatabase db, String text) async {
    final refs = EntityRef.findAll(text);
    if (refs.isEmpty) return null;

    final lines = <String>[];
    final found = <String>[];
    final missing = <String>[];
    for (final ref in refs.take(5)) {
      final described = await _describeOne(db, ref);
      if (described == null) {
        missing.add(ref.tag);
        lines.add('${ref.tag}: এই ${ref.kind.label}টি পাওয়া যায়নি।');
      } else {
        found.add(ref.tag);
        lines.add(described);
      }
    }

    if (lines.isEmpty) return null;

    final block = lines.join('\n');
    // Whether the tag was understood is the whole question when the user
    // pastes one, and it is not visible from the token count alone.
    debugPrint(
      'Entity refs: found ${found.isEmpty ? "none" : found.join(",")}'
      '${missing.isEmpty ? "" : " | missing ${missing.join(",")}"}'
      ' | ${block.length} chars added',
    );

    // Without this legend the model guesses at the prefix: a pasted "Q-17"
    // came back answered as though it meant exam number 17.
    return '''
REFERENCED ITEMS — the user pasted short tags that name exact saved rows in this app.
What the prefixes mean:
  Q-<id> = one saved multiple-choice question from the user's mistake notebook. It is NOT an exam and NOT question number <id> of some paper.
  E-<id> = one scheduled exam in the user's routine.
  T-<id> = one topic on the user's weak-topics list.
The full content of each tag the user named follows. Talk about these exact rows. Never guess at what a tag means or renumber it, and if a row says it was not found, say so plainly.

$block''';
  }

  static Future<String?> _describeOne(AppDatabase db, EntityRef ref) async {
    switch (ref.kind) {
      case EntityKind.question:
        final row = await (db.select(
          db.drillQuestions,
        )..where((t) => t.id.equals(ref.id))).getSingleOrNull();
        if (row == null) return null;

        final options = _decodeOptions(row.optionsJson);
        final numbered = [
          for (var i = 0; i < options.length; i++) '$i. ${options[i]}',
        ].join(' | ');
        final stored =
            row.correctIndex >= 0 && row.correctIndex < options.length
            ? options[row.correctIndex]
            : '(অজানা)';

        return '${ref.tag} — saved MCQ from the mistake notebook '
            '(${row.subject} / ${row.topic})\n'
            '  প্রশ্ন: ${row.questionText}\n'
            '  অপশন: $numbered\n'
            '  সংরক্ষিত উত্তর: $stored\n'
            '  ব্যাখ্যা: ${_clip(row.explanation, maxExplanationChars)}';

      case EntityKind.exam:
        final row = await (db.select(
          db.examSchedules,
        )..where((t) => t.id.equals(ref.id))).getSingleOrNull();
        if (row == null) return null;

        final date = row.examDate.toIso8601String().substring(0, 10);
        var desc =
            '${ref.tag} — scheduled exam: ${row.title}\n'
            '  তারিখ: $date ${row.examTime} · ট্র্যাক: ${row.trackName}\n'
            '  বিষয়: ${row.subject} · সিলেবাস: '
            '${_clip(row.topicsCovered, maxTopicsChars)}';

        if (row.resourceSummary != null &&
            row.resourceSummary!.trim().startsWith('[')) {
          try {
            final decoded = jsonDecode(row.resourceSummary!);
            if (decoded is List && decoded.isNotEmpty) {
              desc += '\n  সংরক্ষিত প্রশ্নমালা (${decoded.length}টি MCQ):\n';
              for (var i = 0; i < decoded.length; i++) {
                final q = decoded[i];
                final qText = q['question']?.toString() ?? '';
                final opts = (q['options'] as List?)?.join(', ') ?? '';
                final cIdx = q['correct_index'];
                desc +=
                    '    $i. "$qText" | অপশন: [$opts] | চিহ্নিত উত্তর: $cIdx\n';
              }
              desc +=
                  '  (To propose question fixes/deletions for this exam based on critique, emit [[ACTION:FIX_EXAM_BEGIN|${row.id}|${row.title}]] [{"question_index": i, "proposed_correct_index": optIdx, "is_delete": false, "reason": "..."}] [[ACTION:FIX_EXAM_END]])\n';
            }
          } catch (_) {}
        }
        return desc;

      case EntityKind.topic:
        final row = await (db.select(
          db.weakTopics,
        )..where((t) => t.id.equals(ref.id))).getSingleOrNull();
        if (row == null) return null;

        return '${ref.tag} — weak topic: ${row.subject} / ${row.topicName}\n'
            '  অবস্থা: ${row.proficiencyLevel.name}'
            '${(row.notes ?? '').isEmpty ? '' : ' · নোট: ${_clip(row.notes!, maxTopicsChars)}'}';
    }
  }

  static List<String> _decodeOptions(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.map((e) => e.toString()).toList();
    } catch (_) {}
    return const [];
  }

  static String _clip(String value, int max) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '(নেই)';
    return trimmed.length <= max ? trimmed : '${trimmed.substring(0, max)}…';
  }
}
