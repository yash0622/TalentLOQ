import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class SalaryFilterBottomSheet extends StatefulWidget {
  final RangeValues currentRange;
  final String selectedType;
  final Function(RangeValues range, String type) onApply;

  const SalaryFilterBottomSheet({
    super.key,
    required this.currentRange,
    required this.selectedType,
    required this.onApply,
  });

  @override
  State<SalaryFilterBottomSheet> createState() => _SalaryFilterBottomSheetState();
}

class _SalaryFilterBottomSheetState extends State<SalaryFilterBottomSheet> {
  late RangeValues _range;
  late String _selectedType;

  @override
  void initState() {
    super.initState();
    _range = widget.currentRange;
    _selectedType = widget.selectedType;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
          // Sheet Header Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Filter Jobs & Salary',
                  style: theme.textTheme.headlineSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _range = const RangeValues(12, 30);
                    _selectedType = 'All';
                  });
                },
                child: const Text('Reset'),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Salary Range Slider
          Text(
            'Annual Salary Range (INR)',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '₹${_range.start.round()} LPA - ₹${_range.end.round()} LPA+ / year',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          RangeSlider(
            values: _range,
            min: 5,
            max: 50,
            divisions: 45,
            activeColor: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
            labels: RangeLabels(
              '₹${_range.start.round()}L',
              '₹${_range.end.round()}L',
            ),
            onChanged: (values) {
              setState(() => _range = values);
            },
          ),
          const SizedBox(height: 20),

          // Employment Type Filter Chips
          Text(
            'Job Type',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['All', 'Full-Time', 'Remote', 'Contract', 'Hybrid'].map((type) {
              final isSelected = _selectedType == type;
              return ChoiceChip(
                label: Text(type),
                selected: isSelected,
                selectedColor: isDark ? AppColors.darkPrimaryContainer : AppColors.lightPrimary,
                labelStyle: TextStyle(
                  color: isSelected
                      ? Colors.white
                      : (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
                  fontWeight: FontWeight.w600,
                ),
                onSelected: (selected) {
                  if (selected) {
                    setState(() => _selectedType = type);
                  }
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 28),

          // Apply Button
          ElevatedButton(
            onPressed: () {
              widget.onApply(_range, _selectedType);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('Apply Filters', style: TextStyle(fontSize: 16)),
          ),
          ],
        ),
      ),
    ),
  );
}
}
