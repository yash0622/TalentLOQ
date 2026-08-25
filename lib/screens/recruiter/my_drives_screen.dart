import 'package:flutter/material.dart';
import '../../controllers/paging_controller.dart';
import '../../services/drive_service.dart';
import '../../services/application_visibility_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/paginated_list_view.dart';
import '../../widgets/skeleton_widgets.dart';
import 'create_drive_form.dart';
import 'applicants_screen.dart';

class MyDrivesScreen extends StatefulWidget {
  const MyDrivesScreen({super.key});

  @override
  State<MyDrivesScreen> createState() => _MyDrivesScreenState();
}

class _MyDrivesScreenState extends State<MyDrivesScreen> {
  final DriveService _driveService = DriveService();
  late final PagingController<Map<String, dynamic>> _pagingController;

  @override
  void initState() {
    super.initState();
    ApplicationVisibilityState.instance.addListener(_onApplicationRecorded);
    _pagingController = PagingController<Map<String, dynamic>>(
      fetchPage: (page, limit) => _driveService.getRecruiterDrivesPaginated(page: page, limit: limit),
    );
  }

  void _onApplicationRecorded() {
    if (mounted) _pagingController.refresh();
  }

  @override
  void dispose() {
    _pagingController.dispose();
    ApplicationVisibilityState.instance.removeListener(_onApplicationRecorded);
    super.dispose();
  }

  Future<void> _publishDrive(String driveId) async {
    final success = await _driveService.publishDrive(driveId);
    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Drive published to all eligible students!'), backgroundColor: AppColors.success),
        );
        _pagingController.refresh();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not publish drive.'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _openForm({Map<String, dynamic>? drive}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateDriveForm(
          initialDrive: drive,
          onSuccess: () => _pagingController.refresh(),
        ),
      ),
    );
  }

  void _openApplicants(Map<String, dynamic> drive) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ApplicantsScreen(
          listingId: drive['drive_id'] ?? '',
          companyName: drive['company_name'] ?? 'Company',
          interviewJob: drive['drive_title'] ?? drive['interview_job'] ?? 'Drive',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Campus Placement Drives'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _pagingController.refresh(),
            tooltip: 'Refresh',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Drive'),
      ),
      body: RefreshIndicator(
        onRefresh: () => _pagingController.refresh(),
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
                    'No Placement Drives Created',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Tap the button below to publish your first placement drive.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppColors.lightTextSecondary),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _openForm(),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Create Placement Drive'),
                  ),
                ],
              ),
            ),
          ),
          itemBuilder: (context, item, index) {
            final statusStr = (item['status'] ?? 'draft').toString().toLowerCase();
            final isPublished = statusStr == 'published';
            final isClosed = statusStr == 'closed';
            final totalApps = item['applicant_count'] ?? 0;
            final eligibleApps = item['eligible_applicant_count'] ?? 0;

            return Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _openForm(drive: item),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['company_name'] ?? 'Company Name',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  item['drive_title'] ?? item['interview_job'] ?? 'Drive Position',
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

                          // Status Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isPublished
                                  ? AppColors.successLightBg
                                  : isClosed
                                      ? AppColors.error.withValues(alpha: 0.15)
                                      : AppColors.warning.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              statusStr.toUpperCase(),
                              style: TextStyle(
                                color: isPublished
                                    ? AppColors.success
                                    : isClosed
                                        ? AppColors.error
                                        : AppColors.warning,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Applicant Counts Row
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.primaryLightBg,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.people_rounded, size: 14, color: AppColors.lightPrimary),
                                const SizedBox(width: 4),
                                Text('Total Applicants: $totalApps', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.lightPrimary)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.successLightBg,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.check_circle_rounded, size: 14, color: AppColors.success),
                                const SizedBox(width: 4),
                                Text('Eligible: $eligibleApps', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.success)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 10),

                      // Action Buttons
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _openApplicants(item),
                              icon: const Icon(Icons.how_to_reg_rounded, size: 16),
                              label: const Text('Manage Applicants'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (!isPublished)
                            ElevatedButton.icon(
                              onPressed: () => _publishDrive(item['drive_id']),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.success,
                                foregroundColor: Colors.white,
                              ),
                              icon: const Icon(Icons.send_rounded, size: 16),
                              label: const Text('Publish'),
                            )
                          else
                            IconButton(
                              icon: const Icon(Icons.edit_rounded, size: 20),
                              onPressed: () => _openForm(drive: item),
                              tooltip: 'Edit Drive',
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
    );
  }
}
