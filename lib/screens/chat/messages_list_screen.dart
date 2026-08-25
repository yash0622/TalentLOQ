import 'package:flutter/material.dart';
import '../../mock_data/mock_data.dart';
import '../../models/models.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_avatar.dart';
import '../../services/drive_service.dart';
import '../../services/auth_service.dart';

class MessagesListScreen extends StatefulWidget {
  final Function(Conversation) onSelectConversation;

  const MessagesListScreen({super.key, required this.onSelectConversation});

  @override
  State<MessagesListScreen> createState() => _MessagesListScreenState();
}

class _MessagesListScreenState extends State<MessagesListScreen> {
  String _searchQuery = '';
  final DriveService _driveService = DriveService();
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _fetchBackendNotifications();
  }

  Future<void> _fetchBackendNotifications() async {
    final data = await _authService.getUserNotifications();
    final notifs = (data['notifications'] as List?) ?? [];
    final chats = (data['messages'] as List?) ?? [];

    // Also fetch active published drives to populate company recruiter channels
    List<dynamic> activeDrives = [];
    try {
      activeDrives = await _driveService.getPublishedDrives();
    } catch (_) {}

    if (!mounted) return;

    setState(() {
      // 1. Process backend notifications & direct messages
      for (var item in [...notifs, ...chats]) {
        if (item is! Map) continue;
        final title = (item['title'] ?? item['sender_name'] ?? 'Placement Officer').toString();
        final body = (item['body'] ?? item['text'] ?? '').toString();
        final id = (item['notification_id'] ?? item['message_id'] ?? 'notif-${DateTime.now().millisecondsSinceEpoch}').toString();

        if (body.isEmpty) continue;

        final convIndex = MockData.conversations.indexWhere(
          (c) => c.id == id || c.partnerName.toLowerCase().contains(title.toLowerCase()),
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
          MockData.conversations.insert(0, conv);
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

      // 2. Auto-populate active placement drive recruiters so chat list is never empty
      for (var drive in activeDrives) {
        if (drive is! Map) continue;
        final companyName = (drive['company_name'] ?? 'Placement Cell').toString();
        final role = (drive['interview_job'] ?? drive['drive_title'] ?? 'Recruiter').toString();
        final driveId = (drive['drive_id'] ?? drive['listing_id'] ?? '').toString();

        final exists = MockData.conversations.any(
          (c) => c.partnerName.toLowerCase().contains(companyName.toLowerCase()),
        );

        if (!exists) {
          final conv = Conversation(
            id: driveId.isNotEmpty ? driveId : 'conv-${DateTime.now().millisecondsSinceEpoch}',
            partnerName: '$companyName Recruiter',
            partnerRole: '$role • Campus Placement',
            avatarUrl: '',
            lastMessage: 'Tap to chat with $companyName recruiter regarding drive updates & interview rounds.',
            time: 'Active',
            unreadCount: 0,
            isOnline: true,
          );
          MockData.conversations.add(conv);

          MockData.conversationMessages.putIfAbsent(conv.id, () => []).add(
            ChatMessage(
              id: 'init-${conv.id}',
              senderId: 'recruiter',
              senderName: '$companyName Recruiter',
              text: 'Welcome! Feel free to ask any questions regarding $companyName recruitment drive.',
              time: 'Today',
              isMe: false,
            ),
          );
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final filteredConversations = MockData.conversations.where((conv) {
      return conv.partnerName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          conv.partnerRole.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          conv.lastMessage.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startNewConversation,
        icon: const Icon(Icons.edit_note_rounded),
        label: const Text('New Chat'),
        backgroundColor: isDark ? AppColors.darkPrimaryContainer : AppColors.lightPrimary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Search Header Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
              border: Border(
                bottom: BorderSide(
                  color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                ),
              ),
            ),
            child: TextField(
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: 'Search messages and contacts...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () => setState(() => _searchQuery = ''),
                      )
                    : null,
              ),
            ),
          ),

          // Conversations List
          Expanded(
            child: filteredConversations.isNotEmpty
                ? ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: filteredConversations.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      indent: 72,
                      color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                    ),
                    itemBuilder: (context, index) {
                      final conv = filteredConversations[index];
                      return ListTile(
                        onTap: () {
                          setState(() {
                            conv.unreadCount = 0;
                          });
                          widget.onSelectConversation(conv);
                        },
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        leading: Stack(
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
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                conv.partnerName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: conv.unreadCount > 0 ? FontWeight.bold : FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            Text(
                              conv.time,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: conv.unreadCount > 0 ? AppColors.lightPrimary : null,
                                fontWeight: conv.unreadCount > 0 ? FontWeight.bold : null,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 2),
                            Text(
                              conv.partnerRole,
                              style: theme.textTheme.bodySmall?.copyWith(fontSize: 11, color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
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
                        trailing: conv.unreadCount > 0
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: const BoxDecoration(
                                  color: AppColors.lightPrimary,
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  '${conv.unreadCount}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              )
                            : null,
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
