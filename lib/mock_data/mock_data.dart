import '../models/models.dart';

class MockData {
  static final List<Job> jobs = [];
  static final List<Candidate> candidates = [];
  static final List<Application> applications = [];

  // Active Conversations List (empty by default; populated when users initiate chats)
  static final List<Conversation> conversations = [];

  // Map of conversation ID to message history
  static final Map<String, List<ChatMessage>> conversationMessages = {};

  static final List<ChatMessage> chatMessages = [];
  static final List<InterviewSlot> interviewSlots = [];
  static final List<Announcement> announcements = [];
  static final List<SupportTicket> supportTickets = [];
}
