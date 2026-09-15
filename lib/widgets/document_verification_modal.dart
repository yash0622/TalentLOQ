import 'package:flutter/material.dart';
import '../services/recruiter_service.dart';
import '../theme/app_colors.dart';
import '../utils/document_viewer_helper.dart';

class DocumentVerificationModal extends StatefulWidget {
  final String documentId;
  final String documentTitle;
  final String? studentName;
  final String? studentId;
  final String? filename;
  final String? fileUrl;
  final Map<String, dynamic>? initialData;

  const DocumentVerificationModal({
    super.key,
    required this.documentId,
    required this.documentTitle,
    this.studentName,
    this.studentId,
    this.filename,
    this.fileUrl,
    this.initialData,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String documentId,
    required String documentTitle,
    String? studentName,
    String? studentId,
    String? filename,
    String? fileUrl,
    Map<String, dynamic>? initialData,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DocumentVerificationModal(
        documentId: documentId,
        documentTitle: documentTitle,
        studentName: studentName,
        studentId: studentId,
        filename: filename,
        fileUrl: fileUrl,
        initialData: initialData,
      ),
    );
  }

  @override
  State<DocumentVerificationModal> createState() => _DocumentVerificationModalState();
}

class _DocumentVerificationModalState extends State<DocumentVerificationModal> {
  final RecruiterService _recruiterService = RecruiterService();

  bool _isExtracting = false;
  bool _isSubmitting = false;
  String? _statusMessage;

