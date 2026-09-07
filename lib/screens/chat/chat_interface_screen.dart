import 'package:flutter/material.dart';
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
  final TokenStorageService _tokenStorage = TokenStorageService();
  final ChatService _chatService = ChatService();
  String _myName = 'Me';

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

    // Fetch backend messages
    if (widget.conversation.id.isNotEmpty) {
      final backendMsgs = await _chatService.getMessages(widget.conversation.id);
      if (mounted && backendMsgs.isNotEmpty) {
        setState(() {
          _messages = backendMsgs;
        });
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

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
    });
    _inputController.clear();

    // Send to backend
    await _chatService.sendMessage(
      recipientId: widget.conversation.id,
      text: text,
      conversationId: widget.conversation.id,
      recipientName: widget.conversation.partnerName,
    );
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: widget.onBack,
        ),
        title: Row(
          children: [
            AppAvatar(
              radius: 18,
              imageUrl: widget.conversation.avatarUrl,
              fallbackText: widget.conversation.partnerName,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.conversation.partnerName,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Text(
                    'Online',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.success,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Text(
                      'No messages yet. Say hello!',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.hintColor,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      return _buildMessageBubble(msg, isDark);
                    },
                  ),
          ),
          _buildInputBar(theme, isDark),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg, bool isDark) {
    return Align(
      alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: msg.isMe
              ? (isDark ? AppColors.darkPrimary : AppColors.lightPrimary)
              : (isDark ? AppColors.darkSurfaceContainer : AppColors.lightSurfaceContainer),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(msg.isMe ? 16 : 4),
            bottomRight: Radius.circular(msg.isMe ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: msg.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              msg.text,
              style: TextStyle(
                color: msg.isMe
                    ? Colors.white
                    : (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              msg.time,
              style: TextStyle(
                color: msg.isMe
                    ? Colors.white70
                    : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputController,
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: isDark
                      ? AppColors.darkSurfaceContainer
                      : AppColors.lightSurfaceContainer,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.send_rounded),
              color: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
              onPressed: _sendMessage,
            ),
          ],
        ),
      ),
    );
  }
}
