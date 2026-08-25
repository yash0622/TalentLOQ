import 'package:flutter/material.dart';
import 'cached_app_image.dart';

class AppAvatar extends StatelessWidget {
  final String imageUrl;
  final double radius;
  final String? fallbackText;

  const AppAvatar({
    super.key,
    required this.imageUrl,
    this.radius = 24,
    this.fallbackText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
      ),
      child: ClipOval(
        child: CachedAppImage(
          imageUrl: imageUrl,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          fallbackIcon: Icons.person_rounded,
          fallbackText: fallbackText,
        ),
      ),
    );
  }
}
