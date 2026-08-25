import 'package:flutter/material.dart';
import '../../mock_data/mock_data.dart';
import '../../models/models.dart';
import '../../theme/app_colors.dart';
import '../../widgets/skeleton_widgets.dart';
import '../../services/recruiter_service.dart';
import 'add_company_form.dart';
import 'applicants_screen.dart';
import 'my_listings_screen.dart';
import 'recruiter_dashboard_screen.dart';

class CompanyPortalScreen extends StatefulWidget {
  final Function(Candidate) onSelectCandidate;
  final VoidCallback onScheduleInterview;

  const CompanyPortalScreen({
    super.key,
    required this.onSelectCandidate,
    required this.onScheduleInterview,
  });

  @override
  State<CompanyPortalScreen> createState() => _CompanyPortalScreenState();
}

class _CompanyPortalScreenState extends State<CompanyPortalScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final RecruiterService _recruiterService = RecruiterService();
  bool _isLoadingListings = false;
  List<dynamic> _realListings = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _fetchListings();
  }

  Future<void> _fetchListings() async {
    setState(() => _isLoadingListings = true);
    final results = await _recruiterService.getRecruiterListings();
    setState(() {
      _realListings = results;
      _isLoadingListings = false;
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _openApplicants(Map<String, dynamic> item) {
    final listingId = (item['listing_id'] ?? item['drive_id'] ?? '').toString();
    final companyName = (item['company_name'] ?? 'Company').toString();
    final interviewJob = (item['interview_job'] ?? item['drive_title'] ?? 'Role').toString();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ApplicantsScreen(
          listingId: listingId,
          companyName: companyName,
          interviewJob: interviewJob,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Modal & Alert Dialog Handlers
  // ---------------------------------------------------------------------------

  String _formatCtcValue(dynamic val) {
    if (val == null) return '';
    final str = val.toString().trim();
    if (str.isEmpty) return '';
    final numVal = double.tryParse(str.replaceAll(RegExp(r'[^0-9.]'), ''));
    if (numVal != null && numVal > 0) {
      if (numVal >= 100000) {
        final lpa = numVal / 100000;
        return '${lpa % 1 == 0 ? lpa.toInt() : lpa.toStringAsFixed(1)} LPA';
      } else {
        return '${numVal % 1 == 0 ? numVal.toInt() : numVal.toStringAsFixed(1)} LPA';
      }
    }
    return str.contains('LPA') ? str : '$str LPA';
  }

  void _showCompanyDetailsDialog(BuildContext context, Map<String, dynamic> item) {
    final companyName = (item['company_name'] ?? item['company'] ?? 'Company Name').toString();
    final jobTitle = (item['interview_job'] ?? item['drive_title'] ?? item['title'] ?? 'Placement Drive').toString();
    final companyEmail = (item['company_email'] ?? 'Not specified').toString();
    final location = (item['location'] ?? item['interview_venue'] ?? 'On Campus').toString();
    final minCgpa = (item['cgpa_criteria'] ?? item['min_cgpa'] ?? 'N/A').toString();
    final mode = (item['mode'] ?? 'On Campus').toString().replaceAll('_', ' ').toUpperCase();
    final empType = (item['employment_type'] ?? 'Full Time').toString().replaceAll('_', ' ').toUpperCase();
    final description = (item['description'] ?? 'No description provided.').toString();
    final statusStr = (item['status'] ?? 'published').toString().toUpperCase();
    final reqsList = (item['required_skills'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final prefList = (item['preferred_skills'] as List?)?.map((e) => e.toString()).toList() ?? [];
    
    final rawMin = item['ctc_min'];
    final rawMax = item['ctc_max'];
    final ctcMin = rawMin != null ? _formatCtcValue(rawMin) : null;
    final ctcMax = rawMax != null ? _formatCtcValue(rawMax) : null;
    final stipend = item['stipend'] != null ? '₹${item['stipend']}/mo' : null;
    final bond = (item['bond_details'] ?? item['bond_time'] ?? 'None').toString();
    final schedule = (item['schedule_datetime'] ?? item['interview_datetime'] ?? 'To Be Announced').toString();
    final deadline = (item['registration_deadline'] ?? 'Open').toString();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) {
        final theme = Theme.of(bottomSheetContext);
        final isDark = theme.brightness == Brightness.dark;

        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkBackground : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(bottomSheetContext).viewInsets.bottom,
          ),
          child: DraggableScrollableSheet(
            initialChildSize: 0.75,
            minChildSize: 0.4,
            maxChildSize: 0.92,
            expand: false,
            builder: (sheetContext, scrollController) {
              return Column(
                children: [
                  // Top Drag Grab Handle
                  const SizedBox(height: 12),
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Header Bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: AppColors.lightPrimary,
                          radius: 22,
                          child: Text(
                            companyName.isNotEmpty ? companyName[0].toUpperCase() : 'C',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                companyName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                jobTitle,
                                style: const TextStyle(fontSize: 13, color: AppColors.lightPrimary, fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.successLightBg,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            statusStr == 'PUBLISHED' ? 'Published' : statusStr,
                            style: const TextStyle(color: AppColors.success, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(bottomSheetContext),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 20, thickness: 0.8),

                  // Scrollable Details List
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                      children: [
                        // Key Specs Container Card
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.darkSurface : AppColors.lightBackground,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                            ),
                          ),
                          child: Column(
                            children: [
                              _buildDialogInfoRow(Icons.location_on_outlined, 'Location / Venue', location, isDark: isDark),
                              const Divider(height: 14, thickness: 0.5),
                              _buildDialogInfoRow(Icons.email_outlined, 'Company Email', companyEmail, isDark: isDark),
                              const Divider(height: 14, thickness: 0.5),
                              _buildDialogInfoRow(Icons.school_outlined, 'Min CGPA Required', minCgpa, isDark: isDark),
                              const Divider(height: 14, thickness: 0.5),
                              _buildDialogInfoRow(Icons.work_outline, 'Mode & Type', '$mode • $empType', isDark: isDark),
                              if (ctcMin != null || ctcMax != null || stipend != null) ...[
                                const Divider(height: 14, thickness: 0.5),
                                _buildDialogInfoRow(
                                  Icons.payments_outlined,
                                  'Compensation Package',
                                  ctcMax != null ? '$ctcMin - $ctcMax' : (stipend ?? ctcMin ?? 'As per policy'),
                                  isDark: isDark,
                                ),
                              ],
                              const Divider(height: 14, thickness: 0.5),
                              _buildDialogInfoRow(Icons.calendar_month_outlined, 'Interview Schedule', schedule, isDark: isDark),
                              const Divider(height: 14, thickness: 0.5),
                              _buildDialogInfoRow(Icons.timer_outlined, 'Registration Deadline', deadline, isDark: isDark),
                              if (bond != 'None' && bond.isNotEmpty) ...[
                                const Divider(height: 14, thickness: 0.5),
                                _buildDialogInfoRow(Icons.verified_user_outlined, 'Service Bond', bond, isDark: isDark),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Overview Section
                        const Text(
                          'Company & Drive Overview',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.darkSurfaceContainerLow : AppColors.lightSurfaceContainerLow,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            description,
                            style: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.lightTextSecondary),
                          ),
                        ),

                        // Required Skills
                        if (reqsList.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          const Text(
                            'Required Skills',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: reqsList.map((skill) {
                              return Chip(
                                avatar: const Icon(Icons.check_circle_outline_rounded, size: 14, color: AppColors.lightPrimary),
                                label: Text(skill, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                                backgroundColor: AppColors.primaryLightBg,
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              );
                            }).toList(),
                          ),
                        ],

                        // Preferred Skills
                        if (prefList.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          const Text(
                            'Preferred Skills',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: prefList.map((skill) {
                              return Chip(
                                avatar: const Icon(Icons.star_outline_rounded, size: 14, color: AppColors.success),
                                label: Text(skill, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                                backgroundColor: AppColors.successLightBg,
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              );
                            }).toList(),
                          ),
                        ],
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(bottomSheetContext);
                            _openApplicants(item);
                          },
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size.fromHeight(44),
                          ),
                          icon: const Icon(Icons.people_alt_rounded, size: 18),
                          label: const Text('View All Applicants for this Drive'),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildDialogInfoRow(IconData icon, String label, String value, {bool isDark = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurfaceContainerHigh : AppColors.primaryLightBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: AppColors.lightPrimary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.lightTextSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                  ),
                  softWrap: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateJobModal() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddCompanyForm(onSuccess: _fetchListings),
      ),
    );
  }

  void _showPostAnnouncementModal() {
    final titleCtrl = TextEditingController();
    final contentCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(modalContext).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Publish Broadcast Announcement', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('This message will be instantly visible to all students on campus.', style: TextStyle(fontSize: 12, color: AppColors.lightTextSecondary)),
              const SizedBox(height: 14),
              TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Announcement Title')),
              const SizedBox(height: 10),
              TextField(controller: contentCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'Announcement Details')),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    if (titleCtrl.text.trim().isEmpty) return;

                    final ann = Announcement(
                      id: 'ann-${DateTime.now().millisecondsSinceEpoch}',
                      title: titleCtrl.text.trim(),
                      content: contentCtrl.text.trim(),
                      author: 'Placement Officer',
                      createdAt: 'Just Now',
                    );

                    setState(() {
                      MockData.announcements.insert(0, ann);
                    });

                    await _recruiterService.postAnnouncement(titleCtrl.text.trim(), contentCtrl.text.trim());

                    if (!modalContext.mounted) return;
                    Navigator.pop(modalContext);
                    ScaffoldMessenger.of(modalContext).showSnackBar(
                      const SnackBar(
                        content: Text('Broadcast announcement published to student feed!'),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  },
                  icon: const Icon(Icons.campaign_rounded),
                  label: const Text('Publish Broadcast'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showLogOutcomeModal(InterviewSlot slot) {
    String selectedOutcome = 'passed';
    final feedbackCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20, right: 20, top: 20,
                bottom: MediaQuery.of(modalContext).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Log Interview Outcome - ${slot.candidateName}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('${slot.position} • ${slot.type}', style: const TextStyle(fontSize: 12, color: AppColors.lightTextSecondary)),
                  const SizedBox(height: 14),
                  const Text('Interview Outcome Status:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: selectedOutcome,
                    items: const [
                      DropdownMenuItem(value: 'passed', child: Text('Passed - Recommend Offer')),
                      DropdownMenuItem(value: 'next_round', child: Text('Next Round - Technical Assessment')),
                      DropdownMenuItem(value: 'failed', child: Text('Failed - Send Regret Note')),
                    ],
                    onChanged: (val) {
                      if (val != null) setModalState(() => selectedOutcome = val);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(controller: feedbackCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Feedback & Review Notes')),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        setState(() {
                          final idx = MockData.interviewSlots.indexWhere((s) => s.id == slot.id);
                          if (idx != -1) {
                            MockData.interviewSlots[idx] = InterviewSlot(
                              id: slot.id,
                              date: slot.date,
                              time: slot.time,
                              candidateName: slot.candidateName,
                              position: slot.position,
                              type: slot.type,
                              isBooked: slot.isBooked,
                              status: selectedOutcome,
                              feedback: feedbackCtrl.text.trim(),
                            );
                          }
                        });

                        await _recruiterService.logInterviewOutcome(slot.id, selectedOutcome, feedbackCtrl.text.trim());

                        if (!modalContext.mounted) return;
                        Navigator.pop(modalContext);
                        ScaffoldMessenger.of(modalContext).showSnackBar(
                          SnackBar(
                            content: Text('Outcome logged as ${selectedOutcome.toUpperCase()} for ${slot.candidateName}'),
                            backgroundColor: selectedOutcome == 'passed' ? AppColors.success : AppColors.warning,
                          ),
                        );
                      },
                      icon: const Icon(Icons.task_alt_rounded),
                      label: const Text('Save Outcome'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Screen Builder
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      children: [
        // Clean Header & Action Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
            border: Border(
              bottom: BorderSide(
                color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.business_center_rounded, color: AppColors.lightPrimary, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Recruiter Control Center',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.dashboard_rounded, size: 20),
                tooltip: 'Dashboard Stats',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RecruiterDashboardScreen()),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.list_alt_rounded, size: 20),
                tooltip: 'My Company Listings',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MyListingsScreen()),
                ),
              ),
            ],
          ),
        ),

        // Perfectly Aligned TabBar
        Container(
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorSize: TabBarIndicatorSize.label,
            indicatorColor: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
            labelColor: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
            unselectedLabelColor: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 12),
            labelPadding: const EdgeInsets.symmetric(horizontal: 16),
            tabs: const [
              Tab(icon: Icon(Icons.work_outline_rounded, size: 20), text: 'Job Postings'),
              Tab(icon: Icon(Icons.how_to_reg_rounded, size: 20), text: 'Validation'),
              Tab(icon: Icon(Icons.calendar_month_rounded, size: 20), text: 'Interviews'),
              Tab(icon: Icon(Icons.campaign_outlined, size: 20), text: 'Broadcasts'),
            ],
          ),
        ),

        // Tab Body Content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildJobPostingsTab(context, isDark),
              _buildValidationDashboardTab(context, isDark),
              _buildInterviewSchedulingTab(context, isDark),
              _buildBroadcastsAndTicketsTab(context, isDark),
            ],
          ),
        ),
      ],
    );
  }

  // Tab 1: Job Postings & Parser Agent View
  // ---------------------------------------------------------------------------
  Widget _buildJobPostingsTab(BuildContext context, bool isDark) {
    final hasRealJobs = _realListings.isNotEmpty;

    return RefreshIndicator(
      onRefresh: _fetchListings,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Campus Job & Drives',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Database-Driven Recruiter Listings',
                        style: TextStyle(fontSize: 11, color: AppColors.success, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _showCreateJobModal,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Post Listing', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_isLoadingListings)
              Column(
                children: List.generate(
                  3,
                  (_) => const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: DriveCardSkeleton(),
                  ),
                ),
              )
            else if (hasRealJobs) ...[
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _realListings.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final item = Map<String, dynamic>.from(_realListings[index] as Map);
                  final companyName = (item['company_name'] ?? 'Company').toString();
                  final title = (item['interview_job'] ?? item['drive_title'] ?? item['title'] ?? 'Placement Drive').toString();
                  final location = (item['location'] ?? item['interview_venue'] ?? 'On Campus').toString();
                  final reqsList = (item['required_skills'] as List?)?.map((e) => e.toString()).toList() ?? [];
                  final rawStatus = (item['status'] ?? 'published').toString();
                  final statusText = rawStatus.toUpperCase();
                  final isPublished = rawStatus.toLowerCase() == 'published' || rawStatus.toLowerCase() == 'active';

                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _showCompanyDetailsDialog(context, item),
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
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isPublished ? AppColors.successLightBg : AppColors.warning.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    statusText,
                                    style: TextStyle(
                                      color: isPublished ? AppColors.success : AppColors.warning,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    '$companyName • $location',
                                    style: const TextStyle(fontSize: 12, color: AppColors.lightTextSecondary),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const Row(
                                  children: [
                                    Text('Tap for details', style: TextStyle(fontSize: 10, color: AppColors.lightPrimary, fontWeight: FontWeight.w600)),
                                    SizedBox(width: 2),
                                    Icon(Icons.info_outline_rounded, size: 12, color: AppColors.lightPrimary),
                                  ],
                                ),
                              ],
                            ),
                            if (reqsList.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              const Divider(height: 1),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: reqsList.map((req) {
                                  return Chip(
                                    label: Text(req, style: const TextStyle(fontSize: 10)),
                                    backgroundColor: AppColors.primaryLightBg,
                                    visualDensity: VisualDensity.compact,
                                  );
                                }).toList(),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () => _openApplicants(item),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  icon: const Icon(Icons.people_rounded, size: 14),
                                  label: const Text('Manage Applicants', style: TextStyle(fontSize: 11)),
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
            ] else ...[
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'No active job postings found in database. Click "Post Listing" to publish a drive.',
                      style: TextStyle(color: AppColors.lightTextSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 2: Candidate Review & Validation Dashboard
  // ---------------------------------------------------------------------------
  Widget _buildValidationDashboardTab(BuildContext context, bool isDark) {
    return const SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Candidate Validation Dashboard', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          SizedBox(height: 2),
          Text('Review AI Match Scores, Skill Gaps, & Student Approval Gate verification.', style: TextStyle(fontSize: 11, color: AppColors.lightTextSecondary)),
          SizedBox(height: 14),
          Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'No candidate applications submitted yet.',
                  style: TextStyle(color: AppColors.lightTextSecondary),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 3: Interview Selection, Scheduling & Outcome Logging
  // ---------------------------------------------------------------------------
  Widget _buildInterviewSchedulingTab(BuildContext context, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text('Scheduled Campus Interviews', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: widget.onScheduleInterview,
                icon: const Icon(Icons.add_task_rounded, size: 18),
                label: const Text('Schedule'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'No interviews scheduled yet. Select a candidate from your active drives to schedule an interview.',
                  style: TextStyle(color: AppColors.lightTextSecondary),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 4: Broadcast Announcements & Support Tickets
  // ---------------------------------------------------------------------------
  Widget _buildBroadcastsAndTicketsTab(BuildContext context, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text('Campus Broadcasts', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _showPostAnnouncementModal,
                icon: const Icon(Icons.campaign_rounded, size: 18),
                label: const Text('Broadcast'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: Text(
                  'No campus broadcasts published yet. Click "Broadcast" to create an announcement.',
                  style: TextStyle(color: AppColors.lightTextSecondary, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text('Student Support Tickets & AI Disputes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: Text(
                  'No student support tickets or AI disputes logged.',
                  style: TextStyle(color: AppColors.lightTextSecondary, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }


}
