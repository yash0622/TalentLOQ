import 'package:flutter/material.dart';
import '../../services/recruiter_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/skeleton_widgets.dart';
import 'add_company_form.dart';
import 'my_listings_screen.dart';

class RecruiterDashboardScreen extends StatefulWidget {
  final VoidCallback? onOpenDrawer;
  const RecruiterDashboardScreen({super.key, this.onOpenDrawer});

  @override
  State<RecruiterDashboardScreen> createState() => _RecruiterDashboardScreenState();
}

class _RecruiterDashboardScreenState extends State<RecruiterDashboardScreen> {
  final RecruiterService _recruiterService = RecruiterService();
  bool _isLoading = true;
  int _registeredStudents = 0;
  int _activeListings = 0;
  int _offersMade = 0;

  @override
  void initState() {
    super.initState();
    _fetchStats();
  }

  Future<void> _fetchStats() async {
    setState(() => _isLoading = true);
    final stats = await _recruiterService.getRecruiterStats();
    final students = await _recruiterService.getRegisteredStudents();
    setState(() {
      _registeredStudents = (stats['total_registered_students'] as int?) ?? (students.isNotEmpty ? students.length : 0);
      _activeListings = (stats['total_active_listings'] as int?) ?? (stats['total_active_drives'] as int?) ?? 0;
      _offersMade = (stats['total_offers_made'] as int?) ?? 0;
      _isLoading = false;
    });
  }

