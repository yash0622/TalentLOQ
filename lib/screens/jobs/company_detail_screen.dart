import 'package:flutter/material.dart';
import '../../services/drive_service.dart';
import '../../services/application_visibility_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/pdf_viewer_widget.dart';
import '../../widgets/skeleton_widgets.dart';

class CompanyDetailScreen extends StatefulWidget {
  final String listingId;
  final Map<String, dynamic>? initialData;
  final double studentCgpa;
  final bool hasResume;
  final VoidCallback? onNavigateToProfile;

  const CompanyDetailScreen({
    super.key,
    required this.listingId,
    this.initialData,
    this.studentCgpa = 8.0,
    this.hasResume = true,
    this.onNavigateToProfile,
  });

  @override
  State<CompanyDetailScreen> createState() => _CompanyDetailScreenState();
}

class _CompanyDetailScreenState extends State<CompanyDetailScreen> {
  final DriveService _driveService = DriveService();

  bool _isLoading = true;
  Map<String, dynamic>? _detail;
  bool _hasApplied = false;
  bool _isApplying = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _detail = widget.initialData;
      _isLoading = false;
    }
    _fetchDetail();
    _checkMyStatus();
  }

  Future<void> _fetchDetail() async {
    final res = await _driveService.getDriveDetail(widget.listingId);
    if (mounted && res != null) {
      setState(() {
        _detail = res;
        _hasApplied = res['has_applied'] == true || ApplicationVisibilityState.instance.isApplied(widget.listingId);
        _isLoading = false;
      });
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _checkMyStatus() async {
    final statusMap = await _driveService.getMyDriveStatus(widget.listingId);
    if (mounted && statusMap['applied'] == true) {
      setState(() => _hasApplied = true);
    }
  }

  Future<void> _handleApply() async {
    final isEligible = _detail?['is_eligible'] ?? true;

    // 1. Resume Check
    if (!widget.hasResume) {
      final shouldRedirect = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppColors.warning),
              SizedBox(width: 8),
              Text('Resume Required'),
            ],
          ),
          content: const Text(
            'No uploaded resume found in your student profile. Please upload a resume first to apply.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Go to Resume Upload'),
            ),
          ],
        ),
      );

      if (shouldRedirect == true) {
        if (mounted) {
          widget.onNavigateToProfile?.call();
          Navigator.maybePop(context);
        }
      }
      return;
    }

    // 2. Non-blocking Eligibility Warning Dialog
    if (!isEligible) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.error_outline_rounded, color: AppColors.warning),
              SizedBox(width: 8),
              Text('Eligibility Warning'),
            ],
          ),
          content: Text(
            'You do not meet all eligibility criteria for this posting.\n\n'
            '• Min CGPA Cutoff: ${(_detail?['cgpa_criteria'] ?? _detail?['min_cgpa'] ?? 6.0)}\n'
            '• Your CGPA: ${widget.studentCgpa.toStringAsFixed(2)}\n\n'
            'Your application will record an eligibility flag. Apply anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Apply Anyway'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

    // 3. Submit Application
    setState(() => _isApplying = true);

    final res = await _driveService.applyToDrive(widget.listingId);

    setState(() => _isApplying = false);

    if (!mounted) return;

    if (res['success'] == true) {
      setState(() {
        _hasApplied = true;
        _detail?['has_applied'] = true;
        _detail?['my_application_status'] = 'applied';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Application submitted successfully!'),
          backgroundColor: AppColors.success,
        ),
      );
    } else if (res['no_resume'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message'] ?? 'Please upload a resume first.'), backgroundColor: AppColors.error),
      );
      widget.onNavigateToProfile?.call();
    } else if (res['conflict'] == true) {
      setState(() => _hasApplied = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You have already applied to this listing.'), backgroundColor: AppColors.lightPrimary),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message'] ?? 'Could not submit application.'), backgroundColor: AppColors.error),
      );
    }
  }

  String _formatCtcValue(dynamic val) {
    if (val == null) return '';
    final str = val.toString().trim();
    if (str.isEmpty) return '';
    final numVal = double.tryParse(str.replaceAll(RegExp(r'[^0-9.]'), ''));
    if (numVal != null && numVal > 0) {
      if (numVal >= 100000) {
        final lpa = numVal / 100000;
        return '${lpa % 1 == 0 ? lpa.toInt() : lpa.toStringAsFixed(1)} LPA';
      } else if (numVal <= 100) {
        return '${numVal % 1 == 0 ? numVal.toInt() : numVal.toStringAsFixed(1)} LPA';
      }
    }
    return str.contains('LPA') ? str : '$str LPA';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final item = _detail ?? widget.initialData;

    final companyName = item?['company_name'] ?? 'Company';
    final jobTitle = item?['interview_job'] ?? item?['drive_title'] ?? 'Company Placement Listing';
    
    final rawMin = item?['ctc_min'] ?? 6.0;
    final rawMax = item?['ctc_max'] ?? 12.0;
    final minFmt = _formatCtcValue(rawMin);
    final maxFmt = _formatCtcValue(rawMax);
    String ctcDisplay = 'CTC Package: $minFmt - $maxFmt';
    if (minFmt == maxFmt) {
      ctcDisplay = 'CTC Package: $minFmt';
    } else {
      final cleanMin = minFmt.replaceAll(' LPA', '');
      ctcDisplay = 'CTC Package: $cleanMin - $maxFmt';
    }

    final isEligible = item?['is_eligible'] ?? true;
    final pdfUrl = item?['pdf_url'] ?? item?['attachment_pdf_url'];
    final description = item?['description'] ?? 'No description provided.';
    final reqSkills = (item?['required_skills'] as List?) ?? ['Communication', 'Problem Solving'];
    final selectionRounds = (item?['selection_process'] as List?) ?? [
      {'round_number': 1, 'round_name': 'Aptitude Test'},
      {'round_number': 2, 'round_name': 'Technical Round'},
      {'round_number': 3, 'round_name': 'HR Round'},
    ];
    final bondDetails = item?['bond_time'] ?? item?['bond_details'] ?? '1 Year';
    final scheduleDatetime = item?['interview_datetime'] ?? item?['schedule_datetime'] ?? 'To Be Scheduled';
    final venue = item?['interview_venue'] ?? item?['location'] ?? 'Campus Auditorium';

    return Scaffold(
      appBar: AppBar(
        title: Text(companyName),
      ),
      body: (_isLoading && _detail == null && widget.initialData == null)
          ? const DriveDetailSkeleton()
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header Card
                        Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: AppColors.primaryLightBg,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(Icons.business_rounded, color: AppColors.lightPrimary, size: 28),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            companyName,
                                            style: theme.textTheme.titleMedium?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 18,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            jobTitle,
                                            style: theme.textTheme.bodyMedium?.copyWith(
                                              color: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                const Divider(height: 1),
                                const SizedBox(height: 12),

                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        ctcDisplay,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isEligible ? AppColors.successLightBg : AppColors.warning.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        isEligible ? '✔ Eligible' : '⚠ Not Eligible',
                                        style: TextStyle(
                                          color: isEligible ? AppColors.success : AppColors.warning,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Auto-Eligibility Criteria Section
                        Text('Auto-Eligibility Criteria & Policy Requirements', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.grade_rounded, size: 18, color: AppColors.lightPrimary),
                                    const SizedBox(width: 8),
                                    const Text('Minimum CGPA Cutoff:', style: TextStyle(fontSize: 12, color: AppColors.lightTextSecondary)),
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppColors.primaryLightBg,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '${item?['cgpa_criteria'] ?? item?['min_cgpa'] ?? 6.0}',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.lightPrimary),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                const Divider(height: 1),
                                const SizedBox(height: 10),

                                const Text('Eligible Academic Programs:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: ((item?['eligible_courses'] as List?) ?? ['BTECH_CSE', 'BCA']).map((course) {
                                    return Chip(
                                      label: Text(course.toString(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                      backgroundColor: AppColors.primaryLightBg,
                                      visualDensity: VisualDensity.compact,
                                    );
                                  }).toList(),
                                ),
                                const SizedBox(height: 10),
                                const Divider(height: 1),
                                const SizedBox(height: 10),

                                const Text('Policy Requirements Check:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 6),
                                _buildPolicyRow('Placement Cell Access', (item?['placement_policy_flags']?['requires_placement_access'] ?? true)),
                                _buildPolicyRow('Academic Placement Eligibility', (item?['placement_policy_flags']?['requires_placement_eligible'] ?? true)),
                                _buildPolicyRow('Full-Time Job Interest Opt-in', (item?['placement_policy_flags']?['requires_job_interest'] ?? true)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Selection Process Rounds Stepper
                        if (selectionRounds.isNotEmpty) ...[
                          Text('Selection Process Rounds', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                children: [
                                  for (int i = 0; i < selectionRounds.length; i++) ...[
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 13,
                                          backgroundColor: AppColors.lightPrimary,
                                          child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            (selectionRounds[i] as Map)['round_name'] ?? 'Round ${i + 1}',
                                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (i < selectionRounds.length - 1)
                                      const Align(
                                        alignment: Alignment.centerLeft,
                                        child: Padding(
                                          padding: EdgeInsets.only(left: 12, top: 4, bottom: 4),
                                          child: SizedBox(
                                            height: 14,
                                            child: VerticalDivider(thickness: 2, color: AppColors.lightPrimary),
                                          ),
                                        ),
                                      ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Listing Schedule & Requirements
                        Text('Interview Schedule & Venue', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              children: [
                                _buildDetailRow(Icons.calendar_month_rounded, 'Date & Time', scheduleDatetime),
                                const Divider(height: 16),
                                _buildDetailRow(Icons.location_on_rounded, 'Venue / Platform', venue),
                                const Divider(height: 16),
                                _buildDetailRow(Icons.verified_rounded, 'Service Bond', bondDetails),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Required Skills Chips
                        if (reqSkills.isNotEmpty) ...[
                          Text('Required Skills', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: reqSkills.map((sk) {
                              return Chip(
                                label: Text(sk.toString(), style: const TextStyle(fontSize: 11)),
                                backgroundColor: AppColors.primaryLightBg,
                                visualDensity: VisualDensity.compact,
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // PDF Attachment Section
                        if (pdfUrl != null && pdfUrl.toString().isNotEmpty) ...[
                          Text('Job Brochure PDF Attachment', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          DeferredPdfViewerCard(
                            pdfUrl: pdfUrl.toString(),
                            title: 'Company Brochure PDF',
                            subtitle: pdfUrl.toString().split('/').last,
                            icon: Icons.picture_as_pdf_rounded,
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Job Description
                        Text('Job Description', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              description.toString(),
                              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Apply Bar
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                    border: Border(
                      top: BorderSide(
                        color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                      ),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: ElevatedButton(
                      onPressed: (_hasApplied || _isApplying) ? null : _handleApply,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        backgroundColor: _hasApplied ? AppColors.success : null,
                      ),
                      child: _isApplying
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Text(
                              _hasApplied ? '✔ Applied' : 'Apply Now',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.lightPrimary),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.lightTextSecondary)),
        const Spacer(),
        Expanded(
          flex: 2,
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildPolicyRow(String label, bool isRequired) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            isRequired ? Icons.check_circle_rounded : Icons.info_outline_rounded,
            size: 14,
            color: isRequired ? AppColors.success : AppColors.lightTextSecondary,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: isRequired ? AppColors.success : AppColors.lightTextSecondary,
              fontWeight: isRequired ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          const Spacer(),
          Text(
            isRequired ? 'Required' : 'Optional',
            style: TextStyle(
              fontSize: 10,
              color: isRequired ? AppColors.success : AppColors.lightTextSecondary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
