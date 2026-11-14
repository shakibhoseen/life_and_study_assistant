import 'package:flutter/material.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/theme/fluent_tokens.dart';

class ChatUserBubble extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback onCopy;
  final String formattedTime;

  const ChatUserBubble({
    super.key,
    required this.message,
    required this.onCopy,
    required this.formattedTime,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Align(
      alignment: Alignment.centerRight,
      child: InkWell(
        onLongPress: onCopy,
        borderRadius: FluentRadius.cardBorder,
        child: Container(
          margin: const EdgeInsets.only(bottom: FluentSpacing.m, left: 48),
          padding: const EdgeInsets.symmetric(
            horizontal: FluentSpacing.m,
            vertical: FluentSpacing.s,
          ),
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(FluentRadius.card),
              topRight: Radius.circular(FluentRadius.control),
              bottomLeft: Radius.circular(FluentRadius.card),
              bottomRight: Radius.circular(FluentRadius.card),
            ),
            boxShadow: FluentElevation.card(theme.brightness),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                message.textContent,
                // On a saturated accent fill, so onPrimary is correct here.
                style: FluentType.body.copyWith(color: scheme.onPrimary),
              ),
              const SizedBox(height: FluentSpacing.xs),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      formattedTime,
                      style: FluentType.caption.copyWith(
                        color: scheme.onPrimary.withValues(alpha: 0.75),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: FluentSpacing.s),
                  InkWell(
                    onTap: onCopy,
                    borderRadius: FluentRadius.controlBorder,
                    child: Padding(
                      padding: const EdgeInsets.all(FluentSpacing.xxs),
                      child: Icon(
                        Icons.copy_rounded,
                        size: 14,
                        color: scheme.onPrimary.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
