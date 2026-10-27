import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../core/services/ai/gemini_ai_service.dart';
import '../../../../core/services/ai/models/chat_verification_result.dart';
import '../../../../core/services/ai/models/verification_result.dart';
import '../../../../core/utils/bengali_math_sanitizer.dart';
import '../../domain/chat_verifiability.dart';
import '../../domain/models/chat_action.dart';
import '../providers/chat_provider.dart';

import '../../../../core/services/voice/voice_recording_service.dart';

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
            Text('মেসেজ সফলভাবে কপি হয়েছে!'),
          ],
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
          borderRadius: BorderRadius.circular(8),
          onTap: () => _showSessionsSheet(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Icon(Icons.arrow_drop_down, size: 20),
                        ],
                      ),
                      Text(
                        subtitleText,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black54,
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
              const PopupMenuItem(
                value: 'rename',
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 18, color: Colors.indigo),
                    SizedBox(width: 8),
                    Text('Rename Thread'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'context',
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: Colors.indigo),
                    SizedBox(width: 8),
                    Text('View Current Context'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(
                      Icons.cleaning_services_outlined,
                      size: 18,
                      color: Colors.orange,
                    ),
                    SizedBox(width: 8),
                    Text('Clear Thread Messages'),
                  ],
                ),
              ),
              if (sessions.length > 1)
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, size: 18, color: Colors.red),
                      SizedBox(width: 8),
                      Text(
                        'Delete Thread',
                        style: TextStyle(color: Colors.red),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Column(
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
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(child: Text('Error: $err')),
              data: (messages) {
                if (messages.isEmpty) {
                  return _buildEmptyState(currentSession);
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  // Once the reply starts streaming it has its own bubble in
                  // `messages`, so the thinking indicator would be a duplicate.
                  itemCount:
                      messages.length +
                      (chatState.isSending && !chatState.isStreaming ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == messages.length &&
                        chatState.isSending &&
                        !chatState.isStreaming) {
                      return _buildThinkingIndicator();
                    }

                    final message = messages[index];
                    final isUser = message.role == 'user';
                    if (isUser) return _buildUserBubble(message);

                    // A verifier needs the question this answers, and the turn
                    // before it when the question is a follow-up.
                    final question = index > 0 ? messages[index - 1] : null;
                    final earlierUser = index > 2 ? messages[index - 3] : null;
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
    );
  }

  Widget _buildTopicBanner(ChatSession session) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.indigo.withValues(alpha: 0.25)
            : Colors.indigo.shade50,
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? Colors.indigo.withValues(alpha: 0.4)
                : Colors.indigo.shade100,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _getSubjectIcon(session.subject),
            size: 16,
            color: isDark ? Colors.indigo.shade200 : Colors.indigo.shade800,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Dedicated Thread: ${session.subject} • ${session.topic ?? session.title}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.indigo.shade900,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: () => _showSessionsSheet(context),
            child: Text(
              'Switch Thread',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isDark
                    ? const Color(0xFF93C5FD)
                    : Colors.indigo.shade700,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickPromptsBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(vertical: 6),
      color: isDark
          ? const Color(0xFF0F172A)
          : Colors.indigo.shade50.withValues(alpha: 0.3),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _quickPrompts.length,
        separatorBuilder: (ctx, i) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final prompt = _quickPrompts[index];
          return ActionChip(
            label: Text(
              prompt,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isDark
                    ? const Color(0xFFF1F5F9)
                    : Colors.indigo.shade900,
              ),
            ),
            backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
            side: BorderSide(
              color: isDark ? const Color(0xFF334155) : Colors.indigo.shade100,
            ),
            onPressed: () => _handleSend(prompt),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(ChatSession? session) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isTopicSession =
        session != null &&
        session.subject != null &&
        session.subject!.isNotEmpty &&
        session.subject != 'General';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.indigo.withValues(alpha: 0.25)
                    : Colors.indigo.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _getSubjectIcon(session?.subject),
                size: 48,
                color: isDark ? Colors.indigo.shade200 : Colors.indigo.shade700,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isTopicSession
                  ? session.title
                  : 'আপনার ব্যক্তিগত AI মেন্টর ও পার্টনার',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isTopicSession
                  ? 'এই থ্রেডের সমস্ত আলোচনা ও মেমরি সম্পূর্ণ এই টপিকের জন্যই সংরক্ষিত থাকবে। যেকোনো নিয়ম, শর্টকাট বা বিগত বছরের প্রশ্ন জানতে পারেন।'
                  : 'ফুল-টাইম অফিস ও ক্লান্তির সাথে সামঞ্জস্য রেখে BCS ও চাকরির পরীক্ষার সেরা প্রস্তুতি নিন।\nযেকোনো কঠিন টপিক বুঝে নিতে পারেন বা রিভিশন ড্রিল তৈরি করতে বলুন।',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: isTopicSession
                  ? [
                      _buildStarterCard(
                        '📖 মূল নিয়ম ও সহজ ট্রিকস বলো',
                        session.subject ?? 'Core Rules',
                        isDark,
                      ),
                      _buildStarterCard(
                        '⚠️ কমন ফাঁদ ও ভুল হওয়ার জায়গা',
                        'Exam Traps',
                        isDark,
                      ),
                      _buildStarterCard(
                        '📝 বিগত বছরের ৫টি গুরুত্বপূর্ণ MCQ',
                        'Past Questions',
                        isDark,
                      ),
                    ]
                  : [
                      _buildStarterCard(
                        '📖 সমাস বা ব্যাকরণ বুঝাও',
                        'বাংলা ব্যাকরণ',
                        isDark,
                      ),
                      _buildStarterCard(
                        '😴 ৫ মিনিটের কুইক ড্রিল',
                        'ক্লান্তি ম্যানেজমেন্ট',
                        isDark,
                      ),
                      _buildStarterCard(
                        '📅 LiveMCQ রিভিশন ট্রিকস',
                        'পরীক্ষা প্রস্তুতি',
                        isDark,
                      ),
                    ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStarterCard(String title, String subtitle, bool isDark) {
    return InkWell(
      onTap: () => _handleSend(title),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : Colors.grey.shade300,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? const Color(0xFF94A3B8) : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserBubble(ChatMessage message) {
    return Align(
      alignment: Alignment.centerRight,
      child: InkWell(
        onLongPress: () => _copyMessageText(message.textContent),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12, left: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.indigo.shade600,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(4),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                message.textContent,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 5),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatDateTime(message.timestamp),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => _copyMessageText(message.textContent),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        Icons.copy_rounded,
                        size: 12,
                        color: Colors.white.withValues(alpha: 0.8),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final actions = ChatAction.decodeList(message.suggestedAction);

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14, right: 36),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF111827) : Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
          border: Border.all(
            color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade200,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.asset(
                    'assets/branding/playstore_icon_512.png',
                    width: 20,
                    height: 20,
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.school,
                      size: 18,
                      color: Colors.indigo,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'AI Companion',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.indigo,
                  ),
                ),
                const Spacer(),
                Text(
                  _formatDateTime(message.timestamp),
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => _copyMessageText(message.textContent),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2.5,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1E293B)
                          : const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.copy_rounded,
                          size: 11,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : Colors.indigo.shade600,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          'Copy',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : Colors.indigo.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            MarkdownBody(
              data: BengaliMathSanitizer.sanitize(message.textContent),
              selectable: true,
              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                  .copyWith(
                    p: TextStyle(
                      fontSize: 14.5,
                      height: 1.55,
                      color: isDark
                          ? const Color(0xFFF1F5F9)
                          : const Color(0xFF1E293B),
                    ),
                    h1: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      height: 1.5,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                    h2: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      height: 1.45,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                    h3: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      height: 1.4,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                    listBullet: TextStyle(
                      fontSize: 14,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B),
                    ),
                    strong: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                    code: TextStyle(
                      backgroundColor: isDark
                          ? const Color(0xFF1E293B)
                          : Colors.grey.shade100,
                      fontSize: 12.5,
                      fontFamily: 'monospace',
                    ),
                  ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                InkWell(
                  onTap: () => _copyMessageText(message.textContent),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1E293B)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF334155)
                            : const Color(0xFFCBD5E1),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.copy_rounded,
                          size: 13,
                          color: isDark
                              ? const Color(0xFFCBD5E1)
                              : const Color(0xFF475569),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Copy Response',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? const Color(0xFFF1F5F9)
                                : const Color(0xFF334155),
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
              const SizedBox(height: 10),
              _buildVerifyBlock(message, question, priorContext, isDark),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Divider(
                height: 1,
                color: isDark
                    ? const Color(0xFF334155)
                    : const Color(0xFFE2E8F0),
              ),
              const SizedBox(height: 8),
              Text(
                '⚡ Suggested Actions:',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isDark ? const Color(0xFF94A3B8) : Colors.black54,
                ),
              ),
              const SizedBox(height: 6),
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                visualDensity: VisualDensity.compact,
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
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (_verifyFailed.contains(message.id))
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 2),
                child: Text(
                  'যাচাই করা গেল না।',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.redAccent.shade200,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
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
                color: isDark ? Colors.white60 : Colors.black54,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  // Bengali digits, like the rest of the app.
                  '${BengaliMathSanitizer.toBengaliDigits('${result.claimsFound}')}টি দাবির মধ্যে '
                  '${BengaliMathSanitizer.toBengaliDigits('${result.claimsEvaluated}')}টি দেখা হয়েছে · '
                  '${BengaliMathSanitizer.toBengaliDigits('${result.verifiableCount}')}টি স্বাধীনভাবে যাচাই করা গেছে',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          if (result.isPartial) ...[
            const SizedBox(height: 4),
            Text(
              result.extractionNote.isNotEmpty
                  ? result.extractionNote
                  : 'সব দাবি যাচাই করা যায়নি।',
              style: TextStyle(
                fontSize: 10.5,
                color: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
              ),
            ),
          ],
          const SizedBox(height: 8),
          ...result.claims.map((c) => _buildClaimRow(c, isDark)),
          const SizedBox(height: 4),
          Text(
            'External sources not checked',
            style: TextStyle(
              fontSize: 10,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClaimRow(VerifiedClaim claim, bool isDark) {
    // Grey, not amber, for "not verified": amber reads as a warning about the
    // claim, when the only thing being reported is that the app could not
    // check it. Only red warns, and only green claims a check was made.
    final (color, icon, status) = switch (claim.verdict) {
      VerificationVerdict.supported => (
        Colors.green,
        Icons.check_circle_outline,
        'যাচাই হয়েছে',
      ),
      VerificationVerdict.likelyIncorrect => (
        Colors.redAccent,
        Icons.error_outline,
        'সম্ভবত ভুল',
      ),
      VerificationVerdict.inconclusive => (
        isDark ? Colors.white38 : Colors.black38,
        Icons.remove_circle_outline,
        'যাচাই করা যায়নি',
      ),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '“${claim.text}”',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    fontStyle: FontStyle.italic,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 6,
                  runSpacing: 3,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      status,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    Text(
                      '${claim.kind.label} · ${claim.evidence.label}',
                      style: TextStyle(
                        fontSize: 9.5,
                        color: isDark ? Colors.white38 : Colors.black45,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  claim.reasoning,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.45,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
                if (claim.downgraded) ...[
                  const SizedBox(height: 2),
                  Text(
                    'মডেল এটিকে সঠিক বলেছিল, কিন্তু যাচাই করার মতো উৎস নেই।',
                    style: TextStyle(
                      fontSize: 10.5,
                      height: 1.4,
                      fontStyle: FontStyle.italic,
                      color: isDark ? Colors.white38 : Colors.black45,
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
    final isDone = action.isExecuted;

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDone
            ? (isDark
                  ? Colors.green.withValues(alpha: 0.2)
                  : Colors.green.shade50)
            : (isDark
                  ? Colors.indigo.withValues(alpha: 0.2)
                  : Colors.indigo.shade50),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDone
              ? (isDark ? Colors.green.shade800 : Colors.green.shade200)
              : (isDark ? Colors.indigo.shade800 : Colors.indigo.shade200),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isDone ? Icons.check_circle : Icons.auto_awesome,
            size: 16,
            color: isDone
                ? (isDark ? Colors.green.shade400 : Colors.green)
                : (isDark ? Colors.indigo.shade300 : Colors.indigo),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action.title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isDone
                        ? (isDark
                              ? Colors.green.shade300
                              : Colors.green.shade900)
                        : (isDark
                              ? Colors.indigo.shade200
                              : Colors.indigo.shade900),
                  ),
                ),
                Text(
                  'Subject: ${action.subject}',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isDone
                  ? (isDark ? Colors.green.shade900 : Colors.green.shade100)
                  : Colors.indigo,
              foregroundColor: isDone
                  ? (isDark ? Colors.green.shade100 : Colors.green.shade900)
                  : Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            onPressed: isDone
                ? null
                : () async {
                    final success = await ref
                        .read(chatNotifierProvider.notifier)
                        .executeAction(action: action, message: message);
                    if (success && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '"${action.title}" added to Weak Topics radar!',
                          ),
                          backgroundColor: Colors.green.shade700,
                        ),
                      );
                    }
                  },
            child: Text(
              isDone ? 'Saved' : 'Save Topic',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThinkingIndicator() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.indigo,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Gemini is thinking...',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white70 : Colors.black54,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        MediaQuery.of(context).viewInsets.bottom > 0 ? 8 : 16,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111827) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade200,
          ),
        ),
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
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white : Colors.black87,
              ),
              decoration: InputDecoration(
                hintText: _isRecording
                    ? '🎙 শুনছি… ${_recordedSeconds}s / ${_maxRecordSeconds}s'
                    : (_isTranscribing
                          ? 'লেখা হচ্ছে…'
                          : 'Ask Gemini anything (BCS, routine, doubts)...'),
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white54 : Colors.grey.shade500,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF1E293B)
                    : Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
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
                    color: _isRecording
                        ? Colors.redAccent
                        : (isDark ? Colors.white60 : Colors.grey.shade600),
                  ),
          ),
          const SizedBox(width: 2),
          CircleAvatar(
            backgroundColor: isSending
                ? (isDark ? Colors.grey.shade700 : Colors.grey.shade300)
                : Colors.indigo,
            radius: 20,
            child: IconButton(
              icon: isSending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send, size: 18, color: Colors.white),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Consumer(
          builder: (context, ref, _) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final sessionsAsync = ref.watch(chatSessionsStreamProvider);
            final activeSessionId = ref
                .watch(chatNotifierProvider)
                .currentSessionId;

            return SafeArea(
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.75,
                ),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        Icon(
                          Icons.forum,
                          color: isDark
                              ? const Color(0xFF818CF8)
                              : Colors.indigo,
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Study Threads & Sessions',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF0F172A),
                          ),
                        ),
                        const Spacer(),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.add, size: 15),
                          label: const Text(
                            'New Thread',
                            style: TextStyle(fontSize: 12),
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _showNewSessionDialog(context);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Each thread maintains separate, focused memory for that subject or topic.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark ? const Color(0xFF94A3B8) : Colors.grey,
                      ),
                    ),
                    Divider(
                      height: 20,
                      color: isDark
                          ? const Color(0xFF334155)
                          : const Color(0xFFE2E8F0),
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
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.black54,
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
                                elevation: isActive ? 1.5 : 0.5,
                                margin: const EdgeInsets.only(bottom: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: isActive
                                        ? Colors.indigo.shade400
                                        : (isDark
                                              ? const Color(0xFF334155)
                                              : Colors.grey.shade200),
                                    width: isActive ? 1.5 : 1,
                                  ),
                                ),
                                color: isActive
                                    ? (isDark
                                          ? Colors.indigo.withValues(alpha: 0.3)
                                          : Colors.indigo.shade50.withValues(
                                              alpha: 0.5,
                                            ))
                                    : (isDark
                                          ? const Color(0xFF1E293B)
                                          : Colors.white),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: isActive
                                        ? Colors.indigo
                                        : (isDark
                                              ? const Color(0xFF0F172A)
                                              : Colors.grey.shade100),
                                    child: Icon(
                                      _getSubjectIcon(session.subject),
                                      color: isActive
                                          ? Colors.white
                                          : (isDark
                                                ? Colors.indigo.shade300
                                                : Colors.indigo.shade800),
                                      size: 20,
                                    ),
                                  ),
                                  title: Text(
                                    session.title,
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: isActive
                                          ? FontWeight.bold
                                          : FontWeight.w500,
                                      color: isActive
                                          ? (isDark
                                                ? Colors.indigo.shade200
                                                : Colors.indigo.shade900)
                                          : (isDark
                                                ? Colors.white
                                                : Colors.black87),
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${session.subject ?? "General"} • ${_formatDateTime(session.updatedAt)}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark
                                          ? const Color(0xFF94A3B8)
                                          : Colors.grey.shade600,
                                    ),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isActive)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.indigo,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: const Text(
                                            'Active',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      PopupMenuButton<String>(
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
                                          const PopupMenuItem(
                                            value: 'rename',
                                            child: Text('Rename'),
                                          ),
                                          if (sessions.length > 1)
                                            const PopupMenuItem(
                                              value: 'delete',
                                              child: Text(
                                                'Delete',
                                                style: TextStyle(
                                                  color: Colors.red,
                                                ),
                                              ),
                                            ),
                                        ],
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
        title: const Text('Create New Study Thread'),
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
              const SizedBox(height: 10),
              TextField(
                controller: topicController,
                decoration: const InputDecoration(
                  labelText: 'Topic Name (e.g. কারক ও বিভক্তি, লাভ-ক্ষতি)',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
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
        title: const Text('Rename Thread'),
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
        title: Text('Delete "${session.title}"?'),
        content: const Text(
          'This will permanently delete this thread and all its messages from your local device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
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
        title: const Row(
          children: [
            Icon(Icons.psychology, color: Colors.indigo),
            SizedBox(width: 8),
            Text('Active Gemini Context', style: TextStyle(fontSize: 16)),
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
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(ctx).brightness == Brightness.dark
                      ? Colors.white70
                      : Colors.black54,
                ),
              ),
              const Divider(height: 20),
              if (activeSession != null) ...[
                Text(
                  '💬 Active Thread: ${activeSession.title}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.indigo,
                  ),
                ),
                if (activeSession.subject != null)
                  Text(
                    'Subject: ${activeSession.subject} | Topic: ${activeSession.topic ?? "General"}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(ctx).brightness == Brightness.dark
                          ? Colors.white
                          : Colors.black87,
                    ),
                  ),
                const SizedBox(height: 10),
              ],
              Text(
                '⚡ Energy: ${todayLog?.energyLevel.name ?? "Moderate"} | Fatigue: ${todayLog?.officeFatigueScore ?? 5}/10',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '🎯 Weak Topics (${weakTopics.length}):',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              if (weakTopics.isEmpty)
                const Text(
                  'None yet',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                )
              else
                ...weakTopics.map(
                  (t) => Text(
                    '• [${t.subject}] ${t.topicName} (${t.proficiencyLevel.name})',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              const SizedBox(height: 10),
              Text(
                '📅 Upcoming Exams (${exams.length}):',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              if (exams.isEmpty)
                const Text(
                  'No exams scheduled',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                )
              else
                ...exams.map(
                  (e) => Text(
                    '• ${e.title} (${e.examDate.toIso8601String().substring(0, 10)})',
                    style: const TextStyle(fontSize: 12),
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
        title: const Text('Clear Thread Messages?'),
        content: Text(
          'This will delete messages in "${currentSession?.title ?? "this thread"}" from your local device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
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
