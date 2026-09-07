import 'package:flutter/material.dart';
import '../../controllers/paging_controller.dart';
import '../../services/drive_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/paginated_list_view.dart';
import '../../widgets/skeleton_widgets.dart';
import 'company_detail_screen.dart';

import '../../services/application_visibility_state.dart';

class OpportunitiesScreen extends StatefulWidget {
  final double studentCgpa;
  final bool hasResume;
  final VoidCallback? onNavigateToProfile;
  final bool embedInTab;
  final String initialFilterMode;

  const OpportunitiesScreen({
    super.key,
    this.studentCgpa = 8.0,
    this.hasResume = true,
    this.onNavigateToProfile,
    this.embedInTab = false,
    this.initialFilterMode = 'all',
  });

  @override
  State<OpportunitiesScreen> createState() => _OpportunitiesScreenState();
}

class _OpportunitiesScreenState extends State<OpportunitiesScreen> with AutomaticKeepAliveClientMixin {
  final DriveService _driveService = DriveService();
  final TextEditingController _searchController = TextEditingController();
  late final PagingController<Map<String, dynamic>> _pagingController;

  String _searchQuery = '';
  late String _filterMode;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _filterMode = widget.initialFilterMode;
    ApplicationVisibilityState.instance.addListener(_onApplicationRecorded);
    _initPagingController();
    _searchController.addListener(_onSearchChanged);
    // Prefetch student's existing applications into visibility cache
    _driveService.getMyApplicationsPaginated(page: 1, limit: 100);
  }

  void _initPagingController() {
    _pagingController = PagingController<Map<String, dynamic>>(
      fetchPage: (page, limit) => _filterMode == 'matched'
          ? _driveService.getRecommendedDrivesPaginated(page: page, limit: limit)
          : _driveService.getPublishedDrivesPaginated(page: page, limit: limit),
    );
  }

  @override
  void didUpdateWidget(covariant OpportunitiesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialFilterMode != widget.initialFilterMode) {
      setState(() {
        _filterMode = widget.initialFilterMode;
        _pagingController.dispose();
        _initPagingController();
      });
    }
  }

  void _onApplicationRecorded() {
    if (mounted) {
      _pagingController.refresh();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _pagingController.dispose();
    ApplicationVisibilityState.instance.removeListener(_onApplicationRecorded);
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.trim().toLowerCase();
    });
  }

  Future<void> _openDetail(Map<String, dynamic> item) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CompanyDetailScreen(
          listingId: (item['listing_id'] ?? item['drive_id'] ?? '').toString(),
          initialData: item,
          studentCgpa: widget.studentCgpa,
          hasResume: widget.hasResume,
          onNavigateToProfile: widget.onNavigateToProfile,
        ),
      ),
    );
    if (mounted) {
      _pagingController.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final body = RefreshIndicator(
      onRefresh: () => _pagingController.refresh(),
      child: Column(
          children: [
            // Search Input Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: _filterMode == 'matched'
                      ? 'Search matched opportunities...'
                      : 'Search by company, role, or qualification...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged();
                          },
                        )
                      : null,
                ),
              ),
            ),

            // Paginated Drives List View
            Expanded(
              child: PaginatedListView<Map<String, dynamic>>(
                controller: _pagingController,
                itemKey: (item) => ValueKey(item['drive_id'] ?? item['listing_id'] ?? item.hashCode),
                skeletonBuilder: (_, _) => const DriveCardSkeleton(),
                emptyWidget: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.campaign_outlined, size: 54, color: AppColors.lightTextSecondary),
                        const SizedBox(height: 12),
                        Text(
                          _filterMode == 'matched'
                              ? 'No Matching Drives Yet'
                              : 'No Placement Drives Found',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _filterMode == 'matched'
                              ? 'Make sure your resume is uploaded with your skills to discover drives tailored to you.'
                              : 'Check back soon! Placement officers will publish active hiring drives shortly.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12, color: AppColors.lightTextSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
                itemBuilder: (context, item, index) {
                  if (_searchQuery.isNotEmpty) {
                    final name = (item['company_name'] ?? '').toString().toLowerCase();
                    final title = (item['drive_title'] ?? item['interview_job'] ?? '').toString().toLowerCase();
                    final desc = (item['description'] ?? '').toString().toLowerCase();
                    if (!name.contains(_searchQuery) && !title.contains(_searchQuery) && !desc.contains(_searchQuery)) {
                      return const SizedBox.shrink();
                    }
                  }

                  final companyName = item['company_name'] ?? 'Company Name';
                  final driveTitle = item['drive_title'] ?? item['interview_job'] ?? 'Placement Drive';
                  final empType = (item['employment_type'] ?? 'full_time').toString().replaceAll('_', ' ').toUpperCase();
                  final ctcMin = item['ctc_min'] ?? 6.0;
                  final ctcMax = item['ctc_max'] ?? 12.0;
                  final isEligible = item['is_eligible'] ?? true;
                  final snippet = item['description'] ?? '';

                  return Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _openDetail(item),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryLightBg,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.business_rounded,
                                    color: AppColors.lightPrimary,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        companyName,
                                        style: theme.textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        driveTitle,
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          color: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),

                                // Is Eligible Badge
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isEligible
                                        ? AppColors.successLightBg
                                        : AppColors.warning.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    isEligible ? '✔ Eligible' : '⚠ Not Eligible',
                                    style: TextStyle(
                                      color: isEligible ? AppColors.success : AppColors.warning,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // Eligibility Details Summary Pill
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: isDark ? AppColors.darkSurfaceContainerHigh : AppColors.lightSurfaceContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.school_rounded, size: 14, color: AppColors.lightPrimary),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Min CGPA: ${item['min_cgpa'] ?? item['cgpa_criteria'] ?? 6.0} • Eligible: ${(item['eligible_courses'] as List?)?.join(', ') ?? 'All Courses'}',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Skill Overlap Summary Badge (if present)
                            if (item['match_summary'] != null && item['match_summary'].toString().isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: AppColors.success.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.auto_awesome_rounded, size: 14, color: AppColors.success),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        item['match_summary'].toString(),
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.success,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 10),

                            // Description Snippet
                            Text(
                              snippet.toString(),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                fontSize: 13,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 12),

                            // CTC & Employment Type Pills
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    'CTC: ₹${(ctcMin is num && ctcMin % 1 == 0) ? ctcMin.toInt() : ctcMin} - ₹${(ctcMax is num && ctcMax % 1 == 0) ? ctcMax.toInt() : ctcMax} LPA • $empType',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.lightTextSecondary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'View Details',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.lightPrimary,
                                      ),
                                    ),
                                    SizedBox(width: 2),
                                    Icon(Icons.arrow_forward_rounded, size: 14, color: AppColors.lightPrimary),
                                  ],
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
      );

    if (widget.embedInTab) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Campus Placement Opportunities'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _pagingController.refresh(),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: body,
    );
  }
}
