import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import '../../controllers/paging_controller.dart';
import '../../network/api_client.dart';
import '../../services/recruiter_service.dart';
import '../../services/application_visibility_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_avatar.dart';
import '../../widgets/paginated_list_view.dart';
import '../../widgets/skeleton_widgets.dart';
import 'round_result_screen.dart';

class ApplicantsScreen extends StatefulWidget {
  final String listingId;
  final String companyName;
  final String interviewJob;

  const ApplicantsScreen({
    super.key,
    required this.listingId,
    required this.companyName,
    required this.interviewJob,
  });

  @override
  State<ApplicantsScreen> createState() => _ApplicantsScreenState();
}

class _ApplicantsScreenState extends State<ApplicantsScreen> {
  final RecruiterService _recruiterService = RecruiterService();
  late final PagingController<Map<String, dynamic>> _pagingController;

  @override
  void initState() {
    super.initState();
    ApplicationVisibilityState.instance.addListener(_onApplicationRecorded);
    _pagingController = PagingController<Map<String, dynamic>>(
      fetchPage: (page, limit) => _recruiterService.getListingApplicantsPaginated(
        widget.listingId,
        page: page,
        limit: limit,
      ),
    );
  }

  void _onApplicationRecorded() {
    if (mounted) _pagingController.refresh();
  }

  String _formatAppliedAt(dynamic rawVal) {
    if (rawVal == null) return 'Recently';
    final str = rawVal.toString().trim();
    if (str.isEmpty || str.toLowerCase() == 'recently') return 'Recently';
    try {
      final dt = DateTime.parse(str).toLocal();
      return '${dt.day} ${_monthName(dt.month)} ${dt.year}';
    } catch (_) {
      if (str.contains('T')) {
        return str.split('T').first;
      }
      return str;
    }
  }

