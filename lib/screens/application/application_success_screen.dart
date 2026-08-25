import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../theme/app_colors.dart';

class ApplicationSuccessScreen extends StatelessWidget {
  final Job job;
  final VoidCallback onViewApplications;
  final VoidCallback onReturnHome;

  const ApplicationSuccessScreen({
    super.key,
    required this.job,
    required this.onViewApplications,
    required this.onReturnHome,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),

              // Celebratory Icon Badge
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: const BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 48,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),

              Text(
                'Application Submitted!',
                textAlign: TextAlign.center,
                style: theme.textTheme.displayLarge?.copyWith(fontSize: 26),
              ),
              const SizedBox(height: 10),
              Text(
                'Your profile & resume have been successfully delivered to the hiring team at ${job.company}.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 32),

              // Application Receipt Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Text('Target Position', style: theme.textTheme.bodyMedium),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              job.title,
                              textAlign: TextAlign.end,
                              style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      Row(
                        children: [
                          Text('Company', style: theme.textTheme.bodyMedium),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              job.company,
                              textAlign: TextAlign.end,
                              style: theme.textTheme.labelLarge,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Reference ID', style: theme.textTheme.bodyMedium),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? AppColors.darkSurfaceContainerLow
                                    : AppColors.lightSurfaceContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                '#TLQ-94821',
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Pipeline Tracker Preview
              Row(
                children: [
                  _buildStepIndicator(context, '1. Submitted', true, true),
                  _buildStepIndicator(context, '2. Under Review', false, false),
                  _buildStepIndicator(context, '3. Interview', false, false),
                ],
              ),

              const SizedBox(height: 32),

              // Action Buttons
              ElevatedButton(
                onPressed: onViewApplications,
                child: const Text('Track My Applications'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: onReturnHome,
                child: const Text('Return to Home Dashboard'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator(BuildContext context, String label, bool isDone, bool isActive) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Container(
            height: 4,
            color: isDone || isActive
                ? AppColors.lightPrimary
                : theme.colorScheme.outlineVariant,
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              fontSize: 11,
              fontWeight: isActive || isDone ? FontWeight.bold : FontWeight.normal,
              color: isActive || isDone ? AppColors.lightPrimary : null,
            ),
          ),
        ],
      ),
    );
  }
}
