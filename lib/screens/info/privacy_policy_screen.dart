import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isDark ? AppColors.darkBackground : AppColors.lightBackground;
    final cardBg = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final borderColor = isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(
          'Privacy Policy',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: textPrimary,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: [
          _buildCard(
            cardBg: cardBg,
            borderColor: borderColor,
            title: '1. Our Promise',
            body:
                'We only collect information needed to run campus placement drives. We do not sell your personal data, we do not run third-party ad networks, and we never share your files with companies you have not applied to.',
            textPrimary: textPrimary,
            textSecondary: textSecondary,
          ),
          const SizedBox(height: 12),
          _buildCard(
            cardBg: cardBg,
            borderColor: borderColor,
            title: '2. What We Collect',
            body:
                '• Profile Information: Your name, college email, phone number, enrollment number, branch, semester, CGPA, and backlog counts.\n'
                '• Academic Documents: Class 10th, 12th, or diploma marksheets, college grade cards, and your resume.\n'
                '• Skills and Links: Technical skills, projects, and links to your GitHub or LinkedIn profiles.\n'
                '• Recruiter Details: Work email, company name, and job drive criteria.',
            textPrimary: textPrimary,
            textSecondary: textSecondary,
          ),
          const SizedBox(height: 12),
          _buildCard(
            cardBg: cardBg,
            borderColor: borderColor,
            title: '3. Why We Use Your Information',
            body:
                '• To check whether you meet company eligibility rules for a drive.\n'
                '• To review your resume format and suggest missing keywords.\n'
                '• To send your profile and resume to recruiters when you apply.\n'
                '• To send you alerts when interview dates or selection results get posted.',
            textPrimary: textPrimary,
            textSecondary: textSecondary,
          ),
          const SizedBox(height: 12),
          _buildCard(
            cardBg: cardBg,
            borderColor: borderColor,
            title: '4. How We Protect Your Data',
            body:
                'We store your uploaded marksheets and resumes in protected storage. Phone numbers and resume text are encrypted in our database. Only registered recruiters from drives you actively apply to can see your application.',
            textPrimary: textPrimary,
            textSecondary: textSecondary,
          ),
          const SizedBox(height: 12),
          _buildCard(
            cardBg: cardBg,
            borderColor: borderColor,
            title: '5. Who Can See Your Information',
            body:
                '• Recruiters: When you apply to a company drive, that company\'s recruiter can view your profile and resume.\n'
                '• Placement Coordinators: Your college placement office can see your application status to help coordinate rounds.',
            textPrimary: textPrimary,
            textSecondary: textSecondary,
          ),
          const SizedBox(height: 12),
          _buildCard(
            cardBg: cardBg,
            borderColor: borderColor,
            title: '6. Your Rights',
            body:
                '• You can view and edit your profile details anytime in the app.\n'
                '• You can upload a newer version of your resume whenever you want.\n'
                '• You can ask our team to delete your account and uploaded documents once your placement season ends.',
            textPrimary: textPrimary,
            textSecondary: textSecondary,
          ),
          const SizedBox(height: 12),
          _buildCard(
            cardBg: cardBg,
            borderColor: borderColor,
            title: '7. How Long We Keep It',
            body:
                'We keep your placement records while you are enrolled in college and during your active placement season. After your batch graduates, records are archived or deleted according to college placement rules.',
            textPrimary: textPrimary,
            textSecondary: textSecondary,
          ),
          const SizedBox(height: 12),
          _buildCard(
            cardBg: cardBg,
            borderColor: borderColor,
            title: '8. Contacting Us',
            body:
                'For privacy questions, corrections, or account deletion:\n\n'
                'Email: support@talentloq.app\n'
                'Address: Vadodara, Gujarat, India\n'
                'Last updated: October 2026',
            textPrimary: textPrimary,
            textSecondary: textSecondary,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildCard({
    required Color cardBg,
    required Color borderColor,
    required String title,
    required String body,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    return Card(
      elevation: 0,
      color: cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: borderColor, width: 0.8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.5,
                color: textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