  String _monthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return (month >= 1 && month <= 12) ? months[month - 1] : '';
  }

  Future<File?> _fetchStudentResume(String resumeLink, String studentName) async {
    final cleanPath = resumeLink.trim();
    if (cleanPath.isEmpty) return null;

    final tempDir = Directory.systemTemp;
    final safeFileName = '${studentName.replaceAll(' ', '_')}_resume.pdf';
    final tempPdf = File('${tempDir.path}/$safeFileName');

    // 1. Download stream from backend via ApiClient.dio (handles baseUrl, ssl pinning & headers)
    try {
      final dio = ApiClient.instance.dio;
      String endpoint = cleanPath;
      if (!cleanPath.startsWith('http')) {
        if (!cleanPath.startsWith('/')) {
          endpoint = '/$cleanPath';
        }
      }

      final response = await dio.get<List<int>>(
        endpoint,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'ngrok-skip-browser-warning': 'true'},
        ),
      );

      if (response.statusCode == 200 && response.data != null && response.data!.isNotEmpty) {
        await tempPdf.writeAsBytes(response.data!);
        return tempPdf;
      }
    } catch (e) {
      debugPrint("Dio resume download error: $e");
    }

    // 2. Direct HttpClient fallback request if Dio encountered an error
    if (cleanPath.startsWith('/api/v1/files/') || cleanPath.startsWith('/static/uploads/') || cleanPath.startsWith('http')) {
      try {
        const baseUrl = 'https://spotting-refuse-scorecard.ngrok-free.dev';
        final fullUrl = cleanPath.startsWith('http') ? cleanPath : '$baseUrl${cleanPath.startsWith('/') ? '' : '/'}$cleanPath';
        final client = HttpClient();
        final request = await client.getUrl(Uri.parse(fullUrl));
        request.headers.add('ngrok-skip-browser-warning', 'true');
        request.headers.add('User-Agent', 'TalentloqApp/1.0');
        final response = await request.close();
        if (response.statusCode == 200) {
          final bytes = await response.fold<List<int>>([], (prev, element) => prev..addAll(element));
          if (bytes.isNotEmpty && bytes.length > 50) {
            await tempPdf.writeAsBytes(bytes);
            return tempPdf;
          }
        }
      } catch (_) {}
    }

    // 3. Fallback to direct file on local filesystem if path exists on device
    if (cleanPath.isNotEmpty) {
      final directFile = File(cleanPath);
      if (directFile.existsSync() && cleanPath.toLowerCase().endsWith('.pdf')) {
        return directFile;
      }
    }

    return null;
  }

  void _openResumeViewer(BuildContext context, Map<String, dynamic> app) async {
    final studentName = (app['name'] ?? app['full_name'] ?? 'Student Candidate').toString();
    final resumeLink = (app['resume_link'] ?? app['resume_id_used'] ?? app['resume_url'] ?? app['resume_id'] ?? '').toString();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Opening student resume document...'),
        duration: Duration(milliseconds: 1200),
      ),
    );

    final pdfFile = await _fetchStudentResume(resumeLink, studentName);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (pdfFile == null || !pdfFile.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.info_outline_rounded, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('Resume not available.', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // Open PDF directly in document viewer
    try {
      final result = await OpenFilex.open(pdfFile.path);
      if (result.type != ResultType.done && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Opened resume: ${pdfFile.path}')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Resume not available.'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
    }
  }

  void _showStudentDetailsModal(BuildContext context, Map<String, dynamic> app) {
    final studentName = (app['name'] ?? app['full_name'] ?? 'Student Candidate').toString();
    final studentId = (app['student_id'] ?? app['user_id'] ?? '').toString();
    final email = (app['email'] ?? app['email_address'] ?? 'Not Specified').toString();
    final phone = (app['phone_number'] ?? app['phone'] ?? app['mobile'] ?? 'Not Specified').toString();
    final course = (app['course'] ?? app['degree'] ?? 'BTECH_CSE').toString();
    final cgpa = (app['cgpa'] ?? app['CGPA'] ?? 8.0).toString();
    final meetsCgpa = app['is_eligible'] ?? app['meets_cgpa_criteria'] ?? true;
    final appliedAt = _formatAppliedAt(app['applied_at']);
    final currentRound = (app['current_round'] ?? 0).toString();
    final finalOutcome = (app['final_outcome'] ?? app['status'] ?? 'applied').toString().replaceAll('_', ' ').toUpperCase();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final theme = Theme.of(sheetCtx);
        final isDark = theme.brightness == Brightness.dark;

        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
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

              // Student Header
              Row(
                children: [
                  AppAvatar(
                    radius: 28,
                    imageUrl: '',
                    fallbackText: studentName,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          studentName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$course • ID: $studentId',
                          style: const TextStyle(fontSize: 12, color: AppColors.lightTextSecondary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(sheetCtx),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // Student -> Application -> Company Details Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkBackground : AppColors.lightBackground,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                  ),
                ),
                child: Column(
                  children: [
                    _buildDetailRow(Icons.business_rounded, 'Target Company', widget.companyName, isDark, textColor: AppColors.lightPrimary),
                    const Divider(height: 14, thickness: 0.5),
                    _buildDetailRow(Icons.work_outline_rounded, 'Applied Position', widget.interviewJob, isDark),
                    const Divider(height: 14, thickness: 0.5),
                    _buildDetailRow(Icons.email_outlined, 'Email Address', email, isDark),
                    const Divider(height: 14, thickness: 0.5),
                    _buildDetailRow(Icons.phone_outlined, 'Contact Mobile', phone, isDark),
                    const Divider(height: 14, thickness: 0.5),
                    _buildDetailRow(Icons.school_outlined, 'Course & Dept', course, isDark),
                    const Divider(height: 14, thickness: 0.5),
                    _buildDetailRow(Icons.star_outline_rounded, 'Academic CGPA', '$cgpa / 10.0', isDark),
                    const Divider(height: 14, thickness: 0.5),
                    _buildDetailRow(
                      Icons.verified_user_outlined,
                      'Eligibility Gate',
                      meetsCgpa ? '✔ Eligible' : '✖ Below Cutoff',
                      isDark,
                      textColor: meetsCgpa ? AppColors.success : AppColors.warning,
                    ),
                    const Divider(height: 14, thickness: 0.5),
                    _buildDetailRow(Icons.calendar_today_outlined, 'Applied Date', appliedAt, isDark),
                    const Divider(height: 14, thickness: 0.5),
                    _buildDetailRow(Icons.timeline_rounded, 'Current Status', 'Round $currentRound ($finalOutcome)', isDark),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Action Buttons Row
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetCtx);
                        _openResumeViewer(context, app);
                      },
                      icon: const Icon(Icons.picture_as_pdf_rounded, color: AppColors.error, size: 18),
                      label: const Text('View Resume'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetCtx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => RoundResultScreen(
                              driveId: widget.listingId,
                              applicantData: app,
                              onUpdated: () => _pagingController.refresh(),
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.how_to_reg_rounded, size: 18),
                      label: const Text('Record Round'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value, bool isDark, {Color? textColor}) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.lightPrimary),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.lightTextSecondary)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: textColor ?? (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _pagingController.dispose();
    ApplicationVisibilityState.instance.removeListener(_onApplicationRecorded);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.companyName} Applicants'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _pagingController.refresh(),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _pagingController.refresh(),
        child: Column(
          children: [
            // Header Banner
            ListenableBuilder(
              listenable: _pagingController,
              builder: (context, _) {
                final total = _pagingController.items.isNotEmpty
                    ? _pagingController.items.length
                    : _pagingController.totalCount;

                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.business_rounded, size: 18, color: AppColors.lightPrimary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Company: ${widget.companyName}',
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.primaryLightBg,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '$total Applied',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.lightPrimary),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.work_outline_rounded, size: 15, color: AppColors.lightTextSecondary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Position: ${widget.interviewJob}',
                              style: const TextStyle(fontSize: 12, color: AppColors.lightTextSecondary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
            const Divider(height: 1),

            // Paginated Applicants List
            Expanded(
              child: PaginatedListView<Map<String, dynamic>>(
                controller: _pagingController,
                itemKey: (item) => ValueKey(item['app_id'] ?? item['student_id'] ?? item.hashCode),
                skeletonBuilder: (_, _) => const ApplicantRowSkeleton(),
                emptyWidget: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.people_outline_rounded, size: 56, color: AppColors.lightTextSecondary),
                        const SizedBox(height: 14),
                        const Text(
                          'No students have applied to your company yet.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Student applications submitted to this placement drive will automatically appear here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: AppColors.lightTextSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
                itemBuilder: (context, app, index) {
                  final studentName = (app['name'] ?? app['full_name'] ?? 'Student Candidate').toString();
                  final cgpa = (app['cgpa'] ?? app['CGPA'] ?? 8.0).toString();
                  final meetsCgpa = app['is_eligible'] ?? app['meets_cgpa_criteria'] ?? true;
                  final appliedAt = app['applied_at'] ?? 'Recently';
                  final resumeLink = (app['resume_link'] ?? app['resume_id_used'] ?? app['resume_url'] ?? app['resume_id'] ?? '').toString();
                  final hasResume = resumeLink.trim().isNotEmpty;

                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                      ),
                    ),
                    child: InkWell(
                      onTap: () => _showStudentDetailsModal(context, app),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Student Info Row
                            Row(
                              children: [
                                AppAvatar(
                                  radius: 22,
                                  imageUrl: '',
                                  fallbackText: studentName,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        studentName,
                                        style: theme.textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'CGPA: $cgpa • ${widget.companyName}',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.lightPrimary,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),

                                // Meets CGPA Criteria Badge
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: meetsCgpa
                                        ? AppColors.successLightBg
                                        : AppColors.warning.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        meetsCgpa ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                                        size: 13,
                                        color: meetsCgpa ? AppColors.success : AppColors.warning,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        meetsCgpa ? '✔ Eligible' : '✖ Below Cutoff',
                                        style: TextStyle(
                                          color: meetsCgpa ? AppColors.success : AppColors.warning,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            const Divider(height: 1),
                            const SizedBox(height: 10),

                            // Footer Actions & Details
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Text(
                                    'Applied: ${_formatAppliedAt(appliedAt)}',
                                    style: const TextStyle(fontSize: 11, color: AppColors.lightTextSecondary),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  onPressed: () => _openResumeViewer(context, app),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  icon: Icon(
                                    Icons.picture_as_pdf_rounded,
                                    size: 14,
                                    color: hasResume ? AppColors.error : AppColors.lightTextSecondary,
                                  ),
                                  label: Text(
                                    hasResume ? 'View Resume' : 'No Resume',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: hasResume ? AppColors.lightTextPrimary : AppColors.lightTextSecondary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => RoundResultScreen(
                                          driveId: widget.listingId,
                                          applicantData: app,
                                          onUpdated: () => _pagingController.refresh(),
                                        ),
                                      ),
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  icon: const Icon(Icons.how_to_reg_rounded, size: 14),
                                  label: const Text('Record Round', style: TextStyle(fontSize: 11)),
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
            ),
          ],
        ),
      ),
    );
  }
}
