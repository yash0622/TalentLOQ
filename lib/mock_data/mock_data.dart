import '../models/models.dart';

class MockData {
  static final List<Job> jobs = [];
  static final List<Candidate> candidates = [];
  static final List<Application> applications = [];

  // Active Conversations List (Populated dynamically per user role)
  static final List<Conversation> conversations = [];

  // Map of conversation ID to message history
  static final Map<String, List<ChatMessage>> conversationMessages = {
    'ai_bot': [
      ChatMessage(
        id: 'welcome_ai_bot',
        senderId: 'ai_bot',
        senderName: 'Placement Assistant',
        text: 'Hello! I am your Placement Assistant.\n\nTell me what opportunities you want me to monitor and apply for in natural English.\n\nExample:\n"Apply for upcoming companies matching my skills, with a salary package of 3–4 LPA."',
        time: 'Always Active',
        isMe: false,
      ),
    ],
  };

  static final List<ChatMessage> chatMessages = [];
  static final List<InterviewSlot> interviewSlots = [];
  static final List<Announcement> announcements = [];
  static final List<SupportTicket> supportTickets = [];
}
