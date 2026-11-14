import 'package:flutter/material.dart';

import '../theme/fluent_tokens.dart';

import '../../features/settings/presentation/screens/settings_screen.dart';

/// Amber is the warning accent, with a light-mode and a dark-mode value that
/// reads on either surface.
Color _warnColour(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFFFCD34D)
    : const Color(0xFFB45309);

/// Tells the user a Gemini key is missing, and takes them where to put it.
///
/// The services say "সেটিংসে কী দিন" and used to leave it there, which is a
/// dead end for anyone who has not already found that screen. Before today
/// these features answered a missing key with invented content, so the gap
/// never showed; removing that made the first run honest and also made it
/// stop, which is only half a fix.
class AiKeyMissingNotice extends StatelessWidget {
  final String message;

  /// Shown after the key is set, so the user lands back on their work.
  final VoidCallback? onRetry;

  const AiKeyMissingNotice({super.key, required this.message, this.onRetry});

  /// Whether [message] is about a missing key rather than some other failure.
  static bool looksLikeKeyProblem(String message) =>
      message.contains('API কী') ||
      message.contains('API Key') ||
      message.contains('কী বসানো নেই');

  @override
  Widget build(BuildContext context) {
    final warn = _warnColour(context);
    return Container(
      padding: const EdgeInsets.all(FluentSpacing.m),
      decoration: BoxDecoration(
        color: FluentLayer.subtle(warn, Theme.of(context).brightness),
        borderRadius: FluentRadius.cardBorder,
        border: Border.all(
          color: warn.withValues(alpha: 0.35),
          width: FluentStroke.width,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.key_rounded, size: 18, color: warn),
              const SizedBox(width: FluentSpacing.s),
              Expanded(
                child: Text(
                  message,
                  style: FluentType.caption.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: FluentSpacing.s),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
                onRetry?.call();
              },
              icon: const Icon(Icons.settings, size: 16),
              label: Text('সেটিংসে যান', style: FluentType.caption),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: FluentRadius.controlBorder,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
