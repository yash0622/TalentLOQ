import 'package:flutter/material.dart';
import '../../mock_data/mock_data.dart';
import '../../models/models.dart';
import '../../theme/app_colors.dart';
import '../../services/drive_service.dart';
import '../../services/interview_service.dart';
import '../../services/application_visibility_state.dart';
import '../../widgets/skeleton_widgets.dart';
import '../jobs/company_detail_screen.dart';

class StudentDashboardScreen extends StatefulWidget {
  final Function(Job) onSelectJob;
  final VoidCallback onViewAllJobs;
  final VoidCallback onViewMessages;
  final VoidCallback? onViewApplications;
  final VoidCallback? onScheduleInterview;

  const StudentDashboardScreen({
    super.key,
    required this.onSelectJob,
    required this.onViewAllJobs,
    required this.onViewMessages,
    this.onViewApplications,
    this.onScheduleInterview,
  });

  @override
  State<StudentDashboardScreen> createState() => _StudentDashboardScreenState();
}

class _StudentDashboardScreenState extends State<StudentDashboardScreen> {
  final DriveService _driveService = DriveService();
  List<Map<String, dynamic>> _recommendedDrives = [];
  List<Map<String, dynamic>> _broadcasts = [];
  bool _isLoadingJobs = true;
  int _appliedCount = 0;
  int _inReviewCount = 0;
  int _interviewsCount = 0;
  Map<String, dynamic>? _upcomingInterview;

  @override
  void initState() {
    super.initState();
    ApplicationVisibilityState.instance.addListener(_onApplicationStateChanged);
    _loadBackendDrives();
  }

  void _onApplicationStateChanged() {
    if (mounted) {
      _loadBackendDrives();
    }
  }

  @override
  void dispose() {
    ApplicationVisibilityState.instance.removeListener(_onApplicationStateChanged);
    super.dispose();
  }

