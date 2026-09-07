import 'package:flutter/material.dart';
import '../services/drive_service.dart';
import '../theme/app_colors.dart';

class AIMatchCoachCard extends StatefulWidget {
  final String driveId;
  final bool questionsOnly;

  const AIMatchCoachCard({
    super.key,
    required this.driveId,
    this.questionsOnly = true,
  });

  @override
  State<AIMatchCoachCard> createState() => _AIMatchCoachCardState();
}

class _AIMatchCoachCardState extends State<AIMatchCoachCard> {
  final DriveService _driveService = DriveService();

  bool _isLoading = true;
  bool _isRefreshing = false;
  Map<String, dynamic>? _matchData;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchMatchData();
  }

  Future<void> _fetchMatchData({bool bypassCache = false}) async {
    if (widget.driveId.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Invalid drive ID.';
        });
      }
      return;
    }

    if (bypassCache) {
      setState(() => _isRefreshing = true);
    } else {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final res = await _driveService.getDriveAIMatch(widget.driveId, bypassCache: bypassCache);
      if (mounted) {
        setState(() {
          _matchData = res;
          _isLoading = false;
          _isRefreshing = false;
          if (res == null) {
            _errorMessage = 'Could not generate AI match intelligence.';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
          _errorMessage = 'AI Match analysis is currently unavailable.';
        });
      }
    }
  }

  Color _getScoreColor(int score) {
    if (score >= 75) return AppColors.success;
    if (score >= 50) return AppColors.warning;
    return AppColors.error;
  }

  Color _getScoreBgColor(int score) {
    if (score >= 75) return AppColors.successLightBg;
    if (score >= 50) return AppColors.warningLightBg;
    return AppColors.error.withValues(alpha: 0.15);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_isLoading) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLightBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.auto_awesome_rounded, color: AppColors.lightPrimary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('AI Match & Interview Coach', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        SizedBox(height: 2),
                        Text('Calibrating 4-pillar rubric with Groq...', style: TextStyle(fontSize: 12, color: AppColors.lightTextSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const LinearProgressIndicator(minHeight: 4, borderRadius: BorderRadius.all(Radius.circular(2))),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null || _matchData == null) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: AppColors.warning, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _errorMessage ?? 'AI match not available for this drive.',
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
              TextButton(
                onPressed: () => _fetchMatchData(bypassCache: true),
                child: const Text('Analyze'),
              ),
            ],
          ),
        ),
      );
    }

    final data = _matchData ?? {};
    final overallScore = (data['overall_match_score'] as num?)?.toInt() ?? 65;
    final fitLevel = data['fit_level']?.toString() ?? 'Medium Fit';
    final rubric = data['rubric_breakdown'] as Map<String, dynamic>? ?? {};
    final coreTech = (rubric['core_tech_score'] as num?)?.toInt() ?? 70;
    final projectDepth = (rubric['project_depth_score'] as num?)?.toInt() ?? 65;
    final roleReadiness = (rubric['role_readiness_score'] as num?)?.toInt() ?? 60;
    final gapLearnability = (rubric['gap_learnability_score'] as num?)?.toInt() ?? 75;

    final equivalences = (data['semantic_equivalences'] as List?) ?? [];
    final projectEvidence = (data['project_evidence'] as List?) ?? [];
    final skillGaps = (data['critical_skill_gaps'] as List?) ?? [];
    final questions = (data['predicted_interview_questions'] as List?) ?? [];
    final prepChecklist = (data['student_prep_checklist'] as List?) ?? [];

    final scoreColor = _getScoreColor(overallScore);
    final scoreBg = _getScoreBgColor(overallScore);

    final cardBorderColor = widget.questionsOnly
        ? (isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant)
        : scoreColor.withValues(alpha: 0.35);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: cardBorderColor,
          width: 1.2,
        ),
      ),
      color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Bar
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLightBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    widget.questionsOnly ? Icons.quiz_outlined : Icons.auto_awesome_rounded,
                    color: AppColors.lightPrimary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.questionsOnly
                            ? 'Targeted Technical Interview Questions'
                            : 'AI Match & Interview Coach',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        widget.questionsOnly
                            ? 'AI-predicted questions tailored to this role'
                            : 'Calibrated 4-Pillar Recruitment Intelligence',
                        style: const TextStyle(fontSize: 11, color: AppColors.lightTextSecondary),
                      ),
                    ],
                  ),
                ),
                if (_isRefreshing)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    onPressed: () => _fetchMatchData(bypassCache: true),
                    tooltip: widget.questionsOnly ? 'Regenerate questions' : 'Re-analyze match',
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // If NOT questionsOnly (e.g. recruiter mode), render the full scoring insights
            if (!widget.questionsOnly) ...[
              // Overall Match Score Hero Card
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: scoreBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: scoreColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 54,
                          height: 54,
                          child: CircularProgressIndicator(
                            value: overallScore / 100.0,
                            backgroundColor: scoreColor.withValues(alpha: 0.18),
                            valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
                            strokeWidth: 5.5,
                          ),
                        ),
                        Text(
                          '$overallScore%',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: scoreColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                fitLevel,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: scoreColor,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                overallScore >= 75
                                    ? Icons.verified_rounded
                                    : (overallScore >= 50 ? Icons.thumb_up_alt_rounded : Icons.trending_up_rounded),
                                size: 16,
                                color: scoreColor,
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            overallScore >= 75
                                ? 'High suitability! Your background and project depth align closely with role requirements.'
                                : (overallScore >= 50
                                    ? 'Solid foundation! A few focused revisions on critical gaps will make you interview-ready.'
                                    : 'Moderate match. Review the recommended 48-hour prep checklist before your interview.'),
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 4-Pillar Calibrated Rubric Breakdown
              const Text(
                '4-Pillar Rubric Breakdown',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
              ),
              const SizedBox(height: 8),
              _buildRubricRow('Core Tech Stack Match (40%)', coreTech, isDark),
              const SizedBox(height: 6),
              _buildRubricRow('Project Architecture & Depth (30%)', projectDepth, isDark),
              const SizedBox(height: 6),
              _buildRubricRow('Role Readiness & Tooling (15%)', roleReadiness, isDark),
              const SizedBox(height: 6),
              _buildRubricRow('Skill Gap Learnability (15%)', gapLearnability, isDark),
              const SizedBox(height: 16),

              // Semantic Equivalences Section
              if (equivalences.isNotEmpty) ...[
                Row(
                  children: [
                    const Icon(Icons.sync_alt_rounded, size: 16, color: AppColors.lightPrimary),
                    const SizedBox(width: 6),
                    const Text('Semantic Equivalences Identified', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                  ],
                ),
                const SizedBox(height: 6),
                for (final eq in equivalences.take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkBackground : AppColors.lightBackground,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                eq['student_skill']?.toString() ?? '',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.lightPrimary),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6),
                                child: Icon(Icons.arrow_forward_rounded, size: 12, color: AppColors.lightTextSecondary),
                              ),
                              Expanded(
                                child: Text(
                                  eq['job_requirement']?.toString() ?? '',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.successLightBg,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  eq['transferability']?.toString() ?? 'High',
                                  style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: AppColors.success),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            eq['reasoning']?.toString() ?? '',
                            style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
              ],

              // Project Evidence Section
              if (projectEvidence.isNotEmpty) ...[
                Row(
                  children: [
                    const Icon(Icons.fact_check_outlined, size: 16, color: AppColors.lightPrimary),
                    const SizedBox(width: 6),
                    const Text('Project Competence Evidence', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                  ],
                ),
                const SizedBox(height: 6),
                for (final pe in projectEvidence.take(2))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkBackground : AppColors.lightBackground,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pe['project_title']?.toString() ?? 'Project',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            pe['evidence']?.toString() ?? '',
                            style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
              ],

              // Critical Skill Gaps
              if (skillGaps.isNotEmpty) ...[
                Row(
                  children: [
                    const Icon(Icons.lightbulb_outline_rounded, size: 16, color: AppColors.warning),
                    const SizedBox(width: 6),
                    const Text('High-Priority Skill Gaps to Bridge', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: skillGaps.map((gap) {
                    return Chip(
                      label: Text(gap.toString(), style: const TextStyle(fontSize: 11, color: AppColors.warning)),
                      backgroundColor: AppColors.warningLightBg,
                      side: BorderSide(color: AppColors.warning.withValues(alpha: 0.3)),
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
              ],
            ],

            // Predicted Technical Interview Questions
            if (questions.isNotEmpty) ...[
              if (!widget.questionsOnly)
                Row(
                  children: [
                    const Icon(Icons.quiz_outlined, size: 16, color: AppColors.lightPrimary),
                    const SizedBox(width: 6),
                    const Text('Predicted Technical Interview Questions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                  ],
                ),
              if (!widget.questionsOnly) const SizedBox(height: 8),
              for (int i = 0; i < questions.length; i++)
                () {
                  final rawQ = questions[i];
                  final Map<String, dynamic> qMap = rawQ is Map
                      ? Map<String, dynamic>.from(rawQ)
                      : {'question': rawQ?.toString() ?? ''};
                  final focusArea = qMap['focus_area']?.toString();
                  final questionText = qMap['question']?.toString() ?? '';
                  final expectedConcept = qMap['expected_concept']?.toString();

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkBackground : AppColors.lightBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryLightBg,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Q${i + 1}',
                                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppColors.lightPrimary),
                                  ),
                                ),
                                if (focusArea != null && focusArea.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      focusArea,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const Icon(Icons.help_outline_rounded, size: 15, color: AppColors.lightPrimary),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          questionText,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, height: 1.35),
                        ),
                        if (expectedConcept != null && expectedConcept.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('💡 ', style: TextStyle(fontSize: 11)),
                                Expanded(
                                  child: Text(
                                    'Expected Concept: $expectedConcept',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }(),
              const SizedBox(height: 10),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(16),
                alignment: Alignment.center,
                child: const Text(
                  'No targeted interview questions generated yet. Tap refresh to generate questions.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: AppColors.lightTextSecondary),
                ),
              ),
            ],

            // 48-Hour Prep Action Plan
            if (prepChecklist.isNotEmpty) ...[
              Row(
                children: [
                  const Icon(Icons.timer_outlined, size: 16, color: AppColors.success),
                  const SizedBox(width: 6),
                  const Text('48-Hour Interview Prep Checklist', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                ],
              ),
              const SizedBox(height: 8),
              for (final item in prepChecklist)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_circle_outline_rounded, size: 14, color: AppColors.success),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.toString(),
                          style: TextStyle(fontSize: 11.5, color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary, height: 1.3),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRubricRow(String title, int score, bool isDark) {
    final color = _getScoreColor(score);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '$score/100',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: score / 100.0,
            minHeight: 5,
            backgroundColor: isDark ? AppColors.darkSurfaceContainerHigh : AppColors.lightSurfaceContainer,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}
