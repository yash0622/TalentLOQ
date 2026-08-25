import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../../services/drive_service.dart';
import '../../theme/app_colors.dart';

class CreateDriveForm extends StatefulWidget {
  final Map<String, dynamic>? initialDrive;
  final VoidCallback? onSuccess;

  const CreateDriveForm({
    super.key,
    this.initialDrive,
    this.onSuccess,
  });

  @override
  State<CreateDriveForm> createState() => _CreateDriveFormState();
}

class _CreateDriveFormState extends State<CreateDriveForm> {
  final _formKey = GlobalKey<FormState>();
  final DriveService _driveService = DriveService();

  int _currentStep = 0;
  bool _isSubmitting = false;

  // Step 1 Controllers
  late TextEditingController _companyNameController;
  late TextEditingController _driveTitleController;
  String _mode = 'on_campus';
  String _employmentType = 'full_time';
  late TextEditingController _locationController;
  late TextEditingController _schoolTagController;
  late TextEditingController _ctcMinController;
  late TextEditingController _ctcMaxController;
  late TextEditingController _stipendController;

  // Step 2 Controllers
  late TextEditingController _descriptionController;
  late TextEditingController _responsibilitiesController;
  late TextEditingController _requiredSkillsController;
  late TextEditingController _preferredSkillsController;
  late TextEditingController _qualificationsController;
  late TextEditingController _additionalReqsController;

  // Step 3 Controllers
  List<String> _selectedCourses = [];
  final TextEditingController _newCourseController = TextEditingController();
  late TextEditingController _minCgpaController;
  bool _reqAccess = false;
  bool _reqEligible = false;
  bool _reqJobInterest = false;
  bool _reqInternshipInterest = false;

  // Step 4 Selection Process Rounds
  List<Map<String, dynamic>> _selectionRounds = [];
  final TextEditingController _newRoundController = TextEditingController();

  // Step 5 Controllers
  DateTime? _selectedScheduleDateTime;
  DateTime? _selectedDeadlineDateTime;
  late TextEditingController _bondDetailsController;
  String? _pickedPdfPath;
  String? _pickedPdfName;
  bool _isPublished = true;

  final List<String> _stepTitles = [
    'Basic Info',
    'Role Details',
    'Eligibility',
    'Rounds',
    'Schedule & PDF',
  ];

  @override
  void initState() {
    super.initState();
    final d = widget.initialDrive;

    // Clean manual fill for new drive
    _companyNameController = TextEditingController(text: d?['company_name'] ?? '');
    _driveTitleController = TextEditingController(text: d?['drive_title'] ?? '');
    _mode = d?['mode'] ?? 'on_campus';
    _employmentType = d?['employment_type'] ?? 'full_time';
    _locationController = TextEditingController(text: d?['location'] ?? '');
    _schoolTagController = TextEditingController(text: d?['school_tag'] ?? '');
    _ctcMinController = TextEditingController(text: d?['ctc_min'] != null ? d!['ctc_min'].toString() : '');
    _ctcMaxController = TextEditingController(text: d?['ctc_max'] != null ? d!['ctc_max'].toString() : '');
    _stipendController = TextEditingController(text: d?['stipend'] != null ? d!['stipend'].toString() : '');

    _descriptionController = TextEditingController(text: d?['description'] ?? '');
    _responsibilitiesController = TextEditingController(text: (d?['key_responsibilities'] as List?)?.join(', ') ?? '');
    _requiredSkillsController = TextEditingController(text: (d?['required_skills'] as List?)?.join(', ') ?? '');
    _preferredSkillsController = TextEditingController(text: (d?['preferred_skills'] as List?)?.join(', ') ?? '');
    _qualificationsController = TextEditingController(text: d?['qualifications'] ?? '');
    _additionalReqsController = TextEditingController(text: d?['additional_requirements'] ?? '');

    if (d?['eligible_courses'] != null) {
      _selectedCourses = List<String>.from(d!['eligible_courses']);
    } else {
      _selectedCourses = [];
    }
    _minCgpaController = TextEditingController(text: d?['min_cgpa'] != null ? d!['min_cgpa'].toString() : '');

    if (d?['selection_process'] != null) {
      _selectionRounds = List<Map<String, dynamic>>.from(
        (d!['selection_process'] as List).map((r) => Map<String, dynamic>.from(r as Map)),
      );
    } else {
      _selectionRounds = [];
    }

    if (d?['placement_policy_flags'] != null) {
      final flags = Map<String, dynamic>.from(d!['placement_policy_flags'] as Map);
      _reqAccess = flags['requires_placement_access'] ?? false;
      _reqEligible = flags['requires_placement_eligible'] ?? false;
      _reqJobInterest = flags['requires_job_interest'] ?? false;
      _reqInternshipInterest = flags['requires_internship_interest'] ?? false;
    }

    _bondDetailsController = TextEditingController(text: d?['bond_details'] ?? '');
    _isPublished = (d?['status'] ?? 'published') == 'published';
    if (d?['attachment_pdf_url'] != null) {
      _pickedPdfName = (d!['attachment_pdf_url'] as String).split('/').last;
    }
  }

