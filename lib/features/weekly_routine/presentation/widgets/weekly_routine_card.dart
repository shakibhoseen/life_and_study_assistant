import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/weekly_routine.dart';
import '../providers/weekly_routine_provider.dart';

/// The week at a glance on the dashboard, with the detail and the command box
/// one tap away.
class WeeklyRoutineCard extends ConsumerWidget {
  const WeeklyRoutineCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routineAsync = ref.watch(weeklyRoutineProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return routineAsync.maybeWhen(
      data: (routine) => Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => WeeklyRoutineSheet.show(context),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.calendar_view_week,
                      size: 20,
                      color: isDark
                          ? Colors.teal.shade200
                          : Colors.teal.shade700,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        routine.title,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: routine.days
                      .map((d) => _DayChip(day: d, isDark: isDark))
                      .toList(),
                ),
                if (routine.principle.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    routine.principle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _DayChip extends StatelessWidget {
  final RoutineDay day;
  final bool isDark;

  const _DayChip({required this.day, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final accent = day.isOffDay
        ? (isDark ? Colors.teal.shade200 : Colors.teal.shade700)
        : (isDark ? Colors.white70 : Colors.black87);

    return Container(
      constraints: const BoxConstraints(maxWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: day.isOffDay
            ? (isDark
                  ? Colors.teal.withValues(alpha: 0.16)
                  : Colors.teal.withValues(alpha: 0.08))
            : (isDark ? Colors.white10 : Colors.grey.shade100),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            day.day,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              color: accent,
            ),
          ),
          Text(
            day.focus,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.35,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

/// Full routine plus the box where the user tells the model what to change.
class WeeklyRoutineSheet extends ConsumerStatefulWidget {
  const WeeklyRoutineSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const WeeklyRoutineSheet(),
    );
  }

  @override
  ConsumerState<WeeklyRoutineSheet> createState() => _WeeklyRoutineSheetState();
}

class _WeeklyRoutineSheetState extends ConsumerState<WeeklyRoutineSheet> {
  final _controller = TextEditingController();

  static const _suggestions = [
    'রাতের সময়টা ৩০ মিনিট করো',
    'শুক্রবার শুধু রিভিশন রাখো',
    'সামনের পরীক্ষাগুলো ধরে সাজাও',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send(String command) async {
    final ok = await ref
        .read(weeklyRoutineNotifierProvider.notifier)
        .applyCommand(command);
    if (ok) _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final routineAsync = ref.watch(weeklyRoutineProvider);
    final state = ref.watch(weeklyRoutineNotifierProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        final routine = routineAsync.value ?? WeeklyRoutine.defaultRoutine;

        return Column(
          children: [
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          routine.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: state.isRevising
                            ? null
                            : () => ref
                                  .read(weeklyRoutineNotifierProvider.notifier)
                                  .resetToDefault(),
                        icon: const Icon(Icons.restart_alt, size: 16),
                        label: const Text(
                          'ডিফল্ট',
                          style: TextStyle(fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                  if (routine.principle.isNotEmpty)
                    Text(
                      routine.principle,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.55,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  const SizedBox(height: 18),
                  _SectionLabel('কর্মদিবসের জানালা', isDark: isDark),
                  const SizedBox(height: 8),
                  ...routine.windows.map((w) => _WindowTile(w, isDark: isDark)),
                  const SizedBox(height: 18),
                  _SectionLabel('সপ্তাহ', isDark: isDark),
                  const SizedBox(height: 8),
                  ...routine.days.map((d) => _DayRow(d, isDark: isDark)),
                  if (routine.lastCommand != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      'সর্বশেষ নির্দেশ: "${routine.lastCommand}"',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontStyle: FontStyle.italic,
                        color: isDark ? Colors.white38 : Colors.black45,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            _CommandBar(
              controller: _controller,
              isRevising: state.isRevising,
              errorMessage: state.errorMessage,
              suggestions: _suggestions,
              onSend: _send,
              isDark: isDark,
            ),
          ],
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final bool isDark;
  const _SectionLabel(this.text, {required this.isDark});

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.bold,
      letterSpacing: 0.6,
      color: isDark ? Colors.teal.shade200 : Colors.teal.shade700,
    ),
  );
}

class _WindowTile extends StatelessWidget {
  final RoutineWindow window;
  final bool isDark;
  const _WindowTile(this.window, {required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? Colors.white10 : Colors.amber.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    window.label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? Colors.amber.shade200
                          : Colors.amber.shade900,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  window.time,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              window.activity,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            if (window.note.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                window.note,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  final RoutineDay day;
  final bool isDark;
  const _DayRow(this.day, {required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 62,
            child: Text(
              day.day,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: day.isOffDay
                    ? (isDark ? Colors.teal.shade200 : Colors.teal.shade700)
                    : (isDark ? Colors.white60 : Colors.black54),
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  day.focus,
                  style: const TextStyle(fontSize: 13.5, height: 1.4),
                ),
                if (day.note.isNotEmpty)
                  Text(
                    day.note,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white38 : Colors.black45,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommandBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isRevising;
  final String? errorMessage;
  final List<String> suggestions;
  final Future<void> Function(String) onSend;
  final bool isDark;

  const _CommandBar({
    required this.controller,
    required this.isRevising,
    required this.errorMessage,
    required this.suggestions,
    required this.onSend,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        14,
        10,
        14,
        10 + MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white12 : Colors.grey.shade200,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                errorMessage!,
                style: const TextStyle(fontSize: 12, color: Colors.redAccent),
              ),
            ),
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: suggestions.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, i) => ActionChip(
                label: Text(
                  suggestions[i],
                  style: const TextStyle(fontSize: 11.5),
                ),
                onPressed: isRevising ? null : () => onSend(suggestions[i]),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: !isRevising,
                  textInputAction: TextInputAction.send,
                  onSubmitted: isRevising ? null : onSend,
                  decoration: const InputDecoration(
                    hintText: 'ছকটা কীভাবে বদলাতে চান?',
                    hintStyle: TextStyle(fontSize: 13.5),
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: isRevising ? null : () => onSend(controller.text),
                icon: isRevising
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
