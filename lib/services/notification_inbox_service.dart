import 'package:dio/dio.dart';
import '../network/api_client.dart';

class NotificationInboxItem {
  final String id;
  final String type;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final bool read;
  final DateTime createdAt;

  NotificationInboxItem({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.data,
    required this.read,
    required this.createdAt,
  });

  factory NotificationInboxItem.fromJson(Map<String, dynamic> json) {
    DateTime parsedDate;
    try {
      parsedDate = DateTime.parse(json['created_at']?.toString() ?? '');
    } catch (_) {
      parsedDate = DateTime.now();
    }

    return NotificationInboxItem(
      id: (json['id'] ?? json['notification_id'] ?? '').toString(),
      type: (json['type'] ?? 'GENERAL').toString(),
      title: (json['title'] ?? '').toString(),
      body: (json['body'] ?? '').toString(),
      data: json['data'] is Map ? Map<String, dynamic>.from(json['data'] as Map) : {},
      read: json['read'] == true,
      createdAt: parsedDate,
    );
  }

  NotificationInboxItem copyWith({bool? read}) {
    return NotificationInboxItem(
      id: id,
      type: type,
      title: title,
      body: body,
      data: data,
      read: read ?? this.read,
      createdAt: createdAt,
    );
  }
}

class NotificationInboxResponse {
  final List<NotificationInboxItem> items;
  final String? nextCursor;
  final bool hasMore;

  NotificationInboxResponse({
    required this.items,
    this.nextCursor,
    required this.hasMore,
  });
}

class NotificationInboxService {
  NotificationInboxService._internal();
  static final NotificationInboxService instance = NotificationInboxService._internal();

  final Dio _dio = ApiClient.instance.dio;

  /// Fetch paginated notification items (GET /notifications?cursor=&limit=)
  Future<NotificationInboxResponse> getNotifications({String? cursor, int limit = 20}) async {
    try {
      final queryParams = <String, dynamic>{'limit': limit};
      if (cursor != null && cursor.isNotEmpty) {
        queryParams['cursor'] = cursor;
      }

      final response = await _dio.get('/notifications', queryParameters: queryParams);
      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map<String, dynamic>;
        final rawItems = data['items'] as List<dynamic>? ?? [];
        final items = rawItems
            .whereType<Map<String, dynamic>>()
            .map((e) => NotificationInboxItem.fromJson(e))
            .toList();

        return NotificationInboxResponse(
          items: items,
          nextCursor: data['next_cursor']?.toString(),
          hasMore: data['has_more'] == true,
        );
      }
    } catch (_) {}

    return NotificationInboxResponse(items: [], hasMore: false);
  }

  /// Get unread notification badge count (GET /notifications/unread-count)
  Future<int> getUnreadCount() async {
    try {
      final response = await _dio.get('/notifications/unread-count');
      if (response.statusCode == 200 && response.data is Map) {
        return (response.data['unread_count'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {}
    return 0;
  }

  /// Mark single notification as read (POST /notifications/{id}/read)
  Future<bool> markAsRead(String notificationId) async {
    try {
      final response = await _dio.post('/notifications/$notificationId/read');
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Mark all notifications as read (POST /notifications/read-all)
  Future<bool> markAllAsRead() async {
    try {
      final response = await _dio.post('/notifications/read-all');
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Fetch user notification category preferences (GET /notifications/preferences)
  Future<Map<String, bool>> getPreferences() async {
    try {
      final response = await _dio.get('/notifications/preferences');
      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map<String, dynamic>;
        return {
          'drive_alerts': data['drive_alerts'] ?? true,
          'round_results': data['round_results'] ?? true,
          'offers': data['offers'] ?? true,
          'chat_messages': data['chat_messages'] ?? true,
        };
      }
    } catch (_) {}
    return {
      'drive_alerts': true,
      'round_results': true,
      'offers': true,
      'chat_messages': true,
    };
  }

  /// Update user notification category preferences (PUT /notifications/preferences)
  Future<bool> updatePreferences(Map<String, bool> prefs) async {
    try {
      final response = await _dio.put('/notifications/preferences', data: prefs);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
