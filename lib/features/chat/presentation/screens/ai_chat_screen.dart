import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../live_mcq/presentation/providers/exam_schedule_provider.dart';
import '../../../live_mcq/presentation/widgets/routine_preview_sheet.dart';
import '../../../quiz/presentation/widgets/quiz_drill_modal.dart';
import '../../../quiz/presentation/widgets/question_bank_scanner_modal.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../core/services/ai/gemini_ai_service.dart';
import '../../../../core/services/ai/models/chat_verification_result.dart';
import '../../../../core/services/ai/models/verification_result.dart';
import '../../../../core/utils/bengali_math_sanitizer.dart';
import '../../../../core/theme/fluent_tokens.dart';
import '../../domain/chat_verifiability.dart';
import '../../domain/models/chat_action.dart';
import '../../../../core/widgets/ai_progress_pipeline_widget.dart';
import '../providers/chat_provider.dart';

import '../../../../core/services/voice/voice_recording_service.dart';
import '../widgets/chat_thinking_indicator.dart';
import '../widgets/chat_user_bubble.dart';
import '../../../../core/widgets/animated_premium_background.dart';

class AiChatScreen extends ConsumerStatefulWidget {
  const AiChatScreen({super.key});

  @override
  ConsumerState<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends ConsumerState<AiChatScreen> {
  // Verification results live for the life of the screen only: nothing is
  // written back to the message being checked.
  final Map<int, ChatVerificationResult> _verifications = {};
  final Set<int> _verifying = {};
  final Set<int> _verifyFailed = {};
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  // Voice goes to text first, so the thread keeps a record of what was asked
  // and a misheard word can be fixed before it is answered.
  bool _isRecording = false;
  bool _isTranscribing = false;
  int _recordedSeconds = 0;
  Timer? _recordTimer;

  /// Gemini bills speech by the second, so a mic left running by accident is
  /// a real cost. It stops itself well before that becomes expensive.
  static const int _maxRecordSeconds = 60;

  final List<String> _quickPrompts = [
    '😴 আজকে অফিস শেষে ক্লান্ত, ৫ মিনিটের প্ল্যান দাও',
    '📖 বাংলা ব্যাকরণ: সমাস সহজে মনে রাখার ট্রিকস',
    '🧮 গণিত: শতকরা ও লাভ-ক্ষতির শর্টকাট টেকনিক',
    '📅 পরবর্তী LiveMCQ পরীক্ষার জন্য রিভিশন টিপস',
    '💡 বিজ্ঞান বা ইংরেজির একটি কঠিন টপিক বুঝিয়ে দাও',
  ];

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _recordTimer?.cancel();
    if (_isRecording) VoiceRecordingService.instance.cancelRecording();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleSend([String? presetText]) {
    final query = presetText ?? _textController.text;
    if (query.trim().isEmpty) return;

    ref.read(chatNotifierProvider.notifier).sendMessage(query);
    if (presetText == null) {
      _textController.clear();
    }
    _scrollToBottom();
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final isToday =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    final timeStr = '$hour:$minute $period';
    if (isToday) return 'Today $timeStr';
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${dt.day} ${months[dt.month - 1]}, $timeStr';
  }

  void _copyMessageText(String text) async {
    final sanitized = BengaliMathSanitizer.sanitize(text);
    await Clipboard.setData(ClipboardData(text: sanitized));
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.greenAccent, size: 18),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'মেসেজ সফলভাবে কপি হয়েছে!',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: FluentRadius.controlBorder),
      ),
    );
  }

  IconData _getSubjectIcon(String? subject) {
    if (subject == null) return Icons.forum_outlined;
    final s = subject.toLowerCase();
    if (s.contains('bangla') || s.contains('বাংলা')) return Icons.menu_book;
    if (s.contains('math') || s.contains('গণিত')) return Icons.calculate;
    if (s.contains('science') || s.contains('বিজ্ঞান')) return Icons.science;
    if (s.contains('english') || s.contains('ইংরেজি')) return Icons.translate;
    if (s.contains('gk') ||
        s.contains('general') ||
        s.contains('আন্তর্জাতিক')) {
      return Icons.public;
    }
    return Icons.psychology;
  }

  @override
  Widget build(BuildContext context) {
    final chatMessagesAsync = ref.watch(chatMessagesStreamProvider);
    final chatState = ref.watch(chatNotifierProvider);
    final sessions = ref.watch(chatSessionsStreamProvider).value ?? [];
    final currentSession = chatState.currentSession;

    ref.listen(chatMessagesStreamProvider, (prev, next) {
      _scrollToBottom();
    });

    final titleText = currentSession?.title ?? 'AI Study Companion';
    final subtitleText =
        currentSession?.subject != null && currentSession!.subject!.isNotEmpty
        ? '[${currentSession.subject}] • ${chatState.currentModelUsed ?? "Gemini"}'
        : (chatState.currentModelUsed != null
              ? '⚡ ${chatState.currentModelUsed}'
              : 'Tailored to your BCS goals');

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          borderRadius: FluentRadius.controlBorder,
          onTap: () => _showSessionsSheet(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: FluentSpacing.s,
              vertical: FluentSpacing.xs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              titleText,
                              style: FluentType.bodyStrong.copyWith(
                                fontSize: 15,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                          const SizedBox(width: FluentSpacing.xxs),
                          const Icon(Icons.arrow_drop_down, size: 20),
                        ],
                      ),
                      Text(
                        subtitleText,
                        style: FluentType.caption.copyWith(
                          color: Theme.of(context).colorScheme.onSurface
                              .withValues(alpha: 0.65),
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: sessions.length > 1,
              label: Text('${sessions.length}'),
              child: const Icon(Icons.forum_outlined),
            ),
            tooltip: 'Topic Threads (${sessions.length})',
            onPressed: () => _showSessionsSheet(context),
          ),
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: 'New Topic Thread',
            onPressed: () => _showNewSessionDialog(context),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (val) {
              if (val == 'rename') {
                if (currentSession != null) {
                  _showRenameSessionDialog(context, currentSession);
                }
              } else if (val == 'context') {
                _showContextDialog(context);
              } else if (val == 'clear') {
                _confirmClearChat(context);
              } else if (val == 'delete') {
                if (currentSession != null) {
                  _confirmDeleteSession(context, currentSession);
                }
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'rename',
                child: Row(
                  children: [
                    Icon(
                      Icons.edit_outlined,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: FluentSpacing.s),
                    Text('Rename Thread', style: FluentType.body),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'context',
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: FluentSpacing.s),
                    Text('View Current Context', style: FluentType.body),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    // Amber warns: this clears the thread.
                    const Icon(
                      Icons.cleaning_services_outlined,
                      size: 18,
                      color: Color(0xFFF59E0B),
                    ),
                    const SizedBox(width: FluentSpacing.s),
                    Text('Clear Thread Messages', style: FluentType.body),
                  ],
                ),
              ),
              if (sessions.length > 1)
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: FluentSpacing.s),
                      Text(
                        'Delete Thread',
                        style: FluentType.body.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          const Positioned.fill(
            child: AnimatedGradientBackground(child: SizedBox.expand()),
          ),
          const FloatingOrb(top: 50, right: -40, size: 240, opacity: 0.14),
          const FloatingOrb(bottom: 120, left: -40, size: 210, opacity: 0.12),
          Column(
            children: [
              // 1. Dedicated Topic Thread Indicator (if active)
              if (currentSession != null &&
                  currentSession.subject != null &&
                  currentSession.subject!.isNotEmpty &&
                  currentSession.subject != 'General')
                _buildTopicBanner(currentSession),

              // 2. Quick suggestion prompt chips
              _buildQuickPromptsBar(),

              const Divider(height: 1),

              // 3. Chat messages list
              Expanded(
                child: chatMessagesAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (err, stack) => Center(child: Text('Error: $err')),
                  data: (messages) {
                    if (messages.isEmpty) {
                      return _buildEmptyState(currentSession);
                    }

                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                        horizontal: FluentSpacing.l,
                        vertical: FluentSpacing.m,
                      ),
                      // Once the reply starts streaming it has its own bubble in
                      // `messages`, so the thinking indicator would be a duplicate.
                      itemCount:
                          messages.length +
                          (chatState.isSending && !chatState.isStreaming
                              ? 1
                              : 0),
                      itemBuilder: (context, index) {
                        if (index == messages.length &&
                            chatState.isSending &&
                            !chatState.isStreaming) {
                          return _buildThinkingIndicator(messages);
                        }

                        final message = messages[index];
                        final isUser = message.role == 'user';
                        if (isUser) return _buildUserBubble(message);

                        // A verifier needs the question this answers, and the turn
                        // before it when the question is a follow-up.
                        final question = index > 0 ? messages[index - 1] : null;
                        final earlierUser = index > 2
                            ? messages[index - 3]
                            : null;
                        final earlierAnswer = index > 1
                            ? messages[index - 2]
                            : null;
                        final isLast = index == messages.length - 1;

                        return _buildModelBubble(
                          message,
                          question: question?.role == 'user'
                              ? question!.textContent
                              : '',
                          priorContext: ChatVerifiability.buildPriorContext(
                            earlierUser: earlierUser?.role == 'user'
                                ? earlierUser!.textContent
                                : null,
                            earlierAnswer: earlierAnswer?.role == 'model'
                                ? earlierAnswer!.textContent
                                : null,
                          ),
                          isStreaming: isLast && chatState.isStreaming,
                        );
                      },
                    );
                  },
                ),
              ),

              // 4. Bottom text input bar
              _buildInputBar(chatState.isSending),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTopicBanner(ChatSession session) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: FluentSpacing.l,
        vertical: FluentSpacing.s,
      ),
      decoration: BoxDecoration(
        color: FluentLayer.subtle(scheme.primary, theme.brightness),
        border: Border(bottom: FluentStroke.side(theme.brightness)),
      ),
      child: Row(
        children: [
          Icon(
            _getSubjectIcon(session.subject),
            size: 16,
            color: scheme.primary,
          ),
          const SizedBox(width: FluentSpacing.s),
          Expanded(
            child: Text(
              'Dedicated Thread: ${session.subject} • ${session.topic ?? session.title}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FluentType.caption.copyWith(
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: FluentSpacing.s),
          InkWell(
            onTap: () => _showSessionsSheet(context),
            borderRadius: FluentRadius.controlBorder,
            child: Text(
              'Switch Thread',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FluentType.caption.copyWith(
                fontWeight: FontWeight.w600,
                color: scheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickPromptsBar() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(vertical: FluentSpacing.xs),
      color: scheme.surface,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: FluentSpacing.m),
        itemCount: _quickPrompts.length,
        separatorBuilder: (ctx, i) => const SizedBox(width: FluentSpacing.s),
        itemBuilder: (context, index) {
          final prompt = _quickPrompts[index];
          return ActionChip(
            label: Text(
              prompt,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FluentType.caption.copyWith(color: scheme.onSurface),
            ),
            backgroundColor: theme.cardTheme.color ?? theme.cardColor,
            side: BorderSide(
              color: FluentStroke.card(theme.brightness),
              width: FluentStroke.width,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: FluentRadius.controlBorder,
            ),
            onPressed: () => _handleSend(prompt),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(ChatSession? session) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isTopicSession =
        session != null &&
        session.subject != null &&
        session.subject!.isNotEmpty &&
        session.subject != 'General';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(FluentSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(FluentSpacing.xl),
              decoration: BoxDecoration(
                // A Fluent icon plate is a rounded square, not a circle.
                color: FluentLayer.subtle(scheme.primary, theme.brightness),
                borderRadius: FluentRadius.controlBorder,
              ),
              child: Icon(
                _getSubjectIcon(session?.subject),
                size: 48,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: FluentSpacing.l),
            Text(
              isTopicSession
                  ? session.title
                  : 'আপনার ব্যক্তিগত AI মেন্টর ও পার্টনার',
              style: FluentType.subtitle.copyWith(
                fontSize: 18,
                color: scheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: FluentSpacing.s),
            Text(
              isTopicSession
                  ? 'এই থ্রেডের সমস্ত আলোচনা ও মেমরি সম্পূর্ণ এই টপিকের জন্যই সংরক্ষিত থাকবে। যেকোনো নিয়ম, শর্টকাট বা বিগত বছরের প্রশ্ন জানতে পারেন।'
                  : 'ফুল-টাইম অফিস ও ক্লান্তির সাথে সামঞ্জস্য রেখে BCS ও চাকরির পরীক্ষার সেরা প্রস্তুতি নিন।\nযেকোনো কঠিন টপিক বুঝে নিতে পারেন বা রিভিশন ড্রিল তৈরি করতে বলুন।',
              style: FluentType.body.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.65),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: FluentSpacing.xl),
            Wrap(
              spacing: FluentSpacing.s,
              runSpacing: FluentSpacing.s,
              alignment: WrapAlignment.center,
              children: isTopicSession
                  ? [
                      _buildStarterCard(
                        '📖 মূল নিয়ম ও সহজ ট্রিকস বলো',
                        session.subject ?? 'Core Rules',
                      ),
                      _buildStarterCard(
                        '⚠️ কমন ফাঁদ ও ভুল হওয়ার জায়গা',
                        'Exam Traps',
                      ),
                      _buildStarterCard(
                        '📝 বিগত বছরের ৫টি গুরুত্বপূর্ণ MCQ',
                        'Past Questions',
                      ),
                    ]
                  : [
                      _buildStarterCard(
                        '📖 সমাস বা ব্যাকরণ বুঝাও',
                        'বাংলা ব্যাকরণ',
                      ),
                      _buildStarterCard(
                        '😴 ৫ মিনিটের কুইক ড্রিল',
                        'ক্লান্তি ম্যানেজমেন্ট',
                      ),
                      _buildStarterCard(
                        '📅 LiveMCQ রিভিশন ট্রিকস',
                        'পরীক্ষা প্রস্তুতি',
                      ),
                      _buildStarterCard(
                        '📸 প্রশ্ন ব্যাংক স্ক্যান করে কুইজ',
                        'বইয়ের পাতা থেকে এক্সাম',
                        onTap: () => QuestionBankScannerModal.show(context),
                      ),
                    ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStarterCard(
    String title,
    String subtitle, {
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return InkWell(
      onTap: onTap ?? () => _handleSend(title),
      borderRadius: FluentRadius.cardBorder,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: FluentSpacing.m,
          vertical: FluentSpacing.s,
        ),
        decoration: BoxDecoration(
          color: theme.cardTheme.color ?? theme.cardColor,
          borderRadius: FluentRadius.cardBorder,
          border: Border.all(
            color: FluentStroke.card(theme.brightness),
            width: FluentStroke.width,
          ),
          boxShadow: FluentElevation.card(theme.brightness),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: FluentType.bodyStrong.copyWith(color: scheme.onSurface),
            ),
            Text(
              subtitle,
              style: FluentType.caption.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserBubble(ChatMessage message) {
    return ChatUserBubble(
      message: message,
      onCopy: () => _copyMessageText(message.textContent),
      formattedTime: _formatDateTime(message.timestamp),
    );
  }

  Future<void> _verifyMessage(
    ChatMessage message,
    String question,
    String priorContext,
  ) async {
    if (_verifying.contains(message.id)) return;
    setState(() {
      _verifying.add(message.id);
      _verifyFailed.remove(message.id);
    });

    final result = await GeminiAiService.instance.verifyChatAnswer(
      userQuestion: question,
      aiAnswer: message.textContent,
      priorContext: priorContext,
    );

    if (!mounted) return;
    setState(() {
      _verifying.remove(message.id);
      if (result == null) {
        _verifyFailed.add(message.id);
      } else {
        _verifications[message.id] = result;
      }
    });
  }

  Widget _buildModelBubble(
    ChatMessage message, {
    String question = '',
    String priorContext = '',
    bool isStreaming = false,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    final isDark = brightness == Brightness.dark;
    final actions = ChatAction.decodeList(message.suggestedAction);

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: FluentSpacing.m, right: 36),
        padding: const EdgeInsets.all(FluentSpacing.m),
        decoration: BoxDecoration(
          color: theme.cardTheme.color ?? theme.cardColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(FluentRadius.control),
            topRight: Radius.circular(FluentRadius.card),
            bottomLeft: Radius.circular(FluentRadius.card),
            bottomRight: Radius.circular(FluentRadius.card),
          ),
          border: Border.all(
            color: FluentStroke.card(brightness),
            width: FluentStroke.width,
          ),
          boxShadow: FluentElevation.card(brightness),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: FluentRadius.controlBorder,
                  child: Image.asset(
                    'assets/branding/playstore_icon_512.png',
                    width: 20,
                    height: 20,
                    errorBuilder: (context, error, stackTrace) =>
                        Icon(Icons.school, size: 18, color: scheme.primary),
                  ),
                ),
                const SizedBox(width: FluentSpacing.s),
                Expanded(
                  child: Text(
                    'AI Companion',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FluentType.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: FluentSpacing.s),
                Flexible(
                  child: Text(
                    _formatDateTime(message.timestamp),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FluentType.caption.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                const SizedBox(width: FluentSpacing.s),
                InkWell(
                  onTap: () => _copyMessageText(message.textContent),
                  borderRadius: FluentRadius.controlBorder,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FluentSpacing.s,
                      vertical: FluentSpacing.xxs,
                    ),
                    decoration: BoxDecoration(
                      color: FluentLayer.subtle(scheme.primary, brightness),
                      borderRadius: FluentRadius.controlBorder,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.copy_rounded,
                          size: 12,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: FluentSpacing.xs),
                        Flexible(
                          child: Text(
                            'Copy',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FluentType.caption.copyWith(
                              fontWeight: FontWeight.w600,
                              color: scheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: FluentSpacing.s),
            MarkdownBody(
              data: BengaliMathSanitizer.sanitize(message.textContent),
              selectable: true,
              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                  .copyWith(
                    p: FluentType.body.copyWith(color: scheme.onSurface),
                    h1: FluentType.subtitle.copyWith(
                      fontSize: 18,
                      color: scheme.onSurface,
                    ),
                    h2: FluentType.subtitle.copyWith(
                      fontSize: 16,
                      color: scheme.onSurface,
                    ),
                    h3: FluentType.bodyStrong.copyWith(
                      fontSize: 15,
                      color: scheme.onSurface,
                    ),
                    listBullet: FluentType.body.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.65),
                    ),
                    strong: FluentType.bodyStrong.copyWith(
                      color: scheme.onSurface,
                    ),
                    code: FluentType.caption.copyWith(
                      backgroundColor: scheme.onSurface.withValues(alpha: 0.06),
                      fontFamily: 'monospace',
                      color: scheme.onSurface,
                    ),
                  ),
            ),
            const SizedBox(height: FluentSpacing.m),
            Row(
              mainAxisAlignment: isStreaming
                  ? MainAxisAlignment.spaceBetween
                  : MainAxisAlignment.end,
              children: [
                if (isStreaming)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FluentSpacing.s,
                      vertical: FluentSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: FluentLayer.subtle(scheme.primary, brightness),
                      borderRadius: FluentRadius.controlBorder,
                      border: Border.all(
                        color: FluentStroke.card(brightness),
                        width: FluentStroke.width,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 8,
                          height: 8,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: scheme.primary,
                          ),
                        ),
                        const SizedBox(width: FluentSpacing.xs),
                        Flexible(
                          child: Text(
                            'AI সরাসরি লিখছে (Streaming)...',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FluentType.caption.copyWith(
                              fontWeight: FontWeight.w600,
                              color: scheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                InkWell(
                  onTap: () => _copyMessageText(message.textContent),
                  borderRadius: FluentRadius.controlBorder,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FluentSpacing.m,
                      vertical: FluentSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.onSurface.withValues(alpha: 0.05),
                      borderRadius: FluentRadius.controlBorder,
                      border: Border.all(
                        color: FluentStroke.card(brightness),
                        width: FluentStroke.width,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.copy_rounded,
                          size: 13,
                          color: scheme.onSurface.withValues(alpha: 0.65),
                        ),
                        const SizedBox(width: FluentSpacing.xs),
                        Flexible(
                          child: Text(
                            'Copy Response',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FluentType.caption.copyWith(
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (ChatVerifiability.canVerify(
              message.textContent,
              isStreaming: isStreaming,
            )) ...[
              const SizedBox(height: FluentSpacing.m),
              _buildVerifyBlock(message, question, priorContext, isDark),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: FluentSpacing.m),
              Divider(height: 1, color: FluentStroke.divider(brightness)),
              const SizedBox(height: FluentSpacing.s),
              Text(
                '⚡ Suggested Actions:',
                style: FluentType.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
              const SizedBox(height: FluentSpacing.s),
              ...actions.map((act) => _buildActionCard(act, message, isDark)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVerifyBlock(
    ChatMessage message,
    String question,
    String priorContext,
    bool isDark,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    final result = _verifications[message.id];
    final busy = _verifying.contains(message.id);

    if (result == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextButton.icon(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: FluentSpacing.s,
                  vertical: FluentSpacing.xxs,
                ),
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(
                  borderRadius: FluentRadius.controlBorder,
                ),
              ),
              onPressed: busy
                  ? null
                  : () => _verifyMessage(message, question, priorContext),
              icon: busy
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.fact_check_outlined, size: 14),
              label: Text(
                busy ? 'যাচাই চলছে…' : 'উত্তর যাচাই করুন',
                style: FluentType.caption.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (_verifyFailed.contains(message.id))
              Padding(
                padding: const EdgeInsets.only(
                  left: FluentSpacing.s,
                  top: FluentSpacing.xxs,
                ),
                child: Text(
                  'যাচাই করা গেল না।',
                  style: FluentType.caption.copyWith(color: scheme.error),
                ),
              ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(FluentSpacing.m),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: FluentRadius.cardBorder,
        border: Border.all(
          color: FluentStroke.card(brightness),
          width: FluentStroke.width,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.fact_check_outlined,
                size: 14,
                color: scheme.onSurface.withValues(alpha: 0.65),
              ),
              const SizedBox(width: FluentSpacing.s),
              Expanded(
                child: Text(
                  // Bengali digits, like the rest of the app.
                  '${BengaliMathSanitizer.toBengaliDigits('${result.claimsFound}')}টি দাবির মধ্যে '
                  '${BengaliMathSanitizer.toBengaliDigits('${result.claimsEvaluated}')}টি দেখা হয়েছে · '
                  '${BengaliMathSanitizer.toBengaliDigits('${result.verifiableCount}')}টি স্বাধীনভাবে যাচাই করা গেছে',
                  style: FluentType.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          if (result.isPartial) ...[
            const SizedBox(height: FluentSpacing.xs),
            Text(
              result.extractionNote.isNotEmpty
                  ? result.extractionNote
                  : 'সব দাবি যাচাই করা যায়নি।',
              // Amber warns: not every claim could be checked.
              style: FluentType.caption.copyWith(
                color: const Color(0xFFF59E0B),
              ),
            ),
          ],
          const SizedBox(height: FluentSpacing.s),
          ...result.claims.map((c) => _buildClaimRow(c, isDark)),
          const SizedBox(height: FluentSpacing.xs),
          Text(
            'External sources not checked',
            style: FluentType.caption.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClaimRow(VerifiedClaim claim, bool isDark) {
    final scheme = Theme.of(context).colorScheme;

    // Grey, not amber, for "not verified": amber reads as a warning about the
    // claim, when the only thing being reported is that the app could not
    // check it. Only red warns, and only green claims a check was made.
    final (color, icon, status) = switch (claim.verdict) {
      VerificationVerdict.supported => (
        const Color(0xFF10B981),
        Icons.check_circle_outline,
        'যাচাই হয়েছে',
      ),
      VerificationVerdict.likelyIncorrect => (
        scheme.error,
        Icons.error_outline,
        'সম্ভবত ভুল',
      ),
      VerificationVerdict.inconclusive => (
        scheme.onSurface.withValues(alpha: 0.5),
        Icons.remove_circle_outline,
        'যাচাই করা যায়নি',
      ),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: FluentSpacing.m),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: FluentSpacing.xxs),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: FluentSpacing.s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '“${claim.text}”',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: FluentType.caption.copyWith(
                    fontStyle: FontStyle.italic,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: FluentSpacing.xs),
                Wrap(
                  spacing: FluentSpacing.s,
                  runSpacing: FluentSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      status,
                      style: FluentType.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                    Text(
                      '${claim.kind.label} · ${claim.evidence.label}',
                      style: FluentType.caption.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: FluentSpacing.xxs),
                Text(
                  claim.reasoning,
                  style: FluentType.caption.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
                if (claim.downgraded) ...[
                  const SizedBox(height: FluentSpacing.xxs),
                  Text(
                    'মডেল এটিকে সঠিক বলেছিল, কিন্তু যাচাই করার মতো উৎস নেই।',
                    style: FluentType.caption.copyWith(
                      fontStyle: FontStyle.italic,
                      color: scheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(ChatAction action, ChatMessage message, bool isDark) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    final isDone = action.isExecuted;
    final isRoutinePlan = action.type == ChatActionType.routinePlan;
    final isStudyTask = action.type == ChatActionType.studyTask;

    // Green marks a completed action; otherwise the accent marks what to act on.
    const successColor = Color(0xFF10B981);
    final accent = isDone ? successColor : scheme.primary;

    return Container(
      margin: const EdgeInsets.only(top: FluentSpacing.s),
      padding: const EdgeInsets.symmetric(
        horizontal: FluentSpacing.m,
        vertical: FluentSpacing.s,
      ),
      decoration: BoxDecoration(
        color: FluentLayer.subtle(accent, brightness),
        borderRadius: FluentRadius.controlBorder,
        border: Border.all(
          color: accent.withValues(alpha: 0.4),
          width: FluentStroke.width,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isDone
                ? Icons.check_circle
                : (action.type == ChatActionType.fixExam
                      ? Icons.auto_fix_high_rounded
                      : (action.type == ChatActionType.addFlashcard
                            ? Icons.bolt_rounded
                            : (isStudyTask
                                  ? Icons.quiz_outlined
                                  : (isRoutinePlan
                                        ? Icons.calendar_month
                                        : Icons.auto_awesome)))),
            size: 16,
            color: accent,
          ),
          const SizedBox(width: FluentSpacing.s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: FluentType.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                Text(
                  action.type == ChatActionType.fixExam
                      ? 'E-${action.examId} পরীক্ষার প্রশ্নসমূহ অটো-ফিক্স'
                      : (action.type == ChatActionType.addFlashcard
                            ? '${action.subject} · ${action.keyRule ?? "ফ্ল্যাশ কার্ড সূত্র"}'
                            : (action.type == ChatActionType.addExam
                                  ? '${action.examDate ?? ""} · ${action.examTime ?? "10:00 PM"} · 🏷️ ${action.effectiveTrackName}'
                                  : (isRoutinePlan
                                        ? '${action.effectiveTrackName} · ${action.routineItems.length} days'
                                        : (isStudyTask
                                              ? '${action.subject} · ${action.minutes != null ? "${action.minutes} মিনিট " : ""}কুইজ ড্রিল'
                                              : 'Subject: ${action.subject}')))),
                  maxLines: action.type == ChatActionType.addFlashcard ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: FluentType.caption.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isDone
                  ? FluentLayer.subtle(successColor, brightness)
                  : scheme.primary,
              foregroundColor: isDone ? successColor : scheme.onPrimary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(
                horizontal: FluentSpacing.m,
                vertical: FluentSpacing.xs,
              ),
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                borderRadius: FluentRadius.controlBorder,
              ),
            ),
            onPressed: isDone
                ? null
                : () async {
                    if (isRoutinePlan) {
                      final items = action.routineItems;
                      if (items.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('রুটিনের তথ্য পাওয়া যায়নি'),
                          ),
                        );
                        return;
                      }

                      final approved = await RoutinePreviewSheet.show(
                        context,
                        items,
                        sourceLabel:
                            'AI Mentor (${action.trackName ?? "Study Routine"})',
                      );

                      if (approved == null || approved.isEmpty || !mounted) {
                        return;
                      }

                      final success = await ref
                          .read(chatNotifierProvider.notifier)
                          .executeAction(
                            action: action,
                            message: message,
                            approvedItems: approved,
                          );

                      if (!success || !mounted) return;

                      ref.invalidate(upcomingExamsStreamProvider);
                      ref.invalidate(allExamsStreamProvider);
                      ref.invalidate(distinctTracksStreamProvider);
                      ref.invalidate(filteredExamsStreamProvider);

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '${approved.length}টি স্টাডি সেশন সফলভাবে সেভ করা হয়েছে',
                          ),
                          backgroundColor: Colors.green.shade700,
                        ),
                      );
                      return;
                    }

                    if (isStudyTask) {
                      await ref
                          .read(chatNotifierProvider.notifier)
                          .executeAction(action: action, message: message);
                      if (!mounted) return;
                      QuizDrillModal.show(
                        context,
                        topic: action.topic ?? action.title,
                        subject: action.subject,
                      );
                      return;
                    }

                    final success = await ref
                        .read(chatNotifierProvider.notifier)
                        .executeAction(action: action, message: message);
                    if (!success || !mounted) return;
                    if (action.type == ChatActionType.addExam ||
                        action.type == ChatActionType.fixExam) {
                      // The routine screens are watching their own streams.
                      ref.invalidate(upcomingExamsStreamProvider);
                      ref.invalidate(allExamsStreamProvider);
                      ref.invalidate(distinctTracksStreamProvider);
                      ref.invalidate(filteredExamsStreamProvider);
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          action.type == ChatActionType.fixExam
                              ? '"${action.title}" সফলভাবে সংশোধন করা হয়েছে'
                              : (action.type == ChatActionType.addFlashcard
                                    ? '"${action.title}" ফ্ল্যাশ কার্ডে যুক্ত হয়েছে'
                                    : (action.type == ChatActionType.addExam
                                          ? '"${action.title}" রুটিনে যোগ হয়েছে'
                                          : '"${action.title}" দুর্বল টপিকে যোগ হয়েছে')),
                        ),
                        backgroundColor: Colors.green.shade700,
                      ),
                    );
                  },
            child: Text(
              isDone
                  ? (action.type == ChatActionType.fixExam
                        ? 'সংশোধিত ✓'
                        : (action.type == ChatActionType.addFlashcard
                              ? 'যুক্ত ✓'
                              : (isRoutinePlan
                                    ? 'সংরক্ষিত'
                                    : (isStudyTask
                                          ? 'কুইজ সম্পন্ন'
                                          : 'যোগ হয়েছে'))))
                  : (action.type == ChatActionType.fixExam
                        ? 'সংশোধন প্রয়োগ'
                        : (action.type == ChatActionType.addFlashcard
                              ? 'কার্ডে যোগ'
                              : (isRoutinePlan
                                    ? 'রুটিন প্রিভিউ'
                                    : (action.type == ChatActionType.addExam
                                          ? 'রুটিনে যোগ'
                                          : (isStudyTask
                                                ? 'কুইজ শুরু'
                                                : 'টপিকে যোগ'))))),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FluentType.caption.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThinkingIndicator([List<ChatMessage>? messages]) {
    AiTaskType type = AiTaskType.text;
    if (messages != null && messages.isNotEmpty) {
      final lastText = messages.last.textContent.toLowerCase();
      if (lastText.contains('image') ||
          lastText.contains('ছবি') ||
          lastText.contains('scan')) {
        type = AiTaskType.image;
      } else if (lastText.contains('voice') ||
          lastText.contains('ভয়েস') ||
          lastText.contains('audio')) {
        type = AiTaskType.audio;
      }
    }
    return ChatThinkingIndicator(type: type);
  }

  Future<void> _toggleVoice() async {
    if (_isTranscribing) return;

    if (_isRecording) {
      _recordTimer?.cancel();
      setState(() {
        _isRecording = false;
        _isTranscribing = true;
      });

      final file = await VoiceRecordingService.instance.stopRecording();
      final text = file == null
          ? null
          : await GeminiAiService.instance.transcribeVoice(file);

      if (!mounted) return;
      setState(() => _isTranscribing = false);

      if (text == null || text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('কিছু শোনা গেল না, আবার বলুন')),
        );
        return;
      }

      // Appended rather than replacing, so a half-typed question survives.
      final existing = _textController.text.trim();
      _textController.text = existing.isEmpty ? text : '$existing $text';
      _textController.selection = TextSelection.fromPosition(
        TextPosition(offset: _textController.text.length),
      );
      _focusNode.requestFocus();
      return;
    }

    try {
      await VoiceRecordingService.instance.startRecording(
        config: VoiceRecordingService.speechConfig,
      );
      if (!mounted) return;
      setState(() {
        _isRecording = true;
        _recordedSeconds = 0;
      });
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted || !_isRecording) {
          t.cancel();
          return;
        }
        setState(() => _recordedSeconds++);
        if (_recordedSeconds >= _maxRecordSeconds) _toggleVoice();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('মাইক্রোফোনের অনুমতি দিন')));
    }
  }

  Widget _buildInputBar(bool isSending) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;

    return Container(
      padding: EdgeInsets.fromLTRB(
        FluentSpacing.m,
        FluentSpacing.s,
        FluentSpacing.m,
        MediaQuery.of(context).viewInsets.bottom > 0
            ? FluentSpacing.s
            : FluentSpacing.l,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: FluentStroke.side(brightness)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              focusNode: _focusNode,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _handleSend(),
              style: FluentType.body.copyWith(color: scheme.onSurface),
              decoration: InputDecoration(
                hintText: _isRecording
                    ? '🎙 শুনছি… ${_recordedSeconds}s / ${_maxRecordSeconds}s'
                    : (_isTranscribing
                          ? 'লেখা হচ্ছে…'
                          : 'Ask Gemini anything (BCS, routine, doubts)...'),
                hintStyle: FluentType.body.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.5),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: FluentSpacing.m,
                  vertical: FluentSpacing.s,
                ),
                filled: true,
                fillColor: scheme.onSurface.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  // A Fluent input is a 4px control, not a pill.
                  borderRadius: FluentRadius.controlBorder,
                  borderSide: BorderSide(
                    color: FluentStroke.card(brightness),
                    width: FluentStroke.width,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: FluentRadius.controlBorder,
                  borderSide: BorderSide(
                    color: FluentStroke.card(brightness),
                    width: FluentStroke.width,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: FluentRadius.controlBorder,
                  borderSide: BorderSide(
                    color: scheme.primary,
                    width: FluentStroke.width,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: FluentSpacing.xs),
          IconButton(
            tooltip: 'প্রশ্ন ব্যাংক স্ক্যান করে এক্সাম',
            onPressed: isSending
                ? null
                : () => QuestionBankScannerModal.show(context),
            icon: Icon(
              Icons.document_scanner_outlined,
              size: 22,
              color: scheme.primary,
            ),
          ),
          IconButton(
            tooltip: _isRecording ? 'থামুন' : 'বলে জিজ্ঞাসা করুন',
            onPressed: isSending ? null : _toggleVoice,
            icon: _isTranscribing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _isRecording ? Icons.stop_circle : Icons.mic_none,
                    size: 24,
                    // Red while recording: a live, stoppable state.
                    color: _isRecording
                        ? scheme.error
                        : scheme.onSurface.withValues(alpha: 0.65),
                  ),
          ),
          const SizedBox(width: FluentSpacing.xxs),
          // A Fluent send control is a 4px rounded square, not a circle.
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isSending
                  ? scheme.onSurface.withValues(alpha: 0.12)
                  : scheme.primary,
              borderRadius: FluentRadius.controlBorder,
            ),
            child: IconButton(
              icon: isSending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  // Sits on the saturated accent fill.
                  : Icon(Icons.send, size: 18, color: scheme.onPrimary),
              onPressed: isSending ? null : () => _handleSend(),
            ),
          ),
        ],
      ),
    );
  }

  // ========================================================
  // TOPIC THREADS / SESSIONS SHEET & DIALOGS
  // ========================================================
  void _showSessionsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(FluentRadius.large),
        ),
      ),
      builder: (ctx) {
        return Consumer(
          builder: (context, ref, _) {
            final theme = Theme.of(context);
            final scheme = theme.colorScheme;
            final brightness = theme.brightness;
            final sessionsAsync = ref.watch(chatSessionsStreamProvider);
            final activeSessionId = ref
                .watch(chatNotifierProvider)
                .currentSessionId;

            return SafeArea(
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.75,
                ),
                padding: const EdgeInsets.fromLTRB(
                  FluentSpacing.l,
                  FluentSpacing.l,
                  FluentSpacing.l,
                  FluentSpacing.s,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        Icon(Icons.forum, color: scheme.primary, size: 20),
                        const SizedBox(width: FluentSpacing.s),
                        Expanded(
                          child: Text(
                            'Study Threads & Sessions',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FluentType.subtitle.copyWith(
                              fontSize: 17,
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: FluentSpacing.s),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            backgroundColor: scheme.primary,
                            foregroundColor: scheme.onPrimary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: FluentSpacing.m,
                              vertical: FluentSpacing.xs,
                            ),
                            visualDensity: VisualDensity.compact,
                            shape: RoundedRectangleBorder(
                              borderRadius: FluentRadius.controlBorder,
                            ),
                          ),
                          icon: const Icon(Icons.add, size: 15),
                          label: Text('New Thread', style: FluentType.caption),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _showNewSessionDialog(context);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: FluentSpacing.s),
                    Text(
                      'Each thread maintains separate, focused memory for that subject or topic.',
                      style: FluentType.caption.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                    Divider(
                      height: FluentSpacing.xl,
                      color: FluentStroke.divider(brightness),
                    ),

                    // List of Sessions
                    Expanded(
                      child: sessionsAsync.when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (err, _) => Center(child: Text('Error: $err')),
                        data: (sessions) {
                          if (sessions.isEmpty) {
                            return Center(
                              child: Text(
                                'No threads found. Create one!',
                                style: FluentType.body.copyWith(
                                  color: scheme.onSurface.withValues(
                                    alpha: 0.65,
                                  ),
                                ),
                              ),
                            );
                          }

                          return ListView.builder(
                            itemCount: sessions.length,
                            itemBuilder: (context, index) {
                              final session = sessions[index];
                              final isActive = session.id == activeSessionId;

                              return Card(
                                elevation: 0,
                                margin: const EdgeInsets.only(
                                  bottom: FluentSpacing.s,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: FluentRadius.cardBorder,
                                  side: BorderSide(
                                    color: isActive
                                        ? scheme.primary.withValues(alpha: 0.55)
                                        : FluentStroke.card(brightness),
                                    width: FluentStroke.width,
                                  ),
                                ),
                                color: isActive
                                    ? FluentLayer.subtle(
                                        scheme.primary,
                                        brightness,
                                      )
                                    : (theme.cardTheme.color ??
                                          theme.cardColor),
                                child: ListTile(
                                  // A Fluent icon plate: rounded square, not a circle.
                                  leading: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: isActive
                                          ? scheme.primary
                                          : FluentLayer.subtle(
                                              scheme.primary,
                                              brightness,
                                            ),
                                      borderRadius: FluentRadius.controlBorder,
                                    ),
                                    child: Icon(
                                      _getSubjectIcon(session.subject),
                                      color: isActive
                                          ? scheme.onPrimary
                                          : scheme.primary,
                                      size: 20,
                                    ),
                                  ),
                                  title: Text(
                                    session.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        (isActive
                                                ? FluentType.bodyStrong
                                                : FluentType.body)
                                            .copyWith(color: scheme.onSurface),
                                  ),
                                  subtitle: Text(
                                    '${session.subject ?? "General"} • ${_formatDateTime(session.updatedAt)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: FluentType.caption.copyWith(
                                      color: scheme.onSurface.withValues(
                                        alpha: 0.65,
                                      ),
                                    ),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isActive)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: FluentSpacing.s,
                                            vertical: FluentSpacing.xxs,
                                          ),
                                          decoration: BoxDecoration(
                                            color: scheme.primary,
                                            borderRadius:
                                                FluentRadius.controlBorder,
                                          ),
                                          child: Text(
                                            'Active',
                                            style: FluentType.caption.copyWith(
                                              // On a saturated accent fill.
                                              color: scheme.onPrimary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: PopupMenuButton<String>(
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          icon: const Icon(
                                            Icons.more_vert,
                                            size: 18,
                                          ),
                                          onSelected: (val) {
                                            if (val == 'rename') {
                                              Navigator.pop(ctx);
                                              _showRenameSessionDialog(
                                                context,
                                                session,
                                              );
                                            } else if (val == 'delete') {
                                              Navigator.pop(ctx);
                                              _confirmDeleteSession(
                                                context,
                                                session,
                                              );
                                            }
                                          },
                                          itemBuilder: (c) => [
                                            PopupMenuItem(
                                              value: 'rename',
                                              child: Text(
                                                'Rename',
                                                style: FluentType.body,
                                              ),
                                            ),
                                            if (sessions.length > 1)
                                              PopupMenuItem(
                                                value: 'delete',
                                                child: Text(
                                                  'Delete',
                                                  style: FluentType.body
                                                      .copyWith(
                                                        color: scheme.error,
                                                      ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  onTap: () {
                                    ref
                                        .read(chatNotifierProvider.notifier)
                                        .switchSession(session.id);
                                    Navigator.pop(ctx);
                                  },
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showNewSessionDialog(BuildContext context) {
    final titleController = TextEditingController();
    final subjectController = TextEditingController();
    final topicController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: FluentRadius.cardBorder),
        title: Text(
          'Create New Study Thread',
          style: FluentType.subtitle.copyWith(fontSize: 18),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: subjectController,
                decoration: const InputDecoration(
                  labelText: 'Subject (e.g. বাংলা ব্যাকরণ, Math)',
                  isDense: true,
                ),
              ),
              const SizedBox(height: FluentSpacing.m),
              TextField(
                controller: topicController,
                decoration: const InputDecoration(
                  labelText: 'Topic Name (e.g. কারক ও বিভক্তি, লাভ-ক্ষতি)',
                  isDense: true,
                ),
              ),
              const SizedBox(height: FluentSpacing.m),
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText:
                      'Thread Title (Optional - auto-generated if blank)',
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final sub = subjectController.text.trim();
              final top = topicController.text.trim();
              var title = titleController.text.trim();

              if (title.isEmpty) {
                if (sub.isNotEmpty && top.isNotEmpty) {
                  title = '$sub: $top';
                } else if (sub.isNotEmpty) {
                  title = sub;
                } else if (top.isNotEmpty) {
                  title = top;
                } else {
                  title = 'New Study Thread';
                }
              }

              await ref
                  .read(chatNotifierProvider.notifier)
                  .createNewSession(
                    title: title,
                    subject: sub.isNotEmpty ? sub : null,
                    topic: top.isNotEmpty ? top : null,
                  );

              if (context.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Switched to "$title"')));
              }
            },
            child: const Text('Create & Open'),
          ),
        ],
      ),
    );
  }

  void _showRenameSessionDialog(BuildContext context, ChatSession session) {
    final controller = TextEditingController(text: session.title);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: FluentRadius.cardBorder),
        title: Text(
          'Rename Thread',
          style: FluentType.subtitle.copyWith(fontSize: 18),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Thread Title',
            isDense: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newTitle = controller.text.trim();
              if (newTitle.isNotEmpty) {
                await ref
                    .read(chatNotifierProvider.notifier)
                    .renameSession(session.id, newTitle);
                if (context.mounted) {
                  Navigator.pop(ctx);
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteSession(
    BuildContext context,
    ChatSession session,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: FluentRadius.cardBorder),
        title: Text(
          'Delete "${session.title}"?',
          style: FluentType.subtitle.copyWith(fontSize: 18),
        ),
        content: Text(
          'This will permanently delete this thread and all its messages from your local device.',
          style: FluentType.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Delete',
              style: FluentType.bodyStrong.copyWith(
                color: Theme.of(ctx).colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(chatNotifierProvider.notifier).deleteSession(session.id);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Deleted "${session.title}"')));
      }
    }
  }

  Future<void> _showContextDialog(BuildContext context) async {
    final db = ref.read(appDatabaseProvider);
    final todayLog = await db.watchTodayLog(DateTime.now()).first;
    // Must match what GeminiChatService actually receives, otherwise this
    // dialog misreports the live context.
    final weakTopics = await db.getContextWeakTopics();
    final exams = await db.getContextUpcomingExams();
    final activeSession = ref.read(chatNotifierProvider).currentSession;

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: FluentRadius.cardBorder),
        title: Row(
          children: [
            Icon(Icons.psychology, color: Theme.of(ctx).colorScheme.primary),
            const SizedBox(width: FluentSpacing.s),
            Flexible(
              child: Text(
                'Active Gemini Context',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FluentType.subtitle.copyWith(fontSize: 17),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Available context. Gemini is sent only the parts a given '
                'question actually needs — plus anything urgent (an exam '
                'within 3 days, or high fatigue).',
                style: FluentType.caption.copyWith(
                  color: Theme.of(ctx).colorScheme.onSurface
                      .withValues(alpha: 0.65),
                ),
              ),
              Divider(
                height: FluentSpacing.xl,
                color: FluentStroke.divider(Theme.of(ctx).brightness),
              ),
              if (activeSession != null) ...[
                Text(
                  '💬 Active Thread: ${activeSession.title}',
                  style: FluentType.bodyStrong.copyWith(
                    color: Theme.of(ctx).colorScheme.primary,
                  ),
                ),
                if (activeSession.subject != null)
                  Text(
                    'Subject: ${activeSession.subject} | Topic: ${activeSession.topic ?? "General"}',
                    style: FluentType.caption.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurface,
                    ),
                  ),
                const SizedBox(height: FluentSpacing.m),
              ],
              Text(
                '⚡ Energy: ${todayLog?.energyLevel.name ?? "Moderate"} | Fatigue: ${todayLog?.officeFatigueScore ?? 5}/10',
                style: FluentType.bodyStrong.copyWith(
                  color: Theme.of(ctx).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: FluentSpacing.m),
              Text(
                '🎯 Weak Topics (${weakTopics.length}):',
                style: FluentType.bodyStrong.copyWith(
                  color: Theme.of(ctx).colorScheme.onSurface,
                ),
              ),
              if (weakTopics.isEmpty)
                Text(
                  'None yet',
                  style: FluentType.caption.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurface
                        .withValues(alpha: 0.5),
                  ),
                )
              else
                ...weakTopics.map(
                  (t) => Text(
                    '• [${t.subject}] ${t.topicName} (${t.proficiencyLevel.name})',
                    style: FluentType.caption.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurface,
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              Text(
                '📅 Upcoming Exams (${exams.length}):',
                style: FluentType.bodyStrong.copyWith(
                  color: Theme.of(ctx).colorScheme.onSurface,
                ),
              ),
              if (exams.isEmpty)
                Text(
                  'No exams scheduled',
                  style: FluentType.caption.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurface
                        .withValues(alpha: 0.5),
                  ),
                )
              else
                ...exams.map(
                  (e) => Text(
                    '• ${e.title} (${e.examDate.toIso8601String().substring(0, 10)})',
                    style: FluentType.caption.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurface,
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClearChat(BuildContext context) async {
    final currentSession = ref.read(chatNotifierProvider).currentSession;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: FluentRadius.cardBorder),
        title: Text(
          'Clear Thread Messages?',
          style: FluentType.subtitle.copyWith(fontSize: 18),
        ),
        content: Text(
          'This will delete messages in "${currentSession?.title ?? "this thread"}" from your local device.',
          style: FluentType.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Clear',
              style: FluentType.bodyStrong.copyWith(
                color: Theme.of(ctx).colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(chatNotifierProvider.notifier).clearCurrentSession();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thread messages cleared.')),
        );
      }
    }
  }
}
