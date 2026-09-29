import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../mock_data/mock_data.dart';
import '../../models/models.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_avatar.dart';
import '../../services/chat_service.dart';
import '../../services/token_storage_service.dart';

class ChatInterfaceScreen extends StatefulWidget {
  final Conversation conversation;
  final VoidCallback onBack;

  const ChatInterfaceScreen({
    super.key,
    required this.conversation,
    required this.onBack,
  });

  @override
  State<ChatInterfaceScreen> createState() => _ChatInterfaceScreenState();
}

class _ChatInterfaceScreenState extends State<ChatInterfaceScreen> {
  late List<ChatMessage> _messages;
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final TokenStorageService _tokenStorage = TokenStorageService();
  final ChatService _chatService = ChatService();

  String _myName = 'Me';
  bool _isSending = false;
  Map<String, dynamic>? _agentCriteria;

  bool get _isAiBot =>
      widget.conversation.id == 'ai_bot' ||
      widget.conversation.partnerName.toLowerCase().contains('ai bot');

  @override
  void initState() {
    super.initState();
    _messages = MockData.conversationMessages[widget.conversation.id] ?? [];
    _loadData();
  }

  Future<void> _loadData() async {
    final profile = await _tokenStorage.getStudentProfile();
    final name = profile['full_name'] as String? ?? '';
    if (mounted && name.isNotEmpty) {
      setState(() {
        _myName = name;
      });
    }

    if (_isAiBot) {
      final criteria = await _chatService.getAiBotCriteria();
      if (mounted && criteria != null) {
        setState(() {
          _agentCriteria = criteria;
        });
      }
    }

    // Fetch backend messages
    if (widget.conversation.id.isNotEmpty) {
      final backendMsgs = await _chatService.getMessages(widget.conversation.id);
      if (mounted && backendMsgs.isNotEmpty) {
        setState(() {
          _messages = backendMsgs;
          MockData.conversationMessages[widget.conversation.id] = backendMsgs;
          if (backendMsgs.isNotEmpty) {
            widget.conversation.lastMessage = backendMsgs.last.text;
            widget.conversation.time = backendMsgs.last.time;
          }
        });
      }
    }
    _scrollToBottom(animated: false);
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        if (animated) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent + 80,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        } else {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent + 80);
        }
      }
    });
  }

  Future<void> _sendMessage([String? customText]) async {
    final text = (customText ?? _inputController.text).trim();
    if (text.isEmpty || _isSending) return;

    final tempMsg = ChatMessage(
      id: 'msg-${DateTime.now().millisecondsSinceEpoch}',
      senderId: 'me',
      senderName: _myName,
      text: text,
      time: 'Just now',
      isMe: true,
    );

    setState(() {
      _messages.add(tempMsg);
      MockData.conversationMessages[widget.conversation.id] = _messages;
      widget.conversation.lastMessage = text;
      widget.conversation.time = 'Just now';
      _isSending = true;
    });
    _inputController.clear();
    _scrollToBottom();

    try {
      await _chatService.sendMessage(
        recipientId: widget.conversation.id,
        text: text,
        conversationId: widget.conversation.id,
        recipientName: widget.conversation.partnerName,
      );

      if (_isAiBot) {
        await _loadData();
      }
    } catch (_) {
      // Silent fallback
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
        _scrollToBottom();
      }
    }
  }

  void _showCriteriaSheet() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final roles = (_agentCriteria?['target_roles'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final domains = (_agentCriteria?['preferred_domains'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final minLpa = _agentCriteria?['min_ctc_lpa'];
    final maxLpa = _agentCriteria?['max_ctc_lpa'];
    final autoApply = _agentCriteria?['autonomous_apply_enabled'] ?? true;
    final lastInstruction = _agentCriteria?['last_instruction'] as String? ?? '';

    String salaryText = 'Any package (no minimum)';
    if (minLpa != null && maxLpa != null) {
      salaryText = '$minLpa – $maxLpa LPA';
    } else if (minLpa != null) {
      salaryText = '$minLpa+ LPA';
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1F2B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Active Placement Criteria',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Interpreted autonomously from instructions',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: autoApply ? const Color(0x1F22C55E) : const Color(0x1FEF4444),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: autoApply ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          autoApply ? Icons.check_circle_rounded : Icons.pause_circle_rounded,
                          size: 13,
                          color: autoApply ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          autoApply ? 'AUTONOMOUS' : 'PAUSED',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: autoApply ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Target Roles & Domains
              const Text(
                'TARGET ROLES & DOMAINS',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: Color(0xFF6366F1)),
              ),
              const SizedBox(height: 8),
              if (roles.isEmpty && domains.isEmpty)
                Text(
                  'No specific domain restrictions (all eligible campus drives considered).',
                  style: TextStyle(fontSize: 13, color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                )
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ...roles.map((r) => _buildCriteriaChip(r, const Color(0xFF6366F1), isDark)),
                    ...domains.map((d) => _buildCriteriaChip(d, const Color(0xFF0EA5E9), isDark)),
                  ],
                ),
              const SizedBox(height: 16),
              // Package
              const Text(
                'MINIMUM PACKAGE EXPECTATION',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: Color(0xFF6366F1)),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF26283B) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.currency_rupee_rounded, size: 16, color: Color(0xFF10B981)),
                    const SizedBox(width: 6),
                    Text(
                      salaryText,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ],
                ),
              ),
              if (lastInstruction.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'LAST RECORDED INSTRUCTION',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: Color(0xFF6366F1)),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF26283B) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: isDark ? Colors.white12 : Colors.grey[300]!),
                  ),
                  child: Text(
                    '"$lastInstruction"',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontStyle: FontStyle.italic,
                      color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.edit_note_rounded, size: 18),
                  label: const Text('Update by messaging AI Bot'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCriteriaChip(String label, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F1017) : const Color(0xFFF8FAFC),
      appBar: _buildAppBar(theme, isDark),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _isAiBot
                    ? _buildAiBotWelcome(theme, isDark)
                    : Center(
                        child: Text(
                          'No messages yet. Say hello!',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.hintColor,
                          ),
                        ),
                      )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    itemCount: _messages.length + (_isSending && _isAiBot ? 1 : 0),
                    itemBuilder: (context, index) {
                      // Date badge at the top
                      if (index == 0) {
                        return Column(
                          children: [
                            _buildDateBadge(isDark),
                            const SizedBox(height: 12),
                            _buildMessageBubble(_messages[0], isDark),
                          ],
                        );
                      }
                      if (index < _messages.length) {
                        return _buildMessageBubble(_messages[index], isDark);
                      }
                      // Thinking indicator when bot is responding
                      return _buildThinkingBubble(isDark);
                    },
                  ),
          ),
          if (_isAiBot) _buildSuggestionsCarousel(isDark),
          _buildInputBar(theme, isDark),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ThemeData theme, bool isDark) {
    return AppBar(
      elevation: 0.5,
      backgroundColor: isDark ? const Color(0xFF161722) : Colors.white,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.arrow_back_rounded, size: 20),
        ),
        onPressed: widget.onBack,
      ),
      titleSpacing: 0,
      title: Row(
        children: [
          _isAiBot
              ? Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 22),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(
                          color: const Color(0xFF22C55E),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark ? const Color(0xFF161722) : Colors.white,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : AppAvatar(
                  radius: 19,
                  imageUrl: widget.conversation.avatarUrl,
                  fallbackText: widget.conversation.partnerName,
                ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        widget.conversation.partnerName,
                        style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_isAiBot) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6366F1), Color(0xFF818CF8)],
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'AI AGENT',
                          style: TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF22C55E),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _isAiBot ? 'Placement Assistant · Autonomous' : 'Active Now',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        if (_isAiBot)
          IconButton(
            tooltip: 'View Active Placement Criteria',
            icon: const Icon(Icons.tune_rounded, size: 21),
            onPressed: _showCriteriaSheet,
          ),
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh_rounded, size: 21),
          onPressed: _loadData,
        ),
      ],
    );
  }

  Widget _buildDateBadge(bool isDark) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1F2B) : const Color(0xFFE2E8F0),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'TODAY',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestionsCarousel(bool isDark) {
    final suggestions = [
      '💼 Apply for AI/ML roles (3-4 LPA)',
      '🚀 Target Full Stack / Python (5+ LPA)',
      '📊 Show my active criteria',
      '🔍 Check matching campus drives',
      '⚡ Apply to all eligible drives',
    ];

    return Container(
      height: 42,
      margin: const EdgeInsets.only(bottom: 6),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        scrollDirection: Axis.horizontal,
        itemCount: suggestions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final prompt = suggestions[index];
          return ActionChip(
            label: Text(
              prompt,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: isDark ? const Color(0xFFC7D2FE) : const Color(0xFF4338CA),
              ),
            ),
            backgroundColor: isDark ? const Color(0xFF1E2139) : const Color(0xFFEEF2FF),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: isDark ? const Color(0xFF373A63) : const Color(0xFFC7D2FE),
                width: 1,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            onPressed: () => _sendMessage(prompt.replaceFirst(RegExp(r'^[^\w]+'), '').trim()),
          );
        },
      ),
    );
  }

  Widget _buildThinkingBubble(bool isDark) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E2138) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? const Color(0xFF33385B) : const Color(0xFFE2E8F0),
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
                color: Color(0xFF6366F1),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'AI Bot is analyzing campus drives...',
              style: TextStyle(
                fontSize: 12.5,
                fontStyle: FontStyle.italic,
                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiBotWelcome(ThemeData theme, bool isDark) {
    final samplePrompts = [
      'Apply for upcoming companies that require AI/ML skills with a salary of 3–4 LPA.',
      'Target Full Stack Developer or Python roles with 5+ LPA.',
      'Show my active placement criteria.',
    ];

    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 16),
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 34),
          ),
          const SizedBox(height: 16),
          Text(
            'Autonomous Placement Assistant',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Instruct me in plain English! I continuously monitor recruiter drives, verify university criteria, and auto-apply on your behalf.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'QUICK SUGGESTIONS:',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
                letterSpacing: 0.6,
              ),
            ),
          ),
          const SizedBox(height: 10),
          ...samplePrompts.map(
            (prompt) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () => _sendMessage(prompt),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkSurfaceContainer
                        : AppColors.lightSurfaceContainer,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark
                          ? AppColors.darkOutlineVariant
                          : AppColors.lightOutlineVariant,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.chat_bubble_outline_rounded, size: 16, color: Color(0xFF6366F1)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          prompt,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                          ),
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: Colors.grey),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg, bool isDark) {
    final isBotMsg = !msg.isMe && _isAiBot;

    return Align(
      alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.84,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: msg.isMe
              ? const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: msg.isMe
              ? null
              : isBotMsg
                  ? (isDark ? const Color(0xFF1E2138) : const Color(0xFFF8FAFC))
                  : (isDark ? AppColors.darkSurfaceContainer : AppColors.lightSurfaceContainer),
          border: isBotMsg
              ? Border.all(
                  color: isDark ? const Color(0xFF33385B) : const Color(0xFFE2E8F0),
                  width: 1,
                )
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(msg.isMe ? 18 : 4),
            bottomRight: Radius.circular(msg.isMe ? 4 : 18),
          ),
        ),
        child: Column(
          crossAxisAlignment: msg.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (isBotMsg) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.smart_toy_rounded, size: 14, color: Color(0xFF6366F1)),
                      SizedBox(width: 5),
                      Text(
                        'AI Placement Assistant',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF6366F1),
                        ),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: msg.text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Copied message to clipboard'),
                          duration: Duration(seconds: 1),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(
                        Icons.copy_rounded,
                        size: 13,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
            Text(
              msg.text,
              style: TextStyle(
                color: msg.isMe
                    ? Colors.white
                    : (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 5),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  msg.time,
                  style: TextStyle(
                    color: msg.isMe
                        ? Colors.white70
                        : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                    fontSize: 10,
                  ),
                ),
                if (msg.isMe) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.done_all_rounded, size: 13, color: Colors.white70),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161722) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF26283B) : const Color(0xFFE2E8F0),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF202234) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isDark ? const Color(0xFF33385B) : const Color(0xFFE2E8F0),
                  ),
                ),
                child: TextField(
                  controller: _inputController,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  decoration: InputDecoration(
                    hintText: _isAiBot
                        ? 'Instruct AI Bot (e.g. Apply for AI/ML 3-4 LPA)...'
                        : 'Type a message...',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: _isSending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 22),
                onPressed: _isSending ? null : () => _sendMessage(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}