import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:talentloq/models/models.dart';

import '../../mock_data/mock_data.dart';
import '../../services/chat_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/chat_date_util.dart';

/// Recruiter AI Recruitment Intelligence Assistant Screen
/// Implements Hybrid OKF (Objective Knowledge Filtering) + RAG (Retrieval-Augmented Generation)
/// with a luxury, modern SaaS aesthetic inspired by glowing intelligence orbs.
class RecruiterAiScreen extends StatefulWidget {
  final Conversation conversation;
  final VoidCallback onBack;
  final Function(Candidate candidate)? onSelectCandidate;
  final Function(Candidate candidate)? onScheduleCandidate;

  const RecruiterAiScreen({
    super.key,
    required this.conversation,
    required this.onBack,
    this.onSelectCandidate,
    this.onScheduleCandidate,
  });

  @override
  State<RecruiterAiScreen> createState() => _RecruiterAiScreenState();
}

class _RecruiterAiScreenState extends State<RecruiterAiScreen>
    with TickerProviderStateMixin {
  final List<ChatMessage> _messages = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ChatService _chatService = ChatService();

  late AnimationController _orbPulseController;
  late AnimationController _orbRotateController;
  late AnimationController _dotsController;
  final Set<String> _animatedMessageIds = {};
  final Set<String> _shortlistedCandidateIds = {};
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String? _activeSessionId = 'recruiter_ai_bot';
  List<Map<String, dynamic>>? _aiSessions;
  bool? _isLoadingSessions;

  bool _isSending = false;
  bool _isLoadingHistory = true;

  @override
  void initState() {
    super.initState();

    _orbPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    _orbRotateController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();

    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();

    _loadMessages(null, true);
  }

  @override
  void dispose() {
    _orbPulseController.dispose();
    _orbRotateController.dispose();
    _dotsController.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages([String? sessionId, bool showLoading = false]) async {
    final targetId = sessionId ?? (_activeSessionId ?? 'recruiter_ai_bot');
    if (showLoading) {
      setState(() {
        _isLoadingHistory = true;
        _activeSessionId = targetId;
      });
    } else {
      _activeSessionId = targetId;
    }
    try {
      final history = await _chatService.getMessages(targetId);
      if (mounted) {
        setState(() {
          if (showLoading) {
            _messages.clear();
            _messages.addAll(history);
            _animatedMessageIds.addAll(history.map((m) => m.id));
            _isLoadingHistory = false;
          } else {
            final existingIds = _messages.map((m) => m.id).toSet();
            for (final m in history) {
              if (!existingIds.contains(m.id)) {
                _messages.add(m);
              }
            }
          }
        });
        _scrollToBottom(animated: !showLoading);
      }
    } catch (_) {
      if (mounted && showLoading) {
        setState(() => _isLoadingHistory = false);
      }
    }
    if (showLoading) {
      _loadAiSessions();
    }
  }

  Future<void> _loadAiSessions({bool showLoading = false}) async {
    if (showLoading) {
      setState(() => _isLoadingSessions = true);
    }
    try {
      final sessions = await _chatService.getAiSessions();
      if (mounted) {
        setState(() {
          _aiSessions = sessions;
          _isLoadingSessions = false;
        });
      }
    } catch (_) {
      if (mounted && showLoading) {
        setState(() => _isLoadingSessions = false);
      }
    }
  }

  void _startNewChat() {
    Navigator.of(context).pop();
    final newId = 'recruiter_ai_bot_${DateTime.now().millisecondsSinceEpoch}';
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
      _loadMessages(sessionId, true);
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
      if (!_scrollController.hasClients) return;
      if (animated) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutQuad,
        );
      } else {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _sendMessage([String? customText]) async {
    final text = (customText ?? _inputController.text).trim();
    if (text.isEmpty || _isSending) return;

    final tempMsg = ChatMessage(
      id: 'msg-${DateTime.now().millisecondsSinceEpoch}',
      senderId: 'recruiter',
      senderName: 'You',
      text: text,
      time: 'Just now',
      isMe: true,
    );

    setState(() {
      _messages.add(tempMsg);
      _isSending = true;
    });
    _inputController.clear();
    _scrollToBottom();

    try {
      final targetId = _activeSessionId ?? 'recruiter_ai_bot';
      final result = await _chatService.sendMessage(
        recipientId: 'recruiter_ai_bot',
        text: text,
        conversationId: targetId,
        recipientName: 'Talent Scout',
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
        if (result?.botResponse == null) {
          await _loadMessages(targetId, false);
        }
        _loadAiSessions();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to get response: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted && _isSending) {
        setState(() => _isSending = false);
        _scrollToBottom();
      }
    }
  }

  void _toggleShortlist(String id, String name) {
    setState(() {
      if (_shortlistedCandidateIds.contains(id)) {
        _shortlistedCandidateIds.remove(id);
      } else {
        _shortlistedCandidateIds.add(id);
      }
    });
    final isShortlisted = _shortlistedCandidateIds.contains(id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isShortlisted
              ? '⭐ $name added to your shortlisted candidates!'
              : '$name removed from shortlist.',
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showClearChatDialog() async {
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
      final target = _activeSessionId ?? 'recruiter_ai_bot';
      final ok = await _chatService.clearConversation(target);
      if (mounted) {
        setState(() {
          _messages.clear();
          _animatedMessageIds.clear();
          widget.conversation.lastMessage = '';
          MockData.conversationMessages.remove(widget.conversation.id);
          MockData.conversationMessages.remove('recruiter_ai_bot');
          MockData.conversationMessages.remove(target);
        });
        await _loadAiSessions();
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
  Widget build(BuildContext context) {
    _aiSessions ??= [];
    _activeSessionId ??= 'recruiter_ai_bot';
    _isLoadingSessions ??= false;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isDark ? const Color(0xFF0C0D17) : const Color(0xFFFAFAFE);

    return Scaffold(
      key: _scaffoldKey,
      endDrawer: _buildChatHistorySidebar(theme, isDark),
      backgroundColor: bgColor,
      appBar: _buildAppBar(theme, isDark),
      body: SafeArea(
        child: Stack(
          children: [
            // Main content area with bottom padding for floating bar
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 80),
                child: _isLoadingHistory
                    ? _buildLoadingState(isDark)
                    : _messages.isEmpty
                        ? _buildEmptyWelcomeState(theme, isDark)
                        : _buildChatList(theme, isDark),
              ),
            ),
            // Floating input bar
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildFloatingInputBar(theme, isDark),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ThemeData theme, bool isDark) {
    return AppBar(
      backgroundColor: isDark ? const Color(0xFF131525) : Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, size: 22),
        onPressed: widget.onBack,
      ),
      titleSpacing: 0,
      title: Text(
        'TalentLOQ Agent',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: isDark ? Colors.white : const Color(0xFF0F172A),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          icon: const Icon(Icons.history_rounded, size: 18),
          label: const Text(
            'History',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          style: TextButton.styleFrom(
            foregroundColor: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildChatHistorySidebar(ThemeData theme, bool isDark) {
    final width = MediaQuery.of(context).size.width * 0.82;
    final clampedWidth = width.clamp(280.0, 360.0);
    final sessions = _aiSessions ?? const <Map<String, dynamic>>[];
    final activeId = _activeSessionId ?? 'recruiter_ai_bot';
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
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.history_rounded, size: 18, color: Color(0xFF8B5CF6)),
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
                  backgroundColor: const Color(0xFF8B5CF6),
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
                                  color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
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
                                (activeId == 'recruiter_ai_bot' && index == 0 && sessions.length == 1);

                            return InkWell(
                              onTap: () => _selectSession(sid),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? (isDark
                                          ? const Color(0xFF8B5CF6).withValues(alpha: 0.18)
                                          : const Color(0xFF8B5CF6).withValues(alpha: 0.1))
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                  border: isActive
                                      ? Border.all(
                                          color: const Color(0xFF8B5CF6).withValues(alpha: 0.4),
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
                                                        ? (isDark ? Colors.white : const Color(0xFF7C3AED))
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

  Widget _buildLoadingState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildCentralOrb(isDark, size: 90),
          const SizedBox(height: 20),
          Text(
            'Connecting to Campus Candidate Knowledge Graph...',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyWelcomeState(ThemeData theme, bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildCentralOrb(isDark, size: 100),
          const SizedBox(height: 28),
          Text(
            'What can I help with?',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }

  /// Glowing Animated Intelligence Orb inspired by modern SaaS aesthetic
  Widget _buildCentralOrb(bool isDark, {double size = 130}) {
    return AnimatedBuilder(
      animation: Listenable.merge([_orbPulseController, _orbRotateController]),
      builder: (context, child) {
        final pulse = _orbPulseController.value;
        final rotation = _orbRotateController.value * 2 * 3.1415926535;

        return Stack(
          alignment: Alignment.center,
          children: [
            // Outermost soft ambient glow
            Container(
              width: size * (1.35 + pulse * 0.15),
              height: size * (1.35 + pulse * 0.15),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFEC4899).withValues(alpha: isDark ? 0.22 : 0.14),
                    const Color(0xFF8B5CF6).withValues(alpha: isDark ? 0.12 : 0.08),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
            // Breathing aura ring
            Container(
              width: size * (1.1 + pulse * 0.08),
              height: size * (1.1 + pulse * 0.08),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFEC4899).withValues(alpha: 0.25 + pulse * 0.2),
                  width: 1.5,
                ),
              ),
            ),
            // Main glowing orb with gradient
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFFFCE7F3).withValues(alpha: isDark ? 0.8 : 0.95),
                    const Color(0xFFF3E8FF).withValues(alpha: isDark ? 0.7 : 0.9),
                    const Color(0xFFDDD6FE).withValues(alpha: isDark ? 0.6 : 0.85),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFEC4899).withValues(alpha: isDark ? 0.4 : 0.3),
                    blurRadius: 28,
                    spreadRadius: 2,
                  ),
                  BoxShadow(
                    color: const Color(0xFF8B5CF6).withValues(alpha: isDark ? 0.35 : 0.25),
                    blurRadius: 36,
                    spreadRadius: -4,
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Rotating abstract neural core shape
                  Transform.rotate(
                    angle: rotation,
                    child: Container(
                      width: size * 0.55,
                      height: size * 0.55,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF2E93), Color(0xFF8B5CF6), Color(0xFF38BDF8)],
                        ),
                        borderRadius: BorderRadius.circular(size * 0.22),
                      ),
                    ),
                  ),
                  // Inner core spark
                  Container(
                    width: size * 0.26,
                    height: size * 0.26,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.9),
                          blurRadius: 16,
                          spreadRadius: 3,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildChatList(ThemeData theme, bool isDark) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      itemCount: _messages.length + (_isSending ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length && _isSending) {
          return _buildTypingIndicator(isDark);
        }
        final msg = _messages[index];
        return _buildMessageBubble(msg, isDark);
      },
    );
  }

  Widget _buildTypingIndicator(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)],
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.psychology_rounded, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF16192B) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? const Color(0xFF272C4C) : const Color(0xFFE2E8F0),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Thinking...',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF8B5CF6)),
                ),
                const SizedBox(width: 8),
                _buildAnimatedDots(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedDots() {
    return AnimatedBuilder(
      animation: _dotsController,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final delay = index * 0.3;
            final progress = (_dotsController.value - delay) % 1.0;
            final scale = 0.5 + 0.5 * (1.0 - (progress - 0.5).abs() * 2).clamp(0.0, 1.0);

            return Transform.scale(
              scale: scale,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                  color: Color(0xFFEC4899),
                  shape: BoxShape.circle,
                ),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildMessageBubble(ChatMessage msg, bool isDark) {
    final rawText = msg.text;

    // Extract embedded candidate cards JSON if present
    List<Map<String, dynamic>> candidateCards = [];
    String displayText = rawText;
    final cardMatch = RegExp(r'<!-- CANDIDATE_CARDS:(.*?) -->').firstMatch(rawText);
    if (cardMatch != null) {
      final jsonStr = cardMatch.group(1);
      displayText = rawText.replaceAll(cardMatch.group(0)!, '').trim();
      if (jsonStr != null && jsonStr.isNotEmpty) {
        try {
          final parsed = jsonDecode(jsonStr);
          if (parsed is List) {
            candidateCards = parsed.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          }
        } catch (_) {}
      }
    }

    if (msg.isMe) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(left: 48, bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(4),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                displayText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                formatChatTimestamp(msg.time),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // AI Message Bubble
    final isNewMessage = !_animatedMessageIds.contains(msg.id);

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(right: 24, bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // AI Header Badge
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(Icons.psychology_rounded, size: 13, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Talent Scout',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                  ),
                ),
                
                const Spacer(),
                IconButton(
                  icon: Icon(
                    Icons.copy_rounded,
                    size: 14,
                    color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                  ),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: displayText));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Copied to clipboard'),
                        duration: Duration(seconds: 1),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Message Container (Long press on AI bubble to delete chat)
            GestureDetector(
              onLongPress: _showClearChatDialog,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF151829) : Colors.white,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(20),
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  ),
                  border: Border.all(
                    color: isDark ? const Color(0xFF262B48) : const Color(0xFFE2E8F0),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    isNewMessage
                        ? RecruiterWordStreamText(
                            fullText: displayText,
                            style: TextStyle(
                              fontSize: 13.8,
                              height: 1.5,
                              color: isDark ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
                            ),
                            onWordEmitted: () => _scrollToBottom(animated: false),
                            onComplete: () {
                              if (mounted) {
                                setState(() => _animatedMessageIds.add(msg.id));
                              }
                            },
                          )
                        : Text(
                            displayText,
                            style: TextStyle(
                              fontSize: 13.8,
                              height: 1.5,
                              color: isDark ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
                            ),
                          ),
                    if (candidateCards.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _buildCandidateCardsList(candidateCards, isDark),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      formatChatTimestamp(msg.time),
                      style: TextStyle(
                        fontSize: 10,
                        color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCandidateCardsList(List<Map<String, dynamic>> cards, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF8B5CF6).withValues(alpha: isDark ? 0.2 : 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.verified_user_rounded, size: 13, color: Color(0xFF8B5CF6)),
              SizedBox(width: 5),
              Text(
                'RETRIEVED CANDIDATE DOSSIERS (HYBRID OKF + RAG)',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: Color(0xFF8B5CF6),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ...cards.map((cand) => _buildSingleCandidateCard(cand, isDark)),
      ],
    );
  }

  Widget _buildSingleCandidateCard(Map<String, dynamic> cand, bool isDark) {
    final candId = (cand['student_id'] ?? '').toString();
    final name = (cand['full_name'] ?? 'Candidate').toString();
    final cgpa = ((cand['cgpa'] ?? 0.0) as num).toDouble();
    final branch = (cand['branch'] ?? 'Computer Science & Engineering').toString();
    final matchScore = ((cand['match_score'] ?? 75) as num).toInt();
    final matchTitle = (cand['match_title'] ?? 'Role Match').toString();
    final internshipCount = ((cand['internship_count'] ?? 0) as num).toInt();
    final topSkills = (cand['top_skills'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final reasons = (cand['reasons'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final gaps = (cand['gaps'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final isShortlisted = _shortlistedCandidateIds.contains(candId);

    final initials = name.trim().split(' ').map((e) => e.isNotEmpty ? e[0].toUpperCase() : '').take(2).join('');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF101221) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF272C4C) : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Avatar + Name/Title + Match Score
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      matchTitle,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF8B5CF6),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0x1F10B981),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF10B981), width: 1),
                ),
                child: Text(
                  '$matchScore% Match',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF10B981),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Badges: CGPA, Branch, Internships
          Row(
            children: [
              _buildSmallBadge(
                Icons.star_rounded,
                '$cgpa CGPA',
                const Color(0xFFF59E0B),
                isDark,
              ),
              const SizedBox(width: 6),
              _buildSmallBadge(
                Icons.business_center_rounded,
                '$internshipCount Internships',
                const Color(0xFF8B5CF6),
                isDark,
              ),
              const SizedBox(width: 6),
              _buildSmallBadge(
                Icons.verified_rounded,
                'Verified',
                const Color(0xFF0EA5E9),
                isDark,
              ),
            ],
          ),
          if (topSkills.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: topSkills.take(6).map((s) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E2238) : const Color(0xFFEDE9FE),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  s,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isDark ? const Color(0xFFDDD6FE) : const Color(0xFF6D28D9),
                  ),
                ),
              )).toList(),
            ),
          ],
          // Explainable AI: Recommended Because & Potential Gaps
          if (reasons.isNotEmpty || gaps.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF171A2C) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (reasons.isNotEmpty) ...[
                    const Text(
                      'Recommended Because:',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF10B981),
                      ),
                    ),
                    const SizedBox(height: 3),
                    ...reasons.take(3).map((r) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        r,
                        style: TextStyle(
                          fontSize: 10,
                          color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                        ),
                      ),
                    )),
                  ],
                  if (gaps.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    const Text(
                      'Potential Gaps / Areas to Assess:',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFF59E0B),
                      ),
                    ),
                    const SizedBox(height: 3),
                    ...gaps.take(2).map((g) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        g,
                        style: TextStyle(
                          fontSize: 10,
                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                        ),
                      ),
                    )),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          // Action Buttons: View Profile, Compare, Shortlist, Ask AI
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    side: BorderSide(
                      color: isDark ? const Color(0xFF373A63) : const Color(0xFFCBD5E1),
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.person_outline_rounded, size: 14),
                  label: const Text('View Profile', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  onPressed: () {
                    final candObj = Candidate(
                      id: candId,
                      name: name,
                      roleTitle: topSkills.isNotEmpty ? topSkills.first : 'Engineering Candidate',
                      avatarUrl: '',
                      location: 'Vadodara, India',
                      experience: '$internshipCount Internships',
                      education: branch,
                      matchScore: matchScore.toDouble(),
                      skills: topSkills,
                      bio: 'Verified candidate from university live database.',
                      status: 'Profile Verified',
                      cgpa: cgpa,
                    );
                    widget.onSelectCandidate?.call(candObj);
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    side: const BorderSide(color: Color(0xFF8B5CF6)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.compare_arrows_rounded, size: 14, color: Color(0xFF8B5CF6)),
                  label: const Text('Compare', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF8B5CF6))),
                  onPressed: () => _sendMessage('Compare $name with the next highest matching candidate.'),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: isShortlisted ? 'Shortlisted' : 'Shortlist Candidate',
                icon: Icon(
                  isShortlisted ? Icons.star_rounded : Icons.star_border_rounded,
                  color: isShortlisted ? const Color(0xFFF59E0B) : (isDark ? Colors.white70 : const Color(0xFF64748B)),
                  size: 22,
                ),
                onPressed: () => _toggleShortlist(candId, name),
              ),
              IconButton(
                tooltip: 'Ask Questions',
                icon: const Icon(Icons.help_outline_rounded, color: Color(0xFFEC4899), size: 20),
                onPressed: () => _sendMessage('Suggest 3 high-impact technical interview questions for $name based on their experience.'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSmallBadge(IconData icon, String text, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3.5),
          Text(
            text,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingInputBar(ThemeData theme, bool isDark) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    return Container(
      margin: EdgeInsets.fromLTRB(16, 0, 16, bottomPad > 0 ? bottomPad + 4 : 12),
      padding: const EdgeInsets.fromLTRB(18, 4, 6, 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF16192E) : Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isDark ? const Color(0xFF282C4B) : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Input text area
          Expanded(
            child: TextField(
              controller: _inputController,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
              decoration: InputDecoration(
                hintText: 'Type here...',
                hintStyle: TextStyle(
                  fontSize: 13.5,
                  color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                filled: false,
                fillColor: Colors.transparent,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          // Send Button
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: _isSending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20),
              onPressed: _isSending ? null : () => _sendMessage(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Word-by-word streaming typewriter text widget with a glowing AI cursor
class RecruiterWordStreamText extends StatefulWidget {
  final String fullText;
  final TextStyle? style;
  final Duration wordDuration;
  final VoidCallback? onWordEmitted;
  final VoidCallback? onComplete;

  const RecruiterWordStreamText({
    super.key,
    required this.fullText,
    this.style,
    this.wordDuration = const Duration(milliseconds: 28),
    this.onWordEmitted,
    this.onComplete,
  });

  @override
  State<RecruiterWordStreamText> createState() => _RecruiterWordStreamTextState();
}

class _RecruiterWordStreamTextState extends State<RecruiterWordStreamText> {
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
        setState(() {
          _currentTokenIndex++;
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

  void _finishImmediately() {
    if (_isFinished) return;
    _timer?.cancel();
    setState(() {
      _isFinished = true;
      _currentTokenIndex = _tokens.length;
    });
    widget.onComplete?.call();
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

    final visibleText = _tokens.sublist(0, _currentTokenIndex).join('');

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _finishImmediately,
      child: RichText(
        text: TextSpan(
          style: widget.style,
          children: [
            TextSpan(text: visibleText),
            TextSpan(
              text: ' ▋',
              style: TextStyle(
                color: const Color(0xFF8B5CF6),
                fontWeight: FontWeight.bold,
                fontSize: (widget.style?.fontSize ?? 13.5) * 0.95,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
