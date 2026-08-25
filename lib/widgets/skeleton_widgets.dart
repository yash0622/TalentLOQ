import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Animated shimmer effect widget.
class AppShimmer extends StatefulWidget {
  final Widget child;

  const AppShimmer({super.key, required this.child});

  @override
  State<AppShimmer> createState() => _AppShimmerState();
}

class _AppShimmerState extends State<AppShimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final baseColor = isDark
        ? AppColors.darkSurfaceContainerHigh
        : AppColors.lightSurfaceContainer;
    final highlightColor = isDark
        ? AppColors.darkSurfaceVariant.withValues(alpha: 0.8)
        : AppColors.lightSurface;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                baseColor,
                highlightColor,
                baseColor,
              ],
              stops: const [0.0, 0.5, 1.0],
              transform: _SlidingGradientTransform(slidePercent: _controller.value),
            ).createShader(bounds);
          },
          child: widget.child,
        );
      },
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  final double slidePercent;
  const _SlidingGradientTransform({required this.slidePercent});

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * (slidePercent * 2 - 1), 0, 0);
  }
}

/// Helper rectangular block for skeleton UI items.
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double borderRadius;

  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceContainerHigh : AppColors.lightSurfaceContainer,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// Skeleton Card matching the real Drive Card layout (OpportunitiesScreen & MyDrivesScreen).
class DriveCardSkeleton extends StatelessWidget {
  const DriveCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AppShimmer(
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
          ),
        ),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SkeletonBox(width: 42, height: 42, borderRadius: 12),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(width: 140, height: 16),
                        SizedBox(height: 6),
                        SkeletonBox(width: 180, height: 14),
                      ],
                    ),
                  ),
                  SizedBox(width: 8),
                  SkeletonBox(width: 70, height: 22, borderRadius: 12),
                ],
              ),
              SizedBox(height: 12),
              SkeletonBox(width: double.infinity, height: 28, borderRadius: 8),
              SizedBox(height: 10),
              SkeletonBox(width: double.infinity, height: 12),
              SizedBox(height: 6),
              SkeletonBox(width: 220, height: 12),
              SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SkeletonBox(width: 160, height: 14),
                  SkeletonBox(width: 90, height: 14),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Skeleton Row matching the real Applicant Card layout (ApplicantsScreen).
class ApplicantRowSkeleton extends StatelessWidget {
  const ApplicantRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AppShimmer(
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
          ),
        ),
        child: const Padding(
          padding: EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SkeletonBox(width: 44, height: 44, borderRadius: 22),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(width: 130, height: 15),
                        SizedBox(height: 6),
                        SkeletonBox(width: 80, height: 12),
                      ],
                    ),
                  ),
                  SkeletonBox(width: 75, height: 22, borderRadius: 12),
                ],
              ),
              SizedBox(height: 10),
              Divider(height: 1),
              SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SkeletonBox(width: 100, height: 12),
                  SkeletonBox(width: 70, height: 24, borderRadius: 8),
                  SkeletonBox(width: 100, height: 28, borderRadius: 8),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Skeleton Page layout matching CompanyDetailScreen.
