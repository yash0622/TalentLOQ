import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../services/token_storage_service.dart';
import '../../network/api_client.dart';
import 'document_verification_screen.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final TokenStorageService _tokenStorage = TokenStorageService();
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _universityController;

  // Read-only verified academic fields
  String _education = '';
  double _cgpa = 0.0;
  int _activeBacklogs = 0;
  int _closedBacklogs = 0;
  List<String> _skills = [];
  double? _tenthPercentage;
  double? _twelfthPercentage;
  double? _diplomaCgpa;
  String? _enrollmentNumber;
  int? _currentSemester;

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _emailController = TextEditingController();
    _universityController = TextEditingController();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _universityController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      Map<String, dynamic> remote = {};
      try {
        final res = await ApiClient.instance.dio.get('/auth/me');
        if (res.statusCode == 200 && res.data is Map) {
          remote = Map<String, dynamic>.from(res.data as Map);
        }
      } catch (e) {
        debugPrint('Fetch profile note: $e');
      }

      final profile = await _tokenStorage.getStudentProfile();

      setState(() {
        _nameController.text = remote['full_name'] ?? profile['full_name'] ?? '';
        _emailController.text = remote['email'] ?? profile['email'] ?? '';
        _universityController.text = remote['university'] ?? profile['university'] ?? 'GSFC University';

        _education = remote['education'] ?? profile['education'] ?? '';
        _cgpa = (remote['cgpa'] as num?)?.toDouble() ?? (profile['cgpa'] as num?)?.toDouble() ?? 0.0;
        _activeBacklogs = (remote['active_backlogs'] as num?)?.toInt() ?? (profile['active_backlogs'] as num?)?.toInt() ?? 0;
        _closedBacklogs = (remote['closed_backlogs'] as num?)?.toInt() ?? (profile['closed_backlogs'] as num?)?.toInt() ?? 0;

        if (remote['skills'] is List) {
          _skills = List<String>.from(remote['skills'] as List);
        } else if (profile['skills'] is List) {
          _skills = List<String>.from(profile['skills'] as List);
        }

        _tenthPercentage = (remote['tenth_percentage'] as num?)?.toDouble();
        _twelfthPercentage = (remote['twelfth_percentage'] as num?)?.toDouble();
        _diplomaCgpa = (remote['diploma_cgpa'] as num?)?.toDouble();
        _enrollmentNumber = remote['enrollment_number'];
        _currentSemester = (remote['current_semester'] as num?)?.toInt();

        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading profile: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    final fullName = _nameController.text.trim();
    final email = _emailController.text.trim();
    final university = _universityController.text.trim();

    try {
      // Save locally
      await _tokenStorage.saveStudentProfile(
        email: email,
        fullName: fullName,
        university: university,
        education: _education,
        cgpa: _cgpa,
        activeBacklogs: _activeBacklogs,
        closedBacklogs: _closedBacklogs,
        skills: _skills,
      );

      // Save to backend - ONLY Name, Email, University allowed
      try {
        await ApiClient.instance.dio.put('/auth/me', data: {
          'full_name': fullName,
          'email': email,
          'university': university,
        });
      } catch (e) {
        debugPrint('PUT /auth/me update note: $e');
      }

      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Profile updated successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving profile: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Profile')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: AppBar(
        title: const Text('Edit Profile', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        elevation: 0,
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        actions: [
          TextButton.icon(
            onPressed: _isSaving ? null : _saveProfile,
            icon: _isSaving
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check_rounded, size: 20),
            label: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Avatar & University Badge
              Center(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: AppColors.primaryLightBg,
                      child: Text(
                        _nameController.text.isNotEmpty ? _nameController.text[0].toUpperCase() : 'S',
                        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.lightPrimary),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLightBg,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.verified_rounded, size: 14, color: AppColors.lightPrimary),
                          const SizedBox(width: 4),
                          Text(
                            _universityController.text.isNotEmpty ? _universityController.text : 'GSFC University',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.lightPrimary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 1. Manually Editable Fields Card
              _buildSectionCard(
                isDark: isDark,
                title: 'Personal Information (Editable)',
                icon: Icons.person_outline_rounded,
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                      prefixIcon: Icon(Icons.badge_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter your full name' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'Registered Email ID',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || !v.contains('@')) ? 'Please enter a valid email' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _universityController,
                    decoration: const InputDecoration(
                      labelText: 'University Name',
                      prefixIcon: Icon(Icons.account_balance_rounded),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter university name' : null,
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // 2. Verified Academic Information Card (Read-Only)
              _buildSectionCard(
                isDark: isDark,
                title: 'Academic Credentials (Verified & Read-Only)',
                icon: Icons.lock_rounded,
                headerBadge: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified_rounded, size: 12, color: AppColors.success),
                      SizedBox(width: 4),
                      Text('Tamper-Resistant', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.success)),
                    ],
                  ),
                ),
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurfaceContainerLow : AppColors.lightSurfaceContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded, size: 16, color: AppColors.lightPrimary),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Academic fields are automatically extracted from your official marksheets. Students cannot manually edit these fields.',
                            style: TextStyle(fontSize: 12, color: AppColors.lightTextSecondary, height: 1.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Metrics Grid
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricTile(
                          isDark: isDark,
                          label: 'Cumulative CGPA',
                          value: _cgpa > 0 ? '$_cgpa / 10.0' : 'Not Verified',
                          isVerified: _cgpa > 0,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildMetricTile(
                          isDark: isDark,
                          label: 'Active Backlogs',
                          value: '$_activeBacklogs Active',
                          isVerified: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricTile(
                          isDark: isDark,
                          label: '10th Percentage',
                          value: _tenthPercentage != null ? '$_tenthPercentage%' : 'Pending',
                          isVerified: _tenthPercentage != null,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildMetricTile(
                          isDark: isDark,
                          label: '12th / Diploma',
                          value: _twelfthPercentage != null
                              ? '$_twelfthPercentage%'
                              : (_diplomaCgpa != null ? '$_diplomaCgpa CGPA' : 'Pending'),
                          isVerified: _twelfthPercentage != null || _diplomaCgpa != null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Degree & Enrollment
                  if (_education.isNotEmpty || _enrollmentNumber != null) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Degree & Branch', style: TextStyle(fontSize: 11, color: AppColors.lightTextSecondary)),
                              const SizedBox(height: 2),
                              Text(
                                _education.isNotEmpty
                                    ? (_currentSemester != null ? '$_education (Sem $_currentSemester)' : _education)
                                    : 'B.Tech CSE',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        if (_enrollmentNumber != null)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text('Enrollment No', style: TextStyle(fontSize: 11, color: AppColors.lightTextSecondary)),
                              const SizedBox(height: 2),
                              Text(_enrollmentNumber!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Verified Skills Chips
                  const Text('Verified Technical Skills', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_skills.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _skills.map((s) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLightBg,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.lightPrimary.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_circle_rounded, size: 12, color: AppColors.success),
                              const SizedBox(width: 4),
                              Text(s, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.lightPrimary)),
                            ],
                          ),
                        );
                      }).toList(),
                    )
                  else
                    const Text('No skills extracted from resume yet.', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: AppColors.lightTextSecondary)),
                  const SizedBox(height: 16),

                  // Open Document Verification Center Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const DocumentVerificationScreen()),
                        );
                        _loadProfile();
                      },
                      icon: const Icon(Icons.document_scanner_rounded, size: 18),
                      label: const Text('Open Document Verification Center', style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.lightPrimary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricTile({
    required bool isDark,
    required String label,
    required String value,
    required bool isVerified,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceContainerHigh : AppColors.lightSurfaceContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isVerified ? AppColors.success.withValues(alpha: 0.3) : (isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: const TextStyle(fontSize: 11, color: AppColors.lightTextSecondary)),
              const Spacer(),
              if (isVerified)
                const Icon(Icons.check_circle_rounded, size: 12, color: AppColors.success),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isVerified ? AppColors.success : (isDark ? Colors.white : Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required bool isDark,
    required String title,
    required IconData icon,
    Widget? headerBadge,
    required List<Widget> children,
  }) {
    return Container(
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
            children: [
              Icon(icon, color: AppColors.lightPrimary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              ?headerBadge,
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}
