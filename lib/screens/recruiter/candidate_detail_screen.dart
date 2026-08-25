import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_avatar.dart';

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

  @override
  void initState() {
    super.initState();
    _validationStatus = widget.candidate.validationStatus;
  }

  void _markValidation(String newStatus) {
    setState(() {
      _validationStatus = newStatus;
    });
    final statusText = newStatus == 'valid' ? 'Valid for Role' : 'Not Valid';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Candidate "${widget.candidate.name}" marked as $statusText.'),
        backgroundColor: newStatus == 'valid' ? AppColors.success : AppColors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final candidate = widget.candidate;
    final matchPercentage = (candidate.matchScore * 100).round();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: widget.onBack,
        ),
        title: const Text('Candidate Review & Validation'),
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
                                      '${candidate.education} • CGPA ${candidate.cgpa}',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Divider(height: 1),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.spaceBetween,
                            children: [
                              // Match Score Pill
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppColors.successLightBg,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.bolt_rounded, color: AppColors.success, size: 16),
                                    const SizedBox(width: 4),
                                    Text(
                                      '$matchPercentage% AI Match Score',
                                      style: const TextStyle(
                                        color: AppColors.success,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Validation Status Pill
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                            backgroundColor: AppColors.success,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: const Icon(Icons.check_circle_rounded, size: 18),
                          label: const Text('Mark Valid'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _markValidation('not_valid'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                            side: const BorderSide(color: AppColors.error),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: const Icon(Icons.cancel_rounded, size: 18),
                          label: const Text('Mark Not Valid'),
                        ),
                      ),
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

                  // Verified Academic Record History
                  Text('Verified Academic Record', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Cumulative CGPA: ${candidate.cgpa} / 10.0', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: candidate.activeBacklogs == 0 ? AppColors.successLightBg : AppColors.error.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  candidate.activeBacklogs == 0 ? '0 Backlogs • Eligible' : '${candidate.activeBacklogs} Active Backlog',
                                  style: TextStyle(
                                    color: candidate.activeBacklogs == 0 ? AppColors.success : AppColors.error,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text('Semester CGPA Progression:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildSemChip('Sem 1', (candidate.cgpa - 0.4).toStringAsFixed(2)),
                              _buildSemChip('Sem 2', (candidate.cgpa - 0.2).toStringAsFixed(2)),
                              _buildSemChip('Sem 3', (candidate.cgpa - 0.1).toStringAsFixed(2)),
                              _buildSemChip('Sem 4', candidate.cgpa.toStringAsFixed(2)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
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
              child: Row(
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
                      onPressed: _validationStatus == 'not_valid'
                          ? null
                          : widget.onScheduleInterview,
                      icon: const Icon(Icons.calendar_month_rounded, size: 18),
                      label: const Text('Schedule Interview'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSemChip(String sem, String score) {
    return Column(
      children: [
        Text(sem, style: const TextStyle(fontSize: 10, color: AppColors.lightTextSecondary)),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.primaryLightBg,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(score, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.lightPrimary)),
        ),
      ],
    );
  }
}
