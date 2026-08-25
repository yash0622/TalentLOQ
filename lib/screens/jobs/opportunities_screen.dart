import 'package:flutter/material.dart';
import '../../controllers/paging_controller.dart';
import '../../services/drive_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/paginated_list_view.dart';
import '../../widgets/skeleton_widgets.dart';
import 'company_detail_screen.dart';

class OpportunitiesScreen extends StatefulWidget {
  final double studentCgpa;
  final bool hasResume;
  final VoidCallback? onNavigateToProfile;
  final bool embedInTab;

  const OpportunitiesScreen({
    super.key,
    this.studentCgpa = 8.0,
    this.hasResume = true,
    this.onNavigateToProfile,
    this.embedInTab = false,
  });

  @override
  State<OpportunitiesScreen> createState() => _OpportunitiesScreenState();
}

class _OpportunitiesScreenState extends State<OpportunitiesScreen> {
  final DriveService _driveService = DriveService();
  final TextEditingController _searchController = TextEditingController();
  late final PagingController<Map<String, dynamic>> _pagingController;

  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _pagingController = PagingController<Map<String, dynamic>>(
      fetchPage: (page, limit) => _driveService.getPublishedDrivesPaginated(page: page, limit: limit),
    );
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _pagingController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.trim().toLowerCase();
    });
  }

  void _openDetail(Map<String, dynamic> item) {
    Navigator.push(
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
  }

  @override
  Widget build(BuildContext context) {
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
                  hintText: 'Search by company, role, or qualification...',
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
                        const Text(
                          'No Placement Drives Found',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Check back soon! Placement officers will publish active hiring drives shortly.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: AppColors.lightTextSecondary),
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
                                    'CTC: ₹${ctcMin}L - ₹${ctcMax}L / yr • $empType',
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
