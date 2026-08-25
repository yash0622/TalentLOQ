import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/drive_service.dart';
import '../../services/application_visibility_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/skeleton_widgets.dart';

class DriveDetailScreen extends StatefulWidget {
  final String driveId;
  final Map<String, dynamic>? initialDriveData;
  final double studentCgpa;
  final bool hasResume;
  final VoidCallback? onNavigateToProfile;

  const DriveDetailScreen({
    super.key,
    required this.driveId,
    this.initialDriveData,
    this.studentCgpa = 8.0,
    this.hasResume = true,
    this.onNavigateToProfile,
  });

  @override
  State<DriveDetailScreen> createState() => _DriveDetailScreenState();
}

class _DriveDetailScreenState extends State<DriveDetailScreen> {
  final DriveService _driveService = DriveService();

  bool _isLoading = true;
  Map<String, dynamic>? _drive;
  bool _hasApplied = false;
  bool _isApplying = false;
  bool _isPreparingEmail = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialDriveData != null) {
      _drive = widget.initialDriveData;
      _isLoading = false;
    }
    _fetchDetail();
    _checkMyStatus();
  }

  Future<void> _fetchDetail() async {
    final detail = await _driveService.getDriveDetail(widget.driveId);
    if (mounted && detail != null) {
      setState(() {
        _drive = detail;
        _hasApplied = detail['has_applied'] == true || ApplicationVisibilityState.instance.isApplied(widget.driveId);
        _isLoading = false;
      });
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _checkMyStatus() async {
    final statusMap = await _driveService.getMyDriveStatus(widget.driveId);
    if (mounted && statusMap['applied'] == true) {
      setState(() => _hasApplied = true);
    }
  }

  void _openPdfBrochure(String pdfUrl) {
    if (pdfUrl.startsWith('http://') || pdfUrl.startsWith('https://')) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Drive Brochure PDF'),
          content: SelectableText('Brochure Link:\n$pdfUrl'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } else {
      try {
        OpenFilex.open(pdfUrl);
      } catch (_) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Drive Brochure PDF'),
            content: Text('Brochure file reference:\n$pdfUrl'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _handleApply() async {
    final isEligible = _drive?['is_eligible'] ?? true;

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
            'No uploaded resume found in your profile. Please upload a resume first to apply for placement drives.',
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
            'You do not meet all criteria for this drive.\n\n'
            '• Drive Cutoff: ${(_drive?['min_cgpa'] ?? 6.0)}\n'
            '• Your CGPA: ${widget.studentCgpa.toStringAsFixed(2)}\n\n'
            'Your application will record an eligibility warning flag. Apply anyway?',
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

    final res = await _driveService.applyToDrive(widget.driveId);

    setState(() => _isApplying = false);

    if (!mounted) return;

    if (res['success'] == true) {
      final body = res['data'];
      final application = body is Map ? body['application'] : null;
      setState(() {
        _hasApplied = true;
        _drive?['has_applied'] = true;
        _drive?['my_application_status'] = application is Map ? application['status'] : 'applied';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Application submitted successfully! Good luck!'),
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
        const SnackBar(content: Text('You have already applied to this drive.'), backgroundColor: AppColors.lightPrimary),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message'] ?? 'Could not submit application.'), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _handleEmailApplication() async {
    setState(() => _isPreparingEmail = true);
    final draft = await _driveService.getEmailDraft(widget.driveId);
    setState(() => _isPreparingEmail = false);

    if (!mounted) return;

    if (draft == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not fetch email application draft.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final toEmail = (draft['to'] ?? '').toString();
    final subjectText = (draft['subject'] ?? '').toString();
    final bodyText = (draft['body'] ?? '').toString();

    final subjectEncoded = Uri.encodeComponent(subjectText);
    final bodyEncoded = Uri.encodeComponent(bodyText);

    final mailtoUri = Uri.parse(
      'mailto:$toEmail?subject=$subjectEncoded&body=$bodyEncoded',
    );

    bool launched = false;
    try {
      if (await canLaunchUrl(mailtoUri)) {
        launched = await launchUrl(mailtoUri);
      }
    } catch (_) {
      launched = false;
    }

    if (launched) {
      _driveService.markEmailClientOpened(widget.driveId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mail client opened! Don\'t forget to attach your resume before sending.'),
          backgroundColor: AppColors.lightPrimary,
          duration: Duration(seconds: 5),
        ),
      );
    } else {
      _driveService.markEmailClientOpened(widget.driveId);
      if (!mounted) return;
      _showCopyEmailFallbackDialog(
        to: toEmail,
        subject: subjectText,
        body: bodyText,
      );
    }
  }

  void _showCopyEmailFallbackDialog({
    required String to,
    required String subject,
    required String body,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.email_outlined, color: AppColors.lightPrimary),
            SizedBox(width: 8),
            Text('Email Application', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'No default email app was detected on your device. You can copy the application details below to paste into your email app or webmail:',
                style: TextStyle(fontSize: 13, color: AppColors.lightTextSecondary),
              ),
              const SizedBox(height: 12),
              const Text('To:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              SelectableText(to.isNotEmpty ? to : 'Company Email Not Specified', style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 8),
              const Text('Subject:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              SelectableText(subject, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 8),
              const Text('Message Body:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primaryLightBg.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: SelectableText(body, style: const TextStyle(fontSize: 12)),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.warning.withOpacity(0.4)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.attach_file, size: 16, color: AppColors.warning),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Don\'t forget to attach your resume before sending.',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.warning),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Copy Email Text'),
            onPressed: () {
              final fullText = 'To: $to\nSubject: $subject\n\n$body';
              Clipboard.setData(ClipboardData(text: fullText));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Email text copied to clipboard! Remember to attach your resume.'),
                  backgroundColor: AppColors.success,
                ),
              );
            },
          ),
        ],
      ),
    );
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
    final item = _drive ?? widget.initialDriveData;

    final companyName = item?['company_name'] ?? 'Company';
    final driveTitle = item?['drive_title'] ?? item?['interview_job'] ?? 'Placement Drive';
    
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
    final pdfUrl = item?['attachment_pdf_url'] ?? item?['pdf_url'];
    final description = item?['description'] ?? 'No description provided.';
    final reqSkills = (item?['required_skills'] as List?) ?? [];
    final selectionRounds = (item?['selection_process'] as List?) ?? [];
    final bondDetails = item?['bond_details'] ?? 'No Bond';
    final scheduleDatetime = item?['schedule_datetime'] ?? 'To Be Scheduled';
    final deadline = item?['registration_deadline'] ?? 'Open';

    return Scaffold(
      appBar: AppBar(
        title: Text(companyName),
      ),
      body: _isLoading
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
                                            driveTitle,
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
                        Text('Eligibility Criteria & Placement Policy', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
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
                                        '${item?['min_cgpa'] ?? item?['cgpa_criteria'] ?? 6.0}',
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
                                _buildPolicyCheckRow('Placement Cell Active Access', (item?['placement_policy_flags']?['requires_placement_access'] ?? true)),
                                _buildPolicyCheckRow('Academic Placement Eligibility', (item?['placement_policy_flags']?['requires_placement_eligible'] ?? true)),
                                _buildPolicyCheckRow('Full-Time Job Interest Opt-in', (item?['placement_policy_flags']?['requires_job_interest'] ?? true)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Selection Process Visual Stepper
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

                        // Drive Info Section
                        Text('Drive Schedule & Requirements', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              children: [
                                _buildDetailRow(Icons.calendar_month_rounded, 'Drive Date & Time', scheduleDatetime),
                                const Divider(height: 16),
                                _buildDetailRow(Icons.event_busy_rounded, 'Registration Deadline', deadline),
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
                          Text('Brochure PDF Attachment', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Card(
                            child: ListTile(
                              leading: const Icon(Icons.picture_as_pdf_rounded, color: AppColors.error, size: 28),
                              title: const Text('Placement Drive Brochure', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              subtitle: Text(pdfUrl.toString().split('/').last, style: const TextStyle(fontSize: 11)),
                              trailing: ElevatedButton.icon(
                                onPressed: () => _openPdfBrochure(pdfUrl.toString()),
                                icon: const Icon(Icons.open_in_new_rounded, size: 14),
                                label: const Text('View PDF'),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Full Description Section
                        Text('Drive Description', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
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

                // Footer Apply Bar
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
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ElevatedButton(
                          onPressed: (_hasApplied || _isApplying || _isDeadlinePassed) ? null : _handleApply,
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            backgroundColor: _hasApplied
                                ? AppColors.success
                                : (_isDeadlinePassed ? Colors.grey : null),
                          ),
                          child: _isApplying
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : Text(
                                  _hasApplied
                                      ? '✔ Applied'
                                      : (_isDeadlinePassed ? '🚫 Registration Closed (Deadline Passed)' : 'Apply for Placement Drive Now'),
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                ),
                        ),
                        if (_hasApplied) ...[
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: _isPreparingEmail ? null : _handleEmailApplication,
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(44),
                              side: const BorderSide(color: AppColors.lightPrimary),
                            ),
                            icon: _isPreparingEmail
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.email_outlined, color: AppColors.lightPrimary),
                            label: const Text(
                              'Email your application directly',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.lightPrimary),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  bool get _isDeadlinePassed {
    final driveData = _drive ?? widget.initialDriveData;
    final deadlineStr = driveData?['registration_deadline'] ?? driveData?['deadline'];
    if (deadlineStr == null) return false;
    final dStr = deadlineStr.toString().trim().toLowerCase();
    if (dStr == 'closed' || dStr == 'registration closed' || dStr == 'expired' || dStr == 'deadline passed') {
      return true;
    }
    if (dStr == 'open' || dStr == 'to be announced' || dStr == 'tba' || dStr == 'n/a' || dStr.isEmpty) {
      return false;
    }
    try {
      final parsed = DateTime.tryParse(deadlineStr.toString());
      if (parsed != null) {
        return DateTime.now().isAfter(parsed.add(const Duration(days: 1)));
      }
    } catch (_) {}
    return false;
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

  Widget _buildPolicyCheckRow(String label, bool isRequired) {
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