  Future<void> _loadBackendDrives() async {
    try {
      final appsResponse = await _driveService.getMyApplicationsPaginated(page: 1, limit: 100);
      final apps = appsResponse.items;
      final inReview = apps.where((a) {
        final st = a['status'];
        final outcome = (st is Map ? st['final_outcome'] : '')?.toString().toLowerCase() ?? '';
        return outcome.contains('progress') || outcome.contains('review') || outcome.contains('pending');
      }).length;

      final interviews = await InterviewService().getMyInterviews();
      final nextIntv = interviews.isNotEmpty ? interviews.first : null;

      final drives = await _driveService.getPublishedDrives();
      final announcements = await _driveService.getBroadcastAnnouncements();

      if (mounted) {
        setState(() {
          _appliedCount = appsResponse.totalCount > 0 ? appsResponse.totalCount : apps.length;
          _inReviewCount = inReview;
          _interviewsCount = interviews.isNotEmpty ? interviews.length : MockData.interviewSlots.where((s) => s.isBooked).length;
          _upcomingInterview = nextIntv;
          _broadcasts = announcements;
          _recommendedDrives = drives
              .cast<Map<String, dynamic>>()
              .where((d) {
                final id = (d['drive_id'] ?? d['listing_id'] ?? '').toString();
                final company = (d['company_name'] ?? d['company'] ?? '').toString();
                return !ApplicationVisibilityState.instance.isApplied(id, company);
              })
              .take(5)
              .toList();
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoadingJobs = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final isSmallScreen = screenWidth < 380;
    final contentPadding = isSmallScreen ? 12.0 : 16.0;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(contentPadding, contentPadding, contentPadding, 120.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Key Metrics Grid (Interactive)
          Row(
            children: [
              _buildStatCard(
                context: context,
                title: 'Applications',
                value: '$_appliedCount',
                subtitle: '$_inReviewCount In Review',
                icon: Icons.assignment_outlined,
                color: AppColors.lightPrimary,
                onTap: widget.onViewApplications ?? widget.onViewAllJobs,
              ),
              SizedBox(width: isSmallScreen ? 6 : 8),
              _buildStatCard(
                context: context,
                title: 'Interviews',
                value: '$_interviewsCount',
                subtitle: _interviewsCount > 0 ? 'Scheduled' : 'None',
                icon: Icons.calendar_today_rounded,
                color: AppColors.success,
                onTap: () => _showUpcomingInterviewDetailsSheet(context),
              ),
              SizedBox(width: isSmallScreen ? 6 : 8),
              _buildStatCard(
                context: context,
                title: 'Active Drives',
                value: _recommendedDrives.isNotEmpty ? '${_recommendedDrives.length}' : '0',
                subtitle: _recommendedDrives.isNotEmpty ? 'Open For You' : 'None Active',
                icon: Icons.bolt_rounded,
                color: AppColors.warning,
                onTap: widget.onViewAllJobs,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Upcoming Interview Alert Card
          if (_upcomingInterview != null || MockData.interviewSlots.where((s) => s.isBooked).isNotEmpty) ...[
            Card(
              color: isDark ? AppColors.darkSurfaceContainerLow : AppColors.lightSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: isDark
                      ? AppColors.darkPrimaryContainer.withValues(alpha: 0.6)
                      : AppColors.lightPrimary.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: Padding(
                padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: AppColors.success.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.videocam_rounded,
                                  color: AppColors.success,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Upcoming Interview',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    fontSize: isSmallScreen ? 13 : 15,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.successLightBg,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Confirmed',
                            style: TextStyle(
                              color: AppColors.success,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _upcomingInterview?['interview_type'] ??
                          (MockData.interviewSlots.isNotEmpty
                              ? MockData.interviewSlots.firstWhere((s) => s.isBooked, orElse: () => MockData.interviewSlots.first).position
                              : 'Technical Interview'),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: isSmallScreen ? 13 : 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.access_time_rounded, size: 15, color: AppColors.lightTextSecondary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _upcomingInterview != null
                                ? '${_upcomingInterview?['date'] ?? ''} • ${_upcomingInterview?['time'] ?? ''}'
                                : (MockData.interviewSlots.isNotEmpty
                                    ? MockData.interviewSlots.firstWhere((s) => s.isBooked, orElse: () => MockData.interviewSlots.first).time
                                    : ''),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: isSmallScreen ? 11 : 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: widget.onViewMessages,
                            icon: const Icon(Icons.video_call_rounded, size: 18),
                            label: const Text('Join Video Call'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            Card(
              color: isDark ? AppColors.darkSurfaceContainerLow : AppColors.lightSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                ),
              ),
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.event_available_rounded, color: AppColors.lightPrimary, size: 24),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('No Upcoming Interviews', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          SizedBox(height: 2),
                          Text('Campus placement interviews scheduled by recruiters will appear here.', style: TextStyle(fontSize: 11, color: AppColors.lightTextSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_broadcasts.isNotEmpty) ...[
            const SizedBox(height: 20),
            _buildBroadcastSection(context, isDark),
          ],
          const SizedBox(height: 24),

          // Recommended Jobs Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Recommended for You',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontSize: isSmallScreen ? 16 : 18,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              TextButton(
                onPressed: widget.onViewAllJobs,
                child: Text(
                  'View Marketplace →',
                  style: TextStyle(fontSize: isSmallScreen ? 11 : 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Jobs List / Empty State
          _isLoadingJobs
              ? Column(
                  children: List.generate(
                    3,
                    (_) => const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: DriveCardSkeleton(),
                    ),
                  ),
                )
              : _recommendedDrives.isNotEmpty
                  ? Column(
                      children: [
                        for (int index = 0; index < _recommendedDrives.length; index++) ...[
                          if (index > 0) const SizedBox(height: 12),
                          Builder(
                            builder: (context) {
                              final drive = _recommendedDrives[index];
                              final rawMin = drive['ctc_min'];
                              final rawMax = drive['ctc_max'];
                              final ctcMin = (rawMin != null ? (double.tryParse(rawMin.toString()) ?? 6.0) : 6.0).round();
                              final ctcMax = (rawMax != null ? (double.tryParse(rawMax.toString()) ?? 12.0) : 12.0).round();
                              final title = drive['interview_job'] ?? drive['drive_title'] ?? 'Placement Listing';
                              final company = drive['company_name'] ?? drive['company'] ?? 'Company';
                              final jobType = (drive['mode'] ?? 'Full-Time').toString().replaceAll('_', ' ');

                              return Container(
                                key: ValueKey(drive['drive_id'] ?? drive['listing_id'] ?? index),
                                decoration: BoxDecoration(
                                  color: isDark ? AppColors.darkSurfaceContainerLow : AppColors.lightSurface,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                                  ),
                                ),
                                child: InkWell(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => CompanyDetailScreen(
                                          listingId: (drive['drive_id'] ?? drive['listing_id']).toString(),
                                          initialData: drive,
                                          onNavigateToProfile: () => widget.onViewApplications?.call(),
                                        ),
                                      ),
                                    );
                                  },
                                  borderRadius: BorderRadius.circular(16),
                                  child: Padding(
                                    padding: EdgeInsets.all(isSmallScreen ? 12 : 14),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              width: isSmallScreen ? 38 : 44,
                                              height: isSmallScreen ? 38 : 44,
                                              decoration: BoxDecoration(
                                                color: isDark ? AppColors.darkSurfaceContainerHigh : AppColors.lightSurfaceContainer,
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: Center(
                                                child: Icon(
                                                  Icons.business_rounded,
                                                  color: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                                                  size: isSmallScreen ? 20 : 24,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    title,
                                                    style: theme.textTheme.titleMedium?.copyWith(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: isSmallScreen ? 14 : 15,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    company,
                                                    style: theme.textTheme.bodyMedium?.copyWith(
                                                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                                      fontSize: isSmallScreen ? 12 : 13,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Icon(
                                              Icons.arrow_forward_ios_rounded,
                                              size: 14,
                                              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: isDark
                                                    ? AppColors.darkSurfaceContainerHigh
                                                    : AppColors.lightSurfaceContainerLow,
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                jobType,
                                                style: theme.textTheme.labelMedium?.copyWith(
                                                  fontSize: isSmallScreen ? 10 : 11,
                                                ),
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: AppColors.successLightBg,
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                '₹${ctcMin % 1 == 0 ? ctcMin.toInt() : ctcMin} - ₹${ctcMax % 1 == 0 ? ctcMax.toInt() : ctcMax} LPA',
                                                style: theme.textTheme.labelMedium?.copyWith(
                                                  color: AppColors.success,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: isSmallScreen ? 10 : 11,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ],
                    )
                  : Card(
                      color: isDark ? AppColors.darkSurfaceContainerLow : AppColors.lightSurface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                        ),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Icon(Icons.business_center_outlined, size: 48, color: AppColors.lightTextSecondary),
                            SizedBox(height: 12),
                            Text(
                              'No Companies Registered Yet',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'No recruiters or companies have posted job openings yet. New campus placement drives will appear here once registered.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: AppColors.lightTextSecondary),
                            ),
                          ],
                        ),
                      ),
                    ),
          const SizedBox(height: 110),
        ],
      ),
    );
  }

  void _showUpcomingInterviewDetailsSheet(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Interview Details',
                      style: theme.textTheme.headlineSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.successLightBg,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      'Confirmed',
                      style: TextStyle(
                        color: AppColors.success,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.work_outline_rounded, color: AppColors.lightPrimary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Senior Frontend Engineer',
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('TechCorp Solutions • San Francisco, CA', style: theme.textTheme.bodyMedium),
                      const Divider(height: 24),
                      Row(
                        children: [
                          const Icon(Icons.access_time_rounded, color: AppColors.lightPrimary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Tomorrow, 10:00 AM - 10:45 AM (EST)',
                              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      Row(
                        children: [
                          const Icon(Icons.videocam_outlined, color: AppColors.lightPrimary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Format: TalentLOQ HD Video Interview',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onViewMessages();
                },
                icon: const Icon(Icons.video_call_rounded),
                label: const Text('Join Video Call Now'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onViewMessages();
                },
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                label: const Text('Message Recruiter'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required BuildContext context,
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // Dynamic sizing via MediaQuery
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 380;

    return Expanded(
      child: Card(
        color: isDark ? AppColors.darkSurfaceContainerLow : AppColors.lightSurface,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isSmallScreen ? 6 : 10,
              vertical: isSmallScreen ? 8 : 12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: isSmallScreen ? 16 : 20),
                SizedBox(height: isSmallScreen ? 4 : 8),
                Text(
                  value,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: isSmallScreen ? 16 : 20,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: isSmallScreen ? 10 : 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: isSmallScreen ? 9 : 10,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBroadcastSection(BuildContext context, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.campaign_rounded, color: AppColors.warning, size: 20),
            SizedBox(width: 8),
            Text(
              'Official Campus Broadcasts',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ..._broadcasts.take(3).map((b) {
          final title = (b['title'] ?? 'Announcement').toString();
          final content = (b['content'] ?? b['message'] ?? '').toString();
          final date = (b['created_at'] ?? '').toString();
          final dateLabel = date.length > 10 ? date.substring(0, 10) : date;
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: AppColors.warning.withValues(alpha: 0.35),
                width: 1.2,
              ),
            ),
            color: isDark ? AppColors.darkSurfaceContainerLow : Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (dateLabel.isNotEmpty)
                        Text(
                          dateLabel,
                          style: const TextStyle(fontSize: 10, color: AppColors.lightTextSecondary),
                        ),
                    ],
                  ),
                  if (content.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      content,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}
