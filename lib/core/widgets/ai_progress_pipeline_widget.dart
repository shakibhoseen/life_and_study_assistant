import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/bengali_math_sanitizer.dart';

/// The category of AI operation being performed.
enum AiTaskType { text, image, audio, drill, explainer, general }

/// A distinct milestone or phase within an AI workflow.
class AiWorkflowStep {
  final String title;
  final String subtitle;
  final IconData icon;
  final double startSecond;

  const AiWorkflowStep({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.startSecond,
  });
}

/// A production-grade progress widget with dynamic multi-stage status,
/// real-time token tracking, elapsed timer, smooth progress bar, and slow-network safety hint.
class AiProgressPipelineWidget extends StatefulWidget {
  final AiTaskType type;
  final bool isCompact;
  final String? customInitialTitle;
  final String? customStatus;
  final String? customSubtitle;
  final int? liveTokens;

  /// Whether [liveTokens] is worked out on the phone rather than reported by
  /// the model. A non-streaming call says nothing about its cost until it
  /// returns, so the figure shown during the wait is an estimate and is
  /// labelled as one.
  final bool liveTokensAreEstimate;

  final VoidCallback? onCancel;

  const AiProgressPipelineWidget({
    super.key,
    this.type = AiTaskType.text,
    this.isCompact = false,
    this.customInitialTitle,
    this.customStatus,
    this.customSubtitle,
    this.liveTokens,
    this.liveTokensAreEstimate = false,
    this.onCancel,
  });

  @override
  State<AiProgressPipelineWidget> createState() =>
      _AiProgressPipelineWidgetState();
}

