import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/drive_service.dart';
import '../../theme/app_colors.dart';
import '../recruiter/offer_setup_modal.dart';

class OfferDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> drive;
  final Map<String, dynamic> status;
  final Map<String, dynamic> offerDetails;
  final String studentId;
  final String candidateName;
  final bool isRecruiter;
  final VoidCallback? onOfferActionCompleted;

  const OfferDetailsScreen({
    super.key,
    required this.drive,
    required this.status,
    this.offerDetails = const {},
    this.studentId = '',
    this.candidateName = 'Candidate',
    this.isRecruiter = false,
    this.onOfferActionCompleted,
  });

  @override
  State<OfferDetailsScreen> createState() => _OfferDetailsScreenState();
}

class _OfferDetailsScreenState extends State<OfferDetailsScreen> {
  final DriveService _driveService = DriveService();
  late Map<String, dynamic> _currentOffer;
  late String _currentOutcome;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _currentOffer = Map<String, dynamic>.from(widget.offerDetails);
    _currentOutcome = (widget.status['final_outcome'] ?? 'selected').toString().toLowerCase();
  }

  String get _driveId => (widget.drive['drive_id'] ?? widget.drive['listing_id'] ?? '').toString();
  String get _companyName => (widget.drive['company_name'] ?? 'Company').toString();
  String get _roleTitle => (_currentOffer['role_title'] ?? widget.drive['drive_title'] ?? widget.drive['interview_job'] ?? 'Placement Position').toString();

  String _formatIndianCurrency(dynamic value, {bool showLakhSuffixIfSmall = false}) {
    if (value == null) return '₹0';
    final str = value.toString().replaceAll('₹', '').replaceAll(',', '').trim();
    if (str.isEmpty) return '₹0';

    final numVal = double.tryParse(str);
    if (numVal == null) return str.startsWith('₹') ? str : '₹$str';

    // If a small value like 1.5 was passed for bonus/stocks and caller requests suffix:
    if (numVal > 0 && numVal < 1000 && showLakhSuffixIfSmall) {
      final lakhStr = numVal % 1 == 0 ? numVal.toInt().toString() : numVal.toStringAsFixed(2);
      return '₹$lakhStr Lakhs';
    }

    // Convert LPA decimal to full rupees if value is < 1000 (e.g. 12.0 or 50.0)
    double rupees = numVal;
    if (numVal > 0 && numVal < 1000) {
      rupees = numVal * 100000;
    }

    try {
      final formatter = NumberFormat.currency(
        locale: 'en_IN',
        symbol: '₹',
        decimalDigits: rupees % 1 == 0 ? 0 : 2,
      );
      return formatter.format(rupees).trim();
    } catch (_) {
      final isInt = rupees % 1 == 0;
      final intPart = rupees.toInt().toString();
      String formattedInt = intPart;
      if (intPart.length > 3) {
        final last3 = intPart.substring(intPart.length - 3);
        String remaining = intPart.substring(0, intPart.length - 3);
        final chunks = <String>[];
        while (remaining.length > 2) {
          chunks.insert(0, remaining.substring(remaining.length - 2));
          remaining = remaining.substring(0, remaining.length - 2);
        }
        if (remaining.isNotEmpty) chunks.insert(0, remaining);
        formattedInt = '${chunks.join(',')},$last3';
      }
      final decPart = isInt ? '' : '.${(rupees - rupees.toInt()).toStringAsFixed(2).substring(2)}';
      return '₹$formattedInt$decPart';
    }
  }

  String _formatDate(dynamic dateStr) {
    if (dateStr == null || dateStr.toString().trim().isEmpty) return 'Not Specified';
    final s = dateStr.toString().trim();
    try {
      final dt = DateTime.parse(s);
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return s;
    }
  }

  Future<void> _handleAccept() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: AppColors.success, size: 24),
            SizedBox(width: 8),
            Text('Accept Placement Offer?'),
          ],
        ),
        content: Text(
          'Are you sure you want to accept the official placement offer from $_companyName for the position of "$_roleTitle"?\n\nYour acceptance will be notified to the recruitment team immediately.',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Review Later'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Confirm & Accept'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    final res = await _driveService.acceptOffer(_driveId);
    setState(() => _isLoading = false);

    if (res) {
      setState(() {
        _currentOutcome = 'accepted';
      });
      widget.onOfferActionCompleted?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎉 Congratulations! You have accepted the placement offer from $_companyName.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to record offer acceptance. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _handleDecline() async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 24),
            SizedBox(width: 8),
            Text('Decline Placement Offer'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to decline this offer from $_companyName? This action cannot be undone.',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                labelText: 'Reason for Declining (Optional)',
                hintText: 'e.g. Accepted another offer / Relocation constraints',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              maxLines: 2,
            ),
          ],
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Confirm Decline'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    final res = await _driveService.declineOffer(_driveId, reason: reasonController.text.trim());
    setState(() => _isLoading = false);

    if (res) {
      setState(() {
        _currentOutcome = 'declined';
      });
      widget.onOfferActionCompleted?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Offer from $_companyName has been declined.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to decline offer. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _openOfferSetup() async {
    final updated = await OfferSetupModal.show(
      context,
      driveId: _driveId,
      studentId: widget.studentId,
      candidateName: widget.candidateName,
      companyName: _companyName,
      roleTitle: _roleTitle,
      initialOfferData: _currentOffer,
    );

    if (updated == true) {
      // Re-fetch or reload
      setState(() {
        // Modal updated backend successfully
      });
      widget.onOfferActionCompleted?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Offer details updated successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    }
  }

  Future<void> _openOfferLetter(String url) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: isDark ? const Color(0xFF2A2415) : const Color(0xFFFFFBEB),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFFDE68A)),
          ),
          content: Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: Color(0xFFB45309), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Offer letter document is not yet available.',
                  style: TextStyle(
                    color: isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Unable to open offer letter link.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // 1. Determine offer compensation data & format in Indian numbering
    final rawCtc = _currentOffer['ctc_lpa'] ??
        widget.drive['ctc_max'] ??
        widget.drive['ctc_min'] ??
        '12.0';
    final double rawCtcNum = double.tryParse(rawCtc.toString().replaceAll('₹', '').replaceAll(',', '').trim()) ?? 12.0;

    // Determine rupees and LPA
    final double totalRupees = rawCtcNum < 1000 ? rawCtcNum * 100000 : rawCtcNum;
    final double lpaVal = totalRupees / 100000;
    final String lpaText = '${lpaVal % 1 == 0 ? lpaVal.toInt() : lpaVal.toStringAsFixed(1)} LPA';
    final String formattedCtc = _formatIndianCurrency(totalRupees);

    final rawBase = _currentOffer['base_fixed_salary'];
    final double baseRupees = rawBase != null
        ? (double.tryParse(rawBase.toString().replaceAll('₹', '').replaceAll(',', '').trim()) ?? (totalRupees * 0.75))
        : (totalRupees * 0.75);
    final double finalBaseRupees = baseRupees < 1000 ? baseRupees * 100000 : baseRupees;
    final String formattedBase = _formatIndianCurrency(finalBaseRupees);

    final rawBonus = _currentOffer['joining_bonus'] ?? '1.5';
    final String formattedBonus = _formatIndianCurrency(rawBonus, showLakhSuffixIfSmall: true);

    final rawStocks = _currentOffer['stocks_esops'] ?? '1.5';
    final String formattedStocks = _formatIndianCurrency(rawStocks, showLakhSuffixIfSmall: true);

    // Monthly take-home estimate
    final double monthlyEstimate = totalRupees / 12;
    final String formattedMonthly = '~${_formatIndianCurrency(monthlyEstimate)} / month';

    // Logistics
    final joiningDate = _currentOffer['joining_date'] ?? '';
    final deadlineDate = _currentOffer['offer_deadline'] ?? '';
    final location = _currentOffer['job_location'] ?? widget.drive['job_location'] ?? '';
    final workMode = _currentOffer['work_mode'] ?? widget.drive['work_mode'] ?? '';
    final probation = _currentOffer['probation_period'] ?? '';
    final bond = _currentOffer['bond_duration'] ?? '';
    final recruiterNote = (_currentOffer['recruiter_notes'] ?? '').toString();
    final offerDocUrl = (_currentOffer['offer_document_url'] ?? '').toString();

    final isAccepted = _currentOutcome == 'accepted';
    final isDeclined = _currentOutcome == 'declined';

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: AppBar(
        title: const Text('Placement Offer Details'),
        actions: [
          if (widget.isRecruiter)
            TextButton.icon(
              onPressed: _openOfferSetup,
              icon: const Icon(Icons.edit_note_rounded, size: 20),
              label: const Text('Configure'),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. HERO OFFER BANNER CARD (Two-line structure with zero overflow)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isAccepted
                            ? [const Color(0xFF15803D), const Color(0xFF22C55E)]
                            : isDeclined
                                ? [const Color(0xFF991B1B), const Color(0xFFEF4444)]
                                : [
                                    isDark ? const Color(0xFF312E81) : const Color(0xFF4F46E5),
                                    isDark ? const Color(0xFF4338CA) : const Color(0xFF6366F1),
                                  ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: (isAccepted ? AppColors.success : (isDeclined ? AppColors.error : AppColors.lightPrimary)).withValues(alpha: 0.3),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Line 1: Status badge pill on the left
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isAccepted
                                    ? Icons.check_circle_rounded
                                    : isDeclined
                                        ? Icons.cancel_rounded
                                        : Icons.stars_rounded,
                                color: Colors.white,
                                size: 15,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isAccepted
                                    ? 'OFFER ACCEPTED'
                                    : isDeclined
                                        ? 'OFFER DECLINED'
                                        : 'OFFICIAL OFFER EXTENDED',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Line 2: Deadline label + date (wrapped with Flexible/Expanded, never overflows)
                        if (deadlineDate.toString().isNotEmpty) ...[
                          Tooltip(
                            message: 'Acceptance Deadline: ${_formatDate(deadlineDate)}',
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    behavior: SnackBarBehavior.floating,
                                    content: Text('Offer Acceptance Deadline: ${_formatDate(deadlineDate)}'),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.schedule_rounded,
                                      size: 14,
                                      color: Colors.white.withValues(alpha: 0.85),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'Deadline: ${_formatDate(deadlineDate)}',
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.95),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                        ] else
                          const SizedBox(height: 12),

                        // Below both: Company Logo, Company Name, and Role Title stacked
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.1),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.business_rounded,
                                color: AppColors.lightPrimary,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _companyName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: -0.3,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    _roleTitle,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.9),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // 2. COMPENSATION & SALARY BREAKDOWN
                  _buildSectionHeader('Compensation Structure', Icons.account_balance_wallet_rounded),
                  const SizedBox(height: 10),
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
                          // Highlight Total CTC
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.darkSurfaceContainerHigh : AppColors.lightSurfaceContainer,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: AppColors.success.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Total Offered CTC',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.lightTextSecondary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        lpaText.isNotEmpty ? 'Annual Gross ($lpaText)' : 'Annual Gross Package',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: AppColors.lightTextSecondary,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerRight,
                                    child: Text(
                                      formattedCtc,
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.success,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Breakdown rows
                          _buildSalaryRow(
                            'Fixed Base Salary',
                            formattedBase,
                            Icons.attach_money_rounded,
                            isDark,
                          ),
                          const Divider(height: 18),
                          _buildSalaryRow(
                            'Joining / Performance Bonus',
                            formattedBonus,
                            Icons.card_giftcard_rounded,
                            isDark,
                          ),
                          const Divider(height: 18),
                          _buildSalaryRow(
                            'Stocks / Equity / ESOPs',
                            formattedStocks,
                            Icons.show_chart_rounded,
                            isDark,
                          ),
                          const Divider(height: 18),
                          _buildSalaryRow(
                            'Est. Monthly In-Hand (approx.)',
                            formattedMonthly,
                            Icons.payments_outlined,
                            isDark,
                            highlight: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // 3. PLACEMENT & LOGISTICS DETAILS
                  _buildSectionHeader('Role & Joining Logistics', Icons.work_outline_rounded),
                  const SizedBox(height: 10),
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
                          _buildInfoRow(
                            Icons.calendar_today_rounded,
                            'Expected Date of Joining',
                            _formatDate(joiningDate),
                            isDark,
                          ),
                          const Divider(height: 18),
                          _buildInfoRow(
                            Icons.event_busy_rounded,
                            'Offer Acceptance Deadline',
                            _formatDate(deadlineDate),
                            isDark,
                          ),
                          const Divider(height: 18),
                          _buildInfoRow(
                            Icons.location_on_rounded,
                            'Job Location',
                            location.toString(),
                            isDark,
                          ),
                          const Divider(height: 18),
                          _buildInfoRow(
                            Icons.home_work_rounded,
                            'Work Mode',
                            workMode.toString(),
                            isDark,
                          ),
                          const Divider(height: 18),
                          _buildInfoRow(
                            Icons.timelapse_rounded,
                            'Probation Period',
                            probation.toString(),
                            isDark,
                          ),
                          const Divider(height: 18),
                          _buildInfoRow(
                            Icons.assignment_turned_in_rounded,
                            'Service Agreement / Bond',
                            bond.toString(),
                            isDark,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // 4. RECRUITER WELCOME NOTE (If provided)
                  if (recruiterNote.isNotEmpty) ...[
                    _buildSectionHeader('Note from Recruiter', Icons.mail_outline_rounded),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkSurfaceContainerLow : AppColors.lightSurfaceContainerLow,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.format_quote_rounded,
                            color: AppColors.lightPrimary,
                            size: 28,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              recruiterNote,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.4,
                                fontStyle: FontStyle.italic,
                                color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],

                  // 5. OFFICIAL OFFER LETTER DOCUMENT
                  _buildSectionHeader('Official Documentation', Icons.description_rounded),
                  const SizedBox(height: 10),
                  if (offerDocUrl.isNotEmpty)
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
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.error.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.picture_as_pdf_rounded,
                                color: AppColors.error,
                                size: 26,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Official_Placement_Offer_${_companyName.replaceAll(' ', '_')}.pdf',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'Verified by Campus Placement Cell',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.lightTextSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: () => _openOfferLetter(offerDocUrl),
                              icon: const Icon(Icons.download_rounded, size: 16),
                              label: const Text('View'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isDark ? AppColors.darkPrimaryContainer : AppColors.lightPrimary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    // Material 3 Informational Banner (soft neutral amber, not solid black alert)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2A2415) : const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark ? const Color(0xFF4A3E20) : const Color(0xFFFDE68A),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, color: Color(0xFFB45309), size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Official offer letter PDF document is being prepared by HR and will be uploaded shortly.',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E),
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),

                  // 6. ACTION CONTROLS / STATUS STATE
                  if (widget.isRecruiter) ...[
                    // Recruiter setup access button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _openOfferSetup,
                        icon: const Icon(Icons.tune_rounded),
                        label: const Text(
                          'Edit & Configure Offer Package',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.lightPrimary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ] else if (isAccepted) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.successLightBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.success.withValues(alpha: 0.5)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.check_circle_rounded, color: AppColors.success, size: 28),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'You have officially accepted this placement offer. Your recruiter will contact you for onboarding formalities.',
                              style: TextStyle(
                                color: AppColors.success,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (isDeclined) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.error.withValues(alpha: 0.5)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.cancel_rounded, color: AppColors.error, size: 28),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'You have declined this placement offer.',
                              style: TextStyle(
                                color: AppColors.error,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    // Student action buttons: Accept or Decline
                    Row(
                      children: [
                        Expanded(
                          flex: 1,
                          child: OutlinedButton(
                            onPressed: _handleDecline,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.error,
                              side: const BorderSide(color: AppColors.error, width: 1.5),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text(
                              'Decline',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: _handleAccept,
                            icon: const Icon(Icons.check_circle_rounded, size: 20),
                            label: const Text(
                              'Accept Offer',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.success,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.lightPrimary),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  Widget _buildSalaryRow(String label, String value, IconData icon, bool isDark, {bool highlight = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          icon,
          size: 16,
          color: highlight ? AppColors.lightPrimary : AppColors.lightTextSecondary,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: highlight
                  ? (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary)
                  : AppColors.lightTextSecondary,
              fontWeight: highlight ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: highlight
                    ? AppColors.lightPrimary
                    : (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 16, color: AppColors.lightPrimary),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 4,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.lightTextSecondary,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 5,
          child: Text(
            value.isNotEmpty ? value : 'Not specified',
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
