import 'package:flutter/material.dart';
import '../../services/drive_service.dart';
import '../../theme/app_colors.dart';

class OfferSetupModal extends StatefulWidget {
  final String driveId;
  final String studentId;
  final String candidateName;
  final String companyName;
  final String roleTitle;
  final Map<String, dynamic>? initialOfferData;

  const OfferSetupModal({
    super.key,
    required this.driveId,
    required this.studentId,
    required this.candidateName,
    required this.companyName,
    required this.roleTitle,
    this.initialOfferData,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String driveId,
    required String studentId,
    required String candidateName,
    required String companyName,
    required String roleTitle,
    Map<String, dynamic>? initialOfferData,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => OfferSetupModal(
        driveId: driveId,
        studentId: studentId,
        candidateName: candidateName,
        companyName: companyName,
        roleTitle: roleTitle,
        initialOfferData: initialOfferData,
      ),
    );
  }

  @override
  State<OfferSetupModal> createState() => _OfferSetupModalState();
}

class _OfferSetupModalState extends State<OfferSetupModal> {
  final _formKey = GlobalKey<FormState>();
  final DriveService _driveService = DriveService();

  late final TextEditingController _ctcController;
  late final TextEditingController _baseSalaryController;
  late final TextEditingController _bonusController;
  late final TextEditingController _stocksController;
  late final TextEditingController _roleController;
  late final TextEditingController _locationController;
  late final TextEditingController _notesController;
  late final TextEditingController _offerLetterUrlController;

  String _workMode = 'Hybrid (3 days in office)';
  String _probationPeriod = '3 Months';
  String _bondTerms = 'No bond / Service agreement';
  DateTime _joiningDate = DateTime.now().add(const Duration(days: 90));
  DateTime _deadlineDate = DateTime.now().add(const Duration(days: 14));
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final init = widget.initialOfferData ?? {};
    _ctcController = TextEditingController(text: init['ctc']?.toString() ?? '');
    _baseSalaryController = TextEditingController(text: init['base_salary']?.toString() ?? '');
    _bonusController = TextEditingController(text: init['bonus']?.toString() ?? '');
    _stocksController = TextEditingController(text: init['stocks']?.toString() ?? '');
    _roleController = TextEditingController(text: init['role_title']?.toString() ?? widget.roleTitle);
    _locationController = TextEditingController(text: init['location']?.toString() ?? '');
    _notesController = TextEditingController(
      text: init['special_notes']?.toString() ??
          'Congratulations! We were highly impressed by your interview rounds and look forward to having you onboard our team.',
    );
    _offerLetterUrlController = TextEditingController(text: init['offer_letter_url']?.toString() ?? '');

