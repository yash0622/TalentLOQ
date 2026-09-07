import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import '../../models/models.dart';
import '../../network/api_client.dart';
import '../../services/recruiter_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_avatar.dart';
import 'offer_setup_modal.dart';

class CandidateDetailScreen extends StatefulWidget {
  final Candidate candidate;
  final VoidCallback onBack;
  final VoidCallback onScheduleInterview;
  final VoidCallback onSendMessage;

  const CandidateDetailScreen({
    super.key,
    required this.candidate,
    required this.onBack,
    required this.onScheduleInterview,
    required this.onSendMessage,
  });

  @override
  State<CandidateDetailScreen> createState() => _CandidateDetailScreenState();
}

class _CandidateDetailScreenState extends State<CandidateDetailScreen> {
  late String _validationStatus;
  final RecruiterService _recruiterService = RecruiterService();
  Map<String, dynamic>? _ugDocument;
  Map<String, dynamic>? _resumeDocument;
  bool _isLoadingDocs = true;

  @override
  void initState() {
    super.initState();
    _validationStatus = widget.candidate.validationStatus;
    _fetchAcademicAndDocs();
  }

  Future<void> _fetchAcademicAndDocs() async {
    try {
      final record = await _recruiterService.getStudentAcademicRecord(widget.candidate.id);
      if (mounted && record != null) {
        setState(() {
          _ugDocument = record['ug_document'] as Map<String, dynamic>?;
          _resumeDocument = record['resume_document'] as Map<String, dynamic>?;
          _isLoadingDocs = false;
        });
        return;
      }
    } catch (_) {}
    if (mounted) {
      setState(() => _isLoadingDocs = false);
    }
  }

