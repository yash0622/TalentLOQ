import 'package:flutter/material.dart';
import '../../services/recruiter_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/skeleton_widgets.dart';
import 'add_company_form.dart';
import 'applicants_screen.dart';

class MyListingsScreen extends StatefulWidget {
  const MyListingsScreen({super.key});

  @override
  State<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends State<MyListingsScreen> {
  final RecruiterService _recruiterService = RecruiterService();
  bool _isLoading = true;
  List<dynamic> _listings = [];

  @override
  void initState() {
    super.initState();
    _fetchListings();
  }

  Future<void> _fetchListings() async {
    setState(() => _isLoading = true);
    final results = await _recruiterService.getRecruiterListings();
    setState(() {
      _listings = results;
      _isLoading = false;
    });
  }

  Future<void> _publishListing(String listingId) async {
    final success = await _recruiterService.publishCompanyListing(listingId);
    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Company listing published!'), backgroundColor: AppColors.success),
        );
        _fetchListings();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not publish listing.'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _openForm({Map<String, dynamic>? listing}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddCompanyForm(
          initialListing: listing,
          onSuccess: _fetchListings,
        ),
      ),
    );
  }

  void _openApplicants(Map<String, dynamic> item) {
    final listingId = (item['listing_id'] ?? item['drive_id'] ?? '').toString();
    final companyName = (item['company_name'] ?? 'Company').toString();
    final interviewJob = (item['interview_job'] ?? item['drive_title'] ?? 'Role').toString();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ApplicantsScreen(
          listingId: listingId,
          companyName: companyName,
          interviewJob: interviewJob,
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
        title: const Text('My Post Listings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetchListings,
            tooltip: 'Refresh',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Post New Listing'),
      ),
      body: RefreshIndicator(
        onRefresh: _fetchListings,
        child: _isLoading
            ? ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: 4,
                itemBuilder: (_, index) => const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: DriveCardSkeleton(),
                ),
              )
            : _listings.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.business_center_outlined, size: 54, color: AppColors.lightTextSecondary),
                          const SizedBox(height: 12),
                          const Text(
                            'No Company Listings Found',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Tap the button below to post your first company placement listing.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: AppColors.lightTextSecondary),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: () => _openForm(),
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('Post Company Listing'),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _listings.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final item = Map<String, dynamic>.from(_listings[index] as Map);
                      final statusStr = (item['status'] ?? 'draft').toString().toLowerCase();
                      final isPublished = statusStr == 'published';
                      final totalApps = item['applicant_count'] ?? 0;
                      final eligibleApps = item['eligible_applicant_count'] ?? totalApps;

                      return Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                          ),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => _openForm(listing: item),
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
                                            item['interview_job'] ?? item['drive_title'] ?? 'Role Title',
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
                                            : AppColors.warning.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        statusStr.toUpperCase(),
                                        style: TextStyle(
                                          color: isPublished ? AppColors.success : AppColors.warning,
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
                                          Text('Applicants: $totalApps', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.lightPrimary)),
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
                                        onPressed: () => _publishListing((item['listing_id'] ?? item['drive_id']).toString()),
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
                                        onPressed: () => _openForm(listing: item),
                                        tooltip: 'Edit Listing',
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
