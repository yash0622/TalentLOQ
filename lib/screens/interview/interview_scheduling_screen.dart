import 'package:flutter/material.dart';
import '../../mock_data/mock_data.dart';
import '../../models/models.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_avatar.dart';
import '../../services/interview_service.dart';

class InterviewSchedulingScreen extends StatefulWidget {
  final Candidate? candidate;
  final VoidCallback onBack;
  final VoidCallback onBookedSuccess;
  final bool showAppBar;

  const InterviewSchedulingScreen({
    super.key,
    this.candidate,
    required this.onBack,
    required this.onBookedSuccess,
    this.showAppBar = true,
  });

  @override
  State<InterviewSchedulingScreen> createState() => _InterviewSchedulingScreenState();
}

class _InterviewSchedulingScreenState extends State<InterviewSchedulingScreen> {
  int _selectedDateIndex = 0;
  int _selectedTimeIndex = 0;
  int _selectedTypeIndex = 0;

  final List<String> _dates = [
    'Thu, Jul 24',
    'Fri, Jul 25',
    'Mon, Jul 28',
    'Tue, Jul 29',
  ];

  final List<String> _times = [
    '10:00 AM - 10:45 AM',
    '11:30 AM - 12:15 PM',
    '02:00 PM - 02:45 PM',
    '04:00 PM - 04:45 PM',
  ];

  final List<String> _interviewTypes = [
    'Technical System Design',
    'Live Coding & Data Structures',
    'Behavioral & Culture Fit',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final targetCandidate = widget.candidate ?? (MockData.candidates.isNotEmpty ? MockData.candidates[0] : null);

    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: widget.onBack,
              ),
              title: const Text('Schedule Interview'),
            )
          : null,
      body: targetCandidate == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.person_search_rounded, size: 48, color: AppColors.lightTextSecondary),
                        const SizedBox(height: 12),
                        const Text(
                          'No Candidate Selected',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Please select a candidate from the Candidate Validation Dashboard to schedule an interview drive.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: AppColors.lightTextSecondary),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: widget.onBack,
                          icon: const Icon(Icons.arrow_back_rounded, size: 18),
                          label: const Text('Back to Dashboard'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Candidate Summary Card
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                AppAvatar(
                                  radius: 22,
                                  imageUrl: targetCandidate.avatarUrl,
                                  fallbackText: targetCandidate.name,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        targetCandidate.name,
                                        style: theme.textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                      Text(
                                        targetCandidate.roleTitle,
                                        style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),

                  // Select Date Section
                  Text(
                    '1. Select Date',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: List.generate(_dates.length, (index) {
                      final isSelected = _selectedDateIndex == index;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedDateIndex = index),
                          child: Container(
                            margin: EdgeInsets.only(right: index == _dates.length - 1 ? 0 : 6),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? (isDark ? AppColors.darkPrimaryContainer : AppColors.lightPrimary)
                                  : (isDark ? AppColors.darkSurfaceContainerLow : AppColors.lightSurfaceContainerLow),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.lightPrimary
                                    : (isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant),
                              ),
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Text(
                                  _dates[index],
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected
                                        ? Colors.white
                                        : (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 18),

                  // Select Time Slot Section
                  Text(
                    '2. Select Time Slot',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _times.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final isSelected = _selectedTimeIndex == index;
                      return InkWell(
                        onTap: () => setState(() => _selectedTimeIndex = index),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? (isDark ? AppColors.darkSurfaceContainerHigh : AppColors.lightSurfaceContainer)
                                : (isDark ? AppColors.darkSurfaceContainerLow : AppColors.lightSurface),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.lightPrimary
                                  : (isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant),
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                                color: isSelected ? AppColors.lightPrimary : theme.hintColor,
                                size: 18,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                _times[index],
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 18),

                  // Select Interview Type Section
                  Text(
                    '3. Interview Type',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Column(
                    children: List.generate(_interviewTypes.length, (index) {
                      final isSelected = _selectedTypeIndex == index;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: ChoiceChip(
                          label: Text(_interviewTypes[index]),
                          selected: isSelected,
                          onSelected: (_) => setState(() => _selectedTypeIndex = index),
                          selectedColor: isDark ? AppColors.darkPrimaryContainer : AppColors.lightPrimary,
                          labelStyle: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),

          // Confirm Action (Sleek Compact Footer)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
              child: ElevatedButton(
                onPressed: () async {
                  final targetName = targetCandidate.name;
                  final targetId = targetCandidate.id;

                  await InterviewService().scheduleInterview(
                    studentId: targetId,
                    candidateName: targetName,
                    date: _dates[_selectedDateIndex],
                    timeSlot: _times[_selectedTimeIndex],
                    interviewType: _interviewTypes[_selectedTypeIndex],
                  );

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Interview scheduled with $targetName on ${_dates[_selectedDateIndex]} at ${_times[_selectedTimeIndex]}!',
                        ),
                        backgroundColor: AppColors.success,
                      ),
                    );
                    widget.onBookedSuccess();
                  }
                },
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(42),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                child: const Text(
                  'Confirm & Send Calendar Invite',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
