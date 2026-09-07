import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import '../network/api_client.dart';
import '../utils/jwt_decoder_util.dart';
import 'package:flutter/material.dart';
import '../mock_data/mock_data.dart';
import '../models/models.dart';
import '../screens/auth/onboarding_screen.dart';
import '../screens/dashboard/student_dashboard_screen.dart';

import '../screens/jobs/jobs_section_screen.dart';
import '../screens/jobs/job_details_screen.dart';
import '../screens/application/application_success_screen.dart';
import '../screens/profile/profile_applications_screen.dart';
import '../screens/profile/document_verification_screen.dart';
import '../screens/profile/edit_profile_screen.dart';
import '../screens/recruiter/company_portal_screen.dart';
import '../screens/recruiter/recruiter_dashboard_screen.dart';
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

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  DateTime? _lastBackPressTime;

  final TokenStorageService _tokenStorage = TokenStorageService();
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    try {
      // Immediate, lean auth-check with fallback timeout
      await _resolveAuth().timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('[AUTH STATUS] Error checking auth status: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingAuth = false;
        });
      }
      // Ensure native splash is permanently dismissed
      try {
        FlutterNativeSplash.remove();
      } catch (_) {}
    }
  }

  Future<void> _resolveAuth() async {
    try {
      final isLoggedIn = await _tokenStorage.getIsLoggedIn();
      final accessToken = await _tokenStorage.getAccessToken();
      final refreshToken = await _tokenStorage.getRefreshToken();
      final role =
          (accessToken != null
              ? JwtDecoderUtil.getRoleFromToken(accessToken)
              : null) ??
          await _tokenStorage.getUserRole() ??
          'student';

      // If user has previously logged in or has valid tokens, KEEP THEM LOGGED IN!
      if (isLoggedIn ||
          (accessToken != null && accessToken.isNotEmpty) ||
          (refreshToken != null && refreshToken.isNotEmpty)) {
        if (accessToken == null || JwtDecoderUtil.isTokenExpired(accessToken)) {
          ApiClient.instance.attemptSilentRefresh().catchError((_) => false);
        }

        if (mounted) {
          _isLoggedIn = true;
          _isRecruiterMode = role == 'recruiter' || role == 'admin';
        }
        return;
      }
    } catch (e) {
      debugPrint('[AUTH STATUS] resolveAuth error: $e');
    }

    if (mounted) {
      _isLoggedIn = false;
      _isRecruiterMode = false;
    }
  }

  Future<void> _handleLogout() async {
    await _tokenStorage.saveIsLoggedIn(false);
    await _authService.logout();
    setState(() {
      _isLoggedIn = false;
      _isRecruiterMode = false;
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

  void _handleBackAction() {
    // 1. If end drawer is open, close it first
    if (_scaffoldKey.currentState?.isEndDrawerOpen ?? false) {
      _scaffoldKey.currentState?.closeEndDrawer();
      return;
    }

    // 2. Dismiss detail overlays in reverse order
    if (_showApplicationSuccess) {
      setState(() {
        _showApplicationSuccess = false;
        _selectedJob = null;
      });
      return;
    }

    if (_showInterviewScheduler) {
      setState(() {
        _showInterviewScheduler = false;
      });
      return;
    }

    if (_selectedJob != null) {
      setState(() {
        _selectedJob = null;
      });
      return;
    }

    if (_selectedCandidate != null) {
      setState(() {
        _selectedCandidate = null;
      });
      return;
    }

    if (_selectedConversation != null) {
      setState(() {
        _selectedConversation = null;
      });
      return;
    }

    // 3. If on a secondary tab, return to Home/Dashboard tab (index 0)
    if (_currentTab != 0) {
      setState(() {
        _currentTab = 0;
      });
      return;
    }

    // 4. At root dashboard: require double back-press within 2 seconds to exit
    final now = DateTime.now();
    if (_lastBackPressTime == null ||
        now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
      _lastBackPressTime = now;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Press back again to exit TalentLOQ'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 0. While checking auth, native splash covers the screen; render clean background
    if (_isCheckingAuth) {
      final isDark = widget.themeMode == ThemeMode.dark;
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF13121B) : Colors.white,
        body: const SizedBox.shrink(),
      );
    }

    // 1. If not logged in, show Onboarding Screen (Login / Register) FIRST
    if (!_isLoggedIn) {
      return OnboardingScreen(
        onLoginComplete: () async {
          await _tokenStorage.saveIsLoggedIn(true);
          final accessToken = await _tokenStorage.getAccessToken();
          final tokenRole = accessToken != null
              ? JwtDecoderUtil.getRoleFromToken(accessToken)
              : null;
          final role = tokenRole ?? await _tokenStorage.getUserRole() ?? 'student';
          if (mounted) {
            setState(() {
              _isRecruiterMode = role == 'recruiter' || role == 'admin';
              _isLoggedIn = true;
            });
          }
        },
      );
    }

    Widget content;

    // 2. Sub-screen Overlays
    if (_showApplicationSuccess && _selectedJob != null) {
      content = ApplicationSuccessScreen(
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
    } else if (_showInterviewScheduler) {
      content = InterviewSchedulingScreen(
        candidate: _selectedCandidate,
        onBack: () => setState(() => _showInterviewScheduler = false),
        onBookedSuccess: () => setState(() {
          _showInterviewScheduler = false;
          _selectedCandidate = null;
        }),
      );
    } else if (_selectedJob != null) {
      content = JobDetailsScreen(
        job: _selectedJob!,
        onBack: () => setState(() => _selectedJob = null),
        onApplySuccess: () {
          setState(() {
            _showApplicationSuccess = true;
          });
        },
      );
    } else if (_selectedCandidate != null) {
      content = CandidateDetailScreen(
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
              (c) => c.partnerName.toLowerCase().contains(
                _selectedCandidate!.name.toLowerCase(),
              ),
            );
          } catch (_) {
            conv = Conversation(
              id: 'conv-${DateTime.now().millisecondsSinceEpoch}',
              partnerName: _selectedCandidate!.name,
              partnerRole: _selectedCandidate!.roleTitle,
              avatarUrl: _selectedCandidate!.avatarUrl,
              lastMessage:
                  'Conversation started with ${_selectedCandidate!.name}',
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
    } else if (_selectedConversation != null) {
      content = ChatInterfaceScreen(
        conversation: _selectedConversation!,
        onBack: () => setState(() => _selectedConversation = null),
      );
    } else {
      final isDark = widget.themeMode == ThemeMode.dark;
      final bottomInset = MediaQuery.paddingOf(context).bottom;

      // 3. Main Scaffold with True Floating Dock (No bottomNavigationBar slot!)
      content = Scaffold(
        key: _scaffoldKey,
        endDrawer: _buildEndDrawer(context, theme, isDark),
        appBar: _buildAppBar(context, theme, isDark),
        body: Stack(
          children: [
            Positioned.fill(
              child: _buildCurrentTabBody(),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: bottomInset > 0 ? bottomInset + 8 : 16,
              child: _buildFloatingBottomDock(context, isDark),
            ),
          ],
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackAction();
      },
      child: content,
    );
  }

  PreferredSizeWidget? _buildAppBar(BuildContext context, ThemeData theme, bool isDark) {
    if (_isRecruiterMode) {
      switch (_currentTab) {
        case 0:
          return AppBar(
            toolbarHeight: 48,
            titleSpacing: 20,
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
                    color: AppColors.warningLightBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Recruiter',
                    style: TextStyle(
                      color: AppColors.warning,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              Builder(
                builder: (ctx) => IconButton(
                  tooltip: 'Settings & Menu',
                  icon: const Icon(Icons.menu_rounded, size: 24),
                  onPressed: () => Scaffold.of(ctx).openEndDrawer(),
                ),
              ),
              const SizedBox(width: 4),
            ],
          );
        case 1:
          // RecruiterDashboardScreen renders its own Scaffold and AppBar with refresh action
          return null;
        case 2:
          return AppBar(
            titleSpacing: 20,
            title: const Text('Messages', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          );
        case 3:
          return AppBar(
            titleSpacing: 20,
            title: const Text('Schedule', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          );
        default:
          return null;
      }
    } else {
      switch (_currentTab) {
        case 0:
          // ONLY show the TalentLOQ Student branding header on Dashboard
          return AppBar(
            toolbarHeight: 48,
            titleSpacing: 20,
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
                    color: AppColors.primaryLightBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Student',
                    style: TextStyle(
                      color: AppColors.lightPrimary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          );
        case 1:
          // JobsSectionScreen renders its own Campus Placement Hub header with TabBar
          return null;
        case 2:
          return AppBar(
            titleSpacing: 20,
            title: const Text('Messages', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          );
        case 3:
          return AppBar(
            titleSpacing: 20,
            title: const Text('My Profile', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            actions: [
              Builder(
                builder: (ctx) => IconButton(
                  tooltip: 'Settings & Menu',
                  icon: const Icon(Icons.menu_rounded, size: 24),
                  onPressed: () => Scaffold.of(ctx).openEndDrawer(),
                ),
              ),
              const SizedBox(width: 4),
            ],
          );
        default:
          return null;
      }
    }
  }

  Widget _buildFloatingBottomDock(BuildContext context, bool isDark) {
    final navItems = _isRecruiterMode
        ? const [
            (icon: Icons.business_center_outlined, activeIcon: Icons.business_center_rounded, label: 'Portal'),
            (icon: Icons.dashboard_outlined, activeIcon: Icons.dashboard_rounded, label: 'Dashboard'),
            (icon: Icons.chat_bubble_outline_rounded, activeIcon: Icons.chat_bubble_rounded, label: 'Messages'),
            (icon: Icons.calendar_month_outlined, activeIcon: Icons.calendar_month_rounded, label: 'Schedule'),
          ]
        : const [
            (icon: Icons.space_dashboard_outlined, activeIcon: Icons.space_dashboard_rounded, label: 'Dashboard'),
            (icon: Icons.list_alt_outlined, activeIcon: Icons.list_alt_rounded, label: 'Jobs'),
            (icon: Icons.chat_bubble_outline_rounded, activeIcon: Icons.chat_bubble_rounded, label: 'Messages'),
            (icon: Icons.person_outline_rounded, activeIcon: Icons.person_rounded, label: 'Profile'),
          ];

    final primaryColor = _isRecruiterMode ? AppColors.warning : AppColors.lightPrimary;
    final activePillBg = _isRecruiterMode
        ? (isDark ? const Color(0x35F59E0B) : AppColors.warningLightBg)
        : (isDark ? const Color(0x354F46E5) : const Color(0xFFEEF2FF));
    final inactiveColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xF0181726)
                : Colors.white.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.12)
                  : const Color(0xFFE2E8F0),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
                blurRadius: 24,
                offset: const Offset(0, 8),
                spreadRadius: 0,
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(navItems.length, (index) {
              final isSelected = (_currentTab < navItems.length ? _currentTab : 0) == index;
              final item = navItems[index];

              return Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () => setState(() => _currentTab = index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      decoration: BoxDecoration(
                        color: isSelected ? activePillBg : Colors.transparent,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isSelected ? item.activeIcon : item.icon,
                            size: 22,
                            color: isSelected ? primaryColor : inactiveColor,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              color: isSelected ? primaryColor : inactiveColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentTabBody() {
    if (_isRecruiterMode) {
      switch (_currentTab) {
        case 0:
          return CompanyPortalScreen(
            onSelectCandidate: (cand) =>
                setState(() => _selectedCandidate = cand),
            onScheduleInterview: () =>
                setState(() => _showInterviewScheduler = true),
          );
        case 1:
          return RecruiterDashboardScreen(
            onOpenDrawer: () => Scaffold.of(context).openEndDrawer(),
          );
        case 2:
          return MessagesListScreen(
            onSelectConversation: (conv) =>
                setState(() => _selectedConversation = conv),
          );
        case 3:
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
            onScheduleInterview: () =>
                setState(() => _showInterviewScheduler = true),
          );
        case 1:
          return const JobsSectionScreen();
        case 2:
          return MessagesListScreen(
            onSelectConversation: (conv) =>
                setState(() => _selectedConversation = conv),
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

  Widget _buildEndDrawer(BuildContext context, ThemeData theme, bool isDark) {
    final textPrimary = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;
    final textSecondary = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final dividerColor = isDark
        ? const Color(0xFF262534)
        : const Color(0xFFF1F5F9);

    return Drawer(
      backgroundColor: isDark ? const Color(0xFF161522) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(left: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Minimal Header Bar with Close Button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 10, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Quick Menu',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                      letterSpacing: -0.3,
                      color: textPrimary,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 22),
                    tooltip: 'Close Menu',
                    color: textSecondary,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              color: isDark ? const Color(0xFF262534) : const Color(0xFFE2E8F0),
            ),

            // Seamless Content (No Boxes, Pure Clean List)
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  // --- PREFERENCES ---
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                    child: Text(
                      'PREFERENCES',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.9,
                        color: textSecondary,
                      ),
                    ),
                  ),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 2,
                    ),
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: widget.themeMode == ThemeMode.dark
                            ? const Color(0x24FFA116)
                            : AppColors.primaryLightBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        widget.themeMode == ThemeMode.dark
                            ? Icons.dark_mode_rounded
                            : Icons.light_mode_rounded,
                        color: widget.themeMode == ThemeMode.dark
                            ? const Color(0xFFFFA116)
                            : AppColors.lightPrimary,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      'Dark Theme',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      widget.themeMode == ThemeMode.dark
                          ? 'Enabled'
                          : 'Disabled',
                      style: TextStyle(fontSize: 12, color: textSecondary),
                    ),
                    trailing: Switch.adaptive(
                      value: widget.themeMode == ThemeMode.dark,
                      activeThumbColor: AppColors.lightPrimary,
                      onChanged: (bool value) {
                        widget.onToggleTheme(
                          value ? ThemeMode.dark : ThemeMode.light,
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Divider(height: 1, color: dividerColor),
                  ),
                  const SizedBox(height: 8),

                  // --- QUICK TOOLS ---
                  if (!_isRecruiterMode) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                      child: Text(
                        'QUICK TOOLS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.9,
                          color: textSecondary,
                        ),
                      ),
                    ),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 2,
                      ),
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.primaryLightBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.verified_user_rounded,
                          color: AppColors.lightPrimary,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        'Document Verification',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        'Upload marksheet & resume',
                        style: TextStyle(fontSize: 12, color: textSecondary),
                      ),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: textSecondary,
                      ),
                      onTap: () {
                        Navigator.of(context).pop();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const DocumentVerificationScreen(),
                          ),
                        );
                      },
                    ),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 2,
                      ),
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.darkPrimary.withValues(alpha: 0.15)
                              : const Color(0xFFE0E7FF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.badge_outlined,
                          color: AppColors.lightPrimary,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        'Edit Profile Info',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        'Name, email & university',
                        style: TextStyle(fontSize: 12, color: textSecondary),
                      ),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: textSecondary,
                      ),
                      onTap: () {
                        Navigator.of(context).pop();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const EditProfileScreen(),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Divider(height: 1, color: dividerColor),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // --- ACCOUNT ---
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                    child: Text(
                      'ACCOUNT',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.9,
                        color: textSecondary,
                      ),
                    ),
                  ),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 2,
                    ),
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.logout_rounded,
                        color: AppColors.error,
                        size: 20,
                      ),
                    ),
                    title: const Text(
                      'Log Out',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.error,
                      ),
                    ),
                    subtitle: Text(
                      'Sign out of this device',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.error.withValues(alpha: 0.8),
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: AppColors.error,
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      _confirmAndLogout();
                    },
                  ),
                ],
              ),
            ),

            // Footer Branding
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const TalentloqBrandingHeader(
                    height: 18,
                    showWordmark: false,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'TalentLOQ • Placement Intelligence',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAndLogout() async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark
            ? AppColors.darkSurface
            : AppColors.lightSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Log Out',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: const Text(
          'Are you sure you want to sign out of your account?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (shouldLogout == true) {
      _handleLogout();
    }
  }
}