class DriveDetailSkeleton extends StatelessWidget {
  const DriveDetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AppShimmer(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Banner Block
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                ),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SkeletonBox(width: 48, height: 48, borderRadius: 12),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBox(width: 160, height: 18),
                            SizedBox(height: 6),
                            SkeletonBox(width: 200, height: 14),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 14),
                  Row(
                    children: [
                      SkeletonBox(width: 80, height: 24, borderRadius: 12),
                      SizedBox(width: 8),
                      SkeletonBox(width: 100, height: 24, borderRadius: 12),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // CTC & Details Grid
            const Row(
              children: [
                Expanded(child: SkeletonBox(height: 70, borderRadius: 12)),
                SizedBox(width: 12),
                Expanded(child: SkeletonBox(height: 70, borderRadius: 12)),
              ],
            ),
            const SizedBox(height: 16),

            // Description Block
            const SkeletonBox(width: 120, height: 16),
            const SizedBox(height: 8),
            const SkeletonBox(width: double.infinity, height: 12),
            const SizedBox(height: 6),
            const SkeletonBox(width: double.infinity, height: 12),
            const SizedBox(height: 6),
            const SkeletonBox(width: 240, height: 12),
            const SizedBox(height: 20),

            // Required Skills Chips Row
            const SkeletonBox(width: 140, height: 16),
            const SizedBox(height: 10),
            const Row(
              children: [
                SkeletonBox(width: 70, height: 26, borderRadius: 14),
                SizedBox(width: 8),
                SkeletonBox(width: 90, height: 26, borderRadius: 14),
                SizedBox(width: 8),
                SkeletonBox(width: 80, height: 26, borderRadius: 14),
              ],
            ),
            const SizedBox(height: 20),

            // Selection Process Timeline Block
            const SkeletonBox(width: 150, height: 16),
            const SizedBox(height: 10),
            const SkeletonBox(width: double.infinity, height: 40, borderRadius: 10),
            const SizedBox(height: 8),
            const SkeletonBox(width: double.infinity, height: 40, borderRadius: 10),
            const SizedBox(height: 20),

            // PDF / Attachment Row
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                ),
              ),
              child: const Row(
                children: [
                  SkeletonBox(width: 32, height: 32, borderRadius: 8),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(width: 150, height: 14),
                        SizedBox(height: 4),
                        SkeletonBox(width: 100, height: 11),
                      ],
                    ),
                  ),
                  SkeletonBox(width: 60, height: 24, borderRadius: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Skeleton for Recruiter Dashboard Stats Cards
class StatCardSkeleton extends StatelessWidget {
  const StatCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppShimmer(
      child: Row(
        children: [
          Expanded(child: SkeletonBox(height: 85, borderRadius: 16)),
          SizedBox(width: 10),
          Expanded(child: SkeletonBox(height: 85, borderRadius: 16)),
          SizedBox(width: 10),
          Expanded(child: SkeletonBox(height: 85, borderRadius: 16)),
        ],
      ),
    );
  }
}

/// Skeleton Page layout matching ProfileApplicationsScreen (Student Profile).
class ProfileSkeleton extends StatelessWidget {
  const ProfileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AppShimmer(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Summary Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                ),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 140, height: 20),
                  SizedBox(height: 8),
                  SkeletonBox(width: 180, height: 14),
                  SizedBox(height: 12),
                  SkeletonBox(width: 130, height: 24, borderRadius: 12),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Academic & Education Profile Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                ),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      SkeletonBox(width: 200, height: 18),
                      SkeletonBox(width: 24, height: 24, borderRadius: 12),
                    ],
                  ),
                  SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBox(width: 100, height: 12),
                            SizedBox(height: 6),
                            SkeletonBox(width: 90, height: 16),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBox(width: 100, height: 12),
                            SizedBox(height: 6),
                            SkeletonBox(width: 70, height: 16),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBox(width: 100, height: 12),
                            SizedBox(height: 6),
                            SkeletonBox(width: 70, height: 16),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBox(width: 100, height: 12),
                            SizedBox(height: 6),
                            SkeletonBox(width: 70, height: 16),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 20),
                  SkeletonBox(width: 100, height: 12),
                  SizedBox(height: 10),
                  Row(
                    children: [
                      SkeletonBox(width: 75, height: 28, borderRadius: 8),
                      SizedBox(width: 8),
                      SkeletonBox(width: 85, height: 28, borderRadius: 8),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Resume Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                ),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SkeletonBox(width: 44, height: 44, borderRadius: 12),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBox(width: 180, height: 16),
                            SizedBox(height: 6),
                            SkeletonBox(width: 140, height: 12),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  Divider(height: 1),
                  SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      SkeletonBox(width: 36, height: 36, borderRadius: 18),
                      SkeletonBox(width: 36, height: 36, borderRadius: 18),
                      SkeletonBox(width: 36, height: 36, borderRadius: 18),
                      SkeletonBox(width: 36, height: 36, borderRadius: 18),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
