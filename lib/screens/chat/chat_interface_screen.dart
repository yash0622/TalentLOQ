import 'package:flutter/material.dart';
import '../../mock_data/mock_data.dart';
import '../../models/models.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_avatar.dart';

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
  String _myName = 'Me';

  @override
  void initState() {
    super.initState();
    _messages = MockData.conversationMessages[widget.conversation.id] ?? [];
    _loadMyName();
  }

  Future<void> _loadMyName() async {
    final profile = await _tokenStorage.getStudentProfile();
    final name = profile['full_name'] as String? ?? '';
    if (mounted && name.isNotEmpty) {
      setState(() {
        _myName = name;
      });
    }
  }

  void _sendMessage() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    final newMsg = ChatMessage(
      id: 'msg-${DateTime.now().millisecondsSinceEpoch}',
      senderId: 'me',
      senderName: _myName,
      text: text,
      time: 'Just now',
      isMe: true,
    );

    setState(() {
      _messages.add(newMsg);
      MockData.conversationMessages[widget.conversation.id] = _messages;
      widget.conversation.lastMessage = text;
      widget.conversation.time = 'Just now';
    });
    _inputController.clear();
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
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.conversation.partnerName,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    widget.conversation.partnerRole,
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Chat Messages Body
          Expanded(
            child: _messages.isNotEmpty
                ? ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      return _buildMessageBubble(msg, theme, isDark);
                    },
                  )
                : Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.forum_outlined, size: 48, color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                          const SizedBox(height: 12),
                          Text(
                            'Conversation Started',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Send a message below to start chatting with ${widget.conversation.partnerName}.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),

          // Quick Suggestions
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                _buildQuickReply('Hello! Could we connect?'),
                const SizedBox(width: 8),
                _buildQuickReply('Thank you for reaching out!'),
                const SizedBox(width: 8),
                _buildQuickReply('When is a good time to talk?'),
              ],
            ),
          ),

          // Message Input Field
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
              border: Border(
                top: BorderSide(
                  color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                ),
              ),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sendMessage,
                    style: IconButton.styleFrom(
                      backgroundColor: isDark
                          ? AppColors.darkPrimaryContainer
                          : AppColors.lightPrimary,
                    ),
                    icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg, ThemeData theme, bool isDark) {
    return Align(
      alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: const BoxConstraints(maxWidth: 300),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: msg.isMe
              ? (isDark ? AppColors.darkPrimaryContainer : AppColors.lightPrimary)
              : (isDark ? AppColors.darkSurfaceContainerLow : AppColors.lightSurfaceContainer),
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
                height: 1.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              msg.time,
              style: TextStyle(
                color: msg.isMe ? Colors.white70 : theme.textTheme.bodySmall?.color,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickReply(String text) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ActionChip(
      label: Text(text),
      onPressed: () {
        _inputController.text = text;
      },
      backgroundColor: isDark ? AppColors.darkSurfaceContainerLow : AppColors.lightSurfaceContainerLow,
      labelStyle: TextStyle(
        fontSize: 12,
        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
      ),
    );
  }
}