  void _openAddForm() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddCompanyForm(onSuccess: _fetchStats),
      ),
    );
  }

  void _openMyListings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const MyListingsScreen(),
      ),
    );
  }

  Future<void> _showStudentsModal() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, scrollController) {
            return FutureBuilder<List<dynamic>>(
              future: _recruiterService.getRegisteredStudents(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: 3,
                    itemBuilder: (_, index) => const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: ApplicantRowSkeleton(),
                    ),
                  );
                }
                final students = snapshot.data ?? [];
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.school_rounded, color: AppColors.lightPrimary),
                              SizedBox(width: 8),
                              Text(
                                'Registered Students List',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Showing ${students.length} student records registered in placement cell database.',
                        style: const TextStyle(fontSize: 12, color: AppColors.lightTextSecondary),
                      ),
                      const Divider(height: 16),
                      Expanded(
                        child: students.isEmpty
                            ? const Center(child: Text('No student records found.'))
                            : ListView.separated(
                                controller: scrollController,
                                itemCount: students.length,
                                separatorBuilder: (_, _) => const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final s = Map<String, dynamic>.from(students[index] as Map);
                                  final name = (s['full_name'] ?? s['name'] ?? 'Student Candidate').toString();
                                  final email = (s['email'] ?? 'student@univ.edu').toString();
                                  final course = (s['course'] ?? 'BTECH_CSE').toString();
                                  final cgpa = (s['CGPA'] ?? s['cgpa'] ?? 8.0).toString();
                                  final hasAccess = s['has_placement_access'] ?? true;

                                  return Card(
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      side: BorderSide(
                                        color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                                      ),
                                    ),
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: AppColors.primaryLightBg,
                                        child: Text(
                                          name.isNotEmpty ? name.substring(0, 1).toUpperCase() : 'S',
                                          style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.lightPrimary),
                                        ),
                                      ),
                                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                      subtitle: Text('$email\nCourse: $course', style: const TextStyle(fontSize: 11, height: 1.3)),
                                      isThreeLine: true,
                                      trailing: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: AppColors.successLightBg,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text('CGPA: $cgpa', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.success)),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            hasAccess ? '✔ Active Access' : '🚫 Restricted',
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                              color: hasAccess ? AppColors.success : AppColors.error,
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
              },
            );
          },
        );
      },
    );
  }

  Future<void> _showPlacementOffersModal() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.85,
          expand: false,
          builder: (_, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.emoji_events_rounded, color: AppColors.warning),
                          SizedBox(width: 8),
                          Text(
                            'Placement Offers Recorded',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$_offersMade recorded placement offer(s) issued across recruitment drives.',
                    style: const TextStyle(fontSize: 12, color: AppColors.lightTextSecondary),
                  ),
                  const Divider(height: 16),
                  Expanded(
                    child: _offersMade == 0
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.emoji_events_outlined,
                                    size: 54,
                                    color: AppColors.warning.withValues(alpha: 0.5),
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'No Placement Offers Recorded Yet',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'Placement offers will appear here when candidates successfully clear final interview rounds & offer letters are issued.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 12, color: AppColors.lightTextSecondary),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            controller: scrollController,
                            itemCount: _offersMade,
                            separatorBuilder: (_, _) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              return Card(
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: BorderSide(
                                    color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                                  ),
                                ),
                                child: const ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: AppColors.successLightBg,
                                    child: Icon(Icons.verified_rounded, color: AppColors.success, size: 20),
                                  ),
                                  title: Text('Placement Offer Confirmed', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                  subtitle: Text('Offer status: Active & Verified', style: TextStyle(fontSize: 11)),
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
    final cardBorder = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(
        color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
      ),
    );

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: const Row(
          children: [
            Icon(Icons.space_dashboard_rounded, color: AppColors.lightPrimary, size: 22),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Recruiter Dashboard',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetchStats,
            tooltip: 'Refresh Analytics',
          ),
          if (widget.onOpenDrawer != null)
            IconButton(
              tooltip: 'Settings & Menu',
              icon: const Icon(Icons.menu_rounded, size: 24),
              onPressed: widget.onOpenDrawer,
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchStats,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 130),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Card
              Card(
                elevation: 0,
                shape: cardBorder,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLightBg,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.verified_user_rounded,
                          color: AppColors.lightPrimary,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Placement Officer Control Center',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Post company listings, evaluate multi-round candidates, and record placement offers.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.lightTextSecondary,
                                fontSize: 11.5,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Stat Cards Section Title
              Text(
                'Campus Analytics Summary',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),

              // 3 Stat Cards (2 Equal Height Top Cards + 1 Bottom Banner)
              _isLoading
                  ? const StatCardSkeleton()
                  : Column(
                      children: [
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Total Registered Students Card
                              Expanded(
                                child: Card(
                                  elevation: 0,
                                  shape: cardBorder,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: _showStudentsModal,
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: AppColors.primaryLightBg,
                                                  borderRadius: BorderRadius.circular(10),
                                                ),
                                                child: const Icon(Icons.school_rounded, color: AppColors.lightPrimary, size: 20),
                                              ),
                                              const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: AppColors.lightPrimary),
                                            ],
                                          ),
                                          const Spacer(),
                                          Text(
                                            '$_registeredStudents',
                                            style: const TextStyle(
                                              fontSize: 26,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.lightPrimary,
                                              height: 1.2,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          const Text(
                                            'Registered\nStudents',
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              color: AppColors.lightTextSecondary,
                                              fontWeight: FontWeight.w600,
                                              height: 1.25,
                                            ),
                                            maxLines: 2,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),

                              // Total Active Listings Card
                              Expanded(
                                child: Card(
                                  elevation: 0,
                                  shape: cardBorder,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: _openMyListings,
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: AppColors.successLightBg,
                                                  borderRadius: BorderRadius.circular(10),
                                                ),
                                                child: const Icon(Icons.campaign_rounded, color: AppColors.success, size: 20),
                                              ),
                                              const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: AppColors.success),
                                            ],
                                          ),
                                          const Spacer(),
                                          Text(
                                            '$_activeListings',
                                            style: const TextStyle(
                                              fontSize: 26,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.success,
                                              height: 1.2,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          const Text(
                                            'Active Placement\nDrives',
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              color: AppColors.lightTextSecondary,
                                              fontWeight: FontWeight.w600,
                                              height: 1.25,
                                            ),
                                            maxLines: 2,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Total Placement Offers Card
                        Card(
                          elevation: 0,
                          shape: cardBorder,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: _showPlacementOffersModal,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0x35F59E0B) : AppColors.warningLightBg,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(Icons.emoji_events_rounded, color: AppColors.warning, size: 24),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              '$_offersMade',
                                              style: const TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.warning,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            const Text(
                                              'Placement Offers',
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        const Text(
                                          'Total verified offers recorded across drives',
                                          style: TextStyle(fontSize: 11.5, color: AppColors.lightTextSecondary, fontWeight: FontWeight.w500),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.warning),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
              const SizedBox(height: 24),

              // Operations Section Title
              Text(
                'Quick Operations & Actions',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),

              // Operation 1: Post New Drive
              Card(
                elevation: 0,
                shape: cardBorder,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: _openAddForm,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLightBg,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.add_business_rounded, color: AppColors.lightPrimary, size: 22),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Post New Company Drive',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Create draft or publish new job listing with PDF attachment & CGPA cutoff',
                                style: TextStyle(fontSize: 11.5, color: AppColors.lightTextSecondary, height: 1.3),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.lightTextSecondary),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Operation 2: Manage All Drives & Applicants
              Card(
                elevation: 0,
                shape: cardBorder,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: _openMyListings,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.successLightBg,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.folder_shared_rounded, color: AppColors.success, size: 22),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Manage All Drives & Applicants',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'View active listings, evaluate applicants, and progress round outcomes',
                                style: TextStyle(fontSize: 11.5, color: AppColors.lightTextSecondary, height: 1.3),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.lightTextSecondary),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
