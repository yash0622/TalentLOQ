import 'package:flutter/material.dart';
import '../../mock_data/mock_data.dart';
import '../../models/models.dart';
import '../../services/drive_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_avatar.dart';
import 'offer_setup_modal.dart';

class RoundResultScreen extends StatefulWidget {
  final String driveId;
  final Map<String, dynamic> applicantData;
  final VoidCallback? onUpdated;

  const RoundResultScreen({
    super.key,
    required this.driveId,
    required this.applicantData,
    this.onUpdated,
  });

  @override
  State<RoundResultScreen> createState() => _RoundResultScreenState();
}

class _RoundResultScreenState extends State<RoundResultScreen> {
  final DriveService _driveService = DriveService();
  final TextEditingController _messageController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _recordResult(String result) async {
    setState(() => _isSubmitting = true);
    final studentId = (widget.applicantData['student_id'] ?? widget.applicantData['user_id'] ?? widget.applicantData['id'] ?? '').toString();
    final res = await _driveService.updateCandidateRound(
      widget.driveId,
      studentId,
      result,
      customMessage: _messageController.text,
    );
    setState(() => _isSubmitting = false);

    if (mounted) {
      if (res != null) {
        final studentName = (widget.applicantData['name'] ?? widget.applicantData['full_name'] ?? widget.applicantData['student_name'] ?? 'Candidate').toString();
        final customNote = _messageController.text.trim();
        final msgText = customNote.isNotEmpty
            ? '🎉 Congratulations $studentName! You have been selected & advanced to the next round!\nNote: $customNote'
            : '🎉 Congratulations $studentName! You passed the selection round and have been advanced to the next round!';

        // Post Direct Message to Student in Messages Section
        try {
          final convIndex = MockData.conversations.indexWhere(
            (c) => c.id == studentId || c.partnerName.toLowerCase() == studentName.toLowerCase(),
          );
          Conversation conv;
          if (convIndex != -1) {
            conv = MockData.conversations[convIndex];
            conv.lastMessage = msgText;
            conv.time = 'Just Now';
            conv.unreadCount += 1;
          } else {
            conv = Conversation(
              id: studentId.isNotEmpty ? studentId : 'conv-${DateTime.now().millisecondsSinceEpoch}',
              partnerName: studentName,
              partnerRole: 'Student Applicant',
              avatarUrl: '',
              lastMessage: msgText,
              time: 'Just Now',
              unreadCount: 1,
              isOnline: true,
            );
            MockData.conversations.insert(0, conv);
          }

          final chatMsg = ChatMessage(
            id: 'msg-${DateTime.now().millisecondsSinceEpoch}',
            senderId: 'recruiter',
            senderName: 'Placement Officer',
            text: msgText,
            time: 'Just Now',
            isMe: true,
          );

          MockData.conversationMessages.putIfAbsent(conv.id, () => []).add(chatMsg);
        } catch (_) {}

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result == 'pass'
                ? 'Candidate passed! Direct message sent to $studentName in Messages section.'
                : 'Candidate marked failed.'),
            backgroundColor: result == 'pass' ? AppColors.success : AppColors.error,
          ),
        );
        widget.onUpdated?.call();
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update candidate round result.'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final app = widget.applicantData;
    final name = (app['name'] ?? app['full_name'] ?? app['student_name'] ?? 'Candidate Name').toString();
    final cgpa = (app['cgpa'] ?? app['CGPA'] ?? 8.0).toString();
    final course = (app['course'] ?? app['degree'] ?? 'BTECH_CSE').toString();
    final isEligible = app['is_eligible'] ?? app['meets_cgpa_criteria'] ?? true;
    final currentRound = app['current_round'] ?? 0;
    final finalOutcome = (app['final_outcome'] ?? app['status'] ?? 'in_progress').toString().toLowerCase();
    final roundHistory = (app['round_history'] as List?) ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Record Selection Round Result'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Candidate Info Card
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                ),
              ),
              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    AppAvatar(radius: 26, imageUrl: '', fallbackText: name),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 3),
                          Text(
                            '$course • CGPA: $cgpa',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isEligible ? AppColors.successLightBg : AppColors.warning.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isEligible ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                                  size: 13,
                                  color: isEligible ? AppColors.success : AppColors.warning,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isEligible ? 'Meets Drive Eligibility' : 'CGPA Warning',
                                  style: TextStyle(
                                    color: isEligible ? AppColors.success : AppColors.warning,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Selection Progress & Outcome Section
            Text(
              'Current Selection Status',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                ),
              ),
              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.layers_outlined,
                              size: 18,
                              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Completed Rounds',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.darkSurfaceContainerHigh
                                : AppColors.lightSurfaceContainerHigh,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$currentRound',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    Divider(
                      height: 24,
                      color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.flag_outlined,
                              size: 18,
                              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Current Outcome',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: finalOutcome == 'selected'
                                ? AppColors.successLightBg
                                : finalOutcome == 'rejected'
                                    ? AppColors.error.withValues(alpha: 0.15)
                                    : AppColors.primaryLightBg,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            finalOutcome.replaceAll('_', ' ').toUpperCase(),
                            style: TextStyle(
                              color: finalOutcome == 'selected'
                                  ? AppColors.success
                                  : finalOutcome == 'rejected'
                                      ? AppColors.error
                                      : (isDark ? AppColors.darkPrimary : AppColors.lightPrimary),
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Round History Timeline
            if (roundHistory.isNotEmpty) ...[
              Text(
                'Round History Log',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                  ),
                ),
                color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: roundHistory.map<Widget>((rh) {
                      final item = rh as Map;
                      final rNum = item['round_number'] ?? 1;
                      final rName = item['round_name'] ?? 'Round';
                      final rRes = item['result'] ?? 'pending';

                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 12,
                          backgroundColor: rRes == 'pass' ? AppColors.success : AppColors.error,
                          child: Icon(rRes == 'pass' ? Icons.check : Icons.close, size: 12, color: Colors.white),
                        ),
                        title: Text('Round $rNum: $rName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: Text('Result: ${rRes.toString().toUpperCase()}', style: const TextStyle(fontSize: 11)),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Action Buttons
            if (finalOutcome == 'in_progress') ...[
              Text(
                'Evaluate & Record Round Outcome',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _messageController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Direct Note to Applicant (Optional)',
                  hintText: 'e.g. Next technical interview tomorrow at 10 AM in Lab 204.',
                  prefixIcon: const Icon(Icons.mark_email_unread_outlined, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                      width: 1.5,
                    ),
                  ),
                  filled: true,
                  fillColor: isDark ? AppColors.darkSurfaceContainerLow : AppColors.lightSurfaceContainerLow,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 16),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isSubmitting ? null : () => _recordResult('pass'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppColors.success.withValues(alpha: 0.6),
                          disabledForegroundColor: Colors.white70,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: _isSubmitting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.check_circle_rounded, size: 18),
                        label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'Pass & Advance',
                            maxLines: 1,
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isSubmitting ? null : () => _recordResult('fail'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.error,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppColors.error.withValues(alpha: 0.6),
                          disabledForegroundColor: Colors.white70,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: _isSubmitting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.cancel_rounded, size: 18),
                        label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'Mark Failed',
                            maxLines: 1,
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  final studentId = (widget.applicantData['student_id'] ?? widget.applicantData['user_id'] ?? widget.applicantData['id'] ?? '').toString();
                  final studentName = (widget.applicantData['name'] ?? widget.applicantData['full_name'] ?? widget.applicantData['student_name'] ?? 'Candidate').toString();
                  OfferSetupModal.show(
                    context,
                    driveId: widget.driveId,
                    studentId: studentId,
                    candidateName: studentName,
                    companyName: 'Company',
                    roleTitle: (widget.applicantData['role'] ?? widget.applicantData['job_title'] ?? 'Placement Position').toString(),
                    initialOfferData: widget.applicantData['offer_details'] as Map<String, dynamic>?,
                  ).then((val) {
                    if (val == true) {
                      widget.onUpdated?.call();
                    }
                  });
                },
                icon: const Icon(Icons.workspace_premium_rounded, color: AppColors.success, size: 20),
                label: const Text(
                  'Setup / Configure Placement Offer Package',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.success),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.success, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}