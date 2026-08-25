import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../theme/app_colors.dart';

class JobDetailsScreen extends StatelessWidget {
  final Job job;
  final VoidCallback onBack;
  final VoidCallback onApplySuccess;

  const JobDetailsScreen({
    super.key,
    required this.job,
    required this.onBack,
    required this.onApplySuccess,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: onBack,
        ),
        title: Text(job.company),
        actions: [
          IconButton(
            icon: Icon(
              job.isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
              color: job.isSaved ? AppColors.lightPrimary : null,
            ),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Company Logo & Title Block
                  Center(
                    child: Column(
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.darkSurfaceContainerHigh
                                : AppColors.lightSurfaceContainer,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.business_center_rounded,
                            size: 36,
                            color: AppColors.lightPrimary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          job.title,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${job.company} • ${job.location}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Badges Row
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.primaryLightBg,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                job.jobType,
                                style: const TextStyle(
                                  color: AppColors.lightPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.successLightBg,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                job.salaryRange,
                                style: const TextStyle(
                                  color: AppColors.success,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // About the Role
                  Text('About the Role', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 10),
                  Text(
                    job.description,
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
                  ),
                  const SizedBox(height: 28),

                  // Requirements
                  Text('Requirements & Skills', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 12),
                  ...job.requirements.map((req) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(top: 6),
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: AppColors.lightPrimary,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                req,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  height: 1.5,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )),
                  const SizedBox(height: 28),

                  // Benefits & Perks
                  Text('Benefits & Perks', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 12),
                  ...job.perks.map((perk) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check_circle_rounded,
                              color: AppColors.success,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                perk,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),

          // Bottom Action Bar (Compact)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
              border: Border(
                top: BorderSide(
                  color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: onApplySuccess,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        minimumSize: const Size.fromHeight(42),
                      ),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Apply Now with TalentLOQ Profile',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
