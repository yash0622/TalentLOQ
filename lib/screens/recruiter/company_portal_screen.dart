import 'package:flutter/material.dart';
import '../../mock_data/mock_data.dart';
import '../../models/models.dart';
import '../../theme/app_colors.dart';
import '../../widgets/skeleton_widgets.dart';
import '../../widgets/app_avatar.dart';
import '../../services/recruiter_service.dart';
import '../../services/interview_service.dart';
import 'applicants_screen.dart';
import 'matching_students_screen.dart';
import 'offer_setup_modal.dart';
import 'candidate_detail_screen.dart';
import '../../widgets/recruiter_ai_insight_modal.dart';

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
  bool _isLoadingBroadcasts = false;
  List<Map<String, dynamic>> _broadcasts = [];
  bool _isLoadingValidation = false;
  List<Map<String, dynamic>> _validationApplicants = [];
  List<Map<String, dynamic>> _allValidationApplicants = [];
  String _selectedValidationFilter = 'all';
  bool _isLoadingInterviews = false;
  List<Map<String, dynamic>> _scheduledInterviews = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_handleTabChange);
    _fetchListings();
    _fetchBroadcasts();
    _fetchValidationApplicants();
    _fetchScheduledInterviews();
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging) return;
    if (_tabController.index == 1) {
      _fetchValidationApplicants();
    } else if (_tabController.index == 2) {
      _fetchScheduledInterviews();
    } else if (_tabController.index == 3) {
      _fetchBroadcasts();
    }
  }

  Future<void> _fetchListings() async {
    setState(() => _isLoadingListings = true);
    final list = await _recruiterService.getRecruiterListings();
    if (mounted) {
      setState(() {
        _realListings = list;
        _isLoadingListings = false;
      });
    }
  }

  Future<void> _fetchBroadcasts() async {
    setState(() => _isLoadingBroadcasts = true);
    final list = await _recruiterService.getAnnouncements();
    if (mounted) {
      setState(() {
        _broadcasts = list;
        _isLoadingBroadcasts = false;
      });
    }
  }

  List<Map<String, dynamic>> _filterValidationList(List<Map<String, dynamic>> source, String filter) {
    if (filter == 'all') return source;
    return source.where((a) {
      final s = (a['validation_status'] ?? 'pending').toString().toLowerCase();
      if (filter == 'pending') return s == 'pending' || s == 'null' || s.isEmpty;
      return s == filter.toLowerCase();
    }).toList();
  }

  Candidate _applicantToCandidate(Map<String, dynamic> item) {
    final name = (item['name'] ?? item['candidate_name'] ?? 'Candidate').toString();
    final role = (item['drive_title'] ?? item['position'] ?? 'Candidate').toString();
    final studentId = (item['student_id'] ?? item['id'] ?? item['app_id'] ?? '').toString();
    final cgpaVal = double.tryParse((item['cgpa'] ?? 8.0).toString()) ?? 8.0;
    final matchVal = double.tryParse((item['match_score'] ?? 90).toString()) ?? 90.0;
    final skillsList = List<String>.from(item['skills'] ?? ['Problem Solving', 'Core CS']);
    final resume = (item['resume_link'] ?? '').toString();

    return Candidate(
      id: studentId,
      name: name,
      roleTitle: role,
      avatarUrl: '',
      location: (item['company_name'] ?? 'Campus Drive').toString(),
      experience: 'Final Year Student',
      education: (item['course'] ?? item['education'] ?? 'B.Tech CSE').toString(),
      matchScore: matchVal,
      skills: skillsList,
      bio: 'Candidate for $role at ${item['company_name'] ?? 'Company'}',
      status: (item['final_outcome'] ?? item['status'] ?? 'Under Review').toString(),
      validationStatus: (item['validation_status'] ?? 'pending').toString(),
      cgpa: cgpaVal,
      resumeUrl: resume.isNotEmpty ? resume : null,
    );
  }

  Future<void> _fetchValidationApplicants() async {
    setState(() => _isLoadingValidation = true);
    final list = await _recruiterService.getValidationApplicants();
    if (mounted) {
      setState(() {
        _allValidationApplicants = list;
        _validationApplicants = _filterValidationList(list, _selectedValidationFilter);
        _isLoadingValidation = false;
      });
    }
  }

  Future<void> _fetchScheduledInterviews() async {
    setState(() => _isLoadingInterviews = true);
    final list = await InterviewService().getMyInterviews();
    if (mounted) {
      setState(() {
        _scheduledInterviews = list;
        _isLoadingInterviews = false;
      });
    }
  }

  Future<void> _setValidationStatus(String appId, String newStatus) async {
    // Optimistic update
    setState(() {
      for (var a in _allValidationApplicants) {
        if ((a['app_id'] ?? a['id'] ?? '').toString() == appId) {
          a['validation_status'] = newStatus;
        }
      }
      _validationApplicants = _filterValidationList(_allValidationApplicants, _selectedValidationFilter);
    });

    final ok = await _recruiterService.updateApplicationValidation(appId, newStatus);
    if (ok) {
      _fetchValidationApplicants();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Candidate application marked as ${newStatus.toUpperCase()}.'),
            backgroundColor: newStatus == 'valid' ? AppColors.success : AppColors.error,
          ),
        );
      }
    } else {
      _fetchValidationApplicants();
    }
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

  void _openMatchingStudents(Map<String, dynamic> item) {
    final driveId = (item['drive_id'] ?? item['listing_id'] ?? '').toString();
    final companyName = (item['company_name'] ?? 'Company').toString();
    final driveTitle = (item['drive_title'] ?? item['interview_job'] ?? 'Role').toString();
    final reqSkills = List<String>.from(item['extracted_required_skills'] ?? item['required_skills'] ?? []);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MatchingStudentsScreen(
          driveId: driveId,
          companyName: companyName,
          driveTitle: driveTitle,
          requiredSkills: reqSkills,
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
        return '₹${lpa % 1 == 0 ? lpa.toInt() : lpa.toStringAsFixed(1)} LPA';
      } else {
        return '₹${numVal % 1 == 0 ? numVal.toInt() : numVal.toStringAsFixed(1)} LPA';
      }
    }
    final cleanStr = str.replaceAll('₹', '').trim();
    return cleanStr.contains('LPA') ? '₹$cleanStr' : '₹$cleanStr LPA';
  }

  void _showCompanyDetailsDialog(BuildContext context, Map<String, dynamic> item) {
    final currentItem = Map<String, dynamic>.from(item);
    final driveId = (item['drive_id'] ?? item['listing_id'] ?? '').toString();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) {
        final theme = Theme.of(bottomSheetContext);
        final isDark = theme.brightness == Brightness.dark;

        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            // If full description or skills are missing, lazily fetch full drive detail
            if (driveId.isNotEmpty &&
                ((currentItem['description'] == null || currentItem['description'].toString().trim().isEmpty) ||
                 (currentItem['required_skills'] == null || (currentItem['required_skills'] as List).isEmpty))) {
              _recruiterService.getDriveDetail(driveId).then((fullDoc) {
                if (fullDoc != null && modalContext.mounted) {
                  setModalState(() {
                    currentItem.addAll(fullDoc);
                  });
                }
              });
            }

            final companyName = (currentItem['company_name'] ?? currentItem['company'] ?? 'Company Name').toString();
            final jobTitle = (currentItem['interview_job'] ?? currentItem['drive_title'] ?? currentItem['title'] ?? 'Placement Drive').toString();
            final companyEmail = (currentItem['company_email'] ?? 'Not specified').toString();
            final location = (currentItem['location'] ?? currentItem['interview_venue'] ?? 'On Campus').toString();
            final minCgpa = (currentItem['cgpa_criteria'] ?? currentItem['min_cgpa'] ?? 'N/A').toString();
            final mode = (currentItem['mode'] ?? 'On Campus').toString().replaceAll('_', ' ').toUpperCase();
            final empType = (currentItem['employment_type'] ?? 'Full Time').toString().replaceAll('_', ' ').toUpperCase();
            final rawDesc = (currentItem['description'] ?? currentItem['job_description'] ?? '').toString().trim();
            final description = rawDesc.isNotEmpty ? rawDesc : 'No description provided.';
            final statusStr = (currentItem['status'] ?? 'published').toString().toUpperCase();
            final reqsList = (currentItem['required_skills'] as List?)?.map((e) => e.toString()).toList() ?? [];
            final prefList = (currentItem['preferred_skills'] as List?)?.map((e) => e.toString()).toList() ?? [];
            
            final rawMin = currentItem['ctc_min'];
            final rawMax = currentItem['ctc_max'];
            final ctcMin = rawMin != null ? _formatCtcValue(rawMin) : null;
            final ctcMax = rawMax != null ? _formatCtcValue(rawMax) : null;
            final stipend = currentItem['stipend'] != null ? '₹${currentItem['stipend']}/mo' : null;
            final bond = (currentItem['bond_details'] ?? currentItem['bond_time'] ?? 'None').toString();
            final schedule = (currentItem['schedule_datetime'] ?? currentItem['interview_datetime'] ?? 'To Be Announced').toString();
            final deadline = (currentItem['registration_deadline'] ?? 'Open').toString();

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
                                _openApplicants(currentItem);
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

                    final success = await _recruiterService.postAnnouncement(titleCtrl.text.trim(), contentCtrl.text.trim());
                    if (success) {
                      _fetchBroadcasts();
                    }

                    if (!modalContext.mounted) return;
                    Navigator.pop(modalContext);
                    ScaffoldMessenger.of(modalContext).showSnackBar(
                      SnackBar(
                        content: Text(success ? 'Broadcast announcement published!' : 'Failed to publish broadcast.'),
                        backgroundColor: success ? AppColors.success : AppColors.error,
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

  void showLogOutcomeModal(InterviewSlot slot) {
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
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _openMatchingStudents(item),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    icon: const Icon(Icons.person_search_rounded, size: 14),
                                    label: const Text(
                                      'Matching Candidates',
                                      style: TextStyle(fontSize: 11),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () => _openApplicants(item),
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    icon: const Icon(Icons.people_rounded, size: 14),
                                    label: const Text(
                                      'Manage Applicants',
                                      style: TextStyle(fontSize: 11),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
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
    final allCount = _allValidationApplicants.length;
    final pendingCount = _allValidationApplicants.where((a) {
      final s = (a['validation_status'] ?? 'pending').toString().toLowerCase();
      return s == 'pending' || s == 'null' || s.isEmpty;
    }).length;
    final validCount = _allValidationApplicants.where((a) {
      return (a['validation_status'] ?? '').toString().toLowerCase() == 'valid';
    }).length;
    final notValidCount = _allValidationApplicants.where((a) {
      return (a['validation_status'] ?? '').toString().toLowerCase() == 'not_valid';
    }).length;

    final displayedList = _validationApplicants;

    return RefreshIndicator(
      onRefresh: _fetchValidationApplicants,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Candidate Validation Dashboard',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            const Text(
              'Review AI Match Scores, Skill Gaps, & Student Approval Gate verification.',
              style: TextStyle(fontSize: 11, color: AppColors.lightTextSecondary),
            ),
            const SizedBox(height: 14),

            // Filter Chips Row
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('all', 'All', allCount, isDark),
                  const SizedBox(width: 8),
                  _buildFilterChip('pending', 'Pending', pendingCount, isDark),
                  const SizedBox(width: 8),
                  _buildFilterChip('valid', 'Valid', validCount, isDark),
                  const SizedBox(width: 8),
                  _buildFilterChip('not_valid', 'Not Valid', notValidCount, isDark),
                ],
              ),
            ),
            const SizedBox(height: 16),

            if (_isLoadingValidation)
              Column(
                children: List.generate(
                  3,
                  (_) => const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: DriveCardSkeleton(),
                  ),
                ),
              )
            else if (displayedList.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.how_to_reg_outlined,
                          size: 44,
                          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _selectedValidationFilter == 'all'
                              ? 'No candidate applications submitted yet.'
                              : 'No ${_selectedValidationFilter.replaceAll('_', ' ')} candidates found.',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Applications submitted by students for campus drives will appear here for validation.',
                          style: TextStyle(color: AppColors.lightTextSecondary, fontSize: 11),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: displayedList.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final item = displayedList[index];
                  return _buildValidationCandidateCard(context, item, isDark);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String key, String label, int count, bool isDark) {
    final isSelected = _selectedValidationFilter == key;
    final displayLabel = key == 'not_valid' ? 'Invalid' : label;
    return FilterChip(
      selected: isSelected,
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      label: Text(
        '$displayLabel ($count)',
        style: TextStyle(
          fontSize: 11,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          color: isSelected
              ? Colors.white
              : (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
        ),
      ),
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      selectedColor: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isSelected
              ? Colors.transparent
              : (isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant),
        ),
      ),
      onSelected: (_) {
        setState(() {
          _selectedValidationFilter = key;
          _validationApplicants = _filterValidationList(_allValidationApplicants, key);
        });
      },
    );
  }

  Widget _buildValidationCandidateCard(BuildContext context, Map<String, dynamic> item, bool isDark) {
    final appId = (item['app_id'] ?? item['id'] ?? '').toString();
    final studentId = (item['student_id'] ?? '').toString();
    final driveId = (item['drive_id'] ?? '').toString();
    final candidateName = (item['name'] ?? item['candidate_name'] ?? 'Candidate').toString();
    final companyName = (item['company_name'] ?? 'Company').toString();
    final driveTitle = (item['drive_title'] ?? 'Placement Role').toString();
    final course = (item['course'] ?? item['education'] ?? 'B.Tech CSE').toString();
    final cgpa = (item['cgpa'] ?? 8.0).toString();
    final vStatus = (item['validation_status'] ?? 'pending').toString().toLowerCase();
    final currentRound = item['current_round'] ?? 1;
    final finalOutcome = (item['final_outcome'] ?? '').toString().toLowerCase();
    final skills = (item['skills'] as List?)?.map((e) => e.toString()).toList() ?? [];

    Color statusBg;
    Color statusFg;
    IconData statusIcon;
    String statusLabel;

    if (vStatus == 'valid') {
      statusBg = AppColors.successLightBg;
      statusFg = AppColors.success;
      statusIcon = Icons.verified_rounded;
      statusLabel = 'VALIDATED';
    } else if (vStatus == 'not_valid') {
      statusBg = AppColors.error.withValues(alpha: 0.12);
      statusFg = AppColors.error;
      statusIcon = Icons.cancel_rounded;
      statusLabel = 'NOT VALID';
    } else {
      statusBg = AppColors.warning.withValues(alpha: 0.12);
      statusFg = AppColors.warning;
      statusIcon = Icons.hourglass_top_rounded;
      statusLabel = 'PENDING';
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Avatar, Name, Drive, and Match Score
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AppAvatar(imageUrl: '', fallbackText: candidateName, radius: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        candidateName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '$companyName • $driveTitle',
                        style: const TextStyle(fontSize: 11, color: AppColors.lightTextSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        course,
                        style: TextStyle(
                          fontSize: 10,
                          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Badges Row: CGPA, Validation Status, Current Round, Selection
            Wrap(
              spacing: 5,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: (isDark ? AppColors.darkPrimary : AppColors.lightPrimary).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'CGPA $cgpa',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 11, color: statusFg),
                      const SizedBox(width: 3),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: statusFg,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                    ),
                  ),
                  child: Text(
                    'Round $currentRound',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (finalOutcome == 'selected')
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.successLightBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.workspace_premium_rounded, size: 11, color: AppColors.success),
                        SizedBox(width: 3),
                        Text(
                          'SELECTED',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),

            if (skills.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: skills.take(3).map((skill) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: (isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant).withValues(alpha: 0.6),
                      ),
                    ),
                    child: Text(
                      skill,
                      style: TextStyle(
                        fontSize: 9,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],

            const SizedBox(height: 8),
            Divider(height: 1, color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant),
            const SizedBox(height: 8),

            // Quick Validation Decision Actions
            if (vStatus == 'pending') ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _setValidationStatus(appId, 'not_valid'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: BorderSide(color: AppColors.error.withValues(alpha: 0.4)),
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        minimumSize: const Size(0, 30),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.close_rounded, size: 13),
                      label: const Text('Mark Invalid', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _setValidationStatus(appId, 'valid'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        minimumSize: const Size(0, 30),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.check_rounded, size: 13),
                      label: const Text('Mark Valid', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ] else if (vStatus == 'valid') ...[
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.successLightBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded, color: AppColors.success, size: 13),
                        SizedBox(width: 4),
                        Text(
                          'Verified for Drive',
                          style: TextStyle(color: AppColors.success, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () => _setValidationStatus(appId, 'not_valid'),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.close_rounded, size: 12, color: AppColors.error.withValues(alpha: 0.8)),
                          const SizedBox(width: 3),
                          Text(
                            'Mark Invalid',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.error.withValues(alpha: 0.9),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cancel_rounded, color: AppColors.error, size: 13),
                        SizedBox(width: 4),
                        Text(
                          'Marked Not Valid',
                          style: TextStyle(color: AppColors.error, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () => _setValidationStatus(appId, 'valid'),
                    borderRadius: BorderRadius.circular(6),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_rounded, size: 12, color: AppColors.success),
                          SizedBox(width: 3),
                          Text(
                            'Re-Validate',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.success,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 4),

            // Secondary Actions: Review Profile, AI Screening, Setup Offer
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () {
                      final candidate = _applicantToCandidate(item);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CandidateDetailScreen(
                            candidate: candidate,
                            onBack: () => Navigator.pop(context),
                            onScheduleInterview: widget.onScheduleInterview,
                            onSendMessage: () {},
                          ),
                        ),
                      );
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                      minimumSize: const Size(0, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.person_outline_rounded, size: 13),
                    label: const Text('Profile', style: TextStyle(fontSize: 11)),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: () {
                      RecruiterAIInsightModal.show(
                        context,
                        driveId: driveId,
                        studentId: studentId,
                        studentName: candidateName,
                        jobTitle: driveTitle,
                      );
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                      minimumSize: const Size(0, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.psychology_outlined, size: 13),
                    label: const Text('AI Screening', style: TextStyle(fontSize: 11)),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: () {
                      OfferSetupModal.show(
                        context,
                        driveId: driveId,
                        studentId: studentId,
                        candidateName: candidateName,
                        companyName: companyName,
                        roleTitle: driveTitle,
                        initialOfferData: item['offer_details'] as Map<String, dynamic>?,
                      );
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                      minimumSize: const Size(0, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: AppColors.lightPrimary,
                    ),
                    icon: const Icon(Icons.card_giftcard_rounded, size: 13),
                    label: const Text('Setup Offer', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 3: Interview Selection, Scheduling & Outcome Logging
  // ---------------------------------------------------------------------------
  Widget _buildInterviewSchedulingTab(BuildContext context, bool isDark) {
    final allSlots = <InterviewSlot>[];

    for (final m in _scheduledInterviews) {
      allSlots.add(
        InterviewSlot(
          id: (m['interview_id'] ?? m['id'] ?? m['_id'] ?? '').toString(),
          date: (m['date'] ?? 'Upcoming').toString(),
          time: (m['time'] ?? m['time_slot'] ?? 'TBD').toString(),
          candidateName: (m['candidate_name'] ?? 'Candidate').toString(),
          position: (m['interview_type'] ?? m['position'] ?? 'Interview').toString(),
          type: (m['interview_type'] ?? 'Technical').toString(),
          isBooked: true,
          status: (m['status'] ?? 'scheduled').toString(),
          feedback: (m['feedback'] ?? '').toString(),
        ),
      );
    }

    for (final s in MockData.interviewSlots) {
      if (!allSlots.any((x) => x.id == s.id)) {
        allSlots.add(s);
      }
    }

    return RefreshIndicator(
      onRefresh: _fetchScheduledInterviews,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Scheduled Interviews',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Manage interview rounds and scheduled meeting slots.',
                        style: TextStyle(fontSize: 11, color: AppColors.lightTextSecondary),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: widget.onScheduleInterview,
                  icon: const Icon(Icons.add_task_rounded, size: 16),
                  label: const Text('Schedule', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 14),

            if (_isLoadingInterviews)
              Column(
                children: List.generate(
                  2,
                  (_) => const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: DriveCardSkeleton(),
                  ),
                ),
              )
            else if (allSlots.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.calendar_month_outlined,
                          size: 44,
                          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'No interviews scheduled yet.',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Select a validated candidate to schedule their technical or HR interview slot.',
                          style: TextStyle(color: AppColors.lightTextSecondary, fontSize: 11),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: allSlots.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final slot = allSlots[index];
                  final isPassed = slot.status == 'passed';
                  final isFailed = slot.status == 'failed';

                  Color statusColor = isPassed
                      ? AppColors.success
                      : (isFailed ? AppColors.error : AppColors.warning);

                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  slot.candidateName,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  slot.status.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: statusColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${slot.position} • ${slot.type}',
                            style: const TextStyle(fontSize: 12, color: AppColors.lightTextSecondary),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const Icon(Icons.calendar_today_rounded, size: 13, color: AppColors.lightTextSecondary),
                              const SizedBox(width: 4),
                              Text(slot.date, style: const TextStyle(fontSize: 11)),
                              const SizedBox(width: 14),
                              const Icon(Icons.access_time_rounded, size: 13, color: AppColors.lightTextSecondary),
                              const SizedBox(width: 4),
                              Text(slot.time, style: const TextStyle(fontSize: 11)),
                            ],
                          ),
                          if (slot.feedback.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(8),
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: (isDark ? AppColors.darkSurface : AppColors.lightSurface),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Note: ${slot.feedback}',
                                style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => showLogOutcomeModal(slot),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  icon: const Icon(Icons.rate_review_outlined, size: 15),
                                  label: const Text('Log Outcome', style: TextStyle(fontSize: 11)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 4: Broadcast Announcements & Support Tickets
  // ---------------------------------------------------------------------------
  Widget _buildBroadcastsAndTicketsTab(BuildContext context, bool isDark) {
    return RefreshIndicator(
      onRefresh: _fetchBroadcasts,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Campus Broadcasts',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Official placement drive announcements & alerts.',
                        style: TextStyle(fontSize: 11, color: AppColors.lightTextSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _showPostAnnouncementModal,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Broadcast'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_isLoadingBroadcasts)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else if (_broadcasts.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Column(
                      children: [
                        const Icon(Icons.campaign_outlined, size: 36, color: AppColors.lightTextSecondary),
                        const SizedBox(height: 8),
                        const Text(
                          'No campus broadcasts published yet.',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Click "Broadcast" to create an announcement visible to students.',
                          style: TextStyle(color: AppColors.lightTextSecondary, fontSize: 11),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              ..._broadcasts.map((b) {
                final title = (b['title'] ?? 'Announcement').toString();
                final content = (b['content'] ?? b['message'] ?? '').toString();
                final dateStr = (b['created_at'] ?? '').toString();
                final displayDate = dateStr.length > 10 ? dateStr.substring(0, 10) : dateStr;
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppColors.warningLightBg,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.campaign_rounded, color: AppColors.warning, size: 18),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                title,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ),
                            if (displayDate.isNotEmpty)
                              Text(
                                displayDate,
                                style: const TextStyle(fontSize: 10, color: AppColors.lightTextSecondary),
                              ),
                          ],
                        ),
                        if (content.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            content,
                            style: TextStyle(
                              fontSize: 12.5,
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
      ),
    );
  }


}
