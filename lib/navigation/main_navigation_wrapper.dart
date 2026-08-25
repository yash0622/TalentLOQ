import 'package:flutter/material.dart';
import '../mock_data/mock_data.dart';
import '../models/models.dart';
import '../screens/auth/onboarding_screen.dart';
import '../screens/dashboard/student_dashboard_screen.dart';

import '../screens/jobs/jobs_section_screen.dart';
import '../screens/jobs/job_details_screen.dart';
import '../screens/application/application_success_screen.dart';
import '../screens/profile/profile_applications_screen.dart';
import '../screens/recruiter/company_portal_screen.dart';
import '../screens/recruiter/candidate_detail_screen.dart';
import '../screens/chat/messages_list_screen.dart';
import '../screens/chat/chat_interface_screen.dart';
import '../screens/interview/interview_scheduling_screen.dart';
import '../theme/app_colors.dart';
import '../widgets/talentloq_branding_header.dart';

import '../services/token_storage_service.dart';
import '../services/auth_service.dart';

class MainNavigationWrapper extends StatefulWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onToggleTheme;

  const MainNavigationWrapper({
    super.key,
    required this.themeMode,
    required this.onToggleTheme,
  });

  @override
  State<MainNavigationWrapper> createState() => _MainNavigationWrapperState();
}

class _MainNavigationWrapperState extends State<MainNavigationWrapper> {
  bool _isLoggedIn = false; // Default: Require Login / Registration
  bool _isCheckingAuth = true;
  bool _isRecruiterMode = false; // false: Student, true: Recruiter
  int _currentTab = 0;

  // Active detail view overlays
  Job? _selectedJob;
  Candidate? _selectedCandidate;
  Conversation? _selectedConversation;
  bool _showApplicationSuccess = false;
  bool _showInterviewScheduler = false;

  final TokenStorageService _tokenStorage = TokenStorageService();
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    // Clear stored tokens on startup so restarting the app ALWAYS lands on Login / Registration page
    await _tokenStorage.clearTokens();

