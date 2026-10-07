import '../models/models.dart';
import '../network/api_client.dart';
import '../mock_data/mock_data.dart';

class SendMessageResult {
  final ChatMessage userMessage;
  final ChatMessage? botResponse;

  const SendMessageResult({
    required this.userMessage,
    this.botResponse,
  });
}

class ChatService {
  final ApiClient _apiClient = ApiClient.instance;

  /// Fetch active conversations from backend
  Future<List<Conversation>> getConversations() async {
    try {
      final response = await _apiClient.dio.get('/chat/conversations');
      if (response.statusCode == 200 && response.data is Map) {
        final list = (response.data['conversations'] as List?) ?? [];
        final convs = list.map((item) {
          final m = Map<String, dynamic>.from(item as Map);
          return Conversation(
            id: m['id'] ?? '',
            partnerName: m['candidate_name'] ?? 'Candidate',
            partnerRole: 'Recruiter',
            avatarUrl: '',
            lastMessage: m['last_message'] ?? '',
            time: m['last_message_time'] ?? 'Just now',
            unreadCount: m['unread_count'] ?? 0,
            isOnline: true,
          );
        }).toList();

        if (convs.isNotEmpty) {
          final hasAiBot = convs.any((c) => c.id == 'ai_bot' || c.partnerName == 'Placement Assistant');
          if (!hasAiBot) {
            convs.insert(
              0,
              Conversation(
                id: 'ai_bot',
                partnerName: 'Placement Assistant',
                partnerRole: 'Placement Assistant',
                avatarUrl: '',
                lastMessage: 'Tell me your target domains, skills, and salary in plain English!',
                time: 'Always Active',
                unreadCount: 0,
                isOnline: true,
              ),
            );
          }
          MockData.conversations.clear();
          MockData.conversations.addAll(convs);
          return convs;
        }
      }
    } catch (_) {}
    return MockData.conversations;
  }

  /// Fetch messages for a conversation from backend
  Future<List<ChatMessage>> getMessages(String conversationId) async {
    try {
      final response = await _apiClient.dio.get('/chat/conversations/$conversationId/messages');
      if (response.statusCode == 200 && response.data is Map) {
        final list = (response.data['messages'] as List?) ?? [];
        final msgs = list.map((item) {
          final m = Map<String, dynamic>.from(item as Map);
          return ChatMessage(
            id: m['id'] ?? '',
            senderId: m['sender_id'] ?? '',
            senderName: m['sender_name'] ?? 'User',
            text: m['text'] ?? '',
            time: m['time'] ?? 'Just now',
            isMe: m['is_me'] ?? false,
          );
        }).toList();

        MockData.conversationMessages[conversationId] = msgs;
        return msgs;
      }
    } catch (_) {}
    return MockData.conversationMessages[conversationId] ?? [];
  }

  /// Send chat message via backend API
  Future<SendMessageResult?> sendMessage({
    required String recipientId,
    required String text,
    String? conversationId,
    String? recipientName,
  }) async {
    try {
      final payload = <String, dynamic>{
        'recipient_id': recipientId,
        'text': text,
      };
      if (conversationId != null) payload['conversation_id'] = conversationId;
      if (recipientName != null) payload['recipient_name'] = recipientName;

      final response = await _apiClient.dio.post('/chat/messages', data: payload);
      if (response.statusCode == 201 && response.data is Map) {
        final m = Map<String, dynamic>.from(response.data as Map);
        final newMsg = ChatMessage(
          id: m['id'] ?? 'msg-${DateTime.now().millisecondsSinceEpoch}',
          senderId: m['sender_id'] ?? 'me',
          senderName: m['sender_name'] ?? 'Me',
          text: m['text'] ?? text,
          time: 'Just now',
          isMe: true,
        );

        ChatMessage? botMsg;
        if (m['bot_response'] is Map) {
          final b = Map<String, dynamic>.from(m['bot_response'] as Map);
          botMsg = ChatMessage(
            id: b['id'] ?? 'msg-${DateTime.now().millisecondsSinceEpoch}',
            senderId: b['sender_id'] ?? 'bot',
            senderName: b['sender_name'] ?? 'Assistant',
            text: b['text'] ?? '',
            time: 'Just now',
            isMe: false,
          );
        }

        final targetConvId = conversationId ?? m['conversation_id'];
        if (targetConvId != null) {
          final list = MockData.conversationMessages.putIfAbsent(targetConvId, () => []);
          if (list.isEmpty || list.last.text != text || !list.last.isMe) {
            list.add(newMsg);
          }
          if (botMsg != null) {
            list.add(botMsg);
          }
        }

        return SendMessageResult(userMessage: newMsg, botResponse: botMsg);
      }
    } catch (_) {}

    final fallbackMsg = ChatMessage(
      id: 'msg-${DateTime.now().millisecondsSinceEpoch}',
      senderId: 'me',
      senderName: 'Me',
      text: text,
      time: 'Just now',
      isMe: true,
    );
    if (conversationId != null) {
      final list = MockData.conversationMessages.putIfAbsent(conversationId, () => []);
      if (list.isEmpty || list.last.text != text || !list.last.isMe) {
        list.add(fallbackMsg);
      }
    }
    return SendMessageResult(userMessage: fallbackMsg);
  }

  /// Get active AI placement agent criteria for student
  Future<Map<String, dynamic>?> getAiBotCriteria() async {
    try {
      final response = await _apiClient.dio.get('/chat/ai-agent/criteria');
      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
    } catch (_) {}
    return null;
  }

  /// Delete/clear all messages in a conversation
  Future<bool> clearConversation(String conversationId) async {
    try {
      final response = await _apiClient.dio.delete('/chat/conversations/$conversationId');
      MockData.conversationMessages.removeWhere(
        (k, _) => k == conversationId || k.contains(conversationId) || conversationId.contains(k),
      );
      return response.statusCode == 200;
    } catch (_) {
      MockData.conversationMessages.removeWhere(
        (k, _) => k == conversationId || k.contains(conversationId) || conversationId.contains(k),
      );
      return false;
    }
  }

  /// Get AI Chat sessions/history
  Future<List<Map<String, dynamic>>> getAiSessions() async {
    try {
      final response = await _apiClient.dio.get('/chat/ai/sessions');
      if (response.statusCode == 200 && response.data is Map) {
        final list = response.data['sessions'] as List?;
        if (list != null) {
          return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      }
    } catch (_) {}
    return [];
  }
}