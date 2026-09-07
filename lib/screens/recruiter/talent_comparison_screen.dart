import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import '../../network/api_client.dart';
import '../../services/recruiter_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_avatar.dart';

class TalentComparisonScreen extends StatefulWidget {
  final String driveId;
  final String companyName;
  final String interviewJob;

  const TalentComparisonScreen({
    super.key,
    required this.driveId,
    required this.companyName,
    required this.interviewJob,
  });

  @override
  State<TalentComparisonScreen> createState() => _TalentComparisonScreenState();
}

class _TalentComparisonScreenState extends State<TalentComparisonScreen> {
  final RecruiterService _recruiterService = RecruiterService();

  bool _isLoading = true;
  String _errorMessage = '';
  List<Map<String, dynamic>> _candidates = [];
  List<String> _requiredSkills = [];
  String _selectedFilter = 'all'; // 'all', 'top', 'internships', 'devops'

  @override
  void initState() {
    super.initState();
    _fetchComparison();
  }

  Future<void> _fetchComparison() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    final data = await _recruiterService.getTalentComparison(widget.driveId);

    if (!mounted) return;

    if (data != null && data['candidates'] is List) {
      setState(() {
        _candidates = List<Map<String, dynamic>>.from(data['candidates'] as List);
        if (data['required_skills'] is List) {
          _requiredSkills = List<String>.from(data['required_skills'] as List);
        }
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Could not load candidate comparison data.';
      });
    }
  }

  List<Map<String, dynamic>> get _filteredCandidates {
    switch (_selectedFilter) {
      case 'top':
        return _candidates.where((c) => (c['composite_score'] as num? ?? 0) >= 70).toList();
      case 'internships':
        return _candidates.where((c) => (c['internship_count'] as num? ?? 0) > 0).toList();
      case 'devops':
        return _candidates.where((c) {
          final dep = c['deployment_skills'];
          return dep is List && dep.isNotEmpty;
        }).toList();
      default:
        return _candidates;
    }
  }

  Color _getRankColor(int rank) {
    switch (rank) {
      case 1:
        return const Color(0xFFFFD700); // Gold
      case 2:
        return const Color(0xFFC0C0C0); // Silver
      case 3:
        return const Color(0xFFCD7F32); // Bronze
      default:
        return AppColors.lightPrimary;
    }
  }

  Future<void> _viewResume(Map<String, dynamic> candidate) async {
    final resumeLink = (candidate['resume_url'] ?? '').toString().trim();
    final name = (candidate['name'] ?? 'Candidate').toString();

    if (resumeLink.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No resume uploaded for this candidate.')),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Opening resume document...'), duration: Duration(milliseconds: 1200)),
    );

    try {
      final dio = ApiClient.instance.dio;
      String endpoint = resumeLink;
      if (!resumeLink.startsWith('http')) {
        endpoint = resumeLink.startsWith('/') ? resumeLink : '/$resumeLink';
      }

      final tempDir = Directory.systemTemp;
      final safeName = '${name.replaceAll(' ', '_')}_resume.pdf';
      final tempPdf = File('${tempDir.path}/$safeName');

      final response = await dio.get<List<int>>(
        endpoint,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'ngrok-skip-browser-warning': 'true'},
        ),
      );

      if (response.statusCode == 200 && response.data != null && response.data!.isNotEmpty) {
        await tempPdf.writeAsBytes(response.data!);
        await OpenFilex.open(tempPdf.path);
        return;
      }
    } catch (_) {}

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open resume file.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final filtered = _filteredCandidates;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Compare & Rank Top Talent'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetchComparison,
            tooltip: 'Re-evaluate Candidates',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 14),
                  Text(
                    'Analyzing candidates across Skills, Deployment & Internships...',
                    style: TextStyle(fontSize: 13, color: AppColors.lightTextSecondary),
                  ),
                ],
              ),
            )
          : _errorMessage.isNotEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.warning),
                      const SizedBox(height: 12),
                      Text(_errorMessage, style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      ElevatedButton(
                        onPressed: _fetchComparison,
                        child: const Text('Try Again'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Header Scoring Explanation Card
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.auto_awesome_rounded, size: 18, color: AppColors.lightPrimary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${widget.companyName} • ${widget.interviewJob}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryLightBg,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${_candidates.length} Ranked',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.lightPrimary),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Candidates are evaluated using 3 weighted pillars: 40% Core Skills, 30% Deployment/DevOps Knowledge, and 30% Verified Internships.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                              height: 1.35,
                            ),
                          ),
                          if (_requiredSkills.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: _requiredSkills.take(6).map((sk) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isDark ? AppColors.darkSurfaceContainerHigh : AppColors.lightSurfaceContainer,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    sk,
                                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Filter Chips Bar
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: Row(
                        children: [
                          _buildFilterChip('all', 'All Candidates (${_candidates.length})'),
                          const SizedBox(width: 8),
                          _buildFilterChip('top', 'Top Fit (70%+)'),
                          const SizedBox(width: 8),
                          _buildFilterChip('internships', 'Has Internships'),
                          const SizedBox(width: 8),
                          _buildFilterChip('devops', 'Cloud / DevOps Ready'),
                        ],
                      ),
                    ),

                    // Candidate List
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.filter_list_off_rounded, size: 42, color: AppColors.lightTextSecondary),
                                  const SizedBox(height: 8),
                                  const Text('No candidates match this filter', style: TextStyle(fontWeight: FontWeight.bold)),
                                  TextButton(
                                    onPressed: () => setState(() => _selectedFilter = 'all'),
                                    child: const Text('Show All Candidates'),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final cand = filtered[index];
                                final rank = (cand['rank'] as num? ?? index + 1).toInt();
                                final name = (cand['name'] ?? 'Candidate').toString();
                                final course = (cand['course'] ?? 'Engineering').toString();
                                final cgpa = (cand['cgpa'] as num? ?? 0.0).toDouble();
                                final compositeScore = (cand['composite_score'] as num? ?? 0.0).toDouble();
                                final skillScore = (cand['skill_score'] as num? ?? 0.0).toDouble();
                                final depScore = (cand['deployment_score'] as num? ?? 0.0).toDouble();
                                final internshipCount = (cand['internship_count'] as num? ?? 0).toInt();
                                final depSkills = (cand['deployment_skills'] as List?) ?? [];
                                final strengths = (cand['strengths_summary'] ?? '').toString();

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    side: BorderSide(
                                      color: rank <= 3
                                          ? _getRankColor(rank).withValues(alpha: 0.6)
                                          : (isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant),
                                      width: rank <= 3 ? 1.5 : 1,
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Header Row: Rank Medal, Avatar, Name, Composite Score
                                        Row(
                                          children: [
                                            // Rank Badge
                                            Container(
                                              width: 32,
                                              height: 32,
                                              decoration: BoxDecoration(
                                                color: _getRankColor(rank).withValues(alpha: rank <= 3 ? 0.2 : 0.1),
                                                shape: BoxShape.circle,
                                                border: Border.all(color: _getRankColor(rank)),
                                              ),
                                              alignment: Alignment.center,
                                              child: Text(
                                                '#$rank',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: rank <= 3 ? _getRankColor(rank) : AppColors.lightPrimary,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 10),

                                            AppAvatar(
                                              radius: 20,
                                              imageUrl: '',
                                              fallbackText: name,
                                            ),
                                            const SizedBox(width: 10),

                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    name,
                                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  Text(
                                                    '$course • CGPA: ${cgpa.toStringAsFixed(2)}',
                                                    style: TextStyle(
                                                      fontSize: 11.5,
                                                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),

                                            // Composite Score
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                              decoration: BoxDecoration(
                                                color: compositeScore >= 70
                                                    ? AppColors.successLightBg
                                                    : (compositeScore >= 50
                                                        ? AppColors.primaryLightBg
                                                        : AppColors.warning.withValues(alpha: 0.15)),
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Column(
                                                children: [
                                                  Text(
                                                    '${compositeScore.toStringAsFixed(1)}%',
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.bold,
                                                      color: compositeScore >= 70
                                                          ? AppColors.success
                                                          : (compositeScore >= 50 ? AppColors.lightPrimary : AppColors.warning),
                                                    ),
                                                  ),
                                                  const Text(
                                                    'Rank Score',
                                                    style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w600),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        const Divider(height: 1),
                                        const SizedBox(height: 10),

                                        // 3 Pillars Breakdown Bars
                                        Row(
                                          children: [
                                            Expanded(
                                              child: _buildMetricPill(
                                                'Skills',
                                                '${skillScore.toInt()}%',
                                                Icons.code_rounded,
                                                AppColors.lightPrimary,
                                                isDark,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: _buildMetricPill(
                                                'Deployment',
                                                '${depScore.toInt()}%',
                                                Icons.cloud_done_rounded,
                                                depScore > 0 ? AppColors.success : AppColors.lightTextSecondary,
                                                isDark,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: _buildMetricPill(
                                                'Internships',
                                                '$internshipCount Done',
                                                Icons.work_history_rounded,
                                                internshipCount > 0 ? AppColors.success : AppColors.lightTextSecondary,
                                                isDark,
                                              ),
                                            ),
                                          ],
                                        ),

                                        if (depSkills.isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: 4,
                                            children: depSkills.map((ds) {
                                              return Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: AppColors.success.withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                                                ),
                                                child: Text(
                                                  '☁ $ds',
                                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.success),
                                                ),
                                              );
                                            }).toList(),
                                          ),
                                        ],

                                        if (strengths.isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          Text(
                                            '💡 $strengths',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                        ],

                                        const SizedBox(height: 10),
                                        // Action Row: View Resume
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: OutlinedButton.icon(
                                            onPressed: () => _viewResume(cand),
                                            icon: const Icon(Icons.picture_as_pdf_rounded, size: 14, color: AppColors.error),
                                            label: const Text('View Resume', style: TextStyle(fontSize: 11.5)),
                                            style: OutlinedButton.styleFrom(
                                              visualDensity: VisualDensity.compact,
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildFilterChip(String filterKey, String label) {
    final isSelected = _selectedFilter == filterKey;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        setState(() {
          _selectedFilter = filterKey;
        });
      },
      labelStyle: TextStyle(
        fontSize: 11.5,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        color: isSelected ? Colors.white : null,
      ),
      selectedColor: AppColors.lightPrimary,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildMetricPill(String title, String value, IconData icon, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceContainerHigh : AppColors.lightSurfaceContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 10, color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
