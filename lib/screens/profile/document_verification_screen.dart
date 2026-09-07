import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import '../../theme/app_colors.dart';
import '../../widgets/permission_dialogs.dart';
import '../../widgets/skeleton_widgets.dart';
import '../../network/api_client.dart';
import '../../services/token_storage_service.dart';

class DocumentVerificationScreen extends StatefulWidget {
  const DocumentVerificationScreen({super.key});

  @override
  State<DocumentVerificationScreen> createState() => _DocumentVerificationScreenState();
}

class _DocumentVerificationScreenState extends State<DocumentVerificationScreen> {
  final TokenStorageService _tokenStorage = TokenStorageService();
  bool _isLoading = true;
  String? _processingSlot; // Target slot currently uploading/processing

  Map<String, dynamic> _verificationState = {};
  List<dynamic> _userDocuments = [];

  @override
  void initState() {
    super.initState();
    _fetchVerificationData(showFullSpinner: true);
  }

  Future<void> _fetchVerificationData({bool showFullSpinner = false}) async {
    if (showFullSpinner) {
      setState(() => _isLoading = true);
    }
    try {
      final stateRes = await ApiClient.instance.dio.get('/documents/profile/verification-state');
      final docsRes = await ApiClient.instance.dio.get('/documents');

      try {
        final meRes = await ApiClient.instance.dio.get('/auth/me');
        if (meRes.statusCode == 200 && meRes.data is Map) {
          final p = Map<String, dynamic>.from(meRes.data as Map);
          await _tokenStorage.saveStudentProfile(
            email: p['email'] ?? '',
            fullName: p['full_name'] ?? '',
            education: p['education'] ?? '',
            cgpa: (p['cgpa'] is num) ? (p['cgpa'] as num).toDouble() : 0.0,
            activeBacklogs: (p['active_backlogs'] is num) ? (p['active_backlogs'] as num).toInt() : 0,
            closedBacklogs: (p['closed_backlogs'] is num) ? (p['closed_backlogs'] as num).toInt() : 0,
            skills: (p['skills'] is List) ? List<String>.from(p['skills']) : [],
          );
        }
      } catch (e) {
        debugPrint('Profile sync note: $e');
      }

      if (mounted) {
        setState(() {
          if (stateRes.statusCode == 200 && stateRes.data is Map) {
            _verificationState = Map<String, dynamic>.from(stateRes.data as Map);
          }
          if (docsRes.statusCode == 200 && docsRes.data is Map && docsRes.data['documents'] is List) {
            _userDocuments = List<dynamic>.from(docsRes.data['documents'] as List);
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading verification data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickAndUploadDocument(String targetType, String slotTitle) async {
    final hasPermission = await PermissionDialogs.requestDocumentAccessPermission(
      context,
      documentTitle: slotTitle,
      fileTypesDesc: 'PDF, PNG, JPG, JPEG (Max 10MB)',
    );
    if (!hasPermission) return;

    bool isDialogShowing = false;
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
      );

      if (result.isEmpty) return;

      final file = result.first;
      final path = file.path;
      final name = file.name;

      if (path == null || path.isEmpty) return;

      setState(() => _processingSlot = targetType);

      if (!mounted) return;
      // Show AI Scanning Loading Screen
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          isDialogShowing = true;
          return PopScope(
            canPop: false,
            child: Center(
              child: Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                elevation: 8,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 26),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 48,
                        height: 48,
                        child: CircularProgressIndicator(
                          strokeWidth: 3.5,
                          color: AppColors.lightPrimary,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'AI Scanning...',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );

      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(path, filename: name),
        'target_type': targetType,
      });

      final response = await ApiClient.instance.dio.post(
        '/documents/upload',
        data: formData,
        options: Options(
          sendTimeout: const Duration(seconds: 90),
          receiveTimeout: const Duration(seconds: 90),
        ),
      );

      if (response.statusCode == 200) {
        final resData = response.data as Map<String, dynamic>? ?? {};
        final status = resData['status'] as String? ?? 'VERIFIED';
        final overallConf = resData['overall_confidence'] ?? 95.0;

        if (targetType == 'RESUME') {
          await _tokenStorage.saveResume(fileName: name, filePath: path);
        }

        await _fetchVerificationData(showFullSpinner: false);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status == 'VERIFIED'
                  ? '✓ $slotTitle verified successfully ($overallConf% confidence)!'
                  : 'Document submitted: Status is $status.',
            ),
            backgroundColor: status == 'VERIFIED' ? AppColors.success : AppColors.warning,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } on DioException catch (e) {
      if (!mounted) return;
      if (e.type == DioExceptionType.receiveTimeout || e.type == DioExceptionType.connectionTimeout) {
        // Backend often finishes right around the timeout; refresh to catch the processed state
        await _fetchVerificationData();
        return;
      }
      String errorMsg = 'Verification failed. Please ensure document is clear and matches requested slot.';
      if (e.response?.data is Map && (e.response!.data as Map).containsKey('detail')) {
        errorMsg = e.response!.data['detail'].toString();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✕ $errorMsg'),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e'), backgroundColor: AppColors.error),
      );
    } finally {
      if (isDialogShowing && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (mounted) setState(() => _processingSlot = null);
    }
  }

  Map<String, dynamic>? _findDocForType(String docTypeKey) {
    if (_userDocuments.isEmpty) return null;
    for (final doc in _userDocuments) {
      final t = doc['document_type']?.toString().toUpperCase() ?? '';
      final target = doc['target_type']?.toString().toUpperCase() ?? '';

      // Priority 1: Explicit target slot where user uploaded
      if (target.isNotEmpty) {
        if (docTypeKey == 'RESUME' && target == 'RESUME') return doc;
        if (docTypeKey == 'TENTH' && target == 'TENTH_MARKSHEET') return doc;
        if (docTypeKey == 'TWELFTH_OR_DIPLOMA' && target == 'TWELFTH_OR_DIPLOMA') return doc;
        if (docTypeKey == 'UG_MARKSHEET' && target == 'UG_MARKSHEET') return doc;
      } else {
        // Priority 2: Detected document type fallback if target is absent
        if (docTypeKey == 'RESUME' && t == 'RESUME') return doc;
        if (docTypeKey == 'TENTH' && t == 'TENTH_MARKSHEET') return doc;
        if (docTypeKey == 'TWELFTH_OR_DIPLOMA' && (t == 'TWELFTH_MARKSHEET' || t == 'DIPLOMA_MARKSHEET')) return doc;
        if (docTypeKey == 'UG_MARKSHEET' && t == 'UG_MARKSHEET') return doc;
      }
    }
    return null;
  }

  Future<void> _confirmAndRemoveDocument(
    Map<String, dynamic>? docRecord,
    String targetType,
    String title,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Remove $title?',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: const Text(
          'This will permanently delete this verified document from the system and database. '
          'Associated verified parameters will be cleared. Do you wish to continue?',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _processingSlot = targetType;
    });

    try {
      final docId = docRecord?['document_id']?.toString() ?? targetType;
      await ApiClient.instance.dio.delete(
        '/documents/$docId',
        queryParameters: {'target_type': targetType},
      );

      if (targetType == 'RESUME') {
        try {
          await ApiClient.instance.dio.delete('/auth/resume');
        } catch (_) {}
        await _tokenStorage.clearResume();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ $title removed from database successfully.'),
            backgroundColor: AppColors.success,
          ),
        );
      }

