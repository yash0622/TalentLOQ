import 'package:flutter/material.dart';
import '../../controllers/paging_controller.dart';
import '../../services/drive_service.dart';
import '../../services/application_visibility_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/paginated_list_view.dart';
import '../../widgets/skeleton_widgets.dart';
import '../jobs/company_detail_screen.dart';

class MyApplicationsScreen extends StatefulWidget {
  final bool embedInTab;

  const MyApplicationsScreen({
    super.key,
    this.embedInTab = false,
  });

  @override
  State<MyApplicationsScreen> createState() => _MyApplicationsScreenState();
}

class _MyApplicationsScreenState extends State<MyApplicationsScreen> {
  final DriveService _driveService = DriveService();
  late final PagingController<Map<String, dynamic>> _pagingController;

  @override
  void initState() {
    super.initState();
    ApplicationVisibilityState.instance.addListener(_onApplicationRecorded);
    _pagingController = PagingController<Map<String, dynamic>>(
      fetchPage: (page, limit) => _driveService.getMyApplicationsPaginated(page: page, limit: limit),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final body = RefreshIndicator(
      onRefresh: () => _pagingController.refresh(),
      child: PaginatedListView<Map<String, dynamic>>(
          controller: _pagingController,
          itemKey: (item) {
            final drive = item['drive'] as Map<String, dynamic>? ?? {};
            return ValueKey(drive['drive_id'] ?? item.hashCode);
          },
          skeletonBuilder: (_, _) => const DriveCardSkeleton(),
          emptyWidget: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.assignment_turned_in_outlined, size: 54, color: AppColors.lightTextSecondary),
                  const SizedBox(height: 12),
                  const Text(
                    'No Active Applications',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Browse campus placement drives under Opportunities to apply.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppColors.lightTextSecondary),
                  ),
                ],
              ),
            ),
          ),
          itemBuilder: (context, item, index) {
            final drive = Map<String, dynamic>.from(item['drive'] as Map? ?? {});
            final st = Map<String, dynamic>.from(item['status'] as Map? ?? {});

            final companyName = drive['company_name'] ?? 'Company';
            final driveTitle = drive['drive_title'] ?? drive['interview_job'] ?? 'Placement Drive';
            final driveId = (drive['drive_id'] ?? drive['listing_id'] ?? '').toString();
            final currentRound = st['current_round'] ?? 0;
            final finalOutcome = (st['final_outcome'] ?? 'in_progress').toString().toLowerCase();
            final selectionRounds = (drive['selection_process'] as List?) ?? [
              {'round_number': 1, 'round_name': 'Aptitude Test'},
              {'round_number': 2, 'round_name': 'Technical Round'},
              {'round_number': 3, 'round_name': 'HR Round'},
            ];

            return Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  if (driveId.isNotEmpty) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CompanyDetailScreen(
                          listingId: driveId,
                          initialData: drive,
                        ),
                      ),
                    );
                  }
                },
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
                          child: const Icon(Icons.business_rounded, color: AppColors.lightPrimary, size: 22),
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

                        // Final Outcome Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: finalOutcome == 'selected'
                                ? AppColors.successLightBg
                                : finalOutcome == 'rejected'
                                    ? AppColors.error.withValues(alpha: 0.15)
                                    : AppColors.primaryLightBg,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            finalOutcome.replaceAll('_', ' ').toUpperCase(),
                            style: TextStyle(
                              color: finalOutcome == 'selected'
                                  ? AppColors.success
                                  : finalOutcome == 'rejected'
                                      ? AppColors.error
                                      : AppColors.lightPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.lightTextSecondary),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Progress Stepper Bar
                    const Text('Selection Process Rounds:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: List.generate(selectionRounds.length, (i) {
                          final rName = (selectionRounds[i] as Map)['round_name'] ?? 'Round ${i + 1}';
                          final isPassedRound = (i + 1) <= currentRound;
                          final isCurrentRound = (i + 1) == (currentRound + 1) && finalOutcome == 'in_progress';

                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isPassedRound
                                      ? AppColors.successLightBg
                                      : isCurrentRound
                                          ? AppColors.primaryLightBg
                                          : (isDark ? AppColors.darkSurfaceContainerHigh : AppColors.lightSurfaceContainer),
                                  borderRadius: BorderRadius.circular(10),
                                  border: isCurrentRound ? Border.all(color: AppColors.lightPrimary, width: 1.5) : null,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isPassedRound
                                          ? Icons.check_circle_rounded
                                          : isCurrentRound
                                              ? Icons.play_circle_fill_rounded
                                              : Icons.radio_button_unchecked_rounded,
                                      size: 14,
                                      color: isPassedRound
                                          ? AppColors.success
                                          : isCurrentRound
                                              ? AppColors.lightPrimary
                                              : AppColors.lightTextSecondary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${i + 1}. $rName',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: (isPassedRound || isCurrentRound) ? FontWeight.bold : FontWeight.normal,
                                        color: isPassedRound
                                            ? AppColors.success
                                            : isCurrentRound
                                                ? AppColors.lightPrimary
                                                : AppColors.lightTextSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (i < selectionRounds.length - 1)
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 4),
                                  child: Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.lightTextSecondary),
                                ),
                            ],
                          );
                        }),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    if (widget.embedInTab) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Drive Applications'),
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
