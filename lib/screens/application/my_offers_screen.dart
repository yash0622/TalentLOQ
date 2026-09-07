import 'package:flutter/material.dart';
import '../../controllers/paging_controller.dart';
import '../../services/drive_service.dart';
import '../../services/application_visibility_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/paginated_list_view.dart';
import '../../widgets/skeleton_widgets.dart';
import 'offer_details_screen.dart';

class MyOffersScreen extends StatefulWidget {
  final bool embedInTab;

  const MyOffersScreen({
    super.key,
    this.embedInTab = false,
  });

  @override
  State<MyOffersScreen> createState() => _MyOffersScreenState();
}

class _MyOffersScreenState extends State<MyOffersScreen> {
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

  void _openOfferDetails(Map<String, dynamic> item, Map<String, dynamic> drive, Map<String, dynamic> st) {
    final offerDetails = Map<String, dynamic>.from(item['offer_details'] as Map? ?? {});
    final studentId = (item['student_id'] ?? '').toString();
    final candidateName = (item['student_name'] ?? 'Candidate').toString();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OfferDetailsScreen(
          drive: drive,
          status: st,
          offerDetails: offerDetails,
          studentId: studentId,
          candidateName: candidateName,
          isRecruiter: false,
          onOfferActionCompleted: () {
            if (mounted) _pagingController.refresh();
          },
        ),
      ),
    ).then((_) {
      if (mounted) _pagingController.refresh();
    });
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
          return ValueKey('offer_${drive['drive_id'] ?? item.hashCode}');
        },
        skeletonBuilder: (_, _) => const DriveCardSkeleton(),
        emptyWidget: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.successLightBg,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.stars_rounded, size: 48, color: AppColors.success),
                ),
                const SizedBox(height: 20),
                Text(
                  'No Placement Offers Yet',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'When a company selects you and releases an official job or internship offer, it will appear here.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        itemBuilder: (context, item, index) {
          final drive = Map<String, dynamic>.from(item['drive'] as Map? ?? {});
          final st = Map<String, dynamic>.from(item['status'] as Map? ?? {});

          final finalOutcome = (st['final_outcome'] ?? 'in_progress').toString().toLowerCase();

          // Only render items where outcome is selected / offered / hired / accepted
          final isOffer = finalOutcome == 'selected' ||
              finalOutcome == 'offered' ||
              finalOutcome == 'hired' ||
              finalOutcome == 'accepted';

          if (!isOffer) {
            return const SizedBox.shrink();
          }

          final companyName = drive['company_name'] ?? 'Company';
          final driveTitle = drive['drive_title'] ?? drive['interview_job'] ?? 'Placement Position';
          final driveId = (drive['drive_id'] ?? drive['listing_id'] ?? '').toString();
          final ctcMin = drive['ctc_min'] ?? 6.0;
          final ctcMax = drive['ctc_max'] ?? 12.0;
          final empType = (drive['employment_type'] ?? 'full_time').toString().replaceAll('_', ' ').toUpperCase();

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(
                color: AppColors.success,
                width: 1.5,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                if (driveId.isNotEmpty) {
                  _openOfferDetails(item, drive, st);
                }
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Offer Banner Pill with overflow protection
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.successLightBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.stars_rounded, color: AppColors.success, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            finalOutcome == 'accepted'
                                ? '🎉 PLACEMENT OFFER ACCEPTED'
                                : '🎉 OFFICIAL PLACEMENT OFFER EXTENDED',
                            style: const TextStyle(
                              color: AppColors.success,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              letterSpacing: 0.3,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Company & Title
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLightBg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.business_rounded, color: AppColors.lightPrimary, size: 24),
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
                                fontSize: 17,
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
                    ],
                  ),
                  const SizedBox(height: 12),

                  // CTC Details Pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurfaceContainerHigh : AppColors.lightSurfaceContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.payments_rounded, size: 16, color: AppColors.success),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Offered CTC: ₹${(ctcMin is num && ctcMin % 1 == 0) ? ctcMin.toInt() : ctcMin} - ₹${(ctcMax is num && ctcMax % 1 == 0) ? ctcMax.toInt() : ctcMax} LPA • $empType',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Action Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        if (driveId.isNotEmpty) {
                          _openOfferDetails(item, drive, st);
                        }
                      },
                      icon: const Icon(Icons.visibility_rounded, size: 16),
                      label: const Text('View Offer & Company Details'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
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
        title: const Text('My Job Offers'),
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