  @override
  void dispose() {
    _companyNameController.dispose();
    _driveTitleController.dispose();
    _locationController.dispose();
    _schoolTagController.dispose();
    _ctcMinController.dispose();
    _ctcMaxController.dispose();
    _stipendController.dispose();
    _descriptionController.dispose();
    _responsibilitiesController.dispose();
    _requiredSkillsController.dispose();
    _preferredSkillsController.dispose();
    _qualificationsController.dispose();
    _additionalReqsController.dispose();
    _minCgpaController.dispose();
    _newCourseController.dispose();
    _newRoundController.dispose();
    _bondDetailsController.dispose();
    super.dispose();
  }

  void _addCourse() {
    final text = _newCourseController.text.trim();
    if (text.isEmpty) return;
    if (!_selectedCourses.contains(text)) {
      setState(() {
        _selectedCourses.add(text);
        _newCourseController.clear();
      });
    }
  }

  void _removeCourse(String course) {
    setState(() {
      _selectedCourses.remove(course);
    });
  }

  Future<void> _pickPdf() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (result != null && result.files.single.path != null) {
        setState(() {
          _pickedPdfPath = result.files.single.path;
          _pickedPdfName = result.files.single.name;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('File picker error: $e')),
        );
      }
    }
  }

  Future<void> _pickScheduleDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedScheduleDateTime ?? now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null) return;

    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedScheduleDateTime ?? now),
    );
    if (time == null) return;

    setState(() {
      _selectedScheduleDateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _pickDeadlineDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDeadlineDateTime ?? now.add(const Duration(days: 5)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null) return;

    setState(() {
      _selectedDeadlineDateTime = DateTime(date.year, date.month, date.day, 23, 59);
    });
  }

  void _addRound() {
    final text = _newRoundController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _selectionRounds.add({
        'round_number': _selectionRounds.length + 1,
        'round_name': text,
      });
      _newRoundController.clear();
    });
  }

  void _removeRound(int index) {
    setState(() {
      _selectionRounds.removeAt(index);
      for (int i = 0; i < _selectionRounds.length; i++) {
        _selectionRounds[i]['round_number'] = i + 1;
      }
    });
  }

  Future<void> _submitDrive() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    final isEdit = widget.initialDrive != null;
    final driveId = widget.initialDrive?['drive_id'];

    final scheduleStr = _selectedScheduleDateTime != null
        ? DateFormat('MMM dd, yyyy • hh:mm a').format(_selectedScheduleDateTime!)
        : (widget.initialDrive?['schedule_datetime'] ?? 'To Be Scheduled');

    final deadlineStr = _selectedDeadlineDateTime != null
        ? DateFormat('MMM dd, yyyy').format(_selectedDeadlineDateTime!)
        : (widget.initialDrive?['registration_deadline'] ?? 'Open');

    final keyResps = _responsibilitiesController.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final reqSkills = _requiredSkillsController.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final prefSkills = _preferredSkillsController.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

    final policyFlagsMap = {
      'requires_placement_access': _reqAccess,
      'requires_placement_eligible': _reqEligible,
      'requires_job_interest': _reqJobInterest,
      'requires_internship_interest': _reqInternshipInterest,
    };

    bool success = false;

    if (isEdit && driveId != null) {
      success = await _driveService.editDrive(driveId, {
        'company_name': _companyNameController.text.trim(),
        'drive_title': _driveTitleController.text.trim(),
        'mode': _mode,
        'employment_type': _employmentType,
        'location': _locationController.text.trim(),
        'school_tag': _schoolTagController.text.trim(),
        'ctc_min': double.tryParse(_ctcMinController.text) ?? 0.0,
        'ctc_max': double.tryParse(_ctcMaxController.text) ?? 0.0,
        'stipend': double.tryParse(_stipendController.text),
        'description': _descriptionController.text.trim(),
        'key_responsibilities': keyResps,
        'required_skills': reqSkills,
        'preferred_skills': prefSkills,
        'qualifications': _qualificationsController.text.trim(),
        'additional_requirements': _additionalReqsController.text.trim(),
        'bond_details': _bondDetailsController.text.trim(),
        'eligible_courses': _selectedCourses,
        'min_cgpa': double.tryParse(_minCgpaController.text) ?? 0.0,
        'placement_policy_flags': policyFlagsMap,
        'selection_process': _selectionRounds,
        'schedule_datetime': scheduleStr,
        'registration_deadline': deadlineStr,
        'status': _isPublished ? 'published' : 'draft',
      });
    } else {
      final mapData = <String, dynamic>{
        'company_name': _companyNameController.text.trim(),
        'drive_title': _driveTitleController.text.trim(),
        'mode': _mode,
        'employment_type': _employmentType,
        'location': _locationController.text.trim(),
        'school_tag': _schoolTagController.text.trim(),
        'ctc_min': double.tryParse(_ctcMinController.text) ?? 0.0,
        'ctc_max': double.tryParse(_ctcMaxController.text) ?? 0.0,
        'stipend': double.tryParse(_stipendController.text),
        'description': _descriptionController.text.trim(),
        'qualifications': _qualificationsController.text.trim(),
        'additional_requirements': _additionalReqsController.text.trim(),
        'bond_details': _bondDetailsController.text.trim(),
        'eligibility_criteria_summary': 'Min CGPA ${_minCgpaController.text}',
        'min_cgpa': double.tryParse(_minCgpaController.text) ?? 0.0,
        'schedule_datetime': scheduleStr,
        'registration_deadline': deadlineStr,
        'status_field': _isPublished ? 'published' : 'draft',
        'eligible_courses_json': jsonEncode(_selectedCourses),
        'selection_process_json': jsonEncode(_selectionRounds),
        'policy_flags_json': jsonEncode(policyFlagsMap),
      };

      success = await _driveService.createDrive(mapData, _pickedPdfPath);
    }

    setState(() => _isSubmitting = false);

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEdit ? 'Drive updated successfully!' : 'Placement drive published successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
        widget.onSuccess?.call();
        Navigator.maybePop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save drive. Please check required fields.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Widget _buildStepHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(_stepTitles.length, (index) {
            final isActive = index == _currentStep;
            final isCompleted = index < _currentStep;

            return InkWell(
              onTap: () => setState(() => _currentStep = index),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppColors.lightPrimary
                      : isCompleted
                          ? AppColors.primaryLightBg
                          : (isDark ? AppColors.darkSurfaceContainerHigh : AppColors.lightSurfaceContainer),
                  borderRadius: BorderRadius.circular(20),
                  border: isActive ? Border.all(color: AppColors.lightPrimary, width: 1.5) : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 10,
                      backgroundColor: isActive
                          ? Colors.white
                          : isCompleted
                              ? AppColors.lightPrimary
                              : AppColors.lightTextSecondary.withValues(alpha: 0.3),
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isActive ? AppColors.lightPrimary : Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _stepTitles[index],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: (isActive || isCompleted) ? FontWeight.bold : FontWeight.normal,
                        color: isActive
                            ? Colors.white
                            : isCompleted
                                ? AppColors.lightPrimary
                                : AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return Column(
          children: [
            TextFormField(
              controller: _companyNameController,
              decoration: const InputDecoration(labelText: 'Company Name', prefixIcon: Icon(Icons.business_rounded)),
              validator: (val) => val == null || val.trim().isEmpty ? 'Enter company name' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _driveTitleController,
              decoration: const InputDecoration(labelText: 'Drive Title (e.g. Campus Drive 2026)', prefixIcon: Icon(Icons.campaign_rounded)),
              validator: (val) => val == null || val.trim().isEmpty ? 'Enter drive title' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _mode,
              decoration: const InputDecoration(labelText: 'Drive Mode', prefixIcon: Icon(Icons.meeting_room_rounded)),
              items: const [
                DropdownMenuItem(value: 'on_campus', child: Text('On Campus')),
                DropdownMenuItem(value: 'off_campus', child: Text('Off Campus')),
                DropdownMenuItem(value: 'virtual', child: Text('Virtual / Remote')),
              ],
              onChanged: (val) => setState(() => _mode = val ?? 'on_campus'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _employmentType,
              decoration: const InputDecoration(labelText: 'Employment Type', prefixIcon: Icon(Icons.work_history_rounded)),
              items: const [
                DropdownMenuItem(value: 'full_time', child: Text('Full-Time')),
                DropdownMenuItem(value: 'internship', child: Text('Internship Only')),
                DropdownMenuItem(value: 'internship_and_full_time', child: Text('Internship + Full-Time')),
              ],
              onChanged: (val) => setState(() => _employmentType = val ?? 'full_time'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _ctcMinController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Min CTC (LPA)', prefixIcon: Icon(Icons.attach_money_rounded)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _ctcMaxController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Max CTC (LPA)', prefixIcon: Icon(Icons.money_rounded)),
                  ),
                ),
              ],
            ),
          ],
        );
      case 1:
        return Column(
          children: [
            TextFormField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Drive Overview & Description'),
              validator: (val) => val == null || val.trim().isEmpty ? 'Enter description' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _responsibilitiesController,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Key Responsibilities (comma-separated)'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _requiredSkillsController,
              decoration: const InputDecoration(labelText: 'Required Skills (comma-separated)'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _qualificationsController,
              decoration: const InputDecoration(labelText: 'Educational Qualifications'),
            ),
          ],
        );
      case 2:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Eligible Programs / Courses:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 6),
            if (_selectedCourses.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text('No courses added yet. Type course names below (e.g. B.Tech CSE, BCA, MBA).', style: TextStyle(fontSize: 12, color: AppColors.lightTextSecondary)),
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _selectedCourses.map((course) {
                  return Chip(
                    label: Text(course, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    backgroundColor: AppColors.primaryLightBg,
                    deleteIcon: const Icon(Icons.cancel_rounded, size: 16, color: AppColors.lightPrimary),
                    onDeleted: () => _removeCourse(course),
                  );
                }).toList(),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newCourseController,
                    decoration: const InputDecoration(
                      hintText: 'Enter course name (e.g. B.Tech CSE)',
                      prefixIcon: Icon(Icons.school_rounded, size: 20),
                    ),
                    onSubmitted: (_) => _addCourse(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: const Icon(Icons.add_rounded),
                  onPressed: _addCourse,
                  tooltip: 'Add Course',
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _minCgpaController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Minimum CGPA Cutoff (0 - 10)', prefixIcon: Icon(Icons.grade_rounded)),
              validator: (val) => val == null || val.trim().isEmpty ? 'Enter minimum CGPA' : null,
            ),
            const SizedBox(height: 16),
            const Text('Policy Requirements Flags:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            SwitchListTile(
              title: const Text('Requires Active Placement Cell Access', style: TextStyle(fontSize: 12)),
              value: _reqAccess,
              onChanged: (val) => setState(() => _reqAccess = val),
            ),
            SwitchListTile(
              title: const Text('Requires Placement Academic Eligibility', style: TextStyle(fontSize: 12)),
              value: _reqEligible,
              onChanged: (val) => setState(() => _reqEligible = val),
            ),
            SwitchListTile(
              title: const Text('Requires Full-Time Job Interest Opt-in', style: TextStyle(fontSize: 12)),
              value: _reqJobInterest,
              onChanged: (val) => setState(() => _reqJobInterest = val),
            ),
            SwitchListTile(
              title: const Text('Requires Internship Interest Opt-in', style: TextStyle(fontSize: 12)),
              value: _reqInternshipInterest,
              onChanged: (val) => setState(() => _reqInternshipInterest = val),
            ),
          ],
        );
      case 3:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Configure Selection Process Rounds:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 10),
            if (_selectionRounds.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No rounds added yet. Add your selection process rounds below.', style: TextStyle(fontSize: 12, color: AppColors.lightTextSecondary)),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _selectionRounds.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    leading: CircleAvatar(
                      radius: 14,
                      child: Text('${index + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                    title: Text(_selectionRounds[index]['round_name'] ?? 'Round'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20),
                      onPressed: () => _removeRound(index),
                    ),
                  );
                },
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newRoundController,
                    decoration: const InputDecoration(hintText: 'Add round name (e.g. Technical Round)'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: const Icon(Icons.add_rounded),
                  onPressed: _addRound,
                ),
              ],
            ),
          ],
        );
      case 4:
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Column(
          children: [
            TextFormField(
              controller: _locationController,
              decoration: const InputDecoration(labelText: 'Drive Location / Platform', prefixIcon: Icon(Icons.location_on_rounded)),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _bondDetailsController,
              decoration: const InputDecoration(labelText: 'Bond Details (e.g. 24 Months)', prefixIcon: Icon(Icons.verified_rounded)),
            ),
            const SizedBox(height: 14),
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant)),
              leading: const Icon(Icons.calendar_month_rounded, color: AppColors.lightPrimary),
              title: const Text('Drive Start Date & Time', style: TextStyle(fontSize: 12)),
              subtitle: Text(
                _selectedScheduleDateTime != null
                    ? DateFormat('MMM dd, yyyy • hh:mm a').format(_selectedScheduleDateTime!)
                    : 'Tap to select drive date & time',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onTap: _pickScheduleDateTime,
            ),
            const SizedBox(height: 12),
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant)),
              leading: const Icon(Icons.event_busy_rounded, color: AppColors.warning),
              title: const Text('Registration Deadline', style: TextStyle(fontSize: 12)),
              subtitle: Text(
                _selectedDeadlineDateTime != null
                    ? DateFormat('MMM dd, yyyy').format(_selectedDeadlineDateTime!)
                    : 'Tap to select deadline',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onTap: _pickDeadlineDateTime,
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.picture_as_pdf_rounded, color: AppColors.error),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Brochure PDF Attachment', style: TextStyle(fontSize: 11, color: AppColors.lightTextSecondary)),
                        Text(_pickedPdfName ?? 'No PDF attached yet', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  OutlinedButton(onPressed: _pickPdf, child: const Text('Pick PDF')),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SwitchListTile(
              title: const Text('Publish Immediately', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(_isPublished ? 'Status: PUBLISHED' : 'Status: DRAFT'),
              value: _isPublished,
              activeThumbColor: AppColors.success,
              onChanged: (val) => setState(() => _isPublished = val),
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isEdit = widget.initialDrive != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Placement Drive' : 'Create Placement Drive'),
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            _buildStepHeader(isDark),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: _buildStepContent(),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                border: Border(
                  top: BorderSide(
                    color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                  ),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isSubmitting
                            ? null
                            : () {
                                if (_currentStep < 4) {
                                  setState(() => _currentStep += 1);
                                } else {
                                  _submitDrive();
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : Text(_currentStep == 4 ? (isEdit ? 'Update Drive' : 'Submit & Save Drive') : 'Next Step'),
                      ),
                    ),
                    if (_currentStep > 0) ...[
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: () {
                          if (_currentStep > 0) {
                            setState(() => _currentStep -= 1);
                          }
                        },
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(80, 48),
                        ),
                        child: const Text('Back'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