    setState(() {
      _isLoggedIn = false;
      _isRecruiterMode = false;
      _isCheckingAuth = false;
    });
  }

  Future<void> _handleLogout() async {
    await _authService.logout();
    setState(() {
      _isLoggedIn = false;
      _currentTab = 0;
      _selectedJob = null;
      _selectedCandidate = null;
      _selectedConversation = null;
      _showInterviewScheduler = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Logged out successfully'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 0. Showing loading screen while checking secure tokens
    if (_isCheckingAuth) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // 1. If not logged in, show Onboarding Screen (Login / Register) FIRST
    if (!_isLoggedIn) {
      return OnboardingScreen(
        onLoginComplete: () async {
          final role = await _tokenStorage.getUserRole();
          setState(() {
            _isRecruiterMode = role == 'recruiter';
            _isLoggedIn = true;
          });
        },
      );
    }

    // 2. Sub-screen Overlays
    if (_showApplicationSuccess && _selectedJob != null) {
      return ApplicationSuccessScreen(
        job: _selectedJob!,
        onViewApplications: () {
          setState(() {
            _showApplicationSuccess = false;
            _selectedJob = null;
            _currentTab = 3; // Profile & Applications tab
          });
        },
        onReturnHome: () {
          setState(() {
            _showApplicationSuccess = false;
            _selectedJob = null;
            _currentTab = 0; // Dashboard tab
          });
        },
      );
    }

    if (_showInterviewScheduler) {
      return InterviewSchedulingScreen(
        candidate: _selectedCandidate,
        onBack: () => setState(() => _showInterviewScheduler = false),
        onBookedSuccess: () => setState(() {
          _showInterviewScheduler = false;
          _selectedCandidate = null;
        }),
      );
    }

    if (_selectedJob != null) {
      return JobDetailsScreen(
        job: _selectedJob!,
        onBack: () => setState(() => _selectedJob = null),
        onApplySuccess: () {
          setState(() {
            _showApplicationSuccess = true;
          });
        },
      );
    }

    if (_selectedCandidate != null) {
      return CandidateDetailScreen(
        candidate: _selectedCandidate!,
        onBack: () => setState(() => _selectedCandidate = null),
        onScheduleInterview: () {
          setState(() {
            _showInterviewScheduler = true;
          });
        },
        onSendMessage: () {
          Conversation? conv;
          try {
            conv = MockData.conversations.firstWhere(
              (c) => c.partnerName.toLowerCase().contains(_selectedCandidate!.name.toLowerCase()),
            );
          } catch (_) {
            conv = Conversation(
              id: 'conv-${DateTime.now().millisecondsSinceEpoch}',
              partnerName: _selectedCandidate!.name,
              partnerRole: _selectedCandidate!.roleTitle,
              avatarUrl: _selectedCandidate!.avatarUrl,
              lastMessage: 'Conversation started with ${_selectedCandidate!.name}',
              time: 'Just now',
              unreadCount: 0,
              isOnline: true,
            );
            MockData.conversations.insert(0, conv);
          }
          setState(() {
            _selectedCandidate = null;
            _selectedConversation = conv;
          });
        },
      );
    }

    if (_selectedConversation != null) {
      return ChatInterfaceScreen(
        conversation: _selectedConversation!,
        onBack: () => setState(() => _selectedConversation = null),
      );
    }

    // 3. Main Scaffold with Bottom Navigation
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 48,
        titleSpacing: 12,
        title: Row(
          children: [
            const TalentloqBrandingHeader(height: 24, showWordmark: false),
            const SizedBox(width: 8),
            Text(
              'TalentLOQ',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _isRecruiterMode ? AppColors.warningLightBg : AppColors.primaryLightBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _isRecruiterMode ? 'Recruiter' : 'Student',
                style: TextStyle(
                  color: _isRecruiterMode ? AppColors.warning : AppColors.lightPrimary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        actions: [
          if ((!_isRecruiterMode && _currentTab == 3) || (_isRecruiterMode && _currentTab == 0)) ...[
            IconButton(
              tooltip: widget.themeMode == ThemeMode.dark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
              icon: Icon(
                widget.themeMode == ThemeMode.dark
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_rounded,
              ),
              onPressed: () {
                widget.onToggleTheme(
                  widget.themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
                );
              },
            ),
            IconButton(
              iconSize: 20,
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(6),
              tooltip: 'Log Out',
              icon: const Icon(Icons.logout_rounded),
              onPressed: _handleLogout,
            ),
            const SizedBox(width: 4),
          ],
        ],
      ),

      // Main Tab Body
      body: _buildCurrentTabBody(),

      // Bottom Navigation Bar
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTab,
        onTap: (index) => setState(() => _currentTab = index),
        items: _isRecruiterMode
            ? const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.dashboard_rounded),
                  label: 'Portal',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.chat_bubble_outline_rounded),
                  label: 'Messages',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.calendar_month_rounded),
                  label: 'Schedule',
                ),
              ]
            : const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.home_filled),
                  label: 'Home',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.work_rounded),
                  label: 'Jobs',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.chat_bubble_outline_rounded),
                  label: 'Messages',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.person_rounded),
                  label: 'Profile',
                ),
              ],
      ),
    );
  }

  Widget _buildCurrentTabBody() {
    if (_isRecruiterMode) {
      switch (_currentTab) {
        case 0:
          return CompanyPortalScreen(
            onSelectCandidate: (cand) => setState(() => _selectedCandidate = cand),
            onScheduleInterview: () => setState(() => _showInterviewScheduler = true),
          );
        case 1:
          return MessagesListScreen(
            onSelectConversation: (conv) => setState(() => _selectedConversation = conv),
          );
        case 2:
          return InterviewSchedulingScreen(
            showAppBar: false,
            onBack: () => setState(() => _currentTab = 0),
            onBookedSuccess: () => setState(() => _currentTab = 0),
          );
        default:
          return const SizedBox.shrink();
      }
    } else {
      switch (_currentTab) {
        case 0:
          return StudentDashboardScreen(
            onSelectJob: (job) => setState(() => _selectedJob = job),
            onViewAllJobs: () => setState(() => _currentTab = 1),
            onViewMessages: () => setState(() => _currentTab = 2),
            onViewApplications: () => setState(() => _currentTab = 1),
            onScheduleInterview: () => setState(() => _showInterviewScheduler = true),
          );
        case 1:
          return const JobsSectionScreen();
        case 2:
          return MessagesListScreen(
            onSelectConversation: (conv) => setState(() => _selectedConversation = conv),
          );
        case 3:
          return ProfileApplicationsScreen(
            onSelectJob: (job) => setState(() => _selectedJob = job),
          );
        default:
          return const SizedBox.shrink();
      }
    }
  }
}
