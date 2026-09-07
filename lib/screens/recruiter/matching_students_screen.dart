import 'package:flutter/material.dart';
import '../../controllers/paging_controller.dart';
import '../../models/models.dart';
import '../../services/recruiter_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/paginated_list_view.dart';
import '../../widgets/skeleton_widgets.dart';
import '../interview/interview_scheduling_screen.dart';
import 'candidate_detail_screen.dart';

class MatchingStudentsScreen extends StatefulWidget {
  final String driveId;
  final String companyName;
  final String driveTitle;
  final List<String> requiredSkills;

  const MatchingStudentsScreen({
    super.key,
    required this.driveId,
    required this.companyName,
    required this.driveTitle,
    this.requiredSkills = const [],
  });

  @override
  State<MatchingStudentsScreen> createState() => _MatchingStudentsScreenState();
}

class _MatchingStudentsScreenState extends State<MatchingStudentsScreen> {
  final RecruiterService _recruiterService = RecruiterService();
  late PagingController<Map<String, dynamic>> _pagingController;

  String _matchType = 'any'; // 'any' or 'all'
  double? _minCgpa;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  void _initController() {
    _pagingController = PagingController<Map<String, dynamic>>(
      fetchPage: (page, limit) => _recruiterService.getMatchingStudentsPaginated(
        widget.driveId,
        matchType: _matchType,
        minCgpa: _minCgpa,
        page: page,
        limit: limit,
      ),
    );
  }

  void _setMatchType(String type) {
    if (_matchType == type) return;
    setState(() {
      _matchType = type;
      _pagingController.dispose();
      _initController();
    });
  }

  @override
  void dispose() {
    _pagingController.dispose();
    super.dispose();
  }

  Candidate _createCandidate(Map<String, dynamic> item) {
    final matchCount = (item['match_count'] is num ? (item['match_count'] as num).toDouble() : 0.0);
    final totalReq = (item['total_required'] is num && (item['total_required'] as num) > 0)
        ? (item['total_required'] as num).toDouble()
        : (widget.requiredSkills.isNotEmpty ? widget.requiredSkills.length.toDouble() : 0.0);
    final double matchScoreOutOf10 = totalReq > 0
        ? ((matchCount / totalReq) * 10.0).clamp(0.0, 10.0)
        : (matchCount > 0 ? (matchCount <= 10 ? matchCount : 10.0) : 7.5);

    return Candidate(
      id: (item['student_id'] ?? '').toString(),
      name: (item['name'] ?? 'Candidate').toString(),
      roleTitle: widget.driveTitle,
      avatarUrl: (item['avatar_url'] ?? '').toString(),
      location: (item['location'] ?? 'GSFC University').toString(),
      experience: 'Fresher',
      education: (item['branch'] ?? 'Engineering').toString(),
      matchScore: matchScoreOutOf10,
      skills: List<String>.from(item['skills'] ?? item['matched_skills'] ?? []),
      bio: 'CGPA: ${item['cgpa'] ?? 'N/A'}',
      status: 'Available',
      skillGaps: List<String>.from(item['missing_skills'] ?? []),
      cgpa: (item['cgpa'] is num) ? (item['cgpa'] as num).toDouble() : (double.tryParse(item['cgpa']?.toString() ?? '') ?? 0.0),
      resumeUrl: (item['resume_url'] ?? item['resume_link'])?.toString(),
    );
  }