class _AiProgressPipelineWidgetState extends State<AiProgressPipelineWidget>
    with SingleTickerProviderStateMixin {
  late final Timer _timer;
  int _elapsedMillis = 0;
  late final AnimationController _pulseController;

  static final List<AiWorkflowStep> _textSteps = [
    const AiWorkflowStep(
      title: 'কনটেক্সট ও রুটিন যাচাই করা হচ্ছে...',
      subtitle: 'আপনার সিলেবাস ও উইক টপিক মিলিয়ে দেখা হচ্ছে',
      icon: Icons.menu_book_outlined,
      startSecond: 0.0,
    ),
    const AiWorkflowStep(
      title: 'উত্তরের রূপরেখা চিন্তা করছে...',
      subtitle: 'নির্ভুল সমাধান ও পয়েন্ট সাজানো হচ্ছে',
      icon: Icons.psychology_outlined,
      startSecond: 2.0,
    ),
    const AiWorkflowStep(
      title: 'রেসপন্স প্রস্তুত ও গুছিয়ে লিখছে...',
      subtitle: 'স্পষ্ট ও সহজ ভাষায় উত্তর তৈরি হচ্ছে',
      icon: Icons.edit_note_rounded,
      startSecond: 5.0,
    ),
    // Nothing here promises the answer is moments away. The step this
    // replaces said "কিছুক্ষণের মধ্যেই উত্তর চলে আসবে" for as long as the
    // wait lasted, however long that was.
    const AiWorkflowStep(
      title: 'ভেবে দেখছে...',
      subtitle: 'লম্বা উত্তরে এই ধাপে সময় লাগে',
      icon: Icons.psychology_outlined,
      startSecond: 12.0,
    ),
  ];

  /// Timed against a real page read, not guessed.
  ///
  /// A streamed run took three minutes and six seconds, and the first word of
  /// the reply did not appear for a hundred seconds: the model reads, then
  /// reasons for a long time, then writes quickly. These steps used to be
  /// timed 0, 2, 6 and 10 seconds, so the last of them sat on screen for
  /// three minutes saying the result was nearly ready. Claiming "almost done"
  /// for the whole wait is worse than saying nothing.
  static final List<AiWorkflowStep> _imageSteps = [
    const AiWorkflowStep(
      title: 'ছবি প্রস্তুত হচ্ছে...',
      subtitle: 'কাটা অংশটুকু পাঠানোর মাপে আনা হচ্ছে',
      icon: Icons.cloud_upload_outlined,
      startSecond: 0.0,
    ),
    const AiWorkflowStep(
      title: 'পাতাটা পড়া হচ্ছে...',
      subtitle: 'লেখা, অপশন ও সূত্রগুলো শনাক্ত করা হচ্ছে',
      icon: Icons.document_scanner_outlined,
      startSecond: 4.0,
    ),
    const AiWorkflowStep(
      title: 'ভেবে দেখছে — এই ধাপটাই সবচেয়ে লম্বা',
      subtitle: 'উত্তর লেখার আগে মিলিয়ে নিচ্ছে, মিনিট দুয়েক লাগতে পারে',
      icon: Icons.psychology_outlined,
      startSecond: 20.0,
    ),
    const AiWorkflowStep(
      title: 'উত্তর লেখা হচ্ছে...',
      subtitle: 'টোকেনের সংখ্যা বাড়তে থাকলে বুঝবেন লেখা শুরু হয়েছে',
      icon: Icons.edit_note_rounded,
      startSecond: 100.0,
    ),
  ];

  static final List<AiWorkflowStep> _audioSteps = [
    const AiWorkflowStep(
      title: 'অডিও প্রসেস ও নয়েজ ফিল্টার হচ্ছে...',
      subtitle: 'ভয়েস ক্লিপটি পরিষ্কার করা হচ্ছে',
      icon: Icons.graphic_eq_rounded,
      startSecond: 0.0,
    ),
    const AiWorkflowStep(
      title: 'ভয়েস থেকে প্রশ্ন ও ভুল শনাক্ত হচ্ছে...',
      subtitle: 'ভুল উত্তরের বিষয়বস্তু উদ্ধার করা হচ্ছে',
      icon: Icons.hearing_rounded,
      startSecond: 2.2,
    ),
    const AiWorkflowStep(
      title: 'নোটবুকে সংরক্ষণ উপযোগী করা হচ্ছে...',
      subtitle: 'টপিক ও সঠিক উত্তর প্রস্তুত হচ্ছে',
      icon: Icons.auto_stories_outlined,
      startSecond: 5.5,
    ),
    const AiWorkflowStep(
      title: 'সংরক্ষণ সম্পন্ন করা হচ্ছে...',
      subtitle: 'কিছুক্ষণের মধ্যেই যোগ হয়ে যাবে',
      icon: Icons.bookmark_added_outlined,
      startSecond: 9.0,
    ),
  ];

  static final List<AiWorkflowStep> _drillSteps = [
    const AiWorkflowStep(
      title: 'টপিক ও দুর্বলতার ইতিহাস পর্যালোচনা হচ্ছে...',
      subtitle: 'বিগত ভুলের প্যাটার্ন বের করা হচ্ছে',
      icon: Icons.analytics_outlined,
      startSecond: 0.0,
    ),
    const AiWorkflowStep(
      title: 'হাই-ইয়েল্ড MCQ প্রশ্ন তৈরি করছে...',
      subtitle: 'মানসম্মত প্রশ্ন ও ৪টি অপশন সাজানো হচ্ছে',
      icon: Icons.quiz_outlined,
      startSecond: 1.8,
    ),
    const AiWorkflowStep(
      title: 'সঠিক উত্তর ও ব্যাখ্যা যাচাই হচ্ছে...',
      subtitle: 'কুইজের নির্ভুলতা নিশ্চিত করা হচ্ছে',
      icon: Icons.check_circle_outline,
      startSecond: 5.0,
    ),
    const AiWorkflowStep(
      title: 'কুইজ ড্রিল সম্পূর্ণ প্রস্তুত...',
      subtitle: 'অনুশীলন শুরু করতে আর কয়েক সেকেন্ড',
      icon: Icons.flash_on,
      startSecond: 8.5,
    ),
  ];

  static final List<AiWorkflowStep> _explainerSteps = [
    const AiWorkflowStep(
      title: 'ভুল উত্তর ও প্রশ্ন পর্যালোচনা হচ্ছে...',
      subtitle: 'আপনার দেওয়া উত্তরের ত্রুটি চিহ্নিত করা হচ্ছে',
      icon: Icons.find_in_page_outlined,
      startSecond: 0.0,
    ),
    const AiWorkflowStep(
      title: 'মূল কনসেপ্ট ও শর্টকাট টেকনিক খোঁজা হচ্ছে...',
      subtitle: 'সহজ মনে রাখার নিয়ম সাজানো হচ্ছে',
      icon: Icons.lightbulb_outline,
      startSecond: 2.0,
    ),
    const AiWorkflowStep(
      title: 'সহজ বাংলায় পূর্ণাঙ্গ ব্যাখ্যা তৈরি হচ্ছে...',
      subtitle: 'ভুল সংশোধনের টিপস প্রস্তুত করা হচ্ছে',
      icon: Icons.auto_awesome,
      startSecond: 5.5,
    ),
  ];

  static final List<AiWorkflowStep> _generalSteps = [
    const AiWorkflowStep(
      title: 'প্রস্তুতি নিচ্ছে...',
      subtitle: 'প্রয়োজনীয় তথ্য সংগ্রহ করা হচ্ছে',
      icon: Icons.hourglass_top_rounded,
      startSecond: 0.0,
    ),
    const AiWorkflowStep(
      title: 'AI প্রসেসিং চলছে...',
      subtitle: 'বিশ্লেষণ ও গণনা করা হচ্ছে',
      icon: Icons.psychology_outlined,
      startSecond: 2.5,
    ),
    const AiWorkflowStep(
      title: 'ফলাফল প্রস্তুত হচ্ছে...',
      subtitle: 'তথ্য গুছিয়ে নেওয়া হচ্ছে',
      icon: Icons.auto_awesome,
      startSecond: 6.5,
    ),
  ];

  List<AiWorkflowStep> get _steps {
    switch (widget.type) {
      case AiTaskType.text:
        return _textSteps;
      case AiTaskType.image:
        return _imageSteps;
      case AiTaskType.audio:
        return _audioSteps;
      case AiTaskType.drill:
        return _drillSteps;
      case AiTaskType.explainer:
        return _explainerSteps;
      case AiTaskType.general:
        return _generalSteps;
    }
  }

  AiWorkflowStep get _currentStep {
    final seconds = _elapsedMillis / 1000.0;
    final steps = _steps;
    for (int i = steps.length - 1; i >= 0; i--) {
      if (seconds >= steps[i].startSecond) {
        return steps[i];
      }
    }
    return steps.first;
  }

  int get _currentStepIndex {
    final step = _currentStep;
    return _steps.indexOf(step);
  }

  /// Smooth asymptotic progress curve: rises fast initially, then slows down
  /// as it approaches 95%, ensuring the user always sees continuous progress.
  double get _progressValue {
    final seconds = _elapsedMillis / 1000.0;
    final raw = 1.0 - math.exp(-seconds / 5.0);
    return raw.clamp(0.08, 0.95);
  }

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (mounted) {
        setState(() {
          _elapsedMillis += 100;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  String _formatElapsed() {
    final totalSeconds = _elapsedMillis ~/ 1000;
    final bnSeconds = BengaliMathSanitizer.toBengaliDigits('$totalSeconds');
    return '$bnSeconds সে.';
  }

  String? _formatTokens() {
    if (widget.liveTokens == null || widget.liveTokens! <= 0) return null;
    final bnTokens = BengaliMathSanitizer.toBengaliDigits(
      '${widget.liveTokens}',
    );
    return widget.liveTokensAreEstimate
        ? '~$bnTokens টোকেন'
        : '$bnTokens টোকেন';
  }

  @override
  Widget build(BuildContext context) {
    return widget.isCompact ? _buildCompact(context) : _buildModal(context);
  }

  // ========================================================
  // COMPACT INLINE VIEW (FOR CHAT BUBBLE / INLINE STATUS)
  // ========================================================
  Widget _buildCompact(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final step = _currentStep;
    final title =
        widget.customStatus ??
        ((widget.customInitialTitle != null && _elapsedMillis < 1200)
            ? widget.customInitialTitle!
            : step.title);

    final progress = _progressValue;
    final percentBn = BengaliMathSanitizer.toBengaliDigits(
      (progress * 100).toInt().toString(),
    );
    final tokensStr = _formatTokens();

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark
                ? const Color(0xFF334155)
                : Colors.indigo.withValues(alpha: 0.15),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  // Animated pulsing icon
                  FadeTransition(
                    opacity: Tween<double>(
                      begin: 0.5,
                      end: 1.0,
                    ).animate(_pulseController),
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.indigo.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(step.icon, size: 14, color: Colors.indigo),
                    ),
                  ),
                  const SizedBox(width: 9),

                  // Animated step text
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        title,
                        key: ValueKey<String>(title),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Live Token Badge (if provided)
                  if (tokensStr != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.amber.withValues(alpha: 0.3),
                          width: 0.5,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.bolt, size: 11, color: Colors.amber),
                          const SizedBox(width: 2),
                          Text(
                            tokensStr,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],

                  // Live Timer Badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.grey.shade800
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isDark
                            ? Colors.grey.shade700
                            : Colors.grey.shade300,
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 11,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '$percentBn% • ${_formatElapsed()}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Continuous Micro Linear Progress Bar
            LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              backgroundColor: isDark
                  ? Colors.indigo.shade900.withValues(alpha: 0.3)
                  : Colors.indigo.shade50,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.indigo),
            ),
          ],
        ),
      ),
    );
  }

  // ========================================================
  // MODAL / FULL SCREEN CARD VIEW (FOR OCR / SCANNER / DRILLS)
  // ========================================================
  Widget _buildModal(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentStep = _currentStep;
    final currentIdx = _currentStepIndex;
    final title = widget.customStatus ?? currentStep.title;
    final subtitle = widget.customSubtitle ?? currentStep.subtitle;
    final progress = _progressValue;
    final percentBn = BengaliMathSanitizer.toBengaliDigits(
      (progress * 100).toInt().toString(),
    );
    final isSlow = _elapsedMillis >= 15000;
    final tokensStr = _formatTokens();

    return Center(
      child: Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Glowing pulsing top icon
            ScaleTransition(
              scale: Tween<double>(
                begin: 0.94,
                end: 1.06,
              ).animate(_pulseController),
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(currentStep.icon, color: Colors.white, size: 30),
              ),
            ),
            const SizedBox(height: 18),

            // Active step title
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                title,
                key: ValueKey<String>(title),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 5),

            // Subtitle
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
            const SizedBox(height: 18),

            // Progress bar + Percent + Timer row
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: isDark
                    ? Colors.grey.shade800
                    : Colors.grey.shade200,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFF6366F1),
                ),
              ),
            ),
            const SizedBox(height: 8),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'অগ্রগতি: $percentBn%',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6366F1),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (tokensStr != null) ...[
                      const Icon(Icons.bolt, size: 13, color: Colors.amber),
                      const SizedBox(width: 3),
                      Text(
                        tokensStr,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Icon(
                      Icons.timer_outlined,
                      size: 13,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'সময়: ${_formatElapsed()}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Checklist of steps
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.2)
                    : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                ),
              ),
              child: Column(
                children: _steps.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final s = entry.value;
                  final isDone = idx < currentIdx;
                  final isCurrent = idx == currentIdx;

                  Color textColor;
                  Widget leadIcon;

                  if (isDone) {
                    textColor = Colors.green;
                    leadIcon = const Icon(
                      Icons.check_circle,
                      size: 14,
                      color: Colors.green,
                    );
                  } else if (isCurrent) {
                    textColor = isDark ? Colors.white : const Color(0xFF4338CA);
                    leadIcon = const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF6366F1),
                      ),
                    );
                  } else {
                    textColor = isDark ? Colors.white38 : Colors.black38;
                    leadIcon = Icon(
                      Icons.radio_button_unchecked,
                      size: 14,
                      color: isDark ? Colors.white24 : Colors.black26,
                    );
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        leadIcon,
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            s.title,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isCurrent
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: textColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),

            // Slow network note
            if (isSlow) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.amber.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.wifi_tethering_error_rounded,
                      size: 15,
                      color: Colors.amber,
                    ),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'ইন্টারনেট কিছুটা ধীরগতির হতে পারে, দয়া করে অপেক্ষা করুন...',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: Colors.amber,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (widget.onCancel != null) ...[
              const SizedBox(height: 14),
              TextButton.icon(
                onPressed: widget.onCancel,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.close, size: 14),
                label: const Text(
                  'বাতিল করুন',
                  style: TextStyle(fontSize: 11.5),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
