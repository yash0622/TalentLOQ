import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../mock_data/mock_data.dart';
import '../../models/models.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_avatar.dart';
import '../../services/chat_service.dart';
import '../../services/token_storage_service.dart';
import '../../utils/chat_date_util.dart';

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

class _ChatInterfaceScreenState extends State<ChatInterfaceScreen> with TickerProviderStateMixin {
  late List<ChatMessage> _messages;
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final TokenStorageService _tokenStorage = TokenStorageService();
  final ChatService _chatService = ChatService();
  late AnimationController _dotsController;
  final Set<String> _animatedMessageIds = <String>{};

  String _myName = 'Me';
  bool _isSending = false;
  Map<String, dynamic>? _agentCriteria;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String? _activeSessionId;
  List<Map<String, dynamic>>? _aiSessions;
  bool? _isLoadingSessions;

  bool get _isAiBot =>
      widget.conversation.id == 'ai_bot' ||
      widget.conversation.partnerName.toLowerCase().contains('ai bot');

  @override
  void initState() {
    super.initState();
    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
    _messages = MockData.conversationMessages[widget.conversation.id] ?? [];
    _animatedMessageIds.addAll(_messages.map((m) => m.id));
    _loadData();
  }

  Future<void> _loadData([String? sessionId]) async {
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

    final currentActive = _activeSessionId ?? '';
    final targetId = sessionId ?? (currentActive.isNotEmpty ? currentActive : widget.conversation.id);
    _activeSessionId = targetId;

    // Fetch backend messages
    if (targetId.isNotEmpty) {
      final backendMsgs = await _chatService.getMessages(targetId);
      if (mounted && backendMsgs.isNotEmpty) {
        setState(() {
          _messages = backendMsgs;
          _animatedMessageIds.addAll(backendMsgs.map((m) => m.id));
          MockData.conversationMessages[targetId] = backendMsgs;
          if (backendMsgs.isNotEmpty) {
            widget.conversation.lastMessage = backendMsgs.last.text;
            widget.conversation.time = backendMsgs.last.time;
          }
        });
      }
    }
    _scrollToBottom(animated: false);
    if (_isAiBot) {
      _loadAiSessions();
    }
  }