  void _openCandidateDetail(Map<String, dynamic> item) {
    final candidate = _createCandidate(item);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CandidateDetailScreen(
          candidate: candidate,
          onBack: () => Navigator.pop(context),
          onScheduleInterview: () {
            Navigator.pop(context);
            _selectForInterview(item);
          },
          onSendMessage: () {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Opening chat with ${candidate.name}...'),
                duration: const Duration(seconds: 2),
              ),
            );
          },
        ),
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return 'S';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
  }

  void _selectForInterview(Map<String, dynamic> item) {
    final candidate = _createCandidate(item);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InterviewSchedulingScreen(
          candidate: candidate,
          onBack: () => Navigator.pop(context),
          onBookedSuccess: () {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Interview scheduled successfully for ${candidate.name}!'),
                    ),
                  ],
                ),
                backgroundColor: AppColors.success,
              ),
            );
          },
        ),
      ),
    );
  }

  void _showRequiredSkillsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) {
        final theme = Theme.of(modalContext);
        final isDark = theme.brightness == Brightness.dark;

        return DraggableScrollableSheet(
          initialChildSize: 0.72,
          minChildSize: 0.35,
          maxChildSize: 0.92,
          expand: false,
          builder: (sheetContext, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkBackground : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
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
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: isDark ? AppColors.darkPrimaryContainer : AppColors.primaryLightBg,
                          radius: 20,
                          child: const Icon(Icons.psychology_rounded, color: AppColors.lightPrimary, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Required Skills',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${widget.companyName} • ${widget.driveTitle}',
                                style: const TextStyle(fontSize: 12, color: AppColors.lightTextSecondary),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.darkPrimaryContainer : AppColors.primaryLightBg,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${widget.requiredSkills.length} Required',
                            style: const TextStyle(
                              color: AppColors.lightPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(modalContext),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 18, thickness: 0.8),
                  Expanded(
                    child: ListView.separated(
                      controller: scrollController,
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
                      itemCount: widget.requiredSkills.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final skill = widget.requiredSkills[index];
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.darkSurfaceContainerLow : AppColors.lightSurfaceContainerLow,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: isDark ? AppColors.darkPrimaryContainer : AppColors.primaryLightBg,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    '${index + 1}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.lightPrimary,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  skill,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.check_circle_rounded, size: 18, color: AppColors.lightPrimary),
                            ],
                          ),
                        );
                      },
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Candidate Skill Matching',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              '${widget.companyName} • ${widget.driveTitle}',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Filter & Criteria Header Card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
              border: Border(
                bottom: BorderSide(
                  color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: SegmentedButton<String>(
                        style: SegmentedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                        ),
                        segments: const [
                          ButtonSegment<String>(
                            value: 'any',
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('Any Match', maxLines: 1),
                            ),
                            icon: Icon(Icons.filter_list_rounded, size: 15),
                          ),
                          ButtonSegment<String>(
                            value: 'all',
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('All Skills', maxLines: 1),
                            ),
                            icon: Icon(Icons.done_all_rounded, size: 15),
                          ),
                        ],
                        selected: {_matchType},
                        onSelectionChanged: (newSelection) {
                          _setMatchType(newSelection.first);
                        },
                      ),
                    ),
                  ],
                ),
                if (widget.requiredSkills.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      // Interactive Required Skills Button
                      InkWell(
                        onTap: () => _showRequiredSkillsModal(context),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.darkPrimaryContainer : AppColors.primaryLightBg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isDark ? AppColors.darkPrimary : AppColors.lightPrimary.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.psychology_rounded, size: 16, color: AppColors.lightPrimary),
                              const SizedBox(width: 6),
                              Text(
                                'Required Skills (${widget.requiredSkills.length})',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.lightPrimary,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: AppColors.lightPrimary),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Candidates Paginated List
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _pagingController.refresh(),
              child: PaginatedListView<Map<String, dynamic>>(
                controller: _pagingController,
                itemKey: (item) => ValueKey(item['student_id'] ?? item.hashCode),
                skeletonBuilder: (_, _) => const DriveCardSkeleton(),
                emptyWidget: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.person_search_outlined,
                          size: 64,
                          color: AppColors.lightTextSecondary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _matchType == 'all'
                              ? 'No Students Have All Required Skills'
                              : 'No Matching Students Found',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _matchType == 'all'
                              ? 'Try switching to "Any Skill Match" to discover candidates with partial matching skills.'
                              : 'No registered students have matched the extracted skills for this drive yet.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 13, color: AppColors.lightTextSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
                itemBuilder: (context, item, index) {
                  final name = (item['name'] ?? 'Student Candidate').toString();
                  final branch = (item['branch'] ?? 'Engineering').toString();
                  final matchedSkills = List<String>.from(item['matched_skills'] ?? []);
                  final missingSkills = List<String>.from(item['missing_skills'] ?? []);
                  final matchCount = item['match_count'] ?? matchedSkills.length;
                  final totalReq = item['total_required'] ?? (widget.requiredSkills.isNotEmpty ? widget.requiredSkills.length : (matchedSkills.length + missingSkills.length));
                  final safeTotalReq = totalReq > 0 ? totalReq : 1;
                  final matchPct = totalReq > 0 ? ((matchCount / totalReq) * 100).round() : 100;
                  final isFullMatch = matchCount >= totalReq && totalReq > 0;
                  final initials = _getInitials(name);

                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1B1A2A) : Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isDark ? const Color(0xFF2C2A40) : const Color(0xFFE2E8F0),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isDark ? Colors.black.withValues(alpha: 0.3) : const Color(0xFF64748B).withValues(alpha: 0.07),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => _openCandidateDetail(item),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Top info row: Gradient Squircle Avatar, Name, Branch
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // Gradient Squircle Avatar with dual initials
                                  Container(
                                    width: 46,
                                    height: 46,
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF6366F1).withValues(alpha: 0.28),
                                          blurRadius: 8,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: Text(
                                        initials,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  // Candidate Name and Branch
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: -0.3,
                                            color: isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A),
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.school_outlined,
                                              size: 13.5,
                                              color: isDark ? AppColors.darkTextSecondary : const Color(0xFF64748B),
                                            ),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                branch,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w500,
                                                  color: isDark ? AppColors.darkTextSecondary : const Color(0xFF64748B),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 13),
                              Container(
                                height: 1,
                                color: isDark ? const Color(0xFF262438) : const Color(0xFFF1F5F9),
                              ),
                              const SizedBox(height: 12),

                              // AI Skill Match Compatibility Assessment Banner
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8.5),
                                decoration: BoxDecoration(
                                  color: isFullMatch
                                      ? (isDark ? const Color(0x1610B981) : const Color(0xFFF0FDF4))
                                      : (isDark ? const Color(0x163B82F6) : const Color(0xFFF8FAFC)),
                                  borderRadius: BorderRadius.circular(11),
                                  border: Border.all(
                                    color: isFullMatch
                                        ? (isDark ? const Color(0x3510B981) : const Color(0xFFDCFCE7))
                                        : (isDark ? const Color(0x353B82F6) : const Color(0xFFE2E8F0)),
                                    width: 1,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          isFullMatch ? Icons.auto_awesome_rounded : Icons.pie_chart_rounded,
                                          size: 14.5,
                                          color: isFullMatch
                                              ? (isDark ? const Color(0xFF34D399) : const Color(0xFF16A34A))
                                              : (isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB)),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          isFullMatch ? 'Full Skill Match' : 'Partial Skill Match',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: isFullMatch
                                                ? (isDark ? const Color(0xFF34D399) : const Color(0xFF15803D))
                                                : (isDark ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8)),
                                          ),
                                        ),
                                        const Spacer(),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7.5, vertical: 2.5),
                                          decoration: BoxDecoration(
                                            color: isFullMatch
                                                ? (isDark ? const Color(0x3010B981) : const Color(0xFFDCFCE7))
                                                : (isDark ? const Color(0x303B82F6) : const Color(0xFFE0E7FF)),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            '$matchCount of $totalReq ($matchPct%)',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: isFullMatch
                                                  ? (isDark ? const Color(0xFF34D399) : const Color(0xFF166534))
                                                  : (isDark ? const Color(0xFF93C5FD) : const Color(0xFF1E40AF)),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 7),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(3),
                                      child: LinearProgressIndicator(
                                        value: (matchCount / safeTotalReq).clamp(0.0, 1.0),
                                        minHeight: 4,
                                        backgroundColor: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          isFullMatch
                                              ? (isDark ? const Color(0xFF10B981) : const Color(0xFF16A34A))
                                              : (isDark ? const Color(0xFF3B82F6) : const Color(0xFF2563EB)),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Skill Micro-Pills: Matched vs Missing
                              if (matchedSkills.isNotEmpty || missingSkills.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    ...matchedSkills.map((s) => Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
                                          decoration: BoxDecoration(
                                            color: isDark ? const Color(0x1F10B981) : const Color(0xFFF0FDF4),
                                            borderRadius: BorderRadius.circular(7),
                                            border: Border.all(
                                              color: isDark ? const Color(0x4010B981) : const Color(0xFFBBF7D0),
                                              width: 0.8,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.check_rounded,
                                                size: 13,
                                                color: isDark ? const Color(0xFF34D399) : const Color(0xFF16A34A),
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                s,
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: isDark ? const Color(0xFF34D399) : const Color(0xFF15803D),
                                                ),
                                              ),
                                            ],
                                          ),
                                        )),
                                    ...missingSkills.map((s) => Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
                                          decoration: BoxDecoration(
                                            color: isDark ? const Color(0x0EFFFFFF) : const Color(0xFFF8FAFC),
                                            borderRadius: BorderRadius.circular(7),
                                            border: Border.all(
                                              color: isDark ? const Color(0x1EFFFFFF) : const Color(0xFFE2E8F0),
                                              width: 0.8,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.close_rounded,
                                                size: 12,
                                                color: isDark ? AppColors.darkTextSecondary : const Color(0xFF94A3B8),
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                s,
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w500,
                                                  color: isDark ? AppColors.darkTextSecondary : const Color(0xFF64748B),
                                                ),
                                              ),
                                            ],
                                          ),
                                        )),
                                  ],
                                ),
                              ],

                              const SizedBox(height: 14),

                              // Dual Action Footer: View Profile & Select for Interview
                              Row(
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () => _openCandidateDetail(item),
                                    icon: const Icon(Icons.person_outline_rounded, size: 16),
                                    label: const Text('Profile'),
                                    style: OutlinedButton.styleFrom(
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                                      side: BorderSide(
                                        color: isDark ? const Color(0xFF37354C) : const Color(0xFFCBD5E1),
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: () => _selectForInterview(item),
                                      icon: const Icon(Icons.event_available_rounded, size: 16),
                                      label: const FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text('Select for Interview'),
                                      ),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: AppColors.lightPrimary,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                                        padding: const EdgeInsets.symmetric(vertical: 10),
                                        elevation: 0,
                                        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
