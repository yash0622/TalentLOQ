import 'package:flutter/material.dart';

/// Theme-aware TalentLOQ Logo Header Widget
/// Automatically switches between light and dark logo assets extracted from the Logo Variations Sheet.
class TalentloqBrandingHeader extends StatelessWidget {
  final double height;
  final bool showWordmark;

  const TalentloqBrandingHeader({
    super.key,
    this.height = 28,
    this.showWordmark = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (showWordmark) {
      return Image.asset(
        'assets/logo/talentloq_wordmark_full.png',
        height: height,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return Text(
            'TalentLOQ',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: height * 0.6,
              color: isDark ? Colors.white : const Color(0xFF1F4E79),
            ),
          );
        },
      );
    }

    // Icon tile selection based on current theme mode
    final String assetPath = isDark
        ? 'assets/logo/talentloq_icon_dark.png'
        : 'assets/logo/talentloq_icon_light.png';

    return Image.asset(
      assetPath,
      height: height,
      width: height,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return Icon(
          Icons.insights_rounded,
          size: height * 0.7,
          color: isDark ? Colors.white : const Color(0xFF1F4E79),
        );
      },
    );
  }
}