  Future<void> _loadAiSessions() async {
    setState(() => _isLoadingSessions = true);
    try {
      final sessions = await _chatService.getAiSessions();
      if (mounted) {
        setState(() {
          _aiSessions = sessions;
          _isLoadingSessions = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingSessions = false);
      }
    }
  }

  void _startNewChat() {
    Navigator.of(context).pop();
    final newId = 'ai_bot_${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      _activeSessionId = newId;
      _messages.clear();
      _animatedMessageIds.clear();
      widget.conversation.lastMessage = '';
    });
  }

  void _selectSession(String sessionId) {
    Navigator.of(context).pop();
    if (_activeSessionId != sessionId) {
      _loadData(sessionId);
    }
  }

  Future<void> _deleteSession(String sessionId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Chat', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: const Text('Are you sure you want to delete this chat session?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _chatService.clearConversation(sessionId);
      if (mounted) {
        if (_activeSessionId == sessionId) {
          _startNewChat();
        }
        await _loadAiSessions();
      }
    }
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
      final currentActive = _activeSessionId ?? '';
      final targetId = currentActive.isNotEmpty ? currentActive : widget.conversation.id;
      final result = await _chatService.sendMessage(
        recipientId: widget.conversation.id,
        text: text,
        conversationId: targetId,
        recipientName: widget.conversation.partnerName,
      );

      if (mounted) {
        setState(() {
          _isSending = false;
          final tempIdx = _messages.indexWhere((m) => m.id == tempMsg.id);
          if (tempIdx != -1 && result != null) {
            _messages[tempIdx] = result.userMessage;
          }
          final bot = result?.botResponse;
          if (bot != null) {
            _messages.add(bot);
            widget.conversation.lastMessage = bot.text;
            widget.conversation.time = bot.time;
          }
        });
        _scrollToBottom();
        if (_isAiBot) {
          _loadAiSessions();
          _chatService.getAiBotCriteria().then((crit) {
            if (mounted && crit != null) {
              setState(() => _agentCriteria = crit);
            }
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSending = false;
          if (_isAiBot) {
            final errMsg = ChatMessage(
              id: 'err-${DateTime.now().millisecondsSinceEpoch}',
              senderId: 'ai_bot',
              senderName: 'Placement Assistant',
              text: "I'm having trouble connecting right now. Please try again in a moment.",
              time: 'Just now',
              isMe: false,
            );
            _messages.add(errMsg);
            _animatedMessageIds.add(errMsg.id);
          }
        });
        _scrollToBottom();
      }
    } finally {
      if (mounted && _isSending) {
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
                  label: const Text('Update by messaging Assistant'),
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

  Future<void> _showClearAiChatDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.delete_sweep_rounded, color: Colors.redAccent, size: 24),
            SizedBox(width: 8),
            Text('Clear Chat', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: const Text(
          'Are you sure you want to delete all messages? This cannot be undone.',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final messenger = ScaffoldMessenger.of(context);
      final currentActive = _activeSessionId ?? '';
      final target = currentActive.isNotEmpty ? currentActive : widget.conversation.id;
      final ok = await _chatService.clearConversation(target);
      if (mounted) {
        setState(() {
          _messages.clear();
          widget.conversation.lastMessage = '';
          MockData.conversationMessages.remove(widget.conversation.id);
          MockData.conversationMessages.remove('ai_bot');
          MockData.conversationMessages.remove(target);
        });
        if (_isAiBot) {
          await _loadAiSessions();
        }
        messenger.showSnackBar(
          SnackBar(
            content: Text(ok ? 'Chat cleared successfully' : 'Chat cleared locally'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _dotsController.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _aiSessions ??= [];
    _activeSessionId ??= widget.conversation.id;
    _isLoadingSessions ??= false;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      key: _scaffoldKey,
      endDrawer: _isAiBot ? _buildChatHistorySidebar(theme, isDark) : null,
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
                          'ASSISTANT',
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
        if (_isAiBot)
          TextButton.icon(
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
            icon: const Icon(Icons.history_rounded, size: 18),
            label: const Text('History', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            style: TextButton.styleFrom(
              foregroundColor: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
          ),
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh_rounded, size: 21),
          onPressed: _loadData,
        ),
      ],
    );
  }

  Widget _buildChatHistorySidebar(ThemeData theme, bool isDark) {
    final width = MediaQuery.of(context).size.width * 0.82;
    final clampedWidth = width.clamp(280.0, 360.0);
    final sessions = _aiSessions ?? const <Map<String, dynamic>>[];
    final activeId = _activeSessionId ?? '';
    final isLoading = _isLoadingSessions ?? false;

    return Drawer(
      width: clampedWidth,
      backgroundColor: isDark ? const Color(0xFF131525) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          bottomLeft: Radius.circular(20),
        ),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.history_rounded, size: 18, color: Color(0xFF6366F1)),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Chat History',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.3,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: ElevatedButton.icon(
                onPressed: _startNewChat,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text(
                  'New Chat',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Text(
                'PREVIOUS CHATS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                ),
              ),
            ),
            const Divider(height: 12, thickness: 0.6),
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : sessions.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  size: 36,
                                  color: isDark ? const Color(0xFF33385B) : const Color(0xFFCBD5E1),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'No previous chats',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          itemCount: sessions.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 4),
                          itemBuilder: (context, index) {
                            final session = sessions[index];
                            final sid = session['id'] as String? ?? '';
                            final title = session['title'] as String? ?? 'Conversation';
                            final lastMsg = session['last_message'] as String? ?? '';
                            final time = session['time'] as String? ?? '';
                            final isActive = sid == activeId ||
                                (activeId.isEmpty && index == 0);

                            return InkWell(
                              onTap: () => _selectSession(sid),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? (isDark
                                          ? const Color(0xFF6366F1).withValues(alpha: 0.18)
                                          : const Color(0xFF6366F1).withValues(alpha: 0.1))
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                  border: isActive
                                      ? Border.all(
                                          color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                                          width: 1,
                                        )
                                      : null,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  title,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                                                    color: isActive
                                                        ? (isDark ? Colors.white : const Color(0xFF4F46E5))
                                                        : (isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B)),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                formatChatTimestamp(time),
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (lastMsg.isNotEmpty) ...[
                                            const SizedBox(height: 3),
                                            Text(
                                              lastMsg,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      icon: Icon(
                                        Icons.delete_outline_rounded,
                                        size: 15,
                                        color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                                      ),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                      tooltip: 'Delete chat',
                                      onPressed: () => _deleteSession(sid),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
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
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
          ),
          border: Border.all(
            color: isDark ? const Color(0xFF33385B) : const Color(0xFFE2E8F0),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.smart_toy_rounded, size: 11, color: Colors.white),
            ),
            const SizedBox(width: 8),
            _buildAnimatedDots(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedDots(bool isDark) {
    return AnimatedBuilder(
      animation: _dotsController,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final delay = index * 0.25;
            final progress = (_dotsController.value - delay) % 1.0;
            final scale = 0.6 + 0.4 * (1.0 - (progress - 0.5).abs() * 2).clamp(0.0, 1.0);
            final opacity = 0.35 + 0.65 * (1.0 - (progress - 0.5).abs() * 2).clamp(0.0, 1.0);

            return Transform.scale(
              scale: scale,
              child: Opacity(
                opacity: opacity,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2.2),
                  width: 5.5,
                  height: 5.5,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
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
    final bubbleWidget = Container(
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
                      'Placement Assistant',
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
          if (isBotMsg && !_animatedMessageIds.contains(msg.id))
            AiWordStreamText(
              fullText: msg.text,
              style: TextStyle(
                color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                fontSize: 13.5,
                height: 1.45,
              ),
              onWordEmitted: () => _scrollToBottom(animated: false),
              onComplete: () {
                if (mounted) {
                  setState(() => _animatedMessageIds.add(msg.id));
                }
              },
            )
          else
            Text(
              msg.text,
              style: TextStyle(
                color: msg.isMe
                    ? Colors.white
                    : (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
                fontSize: 13.5,
                height: 1.45,
              ),
            ),
          const SizedBox(height: 5),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                formatChatTimestamp(msg.time),
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
    );

    return Align(
      alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: isBotMsg
          ? GestureDetector(
              onLongPress: _showClearAiChatDialog,
              child: bubbleWidget,
            )
          : bubbleWidget,
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
                        ? 'Instruct Assistant (e.g. Apply for 3-4 LPA)...'
                        : 'Type a message...',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    filled: false,
                    fillColor: Colors.transparent,
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

/// Fast, progressive word-by-word streaming typewriter text widget with a minimal pulsing cursor
class AiWordStreamText extends StatefulWidget {
  final String fullText;
  final TextStyle? style;
  final Duration wordDuration;
  final VoidCallback? onWordEmitted;
  final VoidCallback? onComplete;

  const AiWordStreamText({
    super.key,
    required this.fullText,
    this.style,
    this.wordDuration = const Duration(milliseconds: 22),
    this.onWordEmitted,
    this.onComplete,
  });

  @override
  State<AiWordStreamText> createState() => _AiWordStreamTextState();
}

class _AiWordStreamTextState extends State<AiWordStreamText> {
  late List<String> _tokens;
  int _currentTokenIndex = 0;
  Timer? _timer;
  bool _isFinished = false;

  @override
  void initState() {
    super.initState();
    _tokens = _tokenize(widget.fullText);
    if (_tokens.isEmpty) {
      _isFinished = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onComplete?.call();
      });
    } else {
      _startTimer();
    }
  }

  List<String> _tokenize(String text) {
    final pattern = RegExp(r'(\S+\s*)');
    final matches = pattern.allMatches(text);
    final result = matches.map((m) => m.group(0) ?? '').toList();
    return result.isNotEmpty ? result : [text];
  }

  void _startTimer() {
    _timer?.cancel();
    _currentTokenIndex = 0;
    _isFinished = false;

    _timer = Timer.periodic(widget.wordDuration, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_currentTokenIndex < _tokens.length) {
        // Fast streaming: 2 words per tick for long content, 1 word for short
        final step = (_tokens.length - _currentTokenIndex > 35) ? 2 : 1;
        setState(() {
          _currentTokenIndex = (_currentTokenIndex + step).clamp(0, _tokens.length);
        });
        widget.onWordEmitted?.call();
      } else {
        timer.cancel();
        setState(() {
          _isFinished = true;
        });
        widget.onComplete?.call();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isFinished) {
      return Text(widget.fullText, style: widget.style);
    }
    final visibleText = _tokens.take(_currentTokenIndex).join();
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(text: visibleText, style: widget.style),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              margin: const EdgeInsets.only(left: 2),
              width: 2,
              height: (widget.style?.fontSize ?? 13.5) * 1.15,
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}