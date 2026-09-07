import 'package:dio/dio.dart';

import 'edit_profile_screen.dart';
import 'document_verification_screen.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/models.dart';
import '../../theme/app_colors.dart';
import '../../services/token_storage_service.dart';
import '../../widgets/skeleton_widgets.dart';
import '../../widgets/permission_dialogs.dart';
import '../../utils/jwt_decoder_util.dart';
import '../../network/api_client.dart';

class ProfileApplicationsScreen extends StatefulWidget {
  final Function(Job) onSelectJob;

  const ProfileApplicationsScreen({super.key, required this.onSelectJob});

  @override
  State<ProfileApplicationsScreen> createState() => _ProfileApplicationsScreenState();
}

class _ProfileApplicationsScreenState extends State<ProfileApplicationsScreen> {
  final TokenStorageService _tokenStorage = TokenStorageService();

  bool _isLoading = true;

  String _studentEmail = '';
  String _fullName = '';
  String _education = '';
  double _cgpa = 0.0;
  int _activeBacklogs = 0;
  int _closedBacklogs = 0;
  List<String> _skills = [];
  List<String> _technicalSkills = [];
  List<String> _softSkills = [];
  List<String> _languages = [];
  Map<String, dynamic> _verifiedFieldsMap = {};

  double? _tenthPercentage;
  String? _tenthBoard;
  int? _tenthYear;
  double? _twelfthPercentage;
  double? _diplomaCgpa;
  String? _twelfthBoard;
  bool _isTenthVerified = false;
  bool _isTwelfthVerified = false;
  bool _isCgpaVerified = false;
  bool _isSkillsExpanded = false;
  Map<String, String> _socialLinks = {};
  bool _hasResume = false;
  int _internshipCount = 0;
  List<dynamic> _internships = [];
  List<String> _deploymentSkills = [];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    // 1. Instant local cache load (Stale-While-Revalidate pattern)
    try {
      final profile = await _tokenStorage.getStudentProfile();
      final accessToken = await _tokenStorage.getAccessToken();

      String localEmail = profile['email'] as String? ?? '';
      if (localEmail.isEmpty && accessToken != null) {
        localEmail = JwtDecoderUtil.getUserIdFromToken(accessToken) ?? '';
      }
      String localFullName = profile['full_name'] as String? ?? profile['fullName'] as String? ?? '';
      if (localFullName.isEmpty && localEmail.isNotEmpty) {
        final prefix = localEmail.split('@')[0];
        localFullName = prefix
            .replaceAll('.', ' ')
            .replaceAll('_', ' ')
            .split(' ')
            .where((w) => w.isNotEmpty)
            .map((w) => '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
            .join(' ');
      }
      if (localFullName.isEmpty) localFullName = 'Student Candidate';

      if (mounted && localEmail.isNotEmpty) {
        setState(() {
          _studentEmail = localEmail;
          _fullName = localFullName;
          _education = profile['education'] as String? ?? '';
          _cgpa = (profile['cgpa'] is num) ? (profile['cgpa'] as num).toDouble() : 0.0;
          _activeBacklogs = (profile['active_backlogs'] is num) ? (profile['active_backlogs'] as num).toInt() : 0;
          _closedBacklogs = (profile['closed_backlogs'] is num) ? (profile['closed_backlogs'] as num).toInt() : 0;
          if (profile['skills'] is List) {
            _skills = List<String>.from(profile['skills'] as List);
          }
          _isLoading = false; // Render cached data immediately
        });
      }
    } catch (_) {}

    // 2. Parallel network refresh
    try {
      Map<String, dynamic> remoteProfile = {};
      Map<String, dynamic> verificationState = {};

      try {
        final responses = await Future.wait([
          ApiClient.instance.dio.get('/auth/me').catchError((_) => Response(requestOptions: RequestOptions(), statusCode: 500)),
          ApiClient.instance.dio.get('/documents/profile/verification-state').catchError((_) => Response(requestOptions: RequestOptions(), statusCode: 500)),
        ]);

        if (responses[0].statusCode == 200 && responses[0].data is Map) {
          remoteProfile = Map<String, dynamic>.from(responses[0].data as Map);
        }
        if (responses[1].statusCode == 200 && responses[1].data is Map) {
          verificationState = Map<String, dynamic>.from(responses[1].data as Map);
        }
      } catch (e) {
        debugPrint('Profile parallel fetch note: $e');
      }

      final profile = await _tokenStorage.getStudentProfile();
      final accessToken = await _tokenStorage.getAccessToken();

      String email = remoteProfile['email'] as String? ?? profile['email'] as String? ?? '';
      if (email.isEmpty && accessToken != null) {
        email = JwtDecoderUtil.getUserIdFromToken(accessToken) ?? '';
      }

      String fullName = remoteProfile['full_name'] as String? ?? profile['full_name'] as String? ?? profile['fullName'] as String? ?? '';
      if (fullName.isEmpty && email.isNotEmpty) {
        final prefix = email.split('@')[0];
        fullName = prefix
            .replaceAll('.', ' ')
            .replaceAll('_', ' ')
            .split(' ')
            .where((w) => w.isNotEmpty)
            .map((w) => '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
            .join(' ');
      }

      if (fullName.isEmpty) {
        fullName = 'Student Candidate';
      }

      String education = remoteProfile['education'] as String? ?? profile['education'] as String? ?? '';
      double cgpa = (remoteProfile['cgpa'] is num)
          ? (remoteProfile['cgpa'] as num).toDouble()
          : ((profile['cgpa'] is num) ? (profile['cgpa'] as num).toDouble() : 0.0);
      int activeBacklogs = (remoteProfile['active_backlogs'] is num)
          ? (remoteProfile['active_backlogs'] as num).toInt()
          : ((profile['active_backlogs'] is num) ? (profile['active_backlogs'] as num).toInt() : 0);
      int closedBacklogs = (remoteProfile['closed_backlogs'] is num)
          ? (remoteProfile['closed_backlogs'] as num).toInt()
          : ((profile['closed_backlogs'] is num) ? (profile['closed_backlogs'] as num).toInt() : 0);

      const softKeywords = {
        'problem solving', 'critical thinking', 'communication', 'teamwork',
        'team leadership', 'leadership', 'collaboration', 'time management',
        'adaptability', 'agile', 'scrum', 'creative thinking', 'decision making',
        'interpersonal skills', 'work ethic', 'public speaking', 'analytical thinking'
      };

      List<String> rawSkills = [];
      if (remoteProfile.containsKey('skills') && remoteProfile['skills'] is List) {
        rawSkills = List<String>.from(remoteProfile['skills'] as List);
      } else if (profile['skills'] is List) {
        rawSkills = List<String>.from(profile['skills'] as List);
      }

      List<String> techSkills = [];
      List<String> softSkills = [];
      if (remoteProfile.containsKey('technical_skills') && remoteProfile['technical_skills'] is List) {
        techSkills = List<String>.from(remoteProfile['technical_skills'] as List);
      }
      if (remoteProfile.containsKey('soft_skills') && remoteProfile['soft_skills'] is List) {
        softSkills = List<String>.from(remoteProfile['soft_skills'] as List);
      }
      if (techSkills.isEmpty && softSkills.isEmpty && rawSkills.isNotEmpty) {
        for (final s in rawSkills) {
          if (softKeywords.contains(s.toLowerCase().trim())) {
            softSkills.add(s);
          } else {
            techSkills.add(s);
          }
        }
      } else if (techSkills.isEmpty && rawSkills.isNotEmpty) {
        techSkills = List<String>.from(rawSkills);
      }

      List<String> languages = [];
      if (remoteProfile.containsKey('languages') && remoteProfile['languages'] is List) {
        languages = List<String>.from(remoteProfile['languages'] as List);
      }

      // Sync to local storage
      await _tokenStorage.saveStudentProfile(
        email: email,
        fullName: fullName,
        education: education,
        cgpa: cgpa,
        activeBacklogs: activeBacklogs,
        closedBacklogs: closedBacklogs,
        skills: rawSkills,
      );

      double? tenthPercentage = (remoteProfile['tenth_percentage'] is num)
          ? (remoteProfile['tenth_percentage'] as num).toDouble()
          : null;
      String? tenthBoard = remoteProfile['tenth_board'] as String?;
      int? tenthYear = (remoteProfile['tenth_passing_year'] is num)
          ? (remoteProfile['tenth_passing_year'] as num).toInt()
          : null;

      double? twelfthPercentage = (remoteProfile['twelfth_percentage'] is num)
          ? (remoteProfile['twelfth_percentage'] as num).toDouble()
          : null;
      double? diplomaCgpa = (remoteProfile['diploma_cgpa'] is num)
          ? (remoteProfile['diploma_cgpa'] as num).toDouble()
          : null;
      String? twelfthBoard = remoteProfile['twelfth_board'] as String?;

      final branch = remoteProfile['branch'] as String?;
      final course = remoteProfile['course'] as String? ?? 'B.Tech';
      if (education.isEmpty || education == 'Pending Document Verification' || education == 'Not Specified') {
        if (branch != null && branch.isNotEmpty) {
          education = '$course - $branch';
        } else {
          education = 'B.Tech - Computer Science & Engineering';
        }
      }

      final verifiedFields = remoteProfile['verified_fields'] as Map<String, dynamic>? ?? {};
      final isTenthVerified = verifiedFields.containsKey('tenth_percentage');
      final isTwelfthVerified = verifiedFields.containsKey('twelfth_percentage') || verifiedFields.containsKey('diploma_cgpa');
      final isCgpaVerified = verifiedFields.containsKey('CGPA');

      bool hasResume = remoteProfile['has_resume'] == true;
      if (remoteProfile['documents'] is Map && remoteProfile['documents']['resume'] != null) {
        hasResume = true;
      }
      if (verificationState['documents_summary'] is Map && verificationState['documents_summary']['resume'] != null) {
        hasResume = true;
      }

      Map<String, String> socialLinks = {};
      if (hasResume) {
        if (remoteProfile['social_links'] is Map) {
          (remoteProfile['social_links'] as Map).forEach((k, v) {
            if (v != null && v.toString().trim().isNotEmpty) {
              socialLinks[k.toString().toLowerCase()] = v.toString().trim();
            }
          });
        }
        if (remoteProfile['linkedin_url'] != null && !socialLinks.containsKey('linkedin')) {
          final s = remoteProfile['linkedin_url'].toString().trim();
          if (s.isNotEmpty) socialLinks['linkedin'] = s;
        }
        if (remoteProfile['github_url'] != null && !socialLinks.containsKey('github')) {
          final s = remoteProfile['github_url'].toString().trim();
          if (s.isNotEmpty) socialLinks['github'] = s;
        }
        if (remoteProfile['leetcode_url'] != null && !socialLinks.containsKey('leetcode')) {
          final s = remoteProfile['leetcode_url'].toString().trim();
          if (s.isNotEmpty) socialLinks['leetcode'] = s;
        }
        if (remoteProfile['portfolio_url'] != null && !socialLinks.containsKey('portfolio')) {
          final s = remoteProfile['portfolio_url'].toString().trim();
          if (s.isNotEmpty) socialLinks['portfolio'] = s;
        }
      }

      int internshipCount = (remoteProfile['internship_count'] is num)
          ? (remoteProfile['internship_count'] as num).toInt()
          : 0;
      List<dynamic> internships = (remoteProfile['internships'] is List)
          ? remoteProfile['internships'] as List
          : [];
      List<String> deploymentSkills = [];
      if (remoteProfile['deployment_skills'] is List) {
        deploymentSkills = List<String>.from(remoteProfile['deployment_skills'] as List);
      }

      if (mounted) {
        setState(() {
          _studentEmail = email;
          _fullName = fullName;
          _education = education;
          _cgpa = cgpa;
          _activeBacklogs = activeBacklogs;
          _closedBacklogs = closedBacklogs;
          _skills = rawSkills;
          _technicalSkills = techSkills;
          _softSkills = softSkills;
          _languages = languages;
          _internshipCount = internshipCount;
          _internships = internships;
          _deploymentSkills = deploymentSkills;
          _verifiedFieldsMap = verificationState['document_verified_fields'] is Map
              ? Map<String, dynamic>.from(verificationState['document_verified_fields'] as Map)
              : {};
          _tenthPercentage = tenthPercentage;
          _tenthBoard = tenthBoard;
          _tenthYear = tenthYear;
          _twelfthPercentage = twelfthPercentage;
          _diplomaCgpa = diplomaCgpa;
          _twelfthBoard = twelfthBoard;
          _isTenthVerified = isTenthVerified;
          _isTwelfthVerified = isTwelfthVerified;
          _isCgpaVerified = isCgpaVerified;
          _hasResume = hasResume;
          _socialLinks = socialLinks;
        });
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }


  Future<void> _openPlatformUrl(
    String rawUrl, {
    required String appName,
    IconData? icon,
    Color? brandColor,
  }) async {
    final allow = await PermissionDialogs.requestExternalAppPermission(
      context,
      appName: appName,
      targetUrl: rawUrl,
      icon: icon,
      brandColor: brandColor,
    );
    if (!allow) return;

    try {
      final uri = Uri.parse(rawUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open link: $rawUrl'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Widget _buildPlatformChip(String platform, String url, bool isDark) {
    final visuals = _getPlatformVisuals(platform, isDark);
    final label = visuals.$1;
    final icon = visuals.$2;
    final color = visuals.$3;
    final bg = visuals.$4;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openPlatformUrl(
          url,
          appName: label,
          icon: icon,
          brandColor: color,
        ),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: color.withValues(alpha: 0.35),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.arrow_outward_rounded, size: 11, color: color.withValues(alpha: 0.7)),
            ],
          ),
        ),
      ),
    );
  }

  (String, IconData, Color, Color) _getPlatformVisuals(String platform, bool isDark) {
    switch (platform.toLowerCase()) {
      case 'linkedin':
        return (
          'LinkedIn',
          Icons.business_center_rounded,
          const Color(0xFF0A66C2),
          const Color(0xFF0A66C2).withValues(alpha: isDark ? 0.2 : 0.1),
        );
      case 'github':
        return (
          'GitHub',
          Icons.terminal_rounded,
          isDark ? const Color(0xFFE6EDF3) : const Color(0xFF24292E),
          isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFF24292E).withValues(alpha: 0.08),
        );
      case 'leetcode':
        return (
          'LeetCode',
          Icons.code_rounded,
          const Color(0xFFFFA116),
          const Color(0xFFFFA116).withValues(alpha: isDark ? 0.2 : 0.1),
        );
      case 'codeforces':
        return (
          'Codeforces',
          Icons.leaderboard_rounded,
          const Color(0xFF1F8ACB),
          const Color(0xFF1F8ACB).withValues(alpha: isDark ? 0.2 : 0.1),
        );
      case 'codechef':
        return (
          'CodeChef',
          Icons.data_object_rounded,
          const Color(0xFF8B5A2B),
          const Color(0xFF8B5A2B).withValues(alpha: isDark ? 0.2 : 0.1),
        );
      case 'hackerrank':
        return (
          'HackerRank',
          Icons.check_circle_outline_rounded,
          const Color(0xFF00EA64),
          const Color(0xFF00EA64).withValues(alpha: isDark ? 0.2 : 0.1),
        );
      case 'kaggle':
        return (
          'Kaggle',
          Icons.analytics_rounded,
          const Color(0xFF20BEFF),
          const Color(0xFF20BEFF).withValues(alpha: isDark ? 0.2 : 0.1),
        );
      case 'geeksforgeeks':
        return (
          'GeeksforGeeks',
          Icons.computer_rounded,
          const Color(0xFF2F8D46),
          const Color(0xFF2F8D46).withValues(alpha: isDark ? 0.2 : 0.1),
        );
      case 'portfolio':
        return (
          'Portfolio',
          Icons.language_rounded,
          AppColors.lightPrimary,
          AppColors.lightPrimary.withValues(alpha: isDark ? 0.2 : 0.1),
        );
      case 'twitter':
        return (
          'X / Twitter',
          Icons.alternate_email_rounded,
          const Color(0xFF1DA1F2),
          const Color(0xFF1DA1F2).withValues(alpha: isDark ? 0.2 : 0.1),
        );
      default:
        return (
          platform.toUpperCase(),
          Icons.link_rounded,
          AppColors.lightPrimary,
          AppColors.lightPrimary.withValues(alpha: isDark ? 0.2 : 0.1),
        );
    }
  }

  void _showProvenanceBottomSheet({
    required String fieldKey,
    required String fieldTitle,
    required String currentValue,
    required bool isVerified,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fieldMeta = _verifiedFieldsMap[fieldKey] is Map ? _verifiedFieldsMap[fieldKey] as Map : null;
    final provenance = fieldMeta?['provenance'] is Map ? fieldMeta!['provenance'] as Map : null;

    final confidence = (fieldMeta?['confidence'] ?? provenance?['confidence'] ?? 95.0) as num;
    final extractionMethod = (fieldMeta?['extraction_method'] ?? provenance?['extraction_method'] ?? 'native').toString();
    final sourceDoc = (fieldMeta?['source'] ?? provenance?['source'] ?? provenance?['source_document_type'] ?? 'Academic Marksheet / Certificate').toString();
    final verifiedAt = (provenance?['verified_at'] ?? '').toString();

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fieldTitle,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          currentValue,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isVerified ? AppColors.success : null,
                            fontSize: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isVerified ? AppColors.success.withValues(alpha: 0.12) : AppColors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isVerified ? AppColors.success.withValues(alpha: 0.3) : AppColors.warning.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isVerified ? Icons.verified_rounded : Icons.info_outline_rounded,
                          size: 14,
                          color: isVerified ? AppColors.success : AppColors.warning,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isVerified ? '✓ Verified' : 'Self-Reported',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isVerified ? AppColors.success : AppColors.warning,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Divider(height: 1, color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant),
              const SizedBox(height: 14),
              _buildProvenanceRow('Source Document', sourceDoc, Icons.description_outlined, isDark),
              const SizedBox(height: 10),
              _buildProvenanceRow(
                'Extraction Method',
                extractionMethod == 'ocr'
                    ? 'Neural OCR (Scanned Image/PDF)'
                    : (extractionMethod == 'manual_override'
                        ? 'Manually Verified by Admin'
                        : 'Native Vector Text Engine'),
                Icons.memory_rounded,
                isDark,
              ),
              const SizedBox(height: 10),
              _buildProvenanceRow('Confidence Score', '$confidence% match', Icons.analytics_outlined, isDark),
              if (verifiedAt.isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildProvenanceRow('Verification Date', verifiedAt.split('T')[0], Icons.schedule_rounded, isDark),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showDisputeDialog(fieldKey: fieldKey, fieldTitle: fieldTitle, currentValue: currentValue);
                  },
                  icon: const Icon(Icons.flag_outlined, size: 16, color: AppColors.error),
                  label: const Text('Flag for Review / Dispute Value', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColors.error.withValues(alpha: 0.4)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showInternshipsModal() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.work_history_rounded, color: AppColors.lightPrimary, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Internships & Industry Experience',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (_internships.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Column(
                      children: [
                        const Icon(Icons.info_outline_rounded, size: 36, color: AppColors.lightTextSecondary),
                        const SizedBox(height: 8),
                        Text(
                          _internshipCount > 0
                              ? '$_internshipCount internship${_internshipCount > 1 ? 's' : ''} detected from your resume.'
                              : 'No internships extracted from resume yet.',
                          style: const TextStyle(fontSize: 13, color: AppColors.lightTextSecondary),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _internships.length,
                    separatorBuilder: (_, _) => const Divider(height: 16),
                    itemBuilder: (_, i) {
                      final item = _internships[i] is Map ? _internships[i] as Map : {'description': _internships[i].toString()};
                      final comp = (item['company_name'] ?? 'Company').toString();
                      final role = (item['role_title'] ?? 'Intern').toString();
                      final dur = (item['duration'] ?? '').toString();
                      final desc = (item['description'] ?? '').toString();

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  role,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                              ),
                              if (dur.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryLightBg,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    dur,
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.lightPrimary),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            comp,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.lightPrimary),
                          ),
                          if (desc.isNotEmpty && desc != '$role at $comp') ...[
                            const SizedBox(height: 4),
                            Text(
                              desc,
                              style: const TextStyle(fontSize: 11.5, color: AppColors.lightTextSecondary),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showDeploymentModal() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.cloud_done_rounded, color: AppColors.lightPrimary, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Cloud & Deployment Experience',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  if (_deploymentSkills.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkPrimaryContainer : AppColors.primaryLightBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${_deploymentSkills.length} Skills',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.lightPrimary),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              if (_deploymentSkills.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.cloud_off_rounded, size: 36, color: AppColors.lightTextSecondary),
                        SizedBox(height: 8),
                        Text(
                          'No cloud or deployment tools extracted yet.',
                          style: TextStyle(fontSize: 13, color: AppColors.lightTextSecondary),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Add Docker, AWS, GCP, Git, CI/CD, or Kubernetes to your resume to showcase deployment readiness.',
                          style: TextStyle(fontSize: 11.5, color: AppColors.lightTextSecondary),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _deploymentSkills.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final skill = _deploymentSkills[i];
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkSurfaceContainerLow : AppColors.lightSurfaceContainerLow,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: isDark ? AppColors.darkPrimaryContainer : AppColors.primaryLightBg,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.cloud_queue_rounded, size: 16, color: AppColors.lightPrimary),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                skill,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                              ),
                            ),
                            const Icon(Icons.check_circle_rounded, size: 16, color: AppColors.success),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showDisputeDialog({
    required String fieldKey,
    required String fieldTitle,
    required String currentValue,
  }) {
    final reasonController = TextEditingController();
    final suggestedController = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (dCtx) {
        return AlertDialog(
          backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.flag_rounded, color: AppColors.error, size: 22),
              const SizedBox(width: 8),
              Text('Dispute $fieldTitle', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'If the automated extraction extracted an incorrect value ($currentValue), submit a dispute. A placement coordinator will cross-reference your document.',
                  style: const TextStyle(fontSize: 12, color: AppColors.lightTextSecondary),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: suggestedController,
                  decoration: InputDecoration(
                    labelText: 'What should this value be?',
                    hintText: 'e.g. 8.95',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Reason / Note (optional)',
                    hintText: 'e.g. Document was blurry or folded at this line',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(dCtx);
                try {
                  final reason = '${suggestedController.text.trim().isNotEmpty ? 'Suggested: ${suggestedController.text.trim()}. ' : ''}${reasonController.text.trim()}';
                  await ApiClient.instance.dio.post(
                    '/documents/profile/verified-data/$fieldKey/flag',
                    data: {'reason': reason},
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('✓ $fieldTitle flagged for review. Dispute ticket created.'),
                        backgroundColor: AppColors.success,
                      ),
                    );
                    _loadProfile();
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to flag field: $e'),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.lightPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Submit Dispute', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildProvenanceRow(String label, String value, IconData icon, bool isDark) {
    return Row(
      children: [
        Icon(icon, size: 16, color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Future<void> _showEditProfileModal() async {
    final updated = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const EditProfileScreen()),
    );
    if (updated == true) {
      _loadProfile();
    }
  }



  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const ProfileSkeleton();
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return RefreshIndicator(
      onRefresh: _loadProfile,
      color: AppColors.lightPrimary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Top Profile Summary Header Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _fullName.isNotEmpty ? _fullName : 'Student Candidate',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (_education.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    _education,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                      color: isDark ? AppColors.darkTextPrimary : const Color(0xFF1E293B),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (_studentEmail.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    _studentEmail,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      fontSize: 12.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkSurfaceContainerHigh : AppColors.lightSurfaceContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.school_rounded, size: 13, color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                          const SizedBox(width: 4),
                          Text('GSFC University', style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.successLightBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified_user_rounded, size: 13, color: AppColors.success),
                          SizedBox(width: 4),
                          Text('Verified Student', style: TextStyle(fontSize: 11, color: AppColors.success, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_hasResume && _socialLinks.values.any((u) => u.trim().isNotEmpty)) ...[
                  const SizedBox(height: 12),
                  Divider(
                    height: 1,
                    color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _socialLinks.entries
                        .where((e) => e.value.trim().isNotEmpty)
                        .map((e) => _buildPlatformChip(e.key, e.value, isDark))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 2. Academic & Education Profile Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Icon(Icons.school_rounded, size: 20, color: AppColors.lightPrimary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Academic & Education Profile',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.lightPrimary),
                      onPressed: _showEditProfileModal,
                      tooltip: 'Edit Profile',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(
                  height: 1,
                  color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                ),
                const SizedBox(height: 14),

                // Row 1: Current CGPA & Class 12th / Diploma
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _showProvenanceBottomSheet(
                          fieldKey: 'CGPA',
                          fieldTitle: 'Current CGPA',
                          currentValue: _cgpa > 0 ? '$_cgpa / 10.0' : '--',
                          isVerified: _isCgpaVerified,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    'Current CGPA',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              (_isCgpaVerified && _cgpa > 0) ? '$_cgpa / 10.0' : '--',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: (_isCgpaVerified && _cgpa > 0) ? AppColors.success : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: InkWell(
                        onTap: () => _showProvenanceBottomSheet(
                          fieldKey: _diplomaCgpa != null ? 'diploma_cgpa' : 'twelfth_percentage',
                          fieldTitle: _diplomaCgpa != null ? 'Diploma CGPA' : 'Class 12th Score',
                          currentValue: _diplomaCgpa != null
                              ? '$_diplomaCgpa CGPA'
                              : (_twelfthPercentage != null ? '$_twelfthPercentage%' : '--'),
                          isVerified: _isTwelfthVerified,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    'Class 12th / Diploma',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _diplomaCgpa != null
                                  ? '$_diplomaCgpa CGPA'
                                  : (_twelfthPercentage != null ? '$_twelfthPercentage%' : '--'),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: _isTwelfthVerified ? AppColors.success : null,
                              ),
                            ),
                            if (_twelfthBoard != null && _twelfthBoard!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                _twelfthBoard!.contains('Baroda') ? 'ITM SLS Baroda' : _twelfthBoard!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11,
                                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Row 2: Class 10th Score & Backlog Status
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _showProvenanceBottomSheet(
                          fieldKey: 'tenth_percentage',
                          fieldTitle: 'Class 10th Score',
                          currentValue: _tenthPercentage != null ? '$_tenthPercentage%' : '--',
                          isVerified: _isTenthVerified,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    'Class 10th Score',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _tenthPercentage != null ? '$_tenthPercentage%' : '--',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: _isTenthVerified ? AppColors.success : null,
                              ),
                            ),
                            if (_tenthBoard != null && _tenthBoard!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                '${_tenthBoard!.contains('GSEB') ? 'GSEB' : (_tenthBoard!.contains('CBSE') ? 'CBSE' : 'State Board')}${_tenthYear != null ? ' • $_tenthYear' : ''}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11,
                                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: InkWell(
                        onTap: () => _showProvenanceBottomSheet(
                          fieldKey: 'active_backlogs',
                          fieldTitle: 'Backlogs Status',
                          currentValue: !_isCgpaVerified
                              ? '--'
                              : (_activeBacklogs == 0
                                  ? 'No Backlogs'
                                  : '$_activeBacklogs Active${_closedBacklogs > 0 ? ' • $_closedBacklogs Cleared' : ''}'),
                          isVerified: _isCgpaVerified && _activeBacklogs == 0,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    'Backlogs Status',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              !_isCgpaVerified
                                  ? '--'
                                  : (_activeBacklogs == 0 ? 'No Backlogs' : '$_activeBacklogs Active'),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: !_isCgpaVerified
                                    ? null
                                    : (_activeBacklogs == 0 ? AppColors.success : AppColors.error),
                              ),
                            ),
                            if (_closedBacklogs > 0) ...[
                              const SizedBox(height: 2),
                              Text(
                                '$_closedBacklogs Cleared',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11,
                                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Row 3: Internships Completed & Cloud/Deployment Knowledge
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Card 1: Internships
                      Expanded(
                        child: InkWell(
                          onTap: _showInternshipsModal,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.darkSurfaceContainerHigh : AppColors.lightSurfaceContainer,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _internshipCount > 0
                                    ? AppColors.success.withValues(alpha: 0.35)
                                    : (isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.work_history_rounded,
                                      size: 15,
                                      color: _internshipCount > 0 ? AppColors.success : AppColors.lightPrimary,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Internships',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.bold,
                                          color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const Icon(Icons.arrow_forward_ios_rounded, size: 11, color: AppColors.lightTextSecondary),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _internshipCount > 0
                                      ? '$_internshipCount Completed'
                                      : '0 Reported',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: _internshipCount > 0 ? AppColors.success : isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Card 2: Deployment & Cloud
                      Expanded(
                        child: InkWell(
                          onTap: _showDeploymentModal,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.darkSurfaceContainerHigh : AppColors.lightSurfaceContainer,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _deploymentSkills.isNotEmpty
                                    ? AppColors.lightPrimary.withValues(alpha: 0.35)
                                    : (isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.cloud_done_rounded,
                                      size: 15,
                                      color: _deploymentSkills.isNotEmpty ? AppColors.lightPrimary : AppColors.lightTextSecondary,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Deployment',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.bold,
                                          color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const Icon(Icons.arrow_forward_ios_rounded, size: 11, color: AppColors.lightTextSecondary),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _deploymentSkills.isNotEmpty
                                            ? _deploymentSkills.take(2).join(', ')
                                            : 'Standard Local',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: _deploymentSkills.isNotEmpty
                                              ? (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary)
                                              : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                    ),
                                    if (_deploymentSkills.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: isDark ? AppColors.darkPrimaryContainer : AppColors.primaryLightBg,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '${_deploymentSkills.length}',
                                          style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: AppColors.lightPrimary),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Divider(
                  height: 1,
                  color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                ),
                const SizedBox(height: 14),

                // 1. Technical Skills Section Heading
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Icon(Icons.code_rounded, size: 20, color: AppColors.lightPrimary),
                    const SizedBox(width: 8),
                    Text(
                      'Technical Skills',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    if ((_technicalSkills.isNotEmpty ? _technicalSkills : _skills).isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkSurfaceVariant : AppColors.primaryLightBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${(_technicalSkills.isNotEmpty ? _technicalSkills : _skills).length} verified',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.lightPrimary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                if ((_technicalSkills.isNotEmpty ? _technicalSkills : _skills).isNotEmpty) ...[
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: (_isSkillsExpanded
                            ? (_technicalSkills.isNotEmpty ? _technicalSkills : _skills)
                            : (_technicalSkills.isNotEmpty ? _technicalSkills : _skills).take(12))
                        .map((skill) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkSurfaceContainerHigh : AppColors.lightSurfaceContainer,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                          ),
                        ),
                        child: Text(
                          skill,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 11.5,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  if ((_technicalSkills.isNotEmpty ? _technicalSkills : _skills).length > 12) ...[
                    const SizedBox(height: 8),
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => setState(() => _isSkillsExpanded = !_isSkillsExpanded),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _isSkillsExpanded
                                  ? 'Show fewer skills'
                                  : 'View all ${(_technicalSkills.isNotEmpty ? _technicalSkills : _skills).length} skills (+${(_technicalSkills.isNotEmpty ? _technicalSkills : _skills).length - 12} more)',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.lightPrimary,
                              ),
                            ),
                            Icon(
                              _isSkillsExpanded
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              size: 16,
                              color: AppColors.lightPrimary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ] else
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'No technical skills added yet',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
                  ),

                // 2. Soft Skills & Competencies Section (Section 11 Spec)
                if (_softSkills.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Divider(
                    height: 1,
                    color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(Icons.psychology_rounded, size: 20, color: AppColors.lightPrimary),
                      const SizedBox(width: 8),
                      Text(
                        'Soft Skills & Competencies',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkSurfaceVariant : AppColors.primaryLightBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${_softSkills.length} verified',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.lightPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: _softSkills.map((skill) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkSurfaceContainerHigh : AppColors.lightSurfaceContainer,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                          ),
                        ),
                        child: Text(
                          skill,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 11.5,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],

                // 3. Known Languages Section (Section 11 Spec)
                if (_languages.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Divider(
                    height: 1,
                    color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(Icons.translate_rounded, size: 20, color: AppColors.lightPrimary),
                      const SizedBox(width: 8),
                      Text(
                        'Known Languages',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: _languages.map((lang) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkSurfaceContainerHigh : AppColors.lightSurfaceContainer,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                          ),
                        ),
                        child: Text(
                          lang,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 11.5,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 3. Document Verification Card
          InkWell(
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const DocumentVerificationScreen()),
              );
              _loadProfile();
            },
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                      color: AppColors.primaryLightBg,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.verified_user_rounded,
                      color: AppColors.lightPrimary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Verify Documents',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'PDF, DOC, DOCX (Max 10MB)',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11.5,
                            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const DocumentVerificationScreen()),
                      );
                      _loadProfile();
                    },
                    icon: const Icon(Icons.file_upload_outlined, color: AppColors.lightPrimary, size: 22),
                    tooltip: 'Verify Documents',
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    padding: const EdgeInsets.all(6),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 100),
        ],
      ),
    ),
  );
}
}