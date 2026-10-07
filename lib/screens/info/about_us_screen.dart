import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class AboutUsScreen extends StatelessWidget {
  const AboutUsScreen({super.key});

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
          'About Us',
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
            title: '1. Why We Built TalentLOQ',
            body:
                'We built TalentLOQ to fix how campus placements run at our university. For years, students and coordinators dealt with messy spreadsheets, missed messages, and confusion over drive cutoffs. We wanted one clear place where students can see their drives, check their resumes, and track interviews without guesswork.',
            textPrimary: textPrimary,
            textSecondary: textSecondary,
          ),
          const SizedBox(height: 12),
          _buildCard(
            cardBg: cardBg,
            borderColor: borderColor,
            title: '2. What You Can Do',
            body:
                'If you are a student:\n'
                '• Check company cutoffs for your branch, CGPA, and backlog limits before applying.\n'
                '• Run your resume through our local ATS Doctor to catch format errors and missing skills.\n'
                '• Upload marksheets once for verification.\n'
                '• Track every application and interview slot in real time.\n\n'
                'If you are a recruiter:\n'
                '• Post placement drives with exact criteria.\n'
                '• Review verified student marksheets and profiles.\n'
                '• Filter applicants by skills and college marks.\n'
                '• Schedule interview rounds and share results directly.',
            textPrimary: textPrimary,
            textSecondary: textSecondary,
          ),
          const SizedBox(height: 12),
          _buildCard(
            cardBg: cardBg,
            borderColor: borderColor,
            title: '3. College Partnership',
            body:
                'TalentLOQ runs in close coordination with the GSFC University placement cell. We test and build features directly with students and recruiters on campus.',
            textPrimary: textPrimary,
            textSecondary: textSecondary,
          ),
          const SizedBox(height: 12),
          _buildCard(
            cardBg: cardBg,
            borderColor: borderColor,
            title: '4. Contact Our Team',
            body:
                'If you run into an issue, have feedback, or want to partner with us:\n\n'
                'Student support: support@talentloq.app\n'
                'Recruiter cell: telentloqrecruiter@gmail.com\n'
                'Campus: Vadodara, Gujarat, India',
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
