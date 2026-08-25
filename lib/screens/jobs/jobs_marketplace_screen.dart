import 'package:flutter/material.dart';
import '../../mock_data/mock_data.dart';
import '../../models/models.dart';
import '../../theme/app_colors.dart';
import 'salary_filter_bottom_sheet.dart';
import 'opportunities_screen.dart';
import '../application/my_applications_screen.dart';
import '../../widgets/skeleton_widgets.dart';

import '../../services/drive_service.dart';

class JobsMarketplaceScreen extends StatefulWidget {
  final Function(Job) onSelectJob;

  const JobsMarketplaceScreen({super.key, required this.onSelectJob});

  @override
  State<JobsMarketplaceScreen> createState() => _JobsMarketplaceScreenState();
}

class _JobsMarketplaceScreenState extends State<JobsMarketplaceScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _searchQuery = '';
  String _selectedType = 'All';
  RangeValues _salaryRange = const RangeValues(0, 100);
  List<Job> _realJobs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _syncBackendDrives();
  }

  Future<void> _syncBackendDrives() async {
    setState(() => _isLoading = true);
    try {
      final drives = await DriveService().getPublishedDrives();
      final List<Job> loaded = [];
      if (drives.isNotEmpty) {
        for (var d in drives) {
          final id = (d['drive_id'] ?? d['listing_id'] ?? '').toString();
          final rawMin = d['ctc_min'];
          final rawMax = d['ctc_max'];
          final ctcMin =
              (rawMin != null
                      ? (double.tryParse(rawMin.toString()) ?? 6.0)
                      : 6.0)
                  .round();
          final ctcMax =
              (rawMax != null
                      ? (double.tryParse(rawMax.toString()) ?? 12.0)
                      : 12.0)
                  .round();

          loaded.add(
            Job(
              id: id,
              title:
                  d['interview_job'] ?? d['drive_title'] ?? 'Placement Drive',
              company: d['company_name'] ?? d['company'] ?? 'Company',
              logoUrl: '',
              location: d['location'] ?? d['interview_venue'] ?? 'On Campus',
              jobType: (d['mode'] ?? 'Full-Time').toString().replaceAll(
                '_',
                ' ',
              ),
              salaryRange: '₹${ctcMin}L - ₹${ctcMax}L / year',
              salaryMin: ctcMin,
              salaryMax: ctcMax,
              description: d['description'] ?? 'Campus Placement Drive',
              requirements:
                  (d['required_skills'] as List?)
                      ?.map((e) => e.toString())
                      .toList() ??
                  ['Problem Solving', 'Communication'],
              perks: ['Health Insurance', 'Performance Bonus'],
              postedTime: 'Recently',
              applicantCount: 12,
            ),
          );
        }
      }

      if (mounted) {
        setState(() {
          _realJobs = loaded;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<Job> get _filteredJobs {
    final list = _realJobs.isNotEmpty ? _realJobs : MockData.jobs;
    return list.where((job) {
      final matchesQuery =
          _searchQuery.isEmpty ||
          job.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          job.company.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          job.location.toLowerCase().contains(_searchQuery.toLowerCase());

      final matchesType =
          _selectedType == 'All' ||
          job.jobType.toLowerCase().contains(_selectedType.toLowerCase());

      return matchesQuery && matchesType;
    }).toList();
  }

  void _openSalaryFilter() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SalaryFilterBottomSheet(
        currentRange: _salaryRange,
        selectedType: _selectedType,
        onApply: (range, type) {
          setState(() {
            _salaryRange = range;
            _selectedType = type;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      children: [
        // Top TabBar for Jobs Section
        Container(
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: isDark
                ? AppColors.darkPrimary
                : AppColors.lightPrimary,
            labelColor: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
            unselectedLabelColor: isDark
                ? AppColors.darkTextSecondary
                : AppColors.lightTextSecondary,
            labelStyle: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
            tabs: const [
              Tab(text: 'Explore Roles'),
              Tab(text: 'Applications (3)'),
              Tab(text: 'Saved Jobs (2)'),
            ],
          ),
        ),

        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // TAB 1: Explore Roles Marketplace
              Column(
                children: [
                  // Campus Drives & Applications Quick Navigation Banner
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    color: isDark
                        ? AppColors.darkSurfaceContainerHigh
                        : AppColors.lightSurfaceContainer,
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const OpportunitiesScreen(),
                              ),
                            ),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primaryLightBg,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.business_center_rounded,
                                    color: AppColors.lightPrimary,
                                    size: 16,
                                  ),
                                  SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      'Campus Drives',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                        color: AppColors.lightPrimary,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: InkWell(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const MyApplicationsScreen(),
                              ),
                            ),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.successLightBg,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.assignment_turned_in_rounded,
                                    color: AppColors.success,
                                    size: 16,
                                  ),
                                  SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      'My Applications',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                        color: AppColors.success,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Search & Filter Header
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkSurface
                          : AppColors.lightSurface,
                      border: Border(
                        bottom: BorderSide(
                          color: isDark
                              ? AppColors.darkOutlineVariant
                              : AppColors.lightOutlineVariant,
                          width: 1,
                        ),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                onChanged: (val) =>
                                    setState(() => _searchQuery = val),
                                style: const TextStyle(fontSize: 14),
                                decoration: InputDecoration(
                                  hintText:
                                      'Search roles, skills, or companies...',
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  isDense: true,
                                  prefixIcon: const Icon(
                                    Icons.search_rounded,
                                    size: 20,
                                  ),
                                  suffixIcon: _searchQuery.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(
                                            Icons.clear_rounded,
                                            size: 18,
                                          ),
                                          onPressed: () =>
                                              setState(() => _searchQuery = ''),
                                        )
                                      : null,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: _openSalaryFilter,
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? AppColors.darkPrimaryContainer
                                      : AppColors.lightPrimary,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.tune_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Filter Chips Row
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _buildFilterChip(
                                'All',
                                _selectedType == 'All',
                                () => setState(() => _selectedType = 'All'),
                              ),
                              const SizedBox(width: 8),
                              _buildFilterChip(
                                'Full-Time',
                                _selectedType == 'Full-Time',
                                () =>
                                    setState(() => _selectedType = 'Full-Time'),
                              ),
                              const SizedBox(width: 8),
                              _buildFilterChip(
                                'Remote',
                                _selectedType == 'Remote',
                                () => setState(() => _selectedType = 'Remote'),
                              ),
                              const SizedBox(width: 8),
                              _buildFilterChip(
                                'High Salary (₹20L+)',
                                _selectedType == '20L',
                                () {
                                  setState(() {
                                    _selectedType = '20L';
                                    _salaryRange = const RangeValues(20, 50);
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Jobs Listing Body
                  Expanded(
                    child: _isLoading
                        ? ListView.builder(
                            padding: const EdgeInsets.all(20),
                            itemCount: 4,
                            itemBuilder: (_, index) => const Padding(
                              padding: EdgeInsets.only(bottom: 12),
                              child: DriveCardSkeleton(),
                            ),
                          )
                        : _filteredJobs.isEmpty
                        ? RefreshIndicator(
                            onRefresh: _syncBackendDrives,
                            child: SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              child: Container(
                                height: 350,
                                alignment: Alignment.center,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.business_center_outlined,
                                      size: 54,
                                      color: theme.hintColor,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No jobs available right now',
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Pull down to refresh or check back soon.',
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: AppColors.lightTextSecondary,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _syncBackendDrives,
                            child: ListView.separated(
                              padding: const EdgeInsets.all(20),
                              itemCount: _filteredJobs.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 14),
                              itemBuilder: (context, index) {
                                final job = _filteredJobs[index];
                                return Card(
                                  child: InkWell(
                                    onTap: () => widget.onSelectJob(job),
                                    borderRadius: BorderRadius.circular(14),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Container(
                                                width: 38,
                                                height: 38,
                                                decoration: BoxDecoration(
                                                  color: isDark
                                                      ? AppColors
                                                            .darkSurfaceContainerHigh
                                                      : AppColors
                                                            .lightSurfaceContainer,
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                                child: const Icon(
                                                  Icons.business_center_rounded,
                                                  color: AppColors.lightPrimary,
                                                  size: 20,
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      job.title,
                                                      style: theme
                                                          .textTheme
                                                          .titleMedium
                                                          ?.copyWith(
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            fontSize: 14,
                                                          ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      '${job.company} • ${job.location}',
                                                      style: theme
                                                          .textTheme
                                                          .bodySmall
                                                          ?.copyWith(
                                                            fontSize: 11,
                                                            color: isDark
                                                                ? AppColors
                                                                      .darkTextSecondary
                                                                : AppColors
                                                                      .lightTextSecondary,
                                                          ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              IconButton(
                                                constraints:
                                                    const BoxConstraints(),
                                                padding: const EdgeInsets.all(
                                                  2,
                                                ),
                                                icon: Icon(
                                                  job.isSaved
                                                      ? Icons.bookmark_rounded
                                                      : Icons
                                                            .bookmark_border_rounded,
                                                  color: job.isSaved
                                                      ? AppColors.lightPrimary
                                                      : null,
                                                  size: 18,
                                                ),
                                                onPressed: () {},
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            job.description,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                                  fontSize: 12,
                                                  height: 1.35,
                                                  color: isDark
                                                      ? AppColors
                                                            .darkTextSecondary
                                                      : AppColors
                                                            .lightTextSecondary,
                                                ),
                                          ),
                                          const SizedBox(height: 10),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Wrap(
                                                  spacing: 6,
                                                  runSpacing: 4,
                                                  children: [
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 8,
                                                            vertical: 4,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: isDark
                                                            ? AppColors
                                                                  .darkSurfaceContainerLow
                                                            : AppColors
                                                                  .lightSurfaceContainerLow,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              6,
                                                            ),
                                                      ),
                                                      child: Text(
                                                        job.jobType,
                                                        style: theme
                                                            .textTheme
                                                            .labelMedium
                                                            ?.copyWith(
                                                              fontSize: 11,
                                                            ),
                                                      ),
                                                    ),
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 8,
                                                            vertical: 4,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: AppColors
                                                            .successLightBg,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              6,
                                                            ),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          const Text(
                                                            '💰 ',
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                            ),
                                                          ),
                                                          Text(
                                                            job.salaryRange,
                                                            style:
                                                                const TextStyle(
                                                                  color: AppColors
                                                                      .success,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  fontSize: 11,
                                                                ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    '${job.applicantCount} applicants',
                                                    style: theme
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                          fontSize: 11,
                                                        ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  const Icon(
                                                    Icons
                                                        .arrow_forward_ios_rounded,
                                                    size: 10,
                                                  ),
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
                  ),
                ],
              ),

              // TAB 2: Active Applications Progress
              ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: MockData.applications.length,
                separatorBuilder: (_, _) => const SizedBox(height: 14),
                itemBuilder: (context, index) {
                  final app = MockData.applications[index];
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  app.job.title,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: app.status.contains('Interview')
                                      ? AppColors.successLightBg
                                      : AppColors.primaryLightBg,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  app.status,
                                  style: TextStyle(
                                    color: app.status.contains('Interview')
                                        ? AppColors.success
                                        : AppColors.lightPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${app.job.company} • Applied ${app.appliedDate}',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 16),

                          // Pipeline Step Bar
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Pipeline Stage: Step ${app.currentStep} of ${app.totalSteps}',
                                    style: theme.textTheme.labelMedium,
                                  ),
                                  Text(
                                    '${(app.currentStep / app.totalSteps * 100).round()}%',
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              LinearProgressIndicator(
                                value: app.currentStep / app.totalSteps,
                                minHeight: 6,
                                borderRadius: BorderRadius.circular(3),
                                backgroundColor: isDark
                                    ? AppColors.darkSurfaceContainerHigh
                                    : AppColors.lightSurfaceContainer,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  app.status.contains('Interview')
                                      ? AppColors.success
                                      : AppColors.lightPrimary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              OutlinedButton(
                                onPressed: () => widget.onSelectJob(app.job),
                                child: const Text('View Role Details'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),

              // TAB 3: Saved Jobs Tab
              ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: MockData.jobs.where((j) => j.isSaved).length,
                separatorBuilder: (_, _) => const SizedBox(height: 14),
                itemBuilder: (context, index) {
                  final job = MockData.jobs
                      .where((j) => j.isSaved)
                      .toList()[index];
                  return Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: const Icon(
                        Icons.business_rounded,
                        color: AppColors.lightPrimary,
                        size: 36,
                      ),
                      title: Text(
                        job.title,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text('${job.company} • ${job.salaryRange}'),
                      trailing: ElevatedButton(
                        onPressed: () => widget.onSelectJob(job),
                        child: const Text('Apply'),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, bool isSelected, VoidCallback onTap) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onTap(),
      selectedColor: isDark
          ? AppColors.darkPrimaryContainer
          : AppColors.lightPrimary,
      labelStyle: TextStyle(
        color: isSelected
            ? Colors.white
            : (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
