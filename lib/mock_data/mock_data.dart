import '../models/models.dart';

class MockData {
  static final List<Job> jobs = [];
  static final List<Candidate> candidates = [];
  static final List<Application> applications = [];

  // Active Conversations List (AI Bot is permanently available at the top)
  static final List<Conversation> conversations = [
    Conversation(
      id: 'ai_bot',
      partnerName: 'AI Bot',
      partnerRole: 'Placement Assistant',
      avatarUrl: '',
      lastMessage: 'Tell me your target domains, skills, and salary in plain English!',
      time: 'Always Active',
      unreadCount: 0,
      isOnline: true,
    ),
  ];

  // Map of conversation ID to message history
  static final Map<String, List<ChatMessage>> conversationMessages = {
    'ai_bot': [
      ChatMessage(
        id: 'welcome_ai_bot',
        senderId: 'ai_bot',
        senderName: 'AI Bot',
        text: 'Hello! I am your AI Placement Assistant.\n\nTell me what opportunities you want me to monitor and apply for in natural English.\n\nExample:\n"Apply for upcoming companies that require AI/ML skills or other domains mentioned in my resume, with a salary package of 3–4 LPA."',
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
