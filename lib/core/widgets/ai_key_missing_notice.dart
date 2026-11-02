import 'package:flutter/material.dart';

import '../../features/settings/presentation/screens/settings_screen.dart';

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.amber.shade900.withValues(alpha: 0.25)
            : Colors.amber.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.amber.shade800 : Colors.amber.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.key_rounded, size: 18, color: Colors.amber.shade800),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark ? Colors.amber.shade100 : Colors.brown,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
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
              label: const Text('সেটিংসে যান', style: TextStyle(fontSize: 12)),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                backgroundColor: Colors.amber.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