  // Editable Form Controllers
  final TextEditingController _cgpaController = TextEditingController();
  final TextEditingController _backlogsController = TextEditingController();
  final TextEditingController _percentageController = TextEditingController();
  final TextEditingController _boardController = TextEditingController();
  final TextEditingController _yearController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  Map<String, dynamic> _extractedData = {};

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _populateFromData(widget.initialData!);
    }
  }

  void _populateFromData(Map<String, dynamic> data) {
    setState(() {
      _extractedData = Map<String, dynamic>.from(data);

      if (data['cgpa'] != null || data['effective_cgpa'] != null || data['total_cgpa'] != null) {
        final val = data['cgpa'] ?? data['effective_cgpa'] ?? data['total_cgpa'];
        _cgpaController.text = val.toString();
      }

      if (data['active_backlogs'] != null || data['current_backlogs'] != null) {
        final val = data['active_backlogs'] ?? data['current_backlogs'];
        _backlogsController.text = val.toString();
      }

      if (data['percentage'] != null || data['tenth_percentage'] != null || data['twelfth_percentage'] != null) {
        final val = data['percentage'] ?? data['tenth_percentage'] ?? data['twelfth_percentage'];
        _percentageController.text = val.toString();
      }

      if (data['board'] != null || data['board_or_college'] != null || data['university'] != null) {
        final val = data['board'] ?? data['board_or_college'] ?? data['university'];
        _boardController.text = val.toString();
      }

      if (data['passing_year'] != null) {
        _yearController.text = data['passing_year'].toString();
      }
    });
  }

  @override
  void dispose() {
    _cgpaController.dispose();
    _backlogsController.dispose();
    _percentageController.dispose();
    _boardController.dispose();
    _yearController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _viewDocument() async {
    await DocumentViewerHelper.viewDocument(
      context,
      fileUrl: widget.fileUrl,
      docTitle: widget.documentTitle,
      filename: widget.filename,
    );
  }

  Future<void> _runAIExtraction() async {
    setState(() {
      _isExtracting = true;
      _statusMessage = 'Running Gemini Multimodal Vision extraction...';
    });

    try {
      final res = await _recruiterService.aiExtractDocument(widget.documentId);
      if (mounted) {
        if (res != null && res['extracted_fields'] is Map) {
          final fields = Map<String, dynamic>.from(res['extracted_fields'] as Map);
          _populateFromData(fields);
          setState(() {
            _isExtracting = false;
            _statusMessage = 'AI extraction completed! Review and edit values below.';
          });
        } else {
          setState(() {
            _isExtracting = false;
            _statusMessage = 'AI Vision could not extract fields reliably. Enter manually.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isExtracting = false;
          _statusMessage = 'AI Vision error: $e';
        });
      }
    }
  }

  Future<void> _approveAndSync() async {
    setState(() => _isSubmitting = true);

    // Build confirmed fields
    final confirmed = Map<String, dynamic>.from(_extractedData);

    if (_cgpaController.text.trim().isNotEmpty) {
      confirmed['cgpa'] = double.tryParse(_cgpaController.text.trim()) ?? 0.0;
    }
    if (_backlogsController.text.trim().isNotEmpty) {
      confirmed['active_backlogs'] = int.tryParse(_backlogsController.text.trim()) ?? 0;
    }
    if (_percentageController.text.trim().isNotEmpty) {
      final p = double.tryParse(_percentageController.text.trim());
      confirmed['percentage'] = p;
      confirmed['tenth_percentage'] = p;
      confirmed['twelfth_percentage'] = p;
    }
    if (_boardController.text.trim().isNotEmpty) {
      confirmed['board'] = _boardController.text.trim();
    }
    if (_yearController.text.trim().isNotEmpty) {
      confirmed['passing_year'] = int.tryParse(_yearController.text.trim());
    }

    final success = await _recruiterService.approveDocument(
      widget.documentId,
      confirmed,
      notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
    );

    if (mounted) {
      setState(() => _isSubmitting = false);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Document verified and student profile updated successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.of(context).pop(true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to approve document. Check network / permissions.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _rejectDocument() async {
    final reasonController = TextEditingController();
    final shouldReject = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Document'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the reason for rejecting this document (visible to student):',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                hintText: 'e.g. Blurry photo, please re-upload clear marksheet PDF',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            onPressed: () {
              if (reasonController.text.trim().isNotEmpty) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Confirm Reject'),
          ),
        ],
      ),
    );

    if (shouldReject == true && mounted) {
      setState(() => _isSubmitting = true);
      final success = await _recruiterService.rejectDocument(widget.documentId, reasonController.text.trim());
      if (mounted) {
        setState(() => _isSubmitting = false);
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Document rejected and candidate notified.')),
          );
          Navigator.of(context).pop(true);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Title & Badges
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.rate_review_rounded, color: AppColors.warning, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.documentTitle,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      if (widget.studentName != null)
                        Text(
                          'Candidate: ${widget.studentName}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Document Details Card
            Card(
              elevation: 0,
              color: isDark ? AppColors.darkSurfaceContainerHigh : AppColors.lightSurfaceContainer,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.attach_file_rounded, size: 20, color: AppColors.lightPrimary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.filename ?? 'Uploaded Document',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _viewDocument,
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: const Text('View File', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Run AI Vision Extraction Button (Recruiter LLM Key)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isExtracting ? null : _runAIExtraction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.lightPrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: _isExtracting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome_rounded, size: 18),
                label: Text(
                  _isExtracting ? 'Extracting via Gemini Vision...' : '✨ Run AI Vision Extraction (Recruiter API)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),

            if (_statusMessage != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.lightPrimary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _statusMessage!,
                  style: const TextStyle(fontSize: 12, color: AppColors.lightPrimary, fontWeight: FontWeight.w500),
                ),
              ),
            ],

            const SizedBox(height: 16),
            const Text(
              'Verified Fields to Sync to Profile:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 10),

            // Form Inputs for Verification
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _cgpaController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'CGPA (e.g. 8.45)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _backlogsController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Active Backlogs',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _percentageController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Percentage (%)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _yearController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Passing Year',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            TextField(
              controller: _boardController,
              decoration: const InputDecoration(
                labelText: 'Board / University / College',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),

            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Reviewer Notes (Optional)',
                hintText: 'e.g. Verified against official university seal',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 20),

            // Action Buttons (Approve / Reject)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isSubmitting ? null : _rejectDocument,
                    icon: const Icon(Icons.cancel_outlined, color: AppColors.error, size: 18),
                    label: const Text('Reject', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.error),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _isSubmitting ? null : _approveAndSync,
                    icon: _isSubmitting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.check_circle_rounded, size: 18),
                    label: Text(
                      _isSubmitting ? 'Syncing...' : 'Approve & Sync Profile',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
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
    );
  }
}