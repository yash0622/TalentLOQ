import 'package:flutter/material.dart';
import '../../services/notification_inbox_service.dart';
import '../../services/notification_service.dart';
import '../../theme/app_colors.dart';

class NotificationInboxScreen extends StatefulWidget {
  const NotificationInboxScreen({super.key});

  @override
  State<NotificationInboxScreen> createState() => _NotificationInboxScreenState();
}

class _NotificationInboxScreenState extends State<NotificationInboxScreen> {
  final NotificationInboxService _inboxService = NotificationInboxService.instance;
  final ScrollController _scrollController = ScrollController();

  List<NotificationInboxItem> _items = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  String? _nextCursor;

  @override
  void initState() {
    super.initState();
    _fetchInitial();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMore) {
      _fetchMore();
    }
  }

  Future<void> _fetchInitial() async {
    setState(() {
      _isLoading = true;
    });

    final res = await _inboxService.getNotifications(limit: 20);

    if (mounted) {
      setState(() {
        _items = res.items;
        _nextCursor = res.nextCursor;
        _hasMore = res.hasMore;
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchMore() async {
    if (_nextCursor == null || _isLoadingMore) return;

    setState(() {
      _isLoadingMore = true;
    });

    final res = await _inboxService.getNotifications(cursor: _nextCursor, limit: 20);

    if (mounted) {
      setState(() {
        _items.addAll(res.items);
        _nextCursor = res.nextCursor;
        _hasMore = res.hasMore;
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _markAllRead() async {
    final success = await _inboxService.markAllAsRead();
    if (success && mounted) {
      setState(() {
        _items = _items.map((item) => item.copyWith(read: true)).toList();
      });
    }
  }

  Future<void> _onItemTapped(NotificationInboxItem item) async {
    if (!item.read) {
      await _inboxService.markAsRead(item.id);
      if (mounted) {
        setState(() {
          final idx = _items.indexWhere((i) => i.id == item.id);
          if (idx != -1) {
            _items[idx] = _items[idx].copyWith(read: true);
          }
        });
      }
    }

    // Trigger deep-linking if item has data payload
    NotificationService.instance.handleDeepLink(item.data);
  }

  IconData _getTypeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'drive_published':
      case 'company_published':
        return Icons.business_center_rounded;
      case 'deadline_reminder':
        return Icons.timer_outlined;
      case 'round_outcome':
      case 'applicant_shortlisted':
        return Icons.how_to_reg_rounded;
      case 'offer':
      case 'offer_recorded':
        return Icons.verified_rounded;
      case 'chat_message':
        return Icons.chat_bubble_outline_rounded;
      case 'document_status':
        return Icons.description_outlined;
      default:
        return Icons.notifications_none_rounded;
    }
  }

  Color _getTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'offer':
      case 'offer_recorded':
        return Colors.green;
      case 'round_outcome':
      case 'applicant_shortlisted':
        return AppColors.lightPrimary;
      case 'deadline_reminder':
        return Colors.amber.shade800;
      case 'chat_message':
        return Colors.purple;
      default:
        return AppColors.lightPrimary;
    }
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasUnread = _items.any((i) => !i.read);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          if (hasUnread)
            TextButton.icon(
              onPressed: _markAllRead,
              icon: const Icon(Icons.done_all_rounded, size: 18),
              label: const Text('Mark all read', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.notifications_off_outlined, size: 64, color: theme.disabledColor),
                      const SizedBox(height: 16),
                      Text(
                        'No notifications yet',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Updates about placement drives and rounds will appear here.',
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchInitial,
                  child: ListView.separated(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _items.length + (_isLoadingMore ? 1 : 0),
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      if (index == _items.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }

                      final item = _items[index];
                      final icon = _getTypeIcon(item.type);
                      final color = _getTypeColor(item.type);

                      return ListTile(
                        onTap: () => _onItemTapped(item),
                        tileColor: item.read ? null : theme.colorScheme.primary.withValues(alpha: 0.04),
                        leading: CircleAvatar(
                          backgroundColor: color.withValues(alpha: 0.12),
                          foregroundColor: color,
                          radius: 20,
                          child: Icon(icon, size: 20),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.title,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: item.read ? FontWeight.w500 : FontWeight.bold,
                                ),
                              ),
                            ),
                            Text(
                              _formatTime(item.createdAt),
                              style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor),
                            ),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            item.body,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: item.read ? theme.hintColor : theme.textTheme.bodySmall?.color,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        trailing: item.read
                            ? null
                            : Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                      );
                    },
                  ),
                ),
    );
  }
}