    if (init['work_mode'] != null) _workMode = init['work_mode'].toString();
    if (init['probation_period'] != null) _probationPeriod = init['probation_period'].toString();
    if (init['bond_terms'] != null) _bondTerms = init['bond_terms'].toString();
  }

  @override
  void dispose() {
    _ctcController.dispose();
    _baseSalaryController.dispose();
    _bonusController.dispose();
    _stocksController.dispose();
    _roleController.dispose();
    _locationController.dispose();
    _notesController.dispose();
    _offerLetterUrlController.dispose();
    super.dispose();
  }

  Future<void> _pickJoiningDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _joiningDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked != null) {
      setState(() => _joiningDate = picked);
    }
  }

  Future<void> _pickDeadlineDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadlineDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (picked != null) {
      setState(() => _deadlineDate = picked);
    }
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final offerData = <String, dynamic>{
      'ctc': _ctcController.text.trim(),
      'base_salary': _baseSalaryController.text.trim(),
      'bonus': _bonusController.text.trim(),
      'stocks': _stocksController.text.trim(),
      'role_title': _roleController.text.trim(),
      'joining_date': '${_joiningDate.year}-${_joiningDate.month.toString().padLeft(2, '0')}-${_joiningDate.day.toString().padLeft(2, '0')}',
      'acceptance_deadline': '${_deadlineDate.year}-${_deadlineDate.month.toString().padLeft(2, '0')}-${_deadlineDate.day.toString().padLeft(2, '0')}',
      'location': _locationController.text.trim(),
      'work_mode': _workMode,
      'probation_period': _probationPeriod,
      'bond_terms': _bondTerms,
      'special_notes': _notesController.text.trim(),
      'offer_letter_url': _offerLetterUrlController.text.trim().isNotEmpty ? _offerLetterUrlController.text.trim() : null,
    };

    final ok = await _driveService.setupOffer(
      driveId: widget.driveId,
      studentId: widget.studentId,
      offerData: offerData,
    );

    setState(() => _isSaving = false);

    if (mounted) {
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎉 Placement Offer successfully issued to ${widget.candidateName}!'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save offer. Please check connection and try again.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF181726) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Header Grab Bar
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),

          // Title Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.successLightBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.workspace_premium_rounded, color: AppColors.success, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Configure Placement Offer',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'For ${widget.candidateName} • ${widget.companyName}',
                        style: const TextStyle(fontSize: 12, color: AppColors.lightTextSecondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 16),

          // Scrollable Form Body
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                children: [
                  // Role Title
                  _buildSectionHeader('1. Position & Designation'),
                  TextFormField(
                    controller: _roleController,
                    decoration: _inputDecoration('Job Role / Title', Icons.work_outline_rounded, isDark),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter role title' : null,
                  ),
                  const SizedBox(height: 16),

                  // Compensation Breakdown
                  _buildSectionHeader('2. Compensation Package (CTC)'),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _ctcController,
                          decoration: _inputDecoration('Total CTC (e.g. 20 LPA)', Icons.currency_rupee_rounded, isDark),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _baseSalaryController,
                          decoration: _inputDecoration('Base Fixed (e.g. 16 LPA)', Icons.payments_outlined, isDark),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _bonusController,
                          decoration: _inputDecoration('Bonus / Variable', Icons.card_giftcard_rounded, isDark),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _stocksController,
                          decoration: _inputDecoration('Stocks / RSUs', Icons.trending_up_rounded, isDark),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Key Dates
                  _buildSectionHeader('3. Offer Timeline & Dates'),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: _pickJoiningDate,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF222133) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Joining Date', style: TextStyle(fontSize: 11, color: AppColors.lightTextSecondary)),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    const Icon(Icons.event_rounded, size: 15, color: AppColors.lightPrimary),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        '${_joiningDate.day}/${_joiningDate.month}/${_joiningDate.year}',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InkWell(
                          onTap: _pickDeadlineDate,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF222133) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Acceptance Deadline', style: TextStyle(fontSize: 11, color: AppColors.lightTextSecondary)),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    const Icon(Icons.alarm_rounded, size: 15, color: AppColors.warning),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        '${_deadlineDate.day}/${_deadlineDate.month}/${_deadlineDate.year}',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                        overflow: TextOverflow.ellipsis,
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
                  const SizedBox(height: 16),

                  // Location & Work Mode
                  _buildSectionHeader('4. Work Location & Setup'),
                  TextFormField(
                    controller: _locationController,
                    decoration: _inputDecoration('Location (City, State)', Icons.location_on_outlined, isDark),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _workMode,
                    isExpanded: true,
                    decoration: _inputDecoration('Work Mode', Icons.laptop_mac_rounded, isDark),
                    items: const [
                      DropdownMenuItem(
                        value: 'On-site (Full Office)',
                        child: Text('On-site (Full Office)', overflow: TextOverflow.ellipsis),
                      ),
                      DropdownMenuItem(
                        value: 'Hybrid (3 days in office)',
                        child: Text('Hybrid (3 days in office)', overflow: TextOverflow.ellipsis),
                      ),
                      DropdownMenuItem(
                        value: 'Remote (Work From Anywhere)',
                        child: Text('Remote (Work From Anywhere)', overflow: TextOverflow.ellipsis),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _workMode = v);
                    },
                  ),
                  const SizedBox(height: 16),

                  // Probation & Bond
                  _buildSectionHeader('5. Terms & Policy'),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _probationPeriod,
                          isExpanded: true,
                          decoration: _inputDecoration('Probation', Icons.timer_outlined, isDark, dense: true),
                          items: const [
                            DropdownMenuItem(
                              value: 'None',
                              child: Text('None', overflow: TextOverflow.ellipsis),
                            ),
                            DropdownMenuItem(
                              value: '3 Months',
                              child: Text('3 Months', overflow: TextOverflow.ellipsis),
                            ),
                            DropdownMenuItem(
                              value: '6 Months',
                              child: Text('6 Months', overflow: TextOverflow.ellipsis),
                            ),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _probationPeriod = v);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _bondTerms,
                          isExpanded: true,
                          decoration: _inputDecoration('Bond', Icons.gavel_rounded, isDark, dense: true),
                          items: const [
                            DropdownMenuItem(
                              value: 'No bond / Service agreement',
                              child: Text('No Bond', overflow: TextOverflow.ellipsis),
                            ),
                            DropdownMenuItem(
                              value: '1 Year Service Bond',
                              child: Text('1 Year Bond', overflow: TextOverflow.ellipsis),
                            ),
                            DropdownMenuItem(
                              value: '2 Years Service Bond',
                              child: Text('2 Years Bond', overflow: TextOverflow.ellipsis),
                            ),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _bondTerms = v);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Notes to Candidate
                  _buildSectionHeader('6. Recruiter Message / Welcome Note'),
                  TextFormField(
                    controller: _notesController,
                    maxLines: 3,
                    decoration: _inputDecoration('Special instructions, welcome remarks, etc.', Icons.notes_rounded, isDark),
                  ),
                  const SizedBox(height: 16),

                  // Offer Letter Link (Optional)
                  _buildSectionHeader('7. Official Offer Letter PDF Link (Optional)'),
                  TextFormField(
                    controller: _offerLetterUrlController,
                    decoration: _inputDecoration('https://drive.google.com/... or cloud PDF URL', Icons.link_rounded, isDark),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),

          // Submit Action Footer
          Container(
            padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).viewInsets.bottom + 16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1F1E2E) : Colors.white,
              border: Border(top: BorderSide(color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant)),
            ),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _handleSubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded, size: 20),
                label: Text(
                  _isSaving ? 'Issuing Offer...' : 'Save & Issue Placement Offer',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.lightTextSecondary),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, IconData icon, bool isDark, {bool dense = false}) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, size: 17, color: AppColors.lightTextSecondary),
      prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      contentPadding: EdgeInsets.symmetric(horizontal: dense ? 8 : 12, vertical: 12),
      isDense: true,
      filled: true,
      fillColor: isDark ? const Color(0xFF222133) : const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.lightPrimary, width: 1.5),
      ),
    );
  }
}
