import 'package:flutter_test/flutter_test.dart';
import 'package:talentloq/models/models.dart';

void main() {
  group('Models - Unit & Regression Tests', () {
    test('Job model instantiates with correct fields and default values', () {
      final job = Job(
        id: 'job_101',
        title: 'Flutter Developer',
        company: 'TechCorp',
        logoUrl: 'https://example.com/logo.png',
        location: 'Vadodara, India',
        jobType: 'Full-Time',
        salaryRange: '₹6-8 LPA',
        salaryMin: 600000,
        salaryMax: 800000,
        description: 'Build cross-platform Flutter applications',
        requirements: ['Flutter', 'Dart', 'FastAPI'],
        perks: ['Remote Option', 'Health Insurance'],
        postedTime: '2 days ago',
        applicantCount: 42,
      );

      expect(job.id, 'job_101');
      expect(job.title, 'Flutter Developer');
      expect(job.isSaved, isFalse); // Default value check
      expect(job.requirements.length, 3);
      expect(job.perks.length, 2);
      expect(job.salaryMin, 600000);
      expect(job.salaryMax, 800000);
    });

    test('Candidate model instantiates with expected defaults', () {
      final candidate = Candidate(
        id: 'cand_202',
        name: 'Jane Doe',
        roleTitle: 'Software Engineer Intern',
        avatarUrl: 'https://example.com/avatar.png',
        location: 'Gujarat',
        experience: 'Fresher',
        education: 'B.Tech CSE, GSFC University',
        matchScore: 92.5,
        skills: ['Flutter', 'Python', 'Docker'],
        bio: 'Aspiring mobile and backend engineer',
        status: 'Under Review',
      );

      expect(candidate.id, 'cand_202');
      expect(candidate.name, 'Jane Doe');
      expect(candidate.matchScore, 92.5);
      // Default parameters checks
      expect(candidate.validationStatus, 'pending');
      expect(candidate.skillGaps, isEmpty);
      expect(candidate.isAutoApplied, isFalse);
      expect(candidate.studentApproved, isTrue);
      expect(candidate.cgpa, 8.0);
      expect(candidate.activeBacklogs, 0);
      expect(candidate.closedBacklogs, 0);
      expect(candidate.resumeUrl, isNull);
      expect(candidate.ugMarksheetUrl, isNull);
    });

    test('Application model links Job and tracks application step progress', () {
      final job = Job(
        id: 'job_102',
        title: 'Backend Engineer',
        company: 'CloudWorks',
        logoUrl: 'https://example.com/logo2.png',
        location: 'Remote',
        jobType: 'Full-Time',
        salaryRange: '₹8-10 LPA',
        salaryMin: 800000,
        salaryMax: 1000000,
        description: 'FastAPI microservices development',
        requirements: ['Python', 'FastAPI'],
        perks: ['Flexible hours'],
        postedTime: '1 day ago',
        applicantCount: 15,
      );

      final app = Application(
        id: 'app_501',
        job: job,
        appliedDate: '12 Sep 2026',
        status: 'Interview Scheduled',
        currentStep: 2,
        totalSteps: 4,
      );

      expect(app.id, 'app_501');
      expect(app.job.title, 'Backend Engineer');
      expect(app.currentStep, 2);
      expect(app.totalSteps, 4);
      expect(app.status, 'Interview Scheduled');
    });

    test('ChatMessage model tracks sender and flags isMe correctly', () {
      final messageMe = ChatMessage(
        id: 'msg_1',
        senderId: 'usr_1',
        senderName: 'You',
        text: 'Hello, when is the interview?',
        time: '10:30 AM',
        isMe: true,
      );

      final messageOther = ChatMessage(
        id: 'msg_2',
        senderId: 'rec_1',
        senderName: 'Recruiter',
        text: 'It is scheduled for tomorrow at 2 PM.',
        time: '10:32 AM',
        isMe: false,
      );

      expect(messageMe.isMe, isTrue);
      expect(messageOther.isMe, isFalse);
    });

    test('Conversation, InterviewSlot, Announcement, and SupportTicket instantiate properly', () {
      final convo = Conversation(
        id: 'conv_1',
        partnerName: 'HR Team',
        partnerRole: 'Talent Acquisition',
        avatarUrl: 'https://example.com/hr.png',
        lastMessage: 'Documents verified.',
        time: '11:00 AM',
        unreadCount: 1,
        isOnline: true,
      );
      expect(convo.unreadCount, 1);
      expect(convo.isOnline, isTrue);

      final slot = InterviewSlot(
        id: 'slot_1',
        date: '2026-09-20',
        time: '02:00 PM',
        candidateName: 'John Doe',
        position: 'Flutter Dev',
        type: 'Technical Round',
      );
      expect(slot.isBooked, isFalse);
      expect(slot.status, 'scheduled');

      final announcement = Announcement(
        id: 'ann_1',
        title: 'Campus Drive Announced',
        content: 'Registration closes this Friday.',
        author: 'Placement Cell',
        createdAt: '2026-09-15',
      );
      expect(announcement.title, 'Campus Drive Announced');

      final ticket = SupportTicket(
        id: 'tkt_1',
        studentName: 'Jane',
        subject: 'Profile Sync Query',
        description: 'Unable to update CGPA',
        status: 'open',
      );
      expect(ticket.aiDraftFlagged, isFalse);
      expect(ticket.status, 'open');
    });
  });
}
