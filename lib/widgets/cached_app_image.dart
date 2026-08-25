import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'skeleton_widgets.dart';

/// Performance-optimized network image widget with fade-in placeholder and fallback.
class CachedAppImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double borderRadius;
  final IconData fallbackIcon;
  final String? fallbackText;

  const CachedAppImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = 0,
    this.fallbackIcon = Icons.business_rounded,
    this.fallbackText,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (imageUrl.isEmpty || !imageUrl.startsWith('http')) {
      return _buildFallback(isDark);
    }

    final imageWidget = Image.network(
      imageUrl,
      width: width,
      height: height,
      fit: fit,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) {
          return AnimatedOpacity(
            opacity: 1.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeIn,
            child: child,
          );
        }
        return SkeletonBox(
          width: width,
          height: height ?? 40,
          borderRadius: borderRadius,
        );
      },
      errorBuilder: (context, error, stackTrace) => _buildFallback(isDark),
    );

    if (borderRadius > 0) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: imageWidget,
      );
    }

    return imageWidget;
  }

  Widget _buildFallback(bool isDark) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceContainerHigh : AppColors.lightSurfaceContainer,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Center(
        child: fallbackText != null && fallbackText!.isNotEmpty
            ? Text(
                fallbackText![0].toUpperCase(),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: (height ?? 40) * 0.4,
                  color: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                ),
              )
            : Icon(
                fallbackIcon,
                size: (height ?? 40) * 0.5,
                color: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
              ),
      ),
    );
  }
}
