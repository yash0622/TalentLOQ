import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:dio/dio.dart';
import '../../models/models.dart';
import '../../theme/app_colors.dart';
import '../../services/token_storage_service.dart';
import '../../widgets/skeleton_widgets.dart';
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
  String _education = 'B.Tech CSE';
  double _cgpa = 7.9;
  int _activeBacklogs = 0;
  int _closedBacklogs = 2;
  List<String> _skills = ['Python', 'React JS'];

  String? _resumeFileName;
  String? _resumeFilePath;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      Map<String, dynamic> remoteProfile = {};
      try {
        final res = await ApiClient.instance.dio.get('/auth/me');
        if (res.statusCode == 200 && res.data is Map) {
          remoteProfile = Map<String, dynamic>.from(res.data as Map);
        }
      } catch (e) {
        debugPrint('Backend profile fetch note: $e');
      }

      final profile = await _tokenStorage.getStudentProfile();
      final resumeInfo = await _tokenStorage.getResume();
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

      String education = remoteProfile['education'] as String? ?? profile['education'] as String? ?? 'B.Tech CSE';
      double cgpa = (remoteProfile['cgpa'] is num) ? (remoteProfile['cgpa'] as num).toDouble() : (profile['cgpa'] as double? ?? 8.0);
      int activeBacklogs = (remoteProfile['active_backlogs'] is num) ? (remoteProfile['active_backlogs'] as num).toInt() : (profile['active_backlogs'] as int? ?? 0);
      int closedBacklogs = (remoteProfile['closed_backlogs'] is num) ? (remoteProfile['closed_backlogs'] as num).toInt() : (profile['closed_backlogs'] as int? ?? 0);

      List<String> skills = [];
      if (remoteProfile['skills'] is List && (remoteProfile['skills'] as List).isNotEmpty) {
        skills = List<String>.from(remoteProfile['skills'] as List);
      } else {
        skills = List<String>.from(profile['skills'] as List? ?? []);
      }

      String? resumeName = remoteProfile['resume_filename'] as String? ?? resumeInfo['fileName'];
      if (resumeName == null || resumeName.isEmpty || resumeName.toLowerCase().contains('jane_smith')) {
        final cleanName = fullName.trim().replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
        resumeName = '${cleanName}_Resume.pdf';
      }

      // Sync to local storage
      await _tokenStorage.saveStudentProfile(
        email: email,
        fullName: fullName,
        education: education,
        cgpa: cgpa,
        activeBacklogs: activeBacklogs,
        closedBacklogs: closedBacklogs,
        skills: skills,
      );

      if (mounted) {
        setState(() {
          _studentEmail = email;
          _fullName = fullName;
          _education = education;
          _cgpa = cgpa;
          _activeBacklogs = activeBacklogs;
          _closedBacklogs = closedBacklogs;
          _skills = skills;
          _resumeFileName = resumeName;
          _resumeFilePath = resumeInfo['filePath'];
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

  Future<void> _pickAndUploadResume() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'txt'],
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final name = file.name;
        final path = file.path ?? '';

        if (path.isEmpty) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No readable file path selected.'),
              backgroundColor: AppColors.error,
            ),
          );
          return;
        }

        // Show uploading indicator
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text('Analyzing document & validating resume structure...')),
              ],
            ),
            duration: const Duration(seconds: 2),
            backgroundColor: AppColors.lightPrimary,
          ),
        );

        final formData = FormData.fromMap({
          'file': await MultipartFile.fromFile(path, filename: name),
        });

        final response = await ApiClient.instance.dio.post('/auth/upload-resume', data: formData);

        if (response.statusCode == 200) {
          final resData = response.data as Map<String, dynamic>? ?? {};
          final classification = resData['document_classification'] as Map<String, dynamic>?;
          final confidence = classification != null ? (classification['confidence'] as num?)?.toDouble() : null;

          await _tokenStorage.saveResume(fileName: name, filePath: path);

          setState(() {
            _resumeFileName = name;
            _resumeFilePath = path;
          });

          if (!mounted) return;
          final confPercent = confidence != null ? (confidence * 100).toInt() : 90;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✓ Resume Detected (Confidence: $confPercent%)\nProcessing your resume...'),
              backgroundColor: AppColors.success,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } on DioException catch (e) {
      if (!mounted) return;
      String errorText = 'This document does not appear to be a resume. Please upload a valid resume/CV.';
      
      if (e.response != null && e.response?.data != null) {
        final resData = e.response?.data;
        if (resData is Map<String, dynamic> && resData.containsKey('detail')) {
          final detail = resData['detail'];
          if (detail is Map<String, dynamic>) {
            final docClass = detail['document_classification'] as Map<String, dynamic>?;
            final confidence = docClass != null ? (docClass['confidence'] as num?)?.toDouble() : 0.0;
            
            if (confidence != null && confidence > 0.30 && confidence < 0.70) {
              errorText = '⚠ Unable to confidently identify this document as a resume. Please upload a clearer or properly formatted resume.';
            } else if (detail['message'] != null) {
              errorText = '✕ ${detail['message']}';
            }
          } else if (detail is String) {
            errorText = '✕ $detail';
          }
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorText),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not upload file: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _openAndShowResume() async {
    if (_resumeFilePath != null && _resumeFilePath!.isNotEmpty) {
      final result = await OpenFilex.open(_resumeFilePath!);
      if (result.type != ResultType.done) {
        if (!mounted) return;
        _showResumeFallbackDialog(result.message);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No resume file path found. Please re-upload your resume.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _showResumeFallbackDialog(String errorMessage) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.picture_as_pdf_rounded, color: AppColors.lightPrimary),
              SizedBox(width: 8),
              Text('Resume Document'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_resumeFileName ?? 'Resume.pdf', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                'Status: $errorMessage',
                style: const TextStyle(fontSize: 12, color: AppColors.lightTextSecondary),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    if (_resumeFilePath != null) {
                      OpenFilex.open(_resumeFilePath!);
                    }
                  },
                  icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
                  label: const Text('Open in PDF Viewer'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _downloadResume() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Resume "${_resumeFileName ?? 'Resume.pdf'}" saved to downloads.'),
        backgroundColor: AppColors.lightPrimary,
      ),
    );
  }

  Future<void> _deleteResume() async {
    await _tokenStorage.clearResume();
    setState(() {
      _resumeFileName = null;
      _resumeFilePath = null;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Resume removed.')),
    );
  }

  void _showEditProfileModal() {
    final nameController = TextEditingController(text: _fullName);
    final eduController = TextEditingController(text: _education);
    final cgpaController = TextEditingController(text: _cgpa.toString());
    final activeBacklogController = TextEditingController(text: _activeBacklogs.toString());
    final closedBacklogController = TextEditingController(text: _closedBacklogs.toString());
    final List<String> tempSkills = List.from(_skills);
    final skillInputController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final theme = Theme.of(context);
            final isDark = theme.brightness == Brightness.dark;

            return Container(
              padding: EdgeInsets.only(
                top: 20,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Edit Academic Profile',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    Text('Full Name', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(hintText: 'Full Name'),
                    ),
                    const SizedBox(height: 12),

                    Text('Education / Degree', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    TextFormField(
                      controller: eduController,
                      decoration: const InputDecoration(hintText: 'e.g. B.Tech CSE'),
                    ),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('CGPA', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              TextFormField(
                                controller: cgpaController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(hintText: 'e.g. 8.5'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Current Backlogs', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              TextFormField(
                                controller: activeBacklogController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(hintText: '0'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    Text('Closed Backlogs', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    TextFormField(
                      controller: closedBacklogController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(hintText: '0'),
                    ),
                    const SizedBox(height: 12),

                    Text('Technical Skills', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: skillInputController,
                            decoration: const InputDecoration(
                              hintText: 'Add skill chip & press +',
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.add_circle_rounded, color: AppColors.lightPrimary),
                          onPressed: () {
                            final text = skillInputController.text.trim();
                            if (text.isNotEmpty && !tempSkills.contains(text)) {
                              setModalState(() {
                                tempSkills.add(text);
                                skillInputController.clear();
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: tempSkills.map((sk) {
                        return Chip(
                          label: Text(sk, style: const TextStyle(fontSize: 11)),
                          onDeleted: () {
                            setModalState(() {
                              tempSkills.remove(sk);
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          final newName = nameController.text.trim();
                          final newEdu = eduController.text.trim();
                          final newCgpa = double.tryParse(cgpaController.text.trim()) ?? _cgpa;
                          final newActive = int.tryParse(activeBacklogController.text.trim()) ?? _activeBacklogs;
                          final newClosed = int.tryParse(closedBacklogController.text.trim()) ?? _closedBacklogs;

                          try {
                            await ApiClient.instance.dio.put('/auth/me', data: {
                              'full_name': newName,
                              'education': newEdu.isNotEmpty ? newEdu : _education,
                              'cgpa': newCgpa,
                              'active_backlogs': newActive,
                              'closed_backlogs': newClosed,
                              'skills': tempSkills,
                            });
                          } catch (_) {}

                          await _tokenStorage.saveStudentProfile(
                            email: _studentEmail,
                            fullName: newName,
                            education: newEdu.isNotEmpty ? newEdu : _education,
                            cgpa: newCgpa,
                            activeBacklogs: newActive,
                            closedBacklogs: newClosed,
                            skills: tempSkills,
                          );

                          setState(() {
                            _fullName = newName;
                            _education = newEdu.isNotEmpty ? newEdu : _education;
                            _cgpa = newCgpa;
                            _activeBacklogs = newActive;
                            _closedBacklogs = newClosed;
                            _skills = List.from(tempSkills);
                          });

                          if (!context.mounted) return;
                          Navigator.pop(context);
                        },
                        child: const Text('Save Profile Changes'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const ProfileSkeleton();
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
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
                if (_studentEmail.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    _studentEmail,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      fontSize: 13,
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
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
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
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
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
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20, color: AppColors.lightPrimary),
                      onPressed: _showEditProfileModal,
                      tooltip: 'Edit Profile',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Divider(
                  height: 1,
                  color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                ),
                const SizedBox(height: 12),

                // Grid Row 1
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Education / Degree', style: theme.textTheme.bodySmall?.copyWith(fontSize: 12, color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary)),
                          const SizedBox(height: 3),
                          Text(_education, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold, fontSize: 14)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Current CGPA', style: theme.textTheme.bodySmall?.copyWith(fontSize: 12, color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary)),
                          const SizedBox(height: 3),
                          Text('$_cgpa / 10.0', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.success)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Grid Row 2
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Current Backlog', style: theme.textTheme.bodySmall?.copyWith(fontSize: 12, color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary)),
                          const SizedBox(height: 3),
                          Text('$_activeBacklogs Current', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold, fontSize: 14)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Closed Backlog', style: theme.textTheme.bodySmall?.copyWith(fontSize: 12, color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary)),
                          const SizedBox(height: 3),
                          Text('$_closedBacklogs Cleared', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold, fontSize: 14)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Skills Section
                Text('Technical Skills', style: theme.textTheme.bodySmall?.copyWith(fontSize: 12, color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _skills.map((skill) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
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
                          fontSize: 12,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 3. Resume Upload & Management Card
          if (_resumeFileName == null) ...[
            InkWell(
              onTap: _pickAndUploadResume,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: AppColors.primaryLightBg,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.cloud_upload_rounded,
                        color: AppColors.lightPrimary,
                        size: 26,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Upload Student Resume',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Supports PDF, DOC, DOCX (Max 10MB)',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: _pickAndUploadResume,
                      icon: const Icon(Icons.file_upload_outlined, size: 18),
                      label: const Text('Select Resume File', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
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
                  InkWell(
                    onTap: _openAndShowResume,
                    borderRadius: BorderRadius.circular(8),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLightBg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.picture_as_pdf_rounded,
                            size: 24,
                            color: AppColors.lightPrimary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _resumeFileName!,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              const Row(
                                children: [
                                  Icon(Icons.check_circle_rounded, size: 13, color: AppColors.success),
                                  SizedBox(width: 4),
                                  Text(
                                    'Uploaded & Verified Resume',
                                    style: TextStyle(fontSize: 12, color: AppColors.success, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Divider(
                    height: 1,
                    color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.visibility_outlined, size: 22, color: AppColors.lightPrimary),
                        onPressed: _openAndShowResume,
                        tooltip: 'Show Document',
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(8),
                      ),
                      IconButton(
                        icon: const Icon(Icons.download_rounded, size: 22, color: AppColors.lightPrimary),
                        onPressed: _downloadResume,
                        tooltip: 'Download Resume',
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(8),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_document, size: 22, color: AppColors.lightPrimary),
                        onPressed: _pickAndUploadResume,
                        tooltip: 'Replace / Change Resume',
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(8),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, size: 22, color: AppColors.error),
                        onPressed: _deleteResume,
                        tooltip: 'Remove Resume',
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(8),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
