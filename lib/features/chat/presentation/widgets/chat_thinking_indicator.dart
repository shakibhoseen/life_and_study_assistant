import 'package:flutter/material.dart';

import '../../../../core/widgets/ai_progress_pipeline_widget.dart';

class ChatThinkingIndicator extends StatelessWidget {
  final AiTaskType type;
  final int? liveTokens;
  final String? customStatus;

  const ChatThinkingIndicator({
    super.key,
    this.type = AiTaskType.text,
    this.liveTokens,
    this.customStatus,
  });

  @override
  Widget build(BuildContext context) {
    return AiProgressPipelineWidget(
      type: type,
      isCompact: true,
      liveTokens: liveTokens,
      customStatus: customStatus,
    );
  }
}
