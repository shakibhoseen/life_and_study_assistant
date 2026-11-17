import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/data/mistake_kind.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../core/theme/fluent_tokens.dart';
import '../providers/mistake_pattern_provider.dart';

/// One tap to say why a question was got wrong.
///
/// It has to be one tap. The app already knows which topic the mistake was
/// in; what it is asking for here is the one thing only the person can
/// supply, at the moment they are already looking at the question. A dialog,
/// a dropdown or a free-text box would all be more expressive and would all
/// go unused by the second week.
///
/// Tapping the kind that is already set clears it, so a mis-tap costs one tap
/// to undo rather than leaving a wrong answer about a wrong answer.
class MistakeKindChips extends ConsumerWidget {
  final DrillQuestion dq;

  const MistakeKindChips({super.key, required this.dq});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final current = mistakeKindFromName(dq.mistakeKind);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ভুলটা কেন হলো?',
          style: FluentType.caption.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: FluentSpacing.xs),
        Wrap(
          spacing: FluentSpacing.xs,
          runSpacing: FluentSpacing.xs,
          children: MistakeKind.values.map((kind) {
            final selected = kind == current;
            return ChoiceChip(
              label: Text(kind.label, style: FluentType.caption),
              selected: selected,
              visualDensity: VisualDensity.compact,
              onSelected: (_) async {
                HapticFeedback.selectionClick();
                await ref
                    .read(appDatabaseProvider)
                    .setMistakeKind(dq.id, selected ? null : kind);
                ref.read(mistakePatternRevisionProvider.notifier).bump();
              },
            );
          }).toList(),
        ),
        if (current != null) ...[
          const SizedBox(height: FluentSpacing.xs),
          // The remedy, said where the tag was just given. A pattern screen
          // nobody opens is worth less than one sentence at the moment the
          // user is still thinking about this question.
          Text(
            current.remedy,
            style: FluentType.caption.copyWith(color: scheme.primary),
          ),
        ],
      ],
    );
  }
}
