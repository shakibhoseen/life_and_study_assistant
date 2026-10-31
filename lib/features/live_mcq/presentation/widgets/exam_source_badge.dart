import 'package:flutter/material.dart';

import '../../domain/models/exam_source_info.dart';

class ExamSourceBadge extends StatelessWidget {
  final ExamSourceInfo source;
  final bool? isDark;

  const ExamSourceBadge({super.key, required this.source, this.isDark});

  @override
  Widget build(BuildContext context) {
    final effectiveIsDark =
        isDark ?? (Theme.of(context).brightness == Brightness.dark);
    Color bg;
    Color border;
    Color text;

    switch (source.kind) {
      case ExamSourceKind.aiMentor:
        bg = effectiveIsDark
            ? const Color(0xFF2E1065)
            : const Color(0xFFF3E8FF);
        border = effectiveIsDark
            ? const Color(0xFF7E22CE)
            : const Color(0xFFD8B4FE);
        text = effectiveIsDark
            ? const Color(0xFFD8B4FE)
            : const Color(0xFF6B21A8);
        break;
      case ExamSourceKind.aiStudyPlan:
        bg = effectiveIsDark
            ? const Color(0xFF042F2E)
            : const Color(0xFFCCFBF1);
        border = effectiveIsDark
            ? const Color(0xFF0F766E)
            : const Color(0xFF5EEAD4);
        text = effectiveIsDark
            ? const Color(0xFF5EEAD4)
            : const Color(0xFF0F766E);
        break;
      case ExamSourceKind.manual:
        bg = effectiveIsDark
            ? const Color(0xFF451A03)
            : const Color(0xFFFEF3C7);
        border = effectiveIsDark
            ? const Color(0xFFB45309)
            : const Color(0xFFFDE68A);
        text = effectiveIsDark
            ? const Color(0xFFFDE68A)
            : const Color(0xFF92400E);
        break;
      case ExamSourceKind.pdfImport:
        bg = effectiveIsDark
            ? const Color(0xFF172554)
            : const Color(0xFFEFF6FF);
        border = effectiveIsDark
            ? const Color(0xFF1D4ED8)
            : const Color(0xFFBFDBFE);
        text = effectiveIsDark
            ? const Color(0xFF93C5FD)
            : const Color(0xFF1E40AF);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: border, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(source.icon, size: 10.5, color: text),
          const SizedBox(width: 3.5),
          Flexible(
            child: Text(
              source.label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: text,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}