  void _markValidation(String newStatus) {
    setState(() {
      _validationStatus = newStatus;
    });
    final statusText = newStatus == 'valid'
        ? 'Valid for Role'
        : newStatus == 'not_valid'
            ? 'Not Valid'
            : 'Pending Review';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Candidate "${widget.candidate.name}" marked as $statusText.'),
        backgroundColor: newStatus == 'valid'
            ? AppColors.success
            : newStatus == 'not_valid'
                ? AppColors.error
                : AppColors.warning,
      ),
    );
  }

  Future<void> _viewDocument(String? fileUrl, String docTitle) async {
    if (fileUrl == null || fileUrl.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$docTitle is not uploaded yet.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Opening $docTitle...'),
        duration: const Duration(milliseconds: 1200),
      ),
    );

    try {
      final dio = ApiClient.instance.dio;
      final tempDir = Directory.systemTemp;
      final cleanName = docTitle.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final targetFile = File('${tempDir.path}/${cleanName}_${DateTime.now().millisecondsSinceEpoch}.pdf');

      String endpoint = fileUrl.trim();
      if (!endpoint.startsWith('http') && !endpoint.startsWith('/')) {
        endpoint = '/$endpoint';
      }

      final response = await dio.get<List<int>>(
        endpoint,
        options: Options(responseType: ResponseType.bytes),
      );

      if (response.statusCode == 200 && response.data != null && response.data!.isNotEmpty) {
        await targetFile.writeAsBytes(response.data!);
        await OpenFilex.open(targetFile.path);
        return;
      }
    } catch (e) {
      debugPrint('[DOC VIEW ERROR] $e');
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open $docTitle. File may not be available on server.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Widget _buildDocumentCard({
    required BuildContext context,
    required bool isDark,
    required String title,
    required String subtitle,
    required IconData icon,
    required Map<String, dynamic>? docData,
    String? fallbackUrl,
  }) {
    final hasDoc = docData != null || (fallbackUrl != null && fallbackUrl.isNotEmpty);
    final fileUrl = docData?['file_url']?.toString() ?? fallbackUrl;
    final filename = docData?['filename']?.toString() ?? (hasDoc ? '$title.pdf' : 'Not uploaded');

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _viewDocument(fileUrl, title),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.lightPrimary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppColors.lightPrimary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasDoc ? filename : 'Document not uploaded yet',
                      style: TextStyle(
                        fontSize: 11,
                        color: hasDoc
                            ? (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary)
                            : AppColors.warning,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (hasDoc) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.successLightBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified_rounded, color: AppColors.success, size: 12),
                      SizedBox(width: 4),
                      Text(
                        'Verified',
                        style: TextStyle(color: AppColors.success, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.lightTextSecondary),
              ] else ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Missing',
                    style: TextStyle(color: AppColors.warning, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final candidate = widget.candidate;

    // Normalize match score to 0 - 10 scale
    final double matchScoreOutOf10;
    if (candidate.matchScore > 10.0) {
      matchScoreOutOf10 = (candidate.matchScore / 10.0).clamp(0.0, 10.0);
    } else if (candidate.matchScore > 0 && candidate.matchScore <= 1.0) {
      matchScoreOutOf10 = (candidate.matchScore * 10.0).clamp(0.0, 10.0);
    } else {
      matchScoreOutOf10 = candidate.matchScore.clamp(0.0, 10.0);
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: widget.onBack,
        ),
        title: const Text('Candidate Review & Validation'),
        actions: [
          IconButton(
            tooltip: 'Setup Placement Offer',
            icon: const Icon(Icons.workspace_premium_rounded, color: AppColors.success),
            onPressed: () {
              OfferSetupModal.show(
                context,
                driveId: '',
                studentId: widget.candidate.id,
                candidateName: widget.candidate.name,
                companyName: 'Company',
                roleTitle: widget.candidate.roleTitle,
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Candidate Header Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              AppAvatar(
                                radius: 32,
                                imageUrl: candidate.avatarUrl,
                                fallbackText: candidate.name,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      candidate.name,
                                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      candidate.roleTitle,
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${candidate.education} • CGPA ${candidate.cgpa.toStringAsFixed(2)}',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Divider(height: 1),
                          const SizedBox(height: 12),
                          // Aligned Match Score & Validation Status Row
                          Row(
                            children: [
                              // 0-10 AI Match Score Pill
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: AppColors.successLightBg,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.bolt_rounded, color: AppColors.success, size: 16),
                                    const SizedBox(width: 4),
                                    Text(
                                      'AI Match: ${matchScoreOutOf10.toStringAsFixed(1)} / 10',
                                      style: const TextStyle(
                                        color: AppColors.success,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              // Validation Status Pill
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: _validationStatus == 'valid'
                                      ? AppColors.successLightBg
                                      : _validationStatus == 'not_valid'
                                          ? AppColors.error.withValues(alpha: 0.15)
                                          : AppColors.warning.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  _validationStatus == 'valid'
                                      ? '✔ VALID'
                                      : _validationStatus == 'not_valid'
                                          ? '✖ NOT VALID'
                                          : '⏳ PENDING REVIEW',
                                  style: TextStyle(
                                    color: _validationStatus == 'valid'
                                        ? AppColors.success
                                        : _validationStatus == 'not_valid'
                                            ? AppColors.error
                                            : AppColors.warning,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (candidate.isAutoApplied) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.primaryLightBg,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.verified_user_rounded, color: AppColors.lightPrimary, size: 14),
                                  SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      'Auto-Apply Agent Proposal • Approved by Student',
                                      style: TextStyle(fontSize: 11, color: AppColors.lightPrimary, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Candidate Validation Action Controls
                  Text('Validation Control Dashboard', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _markValidation('valid'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _validationStatus == 'valid' ? AppColors.success : AppColors.success.withValues(alpha: 0.15),
                            foregroundColor: _validationStatus == 'valid' ? Colors.white : AppColors.success,
                            elevation: _validationStatus == 'valid' ? 2 : 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(color: AppColors.success.withValues(alpha: 0.4)),
                            ),
                          ),
                          icon: const Icon(Icons.check_circle_rounded, size: 18),
                          label: const Text('Mark Valid', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _markValidation('not_valid'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _validationStatus == 'not_valid' ? AppColors.error : AppColors.error.withValues(alpha: 0.15),
                            foregroundColor: _validationStatus == 'not_valid' ? Colors.white : AppColors.error,
                            elevation: _validationStatus == 'not_valid' ? 2 : 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(color: AppColors.error.withValues(alpha: 0.4)),
                            ),
                          ),
                          icon: const Icon(Icons.cancel_rounded, size: 18),
                          label: const Text('Mark Not Valid', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                      if (_validationStatus != 'pending') ...[
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Reset to Pending',
                          icon: const Icon(Icons.restart_alt_rounded, color: AppColors.warning),
                          onPressed: () => _markValidation('pending'),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Matcher Agent Skill-Gap Summary
                  Text('Matcher Agent Skill Gap Analysis', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.analytics_outlined, color: AppColors.lightPrimary, size: 18),
                              SizedBox(width: 8),
                              Text('Identified Skill Gaps for Role', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (candidate.skillGaps.isNotEmpty) ...[
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: candidate.skillGaps.map((gap) {
                                return Chip(
                                  avatar: const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 16),
                                  label: Text(gap, style: const TextStyle(fontSize: 11)),
                                  backgroundColor: AppColors.warning.withValues(alpha: 0.1),
                                  side: BorderSide(color: AppColors.warning.withValues(alpha: 0.3)),
                                );
                              }).toList(),
                            ),
                          ] else ...[
                            const Text('No major skill gaps identified! Excellent match candidate.', style: TextStyle(fontSize: 12, color: AppColors.success)),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Verified Academic Record (Current CGPA only, un-overflowed)
                  Text('Verified Academic Record', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.darkSurfaceContainerHigh : AppColors.lightSurfaceContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.school_rounded, color: AppColors.lightPrimary, size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Current CGPA',
                                  style: TextStyle(fontSize: 11.5, color: AppColors.lightTextSecondary, fontWeight: FontWeight.w500),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${candidate.cgpa.toStringAsFixed(2)} / 10.0',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: candidate.activeBacklogs == 0 ? AppColors.successLightBg : AppColors.error.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              candidate.activeBacklogs == 0 ? '0 Backlogs • Eligible' : '${candidate.activeBacklogs} Active Backlog',
                              style: TextStyle(
                                color: candidate.activeBacklogs == 0 ? AppColors.success : AppColors.error,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Verified Documents (Only Undergraduate Result & Resume Document)
                  Text('Verified Documents', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_isLoadingDocs)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      ),
                    )
                  else ...[
                    _buildDocumentCard(
                      context: context,
                      isDark: isDark,
                      title: 'Undergraduate Result',
                      subtitle: 'Verified UG Marksheet / Degree',
                      icon: Icons.assignment_turned_in_rounded,
                      docData: _ugDocument,
                      fallbackUrl: _ugDocument?['file_url'] ?? candidate.ugMarksheetUrl,
                    ),
                    const SizedBox(height: 10),
                    _buildDocumentCard(
                      context: context,
                      isDark: isDark,
                      title: 'Resume Document',
                      subtitle: 'Verified Candidate Resume (PDF)',
                      icon: Icons.description_rounded,
                      docData: _resumeDocument,
                      fallbackUrl: _resumeDocument?['file_url'] ?? candidate.resumeUrl,
                    ),
                  ],
                  const SizedBox(height: 20),

                  // Candidate Bio & Verified Skills
                  Text('Verified Skills', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: candidate.skills.map((skill) {
                      return Chip(
                        label: Text(skill, style: const TextStyle(fontSize: 11)),
                        backgroundColor: isDark ? AppColors.darkSurfaceContainerLow : AppColors.lightSurfaceContainerLow,
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),

          // Bottom Action Bar
          Container(
            padding: const EdgeInsets.all(12),
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
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        OfferSetupModal.show(
                          context,
                          driveId: '',
                          studentId: widget.candidate.id,
                          candidateName: widget.candidate.name,
                          companyName: 'Company',
                          roleTitle: widget.candidate.roleTitle,
                        );
                      },
                      icon: const Icon(Icons.workspace_premium_rounded, color: AppColors.success, size: 18),
                      label: const Text(
                        'Setup Placement Offer Package',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.success),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.success, width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: widget.onSendMessage,
                          icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                          label: const Text('Message'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _validationStatus == 'not_valid' ? null : widget.onScheduleInterview,
                          icon: const Icon(Icons.calendar_month_rounded, size: 18),
                          label: const Text('Schedule Interview'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
