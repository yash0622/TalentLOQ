import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class TermsConditionsScreen extends StatelessWidget {
  const TermsConditionsScreen({super.key});

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
          'Terms & Conditions',
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
            title: '1. Agreement to Terms',
            body:
                'By signing up for TalentLOQ as a student or recruiter, you agree to these terms. If you do not agree with them, please do not use the app.',
            textPrimary: textPrimary,
            textSecondary: textSecondary,
          ),
          const SizedBox(height: 12),
          _buildCard(
            cardBg: cardBg,
            borderColor: borderColor,
            title: '2. Who Can Use TalentLOQ',
            body:
                'You must be at least 18 years old and an enrolled student, graduate, or verified company recruiter registered through participating institutions.',
            textPrimary: textPrimary,
            textSecondary: textSecondary,
          ),
          const SizedBox(height: 12),
          _buildCard(
            cardBg: cardBg,
            borderColor: borderColor,
            title: '3. Account Responsibilities',
            body:
                '• Keep your login details and OTP codes private. You are responsible for any activity under your account.\n'
                '• Every mark, backlog count, and certificate you submit must be genuine. Submitting altered marksheets or fake resumes breaks university placement rules and will lead to immediate account suspension and referral to the placement committee.',
            textPrimary: textPrimary,
            textSecondary: textSecondary,
          ),
          const SizedBox(height: 12),
          _buildCard(
            cardBg: cardBg,
            borderColor: borderColor,
            title: '4. House Rules',
            body:
                '• Do not upload altered, copied, or fraudulent documents.\n'
                '• Do not post fake drives, spam, or misleading job descriptions.\n'
                '• Do not harass other students, recruiters, or placement staff in chat.\n'
                '• Do not attempt to scrape data or attack platform services.',
            textPrimary: textPrimary,
            textSecondary: textSecondary,
          ),
          const SizedBox(height: 12),
          _buildCard(
            cardBg: cardBg,
            borderColor: borderColor,
            title: '5. Ownership of Content',
            body:
                '• Your resume, academic files, and project details belong to you.\n'
                '• When you apply to a drive, you give TalentLOQ permission to share your application with that specific recruiter.\n'
                '• The TalentLOQ app, ATS Doctor engine, code, and branding belong to our team.',
            textPrimary: textPrimary,
            textSecondary: textSecondary,
          ),
          const SizedBox(height: 12),
          _buildCard(
            cardBg: cardBg,
            borderColor: borderColor,
            title: '6. Placement Disclaimers',
            body:
                '• TalentLOQ helps you prepare and apply for campus drives.\n'
                '• The ATS Resume Doctor score is a preparation guide, not a guarantee of a job offer or interview call.\n'
                '• Final shortlists, interview rounds, salaries, and hiring decisions are made strictly by the hiring company.',
            textPrimary: textPrimary,
            textSecondary: textSecondary,
          ),
          const SizedBox(height: 12),
          _buildCard(
            cardBg: cardBg,
            borderColor: borderColor,
            title: '7. Account Suspension',
            body:
                'We will suspend or delete accounts that provide false academic information, violate college rules, or abuse the platform.',
            textPrimary: textPrimary,
            textSecondary: textSecondary,
          ),
          const SizedBox(height: 12),
          _buildCard(
            cardBg: cardBg,
            borderColor: borderColor,
            title: '8. Governing Law',
            body:
                'These terms follow the laws of India. Any legal dispute will be settled in Vadodara, Gujarat.',
            textPrimary: textPrimary,
            textSecondary: textSecondary,
          ),
          const SizedBox(height: 12),
          _buildCard(
            cardBg: cardBg,
            borderColor: borderColor,
            title: '9. Support',
            body:
                'For questions about these terms, reach our team at:\n\n'
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
