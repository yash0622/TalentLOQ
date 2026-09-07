import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'opportunities_screen.dart';
import '../application/my_applications_screen.dart';
import '../application/my_offers_screen.dart';

class JobsSectionScreen extends StatefulWidget {
  final int initialTabIndex;

  const JobsSectionScreen({
    super.key,
    this.initialTabIndex = 0,
  });

  @override
  State<JobsSectionScreen> createState() => _JobsSectionScreenState();
}

class _JobsSectionScreenState extends State<JobsSectionScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: const Text('Campus Placement Hub'),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: AppColors.lightPrimary,
          indicatorWeight: 3,
          labelColor: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
          unselectedLabelColor: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 13),
          tabs: const [
            Tab(
              icon: Icon(Icons.business_center_rounded, size: 20),
              text: 'Drives',
            ),
            Tab(
              icon: Icon(Icons.assignment_turned_in_rounded, size: 20),
              text: 'Applications',
            ),
            Tab(
              icon: Icon(Icons.workspace_premium_rounded, size: 20),
              text: 'Offers',
            ),
            Tab(
              icon: Icon(Icons.auto_awesome_rounded, size: 20),
              text: 'Matched For You',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          OpportunitiesScreen(embedInTab: true, initialFilterMode: 'all'),
          MyApplicationsScreen(embedInTab: true),
          MyOffersScreen(embedInTab: true),
          OpportunitiesScreen(embedInTab: true, initialFilterMode: 'matched'),
        ],
      ),
    );
  }
}
