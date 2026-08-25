class Job {
  final String id;
  final String title;
  final String company;
  final String logoUrl;
  final String location;
  final String jobType; // e.g. Full-Time, Remote, Contract
  final String salaryRange;
  final int salaryMin;
  final int salaryMax;
  final String description;
  final List<String> requirements;
  final List<String> perks;
  final String postedTime;
  final int applicantCount;
  final bool isSaved;

  Job({
    required this.id,
    required this.title,
    required this.company,
    required this.logoUrl,
    required this.location,
    required this.jobType,
    required this.salaryRange,
    required this.salaryMin,
    required this.salaryMax,
    required this.description,
    required this.requirements,
    required this.perks,
    required this.postedTime,
    required this.applicantCount,
    this.isSaved = false,
  });
}

class Candidate {
  final String id;
  final String name;
  final String roleTitle;
  final String avatarUrl;
  final String location;
  final String experience;
  final String education;
  final double matchScore;
  final List<String> skills;
  final String bio;
  final String status; // e.g. Interview Scheduled, Under Review, Offer Sent
  final String validationStatus; // "pending", "valid", "not_valid"
  final List<String> skillGaps;
  final bool isAutoApplied;
  final bool studentApproved;
  final double cgpa;
  final int activeBacklogs;
  final int closedBacklogs;

  Candidate({
    required this.id,
    required this.name,
    required this.roleTitle,
    required this.avatarUrl,
    required this.location,
    required this.experience,
    required this.education,
    required this.matchScore,
    required this.skills,
    required this.bio,
    required this.status,
    this.validationStatus = 'pending',
    this.skillGaps = const [],
    this.isAutoApplied = false,
    this.studentApproved = true,
    this.cgpa = 8.0,
    this.activeBacklogs = 0,
    this.closedBacklogs = 0,
  });
}

class Application {
  final String id;
  final Job job;
  final String appliedDate;
  final String status; // e.g. Under Review, Interview Scheduled, Accepted, Rejected
  final int currentStep;
  final int totalSteps;

  Application({
    required this.id,
    required this.job,
    required this.appliedDate,
    required this.status,
    required this.currentStep,
    required this.totalSteps,
  });
}

class ChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String text;
  final String time;
  final bool isMe;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.time,
    required this.isMe,
  });
}

class Conversation {
  final String id;
  final String partnerName;
  final String partnerRole;
  final String avatarUrl;
  String lastMessage;
  String time;
  int unreadCount;
  final bool isOnline;

  Conversation({
    required this.id,
    required this.partnerName,
    required this.partnerRole,
    required this.avatarUrl,
    required this.lastMessage,
    required this.time,
    required this.unreadCount,
    required this.isOnline,
  });
}

class InterviewSlot {
  final String id;
  final String date;
  final String time;
  final String candidateName;
  final String position;
  final String type; // e.g. Technical Round, HR Screen
  final bool isBooked;
  final String status; // scheduled, passed, failed, next_round
  final String feedback;

  InterviewSlot({
    required this.id,
    required this.date,
    required this.time,
    required this.candidateName,
    required this.position,
    required this.type,
    this.isBooked = false,
    this.status = 'scheduled',
    this.feedback = '',
  });
}

class Announcement {
  final String id;
  final String title;
  final String content;
  final String author;
  final String createdAt;

  Announcement({
    required this.id,
    required this.title,
    required this.content,
    required this.author,
    required this.createdAt,
  });
}

class SupportTicket {
  final String id;
  final String studentName;
  final String subject;
  final String description;
  final bool aiDraftFlagged;
  final String status; // open, resolved
  final String? recruiterResponse;

  SupportTicket({
    required this.id,
    required this.studentName,
    required this.subject,
    required this.description,
    this.aiDraftFlagged = false,
    required this.status,
    this.recruiterResponse,
  });
}

class AcademicRecord {
  final String studentId;
  final String fullName;
  final String education;
  final double currentCgpa;
  final int activeBacklogs;
  final int closedBacklogs;
  final List<Map<String, dynamic>> cgpaHistory;

  AcademicRecord({
    required this.studentId,
    required this.fullName,
    required this.education,
    required this.currentCgpa,
    required this.activeBacklogs,
    required this.closedBacklogs,
    required this.cgpaHistory,
  });
}
