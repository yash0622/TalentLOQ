import 'package:flutter/foundation.dart';

/// Broadcasts successful applications to screens that may already be mounted.
/// The server remains the source of truth; this only removes stale UI/cache
/// windows after the apply response has been received.
class ApplicationVisibilityState extends ChangeNotifier {
  ApplicationVisibilityState._();
  static final instance = ApplicationVisibilityState._();

  final Map<String, Map<String, dynamic>> _applications = {};
  final Set<String> _appliedCompanyNames = {};

  bool isApplied(String? id, [String? companyName]) {
    if (id != null && id.isNotEmpty && _applications.containsKey(id)) {
      return true;
    }
    if (companyName != null && companyName.isNotEmpty && _appliedCompanyNames.contains(companyName.trim().toLowerCase())) {
      return true;
    }
    return false;
  }

  void recordApplication(Map<String, dynamic> application) {
    final driveId = (application['drive_id'] ?? application['listing_id'])?.toString();
    final companyName = (application['company_name'] ?? application['company'])?.toString().trim().toLowerCase();
    if (companyName != null && companyName.isNotEmpty) {
      _appliedCompanyNames.add(companyName);
    }
    if (driveId == null || driveId.isEmpty) return;
    _applications[driveId] = Map<String, dynamic>.from(application);
    notifyListeners();
  }

  void recordMultipleApplications(List<dynamic> items) {
    bool changed = false;
    for (var item in items) {
      if (item is Map) {
        final drive = item['drive'] is Map ? item['drive'] as Map : item;
        final driveId = (drive['drive_id'] ?? drive['listing_id'] ?? item['drive_id'])?.toString();
        final companyName = (drive['company_name'] ?? drive['company'] ?? item['company_name'])?.toString().trim().toLowerCase();
        if (companyName != null && companyName.isNotEmpty && !_appliedCompanyNames.contains(companyName)) {
          _appliedCompanyNames.add(companyName);
          changed = true;
        }
        if (driveId != null && driveId.isNotEmpty && !_applications.containsKey(driveId)) {
          _applications[driveId] = Map<String, dynamic>.from(item);
          changed = true;
        }
      }
    }
    if (changed) {
      notifyListeners();
    }
  }
}