      await _fetchVerificationData(showFullSpinner: false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to remove document: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _processingSlot = null;
        });
      }
    }
  }

  Future<void> _showDocumentDetails(
    Map<String, dynamic>? docRecord,
    String title,
    String targetType,
  ) async {
    if (docRecord == null) return;
    final filename = docRecord['filename']?.toString() ?? 'Document';
    final fileUrl = docRecord['file_url']?.toString();
    final gridFileId = docRecord['grid_file_id']?.toString();
    final isImage = filename.toLowerCase().endsWith('.jpg') ||
        filename.toLowerCase().endsWith('.jpeg') ||
        filename.toLowerCase().endsWith('.png') ||
        filename.toLowerCase().endsWith('.webp');

    // Show loading spinner dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: Card(
          elevation: 4,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                SizedBox(width: 16),
                Text(
                  'Loading document...',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    Uint8List? fileBytes;
    try {
      String downloadPath = fileUrl ?? '';
      if (downloadPath.isEmpty && gridFileId != null) {
        downloadPath = '/api/v1/files/$gridFileId';
      }
      if (downloadPath.isNotEmpty) {
        final response = await ApiClient.instance.dio.get<List<int>>(
          downloadPath,
          options: Options(responseType: ResponseType.bytes),
        );
        if (response.statusCode == 200 && response.data != null) {
          fileBytes = Uint8List.fromList(response.data!);
        }
      }
    } catch (e) {
      debugPrint('Error downloading document file: $e');
    }

    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    if (fileBytes == null || fileBytes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not load document file "$filename" from server.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    // Write to temporary local file
    final tempDir = Directory.systemTemp;
    final tempFile = File('${tempDir.path}/$filename');
    await tempFile.writeAsBytes(fileBytes);

    if (!mounted) return;

    if (isImage) {
      // Fullscreen interactive pinch-to-zoom image viewer for marksheets
      showDialog(
        context: context,
        builder: (ctx) => Dialog.fullscreen(
          child: Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              title: Text(filename, style: const TextStyle(fontSize: 14)),
              actions: [
                IconButton(
                  icon: const Icon(Icons.open_in_new_rounded),
                  tooltip: 'Open in Gallery',
                  onPressed: () async {
                    final allow = await PermissionDialogs.requestExternalViewerPermission(
                      context,
                      filename: filename,
                      viewerType: 'Gallery / Photos',
                    );
                    if (allow) {
                      OpenFilex.open(tempFile.path);
                    }
                  },
                ),
              ],
            ),
            body: Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 5.0,
                child: Image.memory(
                  fileBytes!,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      // PDF or other document: ask permission before opening with external viewer app
      final allow = await PermissionDialogs.requestExternalViewerPermission(
        context,
        filename: filename,
        viewerType: 'PDF Document Reader',
      );
      if (!allow) return;

      final result = await OpenFilex.open(tempFile.path);
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Document opened at: ${tempFile.path} (${result.message})'),
            backgroundColor: AppColors.lightPrimary,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: AppBar(
        title: const Text('Document Verification', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        elevation: 0,
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _fetchVerificationData(showFullSpinner: false),
            tooltip: 'Refresh Status',
          ),
        ],
      ),
      body: _isLoading
          ? const DocumentVerificationSkeleton()
          : RefreshIndicator(
              onRefresh: () => _fetchVerificationData(showFullSpinner: false),
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                children: [
                  // Section Title
                  Row(
                    children: [
                      const Icon(Icons.folder_shared_outlined, size: 20, color: AppColors.lightPrimary),
                      const SizedBox(width: 8),
                      Text(
                        'Required Academic Documents',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Slot 1: Resume / CV
                  _buildDocumentSlotCard(
                    isDark: isDark,
                    slotKey: 'RESUME',
                    targetType: 'RESUME',
                    title: 'Student Resume / CV',
                    subtitle: 'Extracts & syncs verified Technical Skills and Languages',
                    icon: Icons.description_rounded,
                    docRecord: _findDocForType('RESUME'),
                    badgePreview: _getResumeBadgePreview(_findDocForType('RESUME')),
                  ),
                  const SizedBox(height: 10),

                  // Slot 2: 10th Marksheet
                  _buildDocumentSlotCard(
                    isDark: isDark,
                    slotKey: 'TENTH',
                    targetType: 'TENTH_MARKSHEET',
                    title: 'Class 10th Marksheet',
                    subtitle: 'Extracts 10th Percentage, Board, and Year of Passing',
                    icon: Icons.workspace_premium_rounded,
                    docRecord: _findDocForType('TENTH'),
                    badgePreview: _getTenthBadgePreview(_findDocForType('TENTH')),
                  ),
                  const SizedBox(height: 10),

                  // Slot 3: 12th / Diploma Marksheet
                  _buildDocumentSlotCard(
                    isDark: isDark,
                    slotKey: 'TWELFTH_OR_DIPLOMA',
                    targetType: 'TWELFTH_OR_DIPLOMA',
                    title: 'Class 12th or Diploma Marksheet',
                    subtitle: 'Auto-detects 12th % or Diploma CGPA (No blind conversions)',
                    icon: Icons.school_rounded,
                    docRecord: _findDocForType('TWELFTH_OR_DIPLOMA'),
                    badgePreview: _getTwelfthDiplomaBadgePreview(_findDocForType('TWELFTH_OR_DIPLOMA')),
                  ),
                  const SizedBox(height: 10),

                  // Slot 4: Current UG Marksheet
                  _buildDocumentSlotCard(
                    isDark: isDark,
                    slotKey: 'UG_MARKSHEET',
                    targetType: 'UG_MARKSHEET',
                    title: 'Current UG Marksheet',
                    subtitle: 'Verifies University, Enrollment No, SGPA, CGPA & Backlogs',
                    icon: Icons.analytics_rounded,
                    docRecord: _findDocForType('UG_MARKSHEET'),
                    badgePreview: _getUGBadgePreview(_findDocForType('UG_MARKSHEET')),
                  ),
                  const SizedBox(height: 16),

                  // Security & Authenticity Policy Card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurfaceContainerLow : AppColors.lightSurfaceContainer,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                      ),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.lock_outline_rounded, size: 18, color: AppColors.lightPrimary),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Strict Integrity Notice: Academic parameters (CGPA, backlogs, skills, percentages) are tamper-resistant and read-only. Updates occur exclusively via verified document uploads.',
                            style: TextStyle(fontSize: 12, height: 1.4, color: AppColors.lightTextSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildDocumentSlotCard({
    required bool isDark,
    required String slotKey,
    required String targetType,
    required String title,
    required String subtitle,
    required IconData icon,
    required Map<String, dynamic>? docRecord,
    required List<Widget> badgePreview,
  }) {
    final isProcessing = _processingSlot == targetType;
    final status = docRecord?['processing_status']?.toString().toUpperCase() ?? 'NOT_UPLOADED';
    final filename = docRecord?['filename']?.toString();
    final confidence = (docRecord?['validation_confidence'] as num?)?.toDouble() ??
        (docRecord?['overall_confidence'] as num?)?.toDouble() ??
        95.0;

    Color statusColor;
    String statusLabel;
    IconData? statusIcon;

    switch (status) {
      case 'VERIFIED':
        statusColor = AppColors.success;
        statusLabel = 'Verified (${confidence.toInt()}%)';
        statusIcon = Icons.check_circle_rounded;
        break;
      case 'REVIEW_REQUIRED':
        statusColor = AppColors.warning;
        statusLabel = 'Review Required';
        statusIcon = Icons.warning_amber_rounded;
        break;
      case 'MANUAL_REVIEW':
        statusColor = Colors.deepOrange;
        statusLabel = 'Manual Review';
        statusIcon = Icons.schedule_rounded;
        break;
      case 'FAILED':
        statusColor = AppColors.error;
        statusLabel = 'Verification Failed';
        statusIcon = Icons.error_outline_rounded;
        break;
      default:
        statusColor = isDark ? Colors.white54 : Colors.grey.shade600;
        statusLabel = '';
        statusIcon = null;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: status == 'VERIFIED'
              ? AppColors.success.withValues(alpha: 0.4)
              : (isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant),
          width: status == 'VERIFIED' ? 1.4 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 1. Compact Category Icon
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: status == 'VERIFIED'
                      ? AppColors.success.withValues(alpha: 0.12)
                      : AppColors.primaryLightBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: status == 'VERIFIED' ? AppColors.success : AppColors.lightPrimary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),

              // 2. Title (with optional warning pill for non-verified states)
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (status != 'NOT_UPLOADED' && status != 'VERIFIED' && statusLabel.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      // Status Pill for issues only
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (statusIcon != null) ...[
                              Icon(statusIcon, size: 9, color: statusColor),
                              const SizedBox(width: 3),
                            ],
                            Text(
                              statusLabel,
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 9.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // 3. Upload Icon Only Button
              if (isProcessing)
                const SizedBox(
                  width: 38,
                  height: 38,
                  child: Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (status == 'NOT_UPLOADED')
                IconButton(
                  onPressed: () => _pickAndUploadDocument(targetType, title),
                  icon: const Icon(Icons.cloud_upload_outlined, size: 22, color: AppColors.lightPrimary),
                  tooltip: 'Upload Document',
                  constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                  padding: const EdgeInsets.all(7),
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.primaryLightBg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
            ],
          ),

          // If Document is Uploaded, show only the name of the document uploaded
          if (status != 'NOT_UPLOADED' && docRecord != null && filename != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.attach_file_rounded, size: 13, color: AppColors.lightPrimary),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    filename,
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],

          // If Document is in Review Required or Failed state, show an explanatory banner (Section 11 Spec)
          if (status == 'REVIEW_REQUIRED' || status == 'MANUAL_REVIEW' || status == 'FAILED') ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: status == 'FAILED'
                    ? AppColors.error.withValues(alpha: 0.08)
                    : AppColors.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: (status == 'FAILED' ? AppColors.error : AppColors.warning).withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    status == 'FAILED' ? Icons.error_outline_rounded : Icons.info_outline_rounded,
                    size: 15,
                    color: status == 'FAILED' ? AppColors.error : AppColors.warning,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      () {
                        final valErrors = docRecord?['validation_errors'] as List?;
                        if (valErrors != null && valErrors.isNotEmpty) {
                          return valErrors.join('\n');
                        }
                        final warnings = docRecord?['warnings'] as List?;
                        if (warnings != null && warnings.isNotEmpty) {
                          return warnings.join('\n');
                        }
                        final reasons = docRecord?['reasons'] as List?;
                        if (reasons != null && reasons.isNotEmpty) {
                          return reasons.join('\n');
                        }
                        final extConf = docRecord?['extraction_confidence'];
                        if (extConf != null && (extConf as num) < 40.0) {
                          return 'Low parameter extraction confidence ($extConf%): Key fields (Board/College, Passing Year) were ambiguous or unreadable.';
                        }
                        final valConf = docRecord?['validation_confidence'];
                        if (valConf != null && (valConf as num) < 70.0) {
                          return 'Validation confidence was low ($valConf%). Requires manual coordinator verification.';
                        }
                        if (status == 'FAILED') {
                          return 'Document could not be verified automatically. Please replace with a clear scan.';
                        }
                        return 'Manual coordinator review required for this document. You can submit a dispute or replace the file.';
                      }(),
                      style: TextStyle(
                        fontSize: 11,
                        color: status == 'FAILED'
                            ? AppColors.error
                            : (isDark ? Colors.amber.shade200 : Colors.amber.shade900),
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Dedicated Action Bar: Show, Change, Dispute, Remove (Guaranteed Zero Overflow)
          if (status != 'NOT_UPLOADED') ...[
            const SizedBox(height: 8),
            Divider(
              height: 1,
              color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  // 1. Show Document
                  InkWell(
                    onTap: () => _showDocumentDetails(docRecord, title, targetType),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLightBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.visibility_outlined, size: 14, color: AppColors.lightPrimary),
                          SizedBox(width: 4),
                          Text(
                            'Show',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: AppColors.lightPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 2. Change Document
                  InkWell(
                    onTap: () => _pickAndUploadDocument(targetType, title),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.sync_rounded, size: 14, color: AppColors.success),
                          SizedBox(width: 4),
                          Text(
                            'Change',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: AppColors.success,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 3. Dispute Action (for Review Required or Manual Review)
                  if (status == 'REVIEW_REQUIRED' || status == 'MANUAL_REVIEW')
                    InkWell(
                      onTap: () => _showSlotDisputeDialog(targetType, title),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.flag_outlined, size: 14, color: AppColors.warning),
                            SizedBox(width: 4),
                            Text(
                              'Dispute',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: AppColors.warning,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // 4. Remove Document
                  InkWell(
                    onTap: () => _confirmAndRemoveDocument(docRecord, targetType, title),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.delete_outline_rounded, size: 14, color: AppColors.error),
                          SizedBox(width: 4),
                          Text(
                            'Remove',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: AppColors.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showSlotDisputeDialog(String targetType, String title) {
    String fieldKey = 'CGPA';
    if (targetType == 'TENTH_MARKSHEET') {
      fieldKey = 'tenth_percentage';
    } else if (targetType == 'TWELFTH_MARKSHEET') {
      fieldKey = 'twelfth_percentage';
    } else if (targetType == 'DIPLOMA_CERTIFICATE') {
      fieldKey = 'diploma_cgpa';
    } else if (targetType == 'RESUME') {
      fieldKey = 'skills';
    }

    final reasonController = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (dCtx) {
        return AlertDialog(
          backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.flag_rounded, color: AppColors.warning, size: 22),
              const SizedBox(width: 8),
              Text('Flag $title', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Submit an issue or correction request for this document. Placement team administrators will review the original file.',
                style: TextStyle(fontSize: 12, color: AppColors.lightTextSecondary),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: reasonController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Dispute / Correction Details',
                  hintText: 'e.g. My marksheet shows 85.4% but OCR read 65.4%',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
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
                  await ApiClient.instance.dio.post(
                    '/documents/profile/verified-data/$fieldKey/flag',
                    data: {'reason': reasonController.text.trim()},
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('✓ $title flagged for manual coordinator review.'),
                        backgroundColor: AppColors.success,
                      ),
                    );
                    _fetchVerificationData(showFullSpinner: false);
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to flag: $e'),
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
              child: const Text('Submit Request', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _getResumeBadgePreview([Map<String, dynamic>? docRecord]) {
    if (docRecord == null) return [];
    final verified = _verificationState['document_verified_fields'] as Map<String, dynamic>?;
    final extracted = docRecord['extracted_data'] as Map<String, dynamic>?;

    final skills = verified?['skills']?['value'] as List? ?? (extracted?['skills'] as List?);
    final codingLangs = verified?['coding_languages']?['value'] as List? ?? (extracted?['coding_languages'] as List?) ?? (extracted?['programming_languages'] as List?);
    final spokenLangs = verified?['spoken_languages']?['value'] as List? ?? (extracted?['spoken_languages'] as List?) ?? verified?['languages']?['value'] as List? ?? (extracted?['languages'] as List?);

    // Count available profile links
    final socialLinks = extracted?['social_links'] as Map<String, dynamic>?;
    int linkCount = 0;
    for (final plat in ['linkedin', 'github', 'leetcode', 'hackerrank', 'codeforces', 'kaggle', 'geeksforgeeks', 'twitter']) {
      if (verified?['${plat}_url']?['value'] != null || extracted?['${plat}_url'] != null || (socialLinks != null && socialLinks[plat] != null)) {
        linkCount++;
      }
    }

    List<Widget> chips = [];
    if (skills != null && skills.isNotEmpty) {
      chips.add(_buildDataChip('Skills: ${skills.length}', Icons.psychology_rounded));
    }
    if (codingLangs != null && codingLangs.isNotEmpty) {
      chips.add(_buildDataChip('Coding: ${codingLangs.length}', Icons.code_rounded));
    }
    if (spokenLangs != null && spokenLangs.isNotEmpty) {
      chips.add(_buildDataChip('Spoken: ${spokenLangs.length}', Icons.translate_rounded));
    }
    if (linkCount > 0) {
      chips.add(_buildDataChip('Profiles: $linkCount', Icons.link_rounded));
    }
    return chips;
  }

  List<Widget> _getTenthBadgePreview([Map<String, dynamic>? docRecord]) {
    if (docRecord == null) return [];
    final verified = _verificationState['document_verified_fields'] as Map<String, dynamic>?;
    final extracted = docRecord['extracted_data'] as Map<String, dynamic>?;

    final pct = verified?['tenth_percentage']?['value'] ?? extracted?['tenth_percentage'];
    final tenthCgpa = verified?['tenth_cgpa']?['value'] ?? extracted?['tenth_cgpa'];
    final year = verified?['tenth_passing_year']?['value'] ?? extracted?['passing_year'];
    final board = verified?['tenth_board']?['value'] ?? extracted?['board'];

    List<Widget> chips = [];
    if (pct != null) {
      chips.add(_buildDataChip('Class 10: $pct%${tenthCgpa != null ? ' ($tenthCgpa CGPA)' : ''}', Icons.percent_rounded));
    } else if (tenthCgpa != null) {
      chips.add(_buildDataChip('Class 10: $tenthCgpa CGPA', Icons.grade_rounded));
    }
    if (year != null) {
      chips.add(_buildDataChip('Year: $year', Icons.calendar_today_rounded));
    }
    if (board != null && board.toString().isNotEmpty) {
      final bStr = board.toString().toUpperCase();
      final shortBoard = bStr.contains('GSEB')
          ? 'GSEB'
          : (bStr.contains('CBSE')
              ? 'CBSE'
              : (bStr.contains('ICSE') ? 'ICSE' : 'State Board'));
      chips.add(_buildDataChip(shortBoard, Icons.account_balance_rounded));
    }
    return chips;
  }

  List<Widget> _getTwelfthDiplomaBadgePreview([Map<String, dynamic>? docRecord]) {
    if (docRecord == null) return [];
    final verified = _verificationState['document_verified_fields'] as Map<String, dynamic>?;
    final extracted = docRecord['extracted_data'] as Map<String, dynamic>?;

    final pct12 = verified?['twelfth_percentage']?['value'] ?? extracted?['percentage'] ?? extracted?['twelfth_percentage'];
    final dipCgpa = verified?['diploma_cgpa']?['value'] ?? extracted?['diploma_cgpa'] ?? extracted?['cgpa'];

    List<Widget> chips = [];
    if (pct12 != null) {
      chips.add(_buildDataChip('Class 12: $pct12%', Icons.percent_rounded));
    }
    if (dipCgpa != null) {
      chips.add(_buildDataChip('Diploma CGPA: $dipCgpa / 10.0', Icons.analytics_outlined));
    }
    return chips;
  }

  List<Widget> _getUGBadgePreview([Map<String, dynamic>? docRecord]) {
    if (docRecord == null) return [];
    final verified = _verificationState['document_verified_fields'] as Map<String, dynamic>?;
    final extracted = docRecord['extracted_data'] as Map<String, dynamic>?;

    final effectiveCgpa = verified?['CGPA']?['value'] ?? extracted?['cgpa'] ?? extracted?['CGPA'] ?? verified?['sgpa']?['value'] ?? extracted?['sgpa'];
    final rawSgpa = verified?['sgpa']?['value'] ?? extracted?['sgpa'];
    final backlogs = verified?['active_backlogs']?['value'] ?? extracted?['active_backlogs'];
    final enroll = verified?['enrollment_number']?['value'] ?? extracted?['enrollment_number'];
    final sem = verified?['current_semester']?['value'] ?? extracted?['current_semester'];

    List<Widget> chips = [];
    if (effectiveCgpa != null && (effectiveCgpa as num) > 0) {
      chips.add(_buildDataChip('CGPA: $effectiveCgpa / 10.0', Icons.grade_rounded));
    }
    if (rawSgpa != null && (rawSgpa as num) > 0 && rawSgpa != effectiveCgpa) {
      chips.add(_buildDataChip('SGPA: $rawSgpa', Icons.auto_graph_rounded));
    }
    if (backlogs != null) {
      final bNum = backlogs is num ? backlogs.toInt() : int.tryParse(backlogs.toString()) ?? 0;
      chips.add(_buildDataChip(
        bNum == 0 ? 'No Backlogs' : 'Backlogs: $bNum',
        bNum == 0 ? Icons.check_circle_outline_rounded : Icons.warning_amber_rounded,
      ));
    }
    if (sem != null) {
      chips.add(_buildDataChip('Sem: $sem', Icons.calendar_today_rounded));
    }
    if (enroll != null) {
      chips.add(_buildDataChip('Enroll: $enroll', Icons.badge_outlined));
    }
    return chips;
  }

  Widget _buildDataChip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primaryLightBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.lightPrimary),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.lightPrimary)),
        ],
      ),
    );
  }
}