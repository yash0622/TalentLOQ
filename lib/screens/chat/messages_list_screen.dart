import 'package:flutter/material.dart';
import '../../mock_data/mock_data.dart';
import '../../models/models.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_avatar.dart';
import '../../services/drive_service.dart';
import '../../services/auth_service.dart';
import '../../services/chat_service.dart';
import '../../utils/chat_date_util.dart';

class MessagesListScreen extends StatefulWidget {
  final Function(Conversation) onSelectConversation;
  final bool isRecruiter;

  const MessagesListScreen({
    super.key,
    required this.onSelectConversation,
    this.isRecruiter = false,
  });

  @override
  State<MessagesListScreen> createState() => _MessagesListScreenState();
}

class _MessagesListScreenState extends State<MessagesListScreen> {
  String _searchQuery = '';
  final DriveService _driveService = DriveService();
  final AuthService _authService = AuthService();
  final ChatService _chatService = ChatService();

  @override
  void initState() {
    super.initState();
    _fetchBackendNotifications();
  }

  Future<void> _fetchBackendNotifications() async {
    final data = await _authService.getUserNotifications();
    final notifs = (data['notifications'] as List?) ?? [];
    final chats = (data['messages'] as List?) ?? [];

    if (!mounted) return;

    setState(() {
      // Clean up conversations to prevent cross-role bot leakage
      MockData.conversations.removeWhere((c) =>
          c.partnerName.contains('UCI Placement') ||
          c.lastMessage.contains('UCI Placement'));

      // Ensure appropriate AI Bot is permanently available at the top
      final botId = widget.isRecruiter ? 'recruiter_ai_bot' : 'ai_bot';
      final botTitle = widget.isRecruiter ? 'TalentLOQ Assistant' : 'TalentLOQ Assistant';
      final botRole = widget.isRecruiter ? 'Recruitment Assistant' : 'Autonomous Placement Copilot';
      final botMsg = widget.isRecruiter
          ? 'Ask me anything about candidates.'
          : 'Tell me your target domains, skills, and salary in plain English!';

      // Aggressively remove ANY existing AI bots (both recruiter & student bots, duplicates, variants)
      MockData.conversations.removeWhere((c) {
        final name = c.partnerName.toLowerCase();
        final role = c.partnerRole.toLowerCase();
        final id = c.id.toLowerCase();
        return id == 'ai_bot' ||
            id == 'recruiter_ai_bot' ||
            id.endsWith('_ai_bot') ||
            name.contains('ai bot') ||
            name.contains('talent scout') ||
            name.contains('recruiter ai') ||
            name.contains('talentloq ai') ||
            name.contains('talentloq assistant') ||
            name.contains('placement bot') ||
            name.contains('placement copilot') ||
            role.contains('recruitment assistant') ||
            role.contains('placement assistant');
      });

      MockData.conversationMessages.putIfAbsent(botId, () => [
        ChatMessage(
          id: 'welcome_$botId',
          senderId: botId,
          senderName: botTitle,
          text: widget.isRecruiter
              ? 'Hello! I am your Recruitment Assistant. Ask me anything about candidates in natural English!'
              : 'Hello! I am your Placement Assistant.\n\nTell me what opportunities you want me to monitor and apply for in natural English.\n\nExample:\n"Apply for upcoming companies that match my profile with a salary of 3–4 LPA."',
          time: 'Always Active',
          isMe: false,
        ),
      ]);

      // Insert ONLY the single active available AI bot at index 0
      MockData.conversations.insert(
        0,
        Conversation(
          id: botId,
          partnerName: botTitle,
          partnerRole: botRole,
          avatarUrl: '',
          lastMessage: botMsg,
          time: 'Always Active',
          unreadCount: 0,
          isOnline: true,
        ),
      );

      // 1. Process backend notifications & direct messages (excluding any AI bot duplicates)
      for (var item in [...notifs, ...chats]) {
        if (item is! Map) continue;
        final title = (item['title'] ?? item['sender_name'] ?? 'Placement Officer').toString();
        final body = (item['body'] ?? item['text'] ?? '').toString();
        final id = (item['notification_id'] ?? item['message_id'] ?? 'notif-${DateTime.now().millisecondsSinceEpoch}').toString();

        if (body.isEmpty) continue;
        if (title.contains('UCI Placement') || body.contains('UCI Placement')) continue;

        final titleLower = title.toLowerCase();
        final idLower = id.toLowerCase();
        // If this notification/message is from or for an AI assistant, update the single active bot — NEVER create a new conversation tile!
        final isAiMessage = idLower.contains('ai_bot') ||
            idLower.contains('recruiter_ai') ||
            titleLower.contains('ai bot') ||
            titleLower.contains('talent scout') ||
            titleLower.contains('recruiter ai') ||
            titleLower.contains('talentloq ai') ||
            titleLower.contains('placement bot') ||
            titleLower.contains('copilot');

        if (isAiMessage) {
          final botConv = MockData.conversations.firstWhere(
            (c) => c.id == botId,
            orElse: () => MockData.conversations.first,
          );
          if (botConv.id == botId && body.isNotEmpty) {
            botConv.lastMessage = body;
            botConv.time = 'Just Now';
          }
          continue; // DO NOT create an additional conversation
        }

        final convIndex = MockData.conversations.indexWhere(
          (c) => c.id == id ||
                 c.partnerName.toLowerCase() == title.toLowerCase() ||
                 (c.lastMessage.isNotEmpty && c.lastMessage == body),
        );

        if (convIndex != -1) {
          final conv = MockData.conversations[convIndex];
          conv.lastMessage = body;
          conv.time = 'Just Now';
        } else {
          final conv = Conversation(
            id: id,
            partnerName: title,
            partnerRole: 'Recruiter & Placement Cell',
            avatarUrl: '',
            lastMessage: body,
            time: 'Just Now',
            unreadCount: 1,
            isOnline: true,
          );
          MockData.conversations.add(conv);
        }

        final chatMsgList = MockData.conversationMessages.putIfAbsent(id, () => []);
        if (chatMsgList.every((m) => m.text != body)) {
          chatMsgList.add(ChatMessage(
            id: id,
            senderId: 'recruiter',
            senderName: title,
            text: body,
            time: 'Just Now',
            isMe: false,
          ));
        }
      }
    });
  }

  Future<void> _startNewConversation() async {
    List<dynamic> realDrives = [];
    bool isLoading = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final theme = Theme.of(context);
            final isDark = theme.brightness == Brightness.dark;

            if (isLoading) {
              _driveService.getPublishedDrives().then((drives) {
                if (bottomSheetCtx.mounted) {
                  setModalState(() {
                    realDrives = drives;
                    isLoading = false;
                  });
                }
              });
            }

            return Container(
              height: MediaQuery.of(context).size.height * 0.70,
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          'Select Recruiter / Company to Chat',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () => Navigator.pop(bottomSheetCtx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(bottomSheetCtx);
                      _showManualNewChatDialog();
                    },
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Enter Custom Contact Name'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(42),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Active Companies & Placement Drives',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.lightPrimary),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : realDrives.isNotEmpty
                            ? ListView.separated(
                                padding: const EdgeInsets.only(bottom: 120),
                                itemCount: realDrives.length,
                                separatorBuilder: (_, _) => const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final drive = realDrives[index];
                                  final compName = (drive['company_name'] ?? drive['company'] ?? 'Company Recruiter').toString();
                                  final driveTitle = (drive['drive_title'] ?? drive['title'] ?? 'Placement Drive').toString();
                                  final role = '$driveTitle • Hiring Team';

                                  return ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: AppColors.primaryLightBg,
                                      child: Text(
                                        compName.isNotEmpty ? compName[0].toUpperCase() : 'C',
                                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.lightPrimary),
                                      ),
                                    ),
                                    title: Text(compName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                    subtitle: Text(driveTitle, style: const TextStyle(fontSize: 12, color: AppColors.lightTextSecondary)),
                                    trailing: const Icon(Icons.chat_bubble_outline_rounded, size: 18, color: AppColors.lightPrimary),
                                    onTap: () {
                                      Navigator.pop(bottomSheetCtx);
                                      _createAndOpenConversation(compName, role);
                                    },
                                  );
                                },
                              )
                            : Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.business_center_outlined, size: 40, color: AppColors.lightTextSecondary),
                                      const SizedBox(height: 8),
                                      const Text('No active company drives found in DB.'),
                                      const SizedBox(height: 12),
                                      ElevatedButton(
                                        onPressed: () {
                                          Navigator.pop(bottomSheetCtx);
                                          _showManualNewChatDialog();
                                        },
                                        child: const Text('Start Custom Chat'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showManualNewChatDialog() {
    final nameController = TextEditingController();
    final roleController = TextEditingController(text: 'Hiring Representative');

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Start New Conversation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Recipient Name',
                hintText: 'e.g. Amazon University Hiring or Student Name',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: roleController,
              decoration: const InputDecoration(
                labelText: 'Role / Designation',
                hintText: 'e.g. Technical Recruiter',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              final role = roleController.text.trim();
              Navigator.pop(dialogCtx);
              _createAndOpenConversation(name, role.isNotEmpty ? role : 'Contact');
            },
            child: const Text('Start Chat'),
          ),
        ],
      ),
    );
  }

  void _createAndOpenConversation(String name, String role) {
    Conversation? existing;
    try {
      existing = MockData.conversations.firstWhere(
        (c) => c.partnerName.toLowerCase() == name.toLowerCase(),
      );
    } catch (_) {}

    if (existing != null) {
      widget.onSelectConversation(existing);
    } else {
      final newConv = Conversation(
        id: 'conv-${DateTime.now().millisecondsSinceEpoch}',
        partnerName: name,
        partnerRole: role,
        avatarUrl: '',
        lastMessage: 'Conversation started.',
        time: 'Just now',
        unreadCount: 0,
        isOnline: true,
      );

      setState(() {
        MockData.conversations.insert(0, newConv);
      });

      widget.onSelectConversation(newConv);
    }
  }

  Future<void> _showClearAiChatDialog(Conversation conv) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? AppColors.darkSurfaceContainer : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Delete Chat History',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: const Text(
            'Are you sure you want to delete all messages with the TalentLOQ Assistant? This action cannot be undone.',
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete All'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      final defaultMsg = widget.isRecruiter
          ? 'Ask me anything about candidates.'
          : 'Tell me your target domains, skills, and salary in plain English!';

      await _chatService.clearConversation(conv.id);

      setState(() {
        conv.lastMessage = defaultMsg;
        conv.time = 'Always Active';
        conv.unreadCount = 0;
        MockData.conversationMessages[conv.id] = [];
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('TalentLOQ Assistant history deleted'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final targetBotId = widget.isRecruiter ? 'recruiter_ai_bot' : 'ai_bot';

    final rawMatches = MockData.conversations.where((conv) {
      return conv.partnerName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          conv.partnerRole.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          conv.lastMessage.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    // Ensure ONLY the single available AI bot is displayed in the list
    final filteredConversations = <Conversation>[];
    bool hasAddedAi = false;

    for (final conv in rawMatches) {
      final name = conv.partnerName.toLowerCase();
      final role = conv.partnerRole.toLowerCase();
      final id = conv.id.toLowerCase();
      final isAnyAi = id == 'ai_bot' ||
          id == 'recruiter_ai_bot' ||
          id.endsWith('_ai_bot') ||
          name.contains('ai bot') ||
          name.contains('talent scout') ||
          name.contains('recruiter ai') ||
          name.contains('talentloq ai') ||
          name.contains('placement bot') ||
          role.contains('recruitment assistant') ||
          role.contains('placement assistant');

      if (isAnyAi) {
        if (!hasAddedAi && conv.id == targetBotId) {
          filteredConversations.add(conv);
          hasAddedAi = true;
        }
      } else {
        filteredConversations.add(conv);
      }
    }

    return Scaffold(
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
              border: Border(
                bottom: BorderSide(
                  color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (val) => setState(() => _searchQuery = val),
                    decoration: InputDecoration(
                      hintText: 'Search messages and contacts...',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () => setState(() => _searchQuery = ''),
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  height: 46,
                  width: 46,
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: (isDark ? AppColors.darkPrimary : AppColors.lightPrimary).withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: IconButton(
                    tooltip: 'New Chat',
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.edit_note_rounded, color: Colors.white, size: 24),
                    onPressed: _startNewConversation,
                  ),
                ),
              ],
            ),
          ),

          // Conversations List
          Expanded(
            child: filteredConversations.isNotEmpty
                ? ListView.separated(
                    padding: const EdgeInsets.only(top: 8, bottom: 120),
                    itemCount: filteredConversations.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      indent: 72,
                      color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                    ),
                    itemBuilder: (context, index) {
                      final conv = filteredConversations[index];
                      final isRecruiterAi = conv.id == 'recruiter_ai_bot' ||
                          conv.partnerName.toLowerCase().contains('recruiter ai') ||
                          conv.partnerName.toLowerCase().contains('talent scout');
                      final isStudentAi = conv.id == 'ai_bot' ||
                          conv.partnerName.toLowerCase().contains('placement bot');
                      final isAiBot = isRecruiterAi || isStudentAi;

                      return ListTile(
                        onTap: () {
                          setState(() {
                            conv.unreadCount = 0;
                          });
                          widget.onSelectConversation(conv);
                        },
                        onLongPress: isAiBot ? () => _showClearAiChatDialog(conv) : null,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        leading: isRecruiterAi
                            ? Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF8B5CF6), Color(0xFFEC4899), Color(0xFFF59E0B)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.35),
                                      blurRadius: 10,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: const Icon(Icons.psychology_rounded, color: Colors.white, size: 24),
                              )
                            : isStudentAi
                                ? Container(
                                    width: 48,
                                    height: 48,
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
                                    child: const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 24),
                                  )
                                : Stack(
                                    children: [
                                      AppAvatar(
                                        radius: 24,
                                        imageUrl: conv.avatarUrl,
                                        fallbackText: conv.partnerName,
                                      ),
                                      if (conv.isOnline)
                                        Positioned(
                                          right: 0,
                                          bottom: 0,
                                          child: Container(
                                            width: 12,
                                            height: 12,
                                            decoration: BoxDecoration(
                                              color: AppColors.success,
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: isDark ? AppColors.darkSurface : Colors.white,
                                                width: 2,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                conv.partnerName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: conv.unreadCount > 0 || isAiBot ? FontWeight.bold : FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            if (isStudentAi) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.lightPrimary.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'AUTONOMOUS',
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.lightPrimary,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 2),
                            Text(
                              conv.partnerRole,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 11,
                                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              conv.lastMessage,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: conv.unreadCount > 0
                                    ? (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary)
                                    : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                                fontWeight: conv.unreadCount > 0 ? FontWeight.w600 : FontWeight.normal,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        trailing: SizedBox(
                          width: 72,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                formatConversationTime(conv.time),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.end,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: conv.unreadCount > 0
                                      ? (isDark ? AppColors.darkPrimary : AppColors.lightPrimary)
                                      : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                                  fontWeight: conv.unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 4),
                              if (conv.unreadCount > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                                  decoration: BoxDecoration(
                                    color: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    '${conv.unreadCount}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                )
                              else
                                const SizedBox(height: 18),
                            ],
                          ),
                        ),
                      );
                    },
                  )
                : Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_bubble_outline_rounded, size: 56, color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                          const SizedBox(height: 16),
                          Text(
                            _searchQuery.isEmpty ? 'No conversations yet' : 'No matching messages found',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _searchQuery.isEmpty
                                ? 'Tap "New Chat" below to select an active company or recruiter.'
                                : 'Try searching for another name or keyword.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary, fontSize: 12),
                          ),
                          if (_searchQuery.isEmpty) ...[
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _startNewConversation,
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: const Text('Start First Chat'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
